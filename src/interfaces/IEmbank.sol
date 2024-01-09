// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IDistributableYieldToken} from "./IDistributableYieldToken.sol";

interface IEmbank {
    event DistributeIncentive(address indexed receiver, uint16 proportion, uint256 amount);

    error InvalidProportion(uint256 proportion);

    function dischargeYield(bytes calldata data) external;

    function ybToken() external view returns (IERC20);

    function dyToken() external view returns (IDistributableYieldToken);
}
