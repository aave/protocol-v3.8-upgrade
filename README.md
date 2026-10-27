# Aave V3.8 upgrade process

This document outlines the technical process for upgrading the Aave V3 protocol from version 3.7 to version 3.8.

v3.8 adds a transient reentrancy guard to the `Pool` ([changelog](lib/aave-v3-origin-private/docs/3.8/Aave-v3.8-changelog.md)). Only the `Pool` implementation changes. The `PoolConfigurator`, tokens, config engine and data providers stay on their v3.7 deployments.

## Core components of the upgrade

1. **New implementation:** a new `PoolInstance` (or `L2PoolInstance` on rollups) at `POOL_REVISION` 12. Its `RESERVE_INTEREST_RATE_STRATEGY` is read from the live pool at deploy time.
2. **Libraries:** the five logic libraries are CREATE2-deployed with the aave-v3-origin salt (`AAVE_V3_LIBRARIES_BATCH`). Compiled for `cancun`, only `FlashLoanLogic` gets a new address. The other four resolve to their existing v3.7 deployments and are skipped.
3. **Upgrade payload:** `UpgradePayload` calls `POOL_ADDRESSES_PROVIDER.setPoolImpl(POOL_IMPL)`.
4. **Deployment script:** `Deploy.s.sol` has one script per market. It deploys the libraries, the pool implementation and the payload.

## Payload checks

| When | Reverts with | Unless |
| --- | --- | --- |
| constructor | `WrongAddresses` | `poolImpl.ADDRESSES_PROVIDER()` equals the live pool's |
| constructor | `WrongPoolRevision` | `poolImpl.POOL_REVISION()` is 12 |
| constructor | `WrongInterestRateStrategy` | `poolImpl.RESERVE_INTEREST_RATE_STRATEGY()` equals the live pool's |
| `execute()`, before upgrade | `WrongPoolRevision` | the live pool is at revision 11 |
| `execute()`, after upgrade | `WrongPoolRevision` | the live pool is at revision 12 |

## Libraries

| Library | Address |
| --- | --- |
| BorrowLogic | `0x52Da0ce88202D1542543598D1e1e27F0d344726A` (v3.7, unchanged) |
| FlashLoanLogic | `0xC27a4d7AC0623B129919786d88714eF16132BEaE` (new) |
| LiquidationLogic | `0x96D5686812e33Ab509ECCDb38C89d15607B2a413` (v3.7, unchanged) |
| PoolLogic | `0xD70593841C57cbaA04957cc3EAcE95708e48853b` (v3.7, unchanged) |
| SupplyLogic | `0x584C7d8c4cb05304FE5Ac7fbc97f20A10Fb07564` (v3.7, unchanged) |

## Markets

| Market | Chain id | Pool | Deploy |
| --- | --- | --- | --- |
| Ethereum Core | 1 | L1 | `make deploy chain=mainnet` |
| Ethereum Lido | 1 | L1 | `make deploy-lido` |
| Plasma | 9745 | L1 | `make deploy chain=plasma` |
| Avalanche | 43114 | L1 | `make deploy chain=avalanche` |
| BNB | 56 | L1 | `make deploy chain=bnb` |
| Monad | 143 | L1 | `make deploy chain=monad` |
| Polygon | 137 | L1 | `make deploy chain=polygon` |
| Gnosis | 100 | L1 | `make deploy chain=gnosis` |
| Celo | 42220 | L1 | `make deploy chain=celo` |
| Base | 8453 | L2 | `make deploy chain=base` |
| Arbitrum | 42161 | L2 | `make deploy chain=arbitrum` |
| Optimism | 10 | L2 | `make deploy chain=optimism` |
| Mantle | 5000 | L2 | `make deploy chain=mantle` |
| Ink | 57073 | L2 | `make deploy chain=ink` |
| X Layer | 196 | L2 | `make deploy chain=xLayer` |
| Linea | 59144 | L2 | `make deploy chain=linea` |
| MegaETH | 4326 | L2 | `make deploy chain=megaeth` |

Metis is excluded: `TSTORE` reverts on Andromeda. Ethereum EtherFi, Sonic and Scroll are on v3.7 but deprecated, so they are not upgraded. After deploying, set the payload address in `src/Deployments.sol` so the tests run against the deployed payload.
