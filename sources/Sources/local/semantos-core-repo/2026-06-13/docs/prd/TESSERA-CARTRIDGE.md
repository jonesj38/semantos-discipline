---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/TESSERA-CARTRIDGE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.660904+00:00
---

# Tessera Cartridge — Plan

**Version**: 0.2 DRAFT
**Status**: Plan
**Author**: Todd
**Date**: 2026-05-15 (initial draft); 2026-05-16 (revised against cartridge distro pattern)
**Changelog**:
- 0.2 — Revised against the cartridge distro pattern (`docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md` 2026-05-15) and the in-flight lift program (`docs/prd/D-LIFT-BSV-ANCHOR.md`, `docs/prd/D-LIFT-ODDJOBZ.md`). Explicit hard dependency on DLO.1 (generic cartridge loader) added. Greenfield-discipline subsection added (§0.1) — tessera never inherits the brain-core-baked anti-pattern the lift PRDs are correcting. Manifest is dual-file per the bsv-anchor-bundle scaffold precedent: `cartridges/tessera/cartridge.json` (Phase 36A ExtensionManifest) + `cartridges/tessera/brain/release.config.ts` (release pipeline). Adapter-interface consumption made explicit: StorageAdapter, IdentityAdapter, AnchorAdapter, NetworkAdapter from `core/protocol-types/`. V0.6 Zig project scaffold added.
- 0.1 — initial draft.

**Prerequisites** (must land before V0.3 + V3 + V4 dispatch):
- **DLO.1 (generic cartridge loader)** — `runtime/semantos-brain/src/extensions.zig` generalised from hardcoded oddjobz to reading manifests from `<data_dir>/extensions/<id>/manifest.json` per `docs/prd/D-LIFT-ODDJOBZ.md`. Until DLO.1 lands, the brain can only load oddjobz; tessera cannot be wired into `verb_dispatcher.zig`.
- **Phase 26A–H (kernel isolation)** — ✓ shipped. Four substrate adapter interfaces (StorageAdapter, IdentityAdapter, AnchorAdapter, NetworkAdapter) live in `core/protocol-types/`. Brain installer ships via `scripts/install.sh` + `semantos` CLI (Phase 26G).
- **Phase 36A (Extension Grammar JSON Schema)** — ✓ shipped (`PHASE-36A-ERRATA.md` 2026-04-12). Tessera's `manifest.json` conforms to the `ExtensionManifest` shape in `core/protocol-types/src/extension-manifest.ts`.
- **Phase 36D (Extension Governance Model)** — ✓ shipped. Three-tier hierarchy with consumer bindings.
- **`verb_dispatcher.zig`** — ✓ shipped. Generic `(extensionId, verb) → walker` registry. Tessera registers walkers here with `extensionId="tessera"`.
- **`dispatcher.zig` Phase 0** — ✓ shipped. Auth-gated, capability-checked, audit-logged seam. Tessera dispatches via this.
- **D-O8 `tenant_manifest.zig` + D-O10 `provision_tenant.zig`** — ✓ shipped. Multi-tenant on a single brain host. A Provenance Club fulfilment centre and N producer winery operators can run as tenants on one brain box.

**Companion / parallel-track PRDs**:
- `docs/prd/D-LIFT-ODDJOBZ.md` — the operational-cartridge lift PRD; establishes the carve pattern + DLO.1 generic loader. Tessera follows this pattern from day one (no carve needed because tessera is greenfield).
- `docs/prd/D-LIFT-BSV-ANCHOR.md` — the BSV-anchor lift PRD; relevant because tessera consumes `AnchorAdapter`, not bsv-anchor primitives directly.
- `docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md` — master synthesis doc; tessera is one entry in the cartridge ecosystem this analysis maps.

**Related**:
- `docs/SHELL-CARTRIDGES-HATS.md` — PWA shell + cartridges + hats model; the clean cartridge contract (five parts) and the two cartridge homes
- `docs/ADAPTER-TAXONOMY.md` — substrate vs adapter status table; tessera lands as a new row
- `docs/textbook/34-cell-alignment.md` — D-Doc-1024; the 1024-byte cell across network, disk, runtime, K5; the SHA-256 = BSV anchor unit underpinning consumer scan
- `docs/textbook/35-three-kernels.md` — D-Doc-three-kernels; HRR + 2PDA + Pask layering
- `docs/textbook/36-federation-transport.md` — D-Doc-fed; the four federation layers + operator-internal NATS sibling
- `docs/PROOF-COVERAGE.md` — D-Dform-coverage; proposed K15–K18 invariants this cartridge depends on
- `docs/design/ODDJOBZ-EXTENSION-PLAN.md` — sibling extension plan; same shape
- `docs/prd/BRAIN-FIELD-APP-DB-PIPELINE.md` — the universal field-app pattern this cartridge instantiates ("For other hats (the pattern)" §); note Pravega references in this doc are stale per the streams-tier substitution
- `docs/prd/SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md` — streams-tier substitution note (Pravega → NATS JetStream, 2026-05-14)
- `docs/prd/ODDJOBZ-HOSTED-OPERATOR-STANDUP.md` §2 + W7.3 — canonical NATS subject convention (`op.<pkh16>.<hat>.<event>`) and brain-side wiring (`nats_client.zig`, `nats_event_producer.zig`, `nats_event_bridge.zig`, `nats_subscriber.zig`, `nats_orphan_detector.zig`)
- `docs/prd/UNIFICATION-ROADMAP.md` §2b — the adapter row tessera adds
- `docs/canon/unification-matrix.yml` — the structured matrix; tessera adds one adapter row
- `docs/canon/lexicons.yml` — tessera lexicon registers here; sibling to trades, jural, calendar, brap
- `proofs/lean/Semantos/Lexicons/` — D-Dform-tessera Lean theorems live here
- `extensions/bsv-anchor-bundle/` — in-flight cartridge skeleton (manifest.json + release.config.ts + src + zig); tessera's directory layout mirrors this canonical shape
- `tools/cartridge-scaffold/` — `cartridge new tessera` scaffolds the canonical layout

---

## 0. Headline

> Build `cartridges/tessera/` — a substrate-native cartridge for grape-to-glass-shaped traceability over any physically handed-off object whose value depends on a verifiable care chain. Tessera registers a lexicon of harvest / blend / bottle / custody-transfer / care-event / tamper / scan speech acts; declares cell types with the right linearity class (LINEAR for one-shot transitions, AFFINE for accumulating event streams, RELEVANT for evidence that must exist for a derived view to render); ships walker verbs registered via `verb_dispatcher.zig` with `extensionId="tessera"`; consumes the four Phase-26 adapter interfaces (`StorageAdapter`, `IdentityAdapter`, `AnchorAdapter`, `NetworkAdapter`) from `core/protocol-types/`; and exposes its surface through the field app as seven hats over one brain. Every primitive the cartridge needs already exists in substrate; this plan is composition, not invention. The first commercial surface is a wine-traceability deployment, but the cartridge is neutral by design — cold-chain pharma, premium coffee, art transit, and any future care-chain vertical run on the same `cartridges/tessera/` against the same brain with their own brands at the surface layer.

## 0.1 Greenfield discipline (binding for this PRD)

Tessera is greenfield. It must NEVER reproduce the brain-core-baked anti-pattern that `D-Lift-oddjobz`, `D-Lift-bsv-anchor`, and `D-Lift-wsite` are correcting. This is a hard discipline on the cartridge from day one:

