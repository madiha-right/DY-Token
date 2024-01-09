// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {IDistributableYieldToken} from "../interfaces/IDistributableYieldToken.sol";
import {BaseDam} from "../BaseDam.sol";

contract Dam is BaseDam {
    constructor(IERC20 ybToken, IDistributableYieldToken dyToken, address embank) BaseDam(ybToken, dyToken, embank) {}
}
