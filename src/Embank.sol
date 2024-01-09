// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PercentageMath} from "./libraries/PercentageMath.sol";
import {IDistributableYieldToken} from "./interfaces/IDistributableYieldToken.sol";
import {IEmbank} from "./interfaces/IEmbank.sol";

contract Embank is IEmbank, Ownable {
    using SafeERC20 for IERC20;
    using PercentageMath for uint256;

    IERC20 public immutable ybToken;
    IDistributableYieldToken public immutable dyToken;

    constructor(IERC20 _ybToken, IDistributableYieldToken _dyToken) Ownable(_msgSender()) {
        ybToken = _ybToken;
        dyToken = _dyToken;
    }

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
