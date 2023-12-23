// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {DataTypes} from "../libraries/DataTypes.sol";

interface IDistributableYieldToken is IERC20 {
    error InvalidHatLength(uint256 recipientsLength, uint256 proportionsLength);
    error InvalidProportion(uint256 proportion);

    event Deposit(address indexed user, uint256 amount, address indexed receiver, DataTypes.Hat hat);
    event Withdraw(address indexed user, uint256 amount, address indexed receiver, DataTypes.Hat hat);
    event RecollectLoans(address indexed user, uint256 amount, DataTypes.Hat hat);
    event DistributeLoans(address indexed user, uint256 amount, DataTypes.Hat hat);
    event ChangeHat(address indexed user, DataTypes.Hat oldHat, DataTypes.Hat newHat);
    event ClaimInterest(address indexed user, uint256 amount);

    function decimals() external view returns (uint8);

    function asset() external view returns (address);

    function totalAssets() external view returns (uint256);

    function getAccountData(address user) external view returns (DataTypes.Account memory);

    /**
     * @dev Deposits an `amount` of underlying asset into the vault, receiving in return overlying DY-Tokens.
     * - E.g. User deposits 100 mETH and gets in return 100 DY-mETH
     * @param amount The amount to be deposited
     * @param receiver The address that will receive the DY-Tokens, same as msg.sender if the user
     *   wants to receive them on his own wallet, or a different address if the beneficiary of DY-Tokens
     *   is a different wallet
     * @param recipients List of beneficial recipients
     * @param proportions Relative proportions of benefits received by the recipients
     */
    function deposit(uint256 amount, address receiver, address[] calldata recipients, uint16[] calldata proportions)
        external;

    /**
     * @dev Withdraws an `amount` of underlying asset from the vault, burning the equivalent DY-Tokens owned
     * E.g. User has 100 DY-mETH, calls withdraw() and receives 100 mETH, burning the 100 DY-mETH
     * @param amount The underlying amount to be withdrawn
     *   - Send the value type(uint256).max in order to withdraw the whole DY-Token balance
     * @param receiver Address that will receive the underlying, same as msg.sender if the user
     *   wants to receive it on his own wallet, or a different address if the beneficiary is a
     *   different wallet
     */
    function withdraw(uint256 amount, address receiver) external;

    /**
     * @dev Change the hat for `msg.sender`
     * @param recipients List of beneficial recipients
     * @param proportions Relative proportions of benefits received by the recipients
     */
    function changeHat(address[] calldata recipients, uint16[] calldata proportions) external;

    /**
     * @dev Claim interest for `user`
     * @param user The address of the account to claim interest for
     */
    function claimInterest(address user) external;

    /**
     * @dev Get interest payable for `user`
     * @param user The address of the account to get interest payable for
     */
    function getInterestPayable(address user) external view returns (uint256);
}