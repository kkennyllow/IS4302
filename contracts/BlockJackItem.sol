// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BlockJackItem is ERC721URIStorage, Ownable {
    uint256 private _currentTokenId = 0;
    address public ownerAddress;

    event ItemMinted(uint256 indexed itemId, address indexed recipient, string metadataURI);

    constructor() ERC721("BlockJack Item", "BJI") Ownable(msg.sender) {
        ownerAddress = msg.sender;
    }

    modifier onlyAdmin() {
        require(owner() == _msgSender(), "Only admin can call this function");
        _;
    }

    function mintTo(address recipient, string memory metadataURI) public onlyAdmin returns (uint256) {
        uint256 newItemId = _getNextTokenId();
        _mint(recipient, newItemId);
        _setTokenURI(newItemId, metadataURI);
        _incrementTokenId();
        emit ItemMinted(newItemId, recipient, metadataURI);
        return newItemId;
    }


    function _getNextTokenId() private view returns (uint256) {
        return _currentTokenId + 1;
    }

    function _incrementTokenId() private {
        _currentTokenId++;
    }

}
