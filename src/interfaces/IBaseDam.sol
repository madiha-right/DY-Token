// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IDistributableYieldToken} from "./IDistributableYieldToken.sol";
import {IEmbank} from "./IEmbank.sol";

interface IBaseDam {
    error InvalidPeriod();
    error InvalidRatio();
    error DamAlredyOperating();
    error DamNotOperating();
    error RoundNotEnded();
    error InsufficientBalance();
    error InvalidAddress();

    function endRound(bytes calldata data) external;

    function setHost(address _host) external;

    function setUpstream(uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio) external;

    function deposit(uint256 amount) external;

    function scheduleWithdrawal(uint256 amount, address receiver) external;

    function ybToken() external view returns (IERC20);

    function dyToken() external view returns (IDistributableYieldToken);

    function embank() external view returns (IEmbank);

    function upstream()
        external
        view
        returns (uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio, bool flowing);

    function round() external view returns (uint256 startTime, uint256 endTime);

    function withdrawals(uint256 index) external view returns (uint256 amount, address receiver);

    function host() external view returns (address);
}
