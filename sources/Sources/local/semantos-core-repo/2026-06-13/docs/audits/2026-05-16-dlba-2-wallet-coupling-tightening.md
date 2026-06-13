---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/audits/2026-05-16-dlba-2-wallet-coupling-tightening.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.750539+00:00
---

# DLBA.2 audit — tightening DECISION-PENDING-8 effort estimate

**Date**: 2026-05-16
**Status**: Follow-up to `2026-05-16-dlba-2-wallet-entanglement.md` after source-walk audit.
**Effect**: D-Decouple-Wallet effort estimate drops from ~3-4 weeks to **~1 week**.

---

## TL;DR

The previous audit (f0dcbfd) flagged "wallet imports oddjobz handlers + WSITE internals + all DLBA targets" and estimated ~3-4 weeks to decouple. After actually walking the call sites: **the coupling is already optional-pointer-shaped with explicit fallback handling.** Wallet is *designed* to run without oddjobz/WSITE handlers wired — the carve just needs to replace optional-handler-pointer dispatch with dispatcher.dispatch indirection.

## Evidence — what the call sites actually look like

### Oddjobz handler call pattern (wss_wallet/handlers.zig + reactor.zig)

```zig
const handler = backend.oddjobz_ratify orelse {
    // fallback path — wallet handles the "no oddjobz cartridge loaded" case
};
```

Three handlers (`oddjobz_ratify`, `oddjobz_query`, `oddjobz_attention`) declared as `?*Handler = null` optional pointers on the wallet's `Backend` struct (`wss_wallet/types.zig:74,76,84`). Each call site uses the `orelse {}` Zig idiom — the wallet's code path is already structured to handle the absent-handler case.

| File | Call sites |
|---|---|
| `wss_wallet/handlers.zig:277` | `backend.oddjobz_ratify orelse {...}` |
| `wss_wallet/handlers.zig:373` | `backend.oddjobz_query orelse {...}` |
| `wss_wallet/handlers.zig:776` | `backend.oddjobz_attention orelse {...}` |
| `wss_wallet/reactor.zig:790` | `backend.oddjobz_ratify orelse {...}` |
| `wss_wallet/reactor.zig:866` | `backend.oddjobz_query orelse {...}` |
| `wss_wallet/reactor.zig:919` | `backend.oddjobz_attention orelse {...}` |

**Total: 6 call sites.** Not pervasive. Each is a single optional-deref-with-fallback.

### WSITE call pattern (sni_domain_map + site_server + site_config)

```
$ grep -cE "(site_config|site_server|sni_domain_map)\." [wallet files]
wss_wallet/types.zig:1          ← optional pointer declaration
wss_wallet.zig:4                ← 4 references, of which 2 are comments
wss_wallet/handlers.zig:0
wss_wallet/reactor.zig:3        ← of which 1 is a comment
wallet_op_http.zig:1
cli/wallet.zig:1
```

**~5 actual call sites** (excluding comments). `wss_wallet/types.zig:87` declares `operator_domain_map: ?*const sni_domain_map.DomainMap = null` — same optional-pointer pattern as oddjobz handlers.

### Direct DLBA.3-5 imports (payment_ledger, payment_verifier, refund_tx, output_store, header_store)

These remain — wallet does call into payment/headers/output store directly. But these all become **internal to the bsv-anchor-bundle cartridge** after the lift (since DLBA.3-5 are also being lifted into the same cartridge). The intra-cartridge imports are fine; they're the cartridge's own modules.

## Architectural reality (corrected)

The wallet is **not** a "central hub" requiring extensive decoupling. It's a *primary bsv-anchor coordinator* with **two optional plug-in seams** for sibling cartridges (oddjobz handlers + operator-domain map). Both seams already accept null and have explicit fallback paths.

What the carve actually requires:

1. **Lift the bsv-anchor stack as one unit** — wallet + payment + refund + output_store + header_store all move into `extensions/bsv-anchor-bundle/zig/src/`. The intra-stack imports stay intra-cartridge.
2. **Replace 6 oddjobz call sites + ~5 WSITE call sites** with `dispatcher.dispatch("oddjobz", verb, params)` indirection. Same fallback semantics; new indirection through the dispatcher.
3. **Add a `dispatcher: ?*Dispatcher` field on the wallet's Backend struct** so the wallet can route to other cartridges when present. Brain-core boot wires the dispatcher; cartridges register their walkers per the verb_dispatcher pattern.

