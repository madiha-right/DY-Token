// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IDistributableYieldToken} from "./IDistributableYieldToken.sol";
import {IEmbankment} from "./IEmbankment.sol";

interface IDam {
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

    /* ============ Events ============ */

    /**
     * @dev Emitted when the DAM is put into operation.
     */
    event OperateDam();

    /**
     * @dev Emitted when the DAM is decommissioned.
     */
    event DecommissionDam();

    /**
     * @dev Emitted at the start of each round.
     * @param id The unique identifier of the round.
     * @param startTime The start time of the round.
     * @param endTime The end time of the round.
     */
    event StartRound(uint16 id, uint256 startTime, uint256 endTime);

    /**
     * @dev Emitted at the end of each round.
     * @param id The unique identifier of the round.
     * @param data Data associated with the round's conclusion.
     */
    event EndRound(uint16 indexed id, bytes data);

    /**
     * @dev Emitted upon depositing funds into the DAM.
     * @param sender The address that initiated the deposit.
     * @param amount The amount of funds deposited.
     */
    event Deposit(address indexed sender, uint256 amount);

    /**
     * @dev Emitted when funds are withdrawn from the DAM.
     * @param receiver The address receiving the withdrawn funds.
     * @param amount The amount of funds withdrawn.
     */
    event Withdraw(address indexed receiver, uint256 amount);

    /**
     * @dev Emitted when a withdrawal is scheduled.
     * @param receiver The address scheduled to receive the withdrawal.
     * @param amount The amount to be withdrawn.
     */
    event ScheduleWithdrawal(address indexed receiver, uint256 amount);

    /**
     * @dev Emitted when upstream parameters are set or updated.
     * @param period The duration of each round in seconds.
     * @param reinvestmentRatio The percentage of yield reinvested into the treasury.
     * @param autoStreamRatio The percentage of yield allocated to automatic grant distribution.
     */
    event SetUpstream(uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio);

    /**
     * @dev Emitted when the oracle address is changed.
     * @param oldOracle The previous oracle address.
     * @param newOracle The new oracle address.
     */
    event SetOracle(address indexed oldOracle, address indexed newOracle);

    /* ============ External Functions ============ */

    /**
     * @dev Starts the DAM operation with specified parameters.
     * @param amount The amount of funds that will be the source of yield.
     * @param period The duration of each round in seconds.
     * @param reinvestmentRatio The percentage of yield reinvested back into the treasury.
     * @param autoStreamRatio The percentage of yield allocated to automatic grant distribution.
     */
    function operateDam(uint256 amount, uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio) external;

    /**
     * @dev Decommissions the DAM and schedules a withdrawal to the specified receiver.
     * 			All remaining funds in the DAM will be sent to the receiver.
     * @param receiver The address to receive the remaining funds in the DAM.
     */
    function decommissionDam(address receiver) external;

    /**
     * @dev Ends the current round, verifies data integrity, and processes withdrawals if any.
     * @param data Data required to finalize the round.
     * 				It includes the following:
     * 				- List of addresses to receive grants
     * 				- List of grant proportions
     * @param v Part of the signature (v value).
     * @param r Part of the signature (r value).
     * @param s Part of the signature (s value).
     */
    function endRound(bytes calldata data, uint8 v, bytes32 r, bytes32 s) external;

    /**
     * @dev Deposits the specified amount into the DAM, applying it to the ongoing round.
     * @param amount The amount of funds to deposit.
     */
    function deposit(uint256 amount) external;

    /**
     * @dev Schedules a withdrawal of the specified amount to the given receiver.
     * @param amount The amount of funds to withdraw.
     * @param receiver The address to receive the withdrawn funds.
     */
    function scheduleWithdrawal(uint256 amount, address receiver) external;

    /**
     * @dev Sets the parameters for upcoming rounds in the DAM.
     * @param period The duration of each round in seconds.
     * @param reinvestmentRatio The percentage of yield reinvested back into the treasury.
     * @param autoStreamRatio The percentage of yield allocated to automatic grant distribution.
     */
    function setUpstream(uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio) external;

    /**
     * @dev Updates the oracle address for data verification in endRound.
     * @param newOracle The new oracle address.
     */
    function setOracle(address newOracle) external;

    /* ============ External View Functions ============ */

    /**
     * @dev Returns the ybToken (Yield Bearing Token) used in the DAM.
     * @return The address of the ybToken contract.
     */
    function ybToken() external view returns (IERC20);

    /**
     * @dev Returns the dyToken (Distributable Yield Token) associated with the DAM.
     * @return The address of the dyToken contract.
     */
    function dyToken() external view returns (IDistributableYieldToken);

    /**
     * @dev Returns the Embankment contract address involved in yield distribution.
     * @return The address of the Embankment contract.
     */
    function embankment() external view returns (IEmbankment);

    /**
     * @dev Provides the current configuration of the DAM's upstream.
     * @return period The duration of each round.
     * @return reinvestmentRatio The percentage of yield reinvested into the treasury.
     * @return autoStreamRatio The percentage of yield allocated for automatic distribution.
     * @return flowing Indicates whether the DAM is currently operational.
     */
    function upstream()
        external
        view
        returns (uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio, bool flowing);

    /**
     * @dev Returns the details of the current round in the DAM.
     * @return id The identifier of the current round.
     * @return startTime The start time of the round.
     * @return endTime The end time of the round.
     */
    function round() external view returns (uint16 id, uint256 startTime, uint256 endTime);

    /**
     * @dev Retrieves information about a scheduled withdrawal.
     * @param index The index of the withdrawal in the array.
     * @return amount The amount to be withdrawn.
     * @return receiver The address to receive the withdrawn funds.
     */
    function withdrawals(uint256 index) external view returns (uint256 amount, address receiver);

    /**
     * @dev Returns the address of the oracle responsible for data verification in the DAM.
     * @return The address of the current oracle.
     */
    function oracle() external view returns (address);
}