1. **No tessera identifier in `runtime/semantos-brain/src/` paths, ever.** `grep -r "tessera" runtime/semantos-brain/src/` returns zero matches at every commit. The substrate side of the cartridge contract (`verb_dispatcher.zig` walker registry, `extensions.zig` generic loader, `octave_registry.zig` cell-type registry, four adapter interfaces) is the entire surface tessera touches in brain-core.
2. **No direct LMDB imports.** Tessera's Zig stores consume `StorageAdapter` (`core/protocol-types/src/storage.ts`). The LMDB primitives in `runtime/semantos-brain/src/lmdb/` (cell_store, composite_write, drift_detector, lmdb, lmdb_config, registry_cache) are substrate; brain-core provides an LMDB-backed `StorageAdapter` implementation that tessera consumes through the interface. This mirrors DLO.3's resolution.
3. **No direct BSV / bsv-anchor imports.** Tessera anchors cells via `AnchorAdapter` (`core/protocol-types/src/anchor.ts`). Production deployments use `bsv-anchor-adapter` (provided by the `bsv-anchor-bundle` cartridge once `D-Lift-bsv-anchor` lands). Test deployments use `stub-anchor-adapter`. Tessera knows nothing about BSV, BRC-22, BRC-24, BRC-69, headers, or txids directly — only the `AnchorAdapter` contract.
4. **No direct session-protocol or peer-locator imports for federation.** Tessera publishes cross-operator `SignedBundle<TesseraPatch>` through `NetworkAdapter` (`core/protocol-types/src/network.ts`). Production deployments use `bsv-overlay-network-adapter`; intra-operator multicast and cross-internet WSS are choices of the adapter implementation, not tessera's concern.
5. **No top-level resource registration on `dispatcher.zig`.** Every tessera verb routes through `verb.dispatch` with `extensionId="tessera"` per the cartridge contract. Audit-log `module` field shows `tessera` for every cartridge-originated dispatch.
6. **No bypass of the cartridge loader.** Until DLO.1 lands, tessera is unloadable; the plan accepts this and split V0 into pre-loader-landing deliverables (lexicon canon, Lean theorems, cell-type declarations, manifest files, walker source files in declaration form) and post-loader-landing deliverables (runtime wire-in, octave registration, walker dispatch).

This discipline is enforced by:
- A CI gate `tests/gates/no-tessera-in-brain-core.test.ts` (added in V0.1) that fails if any path under `runtime/semantos-brain/src/` contains the literal string `tessera`.
- A CI gate `tests/gates/tessera-adapter-consumption.test.ts` (added in V0.5) that asserts tessera's TS source imports only from `@semantos/protocol-types/*` (not from `@semantos/wallet-toolbox`, `@bsv/sdk`, or any LMDB / bsv-overlay module directly).

---

## 1. The Pattern

```
                        ┌──────────────────────────────────────────┐
                        │ operator's sovereign node                 │
                        │                                          │
   ┌─────────────────┐  │  ┌────────────────────────────────────┐  │
   │ physical object │──┼─►│ Tier 1 — hardware peer             │  │
   │   bottle, case, │  │  │   NFC tamper seal (NTAG 213-TT,    │  │
   │   pallet …      │  │  │     BCA-derived from chip UID)     │  │
   └─────────────────┘  │  │   temp logger (semi-passive NFC)   │  │
                        │  │   thermo sticker (manual flag)     │  │
                        │  └──────────────┬─────────────────────┘  │
                        │                 │ verb.dispatch          │
                        │                 ▼                        │
                        │  ┌────────────────────────────────────┐  │
                        │  │ tessera cartridge                  │  │
                        │  │   types: GrapeLot AFFINE, Barrel   │  │
                        │  │     LINEAR, Bottle LINEAR, Case    │  │
                        │  │     LINEAR, Pallet LINEAR, Ship-   │  │
                        │  │     ment LINEAR, CareEvent        │  │
                        │  │     AFFINE, ScanEvent RELEVANT,   │  │
                        │  │     TastingNote DEBUG, Tamper-    │  │
                        │  │     Event LINEAR                  │  │
                        │  │   lexicon: tessera                 │  │
                        │  │   caps: cap.tessera.{bottle,       │  │
                        │  │     custody, care-record, scan,    │  │
                        │  │     blend-declare}                 │  │
                        │  │   walkers per verb (12)            │  │
                        │  │   release config                   │  │
                        │  └──────────────┬─────────────────────┘  │
                        │                 │                        │
                        │   ┌─────────────┴────────────┐           │
                        │   │ Semantos substrate       │           │
                        │   │   cell engine (K1–K14)   │           │
                        │   │   capability domain      │           │
                        │   │   identity (BRC-52/BCA)  │           │
                        │   │   federation transport   │           │
                        │   │   event-stream tier      │           │
                        │   │     (NATS JetStream)     │           │
                        │   │   Lean proof layer       │           │
                        │   └──────────┬───────────────┘           │
                        │              │                           │
   ┌─────────────────┐  │              ▼                           │
   │ field-app user  │──┼──►┌────────────────────────────────────┐ │
   │   hat = one of  │  │   │ Tier 2 — field-app hat surfaces    │ │
   │   producer /    │  │   │   producer · field-worker          │ │
   │   distributor / │  │   │   distributor · dock-handler       │ │
   │   dock-handler /│  │   │   retailer · club-member           │ │
   │   retailer /    │  │   │   reads/writes brain via verb.     │ │
   │   club-member   │  │   │     dispatch + hat-scoped views    │ │
   └─────────────────┘  │   └────────────────────────────────────┘ │
                        │                                          │
   ┌─────────────────┐  │   ┌────────────────────────────────────┐ │
   │ anonymous tap   │──┼──►│ Tier 3 — consumer NFC-tap PWA      │ │
   │   "is this      │  │   │   no install, no login             │ │
   │   bottle good?" │  │   │   ambient hat tessera.consumer     │ │
   └─────────────────┘  │   │   SPV-verifies bottle cell <100ms  │ │
                        │   │   renders Care Score + story       │ │
                        │   └────────────────────────────────────┘ │
                        └──────────────────────────────────────────┘

   Federation across operators (per docs/textbook/36-federation-transport.md):

       producer.example  ◄── Phase-26D NetworkAdapter ──►  distributor.example
       (tessera ext)         SignedBundle<TesseraPatch>         (tessera ext)
                             over Phase-35B WSS
                             (cross-internet, cross-governance-domain)

       distributor's dock-readers  ◄── Phase-35A IPv6 multicast ──►  distributor's brain
                                       (intra-operator only)
```

---

## 2. Canonical inputs (read-only by every implementer)

Every implementer of a tessera deliverable treats the following as source of truth. The cartridge contract is governed by `SHELL-CARTRIDGES-HATS.md`; the lexicon registration ritual is governed by `docs/canon/lexicons.yml` + the existing lexicons (trades, jural, calendar, brap) as exemplars; the W-row pattern is governed by `BRAIN-FIELD-APP-DB-PIPELINE.md` §"For other hats (the pattern)".

