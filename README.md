# EIP-7702 Proxy

> ⚠️ These contracts are unaudited prototypes and may contain serious vulnerabilities. DO NOT USE IN PRODUCTION.

A secure ERC-1967 proxy implementation for EIP-7702 smart accounts.

## Overview

The EIP-7702 Proxy provides a secure way to upgrade EOAs to smart contract wallets through EIP-7702 delegation. It solves critical security challenges in the EIP-7702 design space while allowing the use of existing smart account implementations.

## Key Features

### 🔒 Secure Initialization
- Signature-based authorization from the EOA for initial implementation setting and initialization
- Atomic implementation setting + initialization to prevent front-running
- Account state validation through implementation-specific configurable validator
- Reliable protection against signature replay through external nonce tracking

### 💾 Storage Management
- ERC-1967 compliant implementation storage
- Ability to set the ERC-1967 storage slot via the proxy itself
- Built-in token receiver for uninitialized state
- Safe handling of A → B → A delegation patterns

### 🔄 Upgradeability
- Implementation-agnostic design
- Compatible with any ERC-1967 implementation

## Core Components

### EIP7702Proxy
- Manages safe implementation upgrades through `setImplementation`
- Validates EOA signatures for all state changes
- Provides fallback to `DefaultReceiver` when uninitialized
- Overrides `isValidSignature` to provide a final fallback `ecrecover` check

### NonceTracker
- External nonce management for signature validation in storage-safe location
- Prevents signature replay attacks
- Maintains nonce integrity across delegations

### IAccountStateValidator
- Interface for implementation-specific state validation
- Called to ensure correct initialization or other account state
- Reverts invalid state transitions

### DefaultReceiver
- Inherits from Solady `Receiver`
- Provides a default implementation for token compatibility

## Usage

1. Deploy singleton instance of `EIP7702Proxy` with immutable parameters:
   - `NonceTracker` for signature security
   - `DefaultReceiver` for token compatibility

2. Sign an EIP-7702 authorization with the EOA to delegate to the `EIP7702Proxy`
3. Sign a payload for `setImplementation` with the EOA, which includes the new implementation address, initialization calldata, and the address of an account state validator
4. Submit transaction with EIP-7702 authorization and call to `setImplementation(bytes args, bytes signature)` with:
    - `address newImplementation`: address of the new implementation
    - `bytes calldata callData`: initialization calldata
    - `address validator`: address of the account state validator
    - `bytes calldata signature`: ECDSA signature over the initialization hash from the EOA
    - `bool allowCrossChainReplay`: whether to allow cross-chain replay

Now the EOA has been upgraded to the smart account implementation and had its state initialized.

If the smart account implementation supports UUPS upgradeability, it will work as designed by submitting upgrade calls to the account.

