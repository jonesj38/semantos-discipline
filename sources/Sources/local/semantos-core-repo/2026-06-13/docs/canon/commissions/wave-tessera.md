---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/commissions/wave-tessera.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.757588+00:00
---

# Wave Tessera — Cartridge Engineering Commission

**Audience:** Claude Code (orchestrator) and the parallel-agent fleet it dispatches.
**Author:** Todd Price, RBS.
**Date:** 2026-05-15 (initial); 2026-05-16 (revised against cartridge distro pattern).
**Companion to:** `docs/prd/TESSERA-CARTRIDGE.md` v0.2 (the plan this commission lands).
**Milestone:** Wave Tessera unified landing — all V-row PRs merged, matrix row A9 Tessera reflects ≥ ⚠ on every axis, first end-to-end cross-operator scan exercised.

**Hard prerequisites** (must land in `main` before the post-loader cohort of V0 dispatches):
- **DLO.1 (generic cartridge loader)** — `runtime/semantos-brain/src/extensions.zig` generalised per `docs/prd/D-LIFT-ODDJOBZ.md`. Until DLO.1 lands, the brain cannot load tessera; the pre-loader cohort can still dispatch (lexicon canon, Lean theorems, manifest skeleton — see §6 coordination rules).
- **Phase 26A–H** — ✓ shipped. Four substrate adapter interfaces in `core/protocol-types/`. Brain installer via Phase 26G.
- **Phase 36A** — ✓ shipped. Tessera's `manifest.json` validates against the meta-schema in `core/protocol-types/src/extension-manifest.ts`.
- **`verb_dispatcher.zig`** — ✓ shipped. Tessera registers walkers with `extensionId="tessera"`.

**Parallel-track commissions** (this wave coordinates with):
- `docs/prd/D-LIFT-ODDJOBZ.md` — the operational-cartridge lift PRD; DLO.1 is the keystone this wave waits on.
- `docs/prd/D-LIFT-BSV-ANCHOR.md` — the BSV-anchor lift PRD; relevant because tessera consumes `AnchorAdapter`, not bsv-anchor primitives directly.
- `docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md` — master synthesis doc; surfaces the gap that DLO.1 fills.

---

## 1. Mission

Land the `cartridges/tessera/` cartridge as a substrate-native operational/FSM experience cartridge — composing existing primitives (cell engine, capability domain, four Phase-26 adapter interfaces, federation transport, event-stream tier, recovery, lexicon authority, Lean proof layer) without modifying substrate or other extensions. When this commission completes, the field app surfaces seven tessera hats off one brain; the consumer NFC-tap PWA verifies bottle cells via SPV in under 100 ms through `AnchorAdapter`; cross-operator federation has carried a `SignedBundle<TesseraPatch>` from a producer brain to a distributor brain to a retailer brain via `NetworkAdapter`; and five Lean theorems plus the lexicon's ritual obligation are proven.

**This is a greenfield cartridge commission.** Tessera is the first substrate-native cartridge built from day one without the brain-core-baked anti-pattern that `D-Lift-oddjobz` and `D-Lift-bsv-anchor` are correcting. No PR in this wave puts tessera code in `runtime/semantos-brain/src/`. The CI gate `tests/gates/no-tessera-in-brain-core.test.ts` (landed in V0.1) enforces this for every commit.

**This is a cartridge commission, not a substrate commission.** No PR in this wave modifies `core/`, `runtime/`, `apps/`, or another extension's source. The cartridge-boot registrations a tessera PR touches outside `cartridges/tessera/` are limited to:
- `core/constants/constants.json` (domain flag page — V0.1)
- `core/semantos-sir/src/lexicons.ts` (`ALL_LEXICONS` array — V0.4)
- `docs/canon/{lexicons.yml,unification-matrix.yml,deliverables.yml,glossary.yml}`
- `proofs/lean/Semantos/Lexicons/Tessera.lean` (and sub-files for V5.2–V5.7)
- `tests/gates/*.test.ts` (the two CI gates from PRD §0.1)

Any PR touching paths outside that allowlist submits a `BLOCKED:` PR with explicit justification.

The wave splits into **two cohorts** (per PRD §10 critical path):

**Pre-loader cohort** — can dispatch immediately, before DLO.1 lands:
- V0.1 (domain flag + CI gate)
- V0.2 (cartridge scaffold: `manifest.json`, `release.config.ts`, directory layout)
- V0.4 (lexicon canon registration)
- V0.6 (Zig project scaffold)
- V5.2–V5.7 (Lean theorems + ritual obligation)

**Post-loader cohort** — blocks on DLO.1 landing:
- V0.3 (walker registration via `verb_dispatcher.zig` with `extensionId="tessera"`)
- V0.5 (cell-type octave + StorageAdapter consumption + adapter-consumption CI gate)
- V1.x (seven hat surfaces)
- V2.x (five Postgres views)
- V3.x (three NATS deliverables)
- V4.x (four hardware-peer deliverables)
- V5.1 (cross-operator federation via NetworkAdapter)

**Twenty-seven PRs total** (added V0.6 Zig scaffold to the original twenty-six).

---

## 2. Canonical inputs (read-only by every agent)

Same discipline as `docs/canon/commissions/wave-1.5.md`: every agent treats the following as source of truth.

