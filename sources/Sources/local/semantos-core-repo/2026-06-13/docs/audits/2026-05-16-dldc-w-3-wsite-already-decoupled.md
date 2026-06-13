---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/audits/2026-05-16-dldc-w-3-wsite-already-decoupled.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.750283+00:00
---

# DLDC-W.3 audit — WSITE relationship to wallet is already decoupled

**Date**: 2026-05-16
**Status**: DLDC-W.3 closes as a no-op finding. D-Decouple-Wallet reduces to oddjobz-only migration (DLDC-W.2.2 + .2.3, already shipped).

---

## Finding

`docs/audits/2026-05-16-dlba-2-wallet-coupling-tightening.md` (commit 2122bba) flagged "~5 actual WSITE call sites" in wallet code needing dispatcher-route migration. **Source walk shows the count was inflated by doc comments.** Actual code references after filtering comments: **1** (a field declaration on the Backend struct).

The four wallet→WSITE references:
- `wss_wallet/types.zig:87` — `operator_domain_map: ?*const sni_domain_map.DomainMap = null` (Backend struct field declaration; optional injection seam)
- `wss_wallet.zig:70` — doc comment: *"so external callers (`site_server.zig`, `cli.zig`, tests) keep"*
- `wss_wallet.zig:128` — doc comment: *"response. The caller (site_server.handleConnection) then transfers"*
- `wss_wallet/reactor.zig:141` — doc comment: *"path. The caller (site_server.reactorDispatchHttp) also populates"*

Three of the four are documentation referring to `site_server.zig` as a CALLER (i.e. site_server invokes wallet code, populating the Backend struct with its own DomainMap). The wallet doesn't reach into site_server; it just exposes a slot that site_server can fill.

## What this means

The wallet→WSITE relationship is the canonical dependency-injection pattern:

```
                    ┌─────────────────────────────────┐
                    │  site_server.zig (WSITE)        │
                    │                                  │
                    │  constructs:                     │
                    │    let backend = Backend{ ...,  │
                    │      operator_domain_map: my_map │
                    │    };                            │
                    │  then calls wallet handlers      │
                    └────────────┬────────────────────┘
                                 │ DI: site_server provides DomainMap
                                 ▼
                    ┌─────────────────────────────────┐
                    │  wss_wallet.zig (wallet)         │
                    │  Backend has optional field      │
                    │  operator_domain_map; reads it   │
                    │  iff non-null                    │
                    └─────────────────────────────────┘
```

After the cartridge carve:

- **wallet** (in `extensions/bsv-anchor-bundle/zig/src/`) exposes `Backend.operator_domain_map` as an optional DI seam.
- **operator-site** (in `extensions/operator-site/zig/src/`, future D-Lift-wsite cartridge) constructs the wallet's Backend, wires its own DomainMap, then invokes wallet handlers.
- The cartridge boundary holds: WSITE depends on wallet's interface (exported types); wallet has zero knowledge of WSITE.

This is **already** the correct decoupled shape. No migration work needed.

## Consequence for D-Decouple-Wallet effort estimate

Previous estimate (2122bba): ~1 week — 6 oddjobz call site migrations + 5 WSITE call site migrations + verify.

Actual effort:
- DLDC-W.1 (add dispatcher field): pre-shipped (verb_registry already on Backend)
- DLDC-W.2.1 (helper): shipped in 7fa10ad
- DLDC-W.2.2 (handlers.zig 3 oddjobz sites): shipped in 7081e26
- DLDC-W.2.3 (reactor.zig 3 oddjobz sites): shipped in 72d034a
- DLDC-W.3 (WSITE sites): **no-op** (this audit)
- DLDC-W.4 (final gate): one more brain test run + summary doc

**D-Decouple-Wallet completes in ~4 commits over ~1-2 hours of focused work**, not ~1 week. The DLBA.2-5 bundled lift can proceed immediately after DLDC-W.4.

## Why the earlier estimate over-counted

The 2122bba tightening audit pattern-matched on `grep -cE "(site_config|site_server|sni_domain_map)\."` which captures every occurrence including comments. Without filtering `//` lines, doc comments referring to site_server's role inflated the apparent coupling. A future iteration of the audit pattern should filter comments before counting.

This isn't a bug in the audit methodology so much as a useful refinement: line-based counts catch every mention, and references in code comments are noise for coupling-density analysis.

## Updated total remaining carve timeline

| Phase | Was | Now |
|---|---|---|
| D-Decouple-Wallet | ~1 week | **~1-2 hours** (mostly already shipped) |
| DLBA.2-5 bundled lift | ~2 weeks | ~2 weeks (unchanged) |
| DLO.3b.2+ (file-move lifts per PENDING-7) | ~1 week | ~1 week (unchanged) |
| DLO.4-6 (handler carve + REPL + audit) | ~2 weeks | ~2 weeks (unchanged) |
| **Total remaining** | **~6-7 weeks** | **~5-6 weeks** |

Another ~1 week pulled forward by reading the actual code instead of the import declarations.

## References

- `2026-05-16-dlba-2-wallet-coupling-tightening.md` (parent audit; 5 WSITE estimate)
- `runtime/semantos-brain/src/wss_wallet/types.zig:87` (the single optional pointer field)
- Commits 7fa10ad + 7081e26 + 72d034a (DLDC-W.2 implementations)
