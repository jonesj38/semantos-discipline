---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/D-LIFT-ODDJOBZ.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.712788+00:00
---

# D-Lift-oddjobz — Carve oddjobz brain-core code into the `cartridges/oddjobz/` cartridge

> **⚠ PATHS SUPERSEDED BY CC4 (note added 2026-05-19, `docs/cc5-7-impl-specs`).**
> CC4 (canonical-cartridge directory collapse) deleted `extensions/oddjobz/`. **Every
> `extensions/oddjobz/...` reference in this PRD reads as `cartridges/oddjobz/...`.** Verified
> current structure on `origin/main`: `cartridges/oddjobz/cartridge.json` (the canonical
> manifest — *not* `manifest.json`), `cartridges/oddjobz/brain/{src,zig,tools,tests,public}`.
> Specific reconciliations, authoritative over the body below:
> - **DECISION-1** ("Zig subdir = `extensions/oddjobz/zig/`") → **`cartridges/oddjobz/brain/zig/`**.
>   Per `CANONICAL-CARTRIDGE-MODEL.md` §2 the canonical home is `cartridges/<id>/` with a
>   dedicated **`brain/`** part; the lifted Zig is the `brain/` part, not a top-level `zig/`.
>   (`cartridges/oddjobz/brain/zig/` already exists structurally.)
> - **DECISION-2** ("generalize `extensions.zig` to read `<data_dir>/extensions/<id>/manifest.json`")
>   → the runtime enumeration is the **installed-cartridge registry** concern (DLO.1c /
>   `enumerateUserInstalled`), reading installed cartridges' `cartridge.json`. Repo path
>   `cartridges/oddjobz/` ≠ runtime `<data_dir>` install path — keep them distinct when scoping.
> - **C7 (ratified 2026-05-18):** oddjobz's Brain part is `brain.surface: 'cells'` (declarative
>   discourse surface — keeps taxonomy/flows/prompts). The lift does not change its surface kind.
> - **CC6 coordination (canonical-schema-spine wave):** D-LIFT *and* CC6 both touch
>   `provision_tenant.zig` (step 7, extension-bundle copy) and the loader/provisioning path.
>   Sequence so they do not both rewrite that file concurrently — coordinate before DLO scoping;
>   D-LIFT remains a *separate* lift, not a CC5–CC7 fallout.
>
> This note defuses the path landmine authoritatively; the 29 inline `extensions/oddjobz/`
> mentions are intentionally left unedited (re-pathing the body is the D-LIFT owner's task and
> would collide with in-flight edits — the rule above governs).

**Version**: 0.2 (decisions resolved 2026-05-16; Deliverables section authoring in flight)
**Date**: 2026-05-15 (initial draft); 2026-05-16 (decisions resolved)
**Status**: Decisions resolved — ready for DLO.1+ implementation scoping
**Duration**: ~3-4 weeks (initial estimate; refine after deliverables section is scoped)
**Prerequisites**:
- Phase 36A complete (Extension Grammar JSON Schema — `PHASE-36A-ERRATA.md` 2026-04-12)
- Phase 36D complete (Extension Governance Model — three-tier hierarchy with consumer bindings)
- Phase 26G complete (Node Packaging — installer that loads cartridges)
- BRAIN-DISPATCHER-UNIFICATION Phase 0 complete (`dispatcher.zig` keystone) + `verb_dispatcher.zig` walker registry
- D-O8 (`tenant_manifest.zig`) + D-O10 (`provision_tenant.zig`) shipped — multi-tenant provisioning
- `extensions/oddjobz/` cartridge already exists with TypeScript-side code (manifest, lexicon, capabilities, ratification queue, state-machines, cell-types, conversation, prompts, tests, tools)

**Master document**: [`docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md`](../CARTRIDGE-DISTRO-GAP-ANALYSIS.md) §6.1 + §10.3
**Companion PRD**: [`docs/prd/D-LIFT-BSV-ANCHOR.md`](D-LIFT-BSV-ANCHOR.md) (separate carve for wallet/headers/payment)
**Related sweep**: [`docs/prd/PHASE-29.5-KERNEL-ENFORCEMENT-SWEEP.md`](PHASE-29.5-KERNEL-ENFORCEMENT-SWEEP.md) is the design reference for the kernel-enforcement substrate (TS prototype shipped at `packages/policy-runtime/` for CDM/SCADA; per Todd 2026-05-25 those are prototypes, not load-bearing). The brain's Zig analogue (`runtime/semantos-brain/src/policy_runtime.zig`, to-build per [UNIFICATION-ROADMAP.md §11.10](UNIFICATION-ROADMAP.md) order 2b) is what the lifted `intent_cells_handler` calls through; the order 2c task in that program does the call-site swap. This carve and the Zig PolicyRuntime seam are orthogonal — either can land first. Gap A prelude (extract `verifyCertHatBinding` from `intent_cells_handler.zig` into `identity_certs.zig`) ✓ shipped 2026-05-25 (PR #637).
**Branch prefix**: `lift/oddjobz`

---

## Context

`extensions/oddjobz/` already exists as a TypeScript-side cartridge with ~90 source files — manifest, lexicon, capabilities, ratification queue, intake handler, state-machines, cell-types, conversation, prompts, tests. By every Phase 36A measure (grammar declared, capabilities scoped, cell types defined), it is the **exemplar operational cartridge**.

