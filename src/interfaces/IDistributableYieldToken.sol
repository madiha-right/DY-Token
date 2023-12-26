// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {DataTypes} from "../libraries/DataTypes.sol";

interface IDistributableYieldToken is IERC20 {
    error InvalidHatLength(uint256 recipientsLength, uint256 proportionsLength);
    error InvalidProportion(uint256 proportion);

    /**
     * @dev Emitted when a user deposits the underlying asset into the DY-Token.
     * @param user The address of the user who initiated the deposit.
     * @param amount The amount of the underlying yield-bearing token deposited.
     * @param receiver The address receiving the DY-Token that is minted.
     */
    event Deposit(address indexed user, uint256 amount, address indexed receiver);

    /**
     * @dev Emitted when a user withdraws the underlying asset from the vault.
     * @param user The address of the user who initiated the withdrawal.
     * @param amount The amount of the underlying yield-bearing token withdrawn.
     * @param receiver The address receiving the underlying yield-bearing token.
     */
    event Withdraw(address indexed user, uint256 amount, address indexed receiver);

    /**
     * @dev Emitted when delegated amount is recollected from a user's account to other accounts based on recipients.
     * @param user The address of the user from whose account is recollecting delegated amount.
     * @param amount The amount of underlying yield-bearing token recollected.
     * @param hat The hat of the user.
     */
    event RecollectUnderlying(address indexed user, uint256 amount, DataTypes.Hat hat);

    /**
     * @dev Emitted when amount is deleagated from a user's account to other accounts based on the hat recipients.
     * @param user The address of the user from whose account amount is delegated.
     * @param amount The amount of underlying yield-bearing token delegated.
     * @param hat The hat of the user.
     */
    event DelegateUnderlying(address indexed user, uint256 amount, DataTypes.Hat hat);

    /**
     * @dev Emitted when a user changes their hat.
     * @param user The address of the user who changed their hat.
     * @param oldHat The previous hat.
     * @param newHat The new hat.
     */
    event ChangeHat(address indexed user, DataTypes.Hat oldHat, DataTypes.Hat newHat);

    /**
     * @dev Emitted when interest is claimed on behalf of a user.
     * @param user The address of the user whose interest is claimed.
     * @param amount The amount of DY-Tokens generated as interest.
     */
    event ClaimInterest(address indexed user, uint256 amount);

    /**
     * @dev Decimals are computed by adding the decimal offset on top of the underlying asset's decimals. This
     * "original" value is cached during construction of the vault contract. If this read operation fails (e.g., the
     * asset has not been created yet), a default of 18 is used to represent the underlying asset's decimals.
     *
     * See {IERC20Metadata-decimals}.
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Returns the address of the underlying token used for the Vault for accounting, depositing, and withdrawing.
     *
     * - MUST be an ERC-20 token contract.
     * - MUST NOT revert.
     */
    function asset() external view returns (address);

    /**
     * @dev Returns the total amount of the underlying asset that is “managed” by Vault.
     *
     * - SHOULD include any compounding that occurs from yield.
     * - MUST be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT revert.
     */
    function totalAssets() external view returns (uint256);

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
     * @dev Get the account data for `user`.
     * @return The account data.
     */
    function getAccountData(address user) external view returns (DataTypes.Account memory);

    /**
     * @dev Get interest payable for `user`
     * @param user The address of the account to get interest payable for
     */
    function getInterestPayable(address user) external view returns (uint256);
}