| Doc | Path | Role |
|---|---|---|
| Cartridge plan | `docs/prd/TESSERA-CARTRIDGE.md` v0.2 | Authoritative for V-row IDs, scope, acceptance. Every agent cites this for their deliverable. |
| Cartridge distro pattern | `docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md` | Master synthesis. The convergence picture tessera fits into. The "no brain-core baked-in cartridge code" discipline tessera follows from day one. |
| DLO.1 keystone PRD | `docs/prd/D-LIFT-ODDJOBZ.md` | The generic cartridge loader tessera blocks on for the post-loader cohort. Establishes the dual-half cartridge pattern (TS + Zig under one tree) and the resolved DECISIONS (Zig subdir at `extensions/<id>/zig/`, StorageAdapter consumption, generic loader scope). |
| Companion lift PRD | `docs/prd/D-LIFT-BSV-ANCHOR.md` | Establishes how a cartridge consumes `AnchorAdapter`. Tessera's `AnchorAdapter` consumption mirrors the lifted bsv-anchor-bundle pattern. |
| Cartridge skeleton precedent | `extensions/bsv-anchor-bundle/` | Canonical cartridge directory layout: `manifest.json` (Phase 36A) + `release.config.ts` (release pipeline) + `package.json` + `src/` + `zig/`. Tessera's V0.2 mirrors this. |
| Phase 36A meta-schema | `core/protocol-types/src/extension-manifest.ts` + `PHASE-36A-ERRATA.md` | The `ExtensionManifest` shape tessera's `manifest.json` validates against. |
| Cartridge scaffold tool | `tools/cartridge-scaffold/` | `cartridge new tessera` generates V0.2's canonical layout. |
| Adapter interfaces | `core/protocol-types/src/{storage,identity,anchor,network}.ts` | The four interfaces tessera consumes. CI gate `tests/gates/tessera-adapter-consumption.test.ts` enforces this. |
| Cartridge contract | `docs/SHELL-CARTRIDGES-HATS.md` | Five-part cartridge contract; two cartridge homes; four substrate adapter interfaces. Tessera is operational/FSM-home (`extensions/`), not world-app (`apps/world-apps/`). |
| Adapter taxonomy | `docs/ADAPTER-TAXONOMY.md` | Tessera adds one row to §2; status moves DESIGN → DESIGN-in-flight → mixed-status as V-rows land. |
| Field-app pattern | `docs/prd/BRAIN-FIELD-APP-DB-PIPELINE.md` | The universal W0–W5 pattern tessera instantiates. **Note:** Pravega references in this doc are stale per the streams-tier substitution; treat as NATS JetStream. |
| Streams substitution | `docs/prd/SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md` (2026-05-14 note) | Pravega → NATS JetStream. Idempotency keys + dedupe windows mandatory. |
| NATS subjects & wiring | `docs/prd/ODDJOBZ-HOSTED-OPERATOR-STANDUP.md` §2 + W7.3 | Canonical subject form `op.<pkh16>.<hat>.<event>`; `nats_client.zig`, `nats_event_producer.zig`, `nats_event_bridge.zig`, `nats_subscriber.zig`, `nats_orphan_detector.zig`; `attachNatsProducer` pattern. |
| Cell alignment | `docs/textbook/34-cell-alignment.md` | 1024-byte cell; SHA-256 = BSV anchor unit. SPV verification budget on consumer scan. |
| Three kernels | `docs/textbook/35-three-kernels.md` | HRR + 2PDA + Pask layering. Tessera consumes all three; takes no position on HRR/GA. |
| Federation transport | `docs/textbook/36-federation-transport.md` | Four-layer story + NATS sibling. Cross-operator hops carry `SignedBundle<TesseraPatch>` through `NetworkAdapter`; tessera is unaware of Phase-35A/B mechanics. |
| Dispatcher unification | `docs/design/BRAIN-DISPATCHER-UNIFICATION.md` + `runtime/semantos-brain/src/dispatcher.zig` | The auth-gated, capability-checked, audit-logged seam every tessera verb routes through. |
| Proof coverage | `docs/PROOF-COVERAGE.md` | Proposed K15–K18 invariants; tessera Lean theorems anchor against K15 (capability-UTXO conservation) and existing K1/K3/K5. |
| Unification matrix | `docs/canon/unification-matrix.yml` | Each V-row PR that flips an A9 Tessera axis updates this YAML in the SAME PR. |
| Lexicon canon | `docs/canon/lexicons.yml` | V0.4 adds the `tessera` entry; V5.7 marks `tesseraHeader_injective` proven. |
| Deliverables registry | `docs/canon/deliverables.yml` | Each V-row PR adds an entry `{id, title, phase, status, owner, deps, pr_url}` in the SAME PR. |
| Glossary | `docs/canon/glossary.yml` | Canonical aliases. Tessera-specific terms register here once at V0.4. |
| Protocol spec | `docs/spec/protocol-v0.5.md` | Authoritative for wire formats, identity (§4), capability tokens (§5), SignedBundle (§12.1). Deviations require spec amendment first. |

Supporting reads (engineering agents may consult; doc agents work from the canonical set only):

| Doc | When to consult |
|---|---|
| `docs/design/ODDJOBZ-EXTENSION-PLAN.md` | Sibling extension; closest in-shape precedent. Walker registration pattern; manifest shape; FSM-to-capability table. |
| `extensions/oddjobz/` source | Reference implementation of every part of the cartridge contract. |
| `extensions/calendar/`, `extensions/scada/`, `extensions/dispatch/` | Other cartridge exemplars for specific patterns (calendar = hat-typed identity; scada = sensor peers; dispatch = cross-vertical envelope). |
| `core/semantos-sir/src/lexicons.ts` | Existing lexicons (trades, jural, calendar, brap). Tessera adds itself to `ALL_LEXICONS` here. |
| `proofs/lean/Semantos/Lexicons/Trades.lean` | Lexicon Lean exemplar. Tessera mirrors the `headerInjective` obligation shape. |
| `runtime/semantos-brain/src/nats_event_producer.zig` | `attachNatsProducer` reference. |
| `runtime/semantos-brain/src/verb_dispatcher.zig` | Walker registration at brain boot. |
| `runtime/semantos-brain/src/nats_orphan_detector.zig` | Orphan-event detection pattern for V3.3. |

Anything not in the canonical or supporting lists is OUT OF SCOPE for the agent's input set. Each agent's brief specifies the exact paths in scope.

---

## 3. Per-agent brief template

Every agent in this wave receives a brief in the following shape. The orchestrator generates one brief per row of the §7 manifest by filling the placeholders.

