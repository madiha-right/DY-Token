// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";

contract Helper is Test {
    /* ============ Constants ============ */

    uint256 constant PERCENTAGE_FACTOR = 10000;
    uint256 constant PERIOD = 30 days;
    uint16 constant REINVESTMENT_RATIO = 500;
    uint16 constant AUTO_STREAM_RATIO = 9000;
    address constant ORACLE = address(0x1);

    /* ============ Immutables ============ */

    address immutable alice = makeAddr("alice");
    address immutable bob = makeAddr("bob");
    address immutable charlie = makeAddr("charlie");
    address immutable david = makeAddr("david");
    address immutable fred = makeAddr("fred");
    address immutable gene = makeAddr("gene");
    address immutable holly = makeAddr("holly");
    address immutable isaac = makeAddr("isaac");
    address immutable jin = makeAddr("jin");
    address immutable kate = makeAddr("kate");
    address immutable luke = makeAddr("luke");
    address immutable mary = makeAddr("mary");
    address immutable nancy = makeAddr("nancy");
    address immutable oscar = makeAddr("oscar");
    address immutable paul = makeAddr("paul");
    address immutable quinn = makeAddr("quinn");
    address immutable ryan = makeAddr("ryan");
    address immutable sarah = makeAddr("sarah");
    address immutable tom = makeAddr("tom");
    address immutable ursula = makeAddr("ursula");
    address immutable victor = makeAddr("victor");
    address immutable wendy = makeAddr("wendy");
    address immutable xavier = makeAddr("xavier");
    address immutable yvonne = makeAddr("yvonne");
    address immutable zack = makeAddr("zack");
    address immutable allen = makeAddr("allen");
    address immutable brian = makeAddr("brian");
    address immutable carol = makeAddr("carol");
    address immutable dave = makeAddr("dave");
    address immutable eric = makeAddr("eric");
    address immutable frank = makeAddr("frank");
    address immutable grace = makeAddr("grace");
    address immutable helen = makeAddr("helen");
    address immutable iris = makeAddr("iris");
    address immutable jack = makeAddr("jack");
    address immutable karen = makeAddr("karen");
    address immutable larry = makeAddr("larry");
    address immutable molly = makeAddr("molly");
    address immutable nathan = makeAddr("nathan");
    address immutable olivia = makeAddr("olivia");
    address immutable peter = makeAddr("peter");
    address immutable quincy = makeAddr("quincy");
    address immutable rachel = makeAddr("rachel");
    address immutable steve = makeAddr("steve");
    address immutable tina = makeAddr("tina");
    address immutable ulysses = makeAddr("ulysses");
    address immutable victoria = makeAddr("victoria");
    address immutable walter = makeAddr("walter");
    address immutable xena = makeAddr("xena");
    address immutable yuri = makeAddr("yuri");
    address immutable zoe = makeAddr("zoe");

    /* ============ Errors ============ */

    error InvalidPeriod();
    error InvalidRatio();
    error DamAlredyOperating();
    error DamNotOperating();
    error RoundNotEnded();
    error InsufficientBalance();
    error InvalidAmountRequest();
    error InvalidReceiver();
    error InvalidSignature();
    error InvalidProportion(uint256 proportion);
    error OwnableUnauthorizedAccount(address account);
    error InvalidAddress();

    /* ============ Events ============ */

    event OperateDam();
    event DecommissionDam();
    event StartRound(uint16 id, uint256 startTime, uint256 endTime);
    event EndRound(uint16 indexed id, bytes data);
    event Deposit(address indexed sender, uint256 amount);
    event ScheduleWithdrawal(address indexed receiver, uint256 amount);
    event SetUpstream(uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio);
    event SetOracle(address indexed oldOracle, address indexed newOracle);

    event DistributeIncentive(address indexed receiver, uint16 proportion, uint256 amount);

    /* ============ Internal Functions ============ */

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

    function _getDataRoundTwo() internal view returns (bytes memory) {
        address[] memory recipients = new address[](2);
        uint16[] memory proportions = new uint16[](2);

        recipients[0] = fred;
        recipients[1] = gene;

        proportions[0] = 1000;
        proportions[1] = 9000;

        return abi.encode(recipients, proportions);
    }

    function _getDataRoundThree() internal view returns (bytes memory) {
        address[] memory recipients = new address[](45);
        uint16[] memory proportions = new uint16[](45);

        recipients[0] = holly;
        recipients[1] = isaac;
        recipients[2] = jin;
        recipients[3] = kate;
        recipients[4] = luke;
        recipients[5] = mary;
        recipients[6] = nancy;
        recipients[7] = oscar;
        recipients[8] = paul;
        recipients[9] = quinn;
        recipients[10] = ryan;
        recipients[11] = sarah;
        recipients[12] = tom;
        recipients[13] = ursula;
        recipients[14] = victor;
        recipients[15] = wendy;
        recipients[16] = xavier;
        recipients[17] = yvonne;
        recipients[18] = zack;
        recipients[19] = allen;
        recipients[20] = brian;
        recipients[21] = carol;
        recipients[22] = dave;
        recipients[23] = eric;
        recipients[24] = frank;
        recipients[25] = grace;
        recipients[26] = helen;
        recipients[27] = iris;
        recipients[28] = jack;
        recipients[29] = karen;
        recipients[30] = larry;
        recipients[31] = molly;
        recipients[32] = nathan;
        recipients[33] = olivia;
        recipients[34] = peter;
        recipients[35] = quincy;
        recipients[36] = rachel;
        recipients[37] = steve;
        recipients[38] = tina;
        recipients[39] = ulysses;
        recipients[40] = victoria;
        recipients[41] = walter;
        recipients[42] = xena;
        recipients[43] = yuri;
        recipients[44] = zoe;

        proportions[0] = 100;
        proportions[1] = 100;
        proportions[2] = 100;
        proportions[3] = 100;
        proportions[4] = 100;
        proportions[5] = 100;
        proportions[6] = 100;
        proportions[7] = 100;
        proportions[8] = 100;
        proportions[9] = 100;
        proportions[10] = 100;
        proportions[11] = 100;
        proportions[12] = 100;
        proportions[13] = 100;
        proportions[14] = 100;
        proportions[15] = 100;
        proportions[16] = 100;
        proportions[17] = 100;
        proportions[18] = 100;
        proportions[19] = 100;
        proportions[20] = 300;
        proportions[21] = 300;
        proportions[22] = 300;
        proportions[23] = 300;
        proportions[24] = 300;
        proportions[25] = 300;
        proportions[26] = 300;
        proportions[27] = 300;
        proportions[28] = 300;
        proportions[29] = 300;
        proportions[30] = 200;
        proportions[31] = 200;
        proportions[32] = 200;
        proportions[33] = 200;
        proportions[34] = 200;
        proportions[35] = 200;
        proportions[36] = 200;
        proportions[37] = 200;
        proportions[38] = 200;
        proportions[39] = 200;
        proportions[40] = 1000;
        proportions[41] = 1000;
        proportions[42] = 250;
        proportions[43] = 250;
        proportions[44] = 500;

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
        proportions[3] = 3000;

        return (abi.encode(recipients, proportions), 9000);
    }
}
