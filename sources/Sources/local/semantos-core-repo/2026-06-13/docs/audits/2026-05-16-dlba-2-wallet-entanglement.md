---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/audits/2026-05-16-dlba-2-wallet-entanglement.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.752352+00:00
---

# DLBA.2 audit — wallet code is deeply entangled with oddjobz + WSITE

**Date**: 2026-05-16
**Status**: DECISION-PENDING-8 surfaced; DLBA.2-5 architecture rethink needed before lift.
**Related**: DECISION-PENDING-7 (DLO.3 rescope) still open.

---

## Finding

`docs/prd/D-LIFT-BSV-ANCHOR.md` §Deliverables / DLBA.2 scopes the wallet files lift as a contained migration: move `wallet_op_http.zig`, `wss_wallet/*`, `cli/wallet.zig` into `extensions/bsv-anchor-bundle/zig/src/`.

Audit result: **the wallet is the central hub of brain, not a peripheral component.** It directly imports oddjobz business logic (intent-action-router-shaped patterns), WSITE site-serving code, AND every other DLBA.2-5 target file. The "wallet lift" can't be done in isolation — it'd either drag the entire oddjobz + WSITE + payment + headers stack along with it, or require breaking ~15+ direct imports first.

## Evidence — wallet file imports

Files: `wss_wallet.zig` (545 LOC) + `wss_wallet/{handlers,reactor,types}.zig` (2,313 LOC) + `wallet_op_http.zig` (1,069 LOC) + `cli/wallet.zig` (857 LOC) = **4,784 LOC across 6 files.**

Cross-domain imports captured:

### Oddjobz business-logic imports (cartridge-to-cartridge coupling)
```
const oddjobz_attention_handler = @import("oddjobz_attention_handler");
const oddjobz_query_handler = @import("oddjobz_query_handler");
const oddjobz_ratify_handler = @import("oddjobz_ratify_handler");
```
After the carve, **wallet (bsv-anchor cartridge) directly invokes oddjobz (oddjobz cartridge) handlers.** This violates the cartridge-isolation invariant — cartridges should communicate via the dispatcher seam (`verb.dispatch`) or substrate events, not direct imports across cartridge boundaries.

### WSITE imports (operator-site bundle coupling)
```
const site_config_mod = @import("site_config");
const site_server_module = @import("site_server");
const sni_domain_map = @import("sni_domain_map");
const cli_site = @import("site.zig");
```
Wallet is entangled with the operator-site code — likely because wallet authenticates per-site (HTTP 402 payment-gated routes) and the site renderer needs wallet signatures. WSITE was supposed to be a separate D-Lift-wsite cartridge per the gap analysis.

### Internal DLBA.2-5 cross-imports (all-or-nothing lift)
```
const payment_ledger_mod = @import("payment_ledger");
const payment_verifier_mod = @import("payment_verifier");
const refund_tx_mod = @import("refund_tx");
const output_store_fs_mod = @import("output_store_fs");
const output_store_mod = @import("output_store");
const header_store_fs_mod = @import("header_store_fs");
```
Wallet directly imports payment ledger, payment verifier, refund tx, output store, header store — **all the files DLBA.3, DLBA.4, DLBA.5 are supposed to lift independently.** They're already a single tightly-coupled module from the wallet's perspective. The sequential DLBA.2 → .3 → .4 → .5 sequence in the PRD doesn't match the actual code shape.

### Substrate imports (clean — these stay)
```
const bsvz = @import("bsvz");                  // BSV crypto library
const auth_handler_mod = @import("auth_handler"); // identity substrate
const bearer_tokens = @import("bearer_tokens");
const helm_event_broker = @import("helm_event_broker");
const manifest_registry = @import("manifest_registry");
const cell_query_handler = @import("cell_query_handler");
const http_parser_mod = @import("http_parser");
```
These are all substrate. Wallet's relationship to them is the same as any other cartridge would have.

## Architectural reality

The brain's wallet today is acting as a coordination layer between:
- **BSV substrate** (bsvz, payment, headers, output store) — should be the cartridge's internal scope
- **WSITE** (site serving, per-site config, SNI routing) — should be a separate cartridge per the carve plan
- **Oddjobz business logic** (attention, query, ratify) — should be a separate cartridge per the carve plan
- **Identity/auth substrate** (bearer tokens, auth handler, cell query) — substrate

