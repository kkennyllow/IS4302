// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./VRFv2Consumer.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Deck is Ownable {
    struct Card {
        uint8 suit;
        uint8 rank;
    }

    enum PlayerState {
        beforeStand,
        Stand,
        BlackJack
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
    address public ownerAddress;
    address[] public Addresses;
    mapping(address => uint256) private lastActionTime;
    uint256 public constant ACTION_COOLDOWN = 2 seconds;

    //Initialises the consumer that is required for the random number and initialize a deck.
    // constructor(VRFv2Consumer vrfConsumerAddress) {
    //     vrfConsumer = vrfConsumerAddress;
    //     for (uint8 suit = 1; suit <= 4; suit++) {
    //         for (uint8 rank = 1; rank <= 13; rank++) {
    //             deck.push(Card(suit, rank));
    //         }
    //     }
    //     generateDrawRequest();
    //     ownerAddress = msg.sender;
    // }

    event Double(
        address indexed player,
        string message,
        uint256 rank,
        uint256 suit
    );
    event Hit(
        address indexed player,
        string message,
        uint256 rank,
        uint256 suit
    );
    event DistributeCard(address indexed player, string message);

    //Remove this
    constructor() Ownable(msg.sender) {
        // vrfConsumer = vrfConsumerAddress;
        for (uint8 suit = 1; suit <= 4; suit++) {
            for (uint8 rank = 1; rank <= 13; rank++) {
                deck.push(Card(suit, rank));
            }
        }
        string memory randomnumber = "1231238921739821232119498";
        randomNumbersString = randomnumber;
        ownerAddress = msg.sender;
    }

    function isRateLimited(address user) public view returns (bool) {
        return block.timestamp < lastActionTime[user] + ACTION_COOLDOWN;
    }

    modifier onlyDealer() {
        require(owner() == msg.sender || owner() == tx.origin, "Only dealers can call this function");
        _;
    }

    //Shuffle cards based on Fisher-Yates Algorithm.
    function shuffle() public onlyDealer  {
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

    //To make sure that all the cards are back in the deck
    function refreshDeck() onlyDealer public {
        delete deck;
        for (uint8 suit = 1; suit <= 4; suit++) {
            for (uint8 rank = 1; rank <= 13; rank++) {
                deck.push(Card(suit, rank));
            }
        }
    }

    //Generates a request from Chainlink
    // function generateDrawRequest() private {
    //     uint256 requestId = vrfConsumer.requestRandomWords();
    //     requestID = requestId;
    // }

    //Draw card that will be used for distribute cards function, no address is assigned here as opposed to drawCardFromDeck()
    function generateCard() public onlyDealer returns (uint8 suit, uint8 rank) {
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

    function double(address player) public {
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
        uint8 suit = swap.suit;
        uint8 rank = swap.rank;
        deck.pop();
        Players[player].hand.push(Card(suit, rank));
        Players[player].currentState = PlayerState.Stand;
        if (Players[player].numAces >= 1 && Players[player].sum + rank > 21) {
            Players[player].sum -= 10;
            Players[player].numAces -= 1;
        }
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
            } else if ( Players[msg.sender].sum + 11 > 21) {
                Players[msg.sender].sum += 1;
            } 
            else {
                Players[msg.sender].sum += 11;
                Players[msg.sender].numAces += 1;
            }
        } else if (rank >= 10) {
            rank = 10;
            Players[msg.sender].sum += rank;
        } else {
            Players[msg.sender].sum += rank;
        }
        emit Double(player, "Double", rank, suit);
    }

    //Assigns the fulfilled request to the string
    // function fulfillDrawRequest() public {
    //     (bool fulfilled, uint256[] memory randomWords) = vrfConsumer
    //         .getRequestStatus(requestID);
    //     require(
    //         fulfilled == true,
    //         "Please hold on for a moment, transaction in progress. Try again later"
    //     );
    //     uint256 randomNumber = uint256(randomWords[0]);
    //     randomNumbersString = Strings.toString(randomNumber);
    // }

    //Returns size of the deck, this helps ensure that deck is refreshed.
    function size() public view returns (uint256 length) {
        return deck.length;
    }

    //Splits the string so that we can use it for the swapping algorithm.
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

    //Draws a card that is directed to a particular address
    function hit() public returns (uint8 suit, uint8 rank) {
        require(!isRateLimited(msg.sender), "Action rate limited");
        lastActionTime[msg.sender] = block.timestamp;
        require(
            totalSum(msg.sender) < 21,
            "You have already exceeded the limit"
        );
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
            } else if ( Players[msg.sender].sum + 11 > 21) {
                Players[msg.sender].sum += 1;
            } 
            else {
                Players[msg.sender].sum += 11;
                Players[msg.sender].numAces += 1;
            }
        } else if (rank >= 10) {
            rank = 10;
            Players[msg.sender].sum += rank;
        } else {
            Players[msg.sender].sum += rank;
        }
        emit Hit(msg.sender, "Hit", rank, suit);
    }

    function checkHand() public view returns (Card[] memory) {
        return Players[msg.sender].hand;
    }

    function getState(address player) public view returns (PlayerState) {
        return Players[player].currentState;
    }

    function totalSum(address player) public view returns (uint256 sum) {
        return Players[player].sum;
    }

    function clearHand(address player) public {
        delete Players[player].hand;
        Players[player].sum = 0;
    }

    function distributeCards(address[] memory players) public  onlyDealer{
        cardState = CardState.Distributing;
        require(players.length > 0, "No players provided");
        require(
            deck.length >= players.length * 2,
            "Not enough cards for all players"
        );
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = 0; j < players.length; j++) {
                (uint8 suit, uint8 rank) = generateCard();
                Players[players[j]].hand.push(Card(suit, rank));
                if (rank == 1) {
                    if (Players[players[j]].numAces == 1) {
                        Players[players[j]].sum += 1;
                    } else {
                        Players[players[j]].sum += 11;
                        Players[players[j]].numAces += 1;
                        if (Players[players[j]].sum == 21) {
                            Players[players[j]].currentState = PlayerState
                                .BlackJack;
                        }
                    }
                } else if (rank >= 10) {
                    Players[players[j]].sum += 10;
                    if (Players[players[j]].sum == 21) {
                        Players[players[j]].currentState = PlayerState
                            .BlackJack;
                    }
                } else {
                    Players[players[j]].sum += rank;
                }
                if (i == 1) {
                    address playerAddress = Players[players[j]].player;
                    emit DistributeCard(playerAddress, "Distributed Cards");
                }
            }
        }
        cardState = CardState.Idling;
    }

    function beforeStand(address player) public {
        Players[player].currentState = PlayerState.beforeStand;
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

    function showDealerFirst(address players)
        public
        view
        returns (Card memory)
    {
        return Players[players].hand[0];
    }

    function checkState() public view returns (bool) {
        for (uint256 i = 0; i < Addresses.length; i++) {
            address player = Addresses[i];
            if (Players[player].currentState == PlayerState.beforeStand) {
                return false;
            }
        }
        return true;
    }

    function showDealerCards() public view returns (Card[] memory) {
        require(checkState(), "Not everyone is in stand");
        return Players[ownerAddress].hand;
    }
}
