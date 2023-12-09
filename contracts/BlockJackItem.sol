// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BlockJackItem is ERC721URIStorage, Ownable {
    uint256 private _currentTokenId = 0;
    address public ownerAddress;

    event ItemMinted(uint256 indexed itemId, address indexed recipient, string metadataURI);

    /**
     * @dev Constructor function for the BlockJack Item ERC721 contract.
     * The contract is initialized with the specified name, symbol, and the deployer as the owner.
     */
    constructor() ERC721("BlockJack Item", "BJI") Ownable(msg.sender) {
        ownerAddress = msg.sender;
    }

    /**
     * @dev Modifier that allows the function to be called only by the contract owner (admin).
     * Reverts with an error message if the caller is not the owner.
     */
    modifier onlyAdmin() {
        require(owner() == _msgSender(), "Only admin can call this function");
        _;
    }

    /**
     * @dev Mints a new item and assigns it to the specified recipient, setting its metadata URI.
     * Only the contract owner (admin) can call this function.
     * @param recipient The address to which the new token will be assigned.
     * @param metadataURI The URI for the metadata associated with the new token.
     * @return newItemId The ID of the newly minted token.
     */
    function mintTo(address recipient, string memory metadataURI) public onlyAdmin returns (uint256) {
        uint256 newItemId = _getNextTokenId();
        _mint(recipient, newItemId);
        _setTokenURI(newItemId, metadataURI);
        _incrementTokenId();
        emit ItemMinted(newItemId, recipient, metadataURI);
        return newItemId;
    }

    /**
     * @dev Retrieves the next available token ID without modifying any state.
     * @return The next available token ID.
     */
    function _getNextTokenId() private view returns (uint256) {
        return _currentTokenId + 1;
    }

    /**
     * @dev Increments the current token ID, indicating the assignment of a new token.
     */
    function _incrementTokenId() private {
        _currentTokenId++;
    }

}
