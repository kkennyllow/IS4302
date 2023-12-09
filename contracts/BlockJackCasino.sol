// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./Deck.sol";
import "./BlockJackToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BlockJackCasino is Ownable {
    enum GamblingState {
        NotGambling,
        Gambling
    }

    struct Table {
        address[] players;
        mapping(address => uint256) playerBets;
        uint256 minimumBet;
        GamblingState gamblingState;
    }

    Deck deckContract;
    BlockJackToken blockJackTokenContract;
    Table public gamblingTable;
    address public dealerAddress;

    mapping(address => bytes32) private commitments;
    mapping(address => uint256) public revealedBets;
    mapping(address => uint256) private lastActionTime;

    uint256 public commitmentDeadline;
    uint256 public constant ACTION_COOLDOWN = 2 seconds; 
    uint256 public constant COMMITMENT_WINDOW_DURATION = 30 seconds;

    constructor(Deck deckContractAddress, BlockJackToken blockJackTokenAddress)
        Ownable(msg.sender)
    {
        deckContract = deckContractAddress;
        blockJackTokenContract = blockJackTokenAddress;
        dealerAddress = msg.sender;
    }

    event buyCredit(uint256 amount); //buying token for BlockJack
    event dealerLost(
        address indexed winner,
        uint256 amount,
        uint256 winnerSum,
        uint256 loserSum,
        string message
    );
    event dealerWon(
        address indexed loser,
        uint256 amount,
        uint256 winnerSum,
        uint256 loserSum,
        string message
    );
    event dealerDraw(
        address indexed winner,
        uint256 amount,
        uint256 winnerSum,
        uint256 loserSum,
        string message
    );
    event dealerBlow(uint256 count, string message);
    event BlackJack(string message);

     /**
     * @dev Modifier to restrict the execution of a function to only the owner (dealer) of the contract.
     * Throws an error if the caller is not the owner.
     */
    modifier onlyDealer() {
        require(owner() == _msgSender(), "Only dealers can call this function");
        _;
    }
     /**
     * @dev Checks if a user is rate-limited based on the last action timestamp.
     * Users are rate-limited to prevent frequent actions within a cooldown period.
     * @param user The address of the user to check for rate limitation.
     * @return A boolean indicating whether the user is currently rate-limited or not.
     */
    function isRateLimited(address user) public view returns (bool) {
        return block.timestamp < lastActionTime[user] + ACTION_COOLDOWN;
    }

     /**
     * @dev Allows users to purchase BlockJackToken (BJT) by sending Ether.
     * The Ether sent is converted to BJT based on the current conversion rate.
     * The BJT is then credited to the user's account using the ERC20 contract.
     * @notice Users must include enough Ether to cover the desired BJT amount.
     */
    function getBJT() public payable {
        uint256 amount = blockJackTokenContract.getCredit{value: msg.value}(msg.sender);
        emit buyCredit(amount);
    }

    /**
    * @dev Retrieves the current BlockJackToken (BJT) balance of the caller.
    * @return The amount of BlockJackToken (BJT) credited to the caller's account.
    */
    function checkBJT() public view returns (uint256) {
        uint256 credits = blockJackTokenContract.checkCredit(msg.sender);
        return credits;
    }

    /**
     * @dev Sets the minimum bet amount for the gambling table. Only the dealer can invoke this function.
     * @param minimumBet The new minimum bet amount to be set for the gambling table.
     */
    function setMinimumBet(uint256 minimumBet) public onlyDealer {
        gamblingTable.minimumBet = minimumBet;
    }

    /**
     * @dev Retrieves the current minimum bet amount for the gambling table.
     * @return The current minimum bet amount.
     */
    function getMinimumBet() public view returns (uint256) {
        return gamblingTable.minimumBet;
    }

    /**
    * @dev Initiates the betting phase by setting the commitment deadline.
    * Only the contract owner can call this function.
    */
    function startBettingPhase() public onlyOwner {
        commitmentDeadline = block.timestamp + COMMITMENT_WINDOW_DURATION;
    }
    
     /**
     * @dev Creates a commitment hash based on the provided bet amount and nonce.
     * This hash is used during the betting phase for secure commitment.
     *
     * @param betAmount The amount of the bet.
     * @param nonce A unique value to enhance the security of the commitment.
     * @return bytes32 The commitment hash.
     */
    function createCommitment(uint256 betAmount, uint256 nonce) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(betAmount, nonce));
    }

   /**
     * @dev Players commit their increased bet as a hash during the commitment phase.
     * This hash is used for secure commitment and is only applicable if players wish to increase their bet.
     *
     * @param hashCommitment The commitment hash representing the increased bet.
     */
    function commitIncreaseBet(bytes32 hashCommitment) public {
        require(!isRateLimited(msg.sender), "Action rate limited");
        require(gamblingTable.gamblingState == GamblingState.NotGambling, "Betting phase is over");
        require(block.timestamp < commitmentDeadline, "Commitment phase over");
        lastActionTime[msg.sender] = block.timestamp;   
        commitments[msg.sender] = hashCommitment;
    }

     /**
     * @dev Players reveal their previously committed increased bet during the reveal phase.
     * This is used to verify and process the increased bet.
     *
     * @param betAmount The actual bet amount that the player intends to increase to.
     * @param nonce A unique number to ensure the uniqueness of the commitment.
     *
     * Requirements:
     * - The player must not be rate-limited.
     * - A commitment must exist for the player.
     * - The revealed bet must match the commitment.
     */
    function revealIncreaseBet(uint256 betAmount, uint256 nonce) public {
        require(!isRateLimited(msg.sender), "Action rate limited");
        require(commitments[msg.sender] != 0, "No commitment found");
        require(keccak256(abi.encodePacked(betAmount, nonce)) == commitments[msg.sender], "Bet does not match commitment");
        lastActionTime[msg.sender] = block.timestamp;   
        revealedBets[msg.sender] = betAmount;
        commitments[msg.sender] = 0; // Reset commitment
        increaseBet(betAmount);
    }

     /**
     * @dev Increases the player's bet amount during the betting phase.
     *
     * @param betAmount The amount by which the player wants to increase their bet.
     *
     * Requirements:
     * - The gambling state must be 'NotGambling'.
     * - The player must have sufficient BlockJack Tokens (BJT) to cover the increased bet.
     * - The player cannot increase the bet in the middle of a game.
     *
     * Effects:
     * - Updates the player's bet amount in the gambling table.
     * - Transfers the increased bet amount to the dealer.
     */
    function increaseBet(uint256 betAmount) private {
        require(gamblingTable.gamblingState == GamblingState.NotGambling, "You cannot increase your bet in the middle of a game");
        uint256 BJT = checkBJT();
        require(
            BJT >= betAmount,
            "You do not have enough tokens to increase bet."
        );
        gamblingTable.playerBets[msg.sender] += betAmount;
        blockJackTokenContract.transferCredit(dealerAddress, betAmount);
    }

    /**
     * @dev Retrieves the current bet amount of the player.
     *
     * @return betAmount ,The current bet amount of the player.
     */
    function getBet() public view returns (uint256 betAmount) {
        return gamblingTable.playerBets[msg.sender];
    }

     /**
     * @dev Retrieves the current number of players seated at the gambling table.
     *
     * @return The number of players at the gambling table.
     */
    function getTableSize() public view returns (uint256) {
        return gamblingTable.players.length;
    }

     /**
     * @dev Doubles the current bet of the calling player and initiates the double action in the deck.
     *      Transfers the original bet amount to the dealer and updates the player's bet accordingly.
     */
    function double() public {
        uint256 betAmount = getBet();
        blockJackTokenContract.transferCredit(dealerAddress, betAmount);
        gamblingTable.playerBets[msg.sender] *= 2;
        deckContract.double(msg.sender);
    }

    /**
     * @dev Allows a player to join the BlockJack table, provided the table is not in an active game state.
     *      Players, excluding the dealer, can join the table, subject to player limits.
     *      The joining player must meet the minimum bet requirement set by the owner.
     *      The player's bet is initialized to the minimum bet, and the corresponding tokens are transferred to the dealer.
     */
    function joinTable() public {
        require(
            msg.sender != dealerAddress,
            "Dealer cannot join table, start gamble instead"
        );
        uint256 playersOnTable = getTableSize();
        require(
            playersOnTable + 1 <= 7,
            "Too many players are at this table. Pick another table."
        );
        require(
            gamblingTable.gamblingState == GamblingState.NotGambling,
            "You cannot join a table that is in game."
        );
        uint256 minimumBet = getMinimumBet();
        require(minimumBet > 0, "Owner has not set the minimum bet");
        uint256 playerWallet = checkBJT();
        require(
            minimumBet <= playerWallet,
            "You have too little tokens to join this table."
        );
        gamblingTable.players.push(msg.sender);
        gamblingTable.playerBets[msg.sender] = minimumBet;
        blockJackTokenContract.transferCredit(dealerAddress, minimumBet);
    }

    /**
     * @dev Allows a player to leave the Blockjack table, provided the table is not in an active game state.
     *      Players can leave the table when it is not in an active gambling state.
     *      The player's seat is vacated, and their bet is reset to zero.
     */
    function leaveTable() public {
        require(
            gamblingTable.gamblingState == GamblingState.NotGambling,
            "You cannot leave a table when it is in game."
        );
        uint256 length = getTableSize();
        uint256 index = 0;
        for (uint256 i = 0; i < length; i++) {
            if (gamblingTable.players[i] == msg.sender) {
                index = i;
            }
        }
        gamblingTable.players[index] = gamblingTable.players[length - 1];
        gamblingTable.players.pop();
        gamblingTable.playerBets[msg.sender] = 0;
    }

    /**
     * @dev Initiates the gambling phase in the Blockjack game, allowing players to place their bets and start playing.
     *      Only the dealer can initiate the gambling phase.
     *      The function checks if gambling is not already in progress and sets the game state to Gambling.
     *      Players are added to the table, and the dealer shuffles and distributes cards.
     */
    function gamble() public  onlyDealer {
        require(
            gamblingTable.gamblingState == GamblingState.NotGambling,
            "Gambling is in progress"
        );
        gamblingTable.gamblingState = GamblingState.Gambling;
        gamblingTable.players.push(msg.sender);
        deckContract.shuffle(); //Here remove if using metamask
        deckContract.distributeCards(gamblingTable.players);
    }

    
     /**
     * @dev Checks the status of all players on the gambling table to determine if they have all reached the 'Stand' state.
     * @return check A boolean indicating whether all players are in the 'Stand' state.
     */
    function checkStatus() public view returns (bool check) {
        uint256 players = getTableSize();
        for (uint256 i = 0; i < players; i++) {
            Deck.PlayerState state = deckContract.getState(
                gamblingTable.players[i]
            );
            if (state == Deck.PlayerState.beforeStand) {
                return false;
            }
        }
        return true;
    }

    /**
     * @dev Ends the gambling round, processes the results, and distributes winnings or losses accordingly.
     * Only the dealer can call this function.
     * Emits events for various outcomes, such as BlackJack, Dealer blow, Dealer lost, Player blow, Dealer won, and Dealer/Player draw.
     * Resets player states, clears hands, and refreshes the deck for the next round.
     */
    function endGamble() public onlyDealer {
        require(checkStatus(), "Table not ready for further processing");
        gamblingTable.gamblingState = GamblingState.NotGambling;
        uint256 sum = deckContract.totalSum(dealerAddress);
        uint256 players = getTableSize();
        uint256 minimumBet = getMinimumBet();
        for (uint256 i = 0; i < players; i++) {
            uint256 maxBetAmount = 0;
            uint256 playerValue = deckContract.totalSum(
                gamblingTable.players[i]
            );
            Deck.PlayerState state = deckContract.getState(
                gamblingTable.players[i]
            );
            address player = gamblingTable.players[i];
            uint256 betAmount = gamblingTable.playerBets[player];
            maxBetAmount = betAmount > minimumBet ? betAmount : minimumBet;
            //Player and Dealer Blackjack
            if (
                state == Deck.PlayerState.BlackJack &&
                Deck.PlayerState.BlackJack ==
                deckContract.getState(dealerAddress) &&
                player != dealerAddress
            ) {
                blockJackTokenContract.transferCredit(player, maxBetAmount);
                emit BlackJack("Player and Dealer Blackjack");
            }
            //Blackjack case
            else if (
                state == Deck.PlayerState.BlackJack && player != dealerAddress
            ) {
                maxBetAmount = (maxBetAmount * 3) / 2;
                blockJackTokenContract.transferCredit(player, maxBetAmount);
                emit BlackJack("Player Blackjack");
            }
            //Player and Dealer Blow
            else if (playerValue > 21 && sum > 21 && player != dealerAddress) {
                blockJackTokenContract.transferCredit(player, maxBetAmount);
                emit dealerBlow(sum, "Dealer Blow");
            }
            //Dealer Blow
            else if (sum > 21 && player != dealerAddress) {
                maxBetAmount *= 2;
                blockJackTokenContract.transferCredit(player, maxBetAmount);
                emit dealerBlow(sum, "Dealer Blow");
            }
            // Dealer lose
            else if (
                player != dealerAddress && playerValue > sum && playerValue <= 21
            ) {
                maxBetAmount *= 2;
                blockJackTokenContract.transferCredit(player, maxBetAmount);
                emit dealerLost(
                    player,
                    maxBetAmount,
                    playerValue,
                    sum,
                    "Dealer Lost"
                );
            //Player Blow
            } else if ( player != dealerAddress && playerValue > 21
            ) {
                emit dealerWon(
                    player,
                    maxBetAmount,
                    sum,
                    playerValue,
                    "Player Blow"
                );
            }
            //Player lose
            else if (
                player != dealerAddress && sum > playerValue && sum <= 21
            ) {
                emit dealerWon(
                    player,
                    maxBetAmount,
                    sum,
                    playerValue,
                    "Dealer Won"
                );
            }
            //Player and Dealer Draw
            else if (
                playerValue == sum && sum <= 21 && player != dealerAddress
            ) {
                emit dealerDraw(
                    player,
                    maxBetAmount,
                    playerValue,
                    sum,
                    "Dealer Draw"
                );
                blockJackTokenContract.transferCredit(player, maxBetAmount);
            }
            deckContract.beforeStand(player);
            deckContract.clearHand(player);
            gamblingTable.playerBets[player] = 0;
        }
        deckContract.clearHand(dealerAddress);
        gamblingTable.players = new address[](0);
        deckContract.beforeStand(dealerAddress);
        deckContract.refreshDeck();
    }
}
