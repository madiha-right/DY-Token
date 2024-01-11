// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {DataTypes} from "src/libraries/DataTypes.sol";
import {PercentageMath} from "src/libraries/PercentageMath.sol";
import {Token} from "./Token.sol";
import {MockStETH} from "../mocks/MockStETH.sol";

contract Core is Test {
    using PercentageMath for uint256;

    address immutable alice = makeAddr("alice");
    address immutable bob = makeAddr("bob");
    address immutable charlie = makeAddr("charlie");
    address immutable david = makeAddr("david");

    MockStETH public mockStETH;
    Token public dyToken;

    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error InvalidHatLength(uint256 recipientsLength, uint256 proportionsLength);
    error InvalidProportion(uint256 proportion);

    event Deposit(address indexed user, uint256 amount, address indexed receiver);
    event Withdraw(address indexed user, uint256 amount, address indexed receiver);
    event RecollectUnderlying(address indexed user, uint256 amount, DataTypes.Hat hat);
    event DelegateUnderlying(address indexed user, uint256 amount, DataTypes.Hat hat);
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

        uint256 leftAmount = amount;
        uint256 leftShares = shares;

        for (uint256 i = 0; i < recipients.length; i++) {
            DataTypes.Account memory recipient = dyToken.getAccountData(account.hat.recipients[i]);
            bool lastRecipient = i == recipients.length - 1;
            uint256 amountToDelegate = lastRecipient ? leftAmount : amount.mulTo(account.hat.proportions[i]);
            uint256 sharesToDelegate = lastRecipient ? leftShares : shares.mulTo(account.hat.proportions[i]);

            assertEq(recipient.delegatedAmount, amountToDelegate, "delegatedAmount");
            assertEq(recipient.delegatedShares, sharesToDelegate, "delegatedShares");
            assertEq(account.hat.recipients[i], recipients[i], "recipient");
            assertEq(account.hat.proportions[i], proportions[i], "proportion");

            leftAmount -= amountToDelegate;
            leftShares -= sharesToDelegate;
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
        emit DelegateUnderlying(sender, amount, DataTypes.Hat({recipients: recipients, proportions: proportions}));
        vm.expectEmit(true, true, false, true);
        emit Deposit(sender, amount, receiver);

        dyToken.deposit(amount, receiver, recipients, proportions);

        vm.stopPrank();
    }

    function _withdraw(uint256 amount, address receiver, address sender) internal {
        DataTypes.Account memory account = dyToken.getAccountData(sender);

        vm.startPrank(sender);

        vm.expectEmit();
        emit RecollectUnderlying(sender, amount, account.hat);
        vm.expectEmit(true, true, false, true);
        emit Withdraw(sender, amount, receiver);

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
