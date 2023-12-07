// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./ERC20.sol";

contract BlockJackToken {
    ERC20 erc20Contract;
    address owner;

    //1 BlockJackToken cost 0.0001 ETH
    mapping(address => uint256) private lastActionTime;
    uint256 public constant ACTION_COOLDOWN = 2 seconds; 

    constructor() {
        ERC20 e = new ERC20();
        erc20Contract = e;
        owner = msg.sender;
    }

    function isRateLimited(address user) public view returns (bool) {
        return block.timestamp < lastActionTime[user] + ACTION_COOLDOWN;
    }

    function getCredit(
        address recipient,
        uint256 weiAmt
    ) public returns (uint256) {
        require(!isRateLimited(msg.sender), "Action rate limited");
        lastActionTime[msg.sender] = block.timestamp;   
        uint256 amt = weiAmt / (1000000000000000000 / 10000); // Convert weiAmt to BlockJackToken
        erc20Contract.mint(recipient, amt);
        return amt;
    }

    function checkCredit(address ad) public view returns (uint256) {
        uint256 credit = erc20Contract.balanceOf(ad);
        return credit;
    }

    function transferCredit(address recipient, uint256 amt) public {
        require(!isRateLimited(msg.sender), "Action rate limited");
        lastActionTime[msg.sender] = block.timestamp;   
        erc20Contract.transfer(recipient, amt);
    }

    function cashOut() public {
        uint256 credit = checkCredit(msg.sender);
        transferCredit(owner, credit);
        uint256 amountInWei = credit * (1000000000000000000 / 10000);
        payable(msg.sender).transfer(amountInWei);
    }
}
