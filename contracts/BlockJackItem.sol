// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

contract BlockJackItem is ERC721URIStorage {
    uint256 private _currentTokenId = 0;
    address public owner;

    constructor() ERC721("BlockJack Item", "BJI") {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can perform this action");
        _;
    }

    function mintTo(address recipient, string memory metadataURI) public onlyOwner returns (uint256) {
        uint256 newItemId = _getNextTokenId();
        _mint(recipient, newItemId);
        _setTokenURI(newItemId, metadataURI);
        _incrementTokenId();
        return newItemId;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner cannot be the zero address");
        owner = newOwner;
    }

    function _getNextTokenId() private view returns (uint256) {
        return _currentTokenId + 1;
    }

    function _incrementTokenId() private {
        _currentTokenId++;
    }

    // Additional functions can be implemented as needed.
}