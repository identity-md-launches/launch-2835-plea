# plea (PLEA)

`src/PleaToken.sol:PleaToken` is a fixed supply ERC-20. Its constructor mints the
entire supply once to `msg.sender`, the immediate deploying address.

| Property | Value |
| --- | --- |
| Solidity contract name | `PleaToken` |
| Token name | `plea` |
| Symbol | `PLEA` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Initial recipient | Immediate deployer (`msg.sender`) |
| ETH required by constructor | `0` |
| Admin or owner | None |

## Design and assumptions

The requested token uses ordinary ERC-20 transfers and approvals. No tax, transfer
fee, burn, rebase, pause, blacklist, seizure, permit, proxy, or upgrade mechanism
is included. There is no external mint function, initializer, or post-deployment
configuration. The named constant `INITIAL_SUPPLY` is `1_000_000_000 * 10 ** 18`;
the inherited ERC-20 decimals value is 18.

The contract uses the vendored OpenZeppelin Contracts v5.0.2 ERC-20 implementation
without overrides. Transfers deliver exactly the requested amount, including
transfers to contracts. Successful `transfer`, `approve`, and `transferFrom` calls
return `true`; invalid calls revert with ERC-6093 custom errors. Zero-value
transfers are supported, while transfers to the zero address and approvals to a
zero spender revert. Self-transfers preserve the balance. `transferFrom` requires
allowance even when called by the holder; zero-value delegated transfers between
nonzero addresses require no positive allowance.

Finite allowances decrease on spending. An allowance of `type(uint256).max`
remains unchanged until explicitly replaced or revoked. `approve` replaces the
previous allowance and emits `Approval`. Transfers, including the constructor's
single mint, emit `Transfer`. This OpenZeppelin version does not emit `Approval`
when `transferFrom` consumes an allowance; integrations should query `allowance`.
Failed operations roll back balances and allowances together.

## Build and check

Use Foundry with Solidity **0.8.26**, pinned in `foundry.toml`. The build targets
Cancun (supported on the specified Ethereum deployment chain), enables the
optimizer with 200 runs, and sets `bytecode_hash = "none"` for reproducible launch
bytecode. Libraries are vendored as ordinary files; see [DEPENDENCIES.md](DEPENDENCIES.md).
No RPC, credentials, FFI, or filesystem permissions are required.

From the repository root:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xf2ae4f21891ac3ff59777e07b306ab357663aa0e43a31254c5f242965f208e63 forge test
forge fmt --check
sha256sum --check DEPENDENCIES.sha256
```

The tests do not read or change environment variables and run without a fork.
The command above supplies the assignment's fuzz seed to Foundry, not to any test.
Fuzz tests run 1,024 cases each. Stateful invariants run 128 sequences of 64 calls
each with unexpected reverts treated as failures.

The suite covers metadata, the exact mint and event, deployment through a CREATE2
factory with a distinct transaction origin, exact launch allocation transfers,
direct and delegated transfers, self/zero transfers, approvals and revocation,
infinite allowances, unauthorized spending, insufficient balances/allowances,
invalid addresses, atomic failure rollback, and rejected privileged calls.
Stateful tests check supply and balance conservation across randomized transfers,
approvals, revocations, and failed spending attempts.

The allocation fixture models distribution and pool-direction token transfers;
it is not a Uniswap AMM test. The supplied protected integration checks depend on
the separate launch harness, its contracts, and resolved launch parameters. They
are read as acceptance definitions and are not included in this local test suite.

## Deployment parameters

Deploy the creation bytecode for **`src/PleaToken.sol:PleaToken`**, without constructor
arguments, linked libraries, or ETH. A direct deployment credits the deploying
account. A factory deployment credits the factory itself, not the transaction
origin or the caller of the factory. The deploying contract must therefore be
able to distribute its tokens. There are no constructor calls to other contracts
and no chain-specific addresses in the token.

The assignment's Ethereum launch factory is responsible for the later distribution:
10% to its distributor, 77% for pool liquidity, and 13% to the requester-designated
remainder recipient. Those allocations are not constructor transfers. The token
holds no reserved allocation and supplies no application contracts. The separate
launch manifest step supplies the pool and economic parameters from the assignment;
this repository does not supply a `launch.json` or execute transactions.

Before release, the launch operator should build with the pinned settings, review
the creation bytecode and ABI, and have the source independently reviewed. After
deployment, the operator should verify the source on the chain explorer and check
the name, symbol, decimals, `totalSupply`, initial mint event, and factory distribution.

## After launch

There are no settings to configure, admin keys to transfer, or maintenance calls.
The launch factory and distributor handle liquidity and contributor claims outside
this token. Holders control transfers and allowances; the deployer has no special
authority over a holder's tokens.

Holders and integrators are responsible for recipient addresses and approval sizes.
Prefer exact allowances and revoke unused ones. When replacing an existing
allowance, first set it to zero and wait for confirmation before setting the new
amount to reduce the standard ERC-20 allowance race. Check the resulting balance
and allowance: a spender may use its old allowance before the revocation confirms.

There is no recovery function. Tokens sent to this token contract, or to a contract
that cannot transfer them onward, are inaccessible. Ordinary ETH sends revert, and
any forcibly credited ETH cannot be withdrawn. No pause or upgrade can repair a
mistaken transfer or change deployed behavior.

The local tests and manual review are not an independent security audit. Independent
adversarial review and the launch integration checks remain release responsibilities.
