---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/cross-matrix-index.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.631629+00:00
---

# Cross-matrix index

## What this is

Semantos has six matrices, each capturing one orthogonal dimension of the project:

| Matrix | Lens | File |
|---|---|---|
| **Canonicalization** | What surfaces are we collapsing? (app architecture) | `docs/canon/canonicalization-matrix.yml` |
| **Unification** | What dimensions does each substrate cover? (engineering completeness) | `docs/canon/unification-matrix.yml` |
| **Singularity** | How deep does one cell go? (proof-of-vision / demo target) | `docs/canon/singularity-matrix.yml` |
| **Compliance** | Who legally cares about which invariant? (regulator-facing) | `proofs/compliance-matrix.json` |
| **CW Lift** | What external research is worth importing? (prof-faustus / Craig Wright BSV repos) | `docs/canon/cw-lift-matrix.yml` (roadmap: `docs/prd/CW-LIFT-ROADMAP.md`) |
| **RTC** | How does real-time calling/streaming compose? (shell-native voice/video/metered-stream substrate) | `docs/canon/rtc-matrix.yml` (roadmap: `docs/prd/RTC-ROADMAP.md`) |

The four are intentionally orthogonal — a meta-matrix would smear them. What's missing instead is **traceability**: when a chunk of work lands, which cells does it advance across *all four* lenses at once?

This index is that view. One row per significant landed theme (a PR stack, not individual PRs). Hand-edited. Added to as part of the merge-the-stack ritual.

A future renderer can consume these rows + the matrix YAMLs to auto-tally cross-cuts; for now the doc itself is the dashboard.

## Theme rows

### 3. C11 Root Identity "me" surface — wallet sub-track lands (re-tally PR, 2026-05-31)

**No new functional work** — instead, an **honest re-tally** of C11's axes against the code that actually exists in `apps/semantos/lib/shell/me/` + `apps/semantos/lib/src/wallet/`. The wallet sub-track of C11 landed across multiple parallel sessions without the matrix getting updated; the 2026-05-31 re-tally PR closes that gap.

Axes that moved on C11:

| Axis | Before | After | What it means |
|---|---|---|---|
| A — Source extracted | ✗ | ✓ | `apps/semantos/lib/shell/me/` (5 files) + `apps/semantos/lib/src/wallet/` (10+ files) all in tree, with substance |
| B — Target wired | ✗ | ⚠ | Helm AppBar + wallet row in me_sheet wired; first-run cert guard in main.dart still missing |
| C — Tests pass | ✗ | ⚠ | 111 wallet tests passing; shell test suite for boot/secret-question/envelope still ✗ |
| E — PWA-side | ✗ | ⚠ | Wallet portion done; recovery + secret-question UIs scaffolded but not verified end-to-end |
| F — Wallet integration | ⚠ | ✓ | wallet.html + loopback HTTP + JS bridge complete at C11 scope (tx.request deferred to C11-7 by design) |
| I — Docs | ✗ | ⚠ | HELM-ME-SURFACE.md + WALLET-RENDERER-CONTRACT.md + PLEXUS-ALIGNMENT.md exist; glossary additions still pending |

Axes unchanged: D (brain alignment ⚠), G (envelope flow ✗), H (intent pathway ✗), J (n/a).

| Matrix | Cells advanced | Notes |
|---|---|---|
| **Canon** | `D-CANON-C11-A` (✗→✓), `D-CANON-C11-B/C/E/I` (✗→⚠ — explicit naming of remaining gaps), `D-CANON-C11-F` (⚠→✓). | Re-tally not new build; reflects code state that already existed. |
| **Unification** | None — this is documentation honesty, not substrate advance. | |
| **Singularity** | None. | |
| **Compliance** | None directly; wallet identity binding work indirectly supports K2 (authorization bounds) downstream of Phase-1b BCA. | |

**Genuine remaining work on C11** (the matrix now names these explicitly):

- **Axis B**: first-run flow gate in `main.dart` — when `IdentityStore` reports no root cert, route to onboarding instead of the helm.
- **Axis C**: shell widget tests for boot-with-vs-without-cert, secret-question round-trip, envelope generate + reload.
- **Axis E**: end-to-end verification of recovery envelope + secret-question flows (Dart widgets exist; bridge + brain plumbing unverified).
- **Axis G**: PlexusRecoveryEnvelope codec brain wiring + Plexus-RaaS opt-in flow.
- **Axis H**: `me.identity.*` shell-namespace cells minted via IntentDispatcher.

These five are the concrete next moves to flip C11 to full ✓.

Also folded into this PR: comment cleanup in `wallet_launch.dart` — the file header + line 143 said "deferred to PR-C11-4e" for the SemantosWallet JS channel that's now clearly already implemented. Rewrote to reflect current state + reference the live `WalletBridge.handle()` verb table.


---

### Excised: 2PDA-WASM substrate stack + engine-config enforcement (PRs #746-#753 + #755 + #756, walked back 2026-05-31 in PR #760)

