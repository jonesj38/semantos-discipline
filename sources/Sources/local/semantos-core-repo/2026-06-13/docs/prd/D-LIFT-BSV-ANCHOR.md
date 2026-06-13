---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/D-LIFT-BSV-ANCHOR.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.714420+00:00
---

# D-Lift-bsv-anchor — Carve BSV wallet/headers/payment out of brain-core into a `bsv-anchor-bundle` cartridge

**Version**: 0.2 (decisions resolved 2026-05-16; Deliverables section authoring in flight)
**Date**: 2026-05-15 (initial draft); 2026-05-16 (decisions resolved)
**Status**: Carve ~90% done — `cartridges/bsv-anchor-bundle/brain/zig/` (wallet_op_http, output_store_fs, wss_wallet, headers_http, payment_verifier, header_store_fs, refund_tx, reorg_sink) + `cartridges/wallet-headers/brain/` both exist as of 2026-05-25. Both DECISION-PENDINGs resolved by Todd 2026-05-25: PENDING-1 = `cartridges/` (per CC4 canonical layout); PENDING-2 = recommendation (c) mark cartridges as anchor-unverified until backend loads. **New work scope reframed:** brain consumption of the carved cartridges via the new order 3a in [UNIFICATION-ROADMAP §11.10](UNIFICATION-ROADMAP.md) — anchor every cell on write. See §11.10 v0.12 entry for architecture.
**Duration**: ~4-6 weeks (initial estimate; refine after deliverables section is scoped)
**Prerequisites**:
- Phase 26C complete (AnchorAdapter shipped in `core/protocol-types/src/anchor.ts` + `bsv-anchor-adapter.ts`)
- Phase 26G complete (Node Packaging — Dockerfile + install.sh + semantos CLI)
- Phase 36A complete (Extension Grammar JSON Schema)
- BRAIN-DISPATCHER-UNIFICATION Phase 0 complete (`dispatcher.zig` keystone)
- `tools/cartridge-scaffold/` for cartridge-skeleton generation

**Master document**: [`docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md`](../CARTRIDGE-DISTRO-GAP-ANALYSIS.md) §6.2 + §6.3 + §10.3
**Companion PRD**: [`docs/prd/D-LIFT-ODDJOBZ.md`](D-LIFT-ODDJOBZ.md) (separate carve for oddjobz code)
**Related sweep**: [`docs/prd/PHASE-29.5-KERNEL-ENFORCEMENT-SWEEP.md`](PHASE-29.5-KERNEL-ENFORCEMENT-SWEEP.md) Gap 3 ("Plexus adapter not wired to terminal events") is the design reference for the anchor-emission call site. Its TS prototype shipped at `packages/policy-runtime/src/anchor-emitter.ts` (consumed by CDM/SCADA demos — per Todd 2026-05-25 not load-bearing). The brain's Zig anchor-emitter analogue is yet to be built; once it exists, this PRD ships the BSV `AnchorAdapter` implementation that the brain's analogue invokes for on-chain anchoring. Sequence captured in [UNIFICATION-ROADMAP.md §11.10](UNIFICATION-ROADMAP.md).
**Branch prefix**: `lift/bsv-anchor`

---

## Context

`runtime/semantos-brain/src/` today contains 25+ files implementing BSV-specific anchoring, wallet, payment, and SPV-header concerns. These files are *currently* baked into brain-core, but they implement what the Phase 26 architecture defines as the **AnchorAdapter** and **IdentityAdapter** interfaces — substrate consumption seams that any cartridge can plug into.

The mismatch is structural: Phase 26 (Apr 2026) shipped the four adapter interfaces. Phase 26G (Apr 2026) shipped the brain binary distribution mechanism. Phase 36A (Apr 2026) shipped the cartridge contract. But the brain that Phase 26G's Dockerfile packages **still has the BSV anchor backend hard-coded into its kernel**.

This PRD scopes the carve.

### Why this matters

