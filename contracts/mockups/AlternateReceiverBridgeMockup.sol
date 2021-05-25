// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.4;

import "hardhat/console.sol";

import "../interfaces/IRCProxyL2.sol";
import "../interfaces/IRCProxyL1.sol";

// this is only for ganache testing. Public chain deployments will use the existing Realitio contracts.

contract AlternateReceiverBridgeMockup {
    receive() external payable {}

    function relayTokens(
        address _notused,
        address _RCProxyAddress,
        uint256 _amount
    ) external payable {
        _notused;
        (bool _success, ) = payable(_RCProxyAddress).call{value: _amount}("");
        require(_success, "Transfer failed");
    }
}
