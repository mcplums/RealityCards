pragma solidity 0.5.13;

import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@nomiclabs/buidler/console.sol";
import './lib/CloneFactory.sol';
import "./interfaces/IRealitio.sol";
import "./interfaces/ITreasury.sol";
import './interfaces/IRCMarketXdaiV1.sol';

/// @title Reality Cards Factory
/// @author Andrew Stanger

contract RCFactory is Ownable, CloneFactory {

    using SafeMath for uint256;

    ////////////////////////////////////
    //////// VARIABLES /////////////////
    ////////////////////////////////////

    ///// CONTRACT VARIABLES /////
    IRealitio public realitio;
    ITreasury public treasury;

    ///// CONTRACT ADDRESSES /////
    // version implied by position
    mapping(uint256 => address[]) public referenceContractAddresses; 
    mapping(uint256 => address[]) public marketAddresses;
    mapping(address => bool) public mappingOfMarkets; //not currently used

    ///// EVENTS /////
    event LogMarketCreated(address contractAddress, address treasuryAddress, uint256 mode, uint256 version, bytes ipfsHash);
    event LogNewReferenceContract(address contractAddress, uint256 mode, uint256 version);

    constructor(IRealitio _realitioAddress, ITreasury _treasuryAddress) public 
    {
        realitio = _realitioAddress;
        treasury = _treasuryAddress;
        Ownable.initialize(msg.sender);
        assert(treasury.setFactoryAddress(address(this)));
    }

    /// @notice set the reference contract for the contract logic
    /// @dev automatically increments version number if we 'upgrade' the contract
    function setReferenceContractAddress(uint256 _mode, address _referenceContractAddress) public onlyOwner {
        referenceContractAddresses[_mode].push(_referenceContractAddress);
        uint256 _version = referenceContractAddresses[_mode].length-1;
        emit LogNewReferenceContract(_referenceContractAddress, _mode, _version);
    }

    /// @notice create a new market
    function createMarket(
        uint32 _mode,
        bytes memory _ipfsHash,
        address _owner,
        uint256 _numberOfTokens,
        uint32[] memory timestamps,
        string memory _realitioQuestion,
        address _arbitrator,
        uint32 _timeout,
        string memory _tokenName
    ) public onlyOwner returns (address)  {
        address _newAddress;

        if (_mode == 0) {
            _newAddress = createClone(getMostRecentReferenceContract(_mode));
            IRCMarketXdaiV1(_newAddress).initialize({
                _owner: _owner,
                _numberOfTokens: _numberOfTokens,
                _marketLockingTime: timestamps[0],
                _oracleResolutionTime: timestamps[1],
                _templateId: 2,
                _question: _realitioQuestion,
                _arbitrator: _arbitrator,
                _timeout: _timeout,
                _tokenName: _tokenName
            });
            treasury.addMarket(_newAddress);
        }
        
        marketAddresses[_mode].push(_newAddress);
        mappingOfMarkets[_newAddress] = true;
        uint256 _version = referenceContractAddresses[_mode].length-1;
        emit LogMarketCreated(address(_newAddress), address(treasury), _mode, _version, _ipfsHash);

        return _newAddress;
    }

    function getMostRecentReferenceContract(uint256 _mode) public view returns (address) {
        return referenceContractAddresses[_mode][referenceContractAddresses[_mode].length-1];
    }

    function getAllReferenceContracts(uint256 _mode) public view returns (address[] memory) {
        return referenceContractAddresses[_mode];
    }

    function getMostRecentMarket(uint256 _mode) public view returns (address) {
        return marketAddresses[_mode][marketAddresses[_mode].length-1];
    }

    function getAllMarkets(uint256 _mode) public view returns (address[] memory) {
        return marketAddresses[_mode];
    }

}