1. **The distro pattern needs it.** The "brain as Linux-distro experience loader" framing (`docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md` §1) requires that anything user-visible — and anything chain-specific — load as a cartridge. Today, a fresh `semantos node install` from the Phase 26G installer ships a brain with BSV signing, BRC-42 derivation, ARC broadcasting, BHS header sync, and a payment-ledger FSM baked in. That's not a substrate; that's a sovereign-BSV-node product wearing a substrate hat.

2. **The OSS pitch depends on it.** Per `oss_substrate_carve_parked.md`: the OSS substrate is materially stronger as *"a substrate that hosts arbitrary anchored cartridges, of which `bsv-anchor-bundle` is the reference"* than as *"Semantos's BSV sovereign node, source-available."* The architectural difference is real — and lifting wallet/headers/payment out of brain-core makes it legible in the code, not just in marketing.

3. **The anchor primitive is already an interface.** `core/protocol-types/src/anchor.ts` defines `AnchorAdapter` and there's both a `bsv-anchor-adapter.ts` and a `stub-anchor-adapter.ts`. The interface contract exists. What's missing is **brain consuming the interface instead of consuming concrete BSV calls**.

### What this PRD covers

Move the following files out of `runtime/semantos-brain/src/` into a new cartridge at `extensions/bsv-anchor-bundle/` (final location TBD — DECISION-PENDING-1):

**Wallet (BRC-42 derivation + signing + WSS surface):**
- `runtime/semantos-brain/src/wallet_op_http.zig`
- `runtime/semantos-brain/src/wss_wallet.zig`
- `runtime/semantos-brain/src/wss_wallet/handlers.zig`
- `runtime/semantos-brain/src/wss_wallet/reactor.zig`
- `runtime/semantos-brain/src/wss_wallet/types.zig`
- `runtime/semantos-brain/src/cli/wallet.zig`

**Payment (HTTP 402 challenge + claim + ledger + verifier):**
- `runtime/semantos-brain/src/payment_ledger.zig`
- `runtime/semantos-brain/src/payment_verifier.zig`
- `runtime/semantos-brain/src/payment_verifier_stub.zig`

**Refund (refund-tx construction + ARC broadcast — WSITE5.5):**
- `runtime/semantos-brain/src/refund_tx.zig`
- `runtime/semantos-brain/src/refund_tx_stub.zig`

**Output store (UTXO internalisation per WA1-WA4):**
- `runtime/semantos-brain/src/output_store_fs.zig`
- `runtime/semantos-brain/src/lmdb/output_store_lmdb.zig`
- `runtime/semantos-brain/src/lmdb/derivation_state_store_lmdb.zig`

**SPV headers (PoW verification + sync + serve):**
- `runtime/semantos-brain/src/header_store_fs.zig`
- `runtime/semantos-brain/src/lmdb/header_store_lmdb.zig`
- `runtime/semantos-brain/src/headers_sync.zig`
- `runtime/semantos-brain/src/headers_http.zig`
- `runtime/semantos-brain/src/resources/headers_handler.zig`
- `runtime/semantos-brain/src/cli/headers.zig`

### What this PRD does NOT cover

- **Brain-core's IdentityAdapter consumption.** Identity primitives (`bearer_tokens.zig`, `identity_certs.zig`, `hat_*.zig`, `device_pair*.zig`, `wrapped_dek_store.zig`) stay in brain-core — they're substrate, not BSV-specific. The cartridge consumes IdentityAdapter through the existing interface; brain-core remains the IdentityAdapter implementor.
- **Brain-core's signing primitives via `bsvz`.** The `bsvz` crypto library binding stays available in brain-core as a substrate-level capability. Brain-core uses it for cert signing (substrate-need); the cartridge uses it for BSV transactions (BSV-need). Same library, two consumers.
- **Operator-site / WSITE phases.** That's `D-Lift-wsite` (a separate carve PRD, not in scope here).
- **Oddjobz code.** That's `D-Lift-oddjobz` (separate companion PRD).
- **Cell-relay or content-store packages.** Already separated into `packages/cell-relay`, `packages/content-store-*`. No carve needed.
- **Anchor-adapter generalisation work.** The interface in `protocol-types` is already shipped. The cartridge implements it; the cartridge does not redefine it.