```
DELIVERABLE:     <V0.1 | V0.2 | … | V5.7>
TITLE:           <from §7>
TIER:            <V0 boot | V1 hat surface | V2 hat view | V3 event stream | V4 hardware peer | V5 federation/proof>
SEQUENCING:      <sequential — must land before <X> | parallel after <Y> lands>

CARTRIDGE DISCIPLINE (binding):
  - The deliverable touches `cartridges/tessera/` and the cartridge-boot
    registration paths (constants page, lexicon canon, octave registry,
    walker dispatch, matrix, deliverables YAML) only.
  - NO modification to `core/`, `runtime/`, `apps/`, or other `extensions/`
    source files. If the deliverable seems to require this, the agent
    submits a `BLOCKED:` PR with a specific blocker note.
  - The five-part cartridge contract (grammar, walkers, cell types,
    lexicon re-export, release config) governs structure.

CANON DISCIPLINE (binding):
  - Use only the canonical alias for every term in `docs/canon/glossary.yml`.
  - Cite K-invariants (K1–K14, proposed K15–K18) by canonical id.
  - Cite BRC standards (BRC-52, BRC-100, BRC-108, BRC-124, …) by id.
  - PR description includes a "Cartridge discipline: passed" line confirming
    only sanctioned paths are touched.
  - PR description includes a "Canon discipline: passed" line confirming
    the glossary check.

INPUTS (closed set — do not read outside this list):
  - <ordered list from §7 manifest>

WHAT TO BUILD: <verbatim from §7 manifest>

ACCEPTANCE CRITERIA (the orchestrator enforces these before merge):
  1. Implementation lands at the path(s) listed in §7.
  2. Tests for the deliverable land in the corresponding test path(s).
  3. CI gate `bun run check` passes (TS type check).
  4. CI gate `bun run build` passes.
  5. CI gate `bun test tests/gates/import-boundaries.test.ts` passes
     (architectural import boundaries; tessera imports only `core/` +
     `runtime/` + sibling cartridges via dispatch envelope).
  6. Deliverable-specific tests listed in §7 pass.
  7. If the deliverable advances a matrix cell, the YAML update lands
     in the SAME PR: `docs/canon/unification-matrix.yml` for
     A9 Tessera × <axis> moves from ✗/⚠ toward ✓.
  8. The deliverable's structured record is added in the SAME PR:
     `docs/canon/deliverables.yml` gains an entry
     `{id, title, phase: tessera, status: completed, owner, deps, pr_url}`.
  9. PR description cites the section of `docs/prd/TESSERA-CARTRIDGE.md`
     that defines this deliverable.
 10. PR description names every BLOCKED: item if any.

DELIVERABLE PR:
  base:    <main | post-V0-base for V1–V5 deliverables>
  branch:  <feat/V-XX-short-slug>
  title:   <feat(tessera/V-XX): short slug>
```

---

## 4. Voice and style constraints (binding on every agent)

Engineering agents inherit Wave 1.5's discipline plus tessera-specific guardrails:

