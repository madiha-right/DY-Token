// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {DYToken} from "src/DYToken.sol";
import {DistributableERC20} from "src/DistributableERC20.sol";

contract Token is DYToken {
    constructor(IERC20 _asset, string memory _name, string memory _symbol)
        DYToken(_asset)
        DistributableERC20(_name, _symbol)
    {}
}
