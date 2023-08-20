// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import {Test} from "forge-std/Test.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "../mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    Raffle raffle;
    HelperConfig helperConfig;

    address private Player = makeAddr("Player");
    uint256 private constant STARTING_BAL = 10 ether;

    uint256 private entranceFee;
    uint256 private interval;
    address private vrfCoordinator;
    bytes32 private keyHash;
    uint64 private subscriptionId;
    uint32 private callBackGasLimit;
    address private link;
    uint256 private deployerKey;

    event EnteredRaffle(address indexed player);

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.run();
        (
            entranceFee,
            interval,
            vrfCoordinator,
            keyHash,
            subscriptionId,
            callBackGasLimit,
            link,
            deployerKey
        ) = helperConfig.activeNetworkConfig();
        vm.deal(Player, STARTING_BAL);
    }

    function testRaffleInitializesOpenState() external view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertsWhenYouDontPayEnough() external {
        vm.expectRevert(Raffle.Raffle__NotEnoughFunds.selector);
        raffle.enterRaffle{value: 0.001 ether}();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() external {
        vm.prank(Player);
        raffle.enterRaffle{value: entranceFee}();
        assertEq(raffle.getPlayer(0), Player);
    }

    function testEmitsEventOnEntrance() external {
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(Player);

        vm.prank(Player);
        raffle.enterRaffle{value: entranceFee}();
    }

    modifier enterRaffle() {
        vm.startPrank(Player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + raffle.getInterval() + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testCantEnterWhenCalculating() external enterRaffle {
        raffle.performUpKeep("");

        vm.expectRevert(Raffle.Raffle__NotOpened.selector);
        raffle.enterRaffle{value: entranceFee}();
        vm.stopPrank();
    }

    function testCheckUpKeepReturnsFalseIfRaffleNotOpen() external enterRaffle {
        raffle.performUpKeep("");

        (bool upKeepNeeded, ) = raffle.checkUpKeep("");

        assert(!upKeepNeeded);
    }

    function testCheckUpKeepReturnsTrueWhenParametersAreGood()
        external
        enterRaffle
    {
        (bool upKeepNeeded, ) = raffle.checkUpKeep("");

        assert(upKeepNeeded);
    }

    function testPerformUpKeepCanOnlyRunIfCheckUpKeepIsTrue()
        external
        enterRaffle
    {
        raffle.performUpKeep("");
    }

    function testPerformUpKeepRevertsIfCheckUpKeepIsFalse() external {
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState raffleState = Raffle.RaffleState.OPEN;

        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpKeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                raffleState
            )
        );
        raffle.performUpKeep("");
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testPerformUpKeepUpdatesRaffleStateAndEmitRequestId()
        external
        enterRaffle
    {
        vm.prank(Player);
        vm.recordLogs();
        raffle.performUpKeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) > 0);
    }

    //fuzz test
    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpKeep(
        uint256 randomId
    ) external enterRaffle skipFork {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksWinnerAndSendMoney() external skipFork {
        uint256 numPlayers = 6;
        for (uint256 i = 1; i < 6; i++) {
            hoax(address(uint160(i)), STARTING_BAL);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 prize = entranceFee * numPlayers;

        vm.warp(block.timestamp + raffle.getInterval() + 1);
        vm.roll(block.number + 1);

        vm.recordLogs();
        raffle.performUpKeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        uint256 lastTimeStamp = raffle.getLastTimeStamp();
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        assert(raffle.s_recentWinner() != address(0));
        assert(uint256(raffle.getRaffleState()) == 1);
        assert(raffle.getPlayersLength() == 0);
        assert(lastTimeStamp < raffle.getLastTimeStamp());
        //assert(raffle.s_recentWinner().balance == (STARTING_BAL + prize));
    }
}
