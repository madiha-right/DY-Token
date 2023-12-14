// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "./libraries/ERC20.sol";
import {DataTypes} from "./libraries/DataTypes.sol";

/**
 * @title Distributable ERC20
 * @notice Distributable ERC20 implementation
 * @author Easy, inspired by the Openzeppelin ERC20 implementation
 */
abstract contract DistributableERC20 is ERC20 {
    mapping(address => DataTypes.Account) internal _accounts;

    event Transfer(address indexed from, address indexed to, uint256 amount, uint256 shares);

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    /**
     * @notice Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address user) public view override returns (uint256) {
        DataTypes.Account memory account = _accounts[user];
        return account.amount;
    }

    /**
     * @notice Moves `amount` tokens from the caller's account to `to`.
     * @return A boolean value indicating whether the operation succeeded.
     */
    function transfer(address to, uint256 value) public virtual override returns (bool) {
        address sender = _msgSender();
        _executeTransfer(sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _executeTransfer(from, to, value);
        return true;
    }

    /**
     * @dev 1. Recollect loan from the `from` account
     * 			2. Distribute loan to the recipients of the `to` account
     * 			3. Transfer the `amount` tokens from the `from` account to the `to` account
     * @param from The address of the source account
     * @param to The address of the destination account
     * @param amount The number of tokens to transfer
     */
    function _executeTransfer(address from, address to, uint256 amount) internal virtual {}

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual returns (uint256) {}

    /**
     * @dev Overrides _balances to _accounts.rAmount
     * Emits a {Transfer} event.
     */
    function _update(address from, address to, uint256 amount) internal override {
        uint256 shares = _convertToShares(amount, Math.Rounding.Floor);

        if (from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            _totalSupply += amount;
        } else {
            uint256 fromBalance = _accounts[from].amount;
            if (fromBalance < amount) {
                revert ERC20InsufficientBalance(from, fromBalance, amount);
            }
            unchecked {
                // Overflow not possible: amount <= fromBalance <= totalSupply.
                _accounts[from].amount = fromBalance - amount;
            }
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: amount <= totalSupply or amount <= fromBalance <= totalSupply.
                _totalSupply -= amount;
            }
        } else {
            unchecked {
                // Overflow not possible: balance + amount is at most totalSupply, which we know fits into a uint256.
                _accounts[to].amount += amount;
            }
        }

        emit Transfer(from, to, amount, shares);
    }
}
