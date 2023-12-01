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

    constructor(address _blockJackItemAddress, address _blockJackTokenAddress) {
        blockJackItemContract = BlockJackItem(_blockJackItemAddress);
        blockJackTokenContract = BlockJackToken(_blockJackTokenAddress);
    }

    function listItem(uint256 itemId, uint256 price) public {
        require(msg.sender == blockJackItemContract.ownerOf(itemId), "Not the item owner");
        itemPrices[itemId] = price;
        itemOwners[itemId] = msg.sender;
        // Emit event for item listing
    }

    function buyItem(uint256 itemId) public {
        uint256 price = itemPrices[itemId];
        require(price > 0, "Item not for sale");
        require(blockJackTokenContract.checkCredit(msg.sender) >= price, "Insufficient balance");

        blockJackTokenContract.transferCredit(itemOwners[itemId], price);
        blockJackItemContract.safeTransferFrom(itemOwners[itemId], msg.sender, itemId);

        itemPrices[itemId] = 0;  // Item no longer for sale
        itemOwners[itemId] = address(0);
        // Emit event for item purchase
    }

    // Additional functions like getItemPrice, removeListing, etc.
}
