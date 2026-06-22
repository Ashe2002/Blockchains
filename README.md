# Sealed-Bid Vickrey Auction Smart Contract

A Solidity implementation and evaluation of a sealed-bid second-price auction
for a non-fungible token.

## Overview

This project implements a Vickrey auction in which participants submit sealed
bids for an NFT. The highest bidder wins but pays the second-highest bid,
encouraging participants to bid their true valuations under the standard
auction assumptions.

The accompanying report evaluates the contract's functionality, security, gas
efficiency, and user experience. It also compares the implementation with a
classmate's contract to examine alternative design choices.

## Auction Process

1. The seller creates the auction and identifies the NFT.
2. Bidders submit commitments during the bidding phase.
3. Bidders reveal their bids during the reveal phase.
4. The contract identifies the highest and second-highest valid bids.
5. The winner receives the NFT and pays the second-highest amount.
6. Eligible funds are returned to unsuccessful bidders.

## Repository Contents

- `Peer_Contract.sol` - Solidity smart contract.
- `Blockchains_Coursework.pdf` - implementation analysis and evaluation.
- `BDL2025-Coursework_description.pdf` - original coursework specification.

## Evaluation Criteria

- Correctness of the auction mechanism
- Commit-reveal handling
- Security and adversarial behaviour
- Gas consumption
- Refund and payment logic
- User experience
- Comparison with an alternative implementation

## Running the Contract

The contract can be compiled and tested in a Solidity development environment
such as Remix. Select the compiler version compatible with the `pragma`
declaration in `Peer_Contract.sol`, deploy to a local test environment, and test
the bidding and reveal phases with multiple accounts.

This contract was produced for academic analysis and has not been audited for
production use.

## Key Skills Demonstrated

Solidity, smart-contract design, auction theory, commit-reveal mechanisms,
security analysis, gas optimisation, and technical evaluation.

## Academic Context

Coursework completed for Blockchains and Distributed Ledgers at the University
of Edinburgh.
