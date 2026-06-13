---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/audits/2026-05-16-dlba-cli-files-stay-in-brain.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.750027+00:00
---

# DLBA cli/wallet + cli/headers stay in brain-core as adapter glue

**Date**: 2026-05-16
**Status**: Closes DLBA.2.18 + DLBA.4.5 as deferred-by-design. The bsv-anchor cartridge file-lift carve is **COMPLETE** for everything except CLI adapter wrappers, which stay brain-side intentionally.

---

## Finding

Lifting `runtime/semantos-brain/src/cli/wallet.zig` + `cli/headers.zig` into the bsv-anchor-bundle cartridge requires module-conversion (Zig forbids cross-module relative imports). The blocker is `cli/common.zig` — a substrate-shaped CLI helper file imported by **10** cli/*.zig files via relative path `@import("common.zig")`. Moving any individual cli/*.zig out of brain-core breaks its common.zig import.

To lift cli/wallet + cli/headers cleanly, we'd need to convert cli_common to a build.zig-managed module AND make each cli/*.zig its own module — a brain-substrate refactor touching 10+ files for the benefit of two CLI command-interface files.

## Decision: don't lift them

cli/wallet.zig and cli/headers.zig are **CLI command-interface adapter glue**, not cartridge code:
- They consume cli_common (ExitCode, Output, args parsing) — brain-substrate helpers
- They invoke the lifted cartridge code via `@import("wallet_op_http")`, `@import("headers_sync")`, etc. — module names that now resolve to the cartridge dir per the build.zig path updates
- The cartridge OWNS the actual wallet protocol + payment + headers logic; cli/* files just wrap those for command-line invocation

This is the conventional split: brain owns the operator surface (CLI parsing, formatting, exit codes); cartridge owns the protocol/storage code. CLI wrappers are brain-substrate.

## Consequences for the no-bsv-anchor audit

The DLBA.2-5 completion gate scopes "brain-core no-bsv-anchor audit" as: `grep -rln "wallet|payment|refund|header_store|headers_sync|headers_http" runtime/semantos-brain/src/` matches only substrate-shaped names.

After this decision:
- cli/wallet.zig (857 LOC) — stays in brain-core. Adapter glue.
- cli/headers.zig (492 LOC) — stays in brain-core. Adapter glue.
- All 18 other bsv-anchor source files are in the cartridge.

The audit grep WILL match cli/wallet.zig + cli/headers.zig + cli.zig's `@import("cli/wallet.zig")` + `@import("cli/headers.zig")` lines. These are acceptable matches per the adapter-glue framing.

For a fully-clean grep, future work could convert all cli/* to modules + lift cli/wallet + cli/headers. That's an enhancement, not a blocker for the carve completion.

## What the cartridge contains now

`extensions/bsv-anchor-bundle/zig/src/` — 18 files / ~7028 LOC:

```
src/
├── refund_tx.zig + refund_tx_stub.zig
├── payment_verifier.zig + payment_verifier_stub.zig
├── payment_ledger.zig
├── output_store_fs.zig
├── header_store_fs.zig
├── headers_sync.zig
├── headers_http.zig
├── wallet_op_http.zig
├── wss_wallet.zig
├── wss_wallet/
│   ├── types.zig
│   ├── handlers.zig
│   └── reactor.zig
├── lmdb/
│   ├── output_store_lmdb.zig
│   ├── lmdb/header_store_lmdb.zig
│   └── derivation_state_store_lmdb.zig
└── resources/
    └── headers_handler.zig
```

Plus the scaffold files from DLBA.1a:
- README.md, package.json, manifest.json, tsconfig.json, release.config.ts
- src/{index,manifest,capabilities}.ts
- zig/build.zig + zig/build.zig.zon + zig/src/root.zig

## What's NEXT

**bsv-anchor file-lift carve is COMPLETE** (modulo cli/* adapter-glue staying brain-side per this audit). Remaining carve work:

- **DLO.3** — Lift oddjobz entity stores (jobs/quotes/invoices/customers/leads/visits — 6 files) into `extensions/oddjobz/zig/src/`. Same mechanical pattern as bsv-anchor lifts.
- **DLO.4** — Resource handler carve + verb_dispatcher walker registration
- **DLO.5** — REPL contributions + intent_action_router lift
- **DLO.6** — Brain-core no-oddjobz audit (grep returns only adapter-glue matches, mirroring this audit's decision pattern for bsv-anchor)

## References

- `docs/prd/D-LIFT-BSV-ANCHOR.md` (parent PRD)
- `docs/audits/2026-05-16-dlba-2-wallet-coupling-tightening.md` (PENDING-8 tightening)
- `runtime/semantos-brain/src/cli/common.zig` (the 10-importer file blocking module-conversion)
- Commits 75cccf6 through d805827 (all 18 bsv-anchor lift commits on main)