### Brain-core's behavior after carve

Brain-core retains:
- The `AnchorAdapter` consumption seam — calls go through the interface
- A bundled default: when `bsv-anchor-bundle` is loaded, brain registers the BSV `AnchorAdapter` impl with the dispatcher; when it isn't, brain falls back to `stub-anchor-adapter` from protocol-types
- The same six roles articulated in `docs/SHELL-CARTRIDGES-HATS.md` and elsewhere (peer, webserver, dispatcher, provisioner, leader, message box) — none of which are BSV-specific

DECISION-PENDING-2 **RESOLVED 2026-05-25**: option (c) chosen — start with `stub-anchor-adapter` but mark all cartridges as `anchor-unverified` until a real backend loads. Preserves the loader story without silently degrading the verification chain.

---

## Source Files / References

### Brain-core files to carve OUT

| Alias | Path | Role | Lift gate |
|---|---|---|---|
| `WALLET:OP-HTTP` | `runtime/semantos-brain/src/wallet_op_http.zig` | HTTP surface for wallet ops (sign / derive / etc.) | Replace direct callers with `dispatcher.dispatch("wallet", ...)`; route resolves to cartridge walker |
| `WALLET:WSS` | `runtime/semantos-brain/src/wss_wallet.zig` + `wss_wallet/*` | WebSocket wallet surface (long-running session, mobile pairing) | Cartridge-owned reactor; brain-core wires the WSS transport but doesn't own the wallet protocol |
| `WALLET:CLI` | `runtime/semantos-brain/src/cli/wallet.zig` | `brain wallet ...` subcommands | Move to cartridge CLI registration via verb_dispatcher walker registration pattern |
| `PAY:LEDGER` | `runtime/semantos-brain/src/payment_ledger.zig` | Per-site revenue + refund ledger | Cartridge-owned LMDB store |
| `PAY:VERIFIER` | `runtime/semantos-brain/src/payment_verifier.zig` + `_stub.zig` | Verify cited payment txids via WH PoW-verified header store | Cartridge-owned; consumes SPV header store (also cartridge-owned, see HEADERS section below) |
| `REFUND:TX` | `runtime/semantos-brain/src/refund_tx.zig` + `_stub.zig` | Refund-tx construction + ARC broadcast (WSITE5.5) | Cartridge-owned |
| `OUTPUTS:FS` | `runtime/semantos-brain/src/output_store_fs.zig` | FS-backed per-site OutputStore (WA1-WA4 internalisation) | Cartridge-owned |
| `OUTPUTS:LMDB` | `runtime/semantos-brain/src/lmdb/output_store_lmdb.zig` | LMDB-backed OutputStore | Cartridge-owned; uses the same LMDB substrate brain provides |
| `DERIV:STATE` | `runtime/semantos-brain/src/lmdb/derivation_state_store_lmdb.zig` | BRC-42 derivation-state (next-index per protocol) | Cartridge-owned |
| `HEADERS:FS` | `runtime/semantos-brain/src/header_store_fs.zig` | FS-backed BSV block-header store | Cartridge-owned |
| `HEADERS:LMDB` | `runtime/semantos-brain/src/lmdb/header_store_lmdb.zig` | LMDB-backed BSV block-header store | Cartridge-owned |
| `HEADERS:SYNC` | `runtime/semantos-brain/src/headers_sync.zig` | Zig-native BSV P2P header sync (`brain headers sync`) | Cartridge-owned |
| `HEADERS:HTTP` | `runtime/semantos-brain/src/headers_http.zig` | Long-running BHS-compatible HTTP header server (`brain headers serve`) | Cartridge-owned; cartridge declares HTTP route via dispatcher |
| `HEADERS:HANDLER` | `runtime/semantos-brain/src/resources/headers_handler.zig` | JSON-RPC handler for header queries | Cartridge-owned handler, registered via verb_dispatcher |
| `HEADERS:CLI` | `runtime/semantos-brain/src/cli/headers.zig` | `brain headers ...` subcommands | Move to cartridge CLI registration |

