// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Embankment} from "src/Embankment.sol";
import {Dam} from "src/Dam.sol";
import {Token} from "./dyToken/Token.sol";
import {MockStETH} from "./mocks/MockStETH.sol";

contract Core is Test {
    /* ============ Constants ============ */

    uint256 constant PERIOD = 30 days;
    uint16 constant REINVESTMENT_RATIO = 500;
    uint16 constant AUTO_STREAM_RATIO = 9000;
    address constant ORACLE = address(0x1);

    /* ============ Immutables ============ */

    address immutable alice = makeAddr("alice");
    address immutable bob = makeAddr("bob");
    address immutable charlie = makeAddr("charlie");
    address immutable david = makeAddr("david");

    /* ============ State Variables ============ */

    MockStETH public mockStETH;
    Token public dyToken;
    Embankment public embankment;
    Dam public dam;

    /* ============ Errors ============ */

    error InvalidProportion(uint256 proportion);
    error OwnableUnauthorizedAccount(address account);

    /* ============ Events ============ */

    event SetUpstream(uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio);
    event SetOracle(address indexed oldOracle, address indexed newOracle);

    event DistributeIncentive(address indexed receiver, uint16 proportion, uint256 amount);

    /* ============ setUp Function ============ */

    function setUp() public {
        mockStETH = new MockStETH();
        dyToken = new Token(IERC20(address(mockStETH)), "Distributable Yield mock stETH", "DY-mock-stETH");
        embankment = new Embankment(IERC20(address(mockStETH)), dyToken);
        dam = new Dam(mockStETH, dyToken, embankment);
    }

    /* ============ Internal Functions ============ */

    function _mintDyToken(uint256 amount, address receiver) internal {
        mockStETH.mint(address(this), amount);
        mockStETH.approve(address(dyToken), amount);
        dyToken.deposit(amount, receiver, new address[](4), new uint16[](4));
    }

    function _getData() internal view returns (bytes memory) {
        address[] memory recipients = new address[](4);
        uint16[] memory proportions = new uint16[](4);

        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = charlie;
        recipients[3] = david;

        proportions[0] = 1000;
        proportions[1] = 2000;
        proportions[2] = 3000;
        proportions[3] = 4000;

        return abi.encode(recipients, proportions);
    }

    function _getDataInvalidProportion() internal view returns (bytes memory, uint16) {
        address[] memory recipients = new address[](4);
        uint16[] memory proportions = new uint16[](4);

        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = charlie;
        recipients[3] = david;

        proportions[0] = 1000;
        proportions[1] = 2000;
        proportions[2] = 3000;
        proportions[3] = 5000;

        return (abi.encode(recipients, proportions), 11000);
    }
}
