# Vendored dependencies

All Solidity dependencies are ordinary files under `lib/`. No package manager,
submodules, or network access are needed to build or test once Solidity 0.8.26 and
Foundry are installed. The application imports only the ERC-20 dependency below;
forge-std is used only by tests.

| Dependency | Pinned release | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2) | v5.0.2 | ERC20, IERC20, IERC20Metadata, Context, draft-IERC6093, LICENSE | MIT |
| [Forge Standard Library](https://github.com/foundry-rs/forge-std/tree/v1.9.6) | v1.9.6 | `src/**/*.sol`, LICENSE-APACHE, LICENSE-MIT | Apache-2.0 OR MIT |

These files are unmodified release sources. Their upstream copyright and license
notices are retained. `DEPENDENCIES.sha256` lists the SHA-256 hash of every included
file. Check them from the repository root with:

```sh
sha256sum --check DEPENDENCIES.sha256
```

Archive provenance:

- `https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2`
  — SHA-256 `18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a`.
- `https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.6`
  — SHA-256 `53d2b498183cb7dc62cf726cc6c1a222ad728b0d87976a877ca1f3ed3707b1c6`.
