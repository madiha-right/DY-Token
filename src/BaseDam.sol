// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IDistributableYieldToken} from "./interfaces/IDistributableYieldToken.sol";
import {IEmbank} from "./interfaces/IEmbank.sol";
import {IBaseDam} from "./interfaces/IBaseDam.sol";

/**
 * TODO:
 * 1. interface
 * 2. add events
 * 3. endRound() should verify the signature of data
 */

contract BaseDam is IBaseDam, Ownable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    struct Upstream {
        uint256 period; // period of the round
        /**
         * @dev ratio of the yield that goes to the treasury, expressed in BP(basis points).
         * 10000 - reinvestmentRatio = ratio of the yield that goes to the Embank
         */
        uint16 reinvestmentRatio;
        /**
         * @dev ratio of the generated yield in Embank that goes to the projects who registered for the auto stream, expressed in BP(basis points).
         * 10000 - autoStreamRatio = communityStreamRatio(voting)
         */
        uint16 autoStreamRatio;
        bool flowing; // if false, next round will not be started
    }

    struct Round {
        uint256 startTime;
        uint256 endTime;
    }

    struct Withdrawal {
        uint256 amount;
        address receiver;
    }

    uint16 constant PERCENTAGE_FACTOR = 1e4;

    IERC20 public immutable ybToken;
    IDistributableYieldToken public immutable dyToken;
    IEmbank public immutable embank; // where the generated yield will be stored and distributed

    Upstream public upstream; // configs
    Round public round;
    Withdrawal[] public withdrawals; // scheduled withdrawals

    address public host; // address of DAM dev who can make the rounds seemlessly

    modifier onlyHost() {
        address sender = _msgSender();
        if (sender != host) revert OwnableUnauthorizedAccount(sender);
        _;
    }

    // only the owner and DAM dev can call this function
    modifier onlyOwnerAndHost() {
        address sender = _msgSender();
        if (sender != owner() && sender != host) revert OwnableUnauthorizedAccount(sender);
        _;
    }

    constructor(IERC20 ybToken_, IDistributableYieldToken dyToken_, IEmbank embank_) Ownable(_msgSender()) {
        ybToken = ybToken_;
        dyToken = dyToken_;
        embank = embank_;
        host = _msgSender();
    }

    function operateDam(uint256 amount, uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio)
        external
        onlyOwner
    {
        if (upstream.flowing) revert DamAlredyOperating();
        _setUpsteram(period, reinvestmentRatio, autoStreamRatio);
        _deposit(amount);
        _startRound();
    }

    function decommissionDam(address receiver) external onlyOwner {
        if (!upstream.flowing) revert DamNotOperating();
        _scheduleWithdrawal(type(uint256).max, receiver);
        upstream.flowing = false;
    }

    // TODO: only owner and manager can call
    // TODO: find out if signing in front end is enough
    // keccak256(abi.encode(receiver)).toEthSignedMessageHash().recover(embank);
    function endRound(bytes calldata data) external onlyOwner {
        if (block.timestamp < round.endTime) revert RoundNotEnded();
        _dischargeYield(data);

        if (withdrawals.length > 0) {
            _processWithdrawls();
        }
        if (upstream.flowing) {
            _startRound();
        }
    }

    // deposit will be applied directly to the ongoing round
    function deposit(uint256 amount) external onlyOwner {
        _deposit(amount);
    }

    // Withdrawl happens when the round ends
    function scheduleWithdrawal(uint256 amount, address receiver) external onlyOwner {
        if (amount > IERC20(dyToken).balanceOf(address(this))) revert InsufficientBalance();
        _scheduleWithdrawal(amount, receiver);
    }

    // this upstream will be applied from the next round
    function setUpsteram(uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio) external onlyOwner {
        _setUpsteram(period, reinvestmentRatio, autoStreamRatio);
    }

    function setHost(address _host) external onlyHost {
        host = _host;
    }

    function _startRound() internal {
        Upstream memory _upstream = upstream;
        uint256 timestamp = block.timestamp;

        if (!_upstream.flowing) revert DamNotOperating();
        if (timestamp < round.endTime) revert RoundNotEnded();

        round = Round(timestamp, timestamp + _upstream.period);

        uint16 proportion = _upstream.reinvestmentRatio;
        uint256 length = proportion == 0 ? 1 : 2;

        address[] memory recipients = new address[](length);
        uint16[] memory proportions = new uint16[](length);

        // If proportion is 0, all the interest goes to embank
        if (proportion == 0) {
            recipients[0] = address(embank);
            proportions[0] = PERCENTAGE_FACTOR;
        } else {
            recipients[0] = address(embank);
            recipients[1] = address(this);
            proportions[0] = PERCENTAGE_FACTOR - proportion;
            proportions[1] = proportion;
        }

        dyToken.changeHat(recipients, proportions);
    }

    function _dischargeYield(bytes calldata data) internal {
        embank.dischargeYield(data);
    }

    function _setUpsteram(uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio) internal {
        if (period == 0) revert InvalidPeriod();
        if (reinvestmentRatio > PERCENTAGE_FACTOR || autoStreamRatio > PERCENTAGE_FACTOR) {
            revert InvalidRatio();
        }

        upstream = Upstream(period, reinvestmentRatio, autoStreamRatio, true);
    }

    /**
     * @dev Deposits the ybToken to the dyToken, the generated interest will be distributed to the embank and address(this)
     * @param amount Amount to be used as source of the generated interest
     */
    function _deposit(uint256 amount) internal {
        ybToken.safeTransferFrom(_msgSender(), address(this), amount);
        dyToken.deposit(amount, address(this), new address[](0), new uint16[](0));
    }

    function _scheduleWithdrawal(uint256 amount, address receiver) internal {
        if (receiver == address(0)) revert InvalidAddress();
        withdrawals.push(Withdrawal(amount, receiver));
    }

    function _processWithdrawls() internal {
        Withdrawal[] memory _withdrawals = withdrawals;
        uint256 len = _withdrawals.length;

        for (uint256 i = 0; i < len;) {
            _withdraw(withdrawals[i].amount, withdrawals[i].receiver);

            unchecked {
                ++i;
            }
        }

        delete withdrawals;
    }

    /**
     * @dev Withdraws the ybToken from the dyToken and sends it to the receiver
     *      try-catch is used to prevent contract going off
     * @param amount Amount to be withdrawn
     * @param receiver Address of the receiver who will get a part of principal and interest if proportion passed on startJourney()
     */
    function _withdraw(uint256 amount, address receiver) internal {
        // claim interest to send generated interest to the receiver
        if (amount == type(uint256).max) {
            try dyToken.claimInterest(address(this)) {} catch {}
            amount = IERC20(dyToken).balanceOf(address(this));
        }

        try dyToken.withdraw(amount, address(this)) {
            try ybToken.transfer(receiver, amount) {} catch {}
        } catch {}
    }
}
