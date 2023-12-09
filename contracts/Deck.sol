// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

//Importing necessary contracts and libraries
import "./VRFv2Consumer.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

//Main contract for managing the Deck and card game logic
contract Deck is Ownable {
    //Structure to represent a card
    struct Card {
        uint8 suit;
        uint8 rank;
    }
    //Enum to represent the state of a player
    enum PlayerState {
        beforeStand,
        Stand,
        BlackJack
    }
    //Enum to represent the state of the card deck
    enum CardState {
        Shuffling,
        Distributing,
        Idling
    }
    //Structure to represent a player
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

    /**
     * @dev Constructs a new BlockJack Casino deck, initializing the VRF consumer
     * and populating the deck with a standard set of 52 cards (4 suits with ranks
     * from 1 to 13). It also generates the initial Chainlink VRF request to obtain
     * random numbers for shuffling the deck. The address deploying this contract
     * becomes the owner of the casino.
     *
     * @param vrfConsumerAddress The address of the VRF (Verifiable Random Function) consumer
     * contract used to fetch random numbers for card shuffling.
     */
    constructor(VRFv2Consumer vrfConsumerAddress) Ownable(msg.sender) {
        vrfConsumer = vrfConsumerAddress;
        for (uint8 suit = 1; suit <= 4; suit++) {
            for (uint8 rank = 1; rank <= 13; rank++) {
                deck.push(Card(suit, rank));
            }
        }
        //Generate the initial Chainlink VRF request
        generateDrawRequest();
        ownerAddress = msg.sender;
    }

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
    event InitializePlayer(address indexed, string message);

   /**
     * @dev Checks whether a user is currently rate-limited based on a cooldown period.
     *
     * @param user The address of the user to check for rate limiting.
     * @return A boolean indicating whether the user is currently rate-limited.
     */
    function isRateLimited(address user) public view returns (bool) {
        return block.timestamp < lastActionTime[user] + ACTION_COOLDOWN;
    }

    /**
     * @dev Modifier that restricts access to functions only to authorized dealers.
     * Authorized dealers include the contract owner and the transaction originator.
     */
    modifier onlyDealer() {
        require(
            owner() == msg.sender || owner() == tx.origin,
            "Only dealers can call this function"
        );
        _;
    }

     /**
     * @dev Initializes players for a new round in BlockJack Casino.
     * Players are provided with an array of addresses, and each player's state
     * is set to "beforeStand," indicating the start of their turn.
     * The function emits an `InitializePlayer` event for each initialized player.
     *
     * @param playerAddresses An array of player addresses to be initialized.
     */
    function initializePlayers(address[] memory playerAddresses) public onlyDealer {
        for (uint256 i = 0; i < playerAddresses.length; i++) {
            address playerAddress = playerAddresses[i];
            Players[playerAddress].player = playerAddress;
            Players[playerAddress].sum = 0;
            Players[playerAddress].currentState = PlayerState.beforeStand;
            Addresses.push(playerAddress);
            emit InitializePlayer(playerAddress, "Player Initialized");
        }
    }

     /**
     * @dev Shuffles the deck using the Fisher-Yates algorithm.
     * The function can only be called by the dealer and sets the card state to "Shuffling."
     * It iterates through the deck, swapping each card with a randomly selected card,
     * providing a shuffled deck for the subsequent distribution of cards.
     */
    function shuffle() public onlyDealer {
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

     /**
     * @dev Refreshes the deck by clearing the existing deck and initializing a new one.
     * The function can only be called by the dealer.
     * It deletes all cards from the current deck and populates a new deck with standard playing cards.
     */
    function refreshDeck() public onlyDealer {
        delete deck;
        for (uint8 suit = 1; suit <= 4; suit++) {
            for (uint8 rank = 1; rank <= 13; rank++) {
                deck.push(Card(suit, rank));
            }
        }
    }

    /**
     * @dev Generates a Chainlink VRF (Verifiable Random Function) request for drawing random words.
     * The request ID is stored for later fulfillment.
     * The function is marked as private to ensure it can only be called internally.
     */
    function generateDrawRequest() private {
        uint256 requestId = vrfConsumer.requestRandomWords();
        requestID = requestId;
    }

    /**
     * @dev Generates a card by swapping a randomly selected card from the deck.
     * The function ensures that the deck is not empty and performs the card swap using random numbers.
     * Only the dealer is allowed to call this function.
     *
     * @return suit The suit of the generated card.
     * @return rank The rank of the generated card.
     */
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

     /**
     * @dev Facilitates the stand action for a specified player in the BlockJack Casino.
     * This function draws one additional card for the player, after which the player
     * is automatically put into the stand state. Emits a `Double` event with details of the drawn card.
     *
     * @param player The address of the player initiating the double action.
     */
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
            Players[player].numAces >= 1 &&
            Players[player].sum + rank > 21
        ) {
            Players[player].sum -= 10;
            Players[player].numAces -= 1;
        }
        if (rank == 1) {
            if (Players[player].numAces >= 1) {
                Players[player].sum += 1;
                Players[player].numAces -= 1;
            } else if (Players[player].sum + 11 > 21) {
                Players[player].sum += 1;
            } else {
                Players[player].sum += 11;
                Players[player].numAces += 1;
            }
        } else if (rank >= 10) {
            rank = 10;
            Players[player].sum += rank;
        } else {
            Players[player].sum += rank;
        }
        emit Double(player, "Double", rank, suit);
    }

     /**
     * @dev Fulfills the Chainlink VRF draw request, updating the random number string for card shuffling.
     * Checks the status of the request and ensures it has been fulfilled before updating the random number.
     * If the request is still in progress, the function reverts with a message to try again later.
     */
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

    /**
     * @dev Retrieves the current size of the deck.
     * @return length The number of cards remaining in the deck.
     */
    function size() public view returns (uint256 length) {
        return deck.length;
    }

     /**
     * @dev Splits a given string into two parts at position 2.
     * @param str The input string to be split.
     * @return part1 The first part of the split string.
     * @return part2 The second part of the split string.
     */
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

     /**
     * @dev Converts a string to a uint8 by interpreting its ASCII characters as digits.
     * @param str The input string to be converted.
     * @return result The uint8 representation of the input string.
     */
    function stringToUint8(string memory str) private pure returns (uint8) {
        bytes memory b = bytes(str);
        require(b.length > 0, "Empty string");

        uint8 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            result = result * 10 + uint8(b[i]) - 48;
        }

        return result;
    }

   /**
     * @dev Initiates a hit action in the BlockJack game, drawing a card for the player.
     * @return suit The suit of the drawn card.
     * @return rank The rank of the drawn card.
     */
    function hit() public returns (uint8 suit, uint8 rank) {
        require(!isRateLimited(msg.sender), "Action rate limited");
        require( Players[msg.sender].sum < 21 ,"You have already reach more than 21 points or 21 points.");
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
            } else if (Players[msg.sender].sum + 11 > 21) {
                Players[msg.sender].sum += 1;
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
        emit Hit(msg.sender, "Hit", rank, suit);
    }

    /**
     * @dev Retrieves the current hand of cards for the calling player in the BlockJack game.
     * @return An array of Card structs representing the player's hand.
     */
    function checkHand() public view returns (Card[] memory) {
        return Players[msg.sender].hand;
    }

    /**
     * @dev Retrieves the current state of the specified player in the BlockJack game.
     * @param player The address of the player whose state is to be retrieved.
     * @return A value of the `PlayerState` enum indicating the current state of the player.
     */
    function getState(address player) public view returns (PlayerState) {
        return Players[player].currentState;
    }

     /**
     * @dev Retrieves the total sum of card values held by the specified player in the BlockJack game.
     * @param player The address of the player whose total card sum is to be retrieved.
     * @return sum representing the total sum of card values held by the player.
     */
    function totalSum(address player) public view returns (uint256 sum) {
        return Players[player].sum;
    }

     /**
     * @dev Clears the hand of the specified player in the BlockJack Casino game.
     * @param player The address of the player whose hand is to be cleared.
     */
    function clearHand(address player) public {
        delete Players[player].hand;
        Players[player].sum = 0;
    }

     /**
     * @dev Distributes cards to the specified players in the BlockJack Casino game.
     * @param players An array of player addresses to whom the cards will be distributed.
     * Emits `DistributeCard` event for each player after the second card is distributed.
     * Players achieving Blackjack state during distribution are marked accordingly.
     */
    function distributeCards(address[] memory players) public onlyDealer {
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
     /**
     * @dev Transitions the current state of the calling player to 'Stand' in the BlockJack Casino game.
     * This state indicates that the player has chosen to stand, concluding their turn without drawing additional cards.
     * Players in the 'Stand' state cannot make further strategic decisions during the game round.
     * Emits a 'Stand' event to signal the player's action.
     * @notice Only players in the 'beforeStand' state can execute this function.
     */
    function stand() public {
        require(
            Players[msg.sender].currentState == PlayerState.beforeStand,
            "You are already in Stand state."
        );
        Players[msg.sender].currentState = PlayerState.Stand;
    }

     /**
     * @dev Retrieves the current state of the card deck in the BlockJack Casino game.
     * Possible states include 'Idling', 'Distributing', and 'Shuffling'.
     * @return Current state of the card deck.
     */
    function getCardState() public view returns (CardState) {
        return cardState; // Query current card state
    }

    /**
     * @dev Retrieves the first card in the dealer's hand in the BlockJack Casino game.
     * Only the rank and suit of the card are returned.
     * @param players The address of the dealer.
     * @return The first card in the dealer's hand.
     */
    function showDealerFirst(address players)
        public
        view
        returns (Card memory)
    {
        return Players[players].hand[0];
    }
     /**
     * @dev Allows the dealer to set a player's game state to 'beforeStand' in preparation for a new game.
     * Only the dealer can invoke this function.
     * 
     * @param player The address of the player whose game state is being set.
     */
    function beforeStand(address player) public onlyDealer {
        Players[player].currentState = PlayerState.beforeStand;
    }

    /**
     * @dev Checks if all players in the BlockJack Casino game have reached the 'Stand' state.
     * This function is used to determine whether all players have completed their turn.
     * @return A boolean indicating whether all players are in the 'Stand' state.
     */
    function checkState() public view returns (bool) {
        for (uint256 i = 0; i < Addresses.length; i++) {
            address player = Addresses[i];
            if (Players[player].currentState == PlayerState.beforeStand) {
                return false;
            }
        }
        return true;
    }

      /**
     * @dev Retrieves the current hand of the dealer in the BlockJack Casino game.
     * This function ensures that all players have reached the 'Stand' state before revealing the dealer's cards.
     * @return An array of Card structures representing the dealer's hand.
     * @dev Throws an error if not all players are in the 'Stand' state.
     */
    function showDealerCards() public view returns (Card[] memory) {
        require(checkState(), "Not everyone is in stand");
        return Players[ownerAddress].hand;
    }
}
