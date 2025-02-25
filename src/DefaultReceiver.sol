// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Receiver} from "solady/accounts/Receiver.sol";

/// @title DefaultReceiver
///
/// @notice A concrete implementation of Solady's Receiver contract
///
/// @dev Handles ETH, ERC721, and ERC1155 token transfers
contract DefaultReceiver is Receiver {
// We don't need to override any functions since the base contract
// already implements all the necessary functionality:
// - receive() for ETH
// - fallback() with receiverFallback modifier for ERC721/ERC1155
// - _useReceiverFallbackBody() returns true
// - _beforeReceiverFallbackBody() empty implementation
// - _afterReceiverFallbackBody() empty implementation
}
