// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./Deck.sol";
import "./BlockJackToken.sol";

contract BlockJackCasino {
    enum GamblingState {
        NotGambling,
        Gambling
    }

    struct Table {
        uint256 tableNumber;
        address[] players;
        mapping(address => uint256) playerBets;
        uint256 minimumBet;
        GamblingState gamblingState;
    }

    Deck deckContract;
    BlockJackToken blockJackTokenContract;
    Table public gamblingTable;
    address public dealerAddress;

    constructor(Deck deckContractAddress, BlockJackToken blockJackTokenAddress)
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

    function getBJT() public payable {
        //check BJT
        uint256 amount = blockJackTokenContract.getCredit(
            msg.sender,
            msg.value
        );
        emit buyCredit(amount);
    }

    function checkBJT() public view returns (uint256) {
        //check player wallet
        uint256 credits = blockJackTokenContract.checkCredit(msg.sender);
        return credits;
    }

    function setMinimumBet(uint256 minimumBet) public {
        //set minimum bet which can only be done by the owner of the contract
        require(
            msg.sender == dealerAddress,
            "Only dealers can set Minimum Bet."
        );
        gamblingTable.minimumBet = minimumBet;
    }

    function getMinimumBet() public view returns (uint256) {
        return gamblingTable.minimumBet;
    }

    function increaseBet(uint256 betAmount) public {
        require(gamblingTable.gamblingState == GamblingState.NotGambling, "You cannot increase your bet in the middle of a game");
        uint256 BJT = checkBJT();
        require(
            BJT >= betAmount,
            "You do not have enough tokens to increase bet."
        );
        gamblingTable.playerBets[msg.sender] += betAmount;
        blockJackTokenContract.transferCredit(dealerAddress, betAmount);
    }

    function getBet() public view returns (uint256 betAmount) {
        return gamblingTable.playerBets[msg.sender];
    }

    function getTableSize() public view returns (uint256) {
        //get Number of Players
        return gamblingTable.players.length;
    }

    function double() public {
        deckContract.drawCardDouble(msg.sender);
        gamblingTable.playerBets[msg.sender] *= 2;
    }

    //join table
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

    function gamble() public {
        require(
            msg.sender == dealerAddress,
            "Only dealers can initiate Gamble."
        );
        require(
            gamblingTable.gamblingState == GamblingState.NotGambling,
            "Gambling is in progress"
        );
        gamblingTable.gamblingState = GamblingState.Gambling;
        gamblingTable.players.push(msg.sender);
        deckContract.distributeCards(gamblingTable.players);
    }

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

    function endGamble() public {
        require(checkStatus(), "Table not ready for further processing");
        require(msg.sender == dealerAddress, "Only dealers can end gamble.");
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
                deckContract.getState(dealerAddress) && player != dealerAddress
            ) {
                blockJackTokenContract.transferCredit(
                    player,
                    maxBetAmount
                );
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
                player != dealerAddress && playerValue > sum && sum <= 21
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
                playerValue == sum &&
                sum <= 21 &&
                player != dealerAddress
            ) {
                emit dealerDraw(
                    player,
                    maxBetAmount,
                    playerValue,
                    sum,
                    "Dealer Draw"
                );
            }
            deckContract.beforeStand(player);
            deckContract.clearHand(player);
            gamblingTable.playerBets[player] = 0;
        }
        deckContract.clearHand(dealerAddress);
        gamblingTable.players = new address[](0);
        deckContract.beforeStand(dealerAddress);
    }
}
