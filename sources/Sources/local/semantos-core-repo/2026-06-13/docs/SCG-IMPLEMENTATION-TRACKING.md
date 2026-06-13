---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/SCG-IMPLEMENTATION-TRACKING.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.331342+00:00
---

# Semantos Conversation Graph (SCG) — Implementation Phase Tracking

**Companion to:** PRD v0.1 Draft (T. Price / Real Blockchain Solutions)
**Doc owner:** Todd Price
**Repo scoped against:** `/Users/toddprice/projects/semantos-core` @ 2026-05-21
**Status:** Phase 1 substantially landed (Waves 1–8). Phase 2 demo-apps pending. Phase 3 substrate in. Phase 4 retrieval surface in; agent-rewiring + harness pending. Phase 5 branching + schema-driven cells in; governance projection pending.

### Status-board legend

The status boards in §3.9, §4.4, §5.4, §6.3, §7.4 use:

- `[x]` — landed on `main`. A short note names the file(s) and/or RM/PR.
- `[~]` — partially landed. Substrate is in but a consumer/integration step is missing. The note states the gap.
- `[ ]` — not started.
- `[?]` — needs verification (file appears to land the item, but I couldn't confirm green tests without running them in this audit).

---

## State as of 2026-05-21

Snapshot of what's actually shipped, after Waves 0–8 landed on `main`
(see commits `b3b88ed`, `ad8eb14`, `ba310fb`, `722586f`, `e75caf6`,
`60758c0` and the canonical schema-flag promotion in PR #498 `6d16437`).

**Three packages exist on the SCG side:**

1. `core/scg-relations/` (`@semantos/scg-relations`) — substrate-side
   typed relations on `sem_objects`. Exports `RelationKind` (13 kinds incl.
   `REPLIES_TO`, `SUPPORTS`, `DISPUTES`, `SUPERSEDES`, `CITES`, `FORKS`,
   `MERGES`, `REQUESTS_ACTION`, `FULFILLS`, `PAYS`, `ESCROW_LOCKS`,
   `ESCROW_RELEASES`, `ATTESTS`, `GRANTS_ACCESS`, `APPROVES`),
   `createRelation` / `foldRelationGraph`, `relationLexicon`,
   `requireRelationMint` (capability), `forkSubgraph` / `mergeSubgraph`
   (RM-080 branching), `requirePaymentRelation` (RM-063 access gate).
2. `core/conversation-graph/` (`@semantos/conversation-graph`) — generic
   turn pipeline (RM-031b), `autoEmitReplyRelation` (RM-031a),
   `retrieveContext` (RM-061 / Phase 4), `renderThread` / `renderStream`
   (RM-051 / RM-052 projection helpers).
3. `packages/scg/` (`@semantos/scg`) — extension declaration: `scgGrammar`
   + `scgManifest` (RM-021). Manifest-only; no runtime mount-point wiring.
4. `core/experience-cartridge/` (`@semantos/experience-cartridge`) —
   generic cartridge loader (RM-011). `loadCartridge` + `cartridgeRegistry`.
5. `core/plexus-schema-registry/src/schemas/scg-relation.ts` — SCG relation
   payload schema (RM-082), registered under
   `SemantosDomainFlags.SCG_RELATION = 0x0001FE03` (per PR #498).

**Capability slots claimed in `core/plexus-contracts/src/domain-flags.ts`:**
`ClientDomainFlags.RELATION_MINT = 0x0001000c`,
`RELATION_REVOKE = 0x0001000d` (per RM-022).

**SIR constraint variant in `core/semantos-sir/src/types.ts`:**
`{ kind: 'relation'; relationKind: RelationKind; sourceId?; targetId? }`
(line 159). Lowering case in `lower-sir.ts` lines 167–195 (Phase-1
placeholder using `typeHashCheck`; full schema-offset composite is
Phase 5 §7.3 deferred work).

**Reducer pass:** `runtime/intent/src/reducer/relation-pass.ts`,
registered as the 10th pass in `runtime/intent/src/reducer/index.ts`
after `rhetoric-pass` (RM-030).

**Documented locations vs reality.** This doc was written when the
Oddjobz cartridge lived at `extensions/oddjobz/`; it now lives at
`cartridges/oddjobz/brain/`. The path references in §2.10, §3.6,
§3.8, §6.2 below are stale; they're left as-is for diff readability,
but the audit below resolves against the current `cartridges/`
layout.

**What is genuinely pending (per phase, see §3.9 / §4.4 / §5.4 / §6.3 / §7.4):**

- Phase 1 §3.6 — substrate is lifted, but Oddjobz still imports
  `./pipeline.js` (its own `runConversationTurn`) and does not import
  `@semantos/conversation-graph`. RM-041 ("consumer migration") landed
  the package but did not migrate the Oddjobz consumer. **Surfaced
  as a gap; tracked, not fixed in this PR.**
- Phase 2 §4.1 / §4.2 — no `apps/scg-reddit-demo` or
  `apps/scg-stream-demo` exists. Rendering helpers shipped in
  `conversation-graph/src/rendering.ts` (RM-051/052) but no app
  consumes them.
- Phase 4 §6.2 — `retrieveContext` shipped, but no agent rewiring in
  Oddjobz (`turn-extractor` / `reply-generator` still use flat-history
  prompting). Hallucination-harness not written.
- Phase 5 §7.2 — governance projection (proposal → vote → EXECUTES) is
  not visible in the codebase. The relation kinds support the pattern
  (`SUPPORTS`/`DISPUTES`/`APPROVES`) but no operator surface materialises
  it.
- Phase 5 §7.3 — schema is registered and `domain_flag` allocated, but
  `lower-sir.ts` still emits the Phase-1 placeholder composite (`typeHashCheck`
  against `scg.relation:${kind}`) rather than the full schema-offset
  composite against the SCG schema fields. Tagged `[~]` below.

---

## 0. Reconnaissance summary

Before scoping work, a pass over the codebase confirmed three structural facts that materially reshape the PRD:

1. **The "semantic cell" already exists in two forms.** The kernel-level cell is `core/cell-engine` + `core/cell-ops` + `core/protocol-types/src/cell-header.ts` (header-wrapped, hash-anchored, 2PDA-executed). The application-level aggregate is `core/semantic-objects` (`sem_objects` + `sem_object_patches` + `sem_participants` — identity-bound, versioned, optimistic-concurrency-guarded). SCG should not introduce a third cell type; it must compose these two.

2. **The "typed relation" does not exist as a first-class primitive.** Today, relations are *implicit* in two places: (a) `sem_objects.parentId` (hierarchical only) and (b) the patch stream itself (every `ObjectPatch` is effectively an "edit-relation" from author → object). SCG's `SemanticRelation` is the only genuinely new primitive on the substrate side.

3. **Conversation is already implemented — but as an Oddjobz vertical, not a substrate concept.** `extensions/oddjobz/src/conversation/` contains a fully wired turn pipeline (`turn-extractor`, `chat-service`, `reply-generator`, `accumulated-job-state`, `runConversationTurn`). Generalising this is one of the highest-leverage Phase 1 moves: lift the turn machinery out of the vertical, keep Oddjobz as a renderer/cartridge over the generalised primitive.

These findings collapse the substrate work in the PRD from "rebuild a graph engine" to "promote a relation type, extend SIR, register a lexicon, add one reducer pass." The rest is rendering and policy.

---

## 1. Vocabulary reconciliation

The PRD uses some terminology that doesn't exist as named modules in the repo. Pin the mapping before writing code so docs and reviews stay coherent:

| PRD term | Codebase reality | Action |
|---|---|---|
| Semantic Cell | `sem_objects` row + (optionally) packed kernel cell via `core/cell-ops/cellPacker.ts` | **Reuse**. Add `objectKind='scg.cell'` discriminator if a "pure conversation node" needs to be distinguishable from domain aggregates. Otherwise any `sem_objects` row IS a cell. |
| Semantic Relation | Does not exist as a typed entity | **New primitive**, but built as `objectKind='scg.relation'` on `sem_objects` so it inherits identity binding, patches, hashing, versioning for free. See §3.1. |
| Conversation Graph | Patches on a `sem_objects` row of `objectKind='conversation'` (Oddjobz) | **Generalise**. Phase 1 moves this from Oddjobz to a shared package. |
| Experience Cartridge | Closest match: `ExtensionManifest` in `extensions/oddjobz/src/manifest.ts` + FSMs in `state-machines/index.ts` | **Rename in PRD or rename in code.** Recommend: keep "manifest" for the on-disk artefact, use "cartridge" as the runtime loader concept. Phase 1.4. |
| Extension Grammar | `ExtensionGrammar` in `core/protocol-types/src/extension-grammar.ts`; pipeline in `extensions/extraction/src/index.ts` | **Reuse**. SCG ships its own grammar declaring relation entities. |
| Lexicon | `Lexicon<Cat>` in `core/semantos-sir/src/lexicons.ts`; registry `ALL_LEXICONS` | **Extend**. Register `RelationLexicon` alongside `JuralLexicon` etc. |
| Compression Gradient | Implicit pipeline: `reduceToIntent` → `buildSIR` → `lowerSIR` → `emit` → 2PDA. No single orchestrator. | **Keep implicit.** The PRD's gradient is the existing pipeline; the doc should describe it in those terms, not propose a new orchestrator. |
| Intent Reducer / Extraction | `runtime/intent/src/reducer/index.ts::reduceToIntent` (9 trivium/quadrivium passes) | **Extend** with a tenth pass: `relation-pass.ts`. See §3.5. |
| 2PDA Kernel | `core/cell-engine` (Zig) via `core/cell-ops/src/wasm-interface.ts`; opcodes in `core/cell-ops/src/opcodes.ts` (custom range 0xC0–0xCF) | **Reuse**. New IR kinds may need a relation opcode in the 0xC0 range; deferred to Phase 5. |
| Plexus Identity | `core/identity-ports` (4 ports) + `core/plexus-contracts` + `core/plexus-vendor-sdk` | **Reuse**. Relations bind authorship via existing `IdentityPort`. |

The PRD's `NG2` (centralised moderation) and `G3` (native provenance) are already free as a consequence of building on `sem_objects` — every patch carries `facetId`, `createdByCertId`, `lexicon`, and an optimistic-concurrency hash chain. Document this rather than re-engineer it.

---

## 2. Subsystem inventory (file-and-symbol level)

The seven subsystems named in the directive, with their canonical entry points. Every SCG extension hook in §3 references one of these.

### 2.1 Extension grammar
- `core/protocol-types/src/extension-grammar.ts` — `ExtensionGrammar`, `SourceDeclaration`, `EntityMapping`, `CapabilityRequirement`
- `core/protocol-types/src/index.ts` — re-exports
- `extensions/extraction/src/index.ts` — `ExtractionPipeline`, `autoGrammar`, stage functions Fetch → Parse → Typecheck → Infer → Commit
- `extensions/extraction/src/stages/` — `wrapInManifest`, `serialiseManifest`

### 2.2 Experience cartridge (≈ ExtensionManifest)
- `extensions/oddjobz/src/manifest.ts` — `ExtensionManifest`, `oddjobzManifest`
- `extensions/oddjobz/src/state-machines/index.ts` — FSM-edge → capability-mint table (D-O4)
- No loader exists today; manifests are read by the brain's first-boot hook and by the provisioning CLI (D-O10). **Phase 1 adds a generic cartridge loader.**

### 2.3 Lexicon
- `core/semantos-sir/src/lexicons.ts` — `Lexicon` interface, `JuralLexicon`, `ControlSystemsLexicon`, `TradesLexicon`, `ALL_LEXICONS`, `isCategoryOf`, `verifyLexiconInjective`
- `core/semantos-sir/src/types.ts` — `JuralCategory`, `TaxonomyCoordinates`, `TaggedCategory`
- `runtime/intent/src/reducer/types.ts` — `GrammarSpec` (carries lexicon bindings into the reducer)

### 2.4 Apps
- `apps/` — `brain-helm-viewer`, `demo-collab-versioning`, `demo-wasm-threejs`, `legacy-cli`, `loom-react`, `loom-svelte`, `mud`, `navigation_app`, `oddjobtodd`, `oddjobz-mobile`, `piggybank`, `poker-agent`, `semantos-shell`, `settlement`, `site`, `wallet-browser`, `world-apps`, `world-client`
- `runtime/intent/src/pipeline.ts` — `processIntent`, `PipelineDeps` (injectable kernel, storage, emit, sign)
- All apps import `intent`, `identity-ports`, `semantic-objects` — that triple is the de-facto app SDK.

### 2.5 SIR / IR
- `core/semantos-sir/src/index.ts` — `SIRProgram`, `SIRNode`, `lowerSIR`, `compileToSIR`
- `core/semantos-sir/src/types.ts` — `SIRConstraint` discriminated union (kinds: capability, domain, identity, temporal, value, state, interlock, composite), `SIRNode`, `SIRProgram`, `GovernanceContext`, `DomainBinding`
- `core/semantos-sir/src/authority.ts` — `AuthorityVerifier`, `LexiconAuthority`
- `core/semantos-ir/src/types.ts` — `IRProgram`, `IRBinding`, `IRKind` (comparison, logical_and/or/not, capability, domainCheck, typeHashCheck, deref)
- `core/semantos-ir/src/lower.ts` — `lower(ConstraintExpr) → IRProgram`
- `core/semantos-ir/src/emit.ts` — `emit(IRProgram) → Uint8Array`

### 2.6 Compression gradient
- NL → Intent — `runtime/intent/src/reducer/index.ts::reduceToIntent` (9 passes)
- Intent → SIR — `runtime/intent/src/sir-builder.ts::buildSIR`
- SIR → IR — `core/semantos-sir/src/lower-sir.ts::lowerSIR`, `lowerSIRWithAuthority`
- IR → bytes — `core/semantos-ir/src/emit.ts::emit`
- bytes → 2PDA — `core/cell-ops/src/wasm-interface.ts` (Zig/WASM)
- Orchestrator — `runtime/intent/src/pipeline.ts::processIntent`

### 2.7 Intent reducer
- `runtime/intent/src/reducer/index.ts` — `reduceToIntent`, `ReducerResult`, `PassResult`
- `runtime/intent/src/reducer/types.ts` — `ReducerInputState`, `GrammarSpec`, `PassFn`
- Existing passes: `grammar`, `logic`, `rhetoric`, `analogical-prefilter`, `arithmetic`, `geometry`, `music`, `astronomy`, `analogical-rank`
- `runtime/intent/src/handle-message.ts` — `handleMessage`, pending-proposal registry, triage → ratification → dispatch

### 2.8 Cell + semantic-objects (existing substrate)
- `core/cell-engine/` — Zig kernel; `core/cell-engine/src` source, `core/cell-engine/test-vectors`, `core/cell-engine/proof-artifacts`
- `core/cell-ops/src/cellPacker.ts` — `cellPacker` (BUMP, BEEF, ENVELOPE, DATA, STATE sections)
- `core/cell-ops/src/typeHashRegistry.ts` — packed offsets, type-hash computation
- `core/cell-ops/src/opcodes.ts` — `Opcode` enum (custom Plexus range 0xC0–0xCF: `OP_CHECKLINEARTYPE`, `OP_CHECKCAPABILITY`, `OP_CHECKDOMAINFLAG`, `OP_CHECKTYPEHASH`, `OP_DEREF_POINTER`)
- `core/protocol-types/src/cell-header.ts` — `CellHeader`, `CellHeaderLayout`
- `core/semantic-objects/src/schema.ts` — `semObjects`, `semObjectPatches`, `semParticipants` (Drizzle)
- `core/semantic-objects/src/types.ts` — `ObjectRow<P>`, `ObjectPatch<D>`, `Linearity` (`'LINEAR'|'AFFINE'|'RELEVANT'|'FUNGIBLE'`)
- `core/semantic-objects/src/operations.ts` — `createObject`, `appendPatch`, `listPatches`, `foldState`, `addParticipant`
- `core/semantic-objects/src/hash.ts` — `computeNewStateHash`

### 2.9 Identity
- `core/identity-ports/src/ports.ts` — `identityPort`, `recoveryPort`, `attestationPort`, `capabilityPort`, `bindAllIdentityPorts`
- `core/identity-ports/src/types.ts` — port type interfaces
- `core/plexus-contracts/src/identity.ts` — `Brc52Cert`, `computeCertId`
- `core/plexus-contracts/src/domain-flags.ts` — `PlexusStandardFlags`, `ClientDomainFlags`
- `core/plexus-vendor-sdk/src/VendorSDK.ts` — `VendorSDK`, `deriveRootKey`, `deriveChildKey`

### 2.10 Existing conversation surface (Oddjobz)
- `extensions/oddjobz/src/conversation/pipeline.ts` — `runConversationTurn`, `PipelineInput`, `PipelineResult`
- `extensions/oddjobz/src/conversation/turn-handler.ts` — `ChatTurn` processing
- `extensions/oddjobz/src/conversation/turn-extractor.ts` — `extractConversationTurn` (LLM turn → `TaggedFact[]`)
- `extensions/oddjobz/src/conversation/chat-service.ts` — `processConversationTurn`
- `extensions/oddjobz/src/conversation/reply-generator.ts` — `ConversationAction → reply text`
- `extensions/oddjobz/src/conversation/accumulated-job-state.ts` — `AccumulatedJobState`, `mergeExtraction`

---

## 3. Phase 1 — Minimum bolt-on substrate (no new UI)

**Goal.** Promote "typed relation" to a first-class primitive, wire it through SIR/IR/lexicon/grammar/reducer, and lift the conversation pipeline out of Oddjobz so any future app can consume it. **No rendering work, no payments, no governance, no branching.** If Phase 1 ships and no UI changes, that is success.

**Exit criteria.** A unit test creates two `sem_objects` (a "post" and a "reply"), creates a `scg.relation` of kind `REPLIES_TO` between them via the new ops module, fetches the thread back via `foldRelationGraph`, runs an NL intent ("upvote the second one") through `reduceToIntent` and observes a new relation patch with kind `SUPPORTS`, attested by the active identity, with a corresponding `SIRConstraint` lowering cleanly to IR and emitting valid opcodes. All on existing storage, identity, and 2PDA infrastructure.

### 3.1 Relation primitive — new package `core/scg-relations`

**Owner:** core platform
**Depends on:** §3.0 prep only
**New package, not a fork of semantic-objects** — keeps churn isolated.

Files to create:
- `core/scg-relations/src/types.ts` — `RelationKind` (string-literal union of canonical kinds: `REPLIES_TO`, `SUPPORTS`, `DISPUTES`, `SUPERSEDES`, `CITES`, `FORKS`, `REQUESTS_ACTION`, `FULFILLS`, `PAYS`, `ATTESTS`, `GRANTS_ACCESS`, `APPROVES`); `RelationPayload`; `RelationRow` (= `ObjectRow<RelationPayload>` with `objectKind='scg.relation'`); `RelationEdge` (a derived view, not stored).
- `core/scg-relations/src/operations.ts` — `createRelation(db, { kind, sourceId, targetId, ... })` (delegates to `createObject` from `core/semantic-objects/src/operations.ts`), `listRelationsFrom(db, sourceId, kind?)`, `listRelationsTo(db, targetId, kind?)`, `foldRelationGraph(db, rootId, opts)`.
- `core/scg-relations/src/lexicon.ts` — `RelationLexicon` conforming to the `Lexicon<RelationKind>` interface in `core/semantos-sir/src/lexicons.ts`. Exports `relationLexicon` for registration in `ALL_LEXICONS`.
- `core/scg-relations/src/index.ts` — barrel.
- `core/scg-relations/package.json`, `tsconfig.json`, vitest config — match the conventions in sibling `core/*` packages.

Storage decision: **do not extend the `sem_objects` schema.** Relations are `sem_objects` rows of `objectKind='scg.relation'` with `payload = { kind, sourceId, targetId, attestation? }`. The `parentId` column stays NULL for relations (a relation is a peer object, not a child). This avoids a migration in Phase 1.

Edits to existing files:
- `core/semantos-sir/src/lexicons.ts` — add `relationLexicon` to `ALL_LEXICONS`; add `RelationCategory` branch to the `TaggedCategory` discriminated union. Update `verifyLexiconInjective` test fixtures.

### 3.2 SIR constraint extension

**Owner:** SIR
**Depends on:** §3.1

Edits to `core/semantos-sir/src/types.ts`:
- Extend the `SIRConstraint` union with one new variant:
  `{ kind: 'relation'; relationKind: RelationKind; sourceId?: string; targetId?: string }`
- Update any exhaustiveness switches that consume `SIRConstraint` (use `tsc --noUncheckedIndexedAccess` and search `kind === 'composite'` to find them — there are not many, the union is small).

Edits to `core/semantos-sir/src/lower-sir.ts`:
- Add a lowering case for `relation` that produces a composite IR predicate over `OP_CHECKCAPABILITY` (author has the relation-mint capability) + `typeHashCheck` (source and target are valid sem-objects). Defer kernel-level relation opcode (would land in 0xC0 range) to Phase 5; in Phase 1 a relation lowers to a composite of existing checks.

### 3.3 Extension grammar entry

**Owner:** extraction
**Depends on:** §3.1

New file: `extensions/scg/src/grammar.ts`
- Export `scgGrammar: ExtensionGrammar` declaring two `EntityMapping`s: `scg.cell` and `scg.relation`, both binding to the `sem_objects` source.
- `CapabilityRequirement` set: `RELATION_MINT` for `scg.relation` creation; `RELATION_REVOKE` for soft-delete via patch.

Edits:
- `extensions/scg/src/manifest.ts` (new) — declare `scgManifest: ExtensionManifest` referencing the grammar.
- Register `scgManifest` in whatever first-boot path Oddjobz uses (audit `extensions/oddjobz/src/manifest.ts` consumers to find the canonical mount point — likely the brain bootstrap).

### 3.4 Cartridge loader generalisation

**Owner:** runtime
**Depends on:** none; can run in parallel with §3.1–3.3

This is the only "rename + extract" step. Today there is no generic cartridge loader; the brain reads Oddjobz manifests directly. Phase 1 introduces:

New package `core/experience-cartridge`:
- `src/loader.ts` — `loadCartridge(manifest: ExtensionManifest): LoadedCartridge`
- `src/types.ts` — `LoadedCartridge { manifest, grammar, lexicons, fsmEdges, reducerPasses?, conversationHooks? }`
- `src/registry.ts` — `cartridgeRegistry`, `register(cartridge)`, `list()`, `byName(name)`

Migrate:
- The first-boot path that today reads `oddjobzManifest` directly is rewired to call `cartridgeRegistry.register(loadCartridge(oddjobzManifest))`. Oddjobz is now the first registered cartridge; the SCG manifest from §3.3 is the second.

This unblocks: future apps can ship as cartridges (Phase 2), and the conversation pipeline (§3.6) becomes a cartridge hook rather than an Oddjobz-internal call.

### 3.5 Intent-reducer pass

**Owner:** intent runtime
**Depends on:** §3.1, §3.2

New file: `runtime/intent/src/reducer/relation-pass.ts`
- Export `relationPass: PassFn` matching the signature in `runtime/intent/src/reducer/types.ts`.
- Pass detects NL forms expressing relation intents (`"reply to that"`, `"+1 on the previous"`, `"this contradicts what X said"`, `"see also: …"`, `"that fulfills my request"`) using the existing `GrammarSpec` lexicon binding mechanism.
- Emits `SIRConstraint` of `kind: 'relation'` plus a target resolution hint into `ReducerResult.passResults`.

Edits:
- `runtime/intent/src/reducer/index.ts` — register `relationPass` in the pass list. Position: after `rhetoric` (which already detects argumentative stance), before `analogical-prefilter`. Lock this ordering with a snapshot test.

### 3.6 Conversation pipeline generalisation

**Owner:** runtime
**Depends on:** §3.1, §3.4

Lift the conversation machinery out of Oddjobz so it becomes a substrate capability that any cartridge can opt into.

Create `core/conversation-graph` (new package):
- Move (don't copy) from `extensions/oddjobz/src/conversation/`:
  - `pipeline.ts` (`runConversationTurn`) → `core/conversation-graph/src/pipeline.ts`
  - `turn-handler.ts` → `core/conversation-graph/src/turn-handler.ts`
  - `turn-extractor.ts` → `core/conversation-graph/src/turn-extractor.ts`
  - `reply-generator.ts` → `core/conversation-graph/src/reply-generator.ts`
- Keep Oddjobz-specific surfaces in Oddjobz:
  - `chat-service.ts` and `accumulated-job-state.ts` stay in `extensions/oddjobz/src/conversation/` — they are Oddjobz domain logic that consumes the substrate.
- Replace Oddjobz's internal imports with `@semantos/conversation-graph`.

Each conversation turn becomes a patch on a `sem_objects` row of `objectKind='conversation'`. The new turn → relation upgrade: when a turn references a previous turn ("@anchor", quoted text, "reply to X"), the pipeline emits a `scg.relation` of kind `REPLIES_TO`.

Edits:
- `runtime/intent/src/handle-message.ts` — make the conversation hook injectable via `PipelineDeps`; default to the new `core/conversation-graph` implementation. Existing Oddjobz behaviour preserved through the cartridge's `conversationHooks`.

### 3.7 Identity / capability binding

**Owner:** identity
**Depends on:** §3.1

No new ports. Reuse `capabilityPort` from `core/identity-ports/src/ports.ts`. Add two capability constants:
- `RELATION_MINT` (numeric flag in the SCG range — pick a free slot in `core/plexus-contracts/src/domain-flags.ts::ClientDomainFlags`)
- `RELATION_REVOKE`

Edits:
- `core/plexus-contracts/src/domain-flags.ts` — append SCG flags to `ClientDomainFlags` (preserve numeric ordering / no shuffles).
- `core/scg-relations/src/operations.ts::createRelation` — calls `capabilityPort.check({ subject, capability: RELATION_MINT, domainFlag, ... })` before insert; refuses if check fails.

### 3.8 Tests + acceptance

**Owner:** core
**Depends on:** §3.1–3.7

- `core/scg-relations/__tests__/relations.test.ts` — round-trip: createObject post, createObject reply, createRelation REPLIES_TO, foldRelationGraph returns a 2-node graph.
- `core/scg-relations/__tests__/lexicon-injective.test.ts` — `verifyLexiconInjective(relationLexicon)` passes (mirrors the pattern for existing lexicons).
- `core/semantos-sir/__tests__/lower-relation.test.ts` — `SIRConstraint { kind: 'relation', ... }` lowers to a valid `IRProgram`; `emit()` produces non-empty bytes; bytes parse as well-formed opcodes per `core/cell-ops/src/opcodes.ts`.
- `runtime/intent/__tests__/relation-pass.test.ts` — NL strings `"reply to that"`, `"+1"`, `"that fulfills the request"` each produce a relation constraint with the correct `RelationKind`.
- `core/conversation-graph/__tests__/turn-emits-relation.test.ts` — a turn quoting a previous turn auto-emits a `REPLIES_TO` relation.
- E2E (Phase 1 acceptance test): `tests/scg/phase1-substrate.test.ts` — the scenario described in the §3 exit criteria runs end-to-end against the existing storage/identity test harness, no UI.

### 3.9 Phase 1 status board

- [x] §3.1 Relation primitive package — `core/scg-relations/src/{types,operations,lexicon,index}.ts` (RM-010, `b3b88ed`). `relationLexicon` registered.
- [x] §3.2 SIR constraint variant — `core/semantos-sir/src/types.ts:159` (`relation` variant); lowering case `core/semantos-sir/src/lower-sir.ts:167` (RM-020, `b3b88ed`).
- [x] §3.3 Extension grammar entry — `packages/scg/src/grammar.ts`, `packages/scg/src/manifest.ts` (RM-021, `ba310fb`). Note: lives at `packages/scg/` not `extensions/scg/` as originally planned.
- [x] §3.4 Cartridge loader generalisation — `core/experience-cartridge/src/{loader,types,registry}.ts` (RM-011, `ad8eb14`). Named `experience-cartridge`, not the speculative `cartridge-registry`.
- [x] §3.5 Intent-reducer relation pass — `runtime/intent/src/reducer/relation-pass.ts`; registered at position 10 in `runtime/intent/src/reducer/index.ts:33` (RM-030, `b3b88ed`).
- [~] §3.6 Conversation pipeline lifted to core — substrate side **landed**: `core/conversation-graph/src/{pipeline,auto-emit,retrieve-context,rendering,types}.ts` (RM-031a/b, `ba310fb` + `722586f`). Consumer side **not migrated**: `cartridges/oddjobz/brain/src/conversation/turn-handler.ts` still `import { runConversationTurn } from './pipeline.js'` and does not import `@semantos/conversation-graph`. The Oddjobz pipeline at `cartridges/oddjobz/brain/src/conversation/pipeline.ts` is a sibling implementation, not a consumer of the lifted package. RM-041 was named "consumer migration" but only published the lifted package; the actual cut-over is a follow-up.
- [x] §3.7 Capability constants + binding — `core/plexus-contracts/src/domain-flags.ts:85-91` (`RELATION_MINT=0x0001000c`, `RELATION_REVOKE=0x0001000d`); `createRelation` calls `requireRelationMint` via `core/scg-relations/src/capability.ts` (RM-004/022).
- [x] §3.8 Unit tests — `core/scg-relations/src/__tests__/{relations,lexicon-injective,capability,money-and-branching}.test.ts`. Bun-test based.
- [x] §3.8 E2E acceptance test — `core/conversation-graph/src/__tests__/phase1-e2e.test.ts` (RM-040, `722586f`). Composes RM-010/020/022/030/031a.
- [?] Migration note: Oddjobz green — Oddjobz conversation code is untouched (no migration to lifted package), so its tests should be unaffected. Not actively verified in this audit.

---

## 4. Phase 2 — Rendering projections (apps layer)

**Goal.** Validate the substrate by rendering it three ways. No new substrate work; this phase exists to prove generality.

Each projection ships as a cartridge consuming `core/conversation-graph` + `core/scg-relations`.

### 4.1 Reddit-style thread projection
- Cartridge: `apps/scg-reddit-demo` (new), or absorbed into `apps/site` as a route.
- Reads: `foldRelationGraph(rootPostId, { kinds: ['REPLIES_TO', 'SUPPORTS', 'DISPUTES'] })`.
- Ranks: simple weighted sum (supports − disputes). Document that ranking is a UI concern, not a substrate one.
- Acceptance: a thread with 100 nested replies renders in <200ms cold from a warmed `sem_objects` DB.

### 4.2 Discourse-style stream projection
- Cartridge: `apps/scg-stream-demo`.
- Reads: `listPatches` on a conversation aggregate + `listRelationsFrom` per turn.
- Acceptance: chronological scroll with reply-anchor visualisation.

### 4.3 Oddjobz workflow projection
- No new app; verify Oddjobz still renders correctly after §3.6 conversation lift. This is the regression net for Phase 1.

### 4.4 Status board

- [x] §4.1/§4.2 superseded by **persona projection (`projectPersona`)** — substrate-side primitive in `core/conversation-graph/src/rendering.ts` returns a typed `PersonaProjection` whose `topical` face is the Reddit-thread fold and whose `social` face is the Discourse-stream fold. New relation kind `SUBSCRIBES_TO` (kindByte `0x10`) carries pub-sub group memberships. No PWA part — directory consumers (bsvradar-shaped) render the typed structure. Demo apps `D-SCG-reddit-projection` and `D-SCG-stream-projection` are marked SUPERSEDED in `docs/canon/deliverables.yml`; the persona projection is the substrate-side end-state. Tracked as deliverable `D-SCG-persona-projection`. Tests: `core/conversation-graph/src/__tests__/rendering.test.ts` (P1-P8).
- [?] §4.3 Oddjobz regression green — Oddjobz untouched by Waves 1-8; no migration occurred (see §3.6). Pre-existing Oddjobz test suite presumed green; not actively verified in this audit.
- [ ] Performance budget documented and met — 100-reply thread <200ms cold target. No measurement on record.

---

## 5. Phase 3 — Economic primitives (402, micropay, escrow)

**Goal.** Make relations economically active. Specifically: a `PAYS` relation moves value; a `GRANTS_ACCESS` relation gates content read; a `FULFILLS` relation can release escrow.

### 5.1 Money-bearing relation kinds
- Extend `RelationKind` in `core/scg-relations/src/types.ts` with `PAYS`, `ESCROW_LOCKS`, `ESCROW_RELEASES`.
- `RelationPayload` for these kinds carries `amount`, `currency`, `txAnchor?`.

### 5.2 BSV / overlay integration
- Investigate whether existing wallet code in `apps/wallet-browser` and the BSV anchoring path in `core/cell-ops` (search `anchor`, `BUMP`) covers what we need. **Open question** — see §8.
- Add an `EconomicPort` to `core/identity-ports` for `signSpend`, `verifyPayment`.

### 5.3 402-style access gate
- `core/scg-relations/src/access-gate.ts` — `requirePaymentRelation({ targetId, amount }): AccessChallenge`.
- Renderers consult the gate before serving content; if no `PAYS` relation from caller exists, return 402-equivalent challenge.

### 5.4 Status board

- [x] §5.1 Economic relation kinds — `core/scg-relations/src/types.ts:28-46` includes `PAYS`, `ESCROW_LOCKS`, `ESCROW_RELEASES`. `RelationPayload` carries `amount` / `currency` / `txAnchor` fields (RM-060, `e75caf6`).
- [~] §5.2 Wallet/anchor integration audit — `EconomicPort` exists in `core/identity-ports/src/{ports,types}.ts` (lines 321+) with `signSpend` / `verifyPayment` (RM-062, `e75caf6`). Stub binding in `stub-binding.ts:460`. Full wallet-side integration (real `apps/wallet-browser` wiring) not on record; decision-record artefact would help. Tracked as `D-SCG-wallet-integration`.
- [x] §5.3 Access gate primitive — `core/scg-relations/src/access-gate.ts::requirePaymentRelation` (RM-063, `e75caf6`). 402-style challenge surface returns either an access decision or `AccessChallenge`.
- [~] Integration test: paid-content gate + revenue split — gate has tests under `core/scg-relations/src/__tests__/money-and-branching.test.ts`. End-to-end paid-content gate test against a real `sem_objects` substrate exists; revenue-split scenario unclear. Tracked as `D-SCG-revenue-split-e2e`.

---

## 6. Phase 4 — AI memory mode

**Goal.** Make the relation graph a first-class context source for agents. This is mostly a *reader* effort; substrate stays untouched.

### 6.1 Semantic retrieval surface
- `core/conversation-graph/src/retrieve.ts` — `retrieveContext({ subject, query, relationFilter? }): RetrievedSubgraph`.
- Returns a typed subgraph (cells + relations) with provenance, not flattened text.

### 6.2 Agent integration
- Wire into the existing LLM call sites in `extensions/oddjobz/src/conversation/turn-extractor.ts` and `reply-generator.ts`: replace flat-history prompting with subgraph-aware prompting.
- Acceptance: a retrieval test fixture demonstrates a measurable hallucination drop (predefined accuracy metric on a fixed Q&A set against the substrate).

### 6.3 Status board

- [x] §6.1 Retrieval surface — `core/conversation-graph/src/retrieve-context.ts::retrieveContext` (RM-061 sequence, `e75caf6`). Returns a typed subgraph with provenance (not flattened text), per `core/conversation-graph/src/__tests__/retrieve-context.test.ts`.
- [ ] §6.2 Agent rewiring — `cartridges/oddjobz/brain/src/conversation/turn-extractor.ts` and `reply-generator.ts` still use flat-history prompting; neither imports `retrieveContext` from `@semantos/conversation-graph`. Tracked as `D-SCG-agent-rewiring`.
- [ ] §6.3 Hallucination-reduction harness with baseline + post-rewire numbers — depends on §6.2. Tracked as `D-SCG-hallucination-harness`.

---

## 7. Phase 5 — Governance, branching, schema-driven relations

**Goal.** Ship branching, governance, and protocol-level relation binding on top of the cleaned-up header from Phase H (see `outputs/phase-h-header-cleanup-spec.md`). No new kernel opcode for relations — explicit decision (§10 item 7).

### 7.0 Rationale — why no `OP_CHECKRELATION`

The kernel already has `OP_CALLHOST` and `OP_DEREF_POINTER` (`core/cell-engine/src/opcodes/plexus.zig`, dispatcher at 0xC8) which provide host-trusted byte fetches. Any kernel op that operates on host-fetched relation data would just re-spell what `OP_CALLHOST` + existing read/compare opcodes already do, while inheriting host-dependency non-determinism. The only place a relation-aware op gains genuine guarantees is reading **header bytes the kernel knows are present** at fixed offsets — and after Phase H, the right pattern there is "domain_flag selects schema, schema decodes payload, kernel verifies `domainPayloadRoot` binds payload to header." Existing opcodes (`OP_CHECKTYPEHASH`, etc.) already do that work.

### 7.1 Branching (temporal forks)
- New relation kinds: `FORKS`, `MERGES`.
- `core/scg-relations/src/branching.ts` — `forkSubgraph`, `mergeSubgraph` operations. Merge uses three-way comparison on `currentStateHash`.

### 7.2 Governance projection
- A `proposal → debate → vote → execution` chain where each step is a relation and the final `EXECUTES` relation triggers `processIntent` on the proposal's encoded action.
- Voting: model votes as `SUPPORTS` / `DISPUTES` relations, tally via `foldRelationGraph` with weighting from `attestationPort`.

### 7.3 Schema-driven relation cells

Depends on Phase H (see `outputs/phase-h-header-cleanup-spec.md`) having landed the slim header + Plexus schema registry. With those in place, an `scg.relation` cell is:

- `domain_flag = SCG_RELATION` (allocate in `core/plexus-contracts/src/domain-flags.ts`).
- `typeHash` = the SCG-relation type hash (register in `core/cell-ops/src/typeHashRegistry.ts`).
- Payload layout governed by the SCG schema registered at Plexus: ordered fields `source: u256`, `target: u256`, `kind: u8`, `attestation: Sig`.
- `domainPayloadRoot` in the header is a hash over the payload bytes, computed at cell creation.

Kernel-level enforcement comes for free from existing opcodes:
- `OP_CHECKDOMAINFLAG` confirms the cell is an SCG relation.
- `OP_CHECKTYPEHASH` confirms the type.
- A composite predicate using existing hash/compare ops verifies `domainPayloadRoot` against the pushed payload witness, then reads source/target/kind out of the payload at offsets declared by the SCG schema.

**No new opcode. No flag-bit hack. No parentHash overloading.** The schema registry is doing the work that the old `commerceParentHash` slot was implicitly trying to do — and doing it generically for every domain, not just commerce.

Edits:
- `core/plexus-contracts/src/domain-flags.ts` — add `SCG_RELATION`.
- `core/plexus-schema-registry/schemas/scg-relation.ts` (new, lives in the registry package introduced by Phase H §4.1) — declare the SCG relation schema.
- `core/cell-ops/src/typeHashRegistry.ts` — register the SCG-relation type hash.
- `core/semantos-sir/src/lower-sir.ts` — relation-constraint lowering emits the composite predicate against the SCG schema offsets.

### 7.4 Status board

- [x] §7.1 Branching — `core/scg-relations/src/branching.ts::{forkSubgraph,mergeSubgraph}` (RM-080, `e75caf6`). `FORKS` and `MERGES` in `RelationKind`. Tests at `core/scg-relations/src/__tests__/money-and-branching.test.ts:235+`.
- [ ] §7.2 Governance projection (proposal → vote → EXECUTES) — `SUPPORTS`/`DISPUTES`/`APPROVES` exist as relation kinds, but no governance-projection operator surface ties `foldRelationGraph` to a tally + `EXECUTES`-triggered `processIntent`. Tracked as `D-SCG-governance-projection`.
- [~] §7.3 Schema-driven relation cells — `core/plexus-schema-registry/src/schemas/scg-relation.ts` registers `scgRelationSchemaV1` under `SemantosDomainFlags.SCG_RELATION = 0x0001FE03` (RM-082, `e75caf6`; flag promoted to canonical in PR #498 `6d16437`). Today's relations still live in `sem_objects.payload` (jsonb); the on-chain anchored-cell variant ("downstream RMs") that consumes this schema is not yet wired.
- [~] SIR lowerer updated to emit existing-opcode composites against SCG schema offsets — `core/semantos-sir/src/lower-sir.ts:167-195` emits a Phase-1 placeholder (`typeHashCheck` against `scg.relation:${kind}`). The full schema-offset composite (read `source` u256 @ offset 1, `target` u256 @ offset 33, etc.) is deferred. Tracked as `D-SCG-sir-schema-composite`.

---

## 7A. Phase H — Header cleanup + Plexus schema registry (carved out)

**This workstream has been carved out into its own standalone spec.** See `outputs/phase-h-header-cleanup-spec.md`.

**Summary for SCG readers.** Phase H factors domain-specific fields out of the cell header, introduces a domain_flag → payload-schema registry at Plexus, and replaces the stripped fields with one generic `domainPayloadRoot: u256` slot. Header shrinks from 256 bytes of mixed-concern layout to ~132 bytes of kernel-protocol fields plus the bound digest. Commerce semantics migrate to a payload schema registered at Plexus under `domain_flag = COMMERCE`. Kernel ABI bumps `VERSION = 1 → 2`.

**Why it lives in its own doc.** Phase H has independent architectural value (clean kernel/domain separation, recoverable schemas via Plexus, no header bloat for future domains) regardless of whether SCG ever ships. It moves on its own cadence, has its own owner, and unblocks every future domain — not just SCG.

**SCG dependency.** Phase 5 §7.3 (schema-driven relation cells) depends on Phase H landing. Phases 1–4 do not.

**Status:** Drafted, not started.

---

## 8. Cross-cutting concerns

### 8.1 Migrations
Phase 1 does not migrate `sem_objects`. Phase 5 may need a migration to support efficient relation indexing if `foldRelationGraph` becomes a hot path; add a secondary index on `(objectKind='scg.relation', payload->>'sourceId')` and `(objectKind='scg.relation', payload->>'targetId')` then.

### 8.2 Performance budgets
- Phase 1: `foldRelationGraph(rootId, depth=3)` ≤ 50ms p95 on a 10k-object DB.
- Phase 2: thread render ≤ 200ms cold.
- Phase 3: 402 gate decision ≤ 5ms (in-memory cache).
- Phase 5: typed-parentHash relation verification ≤ kernel-tier latency (uses existing `OP_CHECKTYPEHASH` + field reads; should match `OP_CHECKCAPABILITY`).

### 8.3 Lexicon authority + grammar signing
The SCG grammar (§3.3) must be signed under a `LexiconAuthority` per `core/semantos-sir/src/authority.ts` once it lands in production. **Open question:** which signing identity holds the SCG grammar? See §9.

### 8.4 Determinism
Every primitive added must be deterministically replayable. Relations carry a timestamp from `appendPatch`'s `timestamp` field; do not introduce wall-clock dependencies in `foldRelationGraph` or the reducer pass.

### 8.5 Cartridge versioning
`ExtensionManifest` carries a version. Cartridge loader (§3.4) refuses to register two cartridges with incompatible major versions of the same name. Add this to the loader's invariants.

---

## 9. Risk register

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Lifting conversation out of Oddjobz breaks the existing Oddjobz test suite | M | H | Lift via move-not-copy with re-export shim; Oddjobz tests run unchanged. Gated on §4.3. |
| R2 | `SIRConstraint` union extension cascades through many switch statements | L | M | Pre-flight grep for `kind === 'composite'` and similar; fix exhaustiveness in one PR. |
| R3 | Relations-as-sem_objects pattern hits query performance ceiling | M | M | Phase 1 deliberately defers indexing. Re-evaluate at end of Phase 2 with real numbers. |
| R4 | Phase H header refactor breaks an unaudited commerce consumer | L | M | The audit found no production reads of `commercePhase`/`commerceDimension`/`commerceParentHash`/`commercePrevState` by name; but pre-PR re-audit on the actual branch is mandatory. Run full test matrix before merge. |
| R4b | Plexus schema registry recovery story breaks if a vendor's schemas aren't backed up before key loss | M | H | Schema persistence (Phase H §4.1) must land *before* any new domain (including SCG) registers. Make schema-registration the same transaction as domain-flag allocation. Tracked in the Phase H spec. |
| R4c | Migrating commerce semantics to payload changes hash inputs → existing commerce cells fail verification | M | M | Commerce cells in flight today: audit. If any production data exists, ship a one-time migration that rewrites them under the new schema; otherwise this is a green-field cut. |
| R5 | Cartridge loader becomes a god-object | M | M | Keep loader interface narrow: `(manifest) → LoadedCartridge`. No business logic in the loader. |
| R6 | Reducer pass false positives ("reply to that" misclassified) | M | M | Threshold + confidence score from the pass; downstream UI can prompt for confirmation. Standard pattern in the existing reducer. |
| R7 | Economic relations (Phase 3) collide with existing wallet/anchoring code paths | M | H | Audit in §5.2 before touching. Open question 9.3. |
| R8 | Identity port surface widens to "EconomicPort" prematurely | L | M | Hold off until Phase 3; do not pre-bind in Phase 1. |

---

## 10. Open decisions

1. **Cartridge vs manifest terminology.** Recommended: keep "manifest" for the artefact, introduce "cartridge" as the runtime loader concept (§3.4). Resolve before §3.4 lands.

2. **`scg.cell` discriminator.** Do we need a distinct `objectKind='scg.cell'` for "pure conversation nodes", or do we let any `sem_objects` row act as a cell? Recommended: do not introduce a new discriminator in Phase 1. Revisit when the first projection forces the question.

3. **SCG grammar signing identity.** Which `LexiconAuthority` cert signs `scgGrammar`? (§8.3) Likely a Real Blockchain Solutions root cert. Needed before §3.3 ships to non-test environments.

4. **Capability flag slots.** Which numeric slots in `ClientDomainFlags` (`core/plexus-contracts/src/domain-flags.ts`) get assigned to `RELATION_MINT` and `RELATION_REVOKE`? (§3.7) Pick during §3.1 PR.

5. **Wallet integration boundary for Phase 3.** Does `apps/wallet-browser` extend to support 402-style payment relations, or does Phase 3 introduce a new wallet-agnostic facade? Decision deferred to Phase 3 kickoff.

6. **Ranking is a UI concern — formalise.** §4.1 declares ranking outside the substrate. PRD §19 implies it might want to be inside ("semantic ranking" research). Recommended position: never put ranking in the substrate; ship multiple rankers as projections.

7. **Phase 5 kernel scope — RESOLVED.** No `OP_CHECKRELATION` opcode. Given `OP_CALLHOST` already provides host-trusted byte fetches, a kernel relation op over host-fetched data adds nothing; the only kernel-enforceable case is header-resident, and that's done via existing opcodes + a typed `parentHash` slot. See §7.0 and §7.3.

8. **Flag bit allocations — RESOLVED by Phase H.** The flag-bit hack from the previous Phase 5 draft is unnecessary once Phase H lands. Relation typing comes from `domain_flag` + the schema registry, not from stolen `flags` bits.

9. **`relationsRoot` size — RESOLVED by Phase H.** The full 32B `domainPayloadRoot` is available for any cell, no truncation needed. Per-cell-type root-size negotiation is no longer a question.

10. **`OnChainBinding` decommission path.** Owned by Phase H §4.5 — recommends moving anchoring out of the header entirely into an `AnchorAttestation` cell type that relates to the anchored cell. Tracked in the Phase H spec.

11. **Phase H sequencing vs Phase 1.** Phase 1 ships entirely off-kernel (relations as `sem_objects` rows), so Phase H is *not* a Phase 1 blocker — they can run in parallel. Phase 5 (schema-driven relation cells) *does* depend on Phase H. Recommend scheduling Phase H to land between Phases 1 and 5, with no urgency to overlap.

12. **Commerce production data — owned by Phase H.** Tracked as Phase H §8 open decision 2 (existence of in-flight commerce data) and risk H-R3 (one-time migration vs green-field cut). Not an SCG concern; flagged here only because SCG Phase 5 cannot start until Phase H resolves it.

---

## 11. Glossary (for review meetings)

- **Cell** — a `sem_objects` row. Identity-bound, versioned, hash-chained.
- **Relation** — a `sem_objects` row with `objectKind='scg.relation'` whose payload names a source cell, target cell, and `RelationKind`.
- **Cartridge** — a runtime-loaded experience bundle: manifest + grammar + lexicons + FSM edges + optional reducer passes + optional conversation hooks.
- **Lexicon** — typed vocabulary, `Lexicon<Cat>` in `core/semantos-sir/src/lexicons.ts`.
- **Grammar** — declarative `ExtensionGrammar` over an entity-mapping space, validated by the extraction pipeline.
- **Compression gradient** — the existing five-step pipeline: NL → Intent → SIR → IR → opcodes → 2PDA.
- **Intent reducer** — the nine (post-Phase 1: ten) trivium/quadrivium passes producing an `Intent` from NL.

---

## 12. Footnotes for the PRD author

A few suggested edits to PRD v0.1 to keep it aligned with the codebase:

- **§6.1 Semantic Cell.** Replace the abstract struct with a reference to `core/semantic-objects/src/types.ts::ObjectRow<P>` plus `core/protocol-types/src/cell-header.ts::CellHeader` for the kernel-level form.
- **§6.2 Semantic Relations.** Note that source/target reference `sem_objects.id`, and relations are themselves `sem_objects` rows.
- **§12.3 Compression Gradient Integration.** Add concrete entry points: `reduceToIntent → buildSIR → lowerSIR → emit → wasm-interface`.
- **§13 Kernel Integration.** Mention the custom opcode range 0xC0–0xCF. Note that SCG deliberately does *not* add a kernel opcode for relations — the 2PDA's stack-only model means kernel-enforceable relation checks must read header bytes, which is done via existing opcodes (`OP_CHECKTYPEHASH` + `OP_CHECKDOMAINFLAG` + payload-digest verification) over a slim domain-agnostic header. Host-fetched relation data is verified by the same composite predicate any extension uses, with the same trust profile as `OP_CALLHOST`.
- **§14 Storage Model.** Add the Plexus schema registry as a tier: `domain_flag → DomainSchema` mappings persisted under the vendor identity, so key recovery resolves to the schemas needed to decode any payload authored under that domain.
- **Add §6.3 Cell Header.** The protocol-level cell header is domain-agnostic (kernel-protocol fields + one generic `domainPayloadRoot`). Domain-specific semantics — commerce, governance, SCG relations, anchoring — live in the payload under a schema registered at Plexus and addressed by `domain_flag`. The header carries no domain-specific fields.
- **§17.1 Phase 1.** Replace "core graph primitives" with the §3 list from this document — specifically that "threaded rendering" is *not* Phase 1 substrate work; it's a Phase 2 projection.
- **NG3 Generic Blockchain.** Confirmed accurate; BSV anchoring is `core/cell-ops` BUMP/BEEF section work, not a chain dependency.

---

## 13. `packages/scg` cartridge-shape recommendation

**Context.** After Wave 1–8, the SCG codebase has substrate (`core/scg-relations`,
`core/conversation-graph`), a schema entry (`core/plexus-schema-registry/...
scg-relation.ts`), and a manifest-only extension package
(`packages/scg`). The question is: should `packages/scg` be a
runtime-loaded cartridge, and if so, what wiring is missing?

**Vocabulary pin (consolidation of §1 + Glossary).** In the canonical-cartridge
model (`docs/design/CANONICAL-CARTRIDGE-MODEL.md`, U11 row in
`docs/canon/unification-matrix.yml`) a *cartridge* is a runtime-loaded
experience bundle with a single `cartridge.json` manifest + Brain part
+ PWA part, mounted by the loader via `cartridgeRegistry.register(loadCartridge(...))`.
"Extension" was the pre-canonical name for the same concept (still in
`core/protocol-types/src/extension-grammar.ts::ExtensionGrammar` and
`packages/scg/src/manifest.ts::ScgManifest`). The two names refer to
the same runtime concept; "cartridge" is canon, "extension" is
historical.

**Current `packages/scg` shape.** Manifest-only:

- `scgGrammar` declares two entity mappings (`scg.cell`, `scg.relation`)
  + two capabilities (`RELATION_MINT`, `RELATION_REVOKE`).
- `scgManifest` carries `id: 'scg'`, `version: '0.1.0'`, a reference
  to the grammar id/version, and `conversationHooks: 'auto-emit-reply-relation'`.
- Registration test `packages/scg/src/__tests__/registration.test.ts`
  exercises the cartridge-registry path.

There is **no PWA part** (no `apps/scg-*` consumer), **no Brain part**
(no Zig or Bun runtime code under `packages/scg/`), and **no `cartridge.json`**
in the canonical-cartridge shape (CC0). The manifest is a structurally
shaped TS object, not the canonical JSON artefact that the dual-shell
loader (CC2) reads.

**Per `semantos_streams_shell_native.md`:** the conversation engine
ships native in the shell, so SCG-as-cartridge should expose its
*relation-typed stream* into existing conversation substrate, not
re-implement the stream primitive. The lifted substrate at
`core/conversation-graph` already is that primitive. The cartridge's
job is the *declaration* of relation entities + capabilities + the
opt-in hook (`auto-emit-reply-relation`) — not a parallel runtime.

**Recommendation: keep `packages/scg/` as a declaration-only package, but
align it to the canonical-cartridge model (U11).**

Concrete next steps (not in scope for this PR; flagged as deliverable
work):

1. **Move from `packages/scg/` to `cartridges/scg/`.** Match the U11
   canonical-cartridge layout sibling-by-sibling with `cartridges/oddjobz/`,
   `cartridges/chess/`, etc. The current `packages/`-rooted location is
   the pre-CC0 layout.
2. **Add `cartridges/scg/cartridge.json`.** The canonical-cartridge
   manifest (CC0) replaces `ScgManifest.ts`. Declare `id`, `version`,
   the grammar reference, `objectTypes` for `scg.cell` and
   `scg.relation` (CC5 schema-spine), `verbs` (e.g. `scg.relation.mint`,
   `scg.relation.revoke`, mapped to `verb.dispatch`), and
   `linearity` per object type. `scgGrammar.ts` becomes a derived view
   over the manifest, not the source of truth.
3. **Decide on PWA-part scope.** SCG is *substrate-shaped* — its surface
   value is in projections (Reddit / stream / governance demos). A
   "scg" cartridge without a PWA-part is probably correct: the
   relation-typed stream is a primitive Oddjobz / future cartridges
   consume, not a stand-alone experience. Phase 2 projection demos
   (`apps/scg-reddit-demo`, `apps/scg-stream-demo`) are the PWA-parts,
   shipped as separate cartridges that *depend on* the scg cartridge's
   relation primitives. This matches the "cartridges expose typed
   streams INTO Talk; they don't reimplement the stream primitive"
   constraint.
4. **Wire `conversationHooks: 'auto-emit-reply-relation'` to a real
   mount point.** Today the hook is declared but no consumer invokes
   it via the cartridge-registry path; `autoEmitReplyRelation` is
   imported directly by `core/conversation-graph/src/__tests__/phase1-e2e.test.ts`.
   Resolving §3.6's gap (migrate Oddjobz to consume
   `@semantos/conversation-graph`) will surface this: Oddjobz's
   turn-handler should call the registered hook via the registry,
   not import `autoEmitReplyRelation` directly.

**Bottom line.** Current `packages/scg` is a *correct manifest-only
declaration* — for what RM-021 set out to deliver. To become a *proper*
cartridge in the U11 canonical sense it needs: relocation to
`cartridges/scg/`, a `cartridge.json`, declarative `objectTypes` (CC5)
+ `verbs` (CC0), and a real mount point for the conversation hook. No
new runtime code is required at the cartridge layer — the substrate
already carries it. **Naming: "cartridge" is canon; "extension" is
historical.** Update `ScgManifest` / `ExtensionManifest` references in
docs to "cartridge manifest" as the U11 model continues to bed in.

---

## 14. Oddjobz ↔ conversation-graph wiring verification

Per §3.6 / RM-041 the goal was: "lift turn machinery out of Oddjobz,
keep Oddjobz as a renderer/cartridge over the generalised primitive."
Audit findings:

**Substrate side (landed):**

- `core/conversation-graph/src/{pipeline.ts,auto-emit.ts,retrieve-context.ts,rendering.ts,types.ts}` —
  generic pipeline `runConversationTurn<S, F>`, `autoEmitReplyRelation`,
  thread/stream rendering helpers, retrieval surface.
- Five tests under `core/conversation-graph/src/__tests__/` including
  `phase1-e2e.test.ts` (the SCG §3 exit-criteria E2E).

**Consumer side (NOT migrated):**

- `cartridges/oddjobz/brain/src/conversation/turn-handler.ts:24` still
  imports `{ runConversationTurn } from './pipeline.js'` — the
  Oddjobz-local pipeline, not the lifted `@semantos/conversation-graph`
  one.
- `cartridges/oddjobz/brain/src/conversation/pipeline.ts:70` still
  defines its own `runConversationTurn`.
- `grep -rn "conversation-graph\|@semantos/conversation-graph\|autoEmitReplyRelation"
  cartridges/oddjobz/brain/src/` returns **zero matches**.

**Diagnosis.** RM-041 ("consumer migration") landed the lifted package
but did NOT cut Oddjobz over to consume it. The "consumer migration"
commit title implies a switch that the diff didn't actually perform.
This is a real gap, not a documentation drift.

**Implication.** Phase 1 §3.6 is `[~]` not `[x]`. The lifted package is
real and complete; the consumer cut-over is a clean follow-up: rewrite
`cartridges/oddjobz/brain/src/conversation/turn-handler.ts` to import
from `@semantos/conversation-graph` (extractor / state-merger /
reducer-runner become injected ports), retire the Oddjobz-local
`pipeline.ts`, ensure Oddjobz's domain types (`AccumulatedJobState`,
`BridgeContext`) satisfy the generic `S` / `F` type parameters of
`runConversationTurn<S, F>`. **Not fixed in this PR.** Tracked as
deliverable `D-SCG-oddjobz-consumer-cutover`.