| Doc | Path | Role |
|---|---|---|
| Cartridge model | `docs/SHELL-CARTRIDGES-HATS.md` | Five-part cartridge contract; two cartridge homes; four substrate adapter interfaces a cartridge consumes |
| Adapter taxonomy | `docs/ADAPTER-TAXONOMY.md` | Status table tessera adds a row to; substrate vs adapter discipline |
| Cell alignment | `docs/textbook/34-cell-alignment.md` | Why 1024 B; the SHA-256 = BSV anchor unit underpinning consumer scan SPV |
| Three kernels | `docs/textbook/35-three-kernels.md` | HRR + 2PDA + Pask layering; all three load-bearing in tessera |
| Federation transport | `docs/textbook/36-federation-transport.md` | Four-layer story; cross-operator hops; NATS sibling-layer (operator-internal, not federation) |
| Proof coverage | `docs/PROOF-COVERAGE.md` | Proposed K15–K18 invariants; tessera Lean theorems anchor against these |
| Field-app pattern | `docs/prd/BRAIN-FIELD-APP-DB-PIPELINE.md` | Universal W0–W5 pattern; "For other hats (the pattern)" §; **note Pravega refs in this doc are stale per the streams-tier substitution** |
| Streams substitution | `docs/prd/SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md` (2026-05-14 note) | Pravega → NATS JetStream; idempotency + dedupe required |
| NATS subjects & wiring | `docs/prd/ODDJOBZ-HOSTED-OPERATOR-STANDUP.md` §2 + W7.3 | Subject `op.<pkh16>.<hat>.<event>`; `attachNatsProducer` pattern |
| Unification matrix | `docs/canon/unification-matrix.yml` | Tessera adds one adapter row |
| Lexicon canon | `docs/canon/lexicons.yml` | Tessera lexicon registers here as sibling to trades/jural/calendar/brap |
| Protocol spec | `docs/spec/protocol-v0.5.md` | Authoritative for wire formats, identity (§4), capability tokens (§5), SignedBundle (§12.1) |

Supporting reads:

| Doc | When to consult |
|---|---|
| `docs/design/ODDJOBZ-EXTENSION-PLAN.md` | Sibling extension; the closest in-shape precedent. Same five-part cartridge contract; same brain integration; same hat pattern. Tessera mirrors its structure. |
| `docs/EXTENSIONS-VS-TYPES.md` | Four-tier model: extensions are workspaces composing types. Tessera is a workspace; its cell types are first-class. |
| `docs/textbook/28-build-your-first-adapter-kanban.md` | The canonical adapter template tessera follows. |
| `docs/textbook/29-cross-vertical-dispatch-and-federation.md` | Dispatch envelope; how tessera federates with other verticals. |
| `core/semantos-sir/src/lexicons.ts` | Existing lexicons; tessera adds itself to `ALL_LEXICONS`. |
| `proofs/lean/Semantos/Lexicons/Trades.lean` (and siblings) | Lexicon Lean exemplar; tessera authors `Vinifera.lean`-equivalent `Tessera.lean` against the same `headerInjective` obligation. |
| `extensions/oddjobz/` source | Walker registration patterns; manifest shape; FSM-to-capability table (D-O4 analogue). |
| `runtime/semantos-brain/src/nats_event_producer.zig` | Reference for `attachNatsProducer` wiring. |
| `runtime/semantos-brain/src/verb_dispatcher.zig` | Walker registration at brain boot. |
| `runtime/semantos-brain/src/octave_registry.zig` (or equivalent) | Cell-type registration with linearity class. |

Anything not in the canonical or supporting lists is out of scope for implementation.

---

## 3. The cartridge — directory layout + five parts per `SHELL-CARTRIDGES-HATS.md` §4

The directory layout mirrors `extensions/bsv-anchor-bundle/` (the in-flight canonical cartridge skeleton, 2026-05-15) and follows the dual-half pattern resolved by `D-LIFT-ODDJOBZ.md` DECISION-1 (one cartridge = one package, TS + Zig halves under one tree):

```
cartridges/tessera/
├── README.md                   # cartridge overview, install/uninstall notes
├── manifest.json               # Phase 36A ExtensionManifest (canonical declaration)
├── release.config.ts           # repo-wide release pipeline declaration (dual-artifact)
├── package.json                # TS package
├── tsconfig.json
├── src/                        # TS surface
│   ├── capabilities.ts         # cap.tessera.* declarations
│   ├── lexicon.ts              # re-export from core/semantos-sir/src/lexicons.ts
│   ├── object-types/           # cell-type schema definitions
│   ├── flows/                  # state-machine declarations
│   ├── prompts/                # extraction-pipeline prompts
│   ├── taxonomy.json
│   ├── walkers/                # twelve TS-side walker declarations
│   └── adapters/               # TS-side AnchorAdapter / NetworkAdapter consumer wiring
├── zig/                        # Zig surface (FSM impls + walker entry points)
│   ├── build.zig
│   ├── build.zig.zon
│   └── src/
│       ├── tessera_walkers.zig         # registers with verb_dispatcher.zig at boot
│       ├── tessera_fsm/                # bottle, case, pallet, shipment FSMs
│       ├── tessera_stores/             # StorageAdapter-consumer wrappers
│       └── tessera_ratify_walker.zig   # mirrors oddjobz_ratify_walker.zig pattern
└── tests/                      # cartridge-side tests (Zig + TS)
```

The `manifest.json` is the Phase 36A `ExtensionManifest` shape per `core/protocol-types/src/extension-manifest.ts` — the canonical declaration the generic cartridge loader (DLO.1) reads at boot. The `release.config.ts` declares the dual-artifact build (TS bundle + Zig WASM) for the repo-wide release pipeline at `tools/release/`. Note: `D-Manifest-canonical` is pending — three candidate manifest formats (Phase 36A grammar JSON, `package.json`, BRC-102) are not yet reconciled; tessera writes the Phase 36A form per the bsv-anchor-bundle precedent and migrates if D-Manifest-canonical chooses differently.

Tessera ships using `tools/cartridge-scaffold/`'s `cartridge new tessera` command, which generates the canonical layout above. V0.2 (release config) is `cartridge new tessera`, not a manual write.

### 3.1 Grammar — `cartridges/tessera/cartridge.json` + `cartridges/tessera/brain/src/grammar.ts`

Phase 36A `ExtensionManifest` declares the cartridge's substrate surface: id, name, version, `provides`, `consumes`, `wssSubprotocols`, `verbs`, capabilities path, taxonomy path. The TS-side `src/grammar.ts` declares the entity mappings the extraction pipeline (`extensions/extraction/`) uses for NL → cell flow. Both files cohere — the manifest is the brain-loader's canonical reader; the grammar is the extraction-pipeline's reader.

Tessera's `manifest.json` skeleton:

```jsonc
{
  "id": "tessera",
  "name": "Tessera",
  "version": "0.1.0",
  "description": "Care-chain provenance cartridge. Grape-to-glass-shaped traceability over physically handed-off objects.",
  "taxonomyPath": "src/taxonomy.json",
  "flowsDir": "src/flows",
  "promptsDir": "src/prompts",
  "objectTypesDir": "src/object-types",
  "capabilitiesPath": "src/capabilities.ts",
  "provides": [],
  "verbs": [
    { "name": "tessera.harvest", "capability_required": "cap.tessera.harvest" },
    { "name": "tessera.rack", "capability_required": "cap.tessera.rack" },
    { "name": "tessera.blend", "capability_required": "cap.tessera.blend-declare" },
    { "name": "tessera.bottle", "capability_required": "cap.tessera.bottle" },
    { "name": "tessera.assemble-case", "capability_required": "cap.tessera.assemble" },
    { "name": "tessera.transfer-custody", "capability_required": "cap.tessera.custody" },
    { "name": "tessera.record-care-event", "capability_required": "cap.tessera.care-record" },
    { "name": "tessera.tamper", "capability_required": null },
    { "name": "tessera.consumer-scan", "capability_required": "cap.tessera.scan" },
    { "name": "tessera.add-tasting-note", "capability_required": null },
    { "name": "tessera.confirm-receipt", "capability_required": "cap.tessera.custody" },
    { "name": "tessera.report-quality-issue", "capability_required": null },
    { "name": "tessera.thermo-flag", "capability_required": "cap.tessera.care-record" }
  ],
  "consumes": {
    "StorageAdapter": "required — for bottle / case / pallet / shipment / care-event cell stores",
    "IdentityAdapter": "required — for BCA derivation, BRC-52 cert binding on every patch",
    "AnchorAdapter": "required — for SPV-verifiable cell anchoring (consumer scan budget)",
    "NetworkAdapter": "required — for cross-operator SignedBundle<TesseraPatch> federation"
  }
}
```

