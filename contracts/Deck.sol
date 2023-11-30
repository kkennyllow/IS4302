// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./VRFv2Consumer.sol";

contract Deck {
    struct Card {
        uint8 suit;
        uint8 rank;
    }

    struct Player {
        address player;
        Card[] hand;
        uint256 size;
        uint256 sum;
    }
    VRFv2Consumer public vrfConsumer;
    Card[] public deck;
    uint256 public requestID;
    mapping(address => Player) public Players;

    constructor(VRFv2Consumer vrfConsumerAddress) {
        vrfConsumer = vrfConsumerAddress;
        for (uint8 suit = 1; suit <= 4; suit++) {
            for (uint8 rank = 1; rank <= 13; rank++) {
                deck.push(Card(suit, rank));
            }
        }
    }

    function shuffle() public {
        uint256 deckSize = deck.length;
        for (uint256 i = 0; i < deckSize; i++) {
            uint256 j = uint256(
                keccak256(abi.encode(block.timestamp, block.coinbase, i))
            ) % deckSize;
            Card memory tmpCard = deck[i];
            deck[i] = deck[j];
            deck[j] = tmpCard;
        }
    }

    function generateDrawRequest() external payable {
        uint256 requestId = vrfConsumer.requestRandomWords();
        requestID = requestId;
    }

    function drawCard() public returns (uint8 suit, uint8 rank) {
        require(deck.length > 0, "No cards left in the deck");
        Card memory drawnCard = deck[deck.length - 1];
        suit = drawnCard.suit;
        rank = drawnCard.rank;
        deck.pop();
    }

    function drawFromDeck() public returns (uint8 suit, uint8 rank) {
        (bool fulfilled, uint256[] memory randomWords) = vrfConsumer
            .getRequestStatus(requestID);
        require(
            fulfilled == true,
            "Please hold on for a moment, transaction in progress. Try again later"
        );
        require(deck.length > 0, "No cards left in the deck");
        require(
            Players[msg.sender].size <= 5,
            "Cannot draw more than 5 cards."
        );
        Card memory drawnCard = deck[deck.length - 1];
        uint8 index = uint8(randomWords[0] % deck.length);
        Card memory tmpCard = deck[index];
        deck[index] = deck[deck.length - 1];
        deck[deck.length - 1] = tmpCard;
        drawnCard = deck[deck.length - 1];
        deck.pop();
        suit = drawnCard.suit;
        rank = drawnCard.rank;
        Players[msg.sender].hand.push(Card(suit, rank));
        if (rank >= 10) {
            rank = 10;
        }
        Players[msg.sender].sum += rank;
        Players[msg.sender].size += 1;
    }

    function checkHand() public view returns (Card[] memory) {
        return Players[msg.sender].hand;
    }

    function handSize() public view returns (uint256 size) {
        return Players[msg.sender].size;
    }

    function totalSum() public view returns (uint256 sum) {
        return Players[msg.sender].sum;
    }

    function distributeCards(address[] memory players) public {
        require(players.length > 0, "No players provided");
        require(
            deck.length >= players.length * 2,
            "Not enough cards for all players"
        );
        shuffle();
        for (uint256 i = 0; i < players.length; i++) {
            uint256 playerSum = 0;
            for (uint256 j = 0; j < 2; j++) {
                (uint8 suit, uint8 rank) = drawCard();
                Players[players[i]].hand.push(Card(suit, rank));
                if (rank >= 10) {
                    playerSum += 10;
                } else {
                    playerSum += rank;
                }
            }
            Players[players[i]].size = 2;
            Players[players[i]].sum = playerSum;
        }
    }
}