- **Greenfield discipline (binding, per TESSERA-CARTRIDGE.md §0.1).** No tessera code lands in `runtime/semantos-brain/src/` — ever. The literal string `tessera` does not appear in any path under `runtime/semantos-brain/src/`. CI gate `tests/gates/no-tessera-in-brain-core.test.ts` (landed in V0.1) enforces this; every PR re-runs the gate. If any deliverable seems to require putting code in brain-core, the agent submits a `BLOCKED:` PR — never works around the gate.
- **Adapter-interface discipline (binding).** Tessera consumes only the four Phase-26 adapter interfaces from `core/protocol-types/`: `StorageAdapter`, `IdentityAdapter`, `AnchorAdapter`, `NetworkAdapter`. No direct imports of `@bsv/sdk`, `wallet-toolbox`, LMDB primitives, `bsv-overlay-network-adapter` internals, session-protocol multicast adapter, or any path under `runtime/semantos-brain/src/` from inside `cartridges/tessera/`. CI gate `tests/gates/tessera-adapter-consumption.test.ts` (landed in V0.5) enforces this.
- **Walker registration discipline (binding).** Every tessera verb registers via `verb_dispatcher.zig` walker registration with `extensionId="tessera"`. No top-level resource registration on `dispatcher.zig` from inside the cartridge. The walker-registration entry point mirrors `oddjobz_ratify_walker.zig`'s pattern, placed at `cartridges/tessera/brain/zig/src/tessera_walkers.zig`.
- **Manifest-format discipline (binding).** Tessera's `manifest.json` validates against the Phase 36A `ExtensionManifest` meta-schema in `core/protocol-types/src/extension-manifest.ts`. The dual-file pattern (`manifest.json` + `release.config.ts`) follows the `extensions/bsv-anchor-bundle/` precedent. If `D-Manifest-canonical` resolves to a different canonical format during this wave, tessera migrates in a follow-up PR; meanwhile the Phase 36A form is what the loader reads.
- **Code style** matches the surface being modified. TypeScript strict mode for `cartridges/tessera/brain/src/`. Zig conventions for `cartridges/tessera/brain/zig/src/`. Prettier defaults already enforced via the workspace.
- **Test discipline:** every deliverable lands with tests. New TypeScript code uses `bun test` with the existing test layout (`__tests__/` co-located with source). New Zig code uses Zig's built-in test runner with `cartridges/tessera/brain/zig/src/__tests__/`-equivalent placement.
- **Type safety:** TypeScript code MUST compile under `bun run check` with no errors. New types stay in `cartridges/tessera/brain/src/types/`; the cartridge MUST NOT add types to `core/protocol-types/` (greenfield discipline #1).
- **Import-boundary respect:** the `tests/gates/import-boundaries.test.ts` gate enforces tier rules. Tessera imports from `core/protocol-types/` (the adapter interfaces) and from sibling cartridges only through the dispatch envelope (per `docs/textbook/29-cross-vertical-dispatch-and-federation.md`). Tessera does NOT import from `runtime/` (that's where the lift PRDs are extracting cartridge code OUT of).
- **No new third-party runtime dependencies** without explicit approval.
- **No competitor naming** in code comments, PR descriptions, or documentation.
- **Conformance-first:** if a deliverable corresponds to a section of the protocol spec v0.5, it MUST conform.
- **Neutral nomenclature.** Tessera is a neutral cartridge name; the deliverables avoid wine-industry-coded terminology in code identifiers, type names, or test cases. The first commercial surface ships under its own brand (e.g., "Provenance Club"); branded language stays in the surface layer's content and out of the cartridge.

---

## 5. Glossary discipline (mandatory)

Same rules as Wave 1.5. The drift-pair auto-fail list (cell vs object, hat vs facet, capability vs permission, governance domain vs trust domain, Helm vs Loom) applies to commit messages, PR descriptions, code comments, and any documentation written as part of this commission.

Code identifiers in existing source MAY use legacy names where they are part of the established codebase and a rename is out of scope.

**New tessera-specific terms** that need canonical registration land at V0.4 (lexicon canon) and at the same time get a glossary entry. Candidates:

- `tessera` (cartridge name; technical, neutral)
- `care-event` (AFFINE cell representing one logger reading or one manual flag)
- `care-score` (Lean-proven monotonic derivation over a bottle's care-event chain)
- `tamper-loop` (the physical NFC-tag mechanism; not a substrate concept)
- `consumer scan` (the anonymous PWA flow; bound to the `tessera.consumer` hat)

---

## 6. Coordination rules

**One PR per deliverable.** No agent merges its own; the human owner reviews and merges.

**Branch naming:** `feat/V-XX-<short-slug>` (e.g., `feat/V0.1-domain-flag`, `feat/V1.3-dock-handler-hat`). Branch off `main` for V0; branch off the post-V0 base for V1–V5.

**Sequencing — two cohorts, gated by DLO.1:**

```
[Pre-loader cohort — can dispatch immediately, DOES NOT block on DLO.1]

V0.1 (domain flag + no-tessera-in-brain-core gate)  ──┐
                                                       │
                                                       ├─► merge as pre-loader base
V0.2 (cartridge scaffold — manifest.json +            │
       release.config.ts via `cartridge new tessera`) ─┤
                                                       │
V0.4 (lexicon canon)                                  ──┤
V0.6 (Zig project scaffold)                           ──┤
V5.2–V5.7 (Lean theorems + ritual obligation)         ──┘  parallel after V0.2 / V0.4

[EXTERNAL DEPENDENCY: DLO.1 must land in main before post-loader cohort dispatches]

[Post-loader cohort — blocks on DLO.1]

DLO.1 (merged in main)                                ──┐
                                                        ├─► merge as post-loader base
V0.3 (walker registration with extensionId="tessera") ──┤
V0.5 (cell-type octave + StorageAdapter +             │
      adapter-consumption gate)                       ──┘
                                ↓
                V1, V2, V3, V4, V5.1 parallel dispatch
```

The orchestrator MUST block the post-loader cohort dispatch until DLO.1 is merged in `main` AND the pre-loader cohort's V0.1, V0.2, V0.4, V0.6 are merged. Post-loader-cohort agents branch off the post-loader base, not off `main`.

**Within the pre-loader cohort:** V0.1 (domain flag + CI gate) lands first; V0.2 (cartridge scaffold) depends on V0.1; V0.4 (lexicon canon), V0.6 (Zig scaffold), V5.2–V5.7 (Lean theorems) all depend on V0.2 and can land in any order in parallel.

**Within the post-loader cohort:** V0.3 (walker registration) and V0.5 (cell-type octave + StorageAdapter) depend on DLO.1 + V0.6. After V0.3 + V0.5 merge, V1, V2, V3, V4, V5.1 fan out per the §7 sub-sequencing.

**Within V1:** seven hat surfaces — V1.1 (producer) sets the in-app surface pattern; V1.2–V1.7 mirror it for other hats. V1.1 should land first; V1.2–V1.7 parallel after.

**Within V2:** five views. V2.1 (bottle list) is foundational; V2.2 (care score) depends on V5.3 (Lean theorem) for its derivation correctness; V2.3 (consumer story) depends on V2.1 + V2.2; V2.4 + V2.5 parallel.

**Within V3:** V3.1 (producer wiring) is foundational; V3.2 (consumers) and V3.3 (orphan detection) depend on V3.1.

**Within V4:** V4.1 (NFC tag bootstrap) is foundational; V4.2, V4.3, V4.4 depend on V4.1 and can land in any order.

**Within V5:** V5.1 (federation) is independent; V5.2–V5.7 (Lean) can land in any order, parallel.

**File ownership:** each PR touches its own surface plus the matrix and deliverables YAML. Only one PR may modify the matrix or deliverables YAML per merge — handle conflicts via rebase, not by holding the merge.

**Failure handling:** an agent that cannot satisfy a deliverable submits a `BLOCKED:` PR with the specific blocker. The human owner resolves; the agent is then re-dispatched.

**Coordination with the tessera plan:** PRs in this commission MUST cite the section of `docs/prd/TESSERA-CARTRIDGE.md` that defines the deliverable. When a V-row lands first, the plan may need a touch-up to reflect the new state — this is handled in a small post-wave docs cleanup pass, not blocked here.

---

## 7. Wave Tessera manifest

Twenty-seven deliverables. Six in V0 (split pre-loader / post-loader cohorts). Twenty-one parallel after V0 + DLO.1.

### 7.1 V0 — Pre-loader cohort (dispatchable now, before DLO.1)

| ID | Title | Inputs | What to build | Tests | Matrix cell |
|---|---|---|---|---|---|
| **V0.1** | Tessera domain flag + greenfield CI gate | `docs/prd/TESSERA-CARTRIDGE.md` §0.1 + §3.3 + §4; `core/constants/constants.json`; codegen pipeline | Add `tessera` page allocation (2 bytes under `0x0001xxxx`); hat sub-pages 01–05 + 01a, 02a. Codegen flows to TS and Zig. Land CI gate `tests/gates/no-tessera-in-brain-core.test.ts` — fails if `grep -r tessera runtime/semantos-brain/src/` finds anything. | Constants conformance test (page allocation unique; sub-pages in range). Greenfield gate test (initially passes vacuously). | (no matrix cell — substrate plumbing + discipline gate) |
| **V0.2** | Tessera cartridge scaffold | `docs/prd/TESSERA-CARTRIDGE.md` §3 directory layout; `extensions/bsv-anchor-bundle/` (precedent); `tools/cartridge-scaffold/bin/cartridge`; `core/protocol-types/src/extension-manifest.ts` (Phase 36A meta-schema) | Run `cartridge new tessera`. Hand-edit produced `manifest.json` to declare the 13 verbs + 4 `consumes` entries per `docs/prd/TESSERA-CARTRIDGE.md` §3.1. Hand-edit `release.config.ts` to declare dual-artifact build per §3.5. Empty `src/` and `zig/` subdirectories (V0.4 + V0.6 populate them). | Discovery test: `/api/v1/info` includes tessera as DESIGN-status; manifest.json validates against Phase 36A meta-schema; release.config.ts parses against `tools/release/lib/ReleaseConfig`. | (no matrix cell — cartridge plumbing) |
| **V0.4** | Lexicon canon registration | `docs/prd/TESSERA-CARTRIDGE.md` §3.4; `docs/canon/lexicons.yml`; `core/semantos-sir/src/lexicons.ts`; `proofs/lean/Semantos/Lexicons/Trades.lean` (exemplar) | Add `tessera` entry to `docs/canon/lexicons.yml`. Add `TesseraLexicon` to `core/semantos-sir/src/lexicons.ts` `ALL_LEXICONS`. Create `proofs/lean/Semantos/Lexicons/Tessera.lean` skeleton with `tesseraHeader_injective` obligation marked `pending`. Add `cartridges/tessera/brain/src/lexicon.ts` re-exporting the canon type. | Lexicon registration test: `ALL_LEXICONS.includes(TesseraLexicon)`; category set matches §3.4; injectivity obligation present (pending). | A9 × D-lex → ⚠ |
| **V0.6** | Tessera Zig project scaffold | `docs/prd/TESSERA-CARTRIDGE.md` §3 directory layout; `extensions/oddjobz/zig/build.zig` (post-DLO.2 exemplar, or `extensions/bsv-anchor-bundle/zig/`) | `cartridges/tessera/brain/zig/build.zig` + `build.zig.zon` + skeleton `src/tessera_walkers.zig` (walker-registration entry point, no walkers wired) + skeleton FSM stubs. WASM build produces an artifact with the canonical walker-registration export but no functional walkers yet. | `cd cartridges/tessera/zig && zig build` passes; produced WASM exports the canonical walker-registration symbol; zig test runs (zero functional tests). | (no matrix cell — Zig plumbing) |

### 7.1.5 V0 — Post-loader cohort (blocks on DLO.1 + V0.6)

| ID | Title | Inputs | What to build | Tests | Matrix cell |
|---|---|---|---|---|---|
| **V0.3** | Walker dispatch registration | `docs/prd/TESSERA-CARTRIDGE.md` §3.2; `runtime/semantos-brain/src/verb_dispatcher.zig`; `oddjobz_ratify_walker.zig` (canonical registration pattern after DLO.1) | Twelve walker files under `cartridges/tessera/brain/src/walkers/` (TS-side) and `cartridges/tessera/brain/zig/src/tessera_walkers.zig` (Zig-side registration entry). Each registers via `verb_dispatcher.zig` at brain boot with `extensionId="tessera"`. Each has shape `(allocator, ctx, params_json) → result_json`. | Per-walker unit test: dispatch succeeds for valid params, fails with expected error for invalid params (minimum 24 tests). End-to-end: `verb.dispatch` with method `tessera.harvest` reaches the walker via DLO.1's generic loader; audit-log `module` field shows `tessera`. | A9 × D-cap → ⚠ (capability dispatch path live) |
| **V0.5** | Cell-type octave registration + StorageAdapter wiring + adapter-consumption CI gate | `docs/prd/TESSERA-CARTRIDGE.md` §3.3 + §0.1 discipline #2; the octave registry path on the brain; `core/protocol-types/src/storage.ts` | Nine cell types in `cartridges/tessera/brain/src/cell-types/*.ts` with explicit linearity classes (LINEAR / AFFINE / RELEVANT / DEBUG). typeHash computed at boot; registered into octave registry via the generic loader. Zig-side stores in `cartridges/tessera/brain/zig/src/tessera_stores/` consume `StorageAdapter` (NOT direct LMDB). Land CI gate `tests/gates/tessera-adapter-consumption.test.ts` — fails if `cartridges/tessera/` imports anything outside `@semantos/protocol-types/*` for substrate access. | Linearity conformance tests: LINEAR cell respend rejected; AFFINE partial spend accepted; RELEVANT must-use enforced; DEBUG accepted without FSM effect. Nine type-hash uniqueness tests. Adapter-consumption gate passes. | A9 × D-sub → ✓; A9 × B → ⚠ |

### 7.2 V1 — Hat surfaces (parallel after V0)

| ID | Title | Inputs | What to build | Tests | Matrix cell |
|---|---|---|---|---|---|
| **V1.1** | Producer hat surfaces | `docs/prd/TESSERA-CARTRIDGE.md` §4; `apps/oddjobz-mobile/` (or equivalent field-app source); W1.5 (merged) | Vineyard map, harvest entry, blending bench, bottling line, batch dashboard. Hat switch loads producer SQLite views; harvest walker reachable from screen. | E2E test: hat switch to `tessera.producer`; harvest entry posts a cell; cell visible in brain after round-trip. | (advances V1 hat-surface aggregate) |
| **V1.2** | Distributor hat surfaces | as V1.1; V1.1 patterns | Receiving dock, temp-logger sync, custody log, mixed-case assembly, outbound dispatch. | E2E test: receiving a temp-logger burst on the dock-handler hat creates N care-event cells; custody-transfer walker succeeds. | as V1.1 |
| **V1.3** | Dock-handler hat | V1.2 | Single-screen scan-and-confirm: tap pallet → manifest renders → tap logger → care events post → file exception. | E2E test: dock-handler completes full scan flow in <30 s wall clock on emulator. | as V1.1 |
| **V1.4** | Retailer hat surfaces | V1.2 patterns | Inventory verification, digital wine-list export, by-the-glass tamper check. | E2E test: tamper check on bottle with broken tamper-event shows correct state; inventory verification matches custody chain. | as V1.1 |
| **V1.5** | Club-member hat surfaces | V1.1 patterns | Allocation queue, my cellar, scan history, tasting journal, Care Score timeline. | E2E test: scan + add-tasting-note posts; Care Score timeline renders correctly. | as V1.1 |
| **V1.6** | Consumer NFC-tap PWA | `docs/textbook/34-cell-alignment.md` (SPV budget); separate codebase from field app; PWA framework choice (engineering judgment) | Standalone PWA, ambient `tessera.consumer` hat, no login. Loads Care Score + story without install. SPV-verifies bottle cell. | Performance test: tap-to-page in <2 s on representative mobile devices; SPV verify in <100 ms. Lighthouse PWA score ≥ 90. | A9 × A → ⚠ (anonymous identity model proven) |
| **V1.7** | Field-worker offline-first surface | V1.1 patterns; W1.2 outbox cell envelope (merged) | In-vineyard offline-first — block, row, brix-at-pick, harvest tonnage. SQLite outbox carries harvest cells until reconnect. | E2E test: offline harvest entry; reconnect drains outbox; cells reach LMDB. Round-trip integrity. | as V1.1 |

### 7.3 V2 — Postgres hat views (parallel after V0; V2.2 also waits for V5.3)

| ID | Title | Inputs | What to build | Tests | Matrix cell |
|---|---|---|---|---|---|
| **V2.1** | `tessera_bottle_list(p_cert_id)` | W2.1 (merged); `docs/prd/TESSERA-CARTRIDGE.md` §5 V2.1 | Postgres view via `hat_cell_list('\x000104', ...)` per W2.1. Returns owned bottles. | Refresh under 1 s on representative dataset; correct rows returned for known cert_id; empty result for unknown cert_id. | A9 × B → improves |
| **V2.2** | `tessera_care_score(p_cell_id)` | V0.5; V5.3 (theorem) | Joins care-event AFFINE chain, computes score per `tesseraCareScore_monotonic`. | Identical score for identical event sequence; deterministic across runs; score never increases with new event added. | (D-form acceptance) |
| **V2.3** | `tessera_consumer_story_view` | V2.1 + V2.2 | Denormalised for fast NFC-tap render. | Render budget <100 ms; no joins at render time. | (V1.6 dependency) |
| **V2.4** | `tessera_allocation_queue(p_member_cert_id)` | V2.1 | For club-member hat. | Respects capability UTXO; shows next allocation only; correct for known members. | (V1.5 dependency) |
| **V2.5** | `tessera_active_inventory(p_distributor_cert_id)` | V2.1 | Analogue of `oddjobz_active_jobs`. Pask-ranked. | Pask ranking correctness; refresh under 1 s. | (V1.2 dependency) |

### 7.4 V3 — Event-stream tier (NATS JetStream) (parallel after V0)

| ID | Title | Inputs | What to build | Tests | Matrix cell |
|---|---|---|---|---|---|
| **V3.1** | Walker → NATS producer wiring | `docs/prd/ODDJOBZ-HOSTED-OPERATOR-STANDUP.md` §2 + W7.3; `runtime/semantos-brain/src/nats_event_producer.zig`; V0.3 + V0.5 | `attachNatsProducer` hooks into each tessera walker. Seven event kinds emit to `op.<pkh16>.tessera.<event>`. JetStream stream config: file-backed, 30-day, 10K msgs/subject cap. Idempotency key = cell_id; dedupe window ≥ 2 min. | Per-event-kind test: walker emit publishes to right subject; redelivered care-event with same cell_id is no-op at brain. | A9 × C → ⚠ |
| **V3.2** | Durable pull consumers per hat | V3.1; W1.4 (merged) | Field-app subscribes via brain's WSS `/api/v1/events`. Brain-side consumer ack drives stream progress. Hat scope is subject-suffix filter. | Dock-handler sees only inbound care + tamper events; club-member sees only events for their allocation. Reconnect resumes from last-acked event. | A9 × C → improves |
| **V3.3** | Orphan detection | V3.1; `runtime/semantos-brain/src/nats_orphan_detector.zig` | Detect care-events without parent shipment cell, tamper events without parent bottle cell, custody transfers without parent case cell. | Orphan cells surfaced to operator's Helm context (not silently dropped). | (V3.1 acceptance complement) |

### 7.5 V4 — Hardware peer integration (parallel after V0)

| ID | Title | Inputs | What to build | Tests | Matrix cell |
|---|---|---|---|---|---|
| **V4.1** | NFC tag bootstrap | D-A0 (merged) `core/protocol-types/src/bca.ts`; V0.5 | Each NTAG 213-TT chip's UID derives a BCA. Producer's authority cert binds tag BCA to bottle cell at bottling-time walker call. | Tag scan returns BCA-verified bottle cell; SPV check passes; binding ritual signs correctly. | A9 × A → improves |
| **V4.2** | Temp-logger sync handler | V4.1 + V0.3 | Logger as peer (BLE→NFC at dock). Data uploads become AFFINE `tessera.care-event` cells with logger BCA as author. Dock-handler hat dispatches. | 4,000-reading CAEN qLog burst uploads as N care-event cells; chain replayable; idempotent on re-sync. | A9 × A → improves |
| **V4.3** | Tamper-loop event ingestion | V4.1 | Any NFC scan with `tamper_loop = broken` posts `tessera.tamper-event` via consumer-scan walker (from anonymous PWA or member's field-app). | Once tamper lands, K1 rejects any patch reverting bottle tamper field. End-to-end test from PWA tap to LINEAR enforcement. | A9 × D-sub acceptance complement |
| **V4.4** | Thermochromic sticker manual flag | V0.3 | Manual `tessera.thermo-flag` walker exposed in dock-handler hat. No software peer. | Sticker-flagged events visible in distributor's care log; correct attribution to dock-handler operator. | (V1.3 acceptance complement) |

### 7.6 V5 — Federation + Lean theorems (parallel after V0)

| ID | Title | Inputs | What to build | Tests | Matrix cell |
|---|---|---|---|---|---|
| **V5.1** | Cross-operator federation | `docs/textbook/36-federation-transport.md`; `ADAPTER-TAXONOMY.md` A3 correction; existing Phase-26D/35B infra | Producer brain → distributor brain → retailer brain via Phase-26D NetworkAdapter. Cells ride as `SignedBundle<TesseraPatch>` over Phase-35B WSS. Dispatch envelope routes by `payload_type`. | End-to-end: producer bottles → custody transfers to distributor → distributor's brain receives bottle cell with full `prevTxid` chain. Identity-at-each-layer table per textbook §36 satisfied. | A9 × C → ✓; A9 × A → ✓ |
| **V5.2** | Theorem `tessera.tamper_one_shot` | `proofs/lean/Semantos/Lexicons/Trades.lean` (exemplar); K1 LINEAR | Once `tamper_loop = broken`, no patch sequence yields `intact`. Provable by case analysis from K1. | Lean compiles with zero `sorry` / `admit`. Theorem provable from K1 LINEAR specialisation. | (D-form acceptance) |
| **V5.3** | Theorem `tessera.care_score_monotonic` | K1 AFFINE; care-event chain shape from V0.5 | Score sequence is non-increasing as care-events arrive. | Lean compiles with zero `sorry` / `admit`. Witness: any event sequence; corollary: V2.2 view derives consistent score. | (D-form acceptance; V2.2 dependency) |
| **V5.4** | Theorem `tessera.blend_conservation` | Proposed K15 (capability-UTXO conservation) per `PROOF-COVERAGE.md` | At any blend transition, `Σ input.amount = Σ output.amount`. | Lean compiles with zero `sorry` / `admit`. The `tessera.blend` walker verifies against this theorem at PR time. | (D-form acceptance; new K15 instantiation) |
| **V5.5** | Theorem `tessera.custody_linear` | K1 LINEAR | A case cell has at most one open custodian at any time. | Lean compiles with zero `sorry` / `admit`. | (D-form acceptance) |
| **V5.6** | Theorem `tessera.scan_evidence_present` | K1 RELEVANT | A bottle's Care Score view requires ≥1 scan-event in its chain. | Lean compiles with zero `sorry` / `admit`. V2.2 view rejects bottles with no scan-event when invoked in evidenced mode. | (D-form acceptance) |
| **V5.7** | `tesseraHeader_injective` ritual obligation | `proofs/lean/Semantos/Lexicons/Trades.lean::tradesHeader_injective` (exemplar) | Per-lexicon obligation; analogue of `tradesHeader_injective`. | Lean compiles with zero `sorry` / `admit`. `docs/canon/lexicons.yml` `tesseraHeader_injective` status moves `pending → proven`. | A9 × D-lex → ✓ |

---

## 8. Matrix updates summary

Each PR that flips a matrix cell updates `docs/canon/unification-matrix.yml` in the same PR. By end of wave, A9 Tessera should read:

| A9 Tessera | A. Identity | B. Storage | C. Transport | D-sub | D-lex | D-form | D-cap | E. Time | F. Recovery | G. Metering |
|---|---|---|---|---|---|---|---|---|---|---|
| **target end-of-wave** | ✓ V4.1+V5.1 | ✓ V0.5+V5.4 | ✓ V5.1 | ✓ V0.5 | ✓ V0.4+V5.7 | ✓ V5.2–V5.7 | ✓ V0.3+V5.1 | ✓ | ⚠ (passive substrate F) | ⚠ (MFP channels in V3 acceptance) |

D-Recovery and G-Metering close passively against substrate behaviour (no tessera-specific deliverable needed; pattern inherited). Both move to ✓ once the universal pattern is exercised end-to-end against tessera cells in a pilot deployment — tracked as a single post-wave acceptance pass, not a separate V-row.

---

## 9. Acceptance gate (end-of-wave)

Wave Tessera is complete when:

1. All 27 V-row PRs are merged (including V0.6 Zig scaffold).
2. **DLO.1 (generic cartridge loader) is merged in `main`** — this is the gate that unblocks the post-loader cohort. If DLO.1 has not landed, the wave is stalled at the pre-loader-base, not failed.
3. `docs/canon/unification-matrix.yml` A9 Tessera row matches the §8 target.
4. `docs/canon/deliverables.yml` has 27 `phase: tessera` entries with `status: completed`.
5. `docs/canon/lexicons.yml` `tessera` entry shows `tesseraHeader_injective` status `proven`.
6. **`grep -r "tessera" runtime/semantos-brain/src/` returns zero matches** (greenfield discipline holds end-to-end). CI gate `tests/gates/no-tessera-in-brain-core.test.ts` green.
7. **CI gate `tests/gates/tessera-adapter-consumption.test.ts` green** — `cartridges/tessera/` imports nothing outside `@semantos/protocol-types/*` for substrate access (no direct LMDB / `@bsv/sdk` / wallet-toolbox / runtime imports).
8. `bun run check`, `bun run build`, `bun test tests/gates/import-boundaries.test.ts` all green on `main`.
9. End-to-end pilot scenario passes: producer-brain bottles a case; distributor-brain receives via `NetworkAdapter` (production impl `bsv-overlay-network-adapter`); dock-handler hat ingests temp-logger burst into AFFINE care-event cells via `StorageAdapter`; case transfers custody to retailer-brain; club-member scans bottle from retailer custody; consumer NFC-tap PWA SPV-verifies the bottle cell via `AnchorAdapter` in <100 ms; care-score renders consistently with the `tesseraCareScore_monotonic` theorem.
10. **First-boot capability mint via DLO.1 generic loader** — operator-root cert gains tessera-declared capabilities from `cartridges/tessera/cartridge.json`, identical pathway as oddjobz's post-lift cert mint.
11. **Tessera installs/uninstalls via `semantos vertical {install,uninstall} tessera`** against a Phase 26G-installed brain.
12. A milestone tag (`wave-tessera-landed`) is cut on `main`.

---

## 10. Recovery / handoff

If Todd returns mid-wave:

- `git log --oneline ^main feat/V*` shows every landed V-row.
- This commission's progress is reflected in `docs/canon/deliverables.yml` (entries with `phase: tessera`, `status: completed`) and in `docs/canon/unification-matrix.yml` (A9 Tessera row status).
- Any agent that hit a blocker submitted a `BLOCKED:` PR — search open PRs for `[BLOCKED]` in the title.
- The V-row progression in `docs/prd/TESSERA-CARTRIDGE.md` §10 critical-path diagram shows what's done versus pending.

If the wave hits a hard error and stops:

- All commits are local until merge; no `git push --force` is permitted.
- Recovery: review open PRs, identify the stuck deliverable, resolve the blocker, re-dispatch.

---

## 11. Progress log

### 2026-05-19 — pre-loader cohort consolidated & verified

The full pre-loader cohort plus the V5.x Lean theorem set has been consolidated
onto a single branch **`feat/tessera-wave-1`** (rooted at `7baf267` V0.2, stacking
V0.4 → V0.6 → V5.7 → V5.2 → V5.5 → V5.3 → V5.4 → V5.6 → V1.0 → V0.1 →
D-Manifest-canonical, plus the recovered acceptance-gate docs cherry-picked as the
tip commit). All work remains **local-only — unpushed, no PRs**, per the
no-`push --force` / merge-discipline rule above.

Local verification on the consolidated branch (all green):

- TS: 34/34 across `no-tessera-in-brain-core`, `manifest-consistency`,
  `tessera` manifest, `tessera-lexicon` (11), `constants` (12).
- Lean: 9 jobs, **zero `sorry`/`admit`** — `tesseraHeader_injective` proven
  (V5.7 discharges the V0.4 skeleton `sorry`), plus TamperOneShot,
  CustodyLinear, CareScoreMonotonic, BlendConservation, ScanEvidencePresent.
- Zig: `cartridges/tessera/zig` scaffold 3/3 steps, 2/2 tests.
- Flutter: `packages/tessera_experience` 2/2.
- `tools/cartridge-manifest/generate.ts` is idempotent against committed assets.

Notes for the merge campaign (decisions deferred, not blockers):

- The branches form a **dual-root topology**, not the V0.1→V0.2 chain §10's
  diagram implies: `feat/V0.1-domain-flag` is its own lineage (root `1495a86`,
  carries the recovered docs + a bundled DLO.1b oddjobz commit); every other
  V-row roots at `7baf267` (V0.2). `feat/tessera-wave-1` reconciles this by
  taking the V0.2-rooted stack (which already re-applies V0.1 content via
  `554d191`) and cherry-picking only the docs. The bundled `4b2343e` DLO.1b
  oddjobz commit was deliberately **excluded** as out-of-wave scope (DLO.1 is
  already on `main`).
- DLO.1 keystone is on `main`. Remaining pre-loader gate per §9: merge
  V0.1+V0.2+V0.4+V0.6.

### 2026-05-19 — CORRECTION: the "missing walker/octave seam" was a stale-branch artifact

An earlier entry here claimed V0.3/V0.5 were blocked because DLO.1 provides no
generic walker/octave registration seam. **That conclusion was wrong** — it was
drawn from `feat/tessera-wave-1` while that branch was ~262 commits behind
`main`, so the grep only saw the pre-cc4 brain-core-baked pattern
(`oddjobz_ratify_walker.zig`) and the vestigial `extensions/` layout.

On current `main` the shell↔cartridge boundary is fully built (the cc4
"canonical cartridge model" work): `core/experience-cartridge` (loader /
registry / types SDK) + the `cartridges/<id>/brain/` golden path. `oddjobz`
already runs on it — `cartridges/oddjobz/brain/zig/src/` FSM walkers +
`*_store_lmdb.zig` + `src/cell-types/*.ts` carrying linearity class. That **is**
the walker/octave registration seam; it is not missing. `extensions/` is the
vestigial bag (now holds SDKs like `game-sdk`, `policy-runtime`).

**Real situation:** the wave was authored against the pre-cc4 vestigial
`cartridges/tessera/` location. V0.3/V0.5 are *not* blocked on inventing an
ABI — they follow the established oddjobz golden-path pattern. No brain-core
hardcoding; no new substrate seam.

### 2026-05-19 — Rebased onto `origin/main`

`feat/tessera-wave-1` rebased onto `origin/main` (`c77329d`) in an isolated
worktree (the shared tree had a parallel session's uncommitted chess
`build.zig` WIP — left untouched). 15 commits replayed; conflicts resolved:

- `docs/canon/deliverables.yml` — additive (kept main's `V0.1` + appended the
  wave's entries).
- `apps/semantos/lib/shell/semantos_router.dart` — **took main's
  registry-driven (CC2c) router wholesale**; discarded the wave's obsolete
  hardcoded `/tessera` route + icon maps. Tessera integrates via
  `CartridgeRegistry` self-registration, not a router edit.
- `core/constants/constants.json` — kept main's superset (it already had
  `TESSERA_PAGE`); regenerated `constants.zig` + `constants.ts` from source.

Post-rebase verification: Lean 9/9 jobs **zero `sorry`/`admit`**; Zig tessera
scaffold 3/3 steps 2/2. TS could not be run authoritatively in the isolated
worktree (a pre-existing workspace-install issue unrelated to tessera —
`@semantos/oddjobz`/`@semantos/scg-relations` link resolution in a fresh
worktree); the rebase's conflict resolutions are sound by inspection and the
affected TS path was 11/11 pre-rebase in the installed checkout. Authoritative
TS re-verify is pending a run in the main checkout.

The pre-loader cohort + V5.x landed on `origin/main` via clean fast-forward
(`444daee..42fe311`, chess-style: no force, no merge, main ref only, no other
WIP touched).

### 2026-05-19 — Retargeted to the `cartridges/tessera/` golden path

History-preserving `git mv` of the whole cartridge out of the vestigial
`extensions/tessera/` into the cc4 canonical layout, mirroring
`cartridges/oddjobz/`:

- `cartridges/tessera/cartridge.json` — top-level descriptor, golden-path
  shape (`role:"experience"`, `experience.flutterPackage`, `brain/`-relative
  path fields, refreshed `_notes`).
- `cartridges/tessera/brain/` — `src/`, `zig/`, `tests/`, `package.json`,
  `tsconfig.json`, `release.config.ts`, `README.md`.

`tools/cartridge-manifest/generate.ts` now reads
`cartridges/<id>/cartridge.json`; `manifest.test.ts` path fixed; all repo
references migrated (docs/canon + PRD + gate comment). Verified on the
retarget branch: `generate.ts --check` no-drift, manifest test 9/9,
greenfield gate holds, Zig scaffold 3/3 at the new path; Lean unaffected
(9/9 zero-sorry on this base). V0.3/V0.5 now follow the
`cartridges/oddjobz/brain/` reference directly — no brain-core code, no new
ABI (the earlier "missing seam" blocker was a stale-branch artifact).

Branch `feat/tessera-cartridge-retarget` off `origin/main` (`42fe311`);
not pushed.

---

*End of commission. Update this file with progress notes per iteration; matrix and deliverables YAML are the structured tracking layer.*
