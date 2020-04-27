pragma solidity >=0.4.22 <0.7.0;


interface IUniswapOTC {
    function exchangeAddress() external view;

    function tokenAddress() external view;

    function minEthLimit() external view;

    function minTokenLimit() external view;

    function minTokens() external view;

    function totalPurchased() external view;

    function totalFees() external view;

    event OTCPurchase(uint256 tokens_bought, uint256 fee); //Purchased
    event OTCDeposit(uint256 minTokens, uint256 etherAmount); //Reset limit price

    /**
     * @dev Add Trigger address.
     */
    function setTriggerAddress(address _address, bool _authorized) external;

    /**
     * @dev Fund contract and set limit price (in the form of min purchased tokens).
     * Excess value is refunded to sender in the case of a re-balancing.
     */
    function setMinTokens(uint256 _minTokens, uint256 _etherAmount)
        external
        payable
        returns (uint256, uint256);

    function canPurchase() external view returns (bool);

    /**
     * @dev Trigger Uniswap contract, drains entire contract's ETH balance.
     *      Computes fee as minimum of either the estimated slippage (best case) or
     *      spread from limit price (when slippage would be above limit price).
     */
    function sendPurchase(uint256 deadline) external returns (uint256, uint256);

    /**
     * @dev Withdraw OTC provider fee tokens.
     */
    function withdrawFeeTokens() external;

    /**
     * @dev Withdraw OTC client purchased tokens.
     */
    function withdrawClientTokens() external;

    /**
     * @dev Withdraw OTC client ether.
     */
    function withdrawEther() external;

    /**
     * @dev Get eth balance
     */
    function ethBalance() external view returns (uint256);

    /**
     * @dev Get token balance
     */
    function tokenBalance() external view returns (uint256);
}
