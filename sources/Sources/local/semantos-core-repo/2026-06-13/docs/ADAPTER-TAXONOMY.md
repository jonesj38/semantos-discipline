---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/ADAPTER-TAXONOMY.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.328423+00:00
---

# Adapter Taxonomy — What's Shipped vs What's Designed

**Status:** Living document. Last updated 2026-05-13 (Tier-A burst iter 3). Update per-row as code lands.

The substrate paper and public framing tend to flatten the system into "cells + verticals". In practice there are five distinct adapter classes, each with its own integration discipline and its own status reality. This doc is the honest reckoning of what's actually shipped vs what's design-only.

---

## 1. The classes

Working outward from the kernel:

1. **Substrate runtimes** — Phase-26D/35A/35B transports, verifier sidecar, peer locator, intent runtime. They implement the unification axes themselves; they are ✓ by construction (or are bugs against their own spec).
2. **Substrate-adjacent extensions** — chain-broadcast, dispatch, metering. They are *substrate-shaped*: anchored to BSV, transport-agnostic, capability-gated. Other adapters depend on them.
3. **Vertical extensions** — oddjobz, calendar, cdm, scada, re-desk-stub, etc. Each owns a domain-specific lexicon + cell-type schema set.
4. **UI/client adapters** — loom-react, loom-svelte, oddjobz-mobile, helm viewers. They consume the substrate via BRC-100 envelopes.
5. **Tooling/research adapters** — pask-vault-notion, pask-vault-obsidian, navigator, extraction. They drive Pask or feed external systems.

Each class has different expectations for compliance with the unification matrix (`docs/prd/UNIFICATION-ROADMAP.md` §2). Substrate runtimes must be ✓ across every axis they participate in; vertical extensions are allowed to be ⚠ during construction; tooling can be intentionally incomplete.

---

## 2. Status legend

- **✓ shipped** — implemented, has conformance tests, used in production or by other adapters
- **⚠ partial** — code exists, some axes wired, others pending
- **✗ stub** — interface/types only; no real behaviour
- **DESIGN** — no code yet; spec or README only
- **NOT STARTED** — neither code nor spec
- **DOC GAP** — code exists but no README; status inferred from source structure

---

## 3. Substrate runtimes (`runtime/*`)

