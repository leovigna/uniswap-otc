pragma solidity ^0.5.0;

// Constructor for Upgradeable Contract due to Proxy architecture
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";


/**
 * @title Example Contract
 * @notice Copy this contract as a template
 * @dev Upgradeable version OpenZeppelin contract. Uses OpenZeppelin's Initializable, Ownable contracts.
 */
contract MyContract is Initializable, Ownable {
    using SafeMath for uint256;

    /**
     * @notice Called by proxy admin to initialize
     * @dev Avoid using constructor. Instead use initializer pattern.
     * @param _sender The contract initializer address.
     * @return Status if the initialization was successful
     */
    function initialize(address _sender) external initializer returns (bool) {
        Ownable.initialize(msg.sender);
        return true;
    }
}
