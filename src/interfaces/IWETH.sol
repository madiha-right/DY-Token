// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IWETH {
    /// @dev mint tokens for sender based on amount of mantle sent.
    function deposit() external payable;

    /// @dev withdraw mantle based on requested amount and user balance.
    function withdraw(uint256 _amount) external;
}
