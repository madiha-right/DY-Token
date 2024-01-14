// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "./libraries/ERC20.sol";
import {DataTypes} from "./libraries/DataTypes.sol";
import {PercentageMath} from "./libraries/PercentageMath.sol";
import {DistributableERC20} from "./DistributableERC20.sol";
import {IDistributableYieldToken} from "./interfaces/IDistributableYieldToken.sol";

/**
 * @title DYToken (Distributable Yield Token)
 * @notice DY-Token, or Distributable Yield Token, is an _ERC20_ token that is 1:1 redeemable to its underlying yield-bearing token.
 *  			 The underlying yield-bearing token generates interest by itself, for example stETH(https://stake.lido.fi/).
 * 				 Owners of the DY-Tokens can use a definition called hat to configure who is the beneficiary of the accumulated interest.
 * 				 DY-Token can be used for community funds, charities, crowdfunding, etc.
 * @author Madiha, inspired by rToken
 */
abstract contract DYToken is DistributableERC20, IDistributableYieldToken {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using PercentageMath for uint256;

    /* ============ Immutables ============ */

    IERC20 private immutable _asset;
    uint8 private immutable _underlyingDecimals;

    /* ============ Constructor ============ */

    /**
     * @dev Set the underlying asset contract. This must be an ERC20-compatible contract (ERC-20 or ERC-777).
     */
    constructor(IERC20 asset_) {
        (bool success, uint8 assetDecimals) = _tryGetAssetDecimals(asset_);
        _underlyingDecimals = success ? assetDecimals : 18;
        _asset = asset_;
    }

    /**
     * @dev Attempts to fetch the asset decimals. A return value of false indicates that the attempt failed in some way.
     */
    function _tryGetAssetDecimals(IERC20 asset_) private view returns (bool, uint8) {
        (bool success, bytes memory encodedDecimals) =
            address(asset_).staticcall(abi.encodeCall(IERC20Metadata.decimals, ()));
        if (success && encodedDecimals.length >= 32) {
            uint256 returnedDecimals = abi.decode(encodedDecimals, (uint256));
            if (returnedDecimals <= type(uint8).max) {
                return (true, uint8(returnedDecimals));
            }
        }
        return (false, 0);
    }

    /* ============ External Functions ============ */

    /**
     * @dev Decimals are computed by adding the decimal offset on top of the underlying asset's decimals. This
     * "original" value is cached during construction of the vault contract. If this read operation fails (e.g., the
     * asset has not been created yet), a default of 18 is used to represent the underlying asset's decimals.
     *
     * See {IERC20Metadata-decimals}.
     */
    function decimals() public view virtual override(IDistributableYieldToken, ERC20) returns (uint8) {
        return _underlyingDecimals;
    }

    /**
     * @dev Returns the address of the underlying token used for the Vault for accounting, depositing, and withdrawing.
     *
     * - MUST be an ERC-20 token contract.
     * - MUST NOT revert.
     */
    function asset() public view virtual returns (address) {
        return address(_asset);
    }

    /**
     * @dev Returns the total amount of the underlying asset that is “managed” by Vault.
     *
     * - SHOULD include any compounding that occurs from yield.
     * - MUST be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT revert.
     */
    function totalAssets() public view virtual returns (uint256) {
        return _asset.balanceOf(address(this));
    }

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
        public
        virtual
    {
        address sender = _msgSender();

        if (amount == type(uint256).max) {
            amount = _asset.balanceOf(sender);
        }
        // changing hat can be omitted if the user passes empty recipients and proportions
        if (recipients.length != 0 && proportions.length != 0) {
            _changeHat(sender, recipients, proportions);
        }

        _delegateUnderlying(receiver, amount);
        _mint(receiver, amount);

        _asset.safeTransferFrom(sender, address(this), amount);

        emit Deposit(sender, amount, receiver);
    }

    /**
     * @dev Withdraws an `amount` of underlying asset from the vault, burning the equivalent DY-Tokens owned
     * E.g. User has 100 DY-mETH, calls withdraw() and receives 100 mETH, burning the 100 DY-mETH
     * @param amount The underlying amount to be withdrawn
     *   - Send the value type(uint256).max in order to withdraw the whole DY-Token balance
     * @param receiver Address that will receive the underlying, same as msg.sender if the user
     *   wants to receive it on his own wallet, or a different address if the beneficiary is a
     *   different wallet
     */
    function withdraw(uint256 amount, address receiver) public virtual {
        address sender = _msgSender();

        if (amount == type(uint256).max) {
            amount = IERC20(address(this)).balanceOf(sender);
        }

        _recollectUnderlying(sender, amount);
        _burn(sender, amount);

        _asset.safeTransfer(receiver, amount);

        emit Withdraw(sender, amount, receiver);
    }

    /**
     * @notice Change the hat for `msg.sender`
     * @param recipients List of beneficial recipients
     * @param proportions Relative proportions of benefits received by the recipients
     */
    function changeHat(address[] calldata recipients, uint16[] calldata proportions) external virtual {
        address sender = _msgSender();
        _changeHat(sender, recipients, proportions);
    }

    /**
     * @dev Claim interest for the user to get DY-Tokens
     * @param user User account address
     */
    function claimInterest(address user) external virtual {
        _claimInterest(user);
    }

    /**
     * @dev Get the account data for `user`.
     * @return The account data.
     */
    function getAccountData(address user) external view virtual returns (DataTypes.Account memory) {
        return _accounts[user];
    }

    /**
     * @dev Get interest payable of the account
     * @param user User account address
     */
    function getInterestPayable(address user) external view virtual returns (uint256) {
        return _calcInterestPayable(user);
    }

    /* ============ Internal Functions ============ */

    /**
     * @dev Recollect delegated amount of underlying yield-bearing token from the recipients
     * 			- If the account uses the zero hat, recollect delegated amount of underlying yield-bearing token from the owner
     * @param user User account address
     * @param amount Amount of underlying yield-bearing token to be collected from the recipients
     */
    function _recollectUnderlying(address user, uint256 amount) internal virtual {
        DataTypes.Account memory account = _accounts[user];
        uint256 recipientsLen = account.hat.recipients.length;

        if (amount > account.amount) revert ERC20InsufficientBalance(user, account.amount, amount);

        if (recipientsLen == 0 && account.hat.proportions.length == 0) {
            // Account uses the zero hat, recollect delegated amount from the user itself
            _claimInterest(user);
            _accounts[user].delegatedAmount -= amount;
            _accounts[user].delegatedShares -= _convertToShares(amount, Math.Rounding.Floor);
        } else {
            // recollect delegated amount from the recipients
            for (uint256 i = 0; i < recipientsLen;) {
                address recipient = account.hat.recipients[i];
                uint16 proportion = account.hat.proportions[i];
                uint256 amountToRecollect = amount.mulTo(uint256(proportion));

                _claimInterest(recipient);

                _accounts[recipient].delegatedAmount -= amountToRecollect;
                _accounts[recipient].delegatedShares -= _convertToShares(amountToRecollect, Math.Rounding.Floor);

                unchecked {
                    ++i;
                }
            }
        }

        emit RecollectUnderlying(user, amount, account.hat);
    }

    /**
     * @dev Delegate the incoming underlying tokens to the recipients
     * @param user User account address
     * @param amount DY-Token amount being delegated to the recipients
     */
    function _delegateUnderlying(address user, uint256 amount) internal virtual {
        DataTypes.Account memory account = _accounts[user];
        uint256 recipientsLen = account.hat.recipients.length;

        if (recipientsLen == 0 && account.hat.proportions.length == 0) {
            // Account uses the zero hat, delegate amount of underlying yield-bearing token to the user itself
            _accounts[user].delegatedAmount += amount;
            _accounts[user].delegatedShares += _convertToShares(amount, Math.Rounding.Floor);
        } else {
            uint16 totalProportion;
            // split amount of underlying yield-bearing token and delegate it to the recipients
            for (uint256 i = 0; i < recipientsLen;) {
                address recipient = account.hat.recipients[i];
                uint16 proportion = account.hat.proportions[i];

                if (proportion <= 0 || proportion > PercentageMath.PERCENTAGE_FACTOR) {
                    revert InvalidProportion(proportion);
                }

                uint256 amountToDelegate = amount.mulTo(uint256(proportion));
                _accounts[recipient].delegatedAmount += amountToDelegate;
                _accounts[recipient].delegatedShares += _convertToShares(amountToDelegate, Math.Rounding.Floor);
                totalProportion += proportion;

                unchecked {
                    ++i;
                }
            }

            if (totalProportion != PercentageMath.PERCENTAGE_FACTOR) {
                revert InvalidProportion(totalProportion);
            }
        }

        emit DelegateUnderlying(user, amount, account.hat);
    }

    /**
     * @notice Change the hat for user
     * @dev 1. Recollect delegated amount of yield-bearing token from the user account
     * 			2. Change the hat of the user account
     * 		  3. Delegate amount of yield-bearing token to the recipients of the user account
     * @param user User account address
     * @param recipients List of beneficial recipients
     * @param proportions Relative proportions of benefits received by the recipients
     */
    function _changeHat(address user, address[] calldata recipients, uint16[] calldata proportions) internal virtual {
        uint256 len = proportions.length;

        if (recipients.length != len) {
            revert InvalidHatLength(recipients.length, len);
        }

        DataTypes.Account memory account = _accounts[user];

        if (account.amount > 0) {
            _recollectUnderlying(user, account.amount);
        }

        //  NOTE: Without this for loop validation, user can change to the invalid hat(e.g. proportions overflow) if they don't have balance at all.
        uint256 total;

        for (uint256 i = 0; i < len;) {
            total += proportions[i];

            unchecked {
                ++i;
            }
        }

        if (total != PercentageMath.PERCENTAGE_FACTOR) {
            revert InvalidProportion(total);
        }

        _accounts[user].hat = DataTypes.Hat(recipients, proportions);

        if (account.amount > 0) {
            _delegateUnderlying(user, account.amount);
        }

        emit ChangeHat(user, account.hat, DataTypes.Hat(recipients, proportions));
    }

    /**
     * @dev Claim interest for the user to get DY-Tokens
     * @param user User account address
     */
    function _claimInterest(address user) internal virtual {
        uint256 interest = _calcInterestPayable(user);

        if (interest > 0) {
            _accounts[user].interestPaid += interest;
            _delegateUnderlying(user, interest);
            _mint(user, interest);

            emit ClaimInterest(user, interest);
        }
    }

    /**
     * @dev 1. Recollect delegated amount from the `from` account
     * 			2. Delegate amount to the recipients of the `to` account
     * 			3. Transfer the `amount` tokens from the `from` account to the `to` account
     * @param from The address of the source account
     * @param to The address of the destination account
     * @param amount The number of tokens to transfer
     */
    function _executeTransfer(address from, address to, uint256 amount) internal override {
        _recollectUnderlying(from, amount);
        _delegateUnderlying(to, amount);
        _transfer(from, to, amount);
    }

    /**
     * @dev Get interest payable of the account
     *  NOTE: If every interest is paid, totalAssets() will be equal to totalSupply()
     * 	Thus, the share mechanism will not work and _convertToAssets(account.delegatedShares)
     *	will return the amount smaller than the account.delegatedAmount due to the rounding direction
     *	To prevent this, we simply return 0 if every interest is paid
     * @param user User account address
     */
    function _calcInterestPayable(address user) internal view virtual returns (uint256) {
        DataTypes.Account memory account = _accounts[user];
        uint256 gross = _convertToAssets(account.delegatedShares, Math.Rounding.Floor);

        if (gross <= account.delegatedAmount) {
            return 0;
        }

        uint256 interest = gross - account.delegatedAmount;

        if (interest <= account.interestPaid) {
            return 0;
        }
        return interest - account.interestPaid;
    }

    /**
     * @dev Internal conversion function (from amount to shares) with support for rounding direction.
     */
    function _convertToShares(uint256 amount, Math.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return amount.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual returns (uint256) {
        return shares.mulDiv(totalAssets() + 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
    }

    function _decimalsOffset() internal view virtual returns (uint8) {
        return 0;
    }
}
