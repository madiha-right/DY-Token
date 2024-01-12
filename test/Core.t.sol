// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Embankment} from "src/Embankment.sol";
import {Dam} from "src/Dam.sol";
import {DataTypes} from "src/libraries/DataTypes.sol";
import {PercentageMath} from "src/libraries/PercentageMath.sol";
import {Token} from "./dyToken/Token.sol";
import {MockStETH} from "./mocks/MockStETH.sol";

contract Core is Test {
    using SafeERC20 for IERC20;
    using PercentageMath for uint256;
    using MessageHashUtils for bytes32;

    /* ============ Constants ============ */

    uint256 constant PERCENTAGE_FACTOR = 10000;
    uint256 constant PERIOD = 30 days;
    uint16 constant REINVESTMENT_RATIO = 500;
    uint16 constant AUTO_STREAM_RATIO = 9000;
    address constant ORACLE = address(0x1);

    /* ============ Immutables ============ */

    address immutable alice = makeAddr("alice");
    address immutable bob = makeAddr("bob");
    address immutable charlie = makeAddr("charlie");
    address immutable david = makeAddr("david");

    /* ============ State Variables ============ */

    MockStETH public ybToken;
    Token public dyToken;
    Embankment public embankment;
    Dam public dam;

    /* ============ Errors ============ */

    error InvalidPeriod();
    error InvalidRatio();
    error DamAlredyOperating();
    error DamNotOperating();
    error RoundNotEnded();
    error InsufficientBalance();
    error InvalidAmountRequest();
    error InvalidReceiver();
    error InvalidSignature();
    error InvalidProportion(uint256 proportion);
    error OwnableUnauthorizedAccount(address account);

    /* ============ Events ============ */

    event OperateDam();
    event DecommissionDam();
    event StartRound(uint16 id, uint256 startTime, uint256 endTime);
    event EndRound(uint16 indexed id, bytes data);
    event Deposit(address indexed sender, uint256 amount);
    event ScheduleWithdrawal(address indexed receiver, uint256 amount);
    event SetUpstream(uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio);
    event SetOracle(address indexed oldOracle, address indexed newOracle);

    event DistributeIncentive(address indexed receiver, uint16 proportion, uint256 amount);

    /* ============ setUp Function ============ */

    function setUp() public {
        ybToken = new MockStETH();
        dyToken = new Token(IERC20(address(ybToken)), "Distributable Yield mock stETH", "DY-mock-stETH");
        embankment = new Embankment(IERC20(address(ybToken)), dyToken);
        dam = new Dam(ybToken, dyToken, embankment);
    }

    /* ============ Internal Functions ============ */

    function _operateDam(
        uint256 amount,
        uint256 period,
        uint16 reinvestmentRatio,
        uint16 autoStreamRatio,
        uint16 roundId
    ) internal {
        ybToken.mint(address(this), amount);
        IERC20(ybToken).forceApprove(address(dam), amount);

        uint256 timestamp = block.timestamp;

        vm.expectEmit(false, false, false, false);
        emit OperateDam();
        dam.operateDam(amount, period, reinvestmentRatio, autoStreamRatio);

        // _setUpstream()
        (uint256 _period, uint16 _reinvestmentRatio, uint16 _autoStreamRatio, bool _flowing) = dam.upstream();
        assertEq(_period, period, "period should equal to _period");
        assertEq(_reinvestmentRatio, reinvestmentRatio, "reinvestmentRatio should equal to _reinvestmentRatio");
        assertEq(_autoStreamRatio, autoStreamRatio, "autoStreamRatio should equal to _autoStreamRatio");
        assertTrue(_flowing, "flowing should be true");

        // _deposit()
        assertEq(ybToken.balanceOf(address(this)), 0, "balance should be 0");
        assertEq(dyToken.balanceOf(address(dam)), amount, "Dam balance should equal to amount");

        // _startRound()
        (uint16 id, uint256 startTime, uint256 endTime) = dam.round();
        assertEq(id, roundId, "id should equal to roundId");
        assertEq(startTime, timestamp, "startTime should equal to timestamp");
        assertEq(endTime, timestamp + period, "endTime should equal to timestamp + period");

        DataTypes.Account memory account = dyToken.getAccountData(address(dam));

        if (account.hat.recipients.length > 1) {
            assertEq(account.hat.recipients[0], address(embankment), "first recipient should equal to embankment");
            assertEq(account.hat.recipients[1], address(dam), "second recipient should equal to dam");
            assertEq(
                account.hat.proportions[0],
                PERCENTAGE_FACTOR - reinvestmentRatio,
                "first proportion should equal to PERCENTAGE_FACTOR - reinvestmentRatio"
            );
            assertEq(
                account.hat.proportions[1], reinvestmentRatio, "second proportion should equal to reinvestmentRatio"
            );
        } else {
            assertEq(account.hat.recipients[0], address(embankment), "recipient should equal to embankment");
            assertEq(account.hat.proportions[0], 10000, "proportion should equal to 10000");
        }
    }

    function _endRound(bytes calldata data, uint16 roundId) internal {
        (address oracle, uint256 oraclePk) = makeAddrAndKey("oracle");
        bytes32 digest = keccak256(data).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePk, digest);

        dam.setOracle(oracle);

        vm.expectEmit(true, false, false, true);
        emit EndRound(roundId, data);

        dam.endRound(data, v, r, s);

        // embankment.dischargeYield()
        assertEq(IERC20(address(dyToken)).balanceOf(address(embankment)), 0, "Embankment should not have any dyToken");
        assertEq(IERC20(address(ybToken)).balanceOf(address(embankment)), 0, "Embankment should not have any ybToken");

        (address[] memory recipients, uint16[] memory proportions) = abi.decode(data, (address[], uint16[]));
        uint256 totalIncentive = IERC20(address(dyToken)).balanceOf(address(embankment));
        uint256 leftIncentive = totalIncentive;

        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 incentive =
                i == recipients.length - 1 ? leftIncentive : totalIncentive.mulTo(uint256(proportions[i]));
            assertEq(IERC20(address(ybToken)).balanceOf(recipients[i]), incentive, "Incorrect incentive");
            leftIncentive -= incentive;
        }

        // _processWithdrawl()

        // _startRound()
    }

    function _mintYbToken(uint256 amount, address receiver) internal {
        ybToken.mint(receiver, amount);
    }

    function _mintDyToken(uint256 amount, address receiver) internal {
        ybToken.mint(address(this), amount);
        ybToken.approve(address(dyToken), amount);
        dyToken.deposit(amount, receiver, new address[](4), new uint16[](4));
    }

    function _getData() internal view returns (bytes memory) {
        address[] memory recipients = new address[](4);
        uint16[] memory proportions = new uint16[](4);

        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = charlie;
        recipients[3] = david;

        proportions[0] = 1000;
        proportions[1] = 2000;
        proportions[2] = 3000;
        proportions[3] = 4000;

        return abi.encodePacked(recipients, proportions);
    }

    function _getDataInvalidProportion() internal view returns (bytes memory, uint16) {
        address[] memory recipients = new address[](4);
        uint16[] memory proportions = new uint16[](4);

        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = charlie;
        recipients[3] = david;

        proportions[0] = 1000;
        proportions[1] = 2000;
        proportions[2] = 3000;
        proportions[3] = 5000;

        return (abi.encodePacked(recipients, proportions), 11000);
    }
}
