// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./BlockJackToken.sol";
import "./BlockJackItem.sol";

contract BlockjackShop {
    BlockJackItem public blockJackItemContract;
    BlockJackToken public blockJackTokenContract;

    mapping(uint256 => uint256) public itemPrices; // itemId => price
    mapping(uint256 => address) public itemOwners; // itemId => owner
    mapping(address => uint256) private lastActionTime;
    uint256 public constant ACTION_COOLDOWN = 2 seconds;

    event ItemListed(
        uint256 indexed itemId,
        address indexed owner,
        uint256 price
    );
    event ItemPurchased(
        uint256 indexed itemId,
        address indexed buyer,
        uint256 price
    );

    /**
     * @dev Contract constructor.
     * Initializes the BlockJackItem and BlockJackToken contracts based on the provided addresses.
     * @param _blockJackItemAddress The address of the BlockJackItem contract.
     * @param _blockJackTokenAddress The address of the BlockJackToken contract.
     */
    constructor(address _blockJackItemAddress, address _blockJackTokenAddress) {
        //Set the BlockJackItem contract address
        blockJackItemContract = BlockJackItem(_blockJackItemAddress);
        //Set the BlockJackToken contract address
        blockJackTokenContract = BlockJackToken(_blockJackTokenAddress);
    }

    /**
     * @dev Checks if a user is currently rate-limited.
     * Users are rate-limited to prevent frequent actions within a specified cooldown period.
     * @param user The address of the user.
     * @return A boolean indicating whether the user is rate-limited.
     */
    function isRateLimited(address user) public view returns (bool) {
        return block.timestamp < lastActionTime[user] + ACTION_COOLDOWN;
    }

    /**
     * @dev List an item in the marketplace with a specified price.
     * Only the owner of the item can list it for sale.
     * @param itemId The unique identifier of the item to be listed.
     * @param price The price at which the item is listed for sale.
     * Requirements:
     * - The caller must be the owner of the item.
     */
    function listItem(uint256 itemId, uint256 price) public {
        require(
            msg.sender == blockJackItemContract.ownerOf(itemId),
            "Not the item owner"
        );
        itemPrices[itemId] = price;
        itemOwners[itemId] = msg.sender;
        emit ItemListed(itemId, msg.sender, price);
    }

    /**
     * @dev Purchase an item from the marketplace using BlockJackToken.
     * @param itemId The unique identifier of the item to be purchased.
     *
     * Requirements:
     * - The action must not be rate-limited for the caller.
     * - The item must be listed for sale with a positive price.
     * - The buyer must have a sufficient balance to make the purchase.
     *
     * Emits an {ItemPurchased} event on successful purchase.
     */
    function buyItem(uint256 itemId) public {
        require(!isRateLimited(msg.sender), "Action rate limited");
        lastActionTime[msg.sender] = block.timestamp;
        uint256 price = itemPrices[itemId];
        require(price > 0, "Item not for sale");
        require(
            blockJackTokenContract.checkCredit(msg.sender) >= price,
            "Insufficient balance"
        );

        blockJackTokenContract.transferCredit(itemOwners[itemId], price);
        blockJackItemContract.safeTransferFrom(
            itemOwners[itemId],
            msg.sender,
            itemId
        );

        itemPrices[itemId] = 0; // Item no longer for sale
        itemOwners[itemId] = address(0);
        emit ItemPurchased(itemId, msg.sender, price);
    }
}
