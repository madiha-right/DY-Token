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
 *      of fostering ecosystem development and project growth. It handles deposits, withdrawal,
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
    Withdrawal public withdrawal; // scheduled withdrawal

    address public oracle; // address of oracle which provides the result data for the round

    /* ============ Modifiers ============ */

    /// @dev only the owner and oracle can call this function
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

    /**
     * @dev Starts the DAM operation with specified parameters.
     * @param amount The amount of funds that will be the source of yield.
     * @param period The duration of each round in seconds.
     * @param reinvestmentRatio The percentage of yield reinvested back into the treasury.
     * @param autoStreamRatio The percentage of yield allocated to automatic grant distribution.
     */
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

    /**
     * @dev Decommissions the DAM and schedules a withdrawal to the specified receiver.
     * 			All remaining funds in the DAM will be sent to the receiver.
     * @param receiver The address to receive the remaining funds in the DAM.
     */
    function decommissionDam(address receiver) external onlyOwner {
        if (!upstream.flowing) revert DamNotOperating();
        _scheduleWithdrawal(type(uint256).max, receiver);
        upstream.flowing = false;

        emit DecommissionDam();
    }

    /**
     * @dev Ends the current round, verifies data integrity, and processes withdrawal if any.
     * @param data Data required to finalize the round.
     * 				It includes the following:
     * 				- List of addresses to receive grants
     * 				- List of grant proportions
     * @param v Part of the signature (v value).
     * @param r Part of the signature (r value).
     * @param s Part of the signature (s value).
     */
    function endRound(bytes calldata data, uint8 v, bytes32 r, bytes32 s) external onlyOwnerAndOracle {
        Round memory _round = round;

        if (block.timestamp < _round.endTime) revert RoundNotEnded();
        if (keccak256(data).toEthSignedMessageHash().recover(v, r, s) != oracle) revert InvalidSignature();

        embankment.dischargeYield(data);

        Withdrawal memory _withdrawal = withdrawal;

        if (_withdrawal.amount > 0) {
            _withdraw(_withdrawal.amount, _withdrawal.receiver);
            withdrawal = Withdrawal(0, address(0));
        }
        if (upstream.flowing) {
            _startRound();
        }

        emit EndRound(_round.id, data);
    }

    /**
     * @dev Deposits the specified amount into the DAM, applying it to the ongoing round.
     * @param amount The amount of funds to deposit.
     */
    function deposit(uint256 amount) external onlyOwner {
        _deposit(amount);
    }

    /**
     * @dev Schedules a withdrawal of the specified amount to the given receiver.
     * @param amount The amount of funds to withdraw.
     * @param receiver The address to receive the withdrawn funds.
     */
    function scheduleWithdrawal(uint256 amount, address receiver) external onlyOwner {
        if (!upstream.flowing) revert DamNotOperating();

        uint256 balance = IERC20(dyToken).balanceOf(address(this));

        if (amount > balance) revert InsufficientBalance();
        if (amount == balance) revert InvalidAmountRequest(); // to withdraw all, use decommissionDam()

        _scheduleWithdrawal(amount, receiver);
    }

    /**
     * @dev Sets the parameters for upcoming rounds in the DAM.
     * @param period The duration of each round in seconds.
     * @param reinvestmentRatio The percentage of yield reinvested back into the treasury.
     * @param autoStreamRatio The percentage of yield allocated to automatic grant distribution.
     */
    function setUpstream(uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio) external onlyOwner {
        _setUpsteram(period, reinvestmentRatio, autoStreamRatio);
    }

    /**
     * @dev Updates the oracle address for data verification in endRound.
     * @param newOracle The new oracle address.
     */
    function setOracle(address newOracle) external onlyOwnerAndOracle {
        if (newOracle == address(0)) revert InvalidAddress();
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

        uint256 length = _upstream.reinvestmentRatio == 0 ? 1 : 2;

        address[] memory recipients = new address[](length);
        uint16[] memory proportions = new uint16[](length);

        // If the reinvestmentRatio is 0, all the interest goes to embankment
        if (_upstream.reinvestmentRatio == 0) {
            recipients[0] = address(embankment);
            proportions[0] = PERCENTAGE_FACTOR;
        } else {
            recipients[0] = address(embankment);
            recipients[1] = address(this);
            proportions[0] = PERCENTAGE_FACTOR - _upstream.reinvestmentRatio;
            proportions[1] = _upstream.reinvestmentRatio;
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
        ybToken.forceApprove(address(dyToken), amount);
        dyToken.deposit(amount, address(this), new address[](0), new uint16[](0));

        emit Deposit(sender, amount);
    }

    /**
     * @dev Schedules a withdrawal from the DAM. The scheduled withdrawal will be processed when the round ends.
     * @param amount The amount of ybTokens to withdraw.
     * @param receiver The address to receive the ybTokens.
     */
    function _scheduleWithdrawal(uint256 amount, address receiver) internal {
        if (receiver == address(0)) revert InvalidReceiver();
        withdrawal = Withdrawal(amount, receiver);

        emit ScheduleWithdrawal(receiver, amount);
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
