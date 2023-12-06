// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./BlockJackToken.sol";
import "./BlockJackItem.sol";


contract BlockjackShop {
    BlockJackItem public blockJackItemContract;
    BlockJackToken public blockJackTokenContract;

    mapping(uint256 => uint256) public itemPrices;  // itemId => price
    mapping(uint256 => address) public itemOwners;  // itemId => owner
    mapping(address => uint256) private lastActionTime;
    uint256 public constant ACTION_COOLDOWN = 2 seconds; 

    event ItemListed(uint256 indexed itemId, address indexed owner, uint256 price);
    event ItemPurchased(uint256 indexed itemId, address indexed buyer, uint256 price);


    constructor(address _blockJackItemAddress, address _blockJackTokenAddress) {
        blockJackItemContract = BlockJackItem(_blockJackItemAddress);
        blockJackTokenContract = BlockJackToken(_blockJackTokenAddress);
    }

    function isRateLimited(address user) public view returns (bool) {
        return block.timestamp < lastActionTime[user] + ACTION_COOLDOWN;
    }

    function listItem(uint256 itemId, uint256 price) public {
        require(msg.sender == blockJackItemContract.ownerOf(itemId), "Not the item owner");
        itemPrices[itemId] = price;
        itemOwners[itemId] = msg.sender;
        emit ItemListed(itemId, msg.sender, price);
    }
    

    function buyItem(uint256 itemId) public {
        require(!isRateLimited(msg.sender), "Action rate limited");
        lastActionTime[msg.sender] = block.timestamp;  
        uint256 price = itemPrices[itemId];
        require(price > 0, "Item not for sale");
        require(blockJackTokenContract.checkCredit(msg.sender) >= price, "Insufficient balance");

        blockJackTokenContract.transferCredit(itemOwners[itemId], price);
        blockJackItemContract.safeTransferFrom(itemOwners[itemId], msg.sender, itemId);

        itemPrices[itemId] = 0;  // Item no longer for sale
        itemOwners[itemId] = address(0);
        emit ItemPurchased(itemId, msg.sender, price);
    }
}
