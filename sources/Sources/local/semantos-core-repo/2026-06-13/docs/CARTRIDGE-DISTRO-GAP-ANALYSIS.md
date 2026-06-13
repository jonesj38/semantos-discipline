---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.334664+00:00
---

# Cartridge Distro Pattern — Gap Analysis

**Date**: 2026-05-15
**Status**: synthesis doc — not autonomous-loop output
**Companion docs**: `docs/SHELL-CARTRIDGES-HATS.md`, `docs/ADAPTER-TAXONOMY.md`, `docs/canon/unification-matrix.yml`, `docs/prd/PHASE-26-KERNEL-ISOLATION-MASTER.md`, `docs/prd/PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md`, `docs/design/BRAIN-DISPATCHER-UNIFICATION.md`, `docs/design/V1.0-EXECUTION-PLAN.md`

---

## 0. Why this doc exists

The substrate has been telling itself a story across multiple unification streams (Phase 26 kernel isolation, Phase 36 extension ecosystem, BRAIN-DISPATCHER-UNIFICATION, V1.0 single-node execution, the D-O8/9/10 tenant-provisioning chain). Each stream owns its own status. None of them collectively answers:

> How close are we to **brain as a Linux-distro-shaped experience loader** — one binary, four substrate primitives, a default install bundle, formalized cartridges, and an OSS-shippable shape?

This doc is the cross-stream synthesis. It tracks the convergence picture, names where each unification stream actually stands as of 2026-05-15, accounts for **both kinds of cartridge** (operational `extensions/*` and world-app `apps/world-apps/*` — the latter previously a doc gap), and proposes the matrix delta needed to surface this in `docs/canon/unification-matrix.yml` without mutating the live status grid here.

---

## 1. The convergence picture

The "brain as experience loader" framing collapses onto already-designed infrastructure:

