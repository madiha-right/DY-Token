// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {DataTypes} from "src/libraries/DataTypes.sol";
import {DistributableERC20} from "src/DistributableERC20.sol";
import {DYToken} from "src/DYToken.sol";
import {Core} from "./Core.t.sol";

contract TestDYToken is Core {
    function testFuzz_totalAssets(uint256 amount) public {
        amount = bound(amount, 1e18, uint256(type(uint128).max));
        DataTypes.Hat memory emptyHat = _getHat_empty();

        deposit(amount, alice, emptyHat.recipients, emptyHat.proportions, alice);

        uint256 total = IERC20(address(mockStETH)).balanceOf(address(dyToken));

        assertEq(dyToken.totalAssets(), total, "totalAssets after accural");
        assertEq(dyToken.totalSupply(), amount, "totalSupply after accural");
    }

    function testFuzz_deposit(uint256 amount) public {
        amount = bound(amount, 1e18, uint256(type(uint128).max));
        DataTypes.Hat memory hat = _getHat_bobNcharlie_7030();
        deposit(amount, alice, hat.recipients, hat.proportions, alice);
    }

    function testFuzz_deposit_emptyHat(uint256 amount) public {
        amount = bound(amount, 1e18, uint256(type(uint128).max));
        DataTypes.Hat memory emptyHat = _getHat_empty();
        deposit(amount, alice, emptyHat.recipients, emptyHat.proportions, alice);

        assertApproxEqAbs(dyToken.getInterestPayable(alice), dyToken.totalAssets() - amount, 1, "interest");
    }

    function testFuzz_deposit_selfHat(uint256 amount) public {
        amount = bound(amount, 1e18, uint256(type(uint128).max));
        DataTypes.Hat memory selfHat = _getHat_alice_100();
        deposit(amount, alice, selfHat.recipients, selfHat.proportions, alice);

        assertApproxEqAbs(dyToken.getInterestPayable(alice), dyToken.totalAssets() - amount, 1, "interest");
    }

    function testFuzz_withdraw(uint256 amount) public {
        amount = bound(amount, 1e18, uint256(type(uint128).max));
        DataTypes.Hat memory hat = _getHat_bobNcharlie_7030();
        deposit(amount, alice, hat.recipients, hat.proportions, alice);

        withdraw(amount, david, alice);
    }

    function test_withdraw_InsufficientBalance() public {
        DataTypes.Hat memory hat = _getHat_bobNcharlie_7030();
        uint256 amount = 1e18;
        deposit(amount / 2, alice, hat.recipients, hat.proportions, alice);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, alice, amount / 2, amount));
        dyToken.withdraw(amount, david);

        vm.stopPrank();
    }

    function test_changeHat() public {
        DataTypes.Hat memory emptyHat = _getHat_empty();
        DataTypes.Hat memory bobNcharlieHat = _getHat_bobNcharlie_7030();

        deposit(1e18, alice, emptyHat.recipients, emptyHat.proportions, alice);
        changeHat(alice, emptyHat, bobNcharlieHat);
    }

    function test_changeHat_InvalidHatLength() public {
        DataTypes.Hat memory emptyHat = _getHat_empty();
        DataTypes.Hat memory invalidHat = _getHat_invalidLength();

        deposit(1e18, alice, emptyHat.recipients, emptyHat.proportions, alice);

        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidHatLength.selector, invalidHat.recipients.length, invalidHat.proportions.length
            )
        );
        dyToken.changeHat(invalidHat.recipients, invalidHat.proportions);
        vm.stopPrank();
    }

    function test_changeHat_InvalidHatProportion() public {
        DataTypes.Hat memory emptyHat = _getHat_empty();
        DataTypes.Hat memory invalidHatProportion = _getHat_invalidProportion();
        DataTypes.Hat memory invalidHatProportionAcc = _getHat_invalidProportionAcc();

        deposit(1e18, alice, emptyHat.recipients, emptyHat.proportions, alice);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(InvalidProportion.selector, invalidHatProportion.proportions[0]));
        dyToken.changeHat(invalidHatProportion.recipients, invalidHatProportion.proportions);

        uint16 accProportion;

        for (uint256 i = 0; i < invalidHatProportionAcc.proportions.length; i++) {
            accProportion += invalidHatProportionAcc.proportions[i];
        }

        vm.expectRevert(abi.encodeWithSelector(InvalidProportion.selector, accProportion));
        dyToken.changeHat(invalidHatProportionAcc.recipients, invalidHatProportionAcc.proportions);
        vm.stopPrank();
    }

    function test_claimInterest() public {
        DataTypes.Hat memory bobNcharlieHat = _getHat_bobNcharlie_7030();

        deposit(1e18, alice, bobNcharlieHat.recipients, bobNcharlieHat.proportions, alice);
        uint256 bobInterest = dyToken.getInterestPayable(bob);

        vm.expectEmit(true, false, false, true);
        emit ClaimInterest(bob, bobInterest);
        dyToken.claimInterest(bob);

        assertEq(dyToken.balanceOf(bob), bobInterest, "bob balance");
        assertEq(dyToken.getAccountData(bob).interestPaid, bobInterest, "bob interest paid");
        assertEq(dyToken.getInterestPayable(bob), 0, "bob interest payable");

        DataTypes.Hat memory aliceHat = _getHat_alice_100();
        DataTypes.Hat memory emptyHat = _getHat_empty();

        changeHat(bob, emptyHat, aliceHat);

        DataTypes.Account memory aliceAccount = dyToken.getAccountData(alice);

        assertEq(aliceAccount.debtAmount, bobInterest, "alice should have bob's claimed interest as debt");
    }

    function test_transfer() public {
        uint256 amount = 1e18;
        DataTypes.Hat memory emptyHat = _getHat_empty();
        DataTypes.Hat memory bobHat = _getHat_bob_100();
        DataTypes.Hat memory davidHat = _getHat_david_100();

        deposit(amount, alice, bobHat.recipients, bobHat.proportions, alice);
        changeHat(charlie, emptyHat, davidHat);

        uint256 bobInterest = dyToken.getInterestPayable(bob);

        vm.startPrank(alice);
        dyToken.transfer(charlie, amount / 2);
        vm.stopPrank();

        assertEq(dyToken.balanceOf(alice), amount / 2, "alice should have half of the deposit amount");
        assertEq(dyToken.balanceOf(charlie), amount / 2, "charlie should have half of the deposit amount");
        assertEq(dyToken.balanceOf(bob), bobInterest, "bob should be paid the interest");
        assertEq(dyToken.getInterestPayable(bob), 0, "bob should not have interest payable");
        assertEq(dyToken.getAccountData(bob).interestPaid, bobInterest, "bob's interestPaid should be interest amount");
    }
}
