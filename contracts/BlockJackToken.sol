// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./ERC20.sol";

contract BlockJackToken {
    ERC20 erc20Contract;
    address owner;

    constructor()  {
        ERC20 e = new ERC20();
        erc20Contract = e;
        owner = msg.sender;
    }

    function getCredit(address recipient, uint256 weiAmt)
        public
        returns (uint256)
    {
        uint256 amt = weiAmt / (1000000000000000000 / 100); // Convert weiAmt to Dice Token
        erc20Contract.mint(recipient, amt);
        return amt; 
    }
    function checkCredit(address ad) public view returns (uint256) {
        uint256 credit = erc20Contract.balanceOf(ad);
        return credit;
    }
    function transferCredit(address recipient, uint256 amt) public {
        erc20Contract.transfer(recipient, amt);
    }
}