But oddjobz's *runtime* lives in two halves:

- **TypeScript half** at `extensions/oddjobz/src/` — capability declarations, manifest schema, intake parsing, lexicon contributions, ratification orchestration
- **Zig half** baked into `runtime/semantos-brain/src/` — 30+ files implementing the on-brain FSMs, LMDB-backed stores, JSON-RPC resource handlers, broker-subscriber bridges, ratify walkers, and REPL subcommands that *are* oddjobz at runtime

The Zig half lives in brain-core for historical reasons (it was built before the cartridge contract was formalized; before `verb_dispatcher.zig` was the walker boundary; before `extensions.zig`'s registry was generalized beyond a hardcoded oddjobz mint pass). Today it's the largest single contributor to the "fresh brain ships with cartridge-shaped code in its kernel" problem flagged in `CARTRIDGE-DISTRO-GAP-ANALYSIS.md` §6.1.

This PRD scopes the lift of the Zig half into the existing cartridge.

### Why this matters

1. **The distro pattern needs it.** A brain spun up from `scripts/install.sh` (Phase 26G) without any cartridges loaded should still compile, boot, register the four substrate primitives, and expose `dispatcher.dispatch` over the Unix-socket transport — but currently it ships with `jobs.transition`, `quotes.draft`, `invoices.send`, `customers.import`, etc. as if oddjobz were substrate. Removing the oddjobz files **is the cleanest demonstration** that brain-core is substrate, not product.
2. **The cartridge contract needs the pressure test.** `extensions.zig:18-27` explicitly says it is NOT yet an extension loader for arbitrary user-installed extensions ("hardcoded — only oddjobz lives here"). Lifting oddjobz out forces brain to grow the general-purpose extension loader Phase 36 designed. The cartridge that's already wired through `verb_dispatcher.zig` walker registration (via `oddjobz_ratify_walker.zig`'s register-at-boot pattern) is the natural first migration.
3. **The audit log gets cleaner.** Today every JSON-RPC method oddjobz exposes (`jobs.transition`, `quotes.draft`, etc.) is a top-level resource registered directly with `dispatcher.zig` from brain-core code. After the lift, every oddjobz verb routes through `verb.dispatch` with `extensionId=oddjobz`. The audit log gains structural traceability — every oddjobz action is identifiable as cartridge-originated, not brain-originated, with the same uniform shape every other cartridge will use.
4. **Companion to D-Lift-bsv-anchor.** Both PRDs cleave the brain along the same architectural line (substrate vs cartridge). Doing oddjobz first is the lower-risk carve (no chain-specific dependencies, no anchor primitives entangled with brain's own anchoring needs). It pressure-tests the lift pattern that D-Lift-bsv-anchor and D-Lift-wsite both depend on.

### What this PRD covers

Move the following files out of `runtime/semantos-brain/src/` into `extensions/oddjobz/` (subdirectory TBD — DECISION-PENDING-1):

**Oddjobz domain logic in brain (6 files):**
- `runtime/semantos-brain/src/oddjobz_attention_handler.zig`
- `runtime/semantos-brain/src/oddjobz_derivations.zig`
- `runtime/semantos-brain/src/oddjobz_event_bus.zig`
- `runtime/semantos-brain/src/oddjobz_query_handler.zig`
- `runtime/semantos-brain/src/oddjobz_ratify_handler.zig`
- `runtime/semantos-brain/src/oddjobz_ratify_walker.zig`

**REPL subcommand (1 file):**
- `runtime/semantos-brain/src/repl/oddjobz_cmds.zig`

**Oddjobz-specific broker subscriber (1 file, 808 LOC):**
- `runtime/semantos-brain/src/intent_action_router.zig` — bridges `intent_cell.created` events → `jobs.transition` calls. Explicitly oddjobz-specific despite the generic-sounding name (per its own header doc).

**FSMs (4 files):**
- `runtime/semantos-brain/src/job_fsm.zig`
- `runtime/semantos-brain/src/quote_fsm.zig`
- `runtime/semantos-brain/src/invoice_fsm.zig`
- `runtime/semantos-brain/src/visit_fsm.zig`

**Domain entity stores (12 files):**
- `runtime/semantos-brain/src/customers_store_fs.zig`, `customers_store_lmdb.zig`
- `runtime/semantos-brain/src/jobs_store_fs.zig`, `jobs_store_lmdb.zig`, `jobs_store_lmdb_entity.zig`
- `runtime/semantos-brain/src/quotes_store_fs.zig`, `quotes_store_lmdb.zig`
- `runtime/semantos-brain/src/invoices_store_fs.zig`, `invoices_store_lmdb.zig`
- `runtime/semantos-brain/src/leads_store_lmdb.zig`
- `runtime/semantos-brain/src/visits_store_fs.zig`, `visits_store_lmdb.zig`

**Resource handlers (6 files):**
- `runtime/semantos-brain/src/resources/jobs_handler.zig`
- `runtime/semantos-brain/src/resources/quotes_handler.zig`
- `runtime/semantos-brain/src/resources/invoices_handler.zig`
- `runtime/semantos-brain/src/resources/customers_handler.zig`
- `runtime/semantos-brain/src/resources/leads_handler.zig`
- `runtime/semantos-brain/src/resources/visits_handler.zig`

**Hardcoded oddjobz manifest registry (carved-and-generalized, 1 file):**
- `runtime/semantos-brain/src/extensions.zig` — currently hardcoded to oddjobz per its own §"IS NOT" comment. This file does NOT move; instead it gets **generalized** to read manifests from `<data_dir>/extensions/<id>/manifest.json` (the future-D-W1 Phase work the file already names). The hardcoded oddjobz manifest moves into the cartridge.

Total: ~30 brain-core files lifted into the cartridge + 1 brain-core file generalized.

### What this PRD does NOT cover

- **The TypeScript half of `extensions/oddjobz/`.** Already exists; cartridge contract already declared via Phase 36A grammar. No carve needed.
- **`bearer_tokens.zig`, `identity_certs.zig`, `hat_*.zig`, `device_pair*.zig`.** Substrate primitives; not oddjobz-specific. Stay in brain-core.
- **LMDB substrate** (`lmdb/cell_store.zig`, `lmdb/composite_write.zig`, `lmdb/drift_detector.zig`, `lmdb/lmdb.zig`, `lmdb/lmdb_config.zig`, `lmdb/registry_cache.zig`). Generic primitive used by every cartridge that owns LMDB-backed state. Stays in brain-core.
- **`dispatcher.zig`, `verb_dispatcher.zig`, `module_loader.zig`, `instance_manager.zig`, `broker.zig`, `helm_event_broker.zig`.** Substrate. Stay.
- **`attachments_*.zig`.** Generic blob storage primitive used by multiple cartridges (oddjobz + voice-capture + chat). Stays substrate.
- **`pask_*.zig` + `lmdb/pask_snapshot_store*.zig`.** Pask hosting + interaction production. Substrate-shaped per `docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md` §6 judgment-call list. Stays for now; revisit if Pask-as-substrate vs Pask-cartridge ever becomes a separate question.
- **Wallet, headers, payment, refund, output store.** Those are `D-Lift-bsv-anchor` — a separate PRD with its own DECISION-PENDING items.
- **Operator-site (WSITE1-5.5).** Those are `D-Lift-wsite` — separate PRD.

### Brain-core's behavior after carve

Brain-core retains:
- `extensions.zig` **generalized** to read user-installed manifests (the future-D-W1 work). Loading no extensions is a valid configuration — brain starts with zero cartridges.
- The dispatcher seam unchanged. Every oddjobz verb that previously routed through a hardcoded resource handler now routes through `verb.dispatch` with `extensionId=oddjobz`.
- The audit log unchanged in shape. Audit entries gain a `cartridge_id` field naturally (the existing audit-log entry shape per `audit_log.zig` already includes `module` — that's where the cartridge id lands).
- No oddjobz-specific code paths. `grep -r "oddjobz" runtime/semantos-brain/src/` returns zero matches after the lift.

DECISION-PENDING-1 (cartridge subdirectory for Zig code): the existing `extensions/oddjobz/` is TypeScript-shaped (`src/` is .ts, `tsconfig.json` etc.). Where does the lifted Zig code land? Options:
- (a) `extensions/oddjobz/zig/` — sibling to `src/`, parallel to scaffold conventions
- (b) `extensions/oddjobz/src-zig/` — sibling to `src/`, name pattern signals Zig source
- (c) `extensions/oddjobz-brain/` — separate sibling package, parallels the `jam-room` + `jam-room-mobile` split (separate packages, same cartridge identity)
- (d) `extensions/oddjobz/runtime/` — the Zig brain-side is "runtime", parallel to repo-level `runtime/` semantics

Recommendation: (a) `extensions/oddjobz/zig/`. Keeps one cartridge = one package. Lets the cartridge's `release.config.ts` declare both TS and Zig artifacts. The Phase 36A grammar lives at `extensions/oddjobz/manifest.json` (top-level), unifying both halves under one declared cartridge. Surface to Todd for final call.

DECISION-PENDING-2 (extensions.zig generalization scope): does this PRD generalize `extensions.zig` to a full user-installed extension loader (the future-D-W1 scope per its own header), or just enough to load oddjobz from `extensions/oddjobz/manifest.json` instead of hardcoding? Options:
- (a) Full D-W1: read every `<data_dir>/extensions/<id>/manifest.json` at boot, support enable/disable per tenant, support extension delivery + revocation per BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md
- (b) Minimum-viable: read one hardcoded path (`extensions/oddjobz/manifest.json`) as if it were the only manifest, defer the full loader to a follow-up

Recommendation: (a) — the cartridge contract is shipped (Phase 36A) and the governance model is shipped (Phase 36D), so the loader is the only piece missing for arbitrary cartridge loading. Doing the minimum-viable carve buys little and creates a second migration. But (a) widens the scope of this PRD substantially. Surface to Todd.

DECISION-PENDING-3 (the LMDB store boundary): `customers_store_lmdb.zig` etc. use the brain-core LMDB substrate (`lmdb/cell_store.zig`, `lmdb/composite_write.zig`). When the stores move into the cartridge, do they:
- (a) Import the LMDB substrate as a Zig dependency declared in the cartridge's `build.zig.zon` (brain-core exports the LMDB modules as a public Zig package)
- (b) Get re-implemented over a generic `CellStore` interface that brain-core exposes (the StorageAdapter pattern from Phase 26 applied at the cartridge boundary)
- (c) Stay in brain-core as "storage adapter implementations" while the FSMs + handlers move (storage backends are substrate-shaped per existing rationale; the FSMs that use them are cartridge-shaped)

Recommendation: (b) — long-term it's the right architectural fit (cartridges consume StorageAdapter, don't reach into LMDB primitives). Short-term it's the most work. (c) is the fastest path but bleeds the cartridge boundary. (a) is intermediate but creates a Zig-package-from-brain-core publishing burden. Surface to Todd.

---

## Source Files / References

### Brain-core files to carve OUT (the ~30 files)

| Alias | Path | Role | Lift gate |
|---|---|---|---|
| `ODJ:ATTN` | `runtime/semantos-brain/src/oddjobz_attention_handler.zig` | Attention-feed handler — ranks unresolved oddjobz cells | Cartridge-owned; registers via verb_dispatcher under `oddjobz.attention` |
| `ODJ:DERIV` | `runtime/semantos-brain/src/oddjobz_derivations.zig` | BRC-42 derivation paths for oddjobz cell types | Cartridge-owned; consumes IdentityAdapter interface for derivation |
| `ODJ:EVENT` | `runtime/semantos-brain/src/oddjobz_event_bus.zig` | Oddjobz-internal event bus (separate from helm_event_broker) | Cartridge-owned; if cartridges need event-bus primitives, brain exposes helm_event_broker as substrate API and this collapses into it |
| `ODJ:QUERY` | `runtime/semantos-brain/src/oddjobz_query_handler.zig` | Read-side query handler (job lookup, customer search, etc.) | Cartridge-owned; registers under `oddjobz.query.*` verbs |
| `ODJ:RATIFY-H` | `runtime/semantos-brain/src/oddjobz_ratify_handler.zig` | Ratification handler — turns proposals into committed cells | Cartridge-owned; existing walker pattern (`oddjobz_ratify_walker.zig`) already registers via verb_dispatcher |
| `ODJ:RATIFY-W` | `runtime/semantos-brain/src/oddjobz_ratify_walker.zig` | Walker registration entry-point | Cartridge-owned; the canonical example of the walker pattern verb_dispatcher.zig was designed around |
| `ODJ:REPL` | `runtime/semantos-brain/src/repl/oddjobz_cmds.zig` | `brain repl` oddjobz subcommands | Cartridge-owned; REPL gains a cartridge-cmd registration shape so cartridges can contribute REPL commands |
| `INTENT:ROUTER` | `runtime/semantos-brain/src/intent_action_router.zig` (808 LOC) | Broker subscriber bridging `intent_cell.created` → `jobs.transition` | Cartridge-owned; the broker primitive itself stays substrate, the oddjobz-specific subscriber moves |
| `FSM:JOB` | `runtime/semantos-brain/src/job_fsm.zig` | Job state machine (lead → open → quoted → scheduled → done) | Cartridge-owned |
| `FSM:QUOTE` | `runtime/semantos-brain/src/quote_fsm.zig` | Quote state machine | Cartridge-owned |
| `FSM:INVOICE` | `runtime/semantos-brain/src/invoice_fsm.zig` | Invoice state machine | Cartridge-owned |
| `FSM:VISIT` | `runtime/semantos-brain/src/visit_fsm.zig` | Visit state machine | Cartridge-owned |
| `STORE:CUSTOMERS-FS` / `STORE:CUSTOMERS-LMDB` | `customers_store_{fs,lmdb}.zig` | Customer entity store | Cartridge-owned; LMDB boundary per DECISION-PENDING-3 |
| `STORE:JOBS-FS` / `STORE:JOBS-LMDB` / `STORE:JOBS-LMDB-ENT` | `jobs_store_{fs,lmdb,lmdb_entity}.zig` | Job entity store | Cartridge-owned |
| `STORE:QUOTES-FS` / `STORE:QUOTES-LMDB` | `quotes_store_{fs,lmdb}.zig` | Quote entity store | Cartridge-owned |
| `STORE:INVOICES-FS` / `STORE:INVOICES-LMDB` | `invoices_store_{fs,lmdb}.zig` | Invoice entity store | Cartridge-owned |
| `STORE:LEADS-LMDB` | `leads_store_lmdb.zig` | Lead entity store (lmdb-only — no FS variant exists) | Cartridge-owned |
| `STORE:VISITS-FS` / `STORE:VISITS-LMDB` | `visits_store_{fs,lmdb}.zig` | Visit entity store | Cartridge-owned |
| `HND:JOBS` | `runtime/semantos-brain/src/resources/jobs_handler.zig` | JSON-RPC handler for `jobs.*` verbs | Cartridge-owned; routes via verb_dispatcher walker registration |
| `HND:QUOTES` | `resources/quotes_handler.zig` | JSON-RPC handler for `quotes.*` | Cartridge-owned |
| `HND:INVOICES` | `resources/invoices_handler.zig` | JSON-RPC handler for `invoices.*` | Cartridge-owned |
| `HND:CUSTOMERS` | `resources/customers_handler.zig` | JSON-RPC handler for `customers.*` | Cartridge-owned |
| `HND:LEADS` | `resources/leads_handler.zig` | JSON-RPC handler for `leads.*` | Cartridge-owned |
| `HND:VISITS` | `resources/visits_handler.zig` | JSON-RPC handler for `visits.*` | Cartridge-owned |

### Brain-core file to GENERALIZE (not move)

| Path | What changes |
|---|---|
| `runtime/semantos-brain/src/extensions.zig` | Currently hardcoded oddjobz registry per its own §"IS NOT" comment. Generalize per the future-D-W1 scope it names: read manifests from `<data_dir>/extensions/<id>/manifest.json` at boot. Loading no extensions becomes a valid configuration. The hardcoded oddjobz capability declarations move into `extensions/oddjobz/manifest.json` per Phase 36A schema. See DECISION-PENDING-2 for scope. |

### Brain-core files that STAY (substrate)

| Path | Why it stays |
|---|---|
| `dispatcher.zig`, `verb_dispatcher.zig`, `payload_type_router.zig`, `broker.zig`, `helm_event_broker.zig`, `event_loop.zig` | Dispatcher + event-bus substrate |
| `module_loader.zig`, `instance_manager.zig`, `runner.zig`, `wasmtime_runner_*.zig`, `manifest_registry.zig` | Provisioner substrate |
| `bearer_tokens.zig`, `identity_certs.zig`, `hat_*.zig`, `device_pair*.zig`, `wrapped_dek_store.zig`, `wss_operator_auth.zig` | Identity/capability substrate |
| `slot_store_fs.zig`, `state_store_fs.zig`, `lmdb/{cell_store,cell_store_lmdb,composite_write,drift_detector,lmdb,lmdb_config,registry_cache,registry_cache_lmdb}.zig` | Storage substrate |
| `attachments_blob_fs.zig`, `attachments_store_{fs,lmdb}.zig`, `attachments_blob_http.zig`, `attachments_upload_http.zig`, `resources/attachments_handler.zig` | Generic blob substrate (consumed by oddjobz + voice + chat) |
| `pask_*.zig`, `lmdb/pask_snapshot_store*.zig`, `stable_thread_anchor.zig` | Pask hosting substrate |
| `tenant_manifest.zig`, `provision_tenant.zig` | Tenant provisioning substrate (D-O8 / D-O10) |
| `federation/*`, `udp_protocol.zig`, `p2p_wire.zig`, `wire.zig`, `transport/*`, `wss_codec.zig`, `wss_frame_parser.zig` | Peer/transport substrate |
| `audit_log.zig` | Audit substrate |
| `cell_registry.zig`, `cell_query_handler.zig`, `entity_cell.zig`, `action_cell_teachback.zig`, `intent_cells_store_{fs,lmdb}.zig`, `resources/intent_cells_handler.zig`, `intent_cell_lmdb_store.zig` | Cell/intent substrate (universal currency, used by every cartridge) |

### Architectural references

| Alias | Path | What to read |
|---|---|---|
| `GAP-ANALYSIS` | `docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md` | §6.1 oddjobz code in brain core; §10.3 the new deliverable IDs |
| `CLEAN-CONTRACT` | `docs/SHELL-CARTRIDGES-HATS.md` §4 | The five-part cartridge contract |
| `EXEMPLAR-TS` | `extensions/oddjobz/src/` | Existing TS half of oddjobz — manifest.ts, capabilities.ts, lexicon.ts, ratification-queue.ts, state-machines/, cell-types/ |
| `ODDJOBZ-PLAN` | `docs/design/ODDJOBZ-EXTENSION-PLAN.md` | Original extension plan with §11 canonical tenant.toml and the D-O*/D-W* deliverable IDs |
| `DISPATCHER-UNIFICATION` | `docs/design/BRAIN-DISPATCHER-UNIFICATION.md` + `runtime/semantos-brain/src/dispatcher.zig` | Auth-gated capability-checked dispatcher contract — every cartridge verb gates here |
| `WALKER-PATTERN` | `runtime/semantos-brain/src/verb_dispatcher.zig` | Generic walker registry — the cartridge code boundary in code |
| `EXTENSION-DELIVERY` | `docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md` | Extension delivery + revocation model (relevant to DECISION-PENDING-2) |
| `EXTENSIONS-HARDCODE` | `runtime/semantos-brain/src/extensions.zig` (header §"IS NOT") | Self-described limitation that this PRD removes |
| `PHASE-36A-ERRATA` | `docs/prd/PHASE-36A-ERRATA.md` | The cartridge contract that oddjobz already conforms to (TypeScript half) |
| `PHASE-36D-ERRATA` | `docs/prd/PHASE-36D-ERRATA.md` | Governance model — three-tier hierarchy is the consumer-binding shape after carve |
| `PHASE-26G` | `docs/prd/PHASE-26G-NODE-PACKAGING.md` | PRD format reference; also the installer that loads cartridges |
| `BSV-ANCHOR-COMPANION` | `docs/prd/D-LIFT-BSV-ANCHOR.md` | Sibling carve PRD; same lift pattern, different file set |
| `CARTRIDGE-SCAFFOLD` | `tools/cartridge-scaffold/README.md` | `cartridge new <name>` scaffold generator |

### Deliverables

#### DLO.1 — Generic cartridge loader (`extensions.zig` → full D-W1 user-installed loader)

The keystone deliverable. Every other DLO depends on this. Per DECISION-2: full D-W1 generalization, not minimum-viable. Sub-tree into three sub-deliverables that can land independently.

##### DLO.1a — Manifest reader + validator

**Files**:
- New: `runtime/semantos-brain/src/extension_manifest_loader.zig` — reads `<data_dir>/extensions/<id>/manifest.json` for every directory entry in `<data_dir>/extensions/`; deserializes against the Phase 36A grammar JSON schema; validates that declared capabilities are well-formed and don't collide across cartridges.
- Modified: `runtime/semantos-brain/src/extensions.zig` — the hardcoded oddjobz manifest is removed; the file becomes a thin wrapper around `extension_manifest_loader.zig` that exposes `loadAll() -> []ExtensionManifest` for boot-time consumption.
- New: `runtime/semantos-brain/src/__tests__/extension_manifest_loader_test.zig` — covers: valid manifest loads, malformed JSON rejected, schema violations rejected, capability collisions detected across two manifests, empty `<data_dir>/extensions/` directory (zero cartridges) is a valid configuration.

**Acceptance gate**: Brain boots with `<data_dir>/extensions/` containing zero subdirectories — no error, no warning, audit log records "loaded 0 extensions". Brain boots with `<data_dir>/extensions/oddjobz/manifest.json` present — manifest loads, validates, audit log records "loaded 1 extension: oddjobz".

**Effort**: 1 week.
**Deps**: Phase 36A grammar schema (shipped); `core/protocol-types/src/extension-grammar.ts` for the validator contract.

##### DLO.1b — Capability mint pass generalization

**Files**:
- Modified: `runtime/semantos-brain/src/extensions.zig` — `mintFirstBootCapabilities()` is rewritten from the hardcoded oddjobz pass into a loop over `loadAll()`. For each loaded `ExtensionManifest`, mint its declared capabilities into the operator-root cert via `identity_certs.issue_root`. Preserve the §O3 acceptance-gate citation pattern from the existing file's header.
- Modified: `runtime/semantos-brain/src/__tests__/extensions_test.zig` — the existing TS↔Zig parity test (which iterates this Zig list against `extensions/oddjobz/src/capabilities.ts`'s serialized wire form) becomes a parity test against every loaded cartridge's `extensions/<id>/src/capabilities.ts` (or wherever the cartridge declares them per its own manifest path).

**Acceptance gate**: First-boot capability mint runs against every loaded cartridge. With oddjobz loaded, the operator-root cert gains exactly the capabilities declared in `extensions/oddjobz/manifest.json`. With a second cartridge loaded (test fixture), the operator-root cert gains both sets, with capability-collision detection running first.

**Effort**: 3 days.
**Deps**: DLO.1a.

##### DLO.1c — Extension delivery + revocation + quarantine integration

**Files**:
- Modified: `runtime/semantos-brain/src/extension_publish.zig` + `extension_publish_stub.zig` — the existing publish-side wiring (per `extensions/<id>` directory observers) is generalized to handle any cartridge, not just oddjobz-shaped ones.
- Modified: `runtime/semantos-brain/src/extension_subscriber.zig` — generic signed-bundle ingestion for cartridge updates per BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md.
- Modified: `runtime/semantos-brain/src/extension_nullifier.zig` + `_stub.zig` — revocation handling is generalized; the existing per-extension nullifier list per BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md §D-W2 Phase 2 becomes the canonical revocation surface.
- Modified: `runtime/semantos-brain/src/extension_quarantine.zig` — quarantine state machine (per `dispatcher.zig`'s `handler_quarantined` DispatchError variant) extends to any cartridge; on quarantine, all the cartridge's verbs return `handler_quarantined` until operator un-quarantines.

**Acceptance gate**: Operator publishes an updated `oddjobz` manifest; subscriber receives the signed bundle, validates the signature against the manifest's declared maintainer hat, and atomically swaps the manifest. Operator revokes a cartridge; the nullifier observes the revocation, the loader unloads the cartridge, all of its registered verbs return `handler_quarantined`. Operator un-revokes; cartridge re-loads.

**Effort**: 2 weeks.
**Deps**: DLO.1a, DLO.1b, `docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md`, dispatcher Phase 0 (already shipped).

DLO.1 total: ~3.5 weeks. Lands DLO.1a/b/c as separate commits on `lift/oddjobz/dlo-1a`, `lift/oddjobz/dlo-1b`, `lift/oddjobz/dlo-1c` — squash-merge each into `lift/oddjobz` after gate tests pass.

#### DLO.2 through DLO.6 + TDD Gate

Remaining deliverables to be authored in subsequent /loop iterations. Iteration plan:

1. ✅ Header + Context + Source Files/References (iter 1, commit d47c623)
2. ✅ What NOT to Do + Completion Criteria templates (iter 3, commit a784252)
3. ✅ Decisions resolved (commit 9758d29)
4. ✅ DLO.1 keystone deliverable (this iteration)
5. Next: DLO.2 (cartridge subdirectory layout — `extensions/oddjobz/zig/` Zig project scaffold)
6. Then: DLO.3 (per-store StorageAdapter migration — jobs first; quotes/invoices/customers/leads/visits follow)
7. Then: DLO.4 (resource handler carve + walker registration via verb_dispatcher.zig)
8. Then: DLO.5 (REPL contributions + intent-action-router lift)
9. Then: DLO.6 (brain-core no-oddjobz audit — `grep -r "oddjobz" runtime/semantos-brain/src/` returns zero)
10. Then: TDD Gate (T1–T15+) with one test per acceptance gate above
11. Refine Completion Criteria checklist with full test references

---

## Resolved decisions (2026-05-16)

All three DECISION-PENDING items resolved with the originally-recommended option per Todd 2026-05-16 ("all recommended").

- **DECISION-1 — Zig subdirectory layout: `extensions/oddjobz/zig/`** ✓ resolved.
  Sibling to existing `src/` (TypeScript). Keeps one cartridge = one package. The cartridge's `release.config.ts` declares both TS and Zig artifacts. The Phase 36A grammar lives at `extensions/oddjobz/manifest.json` (top-level), unifying both halves under one declared cartridge.
  Implementation gate: `extensions/oddjobz/zig/build.zig` + `build.zig.zon` ship alongside the existing `src/tsconfig.json`. Both halves are buildable independently; both ship as artifacts in the cartridge release.

- **DECISION-2 — `extensions.zig` generalization scope: full D-W1 user-installed loader** ✓ resolved.
  Generalize per the future-D-W1 scope `extensions.zig` already names in its header. Read manifests from `<data_dir>/extensions/<id>/manifest.json` at boot, support enable/disable per tenant, support extension delivery + revocation per `docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md`. Loading no extensions is a valid configuration — brain starts with zero cartridges. Phase 36A cartridge contract is shipped + Phase 36D governance is shipped, so the loader is the only missing piece for arbitrary cartridge loading.
  Implementation gate: `extensions.zig` rewritten as a generic loader; the hardcoded oddjobz capability declarations move to `extensions/oddjobz/manifest.json` and are read at brain boot like any other cartridge's manifest. The §O3 acceptance-gate first-boot capability-mint pass runs against every loaded cartridge's declared capabilities, not just oddjobz. This is a substantial chunk of work — DLO.1 scopes the full loader as a sub-tree of deliverables (DLO.1a/b/c sub-items in the next iteration).

- **DECISION-3 — LMDB store boundary: cartridge consumes StorageAdapter** ✓ resolved.
  Cartridge stores (customers, jobs, quotes, invoices, leads, visits) are reimplemented over the `StorageAdapter` interface (Phase 26 — `core/protocol-types/src/storage.ts`). The LMDB primitives in `runtime/semantos-brain/src/lmdb/` (cell_store, composite_write, drift_detector, lmdb, lmdb_config, registry_cache) stay in brain-core as substrate; brain-core provides an LMDB-backed `StorageAdapter` implementation that the cartridge consumes.
  Implementation gate: each lifted `*_store_lmdb.zig` file is rewritten to take a `StorageAdapter` constructor parameter instead of opening LMDB directly. The cartridge's manifest declares its required `StorageAdapter` capability; the loader wires brain-core's LMDB-backed adapter when the cartridge boots. This is the largest single-file refactor in the carve; rather than try to migrate all six store-types at once, DLO.3 scopes a per-store migration sequence (jobs first as the simplest, then quotes/invoices/customers/leads/visits).

---

## What NOT to Do

These guardrails apply throughout the carve, regardless of which DLO deliverable lands first.

- **Don't break OJT production.** V1 is live on `ssh rbs` per memory `brain_reactor_v1_recovery_complete.md`. Every commit in this PRD must leave the running deployment functional. The carve cannot have an intermediate state where brain-core compiles but production OJT loses jobs/quotes/invoices/customers/leads/visits functionality. Acceptable: brain-core continues calling oddjobz-via-hardcoded-handler during the lift, with the cartridge-loader path enabled in parallel under a feature flag. Not acceptable: a commit that removes brain-core's hardcoded path before the cartridge-loader path is verified working.
- **Don't break the existing TS half of `extensions/oddjobz/`.** The cartridge already exists with manifest, capabilities, lexicon, ratification queue, etc. The Zig carve adds a sibling tree (location per DECISION-PENDING-1) — it doesn't restructure the TS half. Touching TS files is out of scope unless a manifest field needs an additive update to declare the Zig-side artifacts.
- **Don't lose audit-log structural traceability.** Today every oddjobz JSON-RPC verb is registered directly with `dispatcher.zig` from brain-core code; after the lift, every oddjobz verb routes through `verb.dispatch` with `extensionId=oddjobz`. The `audit_log.zig` `module` field, which already exists, is where the cartridge id lands — verify pre/post lift that this field shows `oddjobz` for cartridge-originated dispatches, not the bare resource name.
- **Don't skip walker-pattern registration.** Every lifted handler must register via `verb_dispatcher.zig` walker registration (the existing pattern in `oddjobz_ratify_walker.zig` is the canonical example). Don't re-declare any lifted handler as a top-level resource on `dispatcher.zig` — that's the pre-lift shape and bypasses the cartridge boundary.
- **Don't hardcode oddjobz in `extensions.zig` in any new form.** The whole point of DLO.1 is removing the hardcoded oddjobz pass and reading manifests from a generic location. Don't replace "hardcoded oddjobz" with "hardcoded oddjobz path" — that's the same problem with extra steps.
- **Don't break existing oddjobz Zig-side tests.** Tests in `runtime/semantos-brain/src/__tests__/` (or wherever they live today) get moved alongside their code into the cartridge's test directory. The pre-lift test count and the post-lift test count must match; no test gets dropped without explicit justification in the PRD.
- **Don't conflate LMDB substrate with cartridge-owned stores.** Per DECISION-PENDING-3, the LMDB primitives in `runtime/semantos-brain/src/lmdb/` (cell_store, composite_write, drift_detector, lmdb, lmdb_config, registry_cache) stay in brain-core. Only the *domain stores* (customers/jobs/quotes/invoices/leads/visits) move. The cartridge consumes the LMDB substrate via its preferred boundary per the DECISION-PENDING-3 resolution.
- **Don't break the ratify-walker pattern.** Other cartridges (jam-room, voice-capture, eventually wallet) will copy the `oddjobz_ratify_walker.zig` registration shape as the cartridge boilerplate. Preserving this pattern through the lift means: the registration call lives in a clearly-named entry-point file inside the cartridge, and the function signature stays compatible with `verb_dispatcher.zig`'s `WalkerFn` type.
- **Don't skip the brain-core no-oddjobz audit.** The lift completion gate is `grep -r "oddjobz" runtime/semantos-brain/src/` returns zero matches. If brain-core needs *any* oddjobz-specific identifier after the lift, that's a leak that prevents the next cartridge lift from following the same pattern. Substrate-shaped names (e.g. a verb in `verb_dispatcher.zig` for "register your cartridge") are fine; the literal string `oddjobz` must not appear in brain-core paths.
- **Don't pre-empt `D-Lift-wsite` or `D-Lift-bsv-anchor`.** Some oddjobz code paths reference site_server (for the operator dashboard) or payment_ledger (for invoice settlement). Those references stay routed through brain-core's existing handlers during this carve. After D-Lift-wsite and D-Lift-bsv-anchor land, the cartridge updates its references to consume the wsite + bsv-anchor cartridges directly — that's follow-up work, not in scope here.
- **Don't break the `extensions.zig` capability-mint pattern.** The first-boot capability mint that `extensions.zig` runs against `identity_certs.issue_root` (per its header §"Acceptance-gate citation") is the load-bearing acceptance gate for ODDJOBZ-EXTENSION-PLAN §O3. The generalization must preserve this — every user-installed cartridge's declared capabilities mint into the operator-root cert at first boot, with the same conformance test shape against TS-side `extensions/<id>/src/capabilities.ts`.

---

## Completion Criteria

Provisional checklist; full TDD-gate list (T-numbered) follows in a future iteration once DLO.1–DLO.6 deliverables are scoped.

- [ ] `extensions/oddjobz/<zig-subdir>/` (location per DECISION-PENDING-1) exists with the lifted Zig source tree
- [ ] All ~30 brain-core files listed in §Source Files moved into the cartridge; original paths return file-not-found
- [ ] `grep -r "oddjobz" runtime/semantos-brain/src/` returns zero matches
- [ ] `runtime/semantos-brain/src/extensions.zig` generalized per DECISION-PENDING-2 — reads manifests from `<data_dir>/extensions/<id>/manifest.json` (or whichever scope Todd selects)
- [ ] Brain-core compiles and boots with **zero cartridges loaded** (loading no extensions is a valid configuration)
- [ ] Brain-core compiles and boots with **oddjobz cartridge loaded** (full functionality preserved end-to-end)
- [ ] Pre-lift oddjobz_*_test.zig pass count matches post-lift pass count (no test dropped)
- [ ] First-boot capability mint pass succeeds — operator-root cert gains the oddjobz-declared capabilities from `extensions/oddjobz/manifest.json` per Phase 36A schema
- [ ] Audit log `module` field shows `oddjobz` for cartridge-originated dispatches (verify with one round-trip via `verb.dispatch`)
- [ ] OJT production deployment (`ssh rbs`) continues serving traffic through the lift
- [ ] Ratify-walker pattern preserved — `extensions/oddjobz/zig/ratify_walker.zig` (or equivalent) registers correctly via `verb_dispatcher.zig`
- [ ] Intent-action-router lifted into cartridge — typed-NL operator command still routes from phone → cell submission → brain intent_cells_handler → broker → cartridge subscriber → `jobs.transition`
- [ ] REPL `oddjobz` subcommands work as cartridge-registered REPL contributions
- [ ] `bun run check` + `bun run build` pass on the TS half of `extensions/oddjobz/`
- [ ] Zig build passes for the cartridge's Zig half
- [ ] All commits follow `lift/oddjobz/DLO.N:` naming convention
- [ ] Branch is `lift/oddjobz`
- [ ] No prior phase tests regressed (Phase 26A–H, 36A/C/D, dispatcher Phase 0 still pass)

---

## Next Phase

After D-Lift-oddjobz lands:

1. **D-Lift-bsv-anchor** — sibling carve PRD. Same lift pattern, different file set. Oddjobz being the first cartridge through this carve makes the pattern proven before tackling the more architecturally entangled BSV anchor backend.
2. **D-Lift-wsite** — operator-site / WSITE1–5.5 carve. Becomes a cartridge. Likely consumes both `oddjobz` (for operator-business data) and `bsv-anchor-bundle` (for payment + refund operations) as dependency cartridges.
3. **D-Distro-default-install** — by this point three cartridges have been carved out and the pattern is solid. The default-install bundle definition becomes concrete: substrate-only distro ships zero cartridges by default; sovereign-BSV-node distro ships `bsv-anchor-bundle` + `oddjobz` + `wsite`.
4. **D-Manifest-canonical** — once three cartridges follow the same manifest shape, picking the canonical format becomes a low-risk consolidation.
