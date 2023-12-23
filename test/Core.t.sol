// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {DataTypes} from "src/libraries/DataTypes.sol";
import {PercentageMath} from "src/libraries/PercentageMath.sol";
import {DistributableERC20} from "src/DistributableERC20.sol";
import {DYToken} from "src/DYToken.sol";
import {MockStETH} from "./mocks/MockStETH.sol";

contract Token is DYToken {
    constructor(IERC20 _asset, string memory _name, string memory _symbol)
        DYToken(_asset)
        DistributableERC20(_name, _symbol)
    {}

    function convertToShares(uint256 amount) public view returns (uint256) {
        return _convertToShares(amount, Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }
}

contract Core is Test {
    using PercentageMath for uint256;
    // address constant METH = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa; // METH on mainnet

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address david = makeAddr("david");

    MockStETH public mockStETH;
    Token public dyToken;

    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error InvalidHatLength(uint256 recipientsLength, uint256 proportionsLength);
    error InvalidProportion(uint256 proportion);

    event Deposit(address indexed user, uint256 amount, address indexed receiver, DataTypes.Hat hat);
    event Withdraw(address indexed user, uint256 amount, address indexed receiver, DataTypes.Hat hat);
    event RecollectLoans(address indexed user, uint256 amount, DataTypes.Hat hat);
    event DistributeLoans(address indexed user, uint256 amount, DataTypes.Hat hat);
    event ChangeHat(address indexed user, DataTypes.Hat oldHat, DataTypes.Hat newHat);
    event ClaimInterest(address indexed user, uint256 amount);

    function setUp() public {
        mockStETH = new MockStETH();
        dyToken = new Token(IERC20(address(mockStETH)), "Distributable Yield mock stETH", "DY-mock-stETH");
    }

    function deposit(
        uint256 amount,
        address receiver,
        address[] memory recipients,
        uint16[] memory proportions,
        address sender
    ) public {
        uint256 shares = dyToken.convertToShares(amount);

        _deposit(amount, receiver, recipients, proportions, sender);

        DataTypes.Account memory account = dyToken.getAccountData(receiver);

        assertEq(account.amount, amount, "amount");
        assertEq(dyToken.balanceOf(receiver), amount, "balanceOf");

        uint256 debtToDistribute = amount;
        uint256 debtSharesToDistribute = shares;

        for (uint256 i = 0; i < recipients.length; i++) {
            DataTypes.Account memory recipient = dyToken.getAccountData(account.hat.recipients[i]);
            bool lastRecipient = i == recipients.length - 1;
            uint256 debtAmount = lastRecipient ? debtToDistribute : amount.mulTo(account.hat.proportions[i]);
            uint256 debtShares = lastRecipient ? debtSharesToDistribute : shares.mulTo(account.hat.proportions[i]);

            assertEq(recipient.debtAmount, debtAmount, "debtAmount");
            assertEq(recipient.debtShares, debtShares, "debtShares");
            assertEq(account.hat.recipients[i], recipients[i], "recipient");
            assertEq(account.hat.proportions[i], proportions[i], "proportion");

            debtToDistribute -= debtAmount;
            debtSharesToDistribute -= debtShares;
        }

        mockStETH.simulateAccrual(address(dyToken)); // generate interst

        assertEq(dyToken.balanceOf(receiver), amount, "balance should remain the same");

        uint256 interest;

        if (recipients.length == 0) {
            interest = dyToken.getInterestPayable(receiver);
        } else {
            for (uint256 i = 0; i < recipients.length; i++) {
                address recipient = account.hat.recipients[i];
                interest += dyToken.getInterestPayable(recipient != address(0) ? recipient : receiver);
            }
        }

        assertApproxEqAbs(interest, dyToken.totalAssets() - amount, recipients.length + 1, "interest");
    }

    function withdraw(uint256 amount, address receiver, address sender) public {
        DataTypes.Account memory account = dyToken.getAccountData(sender);
        uint256 len = account.hat.recipients.length;
        uint256[] memory balances = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            balances[i] = dyToken.getInterestPayable(account.hat.recipients[i]);
        }

        _withdraw(amount, receiver, sender);

        assertEq(mockStETH.balanceOf(receiver), amount, "receiver should acquire the withdrawn amount");

        for (uint256 i = 0; len < 1; i++) {
            address recipient = account.hat.recipients[i];
            assertEq(dyToken.getInterestPayable(recipient), 0, "interest should be payed to the recipients");
            assertEq(dyToken.balanceOf(recipient), balances[i], "recipient should acquire the interest");
        }
    }

    function changeHat(address user, DataTypes.Hat memory oldHat, DataTypes.Hat memory newHat) public {
        vm.startPrank(user);
        vm.expectEmit(true, false, false, true);
        emit ChangeHat(user, oldHat, newHat);
        dyToken.changeHat(newHat.recipients, newHat.proportions);
        vm.stopPrank();
        DataTypes.Account memory account = dyToken.getAccountData(user);

        if (oldHat.recipients.length > 0) {
            assertGt(account.interestPaid, 0, "interest should be paid");
        }

        for (uint256 i = 0; i < account.hat.recipients.length; i++) {
            assertEq(account.hat.recipients[i], newHat.recipients[i], "recipient 0 should be new recipient");
            assertEq(account.hat.proportions[i], newHat.proportions[i], "proportion 0 should be new proportion");
        }
    }

    function _deposit(
        uint256 amount,
        address receiver,
        address[] memory recipients,
        uint16[] memory proportions,
        address sender
    ) internal {
        mockStETH.mint(sender, amount);

        vm.startPrank(sender);

        mockStETH.approve(address(dyToken), amount);

        vm.expectEmit(true, false, false, true);
        emit DistributeLoans(sender, amount, DataTypes.Hat({recipients: recipients, proportions: proportions}));
        vm.expectEmit(true, true, false, true);
        emit Deposit(sender, amount, receiver, DataTypes.Hat({recipients: recipients, proportions: proportions}));

        dyToken.deposit(amount, receiver, recipients, proportions);

        vm.stopPrank();
    }

    function _withdraw(uint256 amount, address receiver, address sender) internal {
        DataTypes.Account memory account = dyToken.getAccountData(sender);

        vm.startPrank(sender);

        vm.expectEmit();
        emit RecollectLoans(sender, amount, account.hat);
        vm.expectEmit(true, true, false, true);
        emit Withdraw(sender, amount, receiver, account.hat);

        dyToken.withdraw(amount, receiver);

        vm.stopPrank();
    }

    function _getHat_empty() internal pure returns (DataTypes.Hat memory) {
        address[] memory recipients = new address[](0);
        uint16[] memory proportions = new uint16[](0);

        return DataTypes.Hat({recipients: recipients, proportions: proportions});
    }

    function _getHat_alice_100() internal view returns (DataTypes.Hat memory) {
        address[] memory recipients = new address[](1);
        uint16[] memory proportions = new uint16[](1);

        recipients[0] = alice;
        proportions[0] = 10000;

        return DataTypes.Hat({recipients: recipients, proportions: proportions});
    }

    function _getHat_bob_100() internal view returns (DataTypes.Hat memory) {
        address[] memory recipients = new address[](1);
        uint16[] memory proportions = new uint16[](1);

        recipients[0] = bob;
        proportions[0] = 10000;

        return DataTypes.Hat({recipients: recipients, proportions: proportions});
    }

    function _getHat_david_100() internal view returns (DataTypes.Hat memory) {
        address[] memory recipients = new address[](1);
        uint16[] memory proportions = new uint16[](1);

        recipients[0] = david;
        proportions[0] = 10000;

        return DataTypes.Hat({recipients: recipients, proportions: proportions});
    }

    function _getHat_bobNcharlie_7030() internal view returns (DataTypes.Hat memory) {
        address[] memory recipients = new address[](2);
        uint16[] memory proportions = new uint16[](2);

        recipients[0] = bob;
        recipients[1] = charlie;
        proportions[0] = 7000;
        proportions[1] = 3000;

        return DataTypes.Hat({recipients: recipients, proportions: proportions});
    }

    function _getHat_invalidLength() internal view returns (DataTypes.Hat memory) {
        address[] memory recipients = new address[](1);
        uint16[] memory proportions = new uint16[](2);

        recipients[0] = bob;
        proportions[0] = 7000;
        proportions[1] = 3000;

        return DataTypes.Hat({recipients: recipients, proportions: proportions});
    }

    function _getHat_invalidProportion() internal view returns (DataTypes.Hat memory) {
        address[] memory recipients = new address[](1);
        uint16[] memory proportions = new uint16[](1);

        recipients[0] = bob;
        proportions[0] = 12000;

        return DataTypes.Hat({recipients: recipients, proportions: proportions});
    }

    function _getHat_invalidProportionAcc() internal view returns (DataTypes.Hat memory) {
        address[] memory recipients = new address[](2);
        uint16[] memory proportions = new uint16[](2);

        recipients[0] = bob;
        recipients[1] = charlie;
        proportions[0] = 7000;
        proportions[1] = 8000;

        return DataTypes.Hat({recipients: recipients, proportions: proportions});
    }
}