```
┌────────────────────────────────────────────────────────────────┐
│  BRAIN BINARY (one Zig host shell)                             │
│                                                                 │
│  • dispatcher.zig — single auth-gated, capability-checked,     │
│    audit-logged seam (BRAIN-DISPATCHER-UNIFICATION §2)         │
│  • verb_dispatcher.zig — generic extension-verb walker registry│
│  • module_loader.zig — hash-pinned WASM + lifecycle FSM        │
│  • tenant_manifest.zig + provision_tenant.zig — multi-tenant   │
│    on a single host (D-O8 + D-O10)                             │
└────────────────────────────────────────────────────────────────┘
                  │ consumes four substrate primitives
                  ▼
┌────────────────────────────────────────────────────────────────┐
│  FOUR ADAPTER INTERFACES (Phase 26 — IN protocol-types)        │
│                                                                 │
│  StorageAdapter   core/protocol-types/src/storage.ts           │
│  IdentityAdapter  core/protocol-types/src/identity.ts          │
│  AnchorAdapter    core/protocol-types/src/anchor.ts            │
│  NetworkAdapter   core/protocol-types/src/network.ts           │
│                                                                 │
│  Implementations shipped: node-fs, memory, opfs, indexed-db,   │
│  overlay (Storage); LocalIdentityAdapter, stub, create         │
│  (Identity); bsv-anchor-adapter, stub-anchor-adapter (Anchor); │
│  bsv-overlay-network-adapter, stub-network (Network).          │
└────────────────────────────────────────────────────────────────┘
                  │ loads
                  ▼
┌────────────────────────────────────────────────────────────────┐
│  CARTRIDGES — TWO KINDS                                         │
│                                                                 │
│  Operational/FSM cartridges (`extensions/*`):                  │
│    - declared via Phase 36A Extension Grammar JSON Schema      │
│    - register walkers with verb_dispatcher.zig                  │
│    - own cell types with declared linearity                     │
│    - operator-edge or background loops                          │
│                                                                 │
│  World-app cartridges (`apps/world-apps/*`):                   │
│    - user-facing UI (Svelte / Flutter / three.js)               │
│    - run inside a world region (BEAM-backed)                    │
│    - own semantic-object kinds (`jam.world`, `jam.instrument`, │
│      etc.); anchor session snapshots via BSV PushDrop          │
│    - example: `apps/world-apps/jam-room/` (see §5.2)            │
└────────────────────────────────────────────────────────────────┘
```

User runtime framing of "four core adapters" (p2p connectivity, VST, wallet, headers) maps to **concrete BSV implementations of the Phase 26 abstract interfaces**, not a separate four:

| User framing | Phase 26 interface | Shipped BSV impl |
|---|---|---|
| p2p connectivity | NetworkAdapter | `bsv-overlay-network-adapter.ts` + `runtime/ws-node-adapter/` + `runtime/peer-locator/` |
| VST (filesystem + CAS) | StorageAdapter | `overlay-adapter.ts`, `node-fs-adapter.ts`; CAS via Phase 30F.2 |
| wallet | AnchorAdapter + IdentityAdapter | `bsv-anchor-adapter.ts`, `LocalIdentityAdapter` |
| headers | Part of AnchorAdapter SPV chain | `runtime/semantos-brain/src/headers_sync.zig` |

This is the same architecture from two viewing angles. The user's runtime framing is the BSV-instantiation tier; Phase 26 is the abstract-interface tier.

---

## 2. Phase 26 (Kernel Isolation — the four adapter interfaces)

Reference: `docs/prd/PHASE-26-KERNEL-ISOLATION-MASTER.md` + sub-phase PRDs.

| Sub-phase | Title | Status | Evidence |
|---|---|---|---|
| 26A | Identity Extraction | ✓ shipped | `core/protocol-types/src/identity.ts` + multiple implementations |
| 26B | Local Identity | ✓ shipped | `LocalIdentityAdapter.ts` + `identity-adapters/local/` |
| 26C | Anchor Adapter | ✓ shipped | `anchor.ts` + `bsv-anchor-adapter.ts` + `stub-anchor-adapter.ts` |
| 26D | Network Adapter | ✓ shipped + errata | `network.ts` + `bsv-overlay-network-adapter.ts`; `PHASE-26D-ERRATA.md` 2026-04-01 |
| 26E | Node Bootstrap | ✓ shipped | PR #31 merged (`58ca67d`); `core/protocol-types/src/node.ts` exists; gate tests T1–T15. Uses gate-tests instead of errata docs. |
| 26F | Vertical Loading | ✓ shipped | PR #32 merged (`f97d2fd`); VerticalManifest, VerticalLoader, VerticalRegistry, prompt scripts. Subsequently renamed to Extension* by 26H. Gate tests T1–T20. |
| 26G | Node Packaging | ✓ shipped | PR #33 merged (`093e7b9`). `Dockerfile`, `docker-compose.yml`, `scripts/install.sh`, `semantos` CLI with lifecycle/vertical/identity/anchor subcommands, deployment guides at `docs/deployment/{VPS,DOCKER}-DEPLOYMENT.md`. Gate tests T1–T10. |
| 26H | Extension Rename | ✓ shipped | PR #34 merged (`1886ced`); D26H.1–D26H.8 covering protocol-types, workbench, shell, configs, tests, docs. Some post-merge stragglers (`6fcc73b`, `a9e7cc5`). |

**Status summary**: Phase 26 is **entirely shipped**. Four adapter interfaces real in `protocol-types`. Node bootstrap, vertical loading (renamed extension loading), node packaging, and the vertical→extension rename all merged.

**Corrections to my prior readings**:
1. *"Anchor interface as substrate primitive — 1 week to extract"* — wrong; the AnchorAdapter has been in `protocol-types` for over a month with two implementations.
2. *"Phase 26G Node Packaging — PRD ready, NOT shipped"* — wrong; PR #33 merged. The reason I missed it: Phase 26 sub-phases use gate-tests (T1–T20) instead of `*-ERRATA.md` files, and I was scanning the errata index instead of `git log`.

**What this means for the distro pattern**: Phase 26G shipping is the **biggest update** to the gap analysis. The brain binary distribution mechanism exists. The remaining gap is that the brain it packages still has cartridge-shaped code (oddjobz, wallet, headers, operator-site, jam-room hooks) baked into `runtime/semantos-brain/src/` — see §6. The Phase 26G installer is ready; what it installs is still a not-yet-fully-carved brain.

---

## 3. Phase 36 (Extension Ecosystem — the cartridge contract)

Reference: `docs/prd/PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md` + sub-phase PRDs + erratas.

| Sub-phase | Title | Status | Evidence |
|---|---|---|---|
| 36A | Extension Grammar JSON Schema | ✓ Complete | `PHASE-36A-ERRATA.md` 2026-04-12 — 17 interfaces + 7 type aliases, full validator, adversarial review passed, safe-compute regex |
| 36B | Semantic Extraction Pipeline | ✗ NOT shipped | PRD ready, 3-week effort, prerequisites Phase 36A + 30F.2 (CAS) + Phase 18 (metering) |
| 36C | Schema Inference Agent | ✓ Implementation complete | `PHASE-36C-ERRATA.md` |
| 36D | Extension Governance Model | ✓ Complete | `PHASE-36D-ERRATA.md` |
| 36E | Extension Manager UI | ? unverified | PRD exists, no errata |
| 36F | Connector Reference Impl | ? unverified | PRD exists, no errata |

**Status summary**: Three of six Phase 36 sub-phases shipped (A grammar / C inference / D governance). The **cartridge contract is formalized and validated** — Phase 36A errata confirms the meta-schema with 17 interfaces and adversarial-review safety.

**Correction to my prior reading**: I previously said "cartridge contract isn't formalized — 2-3 weeks design + 1 week impl." Wrong. The contract has been live for five-plus weeks.

The remaining Phase 36 work (B/E/F) is **pipeline + marketplace polish**, not foundational contract design.

---

## 4. Brain-Dispatcher Unification

Reference: `docs/design/BRAIN-DISPATCHER-UNIFICATION.md` + `runtime/semantos-brain/src/dispatcher.zig` (751 LOC).

Per dispatcher.zig's header: *"This file is the architectural seam brain has been missing: a single auth-gated, capability-checked, audit-logged entry point through which every transport calls every resource handler."*

| Layer | File | Status | Notes |
|---|---|---|---|
| Phase 0 — Core dispatcher | `dispatcher.zig` | ✓ shipped | DispatchContext, AuthContext, CapabilitySet, ResourceHandler, Result types. In-process REPL transport. Deny-by-default capability check. |
| Verb-walker registry | `verb_dispatcher.zig` (225 LOC) | ✓ shipped | Generic `(extensionId, verb) → walker` registration. Single JSON-RPC method `verb.dispatch` routes everything. The cartridge boundary in code. |
| Payload-type router | `payload_type_router.zig` (121 LOC) | ✓ shipped (Phase 2) | SignedBundle `payload_type` → routing decision. Mesh-transport plug-in point. |
| Phase 1+ migrations | — | ✗ outstanding | Bearer-token resource migration, `cert: IdentityCert` AuthContext, `llm.complete` resource handler, Unix-socket + HTTP transport adapters all named but not shipped. |
| Host-import broker | `broker.zig` (299 LOC) | ✓ shipped | Module-isolation policy + audit. Different concern from `dispatcher.zig` — guards WASM host imports, not JSON-RPC resources. |
| Native event bus | `helm_event_broker.zig` (874 LOC) + `event_loop.zig` (391 LOC) | ✓ shipped | Pub/sub for cartridge-emitted events. Distinct from `nats_event_bridge.zig` (which mirrors local events into NATS for operator-internal consumption). |

**Status summary**: Dispatcher Phase 0 shipped, the unification target is real, the verb-walker registry that **is the cartridge boundary in code** ships. Phase 1+ migrations (bearer-token, HTTP transport) outstanding.

**Correction to my prior reading**: I previously said "5 dispatcher-shaped files need consolidation." Wrong. They're six different abstractions at different layers, intentionally separate by design.

---

## 5. Cartridge inventory (both kinds)

### 5.1 Operational/FSM cartridges (`extensions/*`)

Counted excluding `node_modules/`:

**Substantial (working/in-progress):**
| Cartridge | Source files | Posture |
|---|---|---|
| `extensions/games/` | 144 | Game vertical |
| `extensions/oddjobz/` | 90 | Exemplar cartridge — 8 canonical cell types, ratify walker pattern, brain-side counterparts (jobs/quotes/invoices/customers/leads/visits FSMs in brain core — see §6) |
| `extensions/extraction/` | 50 | Phase 36B candidate |
| `extensions/calendar/` | 40 | Per-Phase-1b migration to BRC-52 pending |
| `extensions/cdm/` | 38 | ISDA CDM vertical |
| `extensions/game-sdk/` | 36 | Game SemanticObject SDK (Phase 26 GAME-ENGINE-SDK errata: PASS 9/9) |
| `extensions/scada/` | 31 | SCADA chapter-26 vertical |
| `extensions/dispatch/` | 20 | ✓ shipped per ADAPTER-TAXONOMY §4 |

**Stub / early state:**
| Cartridge | Source files | Notes |
|---|---|---|
| `extensions/re-desk-stub/` | 13 | Explicitly stub-shaped |
| `extensions/chain-broadcast/` | 8 | ✓ shipped per ADAPTER-TAXONOMY §4 — short LOC, fully built |
| `extensions/metering/` | 7 | MFP channel-fsm shipped per ADAPTER-TAXONOMY §4 |
| `extensions/navigation/` | 7 | — |
| `extensions/pask-ga/` | 6 | ✓ shipped per ADAPTER-TAXONOMY §6 — small surface |
| `extensions/policy-runtime/` | 6 | Prompt 43 |
| `extensions/pask-vault-notion/` | 5 | ⚠ partial |
| `extensions/md-editor/` | 4 | ✗ stub per ADAPTER-TAXONOMY §4 |
| `extensions/scg/` | 4 | — |
| `extensions/pask-vault-obsidian/` | 4 | ⚠ partial |
| `extensions/recovery/` | 3 | Plexus recovery wiring |
| `extensions/navigator/` | 2 | — |
| `extensions/sites/` | **0** | **Empty placeholder** |

LOC ≠ status. Short LOC + working (chain-broadcast, pask-ga) sits next to short LOC + stub (md-editor). The unification matrix is authoritative; this inventory just bounds the universe.

### 5.2 World-app cartridges (`apps/world-apps/*`) — previously a doc gap

ADAPTER-TAXONOMY §7 flags `apps/world-apps/` as **DOC GAP — World vertical apps. No README, no package.json at top level**. Section 9 of that doc lists it among the documentation-gap directories to close. This is that closure for jam-room:

**`apps/world-apps/jam-room/`** — 93 source files (excl. node_modules), package version 0.2.0, package descriptor declares `semantos: { worldApp: true, protocol: 'world-beam', relay: 'cell-relay' }`.

What's already real on disk (per `docs/prd/jam-room/MASTER.md` §1):
- `src/grid/surface.ts` (525 LOC) — 8×8 pad surface, five Push-3-style modes
- `src/sequencer.ts` (419 LOC) — 13 tracks, four scenes, per-cell vel/prob/ratchet/accent/slide
- `src/audio.ts` (1089 LOC) — WebAudio engine, parallel reverb/delay buses with freeze, sidechain duck, master limiter
- `src/core/beam-clock.ts` (210 LOC) — `BEAMClock` NTP-style sync over CellRelay WebSocket
- `src/core/sync.ts`, `src/core/dag.ts`, `src/core/anchor.ts` — DAG helpers + BSV PushDrop anchoring of session snapshots
- `src/semantic/objects.ts` (688 LOC) — defines `JamboxObjectKind` with 13 declared kinds (`jam.world`, `jam.instrument`, `jam.skin`, `jam.patch`, `jam.snapshot`, `jam.crate`, `jam.track`, `jam.sample-pack`, `jam.sample`, `jam.clock-calibration`, `jam.drum-track`, `jam.pattern`, `jam.arrangement`)
- Companion: `apps/world-apps/jam-room-mobile/` + `packages/jam_experience/` (Flutter/Dart)
- Brain-side hooks: `runtime/semantos-brain/src/jam_clip_state_store.zig`, `runtime/semantos-brain/src/jambox_walkers.zig`
- Release config: `apps/world-apps/jam-room/release.config.ts` (room `release.app.jam-room`, hat `jam-room-maintainer@semantos`)

What jam-room demonstrates about cartridges that no `extensions/*` cartridge does:
- **A user-facing UI surface is a cartridge.** Svelte + three.js + WebAudio bundled with cell-type schema + BSV anchoring + identity binding. The same primitive as oddjobz, different shape.
- **Cartridges can be multi-platform.** Web (Svelte) + mobile (Flutter) share cell-type schema but ship separate UI bundles.
- **Cartridges anchor independently.** Jam-room signs session snapshots via BSV PushDrop; doesn't depend on the operator's wallet cartridge for anchoring. (The AnchorAdapter interface makes this clean — same interface, different consumer.)

What's not there per MASTER §1.6:
- `jam.macro` (per-rack macro controls)
- `jam.clip` as launchable distinct from pattern
- `jam.scene` as launchable group (currently just integer 0–3)
- `jam.take` (captured performance pass)
- `jam.contribution` (split-aware authorship)
- `jam.player` (formal player object)
- `jam.mapping` (controller/rack mapping)
- `jam.rack` (composable instrument bundle)
- `jam.gesture` (filter sweep, riser)
- Note mode (scale/iso/chord), Mix mode
- Strudel adapter, PureData bridge
- Loop-orb / scene-floor / arrangement-wall as control surfaces

These are exactly the Phase A–F PRD scope (13–17 weeks total across phases A through G with 20% buffer). **None of Phases A–G has shipped** — no errata in `docs/prd/jam-room/`.

So jam-room is: substantial v0.2.0 working code, 0 of 7 forward-leaning phases shipped, world-app exemplar that closes the doc gap on the world-app cartridge kind.

---

## 6. Brain-side baked-in cartridge code (the lift-out gap)

Cartridge contract shipped (Phase 36A) doesn't mean existing brain code respects the boundary. Files currently in `runtime/semantos-brain/src/` that are cartridge-shaped:

### 6.1 oddjobz code in brain core
- `oddjobz_attention_handler.zig`, `oddjobz_derivations.zig`, `oddjobz_event_bus.zig`, `oddjobz_query_handler.zig`, `oddjobz_ratify_handler.zig`, `oddjobz_ratify_walker.zig`
- `repl/oddjobz_cmds.zig`
- `intent_action_router.zig` (808 LOC — explicitly oddjobz-specific broker subscriber, NOT a general dispatcher)
- All FSMs + stores: `job_fsm.zig`, `jobs_store_{fs,lmdb,lmdb_entity}.zig`, `quote_fsm.zig`, `quotes_store_{fs,lmdb}.zig`, `invoice_fsm.zig`, `invoices_store_{fs,lmdb}.zig`, `customers_store_{fs,lmdb}.zig`, `leads_store_lmdb.zig`, `visit_fsm.zig`, `visits_store_{fs,lmdb}.zig`
- Their HTTP handlers: `resources/{jobs,quotes,invoices,customers,leads,visits}_handler.zig`

### 6.2 BSV wallet/anchor code in brain core
- Wallet: `wallet_op_http.zig`, `wss_wallet.zig`, `wss_wallet/{handlers,reactor,types}.zig`
- Payment: `payment_ledger.zig`, `payment_verifier{,_stub}.zig`
- Refund: `refund_tx{,_stub}.zig`
- Output store: `output_store_fs.zig`, `lmdb/output_store_lmdb.zig`, `lmdb/derivation_state_store_lmdb.zig`
- CLI: `cli/wallet.zig`

### 6.3 BSV headers code in brain core
- `header_store_fs.zig`, `lmdb/header_store_lmdb.zig`, `headers_sync.zig`, `headers_http.zig`, `resources/headers_handler.zig`, `cli/headers.zig`

### 6.4 Operator-site code in brain core (WSITE1–5.5)
- `site_server.zig`, `site_server/{reactor,util}.zig`
- `sites_store_{fs,lmdb}.zig`, `resources/sites_handler.zig`, `site_config.zig`, `resources/site_config_handler.zig`
- `operator_site_renderer.zig`, `operator_profile.zig`, `operator_profile_loader.zig`, `operator_export.zig`, `operator_exit.zig`
- `caddy_ask_server.zig`, `caddy_template.zig`, `sni_domain_map.zig`, `domain_allowlist.zig`
- `cli/site.zig`

### 6.5 Jam-room hooks in brain core
- `jam_clip_state_store.zig`, `jambox_walkers.zig`

**This is "the lift-out gap"** — no PRD currently scopes it. Phase 26 defined the abstract interfaces. Phase 36 defined the cartridge contract. Neither phase scoped "carve the existing baked-in implementations out of brain-core into separate cartridges." This is the missing PRD.

The lift-out is *not strictly necessary for V1.0* (which is single-node OJT migration — see §7) but **is necessary for the distro pattern** (anyone spinning up a fresh brain shouldn't get OJT-shaped code in their kernel).

---

## 7. V1.0 + brain-side provisioning streams

Reference: `docs/design/V1.0-EXECUTION-PLAN.md` (2026-04-27).

V1.0 = OJT migration + Wallet Pack on a single VPS (`ssh rbs`). Seven sequential stages. Per memory `brain_reactor_v1_recovery_complete.md` (2026-05-13): T0/T1/T2/T4/T5 landed on main; T3 deferred; production binary on ssh rbs predates the work (deploy + PWA round-trip pending). So V1.0 is substantially complete.

**Explicit V1.0 scope decision**: *"Single-node V1.0 first; federation second."* All federation code (peer_registry, slot_router, udp_protocol, p2p_wire, federation/federated_*_store) is post-V1.0 forward-leaning.

**Parallel brain-side provisioning stream (D-O8/9/10)** is shipped:
- `tenant_manifest.zig` (1836 LOC, D-O8) — TOML manifest schema + parser + validator
- `provision_tenant.zig` (1211 LOC, D-O10) — `brain provision-tenant <manifest.toml>` CLI with 12-step provisioning flow + byte-stable log lines
- Plexus calls stubbed at v0.1; real wiring is D-W2 Phase 1
- Multi-tenant on a single brain host already works today

This is distinct from Phase 26G Node Packaging (which would be the *brain binary distribution* mechanism, Docker + systemd + three-persona installer). Two complementary packaging streams: brain-Zig-side (D-O10, shipped) + TypeScript/Docker-side (Phase 26G, outstanding).

---

## 8. The real gap

Cross-stream synthesis of what's shipped vs outstanding for **"brain as Linux-distro experience loader with formalized cartridges"**:

### What's shipped
| Capability | Stream | Evidence |
|---|---|---|
| Four substrate adapter interfaces | Phase 26A/B/C/D | protocol-types + multiple impls |
| Cartridge contract (meta-schema) | Phase 36A | errata 2026-04-12 |
| Cartridge governance model | Phase 36D | errata |
| Schema inference agent | Phase 36C | errata |
| Auth-gated capability-checked dispatcher (Phase 0) | BRAIN-DISPATCHER-UNIFICATION | dispatcher.zig |
| Verb-walker registry (cartridge code boundary) | — | verb_dispatcher.zig |
| Module loader + lifecycle FSM + audit | Brain 1+2.5+2.6 | module_loader.zig, instance_manager.zig, broker.zig |
| Multi-tenant provisioning on one host | D-O8 + D-O10 | tenant_manifest.zig, provision_tenant.zig |
| Cartridge scaffold tool | RM-097 voice→cartridge loop | `tools/cartridge-scaffold/` with `cartridge new <name>` |
| Native event bus + producers/subscribers | — | helm_event_broker.zig, event_loop.zig |
| Local-mesh federation transport | Phase 35A | UDP multicast + peer registry + slot router |
| Cross-internet WSS transport | Phase 35B (per ADAPTER-TAXONOMY correction) | runtime/ws-node-adapter + runtime/peer-locator |
| One mature exemplar operational cartridge | — | extensions/oddjobz (90 src files, 8 cell types, ratify walker pattern) |
| One substantial world-app cartridge | — | apps/world-apps/jam-room (93 src files, 13 jam.* kinds, BSV anchoring) |

### What's outstanding (named PRDs)
| Gap | Stream | Effort estimate |
|---|---|---|
| Semantic Extraction Pipeline (5-stage fetch→commit) | Phase 36B | 3 weeks (PRD) |
| Extension Manager UI | Phase 36E | unscoped |
| Connector Reference Impl | Phase 36F | unscoped |
| Dispatcher Phase 1+ migrations (bearer-token, HTTP transport) | BRAIN-DISPATCHER-UNIFICATION §Phase 1+ | unscoped — named in dispatcher.zig header |
| Plexus wiring for provision-tenant | D-W2 Phase 1 | unscoped |

Phase 26 sub-phases 26E/F/G/H all shipped as of audit 2026-05-15 (see §2 table). No remaining work in the Phase 26 stream.

### What's outstanding (no PRD yet)
| Gap | Why it matters | Note |
|---|---|---|
| **Lift oddjobz code out of brain-core into the cartridge** | Distro pattern requires fresh brain to have no OJT-shaped code | §6.1 — biggest carve |
| **Lift wallet/headers/payment out of brain-core into a `bsv-anchor-bundle` cartridge** | The "default install bundle" needs to be cartridges, not baked-in code | §6.2 + §6.3 |
| **Lift operator-site (WSITE1–5.5) out of brain-core into the cartridge** | Same as above | §6.4 |
| **Cartridge manifest format ↔ Phase 36A grammar alignment** | Today's implicit `package.json` manifest may not align with Phase 36A schema | Sidequest 2 in SHELL-CARTRIDGES-HATS §11 |
| **Default-distro bundle definition** | "Brain ships with these N cartridges pre-loaded" — no code/config for this | Linux-distro analogue: the default install metaphor §1 |
| **Jam-room phases A–G** | World-app exemplar deepens; useful for cartridge-contract pressure-testing | `docs/prd/jam-room/MASTER.md` 13–17 weeks |

### What's outstanding (V1.0 deploy tail)
- Brain V1 production deploy (per memory `brain_reactor_v1_recovery_complete.md`) — production binary on ssh rbs predates the recovery work; round-trip with PWA pending
- T3 deferred — scope analysis captured in memory

---

## 9. Where the cartridge idea is cleanest (and where it isn't)

**Clean parts (the canon):**
1. A cartridge declares **one Extension Grammar JSON** (Phase 36A meta-schema) — entities, field mappings, object types, capability requirements, taxonomy coordinates, migration rules. Validated.
2. A cartridge registers **walkers** with `verb_dispatcher.zig` for each declared verb. Walkers are functions of `(allocator, ctx, params_json) → result_json`. Capability is declared per verb; deny-by-default at dispatch.
3. A cartridge owns **typed cells** with linearity class (LINEAR / AFFINE / RELEVANT / DEBUG / FUNGIBLE-stand-in). Cell types validate against the kernel's typeHash registry.
4. A cartridge consumes substrate services via **four adapter interfaces** (Storage / Identity / Anchor / Network). Each interface has shipping BSV implementations and stub implementations.
5. A cartridge ships with a **release.config.ts** declaring name + room + maintainer hat + version + artifacts + dependencies. Releases land in the substrate's cell-relay versioning room.

**Less clean parts (the contradictions to resolve):**
1. **Two cartridge kinds, two homes.** `extensions/*` for operational/FSM cartridges and `apps/world-apps/*` for world-app cartridges. Per memory `semantos_two_cartridge_kinds.md`: audits that sweep only one location undercount. The doc canon (`SHELL-CARTRIDGES-HATS.md`) treats "apps" as cartridges but doesn't yet name `apps/world-apps/` specifically as a cartridge home; ADAPTER-TAXONOMY §7 mentions `apps/world-apps/` as a doc gap.
2. **Cartridge-shaped code still inside brain-core.** Oddjobz, wallet, headers, operator-site, jam-room hooks all have files in `runtime/semantos-brain/src/`. The cartridge contract exists; the carve to honor it doesn't.
3. **Manifest format ambiguity.** Phase 36A defined the JSON meta-schema. `extensions/oddjobz/package.json` is an implicit manifest. BRC-102 is referenced as a possible alignment target (SHELL-CARTRIDGES-HATS §9, sidequest §11.2). Three formats, one canon needed.
4. **Default install bundle is undefined.** Brain ships pre-loaded with what? No config, no convention. The Linux-distro analogue requires this and nothing names it today.
5. **`extensions/sites/` is literally empty (0 source files).** Either purge or fill — placeholder hurts the doc story.

---

## 10. Proposed unification-matrix.yml deltas

Per `UNIFICATION-DOC-BURST-PLAN.md` §11.4 stop note, matrix mutations are **surfaced before applying** — not made autonomously. The following deltas come out of this analysis. Apply manually after review.

### 10.1 New rows to add under `adapter:` (cartridge-shaped surfaces)

```yaml
- id: world-app-jam-room
  name: Jam Room — world-app cartridge
  note: |
    Collaborative music sequencer running inside a Semantos world region
    (BEAM-backed). Multi-platform: Svelte+three.js web at
    apps/world-apps/jam-room/ (93 src files, v0.2.0); Flutter mobile at
    apps/world-apps/jam-room-mobile/; brain hooks at
    runtime/semantos-brain/src/{jam_clip_state_store,jambox_walkers}.zig.
    Declares 13 jam.* SemanticObjectKind in src/semantic/objects.ts.
    Anchors session snapshots via BSV PushDrop (src/core/anchor.ts).
    PRD: docs/prd/jam-room/MASTER.md Phases A-G (13-17 weeks, 0/7 shipped).
  axes:
    A:
      status: "⚠"
      note: "ownerIdentity + ownerCertId on every JamboxObject header; BRC-52 cert wiring partial."
    B:
      status: "⚠"
      note: "Content-addressed cells via SemanticObjectHeader.previousStateHash; not yet conformance-tested vs cell-relay canonical."
    C:
      status: "⚠"
      note: "CellRelay WebSocket transport; SignedBundle wrapping unverified."
    D-sub:
      status: "⚠"
      note: "linearity field present in SemanticObjectHeader; K1 enforcement at-relay unverified."
    D-lex:
      status: "✗"
      note: "13 jam.* kinds declared in code, not registered with canonical lexicon authority."
    D-form:
      status: "n/a"
      note: "World-app surface; formal proof is U9's domain."
    D-cap:
      status: "✗"
      note: "Blocked on D-Dcap-engine landing BRC-108/115 capability UTXO checks."
    E:
      status: "⚠"
      note: "previousStateHash + DAG helpers in src/core/dag.ts; BEAMClock NTP sync via clock_ping/pong; full anchor chain via PushDrop."
    F:
      status: "✗"
      note: "Plexus recovery wiring not connected."
    G:
      status: "✗"
      note: "Metering channels not opened; jam.world commercial info fields exist but no MFP."

- id: world-app-doc-gap
  name: world-apps directory documentation
  note: |
    Closes the documentation gap flagged in ADAPTER-TAXONOMY.md §9 for
    apps/world-apps/. Catalog of world-app cartridges (currently jam-room
    + jam-room-mobile) added in CARTRIDGE-DISTRO-GAP-ANALYSIS.md §5.2.
  axes:
    A:
      status: "n/a"
      note: "Documentation row, not an adapter axis."
```

### 10.2 Status flips to consider (require live-grid review)

- **Phase 26 row, axes A/C** — if 26A/26B/26C status not yet ✓ in matrix, flip per §2 evidence (interfaces shipped in protocol-types with multiple impls).
- **Phase 36 row, axes affecting cartridge contract** — if matrix doesn't yet reflect 36A/36C/36D shipped, flip per §3 erratas.
- **G5 federation transport** — already corrected per ADAPTER-TAXONOMY commit `152d25a` (the 35B WSS adapter ships); ensure matrix mirrors that.

### 10.3 New deliverable IDs to consider declaring

To track the "no PRD yet" lift-out gaps (§8):

- **D-Lift-oddjobz**: Carve oddjobz code out of `runtime/semantos-brain/src/oddjobz_*.zig` + FSMs + stores + handlers into `extensions/oddjobz/`. Tests: brain core compiles + runs with oddjobz unloaded; brain core with oddjobz loaded passes existing oddjobz_*_test.zig.
- **D-Lift-bsv-anchor**: Carve wallet + headers + payment_ledger + refund_tx out of brain-core into a `bsv-anchor-bundle` cartridge that bundles wallet + headers + payment-policy. Brain core falls back to no-op AnchorAdapter when bundle not loaded.
- **D-Lift-wsite**: Carve WSITE1–5.5 (site_server + sites_store + operator_site_renderer + caddy_*) into an `operator-site` cartridge.
- **D-Distro-default-install**: Define which cartridges ship in the default brain install bundle. Manifest declaring the four substrate-exposing first-party cartridges (identity-hat, peer-pair, status-dashboard, minimal-talk). Build/CI plumbing.
- **D-Manifest-canonical**: Resolve the three-format manifest ambiguity (Phase 36A grammar JSON vs `extensions/*/package.json` vs BRC-102). Pick one canon, migrate.

---

## 11. Honest distance to the distro pattern

Using only PRD-named estimates + named (but unscoped) carves:

| Category | Items | Estimated effort |
|---|---|---|
| Named PRDs outstanding | Phase 36B | ~3 weeks (PRD) |
| Named PRDs unscoped | 36E + 36F + dispatcher Phase 1+ + D-W2 Plexus wiring | unknown |
| New PRDs needed (the lift-outs) | D-Lift-oddjobz + D-Lift-bsv-anchor + D-Lift-wsite + D-Distro-default-install + D-Manifest-canonical | unscoped — likely 6–10 weeks combined for the four lifts + 1 week for the default-install + 1 week for manifest unification, gated on PRD-writing first |
| V1.0 tail | T3 + deploy + PWA round-trip | unknown |

So the headline gap is roughly: **~3 weeks of named-PRD work + ~6–10 weeks of new-PRD work** stands between today and the distro pattern. The cartridge contract is shipped (Phase 36A). The four adapter interfaces are shipped (Phase 26A-D). The node packaging mechanism is shipped (Phase 26G — Dockerfile, install.sh, semantos CLI). What's missing is **the lift-out of cartridge-shaped code from brain-core** (D-Lift-* PRDs not yet written) — without it, the Phase 26G installer packages a brain that still has OJT-shaped code in its kernel.

For the OSS pitch (see `oss_substrate_carve_parked.md` memory): the distro pattern doesn't gate OSS. You can ship the OSS substrate with cartridges-baked-into-brain-core as a v1 limitation and a v2 roadmap. But the OSS pitch is materially stronger if **at least D-Lift-bsv-anchor lands** — so the OSS substrate isn't "Semantos's BSV sovereign node," it's "a substrate that hosts arbitrary anchored cartridges, of which `bsv-anchor-bundle` is the reference."

---

## 12. Sources referenced

- `docs/prd/PHASE-26-KERNEL-ISOLATION-MASTER.md` + sub-phase PRDs
- `docs/prd/PHASE-26-ERRATA.md`, `docs/prd/PHASE-26D-ERRATA.md`
- `docs/prd/PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md` + sub-phase PRDs
- `docs/prd/PHASE-36A-ERRATA.md`, `docs/prd/PHASE-36C-ERRATA.md`, `docs/prd/PHASE-36D-ERRATA.md`
- `docs/design/BRAIN-DISPATCHER-UNIFICATION.md`
- `docs/design/V1.0-EXECUTION-PLAN.md` (2026-04-27)
- `docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md`
- `docs/design/ODDJOBZ-EXTENSION-PLAN.md` (D-O8/D-O10 references)
- `docs/prd/jam-room/MASTER.md` (Phases A–G) + companion phase PRDs
- `docs/ADAPTER-TAXONOMY.md` (sibling synthesis, §7 + §9 doc gaps)
- `docs/SHELL-CARTRIDGES-HATS.md` (the model, §11 pending design work)
- `docs/UNIFICATION-DOC-BURST-PLAN.md` (the 2026-05-13 burst, all tiers complete)
- `docs/canon/unification-matrix.yml` (live status grid; deltas proposed in §10 above)
- `runtime/semantos-brain/src/dispatcher.zig`, `verb_dispatcher.zig`, `payload_type_router.zig`, `broker.zig`, `module_loader.zig`, `instance_manager.zig`, `tenant_manifest.zig`, `provision_tenant.zig`, `extensions.zig`
- `runtime/semantos-brain/src/federation/{federation,slot_router,peer_registry}.zig`
- `core/protocol-types/src/{storage,identity,anchor,network}.ts` + impl files in `adapters/` and `identity-adapters/`
- `apps/world-apps/jam-room/` (src + bridge + serve + release.config.ts)
- `tools/cartridge-scaffold/README.md`
- Memory: `semantos_two_cartridge_kinds.md`, `brain_reactor_v1_recovery_complete.md`, `oss_substrate_carve_parked.md`, `semantos_federation_transport.md`, `shell_cartridges_hats_model.md`, `semantos_no_ai_in_substrate.md`, `semantos_dx_priorities.md`

Update this doc when status changes. Don't let the unification matrix or ADAPTER-TAXONOMY claim a status this gap-analysis contradicts without checking which is stale.