### Brain-core files to KEEP

These stay in brain-core because they're substrate (the AnchorAdapter implementor concerns + identity primitives + LMDB substrate), not BSV cartridge concerns:

| Path | Why it stays |
|---|---|
| `core/protocol-types/src/anchor.ts` | Phase 26C — the AnchorAdapter interface itself |
| `core/protocol-types/src/adapters/bsv-anchor-adapter.ts` | TS-side BSV anchor adapter (substrate-side implementation seam; cartridge wires this on load) |
| `core/protocol-types/src/adapters/stub-anchor-adapter.ts` | Fallback when no backend cartridge loaded — see DECISION-PENDING-2 |
| `runtime/semantos-brain/src/bearer_tokens.zig` | Identity primitive — substrate |
| `runtime/semantos-brain/src/identity_certs.zig` | Identity primitive — substrate |
| `runtime/semantos-brain/src/hat_*.zig` | Hat-rooted authority — substrate |
| `runtime/semantos-brain/src/device_pair*.zig` | Pairing — substrate |
| `runtime/semantos-brain/src/wrapped_dek_store.zig` | DEK store — substrate |
| `runtime/semantos-brain/src/wss_operator_auth.zig` | WSS auth — substrate (cartridge-agnostic) |
| `runtime/semantos-brain/src/lmdb/*` (except output_store/derivation_state/header_store) | LMDB substrate — generic primitive |
| `runtime/semantos-brain/src/broker.zig` | Host-import broker — substrate |
| `runtime/semantos-brain/src/dispatcher.zig` | The unification keystone — substrate |
| `runtime/semantos-brain/src/verb_dispatcher.zig` | Verb-walker registry — substrate |
| `runtime/semantos-brain/src/module_loader.zig` | Cartridge loader — substrate |
| `bsvz` (Zig BSV library) — pinned in `build.zig.zon` | Crypto library — substrate dependency; both brain-core (cert signing) and the cartridge (BSV tx construction) consume it |

### Architectural references

| Alias | Path | What to read |
|---|---|---|
| `GAP-ANALYSIS` | `docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md` | §6 brain-side baked-in cartridge code; §10.3 the new deliverable IDs |
| `CLEAN-CONTRACT` | `docs/SHELL-CARTRIDGES-HATS.md` §4 | The five-part cartridge contract — grammar, walkers, cell types, bindings, optional WASM |
| `ADAPTER-PHASE-26C` | `docs/prd/PHASE-26C-ANCHOR-ADAPTER.md` | The AnchorAdapter interface contract |
| `ADAPTER-OVERLAY` | `docs/ADAPTER-TAXONOMY.md` §7b | Phase 26 four-adapter overlay (matrix-flip guidance) |
| `DISPATCHER` | `docs/design/BRAIN-DISPATCHER-UNIFICATION.md` + `runtime/semantos-brain/src/dispatcher.zig` | Auth-gated capability-checked dispatcher contract |
| `WALLET-DESIGN` | `docs/design/WALLET-TIER-CUSTODY.md` | Wallet-tier policy — informs cartridge's internal capability model |
| `HEADERS-DESIGN` | `docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md` | WH1-WH6 SPV header design — informs cartridge's verification chain |
| `CARTRIDGE-SCAFFOLD` | `tools/cartridge-scaffold/README.md` | `cartridge new` skeleton generator — entry point for cartridge layout |
| `PHASE-26G` | `docs/prd/PHASE-26G-NODE-PACKAGING.md` | Format reference for this PRD; also names the installer that ships brain |
| `EXEMPLAR` | `extensions/oddjobz/` | Existing exemplar operational cartridge (90 src files, 8 canonical cell types) |

### Deliverables

#### DLBA.1 — Cartridge skeleton + WSS subprotocol substrate primitive