The `consumes` block is the binding contract that makes greenfield discipline (§0.1) machine-checkable: any tessera code path that imports outside these four interfaces fails CI.

### 3.2 Walkers — `cartridges/tessera/brain/src/walkers/*.ts`

Twelve walker verbs. Each registered with `runtime/semantos-brain/src/verb_dispatcher.zig` at brain boot. Each has the shape `(allocator, ctx, params_json) → result_json`. Single JSON-RPC method `verb.dispatch` routes all twelve; new verbs add walkers, not new endpoints.

| Verb | Hat scope | Produces | Consumes (capability) |
|---|---|---|---|
| `tessera.harvest` | producer, field-worker | `tessera.grape-lot` (AFFINE) | `cap.tessera.harvest` |
| `tessera.rack` | producer | `tessera.barrel` patch | `cap.tessera.rack` |
| `tessera.blend` | producer | new `tessera.barrel` consuming N input barrels | `cap.tessera.blend-declare` |
| `tessera.bottle` | producer | N `tessera.bottle` (LINEAR) consuming one barrel | `cap.tessera.bottle` |
| `tessera.assemble-case` | producer, distributor | `tessera.case` (LINEAR) referencing N bottle cells via typed `SemanticRelation` | `cap.tessera.assemble` |
| `tessera.transfer-custody` | producer, distributor, retailer | custody patch on case/pallet/shipment | `cap.tessera.custody` |
| `tessera.record-care-event` | distributor, dock-handler, hardware-peer (logger) | `tessera.care-event` (AFFINE) | `cap.tessera.care-record` |
| `tessera.tamper` | hardware-peer (tag), club-member, consumer | `tessera.tamper-event` (LINEAR) on a bottle | (implicit — tamper-loop break is self-authorising) |
| `tessera.consumer-scan` | club-member, consumer | `tessera.scan-event` (RELEVANT) | `cap.tessera.scan` |
| `tessera.add-tasting-note` | club-member | `tessera.tasting-note` (DEBUG) | (none — DEBUG class) |
| `tessera.confirm-receipt` | club-member, retailer | custody patch closing inbound | `cap.tessera.custody` |
| `tessera.report-quality-issue` | club-member, retailer | issue patch on bottle | (none — read-issue is open) |
| `tessera.thermo-flag` | dock-handler | manual `tessera.care-event` for flipped sticker | `cap.tessera.care-record` |

### 3.3 Cell types — `cartridges/tessera/brain/src/cell-types/*.ts`

Nine cell types declared in the grammar's object-type section. Each has a linearity class registered into the octave registry at brain boot (the W4.1 pattern, merged). The kernel verifies linearity at execution time per K1.

| Cell type | Linearity | Why |
|---|---|---|
| `tessera.grape-lot` | AFFINE | Partial consumption into multiple barrels; remainder spendable |
| `tessera.barrel` | LINEAR | Consumed entirely at bottling |
| `tessera.bottle` | LINEAR | One tamper-break ends the cell's open trajectory; the PRD's "no double-pour" is literally K1 |
| `tessera.case` | LINEAR | Custody transfers once; mixed-case assembly is a new case cell pointing back via typed `SemanticRelation` |
| `tessera.pallet` | LINEAR | Pallet split into cases = new pallet cell consuming the old |
| `tessera.shipment` | LINEAR | Closed once destination receives |
| `tessera.care-event` | AFFINE | Many logger readings accumulate against one shipment; one cell per reading |
| `tessera.scan-event` | RELEVANT | Must exist for the Care Score view to render; never destroyed |
| `tessera.tamper-event` | LINEAR | Single transition `intact → broken`; LINEAR enforcement prevents reverting patches per K1 |
| `tessera.tasting-note` | DEBUG | Read-only, opaque to FSMs and capability flow |

Cell alignment per `docs/textbook/34-cell-alignment.md`: every cell is 1024 B — four to an LMDB page, ~64 to a BRC-124 UDP frame, one SHA-256 = one BSV anchor unit. The consumer's NFC tap verifies the bottle cell via SPV proof in under 100ms. The over-determination chapter exists for exactly this scan flow.

### 3.4 Lexicon — `cartridges/tessera/brain/src/lexicon.ts` (re-export from `core/semantos-sir/src/lexicons.ts`)

The lexicon is substrate (U8 in the unification matrix); the cartridge re-exports its own — same pattern as `extensions/oddjobz/src/lexicon.ts`. Categories track speech acts, not cells (per the trades / jural / calendar / brap convention).

Categories: `harvest`, `ferment`, `rack`, `blend`, `addition`, `bottle`, `label`, `custody-transfer`, `care-event`, `excursion`, `tamper-event`, `scan`, `tasting-note`.

Canon registration in `docs/canon/lexicons.yml`:

```yaml
  - id: tessera
    status: built
    lean_file: proofs/lean/Semantos/Lexicons/Tessera.lean
    ts_file: core/semantos-sir/src/lexicons.ts
    extension_re_export: cartridges/tessera/brain/src/lexicon.ts
    description: |
      Care-chain provenance vocabulary for the tessera cartridge.
      Speech acts trace a physical object's journey from origin
      through composition (blend, assemble-case), custody transfers,
      environmental events (care-event, excursion), and consumer
      interaction (scan, tasting-note). Used by any vertical where
      the value of a delivered object depends on its handling history
      — wine, spirits, premium coffee, cold-chain pharma, art transit.
    categories:
      - harvest
      - ferment
      - rack
      - blend
      - addition
      - bottle
      - label
      - custody-transfer
      - care-event
      - excursion
      - tamper-event
      - scan
      - tasting-note
    obligations:
      - obligation: headerInjective
        status: pending
        lean_ref: "Semantos.Lexicons.tesseraHeader_injective"
```

### 3.5 Release config — `cartridges/tessera/brain/release.config.ts`

Declares the dual-artifact build for the repo-wide release pipeline at `tools/release/`, mirroring `extensions/bsv-anchor-bundle/release.config.ts`. Ships both the TypeScript surface (capability declarations, lexicon re-export, AnchorAdapter / NetworkAdapter consumer wiring) and the Zig surface (FSM walkers, StorageAdapter-consumer stores, WASM module). Build step:

```
cd cartridges/tessera && bun run build
cd cartridges/tessera/zig && zig build
```

Skeleton:

```ts
const config: ReleaseConfig = {
  name: 'tessera',
  room: 'release.extension.tessera',
  hat: 'tessera-maintainer@semantos',
  version: pkg.version,
  description:
    'Care-chain provenance cartridge — Phase 36A operational/FSM cartridge consuming Storage/Identity/Anchor/Network adapters.',
  artifacts: [
    { name: 'main.js',         target: 'browser-esm',         path: 'dist/index.js' },
    { name: 'tessera.wasm',    target: 'wasm32-freestanding', path: 'zig/zig-out/bin/tessera.wasm' },
  ],
  dependencies: [
    // Pin core/protocol-types release stateHash here after each tessera release
    // so adapter-interface compatibility is explicit in the signed cell chain.
    // Optional: pin bsv-anchor-bundle stateHash if a deployment requires the
    // BSV AnchorAdapter impl rather than the stub.
  ],
};
```

Releases land in the substrate's cell-relay versioning room. Tessera is NOT in the `D-Distro-default-install` bundle — that bundle is reserved for substrate-exposing cartridges (identity/hat-setup, peer-pair, status-dashboard, minimal-talk). Tessera is a domain cartridge; it installs separately via the `semantos` CLI (Phase 26G) once a deployment elects it.

