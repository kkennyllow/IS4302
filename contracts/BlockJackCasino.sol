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
        uint256 minimumBet;
        GamblingState gamblingState;
    }
    Deck deckContract;
    BlockJackToken blockJackTokenContract;
    mapping(uint256 => Table) public tables;
    address payable dealerAddress;

    constructor(Deck deckContractAddress, BlockJackToken blockJackTokenAddress)
    {
        deckContract = deckContractAddress;
        blockJackTokenContract = blockJackTokenAddress;
        dealerAddress = payable(msg.sender);
    }

    event buyCredit(uint256 amount); //buying token for BlockJack
    event dealerLost(
        address indexed winner,
        uint256 amount,
        uint256 winnerSum,
        uint256 loserSum
    );
    event dealerWon(
        address indexed loser,
        uint256 amount,
        uint256 winnerSum,
        uint256 loserSum
    );
    event dealerBlow(uint256 count);

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

    function getTableSize(uint256 table) public view returns (uint256) {
        //get Number of Players
        return tables[table].players.length;
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
        uint256 playerWallet = checkBJT();
        require(
            minimumBet <= playerWallet,
            "You have too little tokens to join this table."
        );
        tables[table].players.push(msg.sender);
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

    function endGamble(uint256 table) public {
        require(msg.sender == dealerAddress, "Only dealers can end gamble.");
        tables[table].gamblingState = GamblingState.Gambling;
        uint256 sum = deckContract.totalSum(dealerAddress);
        uint256 players = getTableSize(table);
        uint256 minimumBet = getMinimumBet(table);
        for (uint256 i = 0; i < players; i++) {
            uint256 playerValue = deckContract.totalSum(
                tables[table].players[i]
            );
            if (sum > 21 && tables[table].players[i] != dealerAddress) {
                //dealer lose
                blockJackTokenContract.transferCredit(
                    tables[table].players[i],
                    minimumBet
                );
                deckContract.clearHand(tables[table].players[i]);
                emit dealerBlow(sum);
            } else if (
                tables[table].players[i] != dealerAddress &&
                playerValue > sum &&
                sum <= 21
            ) {
                blockJackTokenContract.transferCredit(
                    tables[table].players[i],
                    minimumBet
                );
                deckContract.clearHand(tables[table].players[i]);
                emit dealerLost(
                    tables[table].players[i],
                    minimumBet,
                    playerValue,
                    sum
                );
            } else if (
                tables[table].players[i] != dealerAddress && sum != playerValue
            ) {
                emit dealerWon(
                    tables[table].players[i],
                    minimumBet,
                    sum,
                    playerValue
                );
                deckContract.clearHand(tables[table].players[i]);
            }
        }
        deckContract.clearHand(dealerAddress);
        tables[table].players = new address[](0);
    }
}
