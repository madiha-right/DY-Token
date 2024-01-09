// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {DistributableERC20} from "src/DistributableERC20.sol";

contract Token is DistributableERC20 {
    constructor(string memory name_, string memory symbol_) DistributableERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }

    function convertToShares(uint256 amount) public view returns (uint256) {
        return _convertToShares(amount, Math.Rounding.Floor);
    }
}

contract TestDistributableERC20 is Test {
    Token public token;

    event Transfer(address indexed from, address indexed to, uint256 amount, uint256 shares);

    function setUp() public {
        token = new Token("Test Token", "TST");
    }

    function testFuzz_mint(uint256 amount) public {
        uint256 shares = token.convertToShares(amount);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), amount, shares);
        token.mint(address(this), amount);

        assertEq(token.balanceOf(address(this)), amount);
    }

    function testFuzz_burn(uint256 amount) public {
        token.mint(address(this), amount);

        uint256 shares = token.convertToShares(amount);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(this), address(0), amount, shares);
        token.burn(address(this), amount);

        assertEq(token.balanceOf(address(this)), 0);
    }
}
