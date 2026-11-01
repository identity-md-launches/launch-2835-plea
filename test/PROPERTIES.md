# PLEA test properties

The specification is `plea` / `PLEA`, 18 decimals, and exactly
`1_000_000_000 * 10**18` units minted once to the immediate deployer. Tests exercise
the production `PleaToken`; no derived contract exposes minting or changes its logic.

## Discovery and coverage

The five discovery passes from the supplied Pashov fizz reference were performed
locally. The Trail of Bits property-testing reference informed the bounded input
generators, explicit boundary cases, and algebraic properties. The table records
the resulting properties and their basis; all are expected to hold.

| Discovery pass | Property and implementation basis | Coverage |
| --- | --- | --- |
| Conservation | Fixed supply from `src/PleaToken.sol:10` and constructor at line 14; sum of balances equals supply. Each actor owns exactly what it initially received plus incoming transfers minus outgoing transfers. | Deployment tests; aggregate and individual-balance invariants. |
| State transitions | `ERC20.transfer`, `approve`, and `transferFrom` at lines 109, 132, and 154 of the vendored ERC20 implementation. Approval replaces the budget; only delegated spending consumes it. Reverts preserve balances and allowances. | Independent allowance invariant over all 16 owner/spender pairs; replacement, revocation, isolation, failure and retry tests. |
| Round trips | Exact, fee-free integer transfers in `ERC20._update` at line 188. Sending an amount and returning it restores both balances; splitting a transfer preserves its result. | Stateful round-trip handler; split-versus-single-transfer fuzz test; one-unit regression. No share conversion or rounding mechanism exists here. |
| Adversarial sequences | Sender balance and caller allowance checks in `ERC20._update` and `_spendAllowance` at lines 188 and 305. A caller cannot spend another holder's balance without approval, including the deployer. Valid full-balance transfers must succeed. | Repeated spending, wrong owner/caller/origin, full-balance and dust handlers, overspending, balance failure with sufficient approval, and zero-recipient rejection. |
| Token-specific boundaries | Zero-address guards in `ERC20._transfer` and `_approve` at lines 171 and 284; infinite-allowance sentinel in `_spendAllowance` at line 305. | Explicit zero, one, full supply, `uint256.max - 1`, and `uint256.max` cases; self-transfers, finite/infinite allowances, constructor mint event, and transfer/approval events. |

## Stateful model

`PleaToken.invariant.t.sol` retains the existing closed set of four actors and
starts with the whole supply assigned to the first actor. Ghost `received` and
`sent` counters record requested, successful transfers. Ghost allowances record
approved budgets and authorized spending. None of these values is initialized or
updated by copying the token's balances or allowances.

Successful calls are bounded using this independent history. Expected failures
include deliberately sufficient approval followed by an insufficient-balance
transfer, so the allowance rollback path cannot be hidden by an earlier allowance
error. Zero-recipient calls exercise both direct and delegated transfers. Every
rejected call leaves the ghost transfer history unchanged.

After each handler action, Foundry checks fixed supply, aggregate conservation,
each actor's entitlement, and every owner/spender budget. This catches incorrect
redistribution even when total supply and aggregate balances remain correct.
Inline settings select 256 runs of depth 64 and treat unexpected handler reverts
as failures. Stateless fuzz tests use 1,024 cases each.

## Running

The added tests need no RPC, FFI, new dependencies, or configuration changes.
Use the assignment's seed for reproducibility:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0xf2ae4f21891ac3ff59777e07b306ab357663aa0e43a31254c5f242965f208e63 forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

Build output and cache stay in the disposable scratch directory. The supplied
protected launch checks were read as acceptance inputs; their full factory and
Uniswap integration requires the separate protected harness. The local factory
fixture checks constructor ownership and exact distribution and claim transfers.
No live AMM execution is claimed by these local tests.
