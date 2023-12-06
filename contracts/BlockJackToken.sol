// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./ERC20.sol";

contract BlockJackToken {
    ERC20 erc20Contract;
    address owner;

    //1 BlockJackToken cost 0.0001 ETH

    constructor() {
        ERC20 e = new ERC20();
        erc20Contract = e;
        owner = msg.sender;
    }

    function getCredit(
        address recipient,
        uint256 weiAmt
    ) public returns (uint256) {
        uint256 amt = weiAmt / (1000000000000000000 / 10000); // Convert weiAmt to BlockJackToken
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

    function cashOut() public {
        uint256 credit = checkCredit(msg.sender);
        transferCredit(owner, credit);
        uint256 amountInWei = credit * (1000000000000000000 / 10000);
        payable(msg.sender).transfer(amountInWei);
    }
}