Earlier theme rows for the 2PDA-WASM substrate stack and its engine-config follow-ups occupied this slot. Both were excised in PR #760 in favor of cell-engine scripts dispatched through C10's PolicyRuntime adapter (`runtime/semantos-brain/src/policy_runtime.zig::evaluateReal`). The cell-engine 2PDA already provides every primitive the WASM-handler layer was re-implementing — Plexus opcodes (OP_CHECKLINEARTYPE/AFFINETYPE/RELEVANTTYPE, OP_CHECKCAPABILITY, OP_CHECKIDENTITY, OP_CELLCREATE, OP_DEMOTE, OP_SIGN), OP_CALLHOST (0xD0) + `host_capability_table` for hostcall capability gating, and bounded execution via opcount + script-size + nesting caps. Cell-type handlers as cell-engine bytecode declared in `cellTypes[i].handler.script` is the unified-substrate replacement; PR #760 ships PR1 (excise) -> PR2 (`LINEAR-CELL-SPV-STATE.md` rewrite around OP_CALLHOST + `host_capability_table` not `kernel_*` WASM imports) -> PR3 (manifest schema) -> PR4a (load infrastructure) -> PR1.5 (engine-config orphan + dead `lookupByName` cleanup). Execution wiring (PR4b: direct `executor.execute` vs PolicyRuntime extension), first script handler (PR5: `bsv-spv-verify` as cell-engine bytecode), and C10 finish-the-flips (PR6) follow in separate PRs.

Compliance/Canon/Unification/Singularity claims previously attached to those excised rows revert with them. Independent fixes that were preserved across the excise: the EPHEMERAL Linearity variant in `cartridge_cell_registry.zig` + `cells_mint_handler.zig` + `site_server/reactor.zig` (TS/Zig drift closure from 7e-2f), and `broker.checkInvocationCapabilities` as a generic capability gate for the future script-handler dispatcher.

## Cross-cutting deferrals (blockers spanning multiple matrices)

Single dependencies that, when they un-park, will advance cells in multiple matrices at once. Worth tracking here because they don't fit cleanly in any single matrix's track structure.

| Blocker | Matrices it advances | When it lands |
|---|---|---|
| **Phase-1b BCA cert verifier** | Canon C6/C11 (real cert chain in PWA + brain), Unification U3 (Identity body, not just seam), Singularity L5 (real per-device identity), Compliance multiple (K2 authorization bounds become enforceable in code, not just structurally) | Closes the cert-verifier deferrals across the substrate. |
| **Federation handshake** (Bridget at `brain.utxoengineer.com`) | Canon (no current track — would be C14+), Unification U6 Mesh, Singularity L3 Transport | Not blocked on this repo; blocked on a time-zone-aligned window with Bridget. |
| **Engine-checked DATA_ACCESS access-grant** (the `access.grant` cell-type family + verify `.handler` on the real 2-PDA via the `ScriptContextBuilder` seam — see the Engine-Checked Data Access plan) | **RTC** axis A *authorization* half on A4/A1/A3 + S5-A (the grant is the engine-checked admission gate / MLS membership source); Unification D-cap (capability via BRC-108, now engine-evaluated not advisory); Compliance K2 (authorization bounds enforced by the cell engine, not app TS) | Slice 1 (engine-checked verify/read gate) in flight in a parallel session. RTC A4's swarm `ServePolicy` reuse waits on that plan's deferred **Transfer-integration** slice (seeder runs the verify `.handler` before serving) — same deliverable, two lenses. |

These are the cells that aren't moving today not because we don't know how, but because they're waiting on a specific gate to clear.

> **Note on the RTC matrix and the access-grant convergence.** RTC axis A (`docs/canon/rtc-matrix.yml`) is really two halves: *authentication* (DTLS `a=fingerprint` pinned into the SignedBundle — the media endpoint is the cert holder) and *authorization* (the cert holder is permitted to join). The engine-checked `access.grant` family delivers the authorization half as a substrate primitive, so RTC A4 (broadcast/VOD over the swarm) and the S5 MLS membership source should bind to it rather than re-implement a cert check. The grant is evaluated at **admission time** (subscribe / join), never per media packet — consistent with RTC §7 (media rides native SRTP; the 2-PDA path carries the authz decision + metering receipts, not frames). Interactive calls want a `SESSION_ACCESS` sibling capability to file-share's `DATA_ACCESS` — identical apparatus, different capability type.

## How to add a row

When a stack lands (typically 3+ PRs that ship a coherent architectural move):

1. Read the four matrices, identify which cells the stack actually advances. Be honest about partial advances and structurally-enabled-but-not-realised cases.
2. Cite cells by their canonical deliverable IDs:
   - Canon: `D-CANON-C{track}-{axis}` (axes A–J)
   - Unification: `D-UNIF-U{n}-{axis}` (axes A, B, C, D-sub, D-lex, D-form, D-cap, E, F, G)
   - Singularity: `D-SG-L{n}-{axis}` (axes A–J)
   - Compliance: `{framework} §{requirement-id}` (no D- prefix; the framework + id is the canonical reference)
3. Add a "Known deferrals carried" subsection if the stack honestly defers any guarantees — those become candidates for the cross-cutting deferrals table below.
4. Order rows newest-first under "Theme rows."

The matrix YAMLs themselves stay the source of truth for per-cell status. This doc is the join across them — never duplicate cell status here, just *reference* which cells a stack touched.

## Renderer (future)

`docs/canon/render/cross-matrix-to-dashboard.ts` (not yet written, ~200 LOC) would consume:

- The four matrix YAMLs (for current cell statuses + tallies)
- This index doc's theme rows (for who advanced what)
- The cross-cutting deferrals table (for what's blocked)

…and emit a single dashboard MD showing: per-matrix % complete, recent landings × matrices heat-map, "next likely cell to flip" based on cross-cutting unblockings. Worth building once 3–5 theme rows accumulate and the value of the auto-join becomes obvious.

Until then, this hand-edited doc is the dashboard.
