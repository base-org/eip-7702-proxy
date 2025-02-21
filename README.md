# EIP-7702 Proxy

**Proxy contract designed for EIP-7702 accounts.**

> These contracts are unaudited and simple prototypes. Use at your own risk.

### Key features
* Protect initializers with chain-agnostic EOA signatures
* Use existing Smart Account contracts without changes
* Unify contract implementation upgrades using ERC-1967 storage slots

### How to use
1. Deploy an instance of `EIP7702Proxy` pointing to a specific smart account implementation.
1. Sign an EIP-7702 authorization with the EOA
1. Sign an initialization hash with the EOA
1. Submit transaction with EIP-7702 authorization and call to `account.initialize(bytes args, bytes signature)`
    1. `bytes args`: arguments to the smart account implementation's actual initializer function
    1. `bytes signature`: ECDSA signature over the initialization hash from the EOA

Now the EOA has been upgraded to the smart account implementation and had its state initialized.

If the smart account implementation supports UUPS upgradeability, it will work as designed by submitting upgrade calls to the account.

### How does it work?
* `EIP7702Proxy` is constructed with an `initialImplementation` that it will delegate all calls to by default
* `EIP7702Proxy` is constructed with a `guardedInitializer`, the initializer selector of the `initialImplementation`
* Calls to the account on `guardedInitializer` revert and do not delegate the call to the smart account implementation
* `EIP7702Proxy` defines a new, static selector compatible with all initializers: `initialize(bytes args, bytes signature)`
* Calls to the account on `initialize` have their signature validated via ECDSA and the proxy delegates a call combining the `guardedInitializer` and provided `args` to the `initialImplementation`
* The `initialImplementation` is responsible for handling replay protection, which is standard practice among smart accounts
* All other function selectors are undisturbed and this proxy functions akin to a simple ERC-1967 proxy

---

## Performing EIP-7702 upgrades

This repository contains scripts that can be used to perform an EIP-7702 upgrade to a `EIP7702Proxy` with a `CoinbaseSmartWallet` implementation and initialize the smart account. The [Odyssey testnet](https://hub.conduit.xyz/odyssey) by [Ithaca](https://www.ithaca.xyz) has EIP-7702 enabled. If testing locally, you can use the Anvil testnet with Odyssey enabled.

The upgrade process happens in two steps:

1. **UpgradeEOA.s.sol**: Deploys the implementation and proxy template, then performs the EIP-7702 upgrade
   - Outputs the proxy template address which is needed for the initialization step
   - For Odyssey: Save this address to use in the next step

2. **Initialize.s.sol**: Initializes the smart account with a new owner and tests the upgrade
   - For Odyssey: Requires the proxy template address from step 1

> ℹ️ See the scripts themselves for additional comments and documentation.

### Prerequisites
- Foundry installed
- If you're using the Odyssey testnet, you'll need three private keys funded with some Odyssey ETH (see `.env.example`):
    - `EOA_PRIVATE_KEY`: The private key of the EOA to be upgraded
    - `DEPLOYER_PRIVATE_KEY`: The private key of the EOA that will perform the upgrade
    - `NEW_OWNER_PRIVATE_KEY`: The private key of another EOA that will be added as an owner
    - `PROXY_TEMPLATE_ADDRESS_ODYSSEY`: Address of the proxy template (from UpgradeEOA.s.sol output)

Odyssey Chain Info: https://hub.conduit.xyz/odyssey

### Local Testing (Anvil)

1. Start a local Anvil node with Odyssey enabled:
```bash
anvil --odyssey
```

2. Run the UpgradeEOA script to upgrade your EOA:
```bash
forge script script/UpgradeEOA.s.sol --rpc-url http://localhost:8545 --broadcast --ffi
```

3. Run the Initialize script to set up ownership:
```bash
forge script script/Initialize.s.sol --rpc-url http://localhost:8545 --broadcast
```

### Odyssey Testnet Deployment

1. Set up environment variables (see `.env.example`)

2. Run the UpgradeEOA script with Odyssey RPC:
```bash
forge script script/UpgradeEOA.s.sol --rpc-url https://odyssey.ithaca.xyz --broadcast --ffi
# Note the proxy template address from the output
export PROXY_TEMPLATE_ADDRESS_ODYSSEY=<address from output>
```

3. Run the Initialize script:
```bash
forge script script/Initialize.s.sol --rpc-url https://odyssey.ithaca.xyz --broadcast
```

## Contract Verification

Below are the commands to verify the implementation contract and proxy template. While we can verify the implementation contract and proxy template, we've been unable to verify the upgraded EOA address directly. We suspect it might be related to EIP-7702's deployment mechanism being different from traditional contract deployments, but this needs to be confirmed with the Blockscout and/or Ithaca teams.

In the meantime, you can check correctness by:
1. Comparing your EOA's code with the verified proxy template
2. Checking that the proxy delegates to the verified implementation
3. Using the provided scripts to test interactions

### Verifying the Implementation Contract

```bash
forge verify-contract \
    --verifier blockscout \
    --verifier-url "https://odyssey-explorer.ithaca.xyz/api" \
    --watch \
    --compiler-version "v0.8.23" \
    --num-of-optimizations 200 \
    <IMPLEMENTATION_ADDRESS> \
    lib/smart-wallet/src/CoinbaseSmartWallet.sol:CoinbaseSmartWallet
```

### Verifying the Proxy Template

```bash
forge verify-contract \
    --verifier blockscout \
    --verifier-url "https://odyssey-explorer.ithaca.xyz/api" \
    --watch \
    --compiler-version "v0.8.23" \
    --num-of-optimizations 200 \
    <PROXY_TEMPLATE_ADDRESS> \
    src/EIP7702Proxy.sol:EIP7702Proxy
```
