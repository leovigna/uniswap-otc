pragma solidity >=0.4.22 <0.7.0;

import "./UniswapExchange.sol";
import "./IERC20.sol";


contract UniswapOTC {
    address owner; //OTC owner, earns fee
    address client; //OTC client, manages funds and limit price

    UniswapExchange exchange;
    address public exchangeAddress;

    uint256 public minTokens; //Limit price
    uint256 public totalPurchased;
    uint256 public totalFees;

    mapping(address => bool) triggerAddresses; //Bot trigger permissions

    event PayeeAdded(address account, uint256 shares);
    event OTCPurchase(uint256 tokens_bought, uint256 fee);

    constructor(address _exchangeAddress, address _client) public {
        exchange = UniswapExchange(_exchangeAddress);
        exchangeAddress = exchangeAddress;
        totalPurchased = 0;
        totalFees = 0;
        owner = msg.sender;
        client = _client;
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
        require(triggerAddresses[msg.sender], "Unauthorized");
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
        require(_etherAmount <= address(this).balance, "Insufficient funds!");

        //Set min tokens.
        minTokens = _minTokens;
        //Refund excess balance
        uint256 excess_balance = address(this).balance - _etherAmount;
        payable(msg.sender).transfer(excess_balance);
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
        uint256 eth_balance = address(this).balance;

        uint256 tokens_bought = exchange.getEthToTokenInputPrice(eth_balance);
        //Only buy less than or equal to limit price
        require(tokens_bought >= minTokens, "Purchase above limit price!");
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
        if (tokens_bought_after > minTokens) {
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
        IERC20 token = IERC20(exchange.tokenAddress());

        //Substract fees
        totalFees = 0;
        token.transfer(msg.sender, totalFees);
    }

    /**
     * @dev Withdraw OTC client purchased tokens.
     */
    function withdrawClientTokens() public onlyClient {
        IERC20 token = IERC20(exchange.tokenAddress());

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
}
