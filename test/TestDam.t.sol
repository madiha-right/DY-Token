// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Core} from "./Core.t.sol";

contract TestDam is Core {
    using SafeERC20 for IERC20;
    using MessageHashUtils for bytes32;
    /**
     * TODO:
     *
     * 9. endRound in core
     * with restart
     * with decommission
     * round 3 times
     * 10. check scheduleWithdrawal is working after ending round
     */

    /* ============ operateDam ============ */

    function testFuzz_operateDam(uint256 amount) public {
        amount = bound(amount, 1e18, type(uint128).max);
        _operateDam(amount, PERIOD, REINVESTMENT_RATIO, AUTO_STREAM_RATIO, 1);
    }

    function test_operateDam_AlreadyOperating() public {
        uint256 amount = 1000 * 1e18;
        _operateDam(amount, PERIOD, REINVESTMENT_RATIO, AUTO_STREAM_RATIO, 1);
        vm.expectRevert(abi.encodeWithSelector(DamAlredyOperating.selector));
        dam.operateDam(amount, PERIOD, REINVESTMENT_RATIO, AUTO_STREAM_RATIO);
    }

    function test_operateDam_UnauthorizedAccount() public {
        uint256 amount = 1000 * 1e18;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice));
        dam.operateDam(amount, PERIOD, REINVESTMENT_RATIO, AUTO_STREAM_RATIO);
    }

    /* ============ decomissionDam ============ */

    function testFuzz_decomissionDam(uint256 amount) public {
        amount = bound(amount, 1e18, type(uint128).max);
        _operateDam(amount, PERIOD, REINVESTMENT_RATIO, AUTO_STREAM_RATIO, 1);
        vm.expectEmit(false, false, false, false);
        emit DecommissionDam();

        dam.decommissionDam(alice);

        (,,, bool flowing) = dam.upstream();
        (uint256 withdrawalAmount, address receiver) = dam.withdrawals(0);

        assertEq(withdrawalAmount, type(uint256).max, "scheduled withdrawal amount should equal to type(uint256).max");
        assertEq(receiver, alice, "_receiver should equal to alice");
        assertEq(flowing, false, "Dam should not be operating");
    }

    function test_decomissionDam_NotOperating() public {
        vm.expectRevert(abi.encodeWithSelector(DamNotOperating.selector));
        dam.decommissionDam(address(this));
    }

    function test_decomissionDam_UnauthorizedAccount() public {
        uint256 amount = 1000 * 1e18;
        _operateDam(amount, PERIOD, REINVESTMENT_RATIO, AUTO_STREAM_RATIO, 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice));
        dam.decommissionDam(alice);
    }

    /* ============ endRound ============ */
    // TODO: multiple scenarios
    // endRound with decommission : do it in decomission test
    // 3. endRound 3 times in a row. restart, restart, restart
    function test_endRound() public {}

    function test_endRound_RoundNotEnded() public {
        _operateDam(1000 * 1e18, PERIOD, REINVESTMENT_RATIO, AUTO_STREAM_RATIO, 1);
        vm.expectRevert(abi.encodeWithSelector(RoundNotEnded.selector));
        dam.endRound(_getData(), 0, 0, 0);
    }

    function test_endRound_InvalidSignature_InvalidOracle() public {
        _operateDam(1000 * 1e18, PERIOD, REINVESTMENT_RATIO, AUTO_STREAM_RATIO, 1);

        (, uint256 userPk) = makeAddrAndKey("user");
        bytes memory data = _getData();
        bytes32 digest = keccak256(data).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPk, digest);

        skip(PERIOD);

        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector));
        dam.endRound(data, v, r, s);
    }

    function test_endRound_InvalidSignature_InvalidData() public {
        _operateDam(1000 * 1e18, PERIOD, REINVESTMENT_RATIO, AUTO_STREAM_RATIO, 1);

        (address oracle, uint256 oraclePk) = makeAddrAndKey("oracle");
        bytes memory data = _getData();
        bytes32 digest = keccak256(data).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePk, digest);

        skip(PERIOD);

        dam.setOracle(oracle);
        vm.expectRevert(abi.encodeWithSelector(InvalidSignature.selector));
        dam.endRound(abi.encodePacked(data, uint256(123)), v, r, s);
    }

    function test_endRound_UnauthorizedAccount() public {
        (, uint256 oraclePk) = makeAddrAndKey("oracle");
        bytes memory data = _getData();
        bytes32 digest = keccak256(data).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePk, digest);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice));
        dam.endRound(data, v, r, s);
    }

    /* ============ deposit ============ */

    function test_deposit() public {
        uint256 amount = 1000 * 1e18;
        _operateDam(amount, PERIOD, REINVESTMENT_RATIO, AUTO_STREAM_RATIO, 1);

        _mintYbToken(amount, address(this));
        IERC20(ybToken).forceApprove(address(dam), amount);

        vm.expectEmit(true, false, false, true);
        emit Deposit(address(this), amount);

        dam.deposit(amount);

        assertEq(ybToken.balanceOf(address(this)), 0, "ybToken balance of address(this) should equal to 0");
        assertEq(dyToken.balanceOf(address(dam)), amount * 2, "dyToken balance of dam should equal to amount * 2");
    }

    function test_deposit_NotOperating() public {
        uint256 amount = 1000 * 1e18;
        _mintYbToken(amount, address(this));
        vm.expectRevert(abi.encodeWithSelector(DamNotOperating.selector));
        dam.deposit(amount);
    }

    function test_deposit_UnauthorizedAccount() public {
        uint256 amount = 1000 * 1e18;
        _operateDam(amount, PERIOD, REINVESTMENT_RATIO, AUTO_STREAM_RATIO, 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice));
        dam.deposit(amount);
    }

    /* ============ scheduleWithdrawal ============ */

    function testFuzz_scheduleWithdrawal(uint256 amount) public {
        amount = bound(amount, 1e18, type(uint128).max);
        _operateDam(amount, PERIOD, REINVESTMENT_RATIO, AUTO_STREAM_RATIO, 1);

        vm.expectEmit(true, false, false, true);
        emit ScheduleWithdrawal(alice, amount / 2);
        dam.scheduleWithdrawal(amount / 2, alice);

        vm.expectEmit(true, false, false, true);
        emit ScheduleWithdrawal(bob, amount / 4);
        dam.scheduleWithdrawal(amount / 4, bob);

        (uint256 withdrawalAmount, address receiver) = dam.withdrawals(0);
        (uint256 _withdrawalAmount, address _receiver) = dam.withdrawals(1);
        assertEq(withdrawalAmount, amount / 2, "withdrawalAmount should equal to amount / 2");
        assertEq(_withdrawalAmount, amount / 4, "_withdrawalAmount should equal to amount / 4");
        assertEq(receiver, alice, "receiver should equal to alice");
        assertEq(_receiver, bob, "_receiver should equal to bob");
    }

    function test_scheduleWithdrawal_NotOperating() public {
        uint256 amount = 1000 * 1e18;
        vm.expectRevert(abi.encodeWithSelector(DamNotOperating.selector));
        dam.scheduleWithdrawal(amount, address(this));
    }

    function test_scheduleWithdrawal_InsufficientBalance() public {
        uint256 amount = 1000 * 1e18;
        _operateDam(amount, PERIOD, REINVESTMENT_RATIO, AUTO_STREAM_RATIO, 1);
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector));
        dam.scheduleWithdrawal(amount + 1, address(this));
    }

    function test_scheduleWithdrawal_InvalidAmountRequest() public {
        uint256 amount = 1000 * 1e18;
        _operateDam(amount, PERIOD, REINVESTMENT_RATIO, AUTO_STREAM_RATIO, 1);
        vm.expectRevert(abi.encodeWithSelector(InvalidAmountRequest.selector));
        dam.scheduleWithdrawal(amount, address(this));
    }

    function test_scheduleWithdrawal_InvalidReceiver() public {
        uint256 amount = 1000 * 1e18;
        _operateDam(amount, PERIOD, REINVESTMENT_RATIO, AUTO_STREAM_RATIO, 1);
        vm.expectRevert(abi.encodeWithSelector(InvalidReceiver.selector));
        dam.scheduleWithdrawal(amount - 1, address(0));
    }

    function test_scheduleWithdrawal_UnauthorizedAccount() public {
        uint256 amount = 1000 * 1e18;
        _operateDam(amount, PERIOD, REINVESTMENT_RATIO, AUTO_STREAM_RATIO, 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice));
        dam.scheduleWithdrawal(amount, alice);
    }

    /* ============ setUpstream ============ */

    function test_setUpstream() public {
        vm.expectEmit(false, false, false, true);
        emit SetUpstream(PERIOD, REINVESTMENT_RATIO, AUTO_STREAM_RATIO);

        dam.setUpstream(PERIOD, REINVESTMENT_RATIO, AUTO_STREAM_RATIO);

        (uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio,) = dam.upstream();

        assertEq(period, PERIOD, "period should equal to PERIOD");
        assertEq(reinvestmentRatio, REINVESTMENT_RATIO, "reinvestmentRatio should equal to REINVESTMENT_RATIO");
        assertEq(autoStreamRatio, AUTO_STREAM_RATIO, "autoStreamRatio should equal to AUTO_STREAM_RATIO");
    }

    function test_setUpstream_UnauthorizedAccount() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice));
        dam.setUpstream(PERIOD, REINVESTMENT_RATIO, AUTO_STREAM_RATIO);
    }

    /* ============ setOracle ============ */

    function test_setOracle() public {
        vm.expectEmit(true, true, false, false);
        emit SetOracle(address(0), ORACLE);

        dam.setOracle(ORACLE);
        assertEq(dam.oracle(), ORACLE, "oracle should equal to ORACLE");
    }

    function test_setOracle_UnautorizedAccount() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice));
        dam.setOracle(ORACLE);
    }
}
