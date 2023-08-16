// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {VRFCoordinatorV2Mock} from "../test/mocks/VRFCoordinatorV2Mock.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

//import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

/**
 * @title A sample raffle contract
 * @author Sunday Philip
 * @notice This contract is for creating a sample raffle contract
 * @dev implements Chainlink VRF2
 */
contract Raffle is VRFConsumerBaseV2 {
    /** Custom Errors */
    error Raffle__NotEnoughFunds();
    error Raffle__TransferFailed();
    error Raffle__NotOpened();
    error Raffle__UpKeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        RaffleState raffleState
    );

    /** Type Declarations */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /** State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    uint32 private immutable i_callBackGasLimit;
    VRFCoordinatorV2Mock private immutable i_vrfCoordinator;
    uint64 private immutable i_subscriptionId;
    bytes32 private immutable i_keyHash;
    address[] private s_players;
    uint256 private s_lastTimeStamp;
    address payable public s_recentWinner;
    address private s_linkToken;
    RaffleState private s_raffleState;

    /** Events */
    event EnteredRaffle(address indexed player);
    event PickWinner(address indexed winner);
    event Requested(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 keyHash,
        uint64 subscriptionId,
        uint32 callBackGasLimit,
        address linkToken
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_vrfCoordinator = VRFCoordinatorV2Mock(vrfCoordinator);
        i_keyHash = keyHash;
        i_subscriptionId = subscriptionId;
        i_callBackGasLimit = callBackGasLimit;
        s_raffleState = RaffleState.OPEN;
        s_linkToken = linkToken;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughFunds();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__NotOpened();
        }
        s_players.push(msg.sender);
        emit EnteredRaffle(payable(msg.sender));
    }

    /**
     * @dev this is the function that the chainlink automation calls
     * to perform an upkeep
     * The following should be true for this to return true
     * The time interval of the raffle must have passed
     * The Raffle is in an OPEN raffleState
     * The contract has ETH, i.e, Players
     * The subsciption is funded with LINK tokens (Implicit)
     */
    function checkUpKeep(
        bytes memory /* checkData */
    ) public view returns (bool upKeepNeeded, bytes memory /* PerformData */) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasEth = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upKeepNeeded = (timeHasPassed && isOpen && hasEth && hasPlayers);
    }

    // Get a Random number
    //Use the random number to pick a player
    // Be called automatically
    function performUpKeep(bytes memory /* performData */) external {
        (bool upKeepNeeded, ) = checkUpKeep("");
        if (!upKeepNeeded) {
            revert Raffle__UpKeepNotNeeded(
                address(this).balance,
                s_players.length,
                s_raffleState
            );
        }
        //check to see if enough time has passed
        if (block.timestamp - s_lastTimeStamp < i_interval) {
            revert();
        }
        s_raffleState = RaffleState.CALCULATING;

        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_keyHash,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callBackGasLimit,
            NUM_WORDS
        );
        emit Requested(requestId);
    }

    function fulfillRandomWords(
        uint256 /*requestId */,
        uint[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address winner = s_players[indexOfWinner];
        s_recentWinner = payable(winner);
        s_raffleState = RaffleState.CALCULATING;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        (bool sent, ) = s_recentWinner.call{value: address(this).balance}("");
        if (!sent) {
            revert Raffle__TransferFailed();
        }
        emit PickWinner(s_recentWinner);
    }

    /** Getter Function */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 index) external view returns (address) {
        return s_players[index];
    }

    function getPlayersLength() external view returns (uint256) {
        return s_players.length;
    }

    function getInterval() external view returns (uint256) {
        return i_interval;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