### 3.6 (Not used in v1) WASM module

Not needed. Care-score computation is a walker; HRR similarity is the substrate's intent reducer (no new pass); blend conservation is a Lean theorem evaluated at patch time, not at hot path. Defer WASM until a future tessera vertical needs in-host execution beyond walker scope.

---

## 4. Hats — same field app, surface filtered per capability entity

One `cartridges/tessera/` cartridge. Seven hats. One Flutter binary. One sovereign brain. Per `BRAIN-FIELD-APP-DB-PIPELINE.md` §"For other hats (the pattern)", tessera is the worked instance of "supply chain" the doc names as a future hat — universal layers (LMDB, Pask graph, NATS JetStream streams, capability UTXOs) are unchanged; the hat-specific surface is filtered views scoped by domain flag.

| Hat | Domain sub-page | Field-app surfaces | Walkers granted | Stream subscription | Pask interest |
|---|---|---|---|---|---|
| `tessera.producer` | 01 | Vineyard map, harvest entry, blending bench, bottling line, batch dashboard | harvest, rack, blend, bottle, assemble-case, transfer-custody (outbound) | `op.<pkh16>.tessera.*` filtered to producer's cert_id | "which blends correlate with high consumer ratings" |
| `tessera.field-worker` | 01a | In-vineyard offline-first — block, row, brix-at-pick, harvest tonnage | harvest only | today's blocks for this producer | none (operational, no learning surface) |
| `tessera.distributor` | 02 | Receiving dock, temp-logger sync, custody log, mixed-case assembly, outbound dispatch | record-care-event (ingest), assemble-case, transfer-custody | inbound + outbound custody | "which producers ship clean; which carriers hurt cargo" |
| `tessera.dock-handler` | 02a | Single-screen scan-and-confirm: tap pallet → manifest → tap logger → file exception | record-care-event, transfer-custody (limited), thermo-flag | inbound only, this distributor | "which dock shifts have the most excursions" |
| `tessera.retailer` | 03 | Inventory verification, digital wine-list export, by-the-glass tamper check | transfer-custody, consumer-scan (proxy) | events for this retailer's stock | "which products move when Care Score visible" |
| `tessera.club-member` | 04 | Allocation queue, my cellar, scan history, tasting journal, Care Score timeline | consumer-scan, add-tasting-note, confirm-receipt, report-quality-issue | events for bottles in member's allocation | "what this member rates highly → ranks future allocations" |
| `tessera.consumer` | 05 | NFC tap PWA — Care Score, story, vineyard, winemaker note. No login, no field-app install. | consumer-scan (read-only) | none (one-shot SPV verify) | none (no Pask state for anonymous taps) |

Hat switching is exactly W1.5 (merged). Switching from `tessera.producer` to `tessera.club-member` triggers SQLite view reload + NATS resubscription, no app restart. The capability UTXOs the operator holds change with the hat; the brain enforces K3 domain isolation across hats (no cross-hat data leakage, W0.6 acceptance).

The brain tracks all hats simultaneously. Per W0.6: "the brain serves cells from any registered extension domain flag simultaneously." A solo producer who is also a Provenance Club founder wears two hats out of the same brain; an enterprise distributor with dock staff issues sub-certs whose hats land in the same brain.

---

## 5. Deliverables — V0 through V5

Each deliverable lands as one PR via the wave-tessera commission. IDs are stable; reference them in commits, PRs, and matrix updates.

### V0 — Cartridge skeleton + canon registration

V0 splits into a **pre-loader cohort** (can land before DLO.1; tessera not yet runtime-loadable but the cartridge skeleton exists, manifest declares the contract, canon entries are live) and a **post-loader cohort** (blocks on DLO.1; runtime wire-in).

**Pre-loader cohort** (parallel after V0.1):

- **V0.1 — Domain flag page allocation.** Allocate `tessera` page (2 bytes under `0x0001xxxx`). Hat sub-pages 01–05 plus 01a, 02a. Lands as a `core/constants/constants.json` entry; codegen flows to TS and Zig. Adds CI gate `tests/gates/no-tessera-in-brain-core.test.ts` per §0.1 discipline (initially passes vacuously). No dependencies.
- **V0.2 — Cartridge scaffold (`cartridge new tessera`).** Run `tools/cartridge-scaffold/bin/cartridge new tessera` to generate the canonical directory layout (§3). Lands `cartridges/tessera/cartridge.json` (Phase 36A `ExtensionManifest`), `cartridges/tessera/brain/release.config.ts` (dual-artifact release pipeline), `package.json`, `tsconfig.json`, `README.md`, empty `src/` and `zig/` subdirectories. Acceptance: cartridge appears in `/api/v1/info` discovery as DESIGN-status; manifest validates against the Phase 36A meta-schema. Depends on V0.1.
- **V0.4 — Lexicon canon registration.** Tessera lexicon enters `docs/canon/lexicons.yml`, `core/semantos-sir/src/lexicons.ts` (added to `ALL_LEXICONS`), and `proofs/lean/Semantos/Lexicons/Tessera.lean` (with `tesseraHeader_injective` obligation initially marked `pending`). The TS-side re-export lands at `cartridges/tessera/brain/src/lexicon.ts`. Depends on V0.2.
- **V0.6 — Zig project scaffold.** `cartridges/tessera/brain/zig/build.zig` + `build.zig.zon` + skeleton `src/tessera_walkers.zig` (walker-registration entry point, no walkers wired yet) + skeleton FSM stubs. Build passes (zero functional code, conformance test passes). Depends on V0.2. Acceptance: `cd cartridges/tessera/zig && zig build` succeeds; produced WASM exports the canonical walker-registration symbol.

**Post-loader cohort** (blocks on DLO.1 landing in main):

