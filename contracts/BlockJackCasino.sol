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
    mapping(uint256 => Table) public tables;
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

    function setMinimumBet(uint256 table, uint256 minimumBet) public {
        //set minimum bet which can only be done by the owner of the contract
        require(
            msg.sender == dealerAddress,
            "Only dealers can set Minimum Bet."
        );
        tables[table].minimumBet = minimumBet;
    }

    function getMinimumBet(uint256 table) public view returns (uint256) {
        return tables[table].minimumBet;
    }

    function increaseBet(uint256 betAmount, uint256 table) public {
        uint256 BJT = checkBJT();
        require(
            BJT >= betAmount,
            "You do not have enough tokens to increase bet."
        );
        tables[table].playerBets[msg.sender] += betAmount;
        blockJackTokenContract.transferCredit(dealerAddress, betAmount);
    }

    function getTableSize(uint256 table) public view returns (uint256) {
        //get Number of Players
        return tables[table].players.length;
    }

    function double(uint256 tableNumber) public {
        deckContract.drawCardDouble(msg.sender);
        tables[tableNumber].playerBets[msg.sender] *= 2;
    }

    function joinTable(uint256 table) public {
        //join table
        uint256 playersOnTable = getTableSize(table);
        require(
            playersOnTable + 1 <= 7,
            "Too many players are at this table. Pick another table."
        );
        require(
            tables[table].gamblingState == GamblingState.NotGambling,
            "You cannot join a table that is in game."
        );
        uint256 minimumBet = getMinimumBet(table);
        require(minimumBet > 0, "Owner has not set the minimum bet");
        uint256 playerWallet = checkBJT();
        require(
            minimumBet <= playerWallet,
            "You have too little tokens to join this table."
        );
        tables[table].players.push(msg.sender);
        tables[table].playerBets[msg.sender] = minimumBet;
        blockJackTokenContract.transferCredit(dealerAddress, minimumBet);
    }

    function leaveTable(uint256 table) public {
        require(
            tables[table].gamblingState == GamblingState.NotGambling,
            "You cannot leave a table when it is in game."
        );
        uint256 length = getTableSize(table);
        uint256 index = 0;
        for (uint256 i = 0; i < length; i++) {
            if (tables[table].players[i] == msg.sender) {
                index = i;
            }
        }
        tables[table].players[index] = tables[table].players[length - 1];
        tables[table].players.pop();
    }

    function gamble(uint256 table) public {
        require(
            msg.sender == dealerAddress,
            "Only dealers can initiate Gamble."
        );
        tables[table].gamblingState = GamblingState.NotGambling;
        tables[table].players.push(msg.sender);
        deckContract.distributeCards(tables[table].players);
    }

    function checkStatus(uint256 table) public view returns (bool check) {
        uint256 players = getTableSize(table);
        for (uint256 i = 0; i < players; i++) {
            Deck.PlayerState state = deckContract.getState(
                tables[table].players[i]
            );
            if (state == Deck.PlayerState.beforeStand) {
                return false;
            }
        }
        return true;
    }

    function endGamble(uint256 table) public {
        require(checkStatus(table), "Table not ready for further processing");
        require(msg.sender == dealerAddress, "Only dealers can end gamble.");
        tables[table].gamblingState = GamblingState.NotGambling;
        uint256 sum = deckContract.totalSum(dealerAddress);
        uint256 players = getTableSize(table);
        uint256 minimumBet = getMinimumBet(table);
        for (uint256 i = 0; i < players; i++) {
            uint256 maxBetAmount = 0;
            uint256 playerValue = deckContract.totalSum(
                tables[table].players[i]
            );
            Deck.PlayerState state = deckContract.getState(
                tables[table].players[i]
            );
            address player = tables[table].players[i];
            uint256 betAmount = tables[table].playerBets[player];
            maxBetAmount = betAmount > minimumBet ? betAmount : minimumBet;
            //Player and Dealer Blackjack
            if (
                state == Deck.PlayerState.BlackJack &&
                Deck.PlayerState.BlackJack ==
                deckContract.getState(dealerAddress)
            ) {
                blockJackTokenContract.transferCredit(
                    tables[table].players[i],
                    maxBetAmount
                );
                deckContract.clearHand(tables[table].players[i]);
                deckContract.beforeStand(tables[table].players[i]);
            }
            //Blackjack case
            else if (
                state == Deck.PlayerState.BlackJack &&
                tables[table].players[i] != dealerAddress
            ) {
                maxBetAmount = (maxBetAmount * 3) / 2;
                blockJackTokenContract.transferCredit(
                    tables[table].players[i],
                    maxBetAmount
                );
                deckContract.beforeStand(tables[table].players[i]);
            }
            //Player and Dealer Blow
            else if (playerValue > 21 && sum > 21) {
                blockJackTokenContract.transferCredit(
                    tables[table].players[i],
                    maxBetAmount
                );
                deckContract.clearHand(tables[table].players[i]);
                emit dealerBlow(sum, "Dealer Blow");
                deckContract.beforeStand(tables[table].players[i]);
            }
            //Dealer Blow
            else if (sum > 21 && tables[table].players[i] != dealerAddress) {
                maxBetAmount *= 2;
                blockJackTokenContract.transferCredit(
                    tables[table].players[i],
                    maxBetAmount
                );
                deckContract.clearHand(tables[table].players[i]);
                emit dealerBlow(sum, "Dealer Blow");
                deckContract.beforeStand(tables[table].players[i]);
            }
            // Dealer lose
            else if (
                tables[table].players[i] != dealerAddress &&
                playerValue > sum &&
                sum <= 21
            ) {
                maxBetAmount *= 2;
                blockJackTokenContract.transferCredit(
                    tables[table].players[i],
                    maxBetAmount
                );
                deckContract.clearHand(tables[table].players[i]);
                emit dealerLost(
                    tables[table].players[i],
                    maxBetAmount,
                    playerValue,
                    sum,
                    "Dealer Lost"
                );
                deckContract.beforeStand(tables[table].players[i]);
            }
            //Player lose
            else if (
                tables[table].players[i] != dealerAddress &&
                sum > playerValue &&
                sum <= 21
            ) {
                emit dealerWon(
                    tables[table].players[i],
                    maxBetAmount,
                    sum,
                    playerValue,
                    "Dealer Won"
                );
                deckContract.clearHand(tables[table].players[i]);
                deckContract.beforeStand(tables[table].players[i]);
            }
            //Player and Dealer Draw
            else if (playerValue == sum && sum <= 21 &&  tables[table].players[i] != dealerAddress ) {
                emit dealerDraw(
                    tables[table].players[i],
                    maxBetAmount,
                    playerValue,
                    sum,
                    "Dealer Draw"
                );
                deckContract.beforeStand(tables[table].players[i]);
            }
        }
        deckContract.clearHand(dealerAddress);
        tables[table].players = new address[](0);
        deckContract.beforeStand(dealerAddress);
    }
}
