pragma solidity >=0.4.22 <0.7.0;

import "./IUniswapExchange.sol";
import "./IERC20.sol";


contract UniswapOTC {
    address public owner; //OTC owner, earns fee
    address public client; //OTC client, manages funds and limit price

    address public exchangeAddress;
    address public tokenAddress;

    IERC20 token;
    IUniswapExchange exchange;

    //Min volume values
    uint256 public minEthLimit;
    uint256 public maxTokenPerEth;

    uint256 public minTokens; //Limit price set by client
    uint256 public totalPurchased;
    uint256 public totalFees;

    mapping(address => bool) public triggerAddresses; //Bot trigger permissions
    uint256 constant ONE_DAY_SECONDS = 86400;

    bool public clientTokensWithdrawn; //Check if tokens were withdrawn
    uint256 public feeWithdrawAfter; //Fallback withdraw 24hr

    event OTCPurchase(uint256 tokens_bought, uint256 fee);      //Purchased
    event OTCDeposit(uint256 minTokens, uint256 etherAmount);   //Reset limit price

    constructor(address _exchangeAddress, address _client, uint256 _minEthLimit, uint256 _maxTokenPerEth) public {
        exchange = IUniswapExchange(_exchangeAddress);
        exchangeAddress = _exchangeAddress;
        tokenAddress = exchange.tokenAddress();
        token = IERC20(tokenAddress);
        totalPurchased = 0;
        totalFees = 0;
        owner = msg.sender;
        client = _client;
        minEthLimit = _minEthLimit;
        maxTokenPerEth = _maxTokenPerEth;
        minTokens = 0; //Initialize at 0
    }

    /**
     * @dev OTC Provider. Gives right to fee withdrawal.
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Unauthorized");
        _;
    }

    /**
     * @dev OTC Client. Manages funds and limit price.
     */
    modifier onlyClient() {
        require(msg.sender == client, "Unauthorized");
        _;
    }

    /**
     * @dev Authorized Purchase Trigger addresses for mempool bot.
     */
    modifier onlyTrigger() {
        require(msg.sender == owner || triggerAddresses[msg.sender], "Unauthorized");
        _;
    }

    /**
     * @dev Add Trigger address.
     */
    function setTriggerAddress(address _address, bool _authorized)
        public
        onlyOwner
    {
        triggerAddresses[_address] = _authorized;
    }

    /**
     * @dev Fund contract and set limit price (in the form of min purchased tokens).
     * Excess value is refunded to sender in the case of a re-balancing.
     */
    function setMinTokens(uint256 _minTokens, uint256 _etherAmount)
        public
        payable
        onlyClient
        returns (uint256, uint256)
    {
        require(_etherAmount >= minEthLimit, "Insufficient ETH volume");
        require((_minTokens / _etherAmount) <= maxTokenPerEth, "Excessive token per ETH");
        require(_etherAmount <= address(this).balance, "Insufficient funds!");
        //Client tokens not with drawn
        clientTokensWithdrawn = false;
        //Set min tokens.
        minTokens = _minTokens;
        //Refund excess balance
        uint256 excess_balance = address(this).balance - _etherAmount;

        emit OTCDeposit(_minTokens, _etherAmount);
        payable(msg.sender).transfer(excess_balance);
    }


    /**
     * @dev Return if purchase would be autherized at current prices
     */
    function canPurchase()
        public
        view
        returns (bool)
    {
        //Avoids Uniswap Assert Failure when no liquidity (gas saving)
        if (token.balanceOf(exchangeAddress) == 0) {
            return false; 
        }

        uint256 eth_balance = address(this).balance;   
        uint256 tokens_bought = exchange.getEthToTokenInputPrice(eth_balance);
        //Only buy less than or equal to limit price
        return tokens_bought >= minTokens;
    }

    /**
     * @dev Trigger Uniswap contract, drains entire contract's ETH balance.
     *      Computes fee as minimum of either the estimated slippage (best case) or
     *      spread from limit price (when slippage would be above limit price).
     */
    function sendPurchase(uint256 deadline)
        public
        onlyTrigger
        returns (uint256, uint256)
    {
        //Avoids Uniswap Assert Failure when no liquidity (gas saving)
        require(token.balanceOf(exchangeAddress) > 0, "No liquidity on Uniswap!"); //27,055 Gas

        uint256 eth_balance = address(this).balance;
        uint256 tokens_bought = exchange.getEthToTokenInputPrice(eth_balance);

        //Only buy less than or equal to limit price
        require(tokens_bought >= minTokens, "Purchase above limit price!"); //27,055 Gas
        feeWithdrawAfter = block.timestamp + ONE_DAY_SECONDS; //set timelock = purchase + 24hr

        //Call Uniswap contract
        exchange.ethToTokenSwapInput.value(eth_balance)(
            tokens_bought,
            deadline
        );

        //Fee Calculation as next purchase opportunity cost
        //tokens_bought > tokens_bought_after
        uint256 tokens_bought_after = exchange.getEthToTokenInputPrice(
            eth_balance
        );

        uint256 fee;
        if (tokens_bought_after >= minTokens) {
            fee = tokens_bought - tokens_bought_after; //Upper threshold performance fee
        } else {
            //fee = tokens_bought - minTokens
            fee = tokens_bought - minTokens; //Fee reduced to fit limit price
        }

        emit OTCPurchase(tokens_bought, fee);

        totalPurchased += tokens_bought;
        totalFees += fee;

        return (tokens_bought, fee);
    }

    /**
     * @dev Withdraw OTC provider fee tokens.
     */
    function withdrawFeeTokens() public onlyOwner {
        require(totalFees > 0, "No fees!");
        require(clientTokensWithdrawn || block.timestamp > feeWithdrawAfter, "Wait for client withdrawal or timelock.");

        //Substract fees
        uint256 feeTransfer = totalFees;
        totalFees = 0; //Update set to 0
        totalPurchased = totalPurchased - feeTransfer; //Update token balance

        token.transfer(msg.sender, feeTransfer);
    }

    /**
     * @dev Withdraw OTC client purchased tokens.
     */
    function withdrawClientTokens() public onlyClient {
        require(totalPurchased > 0, "No tokens!");

        //Set as withdrawn
        clientTokensWithdrawn = true;
        //Substract fees
        uint256 clientTokens = totalPurchased - totalFees;
        totalPurchased = totalPurchased - clientTokens;

        token.transfer(msg.sender, clientTokens);
    }

    /**
     * @dev Withdraw OTC client ether.
     */
    function withdrawEther() public onlyClient {
        uint256 eth_balance = address(this).balance;
        payable(msg.sender).transfer(eth_balance);
    }

    /**
     * @dev Get eth balance
     */
    function ethBalance() public view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Get token balance
     */
    function tokenBalance() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

}