That's ~11 call-site edits + 1 type-declaration addition + 1 boot-wire update = **bounded work, ~1 week**.

## Updated DECISION-PENDING-8 framing

Original options stand, but the recommendation tightens:

**(a) RECOMMENDED — Decouple before lifting** — write a SMALL `D-Decouple-Wallet` PRD. Effort revised to **~1 week** (from ~3-4 weeks). Specifically:

- DLDC-W.1 (1-2 days): Add `dispatcher: ?*Dispatcher` to `wss_wallet/types.zig` Backend struct alongside the existing optional handler pointers; wire it through brain-core boot.
- DLDC-W.2 (2-3 days): Replace the 6 oddjobz call sites with `dispatcher.dispatch("oddjobz", verb, params)` indirection; preserve the `orelse {}` fallback semantics; inline tests verify the dispatcher path produces identical results.
- DLDC-W.3 (1-2 days): Replace the ~5 WSITE call sites with `dispatcher.dispatch("operator-site", verb, params)` indirection; same fallback pattern.
- DLDC-W.4 (1 day): Verify brain test suite green; V1 prod path preserved (optional pointers default to null when no cartridge wires them; wallet behaviour byte-identical).

Then DLBA.2-5 proceed as **one bundled lift** (wallet + payment + refund + output_store + header_store → bsv-anchor-bundle), per the corrected architectural framing.

(b), (c) options from prior audit still apply but are less attractive now that the decoupling is bounded.

## Consequences for remaining carve timeline

| Phase | Was | Now |
|---|---|---|
| D-Decouple-Wallet PRD | ~3-4 weeks | **~1 week** |
| DLBA.2-5 (as bundled lift, post-decouple) | ~2-3 weeks | ~2 weeks (no internal coupling work needed; intra-cartridge imports stay intra) |
| DLO.3b.2 onward (file-moves per DECISION-PENDING-7) | ~1 week | ~1 week |
| DLO.4-6 (handler carve, REPL, audit) | ~2 weeks | ~2 weeks |
| **Total remaining** | **~8-10 weeks** | **~6-7 weeks** |

**~2-3 weeks pulled forward** purely by reading the actual call sites instead of inferring from imports. The substrate work (DLO.1, DLO.2, DLBA.1, DLO.3a/b.1) was correct; the lift scoping over-estimated coupling.

## What this DOESN'T change

- DECISION-PENDING-7 (DLO.3 rescope) still needs resolution; recommendation stands at option (a).
- The 6 entity-store file-move lifts are still scoped at ~1 week.
- The 4,784 LOC across the 6 wallet files all still move together — DLBA.2-5 are still ONE bundled lift, not 4 sequential lifts. The PRD's "DLBA.2 wallet → DLBA.3 payment → DLBA.4 headers → DLBA.5 fallback" sequencing is wrong because they're already a tightly-coupled stack.
- The PRD claim that "DLBA.5 = brain-core fallback wiring + anchor-unverified back-fill reconciliation" remains valid as the LAST step (after the bundled lift completes).

## Recommendation

Resolve DECISION-PENDING-7 with option (a) [DLO.3 file-move lift] AND DECISION-PENDING-8 with option (a) [now-tightened D-Decouple-Wallet ~1 week]. Combined, the full carve completes in **~6-7 weeks of focused work** with the V1 production guard intact throughout.

## References

- `2026-05-16-dlba-2-wallet-entanglement.md` (prior audit; estimate ~3-4 weeks)
- `runtime/semantos-brain/src/wss_wallet/types.zig:74-87` (optional handler pointer declarations)
- `runtime/semantos-brain/src/wss_wallet/handlers.zig:277, 373, 776` (oddjobz call sites)
- `runtime/semantos-brain/src/wss_wallet/reactor.zig:790, 866, 919` (oddjobz call sites)
- 11 total cross-cartridge call sites in 4,784 LOC of wallet code