The "wallet hub" pattern is what the V1 sovereign-node design needed (one wallet serving multiple operator businesses on one box). But it produces tight coupling that defeats the cartridge isolation Phase 36A established.

## DECISION-PENDING-8

Three resolution paths:

(a) **Decouple before lifting** — write an intermediate refactor PRD (call it D-Decouple-Wallet) that breaks the 3 oddjobz imports + 4 WSITE imports by introducing dispatcher-routed verbs or event-bus consumption. This is real architectural work (~3-4 weeks) but unblocks ALL three cartridge lifts (oddjobz, bsv-anchor, wsite) by making the cartridge boundary actually meet the code reality.

(b) **Co-lift bsv-anchor + WSITE as one cartridge** — recognize that WSITE depends on wallet for payment-gated routes; merge DLBA + D-Lift-wsite into a single combined cartridge ("sovereign-bsv-node"). Doesn't fix the oddjobz coupling but reduces 3 cartridges to 2. Carve oddjobz independently (DLO.3 file-move via DECISION-PENDING-7 option a).

(c) **Accept the coupling for V1 OSS** — ship `bsv-anchor-bundle` as a "sovereign-BSV-node bundle" containing wallet + payment + headers + WSITE + the oddjobz-handler-call sites; document that this bundle is the V1 product shape; carve oddjobz separately into its own cartridge with brain-side handlers preserved as wallet's required dependencies. Pragmatic but architecturally muddier.

Recommendation: **(a) decouple before lifting**, because:
- The oddjobz handler imports in wallet code are the same "cartridge calling another cartridge directly" pattern Phase 36A explicitly designed against (Phase 36D governance model puts cartridges in their own scope per the three-tier hierarchy).
- Without decoupling, the DLBA.2-5 lifts produce a `bsv-anchor-bundle` that imports `@semantos/oddjobz` as a hard dep — same problem with a different vendor name.
- The decoupling work (~3-4 weeks) is roughly the same effort as a botched lift would consume in iteration + roll-backs.

## Consequences for remaining carve timeline

With DECISION-PENDING-7 (DLO.3 rescope) option (a) + DECISION-PENDING-8 (DLBA.2-5 entanglement) option (a):

| Phase | Status | Effort estimate |
|---|---|---|
| Substrate primitives (DLO.1, DLO.2, DLO.3a/b.1, DLBA.1, DLBA.1b-int-step1) | ✅ shipped | done |
| DLO.3b.2 onward (entity-store file-moves to extensions/oddjobz/zig/) | ready (pending PENDING-7) | ~1 week |
| **D-Decouple-Wallet** (new PRD; break wallet↔oddjobz + wallet↔WSITE direct imports) | not yet scoped | ~3-4 weeks |
| DLBA.2 wallet lift | blocked on D-Decouple-Wallet | ~1 week after |
| DLBA.3-5 payment/headers/fallback lifts | blocked on D-Decouple-Wallet | ~1-2 weeks total |
| DLO.4-6 handler carve, REPL, audit | blocked on DLO.3 + D-Decouple-Wallet | ~2 weeks |

Total remaining: **~8-10 weeks of focused work** (down from original PRD ~10-12 weeks; DLO.3 rescope saved ~2 weeks, but D-Decouple-Wallet adds ~3-4 weeks).

## What's NOT in this audit

I didn't read wss_wallet.zig source line-by-line — only the import declarations. The actual call sites of oddjobz handlers may turn out to be lighter than the imports suggest (e.g. one or two specific verbs called, not pervasive coupling). A follow-up audit could verify this. If the oddjobz coupling is genuinely thin (≤10 call sites), the decoupling work shrinks proportionally.

## References

- `runtime/semantos-brain/src/wss_wallet.zig` (545 LOC)
- `runtime/semantos-brain/src/wss_wallet/{handlers,reactor,types}.zig` (2,313 LOC)
- `runtime/semantos-brain/src/wallet_op_http.zig` (1,069 LOC)
- `runtime/semantos-brain/src/cli/wallet.zig` (857 LOC)
- `docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md` §6.2 + §6.3 + §10.3
- `docs/prd/D-LIFT-BSV-ANCHOR.md` §Deliverables / DLBA.2-5
- `docs/audits/2026-05-16-dlo-3-rescoped-stores-are-cellstore-consumers.md` (DECISION-PENDING-7, related architecture-mismatch audit)
- `docs/audits/2026-05-16-dlo-1c-already-shipped.md` (prior audit finding)
