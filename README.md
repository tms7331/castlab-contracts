# CastLab Smart Contracts

Smart contracts for CastLab, a [Farcaster](https://www.farcaster.xyz/) [mini app](https://miniapps.farcaster.xyz/docs/getting-started) for crowdfunding and betting on scientific experiments. This repository contains the Solidity contracts that power experiment crowdfunding and prediction markets on Base network.

## About CastLab

CastLab represents the beginning of exploring prediction markets for science.  Read more about it in the main repo: [github.com/tms7331/castlab](https://github.com/tms7331/castlab)

## What This Repository Contains

### CastLabExperiment Contract

A unified smart contract combining two complementary mechanisms:

**1. Experiment Crowdfunding**
- Community members fund scientific experiments exploring Farcaster protocol behavior
- Experiments have minimum and maximum funding goals (costMin/costMax)
- Once funded successfully, experiment administrators withdraw USDC to conduct research
- Failed experiments are fully refunded to contributors
- Contribution records preserved for possible NFT claim eligibility

**2. Binary Prediction Markets (Parimutuel)**
- Users bet on experiment outcomes using USDC in a parimutuel-style market
- Two-sided markets: bet on outcome 0 or outcome 1
- Winners receive proportional payouts from the total betting pool (the pool is divided among those who guessed correctly, with payouts proportional to their stakes)
- 60-day timeout protection: withdraw bets if administrators don't set results


### Prerequisites

This project uses [Foundry](https://book.getfoundry.sh/), a blazing fast toolkit for Ethereum development.

## License

MIT License
