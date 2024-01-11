// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PercentageMath} from "./libraries/PercentageMath.sol";
import {IDistributableYieldToken} from "./interfaces/IDistributableYieldToken.sol";
import {IEmbankment} from "./interfaces/IEmbankment.sol";

/**
 * @title Embankment
 * @dev Hold and manages the distribution of yield generated from principal of deposited tokens.
 *      This contract handles the allocation and transfer of yield incentives to various receivers,
 *      based on specified proportions. It interacts with yield-bearing and distributable yield tokens
 *      to manage and distribute yield effectively.
 */
contract Embankment is IEmbankment, Ownable {
    using SafeERC20 for IERC20;
    using PercentageMath for uint256;

    /* ============ Immutables ============ */

    IERC20 public immutable ybToken;
    IDistributableYieldToken public immutable dyToken;

    /* ============ Constructor ============ */

    constructor(IERC20 _ybToken, IDistributableYieldToken _dyToken) Ownable(_msgSender()) {
        ybToken = _ybToken;
        dyToken = _dyToken;
    }

    /* ============ External Functions ============ */

    /**
     * @dev Distributes the yield from the dyToken to designated receivers based on specified proportions.
     *      Claims interest from dyToken, calculates the total incentive, and disburses it.
     * 			The function ensures that the total of the distributed proportions equals 100%.
     * @param data Encoded data containing arrays of receivers' addresses and their corresponding proportions.
     */
    function dischargeYield(bytes calldata data) external {
        dyToken.claimInterest(address(this));

        uint256 totalIncentive = IERC20(dyToken).balanceOf(address(this));
        dyToken.withdraw(totalIncentive, address(this));

        (address[] memory receivers, uint16[] memory proportions) = abi.decode(data, (address[], uint16[]));

        uint256 len = receivers.length;
        uint256 leftAmount = totalIncentive;
        uint16 totalProportion;

        for (uint256 i = 0; i < len;) {
            address receiver = receivers[i];
            uint16 proportion = proportions[i];
            uint256 amount = i == len - 1 ? leftAmount : totalIncentive.mulTo(uint256(proportion));

            leftAmount -= amount;
            totalProportion += proportion;
            ybToken.safeTransfer(receiver, amount);

            emit DistributeIncentive(receiver, proportion, amount);

            unchecked {
                ++i;
            }
        }

        if (totalProportion != PercentageMath.PERCENTAGE_FACTOR) revert InvalidProportion(totalProportion);
    }
}
