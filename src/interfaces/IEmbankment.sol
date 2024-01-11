// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IDistributableYieldToken} from "./IDistributableYieldToken.sol";

interface IEmbankment {
    /* ============ Errors ============ */

    error InvalidProportion(uint256 proportion);

    /* ============ Events ============ */

    /**
     * @dev Emitted when incentives are distributed to a receiver.
     * @param receiver The address receiving the incentive.
     * @param proportion The proportion of total incentives received, specified in basis points.
     * @param amount The actual amount of the incentive distributed.
     */
    event DistributeIncentive(address indexed receiver, uint16 proportion, uint256 amount);

    /* ============ External Functions ============ */

    /**
     * @dev Distributes the yield from the dyToken to designated receivers based on specified proportions.
     *      Claims interest from dyToken, calculates the total incentive, and disburses it.
     * 			The function ensures that the total of the distributed proportions equals 100%.
     * @param data Encoded data containing arrays of receivers' addresses and their corresponding proportions.
     */
    function dischargeYield(bytes calldata data) external;

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
}
