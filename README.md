# G-Naira Token

## Overview
G-Naira (gNGN) is an ERC20-compliant token deployed on the Ethereum network with advanced multi-signature governance capabilities.

## Features

### Core ERC20 Functionality
- Standard ERC20 functionality (transfer, approve, transferFrom)
- Pausable transfers for emergency situations
- Blacklist functionality to prevent specific addresses from transacting
- Rate limiting for large transfers

### Multi-Signature Governance
- **Flexible M-of-N Signature Requirements**: Configurable number of required confirmations
- **Transaction Proposals**: Any signatory can propose operations
- **Automatic Execution**: Operations execute automatically once enough confirmations are received
- **Transaction Timeout**: Proposals expire if not executed within timeframe

### Role-Based Access Control
- **GOVERNOR_ROLE**: Overall system governance and multi-sig participation
- **MINTER_ROLE**: Propose token minting operations
- **BURNER_ROLE**: Propose token burning operations
- **BLACKLIST_MANAGER_ROLE**: Propose blacklisting/unblacklisting operations
- **PAUSER_ROLE**: Emergency pause/unpause functionality

## Tech Stack
- Solidity ^0.8.26
- Hardhat
- OpenZeppelin Contracts
- TypeScript
- QuickNode for RPC access

## Architecture

The system consists of two main contracts:

1. **GNaira Token Contract**: ERC20 token with governance features
2. **MultiSigWallet Contract**: Handles multi-signature operations and confirmations

## Setup & Deployment

### Installation
1. Clone the repository
   ```bash
   git clone https://github.com/Tochy112/G-Naira.git
   ```
2. Install dependencies
   ```bash
   npm install
   ```
3. Create a `.env` file and populate it with the contents of `.env.example` file
4. Compile using, `npx hardhat compile`
5. Deploy on testnet, `npx hardhat run scripts/deploy.ts --network sepolia`
6. Verify deployed contract on base sepolia testnet


## Contract Addresses

### Find my verified token contract here: 
[https://sepolia.basescan.org/address/0xb6D35a791509B801163d7421e1Eade2eaD7d3d66#code](https://sepolia.basescan.org/address/0xb6D35a791509B801163d7421e1Eade2eaD7d3d66#code)

### Find my verified multi-signature (multiSig) contract here: 
[https://sepolia.basescan.org/address/0x7b44CbD6Dac40D5BD2c8B7e703423EF9AC022e38#code](https://sepolia.basescan.org/address/0x7b44CbD6Dac40D5BD2c8B7e703423EF9AC022e38#code)

## License

This project is licensed under the MIT License.