| Path | Status | Role | Key references |
|---|---|---|---|
| `runtime/semantos-brain/` | ✓ shipped | Node binary (`brain`). HTTP/WSS surface, NATS event spine, LMDB stores under K4 discipline. V1 reactor recovery complete per memory `brain_reactor_v1_recovery_complete.md`. | Tracker `docs/REACTOR-PORT-TRACKER.md` |
| `runtime/verifier-sidecar/` | ⚠ partial | D-V1/D-V2 — BRC-100 verification, BRC-52 cert authenticity, identity binding, capability UTXO SPV. D-V2 deployment topology codified (per-node default per §8 Q3, 2026-04-26). | `runtime/verifier-sidecar/README.md` |
| `runtime/session-protocol/` | ⚠ partial | Phase-35A — `MulticastAdapter` over IPv6 UDP multicast (default group `ff02::1`); `NetworkAdapter` interface (Phase-26D). | `runtime/session-protocol/README.md` |
| `runtime/ws-node-adapter/` | ✓ shipped (REVISES §11.6) | **Phase-35B** — `WsNodeAdapter`: WSS-based federation transport between sovereign nodes with license-handshake envelope auth. **Note:** §11.6 of UNIFICATION-ROADMAP listed this as "not shipped" — that was incorrect. The adapter ships. The "not shipped" claim should be tightened to "production deployment topology pending." | `runtime/ws-node-adapter/README.md` |
| `runtime/peer-locator/` | ⚠ partial | D-C6d — BCA → WSS endpoint resolution. Two impls today (`StaticPeerLocator` map-backed + one more); operator-run federated registry lands in Phase-35B.3. | `runtime/peer-locator/README.md` |
| `runtime/intent/` | DOC GAP | Intent pipeline runtime stages (per §11.2's D-IP-* deliverables). Source exists; no README. Status of NL→SIR wiring inferred to be partial — per §11.6 "only `host.exec` fully wired" framing. | Source at `runtime/intent/src/` |
| `runtime/hrr-library/` | DOC GAP | Runtime wrapper around `core/hrr/` for in-process HRR encoding. Source exists; no README. | Source at `runtime/hrr-library/src/` |
| `runtime/world-beam/` | DESIGN | World Host substrate. Single hardcoded region with three `LinearCube` entities. Multi-region per D-W1/D-W2/D-W3 (§11.2) not yet implemented. | `runtime/world-beam/apps/world_host/README.md` |
| `runtime/shell/` | ⚠ partial | VFS path resolver (`runtime/shell/src/vfs/`). Per §11.6 binding to BRC-26 Universal Hash Resolution Protocol pending. | — |
| `runtime/services/` | ⚠ partial | Operator service host. Plexus-network-SDK consumer; payment-channel ports defined per refactor Prompt 14. | — |
| `runtime/node/` | DOC GAP | Node-runtime utilities. Source exists; no README. | Source at `runtime/node/src/` |
| `runtime/legacy-ingest/` | LEGACY | Pre-NATS ingest path. Likely partially superseded by today's NATS A+B work (`7247694`). | — |

### Substrate runtime corrections to UNIFICATION-ROADMAP §11.6

§11.6 of `docs/prd/UNIFICATION-ROADMAP.md` characterised the Phase-35B WSS NodeAdapter as "not shipped" and used it as the rationale for D-C6b being a new deliverable. Reality:

- The adapter code ships at `runtime/ws-node-adapter/`
- The peer-locator ships at `runtime/peer-locator/` with two implementations today
- D-V1 verifier-sidecar ships at `runtime/verifier-sidecar/`

D-C6b should be re-scoped from "implement WsNodeAdapter" to "production-deploy WsNodeAdapter with cross-internet federation topology", which is the actual remaining gap. The contract-test work (D-C6c) and BRC-22/24/87/88 binding (§11.6) remain genuinely undone.

---

## 4. Substrate-adjacent extensions (`extensions/*` — substrate-shaped)

| Path | Status | Role | Key references |
|---|---|---|---|
| `extensions/dispatch/` | ✓ shipped | Cross-vertical federation envelope (chapter 29). Three cell types: `dispatch.envelope.v1` (LINEAR), `dispatch.accepted.v1` (LINEAR), `dispatch.completion.v1` (LINEAR). Transport-agnostic. | `extensions/dispatch/README.md` |
| `extensions/chain-broadcast/` | ✓ shipped | Phase-35A BSV anchoring. Decomposed from 1672-line monolith into 4 services + facade: `CellTxBuilder`, `MapiBroadcaster`, `ChainTipManager`, `BeefStore`. | `extensions/chain-broadcast/README.md` |
| `extensions/metering/` | ✓ shipped (DOC GAP) | MFP (metered payment channels). Phase-29.5 kernel-enforced policies per `channel-fsm.ts` + `PolicyEnforcedChannel` + `SettlementContext`. No README — status inferred from code structure and prior memory work. | Source at `extensions/metering/src/` |
| `extensions/policy-runtime/` | ⚠ partial (DOC GAP) | Extension grammar validator + policy engine per refactor Prompt 43. No README. | Source at `extensions/policy-runtime/src/` |
| `extensions/recovery/` | ⚠ partial (DOC GAP) | Plexus Recovery client wiring. No README. | Source at `extensions/recovery/src/` |
| `extensions/extraction/` | ⚠ partial | Semantic extraction pipeline: fetch, parse, typecheck, infer, commit. Description in `package.json`. | Source + package.json |

---

## 5. Vertical extensions (domain lexicons + cell-type schemas)

| Path | Status | Role | Key references |
|---|---|---|---|
| `extensions/oddjobz/` | ✓ shipped | Eight canonical cell types: `oddjobz.{job, quote, visit, invoice}.v1` (LINEAR with FSMs); `oddjobz.{customer, site}.v1` (PERSISTENT); two more for billing/auth. Per `docs/design/ODDJOBZ-EXTENSION-PLAN.md`. | `extensions/oddjobz/README.md` |
| `extensions/calendar/` | ✓ shipped (v0.3.0) | Calendar as semantic object. **One** schedule aggregate per physical person; append-only patch stream. Bots are producers; UI consumes. Hat attribution per-patch via `facetId`. | `extensions/calendar/README.md` |
| `extensions/cdm/` | ⚠ partial | ISDA CDM lifecycle engine, regulatory reporting, FpML bridge. Per chapter 24 (CDM lexicon). | Source + package.json |
| `extensions/scada/` | ⚠ partial (DOC GAP) | SCADA / control-systems vertical (chapter 26 lexicon). No README. | Source at `extensions/scada/src/` |
| `extensions/re-desk-stub/` | ✓ shipped (intentionally minimal) | Stub property-management vertical. Single `MaintenanceRequest` cell, single capability, single FSM. Exists specifically to validate chapter-29 federation primitive end-to-end with oddjobz on the receiving side. | `extensions/re-desk-stub/README.md` |
| `extensions/md-editor/` | ✗ stub | D-A4 cert-bound interface only. **No editor exists.** In-progress React component at `apps/loom-react/src/helm/MarkdownEditor.tsx` is ~100 LOC CodeMirror wrapper. Tree-of-chains (§8 Q4, D-E-md) not implemented. | `extensions/md-editor/README.md` |
| `extensions/sites/` | DOC GAP | Site/place vertical. No README. | Source at `extensions/sites/src/` |
| `extensions/navigator/` | ⚠ partial | "Core navigation layer for Semantos. Renders any extension's types through tower model, elevation tracking, and consumer binding." Per package.json. | Source + package.json |
| `extensions/navigation/` | DEPRECATED | "DEPRECATED. Use @semantos/navigator and @semantos/consciousness." Per package.json. | package.json deprecation note |
| `extensions/game-sdk/` | ⚠ partial | "Game engine SDK: entities, inventories, trades, state machines, and policies over the cell engine." | package.json |
| `extensions/games/` | ⚠ partial | Concrete games on top of game-sdk. | — |

---

## 6. Tooling / research adapters

| Path | Status | Role |
|---|---|---|
| `extensions/pask-ga/` | ✓ shipped | Genetic-algorithm operators over Pask `genomeKey()`. Collaborator-active research line. Per memory `semantos_hrr_design_decisions.md`: HRR coexists, does not replace. |
| `extensions/pask-vault-notion/` | ⚠ partial | "Notion workspace adapter for the Pask constraint graph — DB4 of the Dimensional Second Brain workstream." |
| `extensions/pask-vault-obsidian/` | ⚠ partial | "Obsidian vault adapter for the Pask constraint graph — DB3 of the Dimensional Second Brain workstream." |

---

## 7. UI / client adapters (`apps/*`)

| Path | Status | Role |
|---|---|---|
| `apps/loom-react/` | ⚠ partial | "Semantos React workbench. Consumes `@semantos/runtime-services`. Renamed from `@semantos/loom` in Phase 3." Helm convergence surface. Many unification-axis cells; not all ✓. |
| `apps/loom-svelte/` | ⚠ partial | Svelte port of Helm. Desktop helm SPA consuming bearer-gated `POST /api/v1/repl` (per `apps/oddjobz-mobile/README.md`). |
| `apps/oddjobz-mobile/` | ⚠ partial | Flutter mobile shell. D-O5m Phase-1 MVP. Pairs into operator's brain via D-O5p QR flow. Awaiting sideload smoke per `docs/REACTOR-PORT-TRACKER.md`. |
| `apps/oddjobtodd/` | ⚠ partial | The "Odd Job Todd" V1 pilot app. |
| `apps/settlement/` | ⚠ partial | "BSV settlement layer: border-router aggregation, CBOR encoding, Merkle batching, and WebSocket relay." Per refactor Prompt 44. Plexus-native; mostly ✓ in §2 matrix (A6 row). |
| `apps/world-apps/` | see §7a | World-app cartridges (BEAM-backed, world-region-scoped). No README at the top level — characterized in §7a below. Documentation gap closed by `docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md` §5.2. |
| `apps/world-client/` | ⚠ partial | three.js World Client (A2 in §2 matrix). |
| `apps/navigation_app/` | ⚠ partial | Post-refactor home for chat-shell, ConversationPanel, world-client (per refactor Prompts 11/31/32/35-37). |
| `apps/semantos/` | ⚠ partial | Operator shell. |
| `apps/wallet-browser/` | ⚠ partial | BRC-100 wallet browser surface. |
| `apps/site/` | ⚠ partial | Public-facing site (the one with `/api/v1/info`, attachments, etc.). |
| `apps/brain-helm-viewer/` | ✗ stub | — |
| `apps/demo-collab-versioning/` | demo | — |
| `apps/demo-wasm-threejs/` | demo | — |
| `apps/legacy-cli/` | LEGACY | Pre-brain CLI. |
| `apps/poker-agent/` | ⚠ partial | Poker agent — chain-broadcast's first production consumer. |
| `apps/piggybank/` | demo | — |
| `apps/mud/` | demo | — |

---

## 7a. World-app cartridges (`apps/world-apps/*`)

`apps/world-apps/` is a second cartridge home distinct from `extensions/*` — the world-app kind per memory `semantos_two_cartridge_kinds.md`. Where `extensions/*` cartridges are operational/FSM (oddjobz, calendar, dispatch, scada, metering — register walkers, own typed cells, run on the operator-edge or as background loops), world-app cartridges are **user-facing UI surfaces running inside a Semantos world region**. They share the cartridge contract (Phase 36A grammar, walker registration via `verb_dispatcher.zig`, typed cells with linearity, release.config.ts) but ship a different bundle shape (Svelte / three.js / Flutter / WebAudio).

| Path | Status | Role |
|---|---|---|
| `apps/world-apps/jam-room/` | ⚠ partial (v0.2.0, 93 src files) | Collaborative music sequencer. 13 declared `jam.*` SemanticObjectKind in `src/semantic/objects.ts` (`jam.world`, `jam.instrument`, `jam.skin`, `jam.patch`, `jam.snapshot`, `jam.crate`, `jam.track`, `jam.sample-pack`, `jam.sample`, `jam.clock-calibration`, `jam.drum-track`, `jam.pattern`, `jam.arrangement`). `BEAMClock` NTP sync over CellRelay WebSocket. BSV PushDrop anchoring of session snapshots via `src/core/anchor.ts`. Brain hooks: `runtime/semantos-brain/src/{jam_clip_state_store,jambox_walkers}.zig`. Release room: `release.app.jam-room`. PRD: `docs/prd/jam-room/MASTER.md` Phases A-G — **0 of 7 phases shipped** (13-17 weeks scoped). |
| `apps/world-apps/jam-room-mobile/` | ⚠ partial | Flutter mobile companion to jam-room. Shares cell-type schema; separate UI bundle. Companion package: `packages/jam_experience/` (Dart). |

### World-app cartridge characterization

A world-app cartridge differs from an operational cartridge in three ways:

1. **UI is first-class.** The cartridge bundle is a deployable web/mobile app, not a TS/Zig library that the operator invokes via REPL. Jam-room ships an `index.html`, `serve.ts`, `bridge.ts`, and a build artifact (`public/main.js`).
2. **World-region-scoped.** The package declares `semantos: { worldApp: true, protocol: 'world-beam', relay: 'cell-relay' }` and runs inside a world region (single-region today per ADAPTER-TAXONOMY §3 `runtime/world-beam/`; multi-region per D-W1).
3. **Independent anchoring.** Jam-room signs session snapshots via BSV PushDrop directly. It consumes the AnchorAdapter interface (Phase 26C) but doesn't depend on the operator's wallet cartridge — same interface, different consumer.

### Audit completeness note

Per memory `semantos_two_cartridge_kinds.md`: any audit that sweeps `extensions/*` without also sweeping `apps/world-apps/*` undercounts. This taxonomy until 2026-05-15 swept only `extensions/*` and flagged `apps/world-apps/` as a doc gap; this section closes the gap.

---

## 7b. The Phase 26 four-adapter overlay on adapter status

A cartridge's "✓ shipped on axis X" claim depends on which adapter interfaces it consumes from substrate. The four Phase 26 adapter interfaces (`core/protocol-types/src/{storage,identity,anchor,network}.ts` — see `docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md` §2 for shipping status) define the consumption seam:

| Axis | Phase 26 interface | Shipping impls in protocol-types |
|---|---|---|
| Identity (A) | `IdentityAdapter` | `LocalIdentityAdapter`, `stub-identity-adapter`, `create-identity-adapter` |
| Storage (B + parts of E) | `StorageAdapter` | `node-fs-adapter`, `memory-adapter`, `opfs-adapter`, `indexed-db-adapter`, `overlay-adapter` |
| Anchor (E + parts of B) | `AnchorAdapter` | `bsv-anchor-adapter`, `stub-anchor-adapter` |
| Network (C + parts of F) | `NetworkAdapter` | `bsv-overlay-network-adapter`, `stub-network-adapter` |

A cartridge that imports one of these interfaces and uses a shipped implementation inherits that axis's substrate-side compliance. A cartridge that hand-rolls its own storage/identity/anchor/network is forking the substrate seam and likely off-axis. Note for matrix-flip reviews: an adapter row that's ⚠ on axis A but whose code shows `import { IdentityAdapter } from '@semantos/protocol-types/identity'` with a shipped impl plugged in may just need the matrix flipped to ✓ — the work was done elsewhere.

---

## 8. What the substrate paper claims vs reality

The §11 truth-alignment supplement in `docs/prd/UNIFICATION-ROADMAP.md` named eight gaps. Updating each against this taxonomy:

| Gap | Status as of 2026-05-13 |
|---|---|
| G1 capability tokens → UTXOs | Still real. `OP_CHECKCAPABILITY` checks a `u32` index against bearer-token store. D-Dcap-engine binding to BRC-108 + BRC-115 (§11.6) remains the work. |
| G2 universal intent pipeline | Still real. `runtime/intent/` exists but no README; per §11.6 only `host.exec` fully wired. NL→SIR (D-Dlex-voice) is new work. |
| G3 mathematically proven | Still real. 55 Lean files, abstract proofs; no property-test derivation, no runtime extraction. D-Dform-property + D-Dform-coverage remain undone. |
| G4 world host 20 Hz tick | Still real. `runtime/world-beam/` is DESIGN — single hardcoded region. D-W1/W2/W3 are A1-internal milestones unstarted. |
| G5 federation transport | **Partially corrected.** Phase-35B WSS `WsNodeAdapter` *ships* (`runtime/ws-node-adapter/`); peer-locator ships (`runtime/peer-locator/`). What's still real: NetworkAdapter contract test suite (D-C6c), BRC-22/24/87/88 binding, and production cross-internet deployment topology. |
| G6 md editor + tree-of-chains | Still real. Stub interface only; tree-of-chains undone. |
| G7 1024-byte alignment story | **Closed** by D-Doc-1024 (chapter 34, commit `bd9da5d`). |
| G8 missing kernels in public story | **Closed** by D-Doc-three-kernels (chapter 35, commit `36631ec`). |

So eight gaps reduce to six real-remaining gaps, with G5's scope shrinking to "deploy + contract suite + BRC-binding" rather than "implement the adapter."

---

## 9. Documentation gaps to close

These directories ship code but lack a top-level README, making status assessment inference-based rather than authoritative:

- `extensions/metering/` (MFP — substrate-adjacent; high priority)
- `extensions/policy-runtime/` (Prompt 43)
- `extensions/recovery/` (Plexus recovery wiring)
- `extensions/scada/` (chapter 26 vertical)
- `extensions/sites/`
- `runtime/world-beam/` (the world-host substrate)
- `runtime/intent/` (the intent pipeline runtime)
- `runtime/hrr-library/`
- `runtime/node/`
- ~~`apps/world-apps/`~~ — **closed 2026-05-15** by §7a above + `docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md` §5.2.

Closing each is roughly a 50-line README dropping the package's status, axis-compliance, and key code paths. A separate sprint should write these — they're not part of the D-Doc-* burst because they're per-component, not per-narrative.

---

## 10. Migration path per ⚠ to ✓

For each ⚠ row in the unification matrix (`docs/prd/UNIFICATION-ROADMAP.md` §2b), the matching deliverable ID in §5 (or §11.2 for new bindings) specifies the work. The general shape:

1. **A axis (Identity)**: integrate BRC-52 cert at the adapter's edge (D-A1..D-A7).
2. **C axis (Transport)**: wrap outbound frames in `SignedBundle<T>` (D-C1..D-C8).
3. **D-sub (substructural)**: classify the adapter's cells by linearity class; route through K1 (D-Dsub-*).
4. **D-lex (lexicon)**: register the adapter's lexicon with the canonical authority; validate payloads (D-Dlex-*).
5. **D-cap (capability)**: bind to BRC-108 + BRC-115 capability UTXO checks (D-Dcap-*); blocked on D-Dcap-engine landing first.
6. **E (time)**: ensure every UI-visible cell has a verifiable hash chain (D-E-*).
7. **F (recovery)**: export adapter state to Plexus recovery payload (D-F1..D-F-lean).
8. **G (metering)**: open MFP channels for paid resources (D-G1..D-G3).

Doing all eight on every ⚠ adapter is the long-tail of unification. The substrate paper's claim — "every surface implements every axis" — holds when this table is all ✓.

---

## 11. Honest framing for public communication

The substrate paper's adapter ecosystem framing should land as:

> Semantos ships ~30 adapters across substrate runtime, substrate-adjacent extensions, vertical extensions, UI clients, and research tooling. Three are fully unification-compliant (chain-broadcast, dispatch, oddjobz). About a dozen are partial — code shipped, some axes wired, others pending. Several are stubs or design-only — most notably the md-editor surface and the multi-region world host. The unification matrix (`docs/prd/UNIFICATION-ROADMAP.md` §2) is the authoritative status grid; this taxonomy is the per-adapter narrative.

Not: *"a polished platform with shipped vertical applications"*. Not: *"a stub of a system with a few demo apps"*. The honest middle: a substrate that ships, with a working set of substrate-adjacent extensions, a single fully-mature vertical (oddjobz), and a long tail of partials and stubs.

---

## 12. Sources referenced

Per-adapter READMEs and `package.json` descriptions, where available:

- `extensions/dispatch/README.md`
- `extensions/chain-broadcast/README.md`
- `extensions/oddjobz/README.md`
- `extensions/calendar/README.md`
- `extensions/md-editor/README.md`
- `extensions/re-desk-stub/README.md`
- `runtime/verifier-sidecar/README.md`
- `runtime/ws-node-adapter/README.md`
- `runtime/peer-locator/README.md`
- `docs/prd/UNIFICATION-ROADMAP.md` §2, §11
- `docs/REACTOR-PORT-TRACKER.md`
- Memory `brain_reactor_v1_recovery_complete.md`
- Memory `semantos_hrr_design_decisions.md`
- Memory `semantos_pask_layering.md`

Update this doc when an adapter's status changes. Don't let the substrate paper claim ✓ for an adapter that this taxonomy lists as ⚠ or ✗.
