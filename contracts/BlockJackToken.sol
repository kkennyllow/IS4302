// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./ERC20.sol";

contract BlockJackToken {
    ERC20 erc20Contract;
    address owner;

    //1 BlockJackToken cost 0.0001 ETH
    mapping(address => uint256) private lastActionTime;
    uint256 public constant ACTION_COOLDOWN = 2 seconds; 

    /**
     * @dev Contract constructor initializes an ERC20 contract and sets the deployer as the owner.
     * The newly created ERC20 contract is stored in the `erc20Contract` variable.
     */
    constructor() {
        ERC20 e = new ERC20();
        erc20Contract = e;
        owner = msg.sender;
    }

     /**
     * @dev Checks whether a user is currently rate-limited based on the time elapsed since their last action.
     * Users are rate-limited to prevent frequent or excessive actions within a specified cooldown period.
     *
     * @param user The address of the user to check for rate-limiting.
     * @return A boolean indicating whether the user is currently rate-limited (true if rate-limited, false otherwise).
     */
    function isRateLimited(address user) public view returns (bool) {
        return block.timestamp < lastActionTime[user] + ACTION_COOLDOWN;
    }

    /**
     * @dev Allows a user to obtain credits by sending Ether to the contract. 
     * The received Ether is converted to BlockJackToken (ERC-20) at a fixed rate.
     * Users are rate-limited to prevent frequent or excessive requests within a specified cooldown period.
     *
     * @param recipient The address to receive the BlockJackToken credits.
     * @return The amount of BlockJackToken credits minted and transferred to the recipient.
     */
    function getCredit(
        address recipient
    ) public payable returns (uint256) {
        require(!isRateLimited(msg.sender), "Action rate limited");
        lastActionTime[msg.sender] = block.timestamp;   
        uint256 amt = msg.value / (1000000000000000000 / 10000); // Convert weiAmt to BlockJackToken
        erc20Contract.mint(recipient, amt);
        return amt;
    }

     /**
     * @dev Retrieves the amount of BlockJackToken (ERC-20) credits held by a specific address.
     *
     * @param ad The address for which to check the BlockJackToken credits.
     * @return The amount of BlockJackToken credits held by the specified address.
     */
    function checkCredit(address ad) public view returns (uint256) {
        uint256 credit = erc20Contract.balanceOf(ad);
        return credit;
    }
     /**
     * @dev Transfers BlockJackToken (ERC-20) credits from the contract owner to a specified recipient.
     *
     * @param recipient The address to which BlockJackToken credits will be transferred.
     * @param amt The amount of BlockJackToken credits to transfer.
     */
    function transferCredit(address recipient, uint256 amt) public {
        erc20Contract.transfer(recipient, amt);
    }

    /**
     * @dev Allows a player to cash out their BlockJackToken (ERC-20) credits, converting them to Ether and transferring the Ether to the player.
     * The corresponding BlockJackToken credits are transferred to the contract owner.
     */
    function cashOut() public {
        uint256 credit = checkCredit(msg.sender);
        transferCredit(owner, credit);
        uint256 amountInWei = credit * (1000000000000000000 / 10000);
        payable(msg.sender).transfer(amountInWei);
    }
}
