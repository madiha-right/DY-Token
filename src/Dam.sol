// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IDistributableYieldToken} from "./interfaces/IDistributableYieldToken.sol";
import {IEmbankment} from "./interfaces/IEmbankment.sol";
import {IDam} from "./interfaces/IDam.sol";

/**
 * @title Dam
 * @dev Implements a performance and growth-based program designed to reward projects within the ecosystem.
 *      This contract manages yield generation and distribution, aligning with the strategic goals
 *      of fostering ecosystem development and project growth. It handles deposits, withdrawals,
 *      and yield distribution, operating in defined rounds with specific configurations.
 */
contract Dam is IDam, Ownable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    /* ============ Structs ============ */

    struct Upstream {
        uint256 period; // period of the round
        /**
         * @dev ratio of the yield that goes to the treasury, expressed in BP(basis points).
         * 10000 - reinvestmentRatio = ratio of the yield that goes to the Embankment
         */
        uint16 reinvestmentRatio;
        /**
         * @dev ratio of the generated yield in Embankment that goes to the projects who registered for the auto stream, expressed in BP(basis points).
         * 10000 - autoStreamRatio = communityStreamRatio(voting)
         */
        uint16 autoStreamRatio;
        bool flowing; // if false, next round will not be started
    }

    struct Round {
        uint16 id;
        uint256 startTime;
        uint256 endTime;
    }

    struct Withdrawal {
        uint256 amount;
        address receiver;
    }

    /* ============ Constants ============ */

    uint16 constant PERCENTAGE_FACTOR = 1e4;

    /* ============ Immutables ============ */

    IERC20 public immutable ybToken;
    IDistributableYieldToken public immutable dyToken;
    IEmbankment public immutable embankment; // where the generated yield will be stored and distributed

    /* ============ State Variables ============ */

    Upstream public upstream; // configs
    Round public round;
    Withdrawal[] public withdrawals; // scheduled withdrawals

    address public oracle; // address of oracle which provides the result data for the round

    /* ============ Modifiers ============ */

    // only the owner and oracle can call this function
    modifier onlyOwnerAndOracle() {
        address sender = _msgSender();
        if (sender != owner() && sender != oracle) revert OwnableUnauthorizedAccount(sender);
        _;
    }

    /* ============ Constructor ============ */

    constructor(IERC20 ybToken_, IDistributableYieldToken dyToken_, IEmbankment embank_) Ownable(_msgSender()) {
        ybToken = ybToken_;
        dyToken = dyToken_;
        embankment = embank_;
    }

    /* ============ External Functions ============ */

    function operateDam(uint256 amount, uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio)
        external
        onlyOwner
    {
        if (upstream.flowing) revert DamAlredyOperating();
        upstream.flowing = true;

        _setUpsteram(period, reinvestmentRatio, autoStreamRatio);
        _deposit(amount);
        _startRound();

        emit OperateDam();
    }

    function decommissionDam(address receiver) external onlyOwner {
        if (!upstream.flowing) revert DamNotOperating();
        _scheduleWithdrawal(type(uint256).max, receiver);
        upstream.flowing = false;

        emit DecommissionDam();
    }

    function endRound(bytes calldata data, bytes32 r, bytes32 vs) external onlyOwnerAndOracle {
        if (keccak256(data).toEthSignedMessageHash().recover(r, vs) != oracle) revert InvalidSignature();
        if (block.timestamp < round.endTime) revert RoundNotEnded();

        embankment.dischargeYield(data);

        if (withdrawals.length > 0) {
            _processWithdrawls();
        }
        if (upstream.flowing) {
            _startRound();
        }

        emit EndRound(round.id, data);
    }

    // deposit will be applied directly to the ongoing round
    function deposit(uint256 amount) external onlyOwner {
        _deposit(amount);
    }

    // Withdrawl happens when the round ends
    function scheduleWithdrawal(uint256 amount, address receiver) external onlyOwner {
        if (!upstream.flowing) revert DamNotOperating();
        if (amount > IERC20(dyToken).balanceOf(address(this))) revert InsufficientBalance();
        _scheduleWithdrawal(amount, receiver);
    }

    // this upstream will be applied from the next round
    function setUpstream(uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio) external onlyOwner {
        _setUpsteram(period, reinvestmentRatio, autoStreamRatio);
    }

    function setOracle(address newOracle) external onlyOwnerAndOracle {
        address oldOracle = oracle;
        oracle = newOracle;
        emit SetOracle(oldOracle, newOracle);
    }

    /* ============ Internal Functions ============ */
    /**
     * @dev Starts a new round for yield generation and distribution.
     *      Sets up the round parameters and configures the dyToken hat for yield distribution.
     *      Can only be called when the previous round has ended and if the DAM is in an operating state.
     */
    function _startRound() internal {
        Round storage _round = round;
        Upstream memory _upstream = upstream;
        uint256 timestamp = block.timestamp;

        if (!_upstream.flowing) revert DamNotOperating();
        if (timestamp < round.endTime) revert RoundNotEnded();

        _round.id += 1;
        _round.startTime = timestamp;
        _round.endTime = timestamp + _upstream.period;

        uint16 proportion = _upstream.reinvestmentRatio;
        uint256 length = proportion == 0 ? 1 : 2;

        address[] memory recipients = new address[](length);
        uint16[] memory proportions = new uint16[](length);

        // If proportion is 0, all the interest goes to embankment
        if (proportion == 0) {
            recipients[0] = address(embankment);
            proportions[0] = PERCENTAGE_FACTOR;
        } else {
            recipients[0] = address(embankment);
            recipients[1] = address(this);
            proportions[0] = PERCENTAGE_FACTOR - proportion;
            proportions[1] = proportion;
        }

        dyToken.changeHat(recipients, proportions);

        emit StartRound(_round.id, timestamp, round.endTime);
    }

    /**
     * @dev Sets the upstream parameters for the DAM.
     * @param period The duration of each round in seconds.
     * @param reinvestmentRatio The percentage of yield reinvested to the treasury. Expressed in BP(basis points).
     * @param autoStreamRatio The percentage of yield allocated to automatic grant distribution. Expressed in BP(basis points).
     */
    function _setUpsteram(uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio) internal {
        if (period == 0) revert InvalidPeriod();
        if (reinvestmentRatio > PERCENTAGE_FACTOR || autoStreamRatio > PERCENTAGE_FACTOR) {
            revert InvalidRatio();
        }

        Upstream storage _upstream = upstream;
        _upstream.period = period;
        _upstream.reinvestmentRatio = reinvestmentRatio;
        _upstream.autoStreamRatio = autoStreamRatio;

        emit SetUpstream(period, reinvestmentRatio, autoStreamRatio);
    }

    /**
     * @dev Deposits ybTokens into the dyToken for yield generation. the generated interest will be distributed to the embankment and address(this)
     * @param amount The amount of ybTokens to deposit.
     */
    function _deposit(uint256 amount) internal {
        if (!upstream.flowing) revert DamNotOperating();

        address sender = _msgSender();
        ybToken.safeTransferFrom(sender, address(this), amount);
        dyToken.deposit(amount, address(this), new address[](0), new uint16[](0));

        emit Deposit(sender, amount);
    }

    /**
     * @dev Schedules a withdrawal from the DAM. The scheduled withdrawal will be processed when the round ends.
     * @param amount The amount of ybTokens to withdraw.
     * @param receiver The address to receive the ybTokens.
     */
    function _scheduleWithdrawal(uint256 amount, address receiver) internal {
        if (receiver == address(0)) revert InvalidAddress();
        withdrawals.push(Withdrawal(amount, receiver));

        emit ScheduleWithdrawal(receiver, amount);
    }

    /**
     * @dev Processes scheduled withdrawals.
     */
    function _processWithdrawls() internal {
        Withdrawal[] memory _withdrawals = withdrawals;
        uint256 len = _withdrawals.length;

        for (uint256 i = 0; i < len;) {
            _withdraw(withdrawals[i].amount, withdrawals[i].receiver);

            unchecked {
                ++i;
            }
        }

        delete withdrawals;
    }

    /**
     * @dev Withdraws ybTokens from dyToken and transfers to the specified receiver.
     * 			try-catch to prevent contract being stuck
     * @param amount The amount of ybTokens to withdraw. If set to max uint256, it withdraws the entire balance.
     * @param receiver The address to receive the withdrawn ybTokens.
     */
    function _withdraw(uint256 amount, address receiver) internal {
        // claim interest to send generated interest to the receiver
        if (amount == type(uint256).max) {
            try dyToken.claimInterest(address(this)) {} catch {}
            amount = IERC20(dyToken).balanceOf(address(this));
        }

        try dyToken.withdraw(amount, address(this)) {
            try ybToken.transfer(receiver, amount) {
                emit Withdraw(receiver, amount);
            } catch {}
        } catch {}
    }
}