- **V0.3 — Walker registration.** Twelve walkers register via `verb_dispatcher.zig` at brain boot with `extensionId="tessera"`. Mirrors `oddjobz_ratify_walker.zig`'s registration pattern. Depends on V0.2 + V0.6 + **DLO.1 (generic cartridge loader)**. Acceptance: `verb.dispatch` with method `tessera.<verb>` reaches the walker; audit-log `module` field shows `tessera`.
- **V0.5 — Cell-type octave registration.** Nine cell types with linearity class register into the octave registry at brain boot. Stores consume `StorageAdapter` (not LMDB directly — see §0.1 discipline #2). Lands the CI gate `tests/gates/tessera-adapter-consumption.test.ts` from §0.1. Depends on V0.1 + V0.6 + **DLO.1**. Acceptance: brain refuses LINEAR cell respend; AFFINE accepts partial spend; RELEVANT requires use; DEBUG accepts without FSM effect; adapter-consumption gate passes.

### V1 — Field-app hat surfaces

- **V1.1 — Producer hat surfaces** (vineyard map, harvest entry, blending bench, bottling line, batch dashboard). Depends on W1.5 (merged) + V0.5.
- **V1.2 — Distributor hat surfaces** (receiving dock, temp-logger sync, custody log, mixed-case assembly, outbound dispatch). Depends on V1.1 patterns.
- **V1.3 — Dock-handler hat** — single-screen scan flow optimised for warehouse use. NFC tap pallet → manifest renders → tap logger → care events post → file exception. Depends on V1.2.
- **V1.4 — Retailer hat surfaces** (inventory verification, digital wine-list export, by-the-glass tamper check). Depends on V1.2 patterns.
- **V1.5 — Club-member hat surfaces** (allocation queue, my cellar, scan history, tasting journal, Care Score timeline). Depends on V1.1 patterns.
- **V1.6 — Consumer NFC-tap PWA** — separate from the field app, ambient `tessera.consumer` hat, no login. Loads Care Score + story without install. Per `SHELL-CARTRIDGES-HATS.md` §4 cartridge discovery. Acceptance: tap-to-page in <2s; SPV proof verifies; no install required.
- **V1.7 — Field-worker offline-first surface** — SQLite outbox carries harvest cells until reconnect. Depends on W1.2 (merged) + V0.5.

### V2 — Postgres hat views

The universal hat-view scaffold W2.1 is already merged. Tessera adds its hat-specific views on top.

- **V2.1 — `tessera_bottle_list(p_cert_id)`** via `hat_cell_list('\x000104', ...)` per W2.1 pattern. Depends on W2.1 (merged). Acceptance: returns owned bottles; <1s refresh on representative dataset.
- **V2.2 — `tessera_care_score(p_cell_id)`** view — joins care-event AFFINE chain, computes score per the Lean theorem `tesseraCareScore_monotonic`. Depends on V0.5 + V5.3. Acceptance: identical score for identical event sequence; deterministic.
- **V2.3 — `tessera_consumer_story_view(p_bottle_cell_id)`** — denormalised for fast NFC-tap render. Depends on V2.1 + V2.2. Acceptance: <100ms render budget; no joins at render time.
- **V2.4 — `tessera_allocation_queue(p_member_cert_id)`** for club-member hat. Depends on V2.1. Acceptance: respects capability UTXO; shows next allocation only.
- **V2.5 — `tessera_active_inventory(p_distributor_cert_id)`** — analogue of `oddjobz_active_jobs` for tessera. Depends on V2.1. Acceptance: Pask-ranked active custody.

### V3 — Event-stream tier (NATS JetStream)

Tessera publishes to `op.<pkh16>.tessera.<event>` per `ODDJOBZ-HOSTED-OPERATOR-STANDUP.md` §2 + W7.3. Per the `SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md` 2026-05-14 substitution note, exactly-once is not free; handler-level idempotency keys and dedupe windows are mandatory.

- **V3.1 — Walker → NATS producer wiring.** `nats_event_producer.zig` `attachNatsProducer` hooks into each tessera walker. Seven event kinds: `bottle_minted`, `care_event_recorded`, `custody_transferred`, `tamper_broken`, `consumer_scanned`, `case_assembled`, `shipment_closed`. JetStream stream config: file-backed, 30-day retention, 10K msgs/subject cap (the W7.3 default). Idempotency key = cell_id (the 1024-byte SHA-256 anchor); dedupe window ≥ 2 min. Depends on W7.3 (merged) + V0.3. Acceptance: every walker that emits a cell transition publishes to the right subject; redelivered care-event with same cell_id is no-op at the brain.
- **V3.2 — Durable pull consumers per hat.** Field-app subscribes via brain's WSS `/api/v1/events` bridge (the W1.4 path). Brain-side consumer ack drives stream progress. Hat scope is a subject-suffix filter. Depends on W1.4 (merged) + V3.1. Acceptance: dock-handler hat sees only `op.<pkh16>.tessera.care_event_recorded` and `op.<pkh16>.tessera.tamper_broken` filtered to operator's inbound shipments; club-member hat sees only events on bottles in their allocation.
- **V3.3 — Orphan detection.** `nats_orphan_detector.zig` for tessera subjects — care-events with no parent shipment cell, tamper events with no parent bottle cell, custody transfers with no parent case cell. Depends on V3.1. Acceptance: orphan cells surfaced to operator's Helm context; not silently dropped.

### V4 — Hardware peer integration (the substrate-novel work)

This is the only area where tessera introduces shape not present in oddjobz, but it slots into existing `extensions/dispatch/` and `extensions/chain-broadcast/` per `ADAPTER-TAXONOMY.md` — not into substrate.

- **V4.1 — NFC tag bootstrap.** Each NTAG 213-TT chip's UID derives a BCA via `core/protocol-types/src/bca.ts` (D-A0, merged). The producer's authority cert binds the tag BCA to a bottle cell at bottling-time walker call. Depends on D-A0 + V0.5. Acceptance: tag scan returns BCA-verified bottle cell; SPV check passes.
- **V4.2 — Temp-logger sync handler.** Logger acts as a peer (BLE→NFC sync at dock). Its data uploads become AFFINE `tessera.care-event` cells with logger BCA as author. Dock-handler hat dispatches via `verb.dispatch`. Depends on V4.1 + V0.3. Acceptance: 4,000-reading CAEN qLog burst uploads as N care-event cells; chain replayable.
- **V4.3 — Tamper-loop event ingestion.** Any NFC scan that reports `tamper_loop = broken` posts a `tessera.tamper-event` cell via the consumer-scan walker (called from anonymous PWA or member's field-app). LINEAR enforcement on the bottle cell prevents subsequent "intact" patches per K1. Depends on V4.1. Acceptance: once tamper lands, K1 rejects any patch reverting bottle tamper field.
- **V4.4 — Thermochromic sticker manual flag.** No software peer; cartridge grammar declares a manual `tessera.thermo-flag` walker exposed in dock-handler hat. Depends on V0.3. Acceptance: sticker-flagged events visible in distributor's care log.

### V5 — Federation across operators + Lean theorems

- **V5.1 — Cross-operator federation wiring.** Producer brain → distributor brain → retailer brain via Phase-26D NetworkAdapter; cells ride as `SignedBundle<TesseraPatch>` over Phase-35B WSS. Dispatch envelope routes by `payload_type`. Depends on existing Phase-26D/35B infrastructure (per `ADAPTER-TAXONOMY.md` A3 correction — shipped). Acceptance: end-to-end test: producer bottles → custody transfers to distributor → distributor's brain receives the bottle cell with full `prevTxid` chain.
- **V5.2 — Lean theorem `tessera.tamper_one_shot`.** Once `tamper_loop = broken`, no patch sequence yields `intact`. Provable by case analysis from K1 LINEAR. Lands in `proofs/lean/Semantos/Lexicons/Tessera/TamperOneShot.lean`.
- **V5.3 — Lean theorem `tessera.care_score_monotonic`.** Score sequence is non-increasing as care-events arrive. New theorem; lands in `proofs/lean/Semantos/Lexicons/Tessera/CareScoreMonotonic.lean`. Acceptance: V2.2 view computes score in a manner provably consistent with the theorem.
- **V5.4 — Lean theorem `tessera.blend_conservation`.** At any blend transition, `Σ input.amount = Σ output.amount`. Maps to proposed K15 (capability-UTXO conservation) per `PROOF-COVERAGE.md`. Lands in `proofs/lean/Semantos/Lexicons/Tessera/BlendConservation.lean`. Acceptance: the `tessera.blend` walker is verified against this theorem at PR time.
- **V5.5 — Lean theorem `tessera.custody_linear`.** A case cell can have at most one open custodian at any time. Provable from K1 LINEAR. Lands in `proofs/lean/Semantos/Lexicons/Tessera/CustodyLinear.lean`.
- **V5.6 — Lean theorem `tessera.scan_evidence_present`.** A bottle's Care Score view requires ≥1 scan-event in its chain. Provable from K1 RELEVANT.
- **V5.7 — `tesseraHeader_injective` ritual obligation.** Per-lexicon obligation; analogue of `tradesHeader_injective`. Lands in `proofs/lean/Semantos/Lexicons/Tessera.lean`. Status in `docs/canon/lexicons.yml` moves from `pending` to `proven`.

---

## 6. Unification matrix update

Tessera adds one row to §2b (Adapters) of `docs/prd/UNIFICATION-ROADMAP.md` and one row to `docs/canon/unification-matrix.yml`. All ten axis cells need disposition.

| Adapter ↓ / Axis → | A. Identity | B. Storage | C. Transport | D-sub | D-lex | D-form | D-cap | E. Time | F. Recovery | G. Metering |
|---|---|---|---|---|---|---|---|---|---|---|
| **A9 Tessera** | ⚠ D-A-tess | ⚠ D-B-tess | ⚠ D-C-tess | ✓ (via U1) | ⚠ D-Dlex-tess | ⚠ D-Dform-tess | ⚠ D-Dcap-tess | ✓ | ⚠ D-F-tess | ⚠ D-G-tess |

Most cells are ⚠ rather than ✗ because the substrate already provides the mechanism — tessera's job is to consume it through the cartridge contract via the four Phase-26 adapter interfaces:

- **D-A-tess** (Identity) — every actor in the tessera flow (producer, distributor, retailer, club-member, consumer, dock-handler, field-worker, hardware peer) carries a BRC-52 cert. All identity operations go through `IdentityAdapter` (`core/protocol-types/src/identity.ts`); the production impl is `LocalIdentityAdapter`. Producers, distributors, retailers register through normal operator onboarding; hardware peers (NFC tags, temp loggers) derive BCAs from chip UIDs and bind under the producer's authority cert via `IdentityAdapter`. ✓ when V4.1 + V4.2 land.
- **D-B-tess** (Storage) — nine cell types with linearity classes; stores consume `StorageAdapter` (`core/protocol-types/src/storage.ts`); brain-core provides an LMDB-backed `StorageAdapter` impl that tessera consumes through the interface (greenfield discipline §0.1 #2). ✓ when V0.5 lands.
- **D-C-tess** (Transport) — `SignedBundle<TesseraPatch>` published via `NetworkAdapter` (`core/protocol-types/src/network.ts`); production impl is `bsv-overlay-network-adapter` plus `runtime/ws-node-adapter/` and `runtime/peer-locator/` per `ADAPTER-TAXONOMY.md` A3 correction. Cross-operator hops cross governance domains transparently — tessera is unaware of Phase-35A vs Phase-35B mechanics; that's adapter-impl detail. ✓ when V5.1 lands.
- **D-Dsub-tess** — ✓ already, via U1's K1 LINEAR/AFFINE/RELEVANT/DEBUG enforcement at the cell engine.
- **D-Dlex-tess** — new lexicon registers at V0.4. ✓ when V0.4 + V5.7 land (`tesseraHeader_injective` obligation proven).
- **D-Dform-tess** — five Lean theorems (V5.2–V5.6) plus ritual obligation (V5.7). ✓ when all six land.
- **D-Dcap-tess** — capabilities `cap.tessera.{harvest, rack, blend-declare, bottle, assemble, custody, care-record, scan}` minted by extension authority cert per `docs/SHELL-CARTRIDGES-HATS.md` §4 + the BRC-108 capability domain. First-boot mint runs via the generic loader (DLO.1) per the resolved decision — every cartridge's declared capabilities mint into the operator-root cert at first boot, not just oddjobz's. ✓ when V0.3 + V0.5 + V5.1 land.
- **E** (Time) — ✓ already, via the universal monotonic hash chain on every cell.
- **D-F-tess** (Recovery) — `AnchorAdapter` provides the SPV-verifiable anchor unit; per-producer / per-distributor BRC-69 edge-backup recipes follow the existing pattern. Nothing tessera-specific to author beyond V0.4. ✓ when the universal recovery pattern is exercised end-to-end for tessera cells (no separate deliverable; passive ✓ on substrate F).
- **D-G-tess** (Metering) — per-consumer-scan MFP tick; per-care-event MFP tick. Deliverable lands as a routine MFP channel attachment on the relevant walkers (V0.3 prerequisite). ✓ when channels are live in V3 acceptance environment.

### Adapter taxonomy row addition

Per `docs/ADAPTER-TAXONOMY.md` §2:

| Adapter | Location | Status | Summary | What's missing |
|---|---|---|---|---|
| `cartridges/tessera/` | `cartridges/tessera/` | DESIGN | Cartridge for grape-to-glass-shaped care-chain traceability. Producer + distributor + retailer + club-member + consumer + dock-handler + field-worker hats over the same brain and the same field app. | Entire cartridge unbuilt. V0–V5 deliverables. |

Joins the per-adapter status row alongside `extensions/oddjobz/`, `extensions/calendar/`, `extensions/dispatch/`, `extensions/scada/`. Cartridge home is operational/FSM per §7a — not a world-app.

---

## 7. Three kernels — where each shows up

The textbook's claim (`docs/textbook/35-three-kernels.md`, D-Doc-three-kernels) is that "cells + 2PDA + intent" frames Semantos as one kernel when it is three. Tessera makes all three load-bearing:

- **2PDA** (`core/cell-engine/`) — every blend / bottle / care-event / custody-transfer cell hits K1; bounded termination via K5 means Care Score computation has a deterministic upper bound on cost; K4 atomicity means a multi-step blend either commits whole or rolls back. This is what makes "the Care Score is reproducible" actually true.
- **Pask** (`core/pask/`) — "which producers ship clean," "which distributors take care of cargo," "which products this member tends to rate highly" surface as stable threads via `pask_stable_thread`. The per-device snapshot (`SqlitePaskSnapshotStore`, W1.3 merged) gives the field-app a portable learning record. The Provenance Club's empirical Care-Score-vs-rating dataset is exactly Pask edge weights crystallising into stable threads.
- **HRR** (`core/hrr/`) — consumer "find me something like this" reduces to similarity in the HRR space the brain already maintains. The intent reducer's existing ten trivium/quadrivium passes cover this once the lexicon is registered; no new pass.

HRR/GA coexistence per memory note `semantos_hrr_design_decisions.md` — tessera consumes whatever the substrate decides; takes no position.

---

## 8. Federation across operators

Per `docs/textbook/36-federation-transport.md` (D-Doc-fed), tessera is a clean application of the four-layer federation story alongside oddjobz. Each operator in the chain runs a sovereign node with its own brain. Critically — per the §0.1 greenfield discipline — tessera does NOT consume Phase-26D, Phase-35A, or Phase-35B directly; it publishes through `NetworkAdapter` (`core/protocol-types/src/network.ts`) and the adapter impl chooses the right wire.

| Adapter / layer | Tessera traffic |
|---|---|
| `NetworkAdapter` (Phase 26D) | The interface tessera codes against. Cartridge publishes `SignedBundle<TesseraPatch>` payloads through it. Substrate decides the wire. |
| `bsv-overlay-network-adapter` (production impl) | Production federation across operators. Routes cells via the BSV overlay network using the running adapter implementation. |
| `runtime/ws-node-adapter/` + `runtime/peer-locator/` (Phase-35B WSS) | What the production NetworkAdapter impl uses for cross-internet hops. Tessera is unaware of this detail. |
| `runtime/session-protocol/src/adapters/multicast-adapter.ts` (Phase-35A) | What the production NetworkAdapter impl uses for intra-operator multicast. Tessera is unaware of this detail. |
| `extensions/dispatch/` semantic envelope | Routes tessera cells by `payload_type` to the right accept-handler on each operator's brain. Tessera registers its `payload_type` table at boot. |
| `stub-network` (test impl) | Unit-test substitution for NetworkAdapter; tessera's wave-tessera test gates use this. |

Sibling layer (not federation): the operator-internal NATS event spine. Per `docs/textbook/36-federation-transport.md` §36.7, the NATS bridge is the operator's; subjects scoped to `op.<pkh16>.*`. The tessera cartridge publishes to `op.<pkh16>.tessera.<event>` on this local stream — that is intra-operator, distinct from cross-operator federation. Tessera consumes NATS through the brain's `nats_event_producer.zig` via the standard `attachNatsProducer` pattern (per `ODDJOBZ-HOSTED-OPERATOR-STANDUP.md` W7.3) — this is a brain-internal API, not an adapter interface, because it's local-only.

---

## 9. Open-question resolutions (versus the source PRD)

The source wine-traceability PRD (the seed document this cartridge implements) raised fourteen open questions. The substrate already answers seven:

| Source PRD §16 question | Substrate answer |
|---|---|
| Q1 build vs. partner on hardware | Partner. Hardware is an adapter peer (V4.x); substrate is substrate. |
| Q2 when to anchor to blockchain | Already: BSV via Plexus, day one. SPV proof is the consumer scan. |
| Q4 international data sovereignty | Per-operator sovereign nodes. Each brain owns its tenant's data. Federation across brains; no data pooling. |
| Q6 integration with Vivino / CellarTracker | They become consumers of the consumer-scan PWA. Substrate publishes the SPV-verifiable cell; anyone reads. |
| Q9 Care Score calibration | Lean-proven monotonicity (V5.3). Per-lexicon calibration data lives in Pask stable threads. |
| Q11 distributor pushback on transparency | Substrate does not anonymise. K3 domain isolation gives the distributor full visibility of their own data; what propagates downstream is exactly what the capability UTXO discloses. |
| Q12 BRC-107 / BRC-108 ecosystem maturity | Moot — `U4` already runs BRC-108; BRC-107 conservation is the same shape; subsumed under the existing capability domain. |

Genuinely open (commercial / regulatory / operational, not substrate-blocked):

- Q3 wine-club licensing (jurisdictional)
- Q5 secondary-market support
- Q7 producer pricing sensitivity
- Q10 last-mile DTC loggers
- Q13 insurance / warranty products
- Q14 seasonal shipping recommendations

These remain commercial decisions; tessera neither resolves them nor depends on them.

---

## 10. Critical path

```
EXTERNAL DEPENDENCY: DLO.1 (generic cartridge loader) — required before V0.3, V0.5, V3, V4 can land
                     Phase 26A–H — ✓ shipped (four adapter interfaces, brain installer, extension rename)
                     Phase 36A   — ✓ shipped (ExtensionManifest meta-schema)

Pre-loader cohort (parallel after V0.1, can land before DLO.1):

V0.1 (domain flag + no-tessera-in-brain-core gate)
  ├─► V0.2 (cartridge scaffold via `cartridge new tessera` — manifest.json + release.config.ts)
  │     ├─► V0.4 (lexicon canon registration)
  │     ├─► V0.6 (Zig project scaffold — build.zig + walker entry stub)
  │     └─► V5.2–V5.7 (Lean theorems + ritual obligation) — parallel after V0.4

Post-loader cohort (blocks on DLO.1):

DLO.1 ──► V0.3 (walker registration via verb_dispatcher with extensionId="tessera")
         └─► V0.5 (cell-type octave registration + StorageAdapter consumption + adapter-consumption CI gate)
                │
                ▼
         V3.1 (NATS producer wiring on tessera walkers)
                ├─► V3.2 (durable consumers per hat)
                └─► V3.3 (orphan detection)
                │
                ▼
         V4.1 (NFC tag bootstrap via IdentityAdapter)
                ├─► V4.2 (temp logger sync — care-event cells)
                ├─► V4.3 (tamper-loop ingest — K1 LINEAR enforcement)
                └─► V4.4 (thermo sticker manual flag)
                │
                ▼
         V1.1 producer ──┬─► V1.2 distributor ──┬─► V1.3 dock-handler
                         │                      └─► V1.4 retailer
                         ├─► V1.5 club-member ──► V1.6 consumer PWA
                         └─► V1.7 field-worker
                │
                ▼
         V2.1 (bottle list) ──┬─► V2.2 (care score, blocks on V5.3 theorem)
                              ├─► V2.3 (consumer story view)
                              ├─► V2.4 (allocation queue)
                              └─► V2.5 (active inventory)
                │
                ▼
         V5.1 (cross-operator federation via NetworkAdapter)
```

Sequential prerequisites:
1. V0.1 (domain flag + CI gate) — first
2. V0.2 (cartridge scaffold) — depends on V0.1
3. V0.4 + V0.6 + V5.2–V5.7 — parallel after V0.2 (pre-loader cohort)
4. **DLO.1 must land in main** before post-loader cohort dispatches
5. V0.3 + V0.5 — depend on DLO.1
6. Everything downstream parallelises per hat / per concern

If DLO.1 lands during the pre-loader phase, the post-loader cohort starts immediately. The pre-loader cohort generates ~12 useful PRs of work (canon entries, theorems, manifest skeleton, lexicon registration) that ship value before runtime wire-in.

---

## 11. Acceptance — what "tessera v1 lands" means

The tessera cartridge v1 is complete when:

1. `cartridges/tessera/` is one self-contained directory; nothing in `core/`, `runtime/`, `apps/`, or other `extensions/` is touched except for the standard cartridge-boot registrations (constants page, lexicon canon).
2. **`grep -r "tessera" runtime/semantos-brain/src/` returns zero matches** — the §0.1 greenfield discipline holds end-to-end. CI gate `tests/gates/no-tessera-in-brain-core.test.ts` is green.
3. **Tessera consumes only the four Phase-26 adapter interfaces** from `core/protocol-types/` (StorageAdapter, IdentityAdapter, AnchorAdapter, NetworkAdapter). CI gate `tests/gates/tessera-adapter-consumption.test.ts` is green — no direct LMDB / BSV / session-protocol imports anywhere in `cartridges/tessera/`.
4. The matrix row A9 Tessera shows ✓ on D-sub, E, and is ≥ ⚠ on all other axes per §6.
5. Seven hats render distinct surfaces in the field app off the same brain, with no cross-hat data leakage (K3 domain isolation acceptance per W0.6).
6. The consumer NFC-tap PWA renders Care Score + story in <2 s with SPV verification of the bottle cell via `AnchorAdapter`.
7. Cross-operator federation has been exercised end-to-end (V5.1 acceptance): a bottle's `prevTxid` chain spans producer → distributor → retailer brains via `NetworkAdapter`.
8. All five Lean theorems (V5.2–V5.6) and the ritual obligation (V5.7) are proven; `docs/canon/lexicons.yml` shows `status: proven` for `tesseraHeader_injective`.
9. NATS subject convention is `op.<pkh16>.tessera.<event>` for all seven event kinds; idempotency via cell_id; redelivered events are no-op.
10. The unification matrix and deliverables YAML are updated with one entry per V-row; `docs/canon/unification-matrix.yml` reflects A9 Tessera status.
11. **First-boot capability mint via the generic loader** — operator-root cert gains the tessera-declared capabilities from `cartridges/tessera/cartridge.json` per Phase 36A schema, through the DLO.1 loader (not through hardcoded brain-core paths).
12. **Cartridge install/uninstall via `semantos` CLI** — `semantos vertical install tessera` and `semantos vertical uninstall tessera` work end-to-end against a Phase 26G-installed brain.
13. A worked-example pilot (e.g., Provenance Club DTC + one distributor partner) operates against the deployed cartridge with at least one cross-operator hop.
14. A second tessera vertical can be added (e.g., cold-chain pharma) by adding a new brand surface in V1.x and a new `cap.tessera.*` set, without touching `cartridges/tessera/` substrate code.

---

## 12. Document maintenance

This plan is the source of truth for the tessera cartridge. Update status in-place. New V-rows get IDs `V<section>.<next>` continuing the sequence.

Companion docs: `docs/canon/commissions/wave-tessera.md` (the parallel-agent commission to actually land V0–V5), the source wine-traceability PRD (the seed), `docs/prd/BRAIN-FIELD-APP-DB-PIPELINE.md` (the universal field-app pattern this instantiates).
