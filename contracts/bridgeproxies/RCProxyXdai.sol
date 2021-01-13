pragma solidity 0.5.13;

import "hardhat/console.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import '../interfaces/IRCProxyMainnet.sol';
import '../interfaces/IBridgeContract.sol';
import '../interfaces/IRCMarket.sol';
import '../interfaces/ITreasury.sol';

/// @title Reality Cards Proxy- xDai side
/// @author Andrew Stanger
contract RCProxyXdai is Ownable
{
    using SafeMath for uint256;
    ////////////////////////////////////
    //////// VARIABLES /////////////////
    ////////////////////////////////////

    /// @dev contract variables
    IBridgeContract public bridge;

    /// @dev governance variables
    address public proxyMainnetAddress;
    address public factoryAddress;
    address public treasuryAddress;
    
    /// @dev market resolution variables
    mapping (address => bool) public marketFinalized;
    mapping (address => uint256) public winningOutcome;

    /// @dev so only markets can upgrade NFTs
    mapping (address => bool) public isMarket;

    /// @dev dai deposit variables
    uint256 validatorCount;
    mapping (address => bool) isValidator;
    mapping (uint256 => Deposit) deposits;
    mapping (uint256 => mapping(address => bool)) hasConfirmedDeposit;

    struct Deposit {
        address user;
        uint256 amount;
        uint256 confirmations;
        bool executed;
    }

    ////////////////////////////////////
    ////////// CONSTRUCTOR /////////////
    ////////////////////////////////////

    constructor(address _bridgeXdaiAddress, address _factoryAddress) public {
        setBridgeXdaiAddress(_bridgeXdaiAddress);
        setFactoryAddress(_factoryAddress);
    }

    ////////////////////////////////////
    //////////// ADD MARKETS ///////////
    ////////////////////////////////////

    /// @dev so only RC NFTs can be upgraded
    function addMarket(address _newMarket) external returns(bool) {
        require(msg.sender == factoryAddress, "Not factory");
        isMarket[_newMarket] = true;
        return true;
    }
    
    ////////////////////////////////////
    ////////// GOVERNANCE //////////////
    ////////////////////////////////////
    
    /// @dev address of mainnet oracle proxy, called by the mainnet side of the arbitrary message bridge
    /// @dev not set in constructor, address not known at deployment
    function setProxyMainnetAddress(address _newAddress) onlyOwner external {
        proxyMainnetAddress = _newAddress;
    }

    /// @dev address of arbitrary message bridge, xdai side
    function setBridgeXdaiAddress(address _newAddress) onlyOwner public {
        bridge = IBridgeContract(_newAddress);
    }

    /// @dev address of RC factory contract, so only factory can post questions
    function setFactoryAddress(address _newAddress) onlyOwner public {
        factoryAddress = _newAddress;
    }

    /// @dev admin override of the Oracle, if not yet settled, for amicable resolution, or bridge fails
    function setAmicableResolution(address _marketAddress, uint256 _winningOutcome) onlyOwner public {
        require(!marketFinalized[_marketAddress], "Event finalised");
        marketFinalized[_marketAddress] = true;
        winningOutcome[_marketAddress] = _winningOutcome;
    }

    /// @dev modify validators for dai deposits
    function setValidator(address _validatorAddress, bool _add) onlyOwner public {
        if(_add) {
            if(!isValidator[_validatorAddress]) {
                isValidator[_validatorAddress] = true;
                validatorCount = validatorCount.add(1);
            }
        } else {
            if(isValidator[_validatorAddress]) {
                isValidator[_validatorAddress] = false;
                validatorCount = validatorCount.sub(1);
            }
        }
    }
    
    ////////////////////////////////////
    ///// CORE FUNCTIONS - ORACLE //////
    ////////////////////////////////////

    /// @dev called by factory upon market creation, posts question to Oracle via arbitrary message bridge
    function sendQuestionToBridge(address _marketAddress, string calldata _question, uint32 _oracleResolutionTime) external {
        require(msg.sender == factoryAddress, "Not factory");
        bytes4 _methodSelector = IRCProxyMainnet(address(0)).postQuestionToOracle.selector;
        bytes memory data = abi.encodeWithSelector(_methodSelector, _marketAddress, _question, _oracleResolutionTime);
        bridge.requireToPassMessage(proxyMainnetAddress,data,200000);
    }
    
    /// @dev called by mainnet oracle proxy via the arbitrary message bridge, sets the winning outcome
    function setWinner(address _marketAddress, uint256 _winningOutcome) external {
        require(!marketFinalized[_marketAddress], "Event finalised");
        require(msg.sender == address(bridge), "Not bridge");
        require(bridge.messageSender() == proxyMainnetAddress, "Not proxy");
        marketFinalized[_marketAddress] = true;
        winningOutcome[_marketAddress] = _winningOutcome;
    }
    
    /// @dev called by market contracts to check if winner known
    function isFinalized(address _marketAddress) external view returns(bool) {
        return(marketFinalized[_marketAddress]);
    }
    
    /// @dev called by market contracts to get the winner
    function getWinner(address _marketAddress) external view returns(uint256) {
        require(marketFinalized[_marketAddress], "Not finalised");
        return winningOutcome[_marketAddress];
    }

    ////////////////////////////////////
    /// CORE FUNCTIONS - NFT UPGRADES //
    ////////////////////////////////////

    function upgradeCard(uint256 _tokenId, string calldata _tokenUri, address _owner) external {
        require(isMarket[msg.sender], "Not market");
        bytes4 _methodSelector = IRCProxyMainnet(address(0)).upgradeCard.selector;
        bytes memory data = abi.encodeWithSelector(_methodSelector, _tokenId, _tokenUri, _owner);
        bridge.requireToPassMessage(proxyMainnetAddress,data,200000);
    }

    function confirmDaiDeposit(address _user, uint256 _amount, uint256 _nonce) external {
        require(isValidator[msg.sender], "Not a validator");

        // If the deposit is new, create it
        if(deposits[_nonce].user == address(0)) {
            Deposit memory newDeposit = Deposit(_user, _amount, 0, false);
            deposits[_nonce] = newDeposit;
        }

        // Only valid if these match
        require(deposits[_nonce].user == _user, "Addresses don't match");
        require(deposits[_nonce].amount == _amount, "Amounts don't match");
        
        // Add 1 confirmation, if this hasn't been done already
        // Note: allowing to execute this twice in case there was
        // not enough money initially
        if(!hasConfirmedDeposit[_nonce][msg.sender]) {
            hasConfirmedDeposit[_nonce][msg.sender] = true;
            deposits[_nonce].confirmations = deposits[_nonce].confirmations.add(1);
        }

        // Execute if not already done so, enough confirmations and enough money
        if(!deposits[_nonce].executed && deposits[_nonce].confirmations >= (validatorCount.div(2)).add(1) && address(this).balance >= _amount) {
            deposits[_nonce].executed = true;
            // do the deposit directly
            ITreasury treasury = ITreasury(treasuryAddress);
            assert(treasury.deposit.value(_amount)(_user));
        }
    }
}