The setup deliverable. Establishes the cartridge boundary in code: a place for the lifted files to land, a manifest declaring what the cartridge does, and the new substrate primitive that lets the cartridge own its wallet WSS protocol while brain-core retains the WSS transport (per DECISION-3 resolution). Sub-tree into three sub-deliverables.

##### DLBA.1a — Cartridge directory scaffold + Phase 36A manifest

**Files**:
- New: `extensions/bsv-anchor-bundle/` directory with skeleton structure parallel to `extensions/oddjobz/`:
  - `extensions/bsv-anchor-bundle/manifest.json` — Phase 36A Extension Grammar JSON declaring the cartridge's identity, version, declared verbs (`anchor.write`, `anchor.read`, `wallet.sign`, `wallet.derive`, `payment.verify`, `payment.refund`, `headers.sync`, `headers.serve`), capability requirements, cell types owned (none initially — cartridge consumes substrate cell types), AnchorAdapter implementation declaration via `provides: ["@semantos/protocol-types/anchor"]` extension-grammar field.
  - `extensions/bsv-anchor-bundle/zig/` — empty Zig project tree (build.zig, build.zig.zon, src/, tests/). Source files arrive in DLBA.2/.3/.4.
  - `extensions/bsv-anchor-bundle/src/` — TS surface (delegates to dispatcher for cartridge-implemented verbs; see DLBA.1c).
  - `extensions/bsv-anchor-bundle/README.md` — one-screen primer naming the cartridge, the AnchorAdapter consumption contract, links to the parent PRD + Phase 26C interface.
- Modified: `tools/cartridge-scaffold/` — `cartridge new bsv-anchor-bundle` should produce this skeleton (audit whether the existing scaffold supports a "substrate-exposing" cartridge variant; if not, extend it).

**Acceptance gate**: `bun run check` passes in `extensions/bsv-anchor-bundle/`; `zig build` passes in `extensions/bsv-anchor-bundle/zig/`; loading the cartridge into a running brain via DLO.1's loader emits "loaded 1 extension: bsv-anchor-bundle" with no errors (cartridge ships with zero declared verbs implemented at this point — that's fine, brain doesn't require any of them yet because the lift hasn't started).

**Effort**: 3 days.
**Deps**: DLO.1a (manifest loader). Phase 36A grammar schema (shipped).

##### DLBA.1b — `wss_subprotocol_registry.zig` substrate primitive

**Files**:
- New: `runtime/semantos-brain/src/wss_subprotocol_registry.zig` — ~100 LOC substrate primitive. Cartridges register `(subprotocol_name, handler_ptr, capability_required)` tuples at boot. On WSS handshake, brain-core's existing `wss_codec.zig` + `wss_frame_parser.zig` parse the subprotocol header (per RFC 6455 §1.9 `Sec-WebSocket-Protocol`); the codec consults the registry; matched subprotocol → frames are dispatched to the registered handler with the original AuthContext + CapabilitySet from `dispatcher.zig`. No match → 1002 Protocol Error close frame.
- Modified: `runtime/semantos-brain/src/wss_codec.zig` — hook into the registry at the handshake-completion point. Existing operator-auth path (`wss_operator_auth.zig`) remains the default-when-no-subprotocol-claimed; subprotocol claims route through the registry instead.
- New: `runtime/semantos-brain/src/__tests__/wss_subprotocol_registry_test.zig` — covers: registration round-trip, unknown subprotocol closes with 1002, frame dispatch preserves AuthContext, capability check runs before handler invocation, two cartridges registering distinct subprotocols don't collide, two cartridges registering the same subprotocol fails registration of the second.

