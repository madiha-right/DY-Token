// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {PercentageMath} from "src/libraries/PercentageMath.sol";
import {Core} from "./Core.t.sol";

contract TestEmbankment is Core {
    using PercentageMath for uint256;

    function testFuzz_dischargeYield(uint256 amount) public {
        amount = bound(amount, 1e18, uint256(type(uint128).max));
        _mintDyToken(amount, address(embankment));

        bytes memory data = _getData();
        (address[] memory recipients, uint16[] memory proportions) = abi.decode(data, (address[], uint16[]));

        uint256 totalIncentive = IERC20(address(dyToken)).balanceOf(address(embankment));

        uint256 leftIncentive = totalIncentive;

        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint16 proportion = proportions[i];
            uint256 incentive = i == recipients.length - 1 ? leftIncentive : totalIncentive.mulTo(uint256(proportion));

            vm.expectEmit(true, false, false, true);
            emit DistributeIncentive(recipient, proportion, incentive);
            leftIncentive -= incentive;
        }

        embankment.dischargeYield(data);

        assertEq(IERC20(address(dyToken)).balanceOf(address(embankment)), 0, "Embankment should not have any dyToken");
        assertEq(IERC20(address(ybToken)).balanceOf(address(embankment)), 0, "Embankment should not have any ybToken");

        leftIncentive = totalIncentive;

        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 incentive =
                i == recipients.length - 1 ? leftIncentive : totalIncentive.mulTo(uint256(proportions[i]));
            assertEq(IERC20(address(ybToken)).balanceOf(recipients[i]), incentive, "Incorrect incentive");
            leftIncentive -= incentive;
        }
    }

    function test_dischargeYield_InvalidProportion() public {
        _mintDyToken(10000 * 1e18, address(embankment));

        (bytes memory data, uint16 proportion) = _getDataInvalidProportion();
        vm.expectRevert(abi.encodeWithSelector(InvalidProportion.selector, proportion));
        embankment.dischargeYield(data);
    }

    function test_dischargeYield_UnauthorizedAccount() public {
        _mintDyToken(10000 * 1e18, address(embankment));

        vm.prank(alice);

        bytes memory data = _getData();
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice));
        embankment.dischargeYield(data);
    }
}
