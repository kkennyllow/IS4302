// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./VRFv2Consumer.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Deck {
    struct Card {
        uint8 suit;
        uint8 rank;
    }

    enum PlayerState {
        beforeStand,
        Stand
    }

    enum CardState {
        Shuffling,
        Distributing,
        Idling
    }

    struct Player {
        address player;
        Card[] hand;
        uint256 sum;
        uint256 numAces;
        PlayerState currentState;
    }

    VRFv2Consumer public vrfConsumer;
    Card[] public deck;
    uint256 public requestID;
    string public randomNumbersString;
    mapping(address => Player) public Players;
    CardState public cardState;
    address public owner;

    constructor(VRFv2Consumer vrfConsumerAddress) {
        vrfConsumer = vrfConsumerAddress;
        for (uint8 suit = 1; suit <= 4; suit++) {
            for (uint8 rank = 1; rank <= 13; rank++) {
                deck.push(Card(suit, rank));
            }
        }
        generateDrawRequest();
        owner = msg.sender;
    }

    function initializePlayers(address[] memory playerAddresses) public {
        for (uint256 i = 0; i < playerAddresses.length; i++) {
            address playerAddress = playerAddresses[i];
            Players[playerAddress].player = playerAddress;
            Players[playerAddress].sum = 0;
            Players[playerAddress].currentState = PlayerState.beforeStand;
        }
    }

    function shuffle() public {
        uint256 deckSize = deck.length;
        cardState = CardState.Shuffling;
        for (uint256 i = 0; i < deckSize; i++) {
            uint256 j = uint256(
                keccak256(abi.encode(block.timestamp, block.coinbase, i))
            ) % deckSize;
            Card memory tmpCard = deck[i];
            deck[i] = deck[j];
            deck[j] = tmpCard;
        }
    }

    function generateDrawRequest() private {
        uint256 requestId = vrfConsumer.requestRandomWords();
        requestID = requestId;
    }

    function drawCard() public returns (uint8 suit, uint8 rank) {
        require(deck.length > 0, "No cards left in the deck");
        Card memory drawnCard = deck[deck.length - 1];
        (string memory first, string memory second) = splitString(
            randomNumbersString
        );
        uint8 index = stringToUint8(first);
        if (index > deck.length) {
            index = uint8(index % deck.length);
        }
        randomNumbersString = second;
        Card memory swap = deck[index];
        deck[index] = drawnCard;
        deck[deck.length - 1] = swap;
        suit = swap.suit;
        rank = swap.rank;
        deck.pop();
        return (suit, rank);
    }

    function fulfillDrawRequest() public {
        (bool fulfilled, uint256[] memory randomWords) = vrfConsumer
            .getRequestStatus(requestID);
        require(
            fulfilled == true,
            "Please hold on for a moment, transaction in progress. Try again later"
        );
        uint256 randomNumber = uint256(randomWords[0]);
        randomNumbersString = Strings.toString(randomNumber);
    }

    function splitString(string memory str)
        private
        pure
        returns (string memory, string memory)
    {
        require(bytes(str).length >= 2, "String is too short");

        // Convert string to bytes
        bytes memory strBytes = bytes(str);

        // Split at position 2
        bytes memory part1 = new bytes(2);
        for (uint256 i = 0; i < 2; i++) {
            part1[i] = strBytes[i];
        }

        // Split from position 2 to the end
        bytes memory part2 = new bytes(strBytes.length - 2);
        for (uint256 i = 2; i < strBytes.length; i++) {
            part2[i - 2] = strBytes[i];
        }

        // Convert bytes back to string
        return (string(part1), string(part2));
    }

    function stringToUint8(string memory str) private pure returns (uint8) {
        bytes memory b = bytes(str);
        require(b.length > 0, "Empty string");

        uint8 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            result = result * 10 + uint8(b[i]) - 48;
        }

        return result;
    }

    function drawFromDeck() public returns (uint8 suit, uint8 rank) {
        require(
            Players[msg.sender].currentState == PlayerState.beforeStand,
            "You cannot draw anymore cards."
        );
        require(deck.length > 0, "No cards left in the deck");
        Card memory tempCard = deck[deck.length - 1];
        (string memory first, string memory second) = splitString(
            randomNumbersString
        );
        uint8 index = stringToUint8(first);
        if (index > deck.length) {
            index = uint8(index % deck.length);
        }
        randomNumbersString = second;
        Card memory swap = deck[index];
        deck[index] = tempCard;
        deck[deck.length - 1] = swap;
        deck.pop();
        suit = swap.suit;
        rank = swap.rank;
        Players[msg.sender].hand.push(Card(suit, rank));
        if (
            Players[msg.sender].numAces >= 1 &&
            Players[msg.sender].sum + rank > 21
        ) {
            Players[msg.sender].sum -= 10;
            Players[msg.sender].numAces -= 1;
        }
        if (rank == 1) {
            if (Players[msg.sender].numAces >= 1) {
                Players[msg.sender].sum += 1;
                Players[msg.sender].numAces -= 1;
            } else {
                Players[msg.sender].sum += 11;
                Players[msg.sender].numAces += 1;
            }
        } else if (rank >= 10) {
            rank = 10;
            Players[msg.sender].sum += rank;
        } else {
            Players[msg.sender].sum += rank;
        }
    }

    function checkHand() public view returns (Card[] memory) {
        return Players[msg.sender].hand;
    }

    function totalSum(address player) public view returns (uint256 sum) {
        return Players[player].sum;
    }

    function clearHand(address player) public {
        delete Players[player].hand;
        Players[player].sum = 0;
    }

    function distributeCards(address[] memory players) public {
        cardState = CardState.Distributing;
        require(players.length > 0, "No players provided");
        require(
            deck.length >= players.length * 2,
            "Not enough cards for all players"
        );
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = 0; j < players.length; j++) {
                (uint8 suit, uint8 rank) = drawCard();
                Players[players[j]].hand.push(Card(suit, rank));
                if (rank == 1) {
                    if (Players[players[j]].numAces == 1) {
                        Players[players[j]].sum += 1;
                    } else {
                        Players[players[j]].sum += 11;
                        Players[players[j]].numAces += 1;
                    }
                } else if (rank >= 10) {
                    Players[players[j]].sum += 10;
                } else {
                    Players[players[j]].sum += rank;
                }
            }
        }
        cardState = CardState.Idling;
    }

    function stand() public {
        require(
            Players[msg.sender].currentState == PlayerState.beforeStand,
            "You are already in Stand state."
        );
        Players[msg.sender].currentState = PlayerState.Stand;
    }

    function getCardState() public view returns (CardState) {
        return cardState; // Query current card state
    }

    function showDealerFirst() public view returns (Card memory) {
        return Players[owner].hand[0];
    }

    function showDealerCards() public view returns (Card[] memory) {
        return Players[owner].hand;
    }
}