**Acceptance gate**: Test cartridge registers a subprotocol; brain-core's WSS endpoint accepts a connection with that subprotocol claimed; frames flow into the cartridge's handler with the right AuthContext; capability-denied frames are blocked at the registry layer (deny-by-default per dispatcher's contract).

**Effort**: 1 week (~5 working days). Mostly the test coverage — the registry itself is small.
**Deps**: dispatcher.zig (shipped), wss_codec.zig + wss_frame_parser.zig (shipped), bearer_tokens.zig for AuthContext (shipped).

##### DLBA.1c — TS-side AnchorAdapter delegation

**Files**:
- Modified: `core/protocol-types/src/adapters/bsv-anchor-adapter.ts` — rewired to delegate to the cartridge via `dispatcher.dispatch("anchor", ...)` instead of calling brain-core wallet code directly. The file's public surface (the methods exposed by `AnchorAdapter` interface) stays identical; the implementation changes from "call brain wallet ops" to "issue dispatcher RPC to cartridge".
- New: `core/protocol-types/src/adapters/__tests__/bsv-anchor-adapter.dispatcher.test.ts` — fixture test using `stub-dispatcher` (or a mock) to verify the delegation paths produce equivalent results to the pre-lift adapter for every existing AnchorAdapter conformance test case.
- Modified: `core/protocol-types/src/adapters/stub-anchor-adapter.ts` — updated per DECISION-2 resolution to return the sentinel `anchor-unverified` proof type that downstream cell validators recognize (cell-header validation extension to be tracked in DLBA.5).

**Acceptance gate**: Existing Phase 26C anchor-adapter conformance tests pass against the rewired TS adapter (no behavioral regression). New tests cover the dispatcher-delegation path. `stub-anchor-adapter` returns `anchor-unverified` proofs that round-trip cleanly through cell-header serialization.

**Effort**: 4 days.
**Deps**: DLBA.1a (cartridge manifest declares the verbs the adapter delegates to). Phase 26C conformance suite (shipped).

DLBA.1 total: ~2.5 weeks (3d + 5d + 4d). Lands DLBA.1a/b/c as separate commits on `lift/bsv-anchor/dlba-1a`, `/dlba-1b`, `/dlba-1c` — squash-merge each into `lift/bsv-anchor` after gate tests pass. DLBA.1a is parallel to DLO.1a (both ship the cartridge boundary primitives in parallel); DLBA.1b is the most independent unit and can land first if DLO.1a isn't yet merged.

#### DLBA.2 through DLBA.5 + TDD Gate

Remaining deliverables to be authored in subsequent /loop iterations. Iteration plan:

1. ✅ Header + Context + Source Files/References (iter 1, commit aa82aef)
2. ✅ What NOT to Do + Completion Criteria templates (iter 3, commit a784252)
3. ✅ Decisions resolved (commit 9758d29)
4. ✅ DLBA.1 cartridge skeleton + WSS subprotocol primitive (this iteration)
5. Next: DLBA.2 (wallet files lift — wallet_op_http + wss_wallet* + cli/wallet, registered against the wss_subprotocol_registry from DLBA.1b)
6. Then: DLBA.3 (payment files lift — payment_ledger + payment_verifier* + refund_tx*)
7. Then: DLBA.4 (headers files lift — header_store_{fs,lmdb} + headers_sync + headers_http + resources/headers_handler + cli/headers; decide whether headers_http stays a cartridge-owned HTTP route per the dispatcher pattern)
8. Then: DLBA.5 (brain-core fallback wiring per DECISION-2; reconciliation pass for anchor-unverified back-fill when the cartridge loads after some cells have already been written with stub proofs)
9. Then: TDD Gate (T1–T15+) with one test per acceptance gate above
10. Refine Completion Criteria checklist with full test references

---

## Resolved decisions (2026-05-16)

All three DECISION-PENDING items resolved with the originally-recommended option per Todd 2026-05-16 ("all recommended").

- **DECISION-1 — Cartridge final location: `extensions/bsv-anchor-bundle/`** ✓ resolved.
  Groups with operational cartridges; treats anchor as a substrate-exposing cartridge (provides AnchorAdapter implementation), not a user-product. Aligns with the "first-party substrate-exposing cartridges in default install" framing from `docs/SHELL-CARTRIDGES-HATS.md` §4.

- **DECISION-2 — Brain-side fallback when bundle not loaded: anchor-unverified-mode** ✓ resolved.
  Brain starts with `stub-anchor-adapter` from protocol-types when no anchor backend cartridge is loaded. All cartridges that emit state hashes are marked `anchor-unverified` in their cell headers until a real backend loads and back-fills. This preserves the loader story without silently degrading the verification chain — a cartridge can run without an anchor backend, but every consumer of its state can tell that the state isn't yet anchored.
  Implementation gate: `core/protocol-types/src/adapters/stub-anchor-adapter.ts` returns a sentinel `anchor-unverified` proof type that downstream cell validators recognize and propagate. The `bsv-anchor-bundle` cartridge, when loaded, registers a real `AnchorAdapter` impl and replaces the stub; back-fill of previously-stubbed anchors happens via a cartridge-side reconciliation pass (scoped in DLBA.5).

- **DECISION-3 — Wallet WSS ownership: brain owns transport, cartridge owns protocol** ✓ resolved.
  `wss_codec.zig` + `wss_frame_parser.zig` + `wss_operator_auth.zig` stay in brain-core as substrate (WSS transport + authentication). The cartridge owns the wallet protocol (`wss_wallet/{handlers,reactor,types}.zig`) and registers itself as a WSS subprotocol handler via a new substrate seam in brain-core. Same pattern as HTTP — brain-core has `http_parser.zig` as transport substrate, cartridge handlers own per-route logic.
  Implementation gate: brain-core grows a `wss_subprotocol_registry.zig` substrate primitive (a tiny addition, ~100 LOC) that cartridges register against at boot. The cartridge's `wss_wallet/reactor.zig` becomes a registered handler under subprotocol `wallet.v1`. WSS frames arrive at brain's transport layer, get dispatched to the registered handler based on subprotocol; the handler is cartridge code.

---

## What NOT to Do

These guardrails apply throughout the carve, regardless of which DLBA deliverable lands first.

- **Don't break the AnchorAdapter interface contract.** Phase 26C shipped the interface in `core/protocol-types/src/anchor.ts`. The cartridge implements that interface; it does not redefine it. If the carve reveals a gap in the interface, that's a separate Phase 26 follow-up PRD — don't fork the interface.
- **Don't bake BSV-specific assumptions into brain-core during the carve.** Every brain-core call site that currently invokes `wallet_op_http.*` or `payment_ledger.*` must route through `dispatcher.dispatch("anchor", ...)` (or whatever resource name the cartridge declares) — never through a direct import of cartridge code. The carve fails if a `grep -r "bsv\|wallet\|payment\|header" runtime/semantos-brain/src/` after the lift matches anything other than substrate identifiers (`bearer_tokens`, etc. — explicitly NOT in scope).
- **Don't break OJT production.** V1 is live on `ssh rbs` per memory `brain_reactor_v1_recovery_complete.md`. The lift must be staged so the running deployment continues functioning at every commit. Acceptable: the cartridge is loaded by default during the lift; later commits switch to the no-op fallback as the default. Not acceptable: a commit where brain-core compiles but production OJT loses wallet/headers/payment functionality.
- **Don't hardcode `bsv-anchor-bundle` as required in brain-core.** It's a default-loaded cartridge per the install bundle, not a substrate dependency. Brain-core must compile and boot with the bundle unloaded (see DECISION-PENDING-2 for fallback shape).
- **Don't conflate IdentityAdapter with the wallet's signing surface.** Brain-core remains the IdentityAdapter implementor (cert chain, hat verification, device pairing). The wallet cartridge consumes IdentityAdapter for BSV-tx-signing — it doesn't reimplement identity primitives.
- **Don't migrate output-store/derivation-state without preserving on-disk data.** Existing per-tenant data lives in brain's data directory under known LMDB databases. The carve must either: (a) leave the data in-place and have the cartridge open the same LMDB env, or (b) ship a one-shot migration tool that moves data into the cartridge's own data directory. Both shapes are acceptable; silent data loss is not.
- **Don't break existing Phase 26C tests.** `core/protocol-types/__tests__/anchor.test.ts` + the AnchorAdapter conformance suite must continue passing on both `bsv-anchor-adapter` and `stub-anchor-adapter`.
- **Don't skip the SPV verification chain.** The trust chain from `headers_sync.zig` (PoW verification) through `payment_verifier.zig` (checking cited payment txids against the PoW-verified header store) is the load-bearing security property of WSITE5+. The cartridge preserves this chain end-to-end; the lift must not introduce a path where `payment_verifier` accepts a txid without consulting the PoW-verified header store.
- **Don't ship without the no-op fallback.** Per DECISION-PENDING-2, brain-core must have *some* answer to "what happens when no anchor backend is loaded." Whichever option Todd picks (refuse-to-start / no-op-with-warning / anchor-unverified-mode), the answer must be wired and tested before the cartridge is the only path to BSV functionality.
- **Don't break the bsvz dependency surface.** `bsvz` is pinned in brain-core's `build.zig.zon`. Both brain-core (for cert signing) and the cartridge (for BSV-tx construction) consume it. The cartridge gets its own `build.zig.zon` pin; brain-core keeps its own. Don't try to centralize the `bsvz` dep into a "shared" location during this carve.
- **Don't pre-empt `D-Lift-wsite`.** WSITE phases reference some of the wallet/payment files (refund-tx broadcast is WSITE5.5). The carve respects that the WSITE code stays in brain-core for now; the cartridge boundary is on the wallet/headers/payment side. After D-Lift-wsite lands, WSITE code becomes a separate cartridge that consumes the bsv-anchor-bundle cartridge for payment/refund operations.

---

## Completion Criteria

Provisional checklist; full TDD-gate list (T-numbered) follows in a future iteration once DLBA.1–DLBA.5 deliverables are scoped.

- [ ] `extensions/bsv-anchor-bundle/` (location per DECISION-PENDING-1) exists with manifest declaring AnchorAdapter implementation
- [ ] All 15 brain-core files listed in §Source Files moved into the cartridge; original paths return file-not-found
- [ ] `grep -r "wallet\|payment\|refund\|header_store\|headers_sync\|headers_http" runtime/semantos-brain/src/` returns only substrate-shaped matches (no business-logic references)
- [ ] Brain-core compiles and boots with `bsv-anchor-bundle` **unloaded** (no-op fallback per DECISION-PENDING-2)
- [ ] Brain-core compiles and boots with `bsv-anchor-bundle` **loaded** (full BSV wallet/anchor/headers functionality preserved)
- [ ] All previously-passing brain-core tests for wallet/payment/refund/headers continue passing — relocated to cartridge's test directory
- [ ] AnchorAdapter conformance tests pass on the cartridge's implementation (parity with `bsv-anchor-adapter.ts`)
- [ ] SPV verification chain end-to-end test (headers_sync → payment_verifier → output_store internalization) passes from inside the cartridge
- [ ] `cli/wallet.zig` + `cli/headers.zig` CLI subcommands work as cartridge-registered REPL contributions
- [ ] OJT production deployment (`ssh rbs`) continues serving traffic through the lift
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] All commits follow `lift/bsv-anchor/DLBA.N:` naming convention
- [ ] Branch is `lift/bsv-anchor`
- [ ] No prior phase tests regressed (Phase 26A–H, 36A/C/D, dispatcher Phase 0 still pass)

---

## Next Phase

After D-Lift-bsv-anchor lands:

1. **D-Lift-wsite** — operator-site / WSITE1–5.5 carve. Becomes a cartridge that consumes `bsv-anchor-bundle` for payment + refund operations. Phase 26G installer ships both bundles loaded by default for the "sovereign-BSV-node" distro variant.
2. **D-Distro-default-install** — define the default brain install bundle. The decision tree includes: ship `bsv-anchor-bundle` by default (sovereign-BSV-node distro), or ship without it (substrate-only distro). Per the OSS-substrate-carve memory `oss_substrate_carve_parked.md`, the OSS pitch favors making this a distro variant rather than a default.
3. **D-Manifest-canonical** — unify the three candidate cartridge manifest formats. `bsv-anchor-bundle` becomes a substrate-exposing cartridge that the canonical-manifest work consumes as a reference case.
