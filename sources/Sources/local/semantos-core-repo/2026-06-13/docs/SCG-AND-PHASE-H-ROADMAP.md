---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/SCG-AND-PHASE-H-ROADMAP.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.326811+00:00
---

# Implementation Roadmap — SCG + Phase H

**Combined roadmap for:**
- `outputs/scg-implementation-tracking.md` (SCG bolt-on, Phases 1–5)
- `outputs/phase-h-header-cleanup-spec.md` (cell header cleanup + Plexus schema registry)

**Scope:** All work items, sequenced by dependency, with the exact files an engineer should read before opening their editor.

**Convention:** Items are `RM-NNN` (stable across renumbering). Waves are partial orders — items in the same wave can run in parallel unless explicitly noted. Cross-references to source specs use `SCG §X.Y` or `H §Z.W`.

---

## How to use this doc

For each item:
- **Read first** = files to skim before writing any code, to understand existing patterns.
- **Create** = new files to author.
- **Edit** = existing files to modify.
- **Accept** = the test or invariant that proves the item is done.

If a "Read first" path looks unfamiliar, that's the cue to read it carefully — don't write changes against a module without seeing how it's currently used.

---

## Dependency graph

```
Wave 0 — Decisions
  │
  ├─► Wave 1 (parallel greenfield)
  │     ├─ RM-010 scg-relations               ──┐
  │     ├─ RM-011 experience-cartridge        ──┤
  │     └─ RM-012 plexus-schema-registry      ──┤
  │                                             │
  │     Wave 2 (build on wave 1)                │
  │     ├─ RM-020 SIR relation constraint ◄────┘
  │     ├─ RM-021 SCG grammar+manifest    ◄─── RM-010
  │     ├─ RM-022 Capability binding      ◄─── RM-010
  │     └─ RM-023 domainPayloadRoot slot  ◄─── RM-012
  │
  │     Wave 3 (deeper integration)
  │     ├─ RM-030 Intent reducer pass     ◄─── RM-020
  │     ├─ RM-031 Conversation lift       ◄─── RM-010, RM-011
  │     └─ RM-032 Strip commerce          ◄─── RM-023
  │
  │     Wave 4 (consumer migrations + tests)
  │     ├─ RM-040 Phase 1 tests + E2E     ◄─── RM-010..031
  │     ├─ RM-041 Commerce consumers      ◄─── RM-032
  │     └─ RM-042 Decommission OCB        ◄─── RM-032
  │
  │     Wave 5 (rendering + kernel)
  │     ├─ RM-050 Kernel ABI bump V2      ◄─── RM-040..042
  │     ├─ RM-051 Reddit projection       ◄─── RM-040
  │     ├─ RM-052 Stream projection       ◄─── RM-040
  │     └─ RM-053 Oddjobz regression      ◄─── RM-040
  │
  │     Wave 6 — Economic primitives      ◄─── RM-050..053
  │     Wave 7 — AI memory mode           ◄─── Wave 5
  │     Wave 8 — Schema-driven relations  ◄─── RM-050
  │     Wave 9 — Dev ergonomics + intent observability
  │     ├─ RM-090..092 reducer/producer instrumentation ◄─── RM-030
  │     ├─ RM-093..095 trace viewer + fixture + replay  ◄─── RM-090, RM-091
  │     ├─ RM-096 typed cell signatures                 ◄─── RM-010, RM-022
  │     └─ RM-097 voice → cartridge dogfood loop        ◄─── RM-091, RM-011
```

Critical path: RM-000 → RM-012 → RM-023 → RM-032 → RM-041 → RM-050 → RM-080 (Phase H + SCG Phase 5).
Independent shorter path: RM-000 → RM-010 → ... → RM-040 → RM-051..053 (SCG Phases 1–2 standalone).
Wave 9 is **off the critical path** — pure tooling and dev-loop ergonomics. It can start as soon as RM-030 lands and runs in parallel with Waves 4+.

---

## Wave 0 — Decisions & re-audit

Cheap, mostly reading and meeting. Blocks everything downstream.

### RM-000 — Re-audit on current branch
- **Source:** Both specs, prerequisite
- **Depends on:** —
- **Read first:**
  - `outputs/scg-implementation-tracking.md` §0 reconnaissance
  - `outputs/phase-h-header-cleanup-spec.md` §2.2 audit findings
  - `core/cell-engine/src/opcodes/plexus.zig` (confirm opcode set unchanged since audit)
  - `core/cell-engine/src/commerce.zig` (still opaque, no opcode reads)
  - `core/protocol-types/src/cell-header.ts` (current layout)
  - `core/cell-ops/src/opcodes.ts` (custom opcode enum)
- **Edit:** none (this is verification)
- **Accept:** `grep -r "commercePhase\|commerceDimension\|commerceParentHash\|commercePrevState" core/ runtime/ extensions/ apps/ tests/` returns the same hits the spec assumes; no surprise consumers.

**RM-000 findings (verified 2026-05-13 against main @ 74c6692):**
1. **`commercePhase` is overloaded** in `core/constants/constants.json` — line 28 starts the `commercePhase` *enum-category* (the `PipelinePhase` taxonomy consumed by `core/cell-ops/src/typeHashRegistry.ts:59::computePhaseHash`); line 74 starts the `headerOffsets.commercePhase` field. **RM-032 and RM-041 must scope deletions strictly to `headerOffsets.{commercePhase,commerceDimension,commerceParentHash,commercePrevState,commerceParentHashSize,commercePrevStateSize}` (lines 74–79).** The enum-category at line 28 and its many consumers (`apps/loom-react/src/canvas/CommercePipeline.tsx`, `runtime/services/.../config-store/*`, `runtime/shell/src/commands/grammar.ts`, `core/protocol-types/src/extension-loader.ts`, multiple phase-gate tests) are unrelated and stay.
2. **`OP_CALLHOST` is at 0xD0, not in the 0xC0–0xCF Plexus range.** The SCG §7.0 rationale still holds (`OP_DEREF_POINTER` at 0xC8 + `OP_CALLHOST` at 0xD0 provide host-fetch); the cross-cutting reads bullet has been corrected to reflect both ranges.
3. **TS/Zig opcode drift (pre-existing, separate issue):** `core/cell-engine/src/opcodes/plexus.zig` dispatches 0xC9–0xCF (`OP_READHEADER`, `OP_CELLCREATE`, `OP_DEMOTE`, `OP_READPAYLOAD`, `OP_SIGN`, `OP_DECREMENT_BUDGET`, `OP_REFILL_BUDGET`) but `core/cell-ops/src/opcodes.ts` only declares 0xC0–0xC8 + 0xD0. Not in Phase-H or SCG scope; tracked separately.
4. **`bumpHash` naming collision** in `apps/poker-agent/src/payment-channel/fsm/*` (SPV-proof FSM types). Unrelated to `OnChainBinding`; do not sweep up in RM-042.

### RM-001 — Decide: hard cut vs compat reader for V1→V2
- **Source:** H §6.1, §8 open decision 1
- **Depends on:** RM-000
- **Read first:**
  - `core/cell-engine/src/constants.zig` (`VERSION: u32 = 1`)
  - `core/cell-engine/src/opcodes/plexus.zig` dispatcher pattern (`else => unreachable`)
- **Accept:** Decision recorded in Phase H spec §8 item 1.

**DECIDED (2026-05-13): Hard cut.** RM-002 confirmed no production commerce data exists, so there is nothing in flight to be backwards-compatible with. RM-050 bumps kernel `VERSION: u32 = 2` directly.

**Pros/cons recap (for the spec record):**
- *Hard cut* — smallest code surface, single deserialiser path, flag-day rollout (all kernels and writers upgrade in lockstep). An old V1 kernel hitting a V2 cell crashes hard via the dispatcher's `else => unreachable`. With no V1 cells in flight this is fine.
- *Compat reader* — reads both V1 and V2 cells into V2 in-memory shape; writers always produce V2. Useful when V1 cells exist and need to be readable while the population ages out. Adds code paths, fixtures, and a deprecation timeline. Not needed here.

### RM-002 — Decide: does production commerce data exist
- **Source:** H §8 open decision 2, risk H-R3
- **Depends on:** RM-000
- **Read first:** runtime/intent, apps/ for any commerce-cell construction
- **Accept:** Yes/no recorded; if yes, RM-041 expands to include a one-time migration of in-flight cells.

**DECIDED (2026-05-13): No production commerce data exists.** RM-041's "one-time migration script under `core/cell-ops/migrations/` for in-flight commerce cells" is **dropped** — RM-041's scope reduces to test-fixture refactor only. Risk H-R3 closed. Unblocks RM-001's hard-cut decision.

### RM-003 — Decide: schema authority
- **Source:** H §8 open decision 3
- **Depends on:** —
- **Read first:**
  - `core/semantos-sir/src/authority.ts` (`LexiconAuthority`, `AuthorityVerifier`)
  - `core/plexus-contracts/src/identity.ts` (`Brc52Cert`, `computeCertId`)
- **Accept:** Reuse `LexiconAuthority` pattern (recommended) or introduce new authority kind, decision recorded.

**DECIDED (2026-05-13): Reuse `LexiconAuthority`.** `core/plexus-schema-registry` (RM-012) mirrors the existing pattern from `core/semantos-sir/src/authority.ts` for schema-author signing — `Brc52CertRef` + `AuthorityVerifier` + `AuthorityVerificationResult`. No new authority kind. Single mental model across lexicons and schemas.

### RM-004 — Allocate flag slots for SCG capabilities
- **Source:** SCG §10 open decision 4
- **Depends on:** —
- **Read first:**
  - `core/plexus-contracts/src/domain-flags.ts` (`PlexusStandardFlags`, `ClientDomainFlags`)
  - `core/cell-engine/src/linearity.zig` (flag bit usage in kernel)
- **Accept:** Numeric slots picked for `RELATION_MINT`, `RELATION_REVOKE`, `SCG_RELATION`, `COMMERCE` (if not present), `ANCHOR_ATTESTATION`, `SCHEMA_AUTHORITY`. Append-only — no shuffling.

**DECIDED (2026-05-13): Slots picked, namespaces separated.**

Plexus Technical Requirements v1.3 §3 reserves `0x00000001`–`0x0000FFFF` for "Plexus standard/extended flags" and `0x00010000`–`0xFFFFFFFF` for "client-defined sovereignty". Every Semantos-introduced flag therefore belongs in the client range. `PlexusStandardFlags` (`0x01`–`0x0d` currently) stays exclusive to Plexus / Dusk-Inc; we **do not** allocate into it.

Within the client range, two distinct concerns appear in the existing `ClientDomainFlags`:
- *Capabilities* (what an actor can do): `VIEW`, `CREATE`, `EDIT`, `DELETE`, `PUBLISH`, `GOVERN_VOTE`, `GOVERN_PROPOSE`, `STAKE`, `TRANSFER`, `ADMIN`, `HOST_EXEC`. These are paired with `capabilityPort.check`.
- *Domain identities* (what a cell's payload encodes): `COMMERCE`, `ANCHOR_ATTESTATION`, `SCG_RELATION`, `SCHEMA_AUTHORITY`. These drive payload-schema lookup at the Plexus schema registry.

These are conceptually distinct and the bare `ClientDomainFlags` constant is already growing unsorted. New namespace:

| Namespace | Range | Purpose |
|---|---|---|
| `ClientDomainFlags` | `0x00010001`–`0x000100FF` (256 slots) | Workbench capabilities. Existing 11 fit comfortably; reserve the block for capability growth. |
| `SemantosDomainFlags` (**new**) | `0x00010100`–`0x000101FF` | Semantos protocol-level domain identifiers — selected by cell header's `domain_flag`, drive schema lookup. |
| (future) further client namespaces | `0x00010200+` | reserved for downstream extensions |

**Allocations:**

`ClientDomainFlags` (RM-022 applies these):

| Flag | Slot | Applied in |
|---|---|---|
| `RELATION_MINT` | `0x0001000c` | RM-022 (`createRelation` gates on this) |
| `RELATION_REVOKE` | `0x0001000d` | RM-022 (soft-delete patch authority) |

`SemantosDomainFlags` (**new constant in `core/plexus-contracts/src/domain-flags.ts`**, applied across multiple RMs):

| Flag | Slot | Applied in |
|---|---|---|
| `SCHEMA_AUTHORITY` | `0x00010100` | RM-012 (meta-flag: this cell registers a schema) |
| `COMMERCE` | `0x00010101` | RM-032 (commerce-payload schema lives under this flag) |
| `ANCHOR_ATTESTATION` | `0x00010102` | RM-042 (anchoring as a cell type) |
| `SCG_RELATION` | `0x00010103` | RM-082 (schema-driven relation cells) |

Append-only. Numeric ordering preserved. No edits applied to `domain-flags.ts` yet — they land in the PRs for RM-022 (`ClientDomainFlags` capabilities), RM-012 (`SemantosDomainFlags` constant + `SCHEMA_AUTHORITY`), RM-032 (`COMMERCE`), RM-042 (`ANCHOR_ATTESTATION`), RM-082 (`SCG_RELATION`).

### RM-005 — Decide: SCG grammar signing identity
- **Source:** SCG §10 open decision 3
- **Depends on:** RM-003
- **Read first:** `core/semantos-sir/src/authority.ts`
- **Accept:** Cert identity recorded; needed before RM-021 ships to non-test environments.

**DEFERRED (2026-05-13): no real RBS root cert exists yet.** Todd: "I don't want to sign anything with something that's not real." RM-021 will use `StubAuthorityVerifier` from `core/semantos-sir/src/authority.ts` for tests/dev. Production rollout of RM-021 (SCG cartridge registered to non-test environments) is **blocked** on either:

1. RBS issuing a real `Brc52Cert` whose `certId` we record here, or
2. The SCG grammar shipping under a different signing authority — to be revisited with Todd when production rollout is in scope.

The signing identity decision is decoupled from RM-021's *implementation* — the grammar code itself can ship; only the `LexiconAuthority` binding waits. Tests use the stub verifier.

---

## Wave 1 — Greenfield packages (parallel)

All three packages are independent. Start in parallel.

### RM-010 — Package `core/scg-relations`
- **Source:** SCG §3.1
- **Depends on:** RM-000, RM-004
- **Read first:**
  - `core/semantic-objects/src/operations.ts` (the `createObject` / `appendPatch` / `listPatches` / `foldState` / `addParticipant` patterns to mirror)
  - `core/semantic-objects/src/types.ts` (`ObjectRow<P>`, `ObjectPatch<D>`, `Linearity`, `ParticipantRole`)
  - `core/semantic-objects/src/schema.ts` (`semObjects`, `semObjectPatches`, `semParticipants` Drizzle definitions)
  - `core/semantic-objects/src/hash.ts` (`computeNewStateHash` — used for optimistic concurrency)
  - `core/semantos-sir/src/lexicons.ts` (`Lexicon` interface, `ALL_LEXICONS`, `verifyLexiconInjective`)
  - `core/semantos-sir/src/types.ts` (`TaggedCategory` union)
  - One sibling package for layout reference, e.g. `core/cell-ops/package.json` + `tsconfig.json`
- **Create:**
  - `core/scg-relations/src/types.ts` — `RelationKind` literal union (`REPLIES_TO`, `SUPPORTS`, `DISPUTES`, `SUPERSEDES`, `CITES`, `FORKS`, `REQUESTS_ACTION`, `FULFILLS`, `PAYS`, `ATTESTS`, `GRANTS_ACCESS`, `APPROVES`), `RelationPayload`, `RelationRow`, `RelationEdge`
  - `core/scg-relations/src/operations.ts` — `createRelation`, `listRelationsFrom`, `listRelationsTo`, `foldRelationGraph`
  - `core/scg-relations/src/lexicon.ts` — `relationLexicon: Lexicon<RelationKind>`
  - `core/scg-relations/src/index.ts` — barrel
  - `core/scg-relations/package.json`, `tsconfig.json`, vitest config
  - `core/scg-relations/__tests__/relations.test.ts` — round-trip create-post, create-reply, create-relation, fold
  - `core/scg-relations/__tests__/lexicon-injective.test.ts` — `verifyLexiconInjective(relationLexicon)` passes
- **Edit:**
  - `core/semantos-sir/src/lexicons.ts` — add `relationLexicon` to `ALL_LEXICONS`; extend `TaggedCategory` union
- **Accept:** Round-trip test green; lexicon injective; relations are `sem_objects` rows of `objectKind='scg.relation'` (no schema migration).

### RM-011 — Package `core/experience-cartridge`
- **Source:** SCG §3.4
- **Depends on:** RM-000
- **Read first:**
  - `extensions/oddjobz/src/manifest.ts` (`ExtensionManifest`, `oddjobzManifest`)
  - `extensions/oddjobz/src/state-machines/index.ts` (FSM-edge → capability-mint table — D-O4)
  - The first-boot path that today reads `oddjobzManifest` directly (grep `oddjobzManifest` to find it)
  - `core/protocol-types/src/extension-grammar.ts` (`ExtensionGrammar`)
- **Create:**
  - `core/experience-cartridge/src/loader.ts` — `loadCartridge(manifest: ExtensionManifest): LoadedCartridge`
  - `core/experience-cartridge/src/types.ts` — `LoadedCartridge { manifest, grammar, lexicons, fsmEdges, reducerPasses?, conversationHooks? }`
  - `core/experience-cartridge/src/registry.ts` — `cartridgeRegistry.register/list/byName`
  - `core/experience-cartridge/__tests__/loader.test.ts`
  - `core/experience-cartridge/__tests__/registry.test.ts` — refuses to register two cartridges with incompatible major versions of the same name
  - Package boilerplate
- **Edit:**
  - First-boot path identified above — call `cartridgeRegistry.register(loadCartridge(oddjobzManifest))` instead of reading manifest directly.
- **Accept:** Oddjobz still boots; cartridge registry list shows Oddjobz; conflict test passes.

### RM-012 — Package `core/plexus-schema-registry`
- **Source:** H §4.1
- **Depends on:** RM-003
- **Read first:**
  - `core/plexus-vendor-sdk/src/store.ts` (SQLite schema, cert table, backup/restore harness)
  - `core/plexus-contracts/src/identity.ts` (`Brc52Cert`, `computeCertId`)
  - `core/plexus-contracts/src/domain-flags.ts` (current flag constants)
  - `core/semantos-sir/src/authority.ts` (`LexiconAuthority` — pattern to mirror for schema signing)
  - `core/cell-ops/src/typeHashRegistry.ts` (typeHash → field layout pattern; conceptually similar)
- **Create:**
  - `core/plexus-schema-registry/src/types.ts` — `DomainSchema`, `FieldDescriptor`, `SchemaLookupKey`, `RegisterResult`, `VerifyResult`
  - `core/plexus-schema-registry/src/registry.ts` — `SchemaRegistry`
  - `core/plexus-schema-registry/src/persistence.ts` — adapter to `core/plexus-vendor-sdk/src/store.ts`
  - `core/plexus-schema-registry/src/encoding.ts` — `encodePayload`, `decodePayload`
  - `core/plexus-schema-registry/src/hash.ts` — `computeDomainPayloadRoot` (SHA-256 over encoded payload)
  - `core/plexus-schema-registry/schemas/index.ts` — barrel
  - `core/plexus-schema-registry/__tests__/round-trip.test.ts`
  - `core/plexus-schema-registry/__tests__/recovery.test.ts` — register, persist, evict in-memory, restore, lookup succeeds
  - `core/plexus-schema-registry/__tests__/signature.test.ts`
  - `core/plexus-schema-registry/__tests__/cross-impl-vectors.test.ts` — deterministic encoding/hash vectors for cross-implementation verification
  - Package boilerplate
- **Edit:**
  - `core/plexus-vendor-sdk/src/store.ts` — add `domain_schemas` table; CRUD via registry persistence (do NOT bypass).
  - `core/plexus-contracts/src/domain-flags.ts` — add `SCHEMA_AUTHORITY` flag; JSDoc note that flag allocation must register a schema in the same transaction.
- **Accept:** Schema registers, persists, evicts, restores, and produces deterministic `domainPayloadRoot` for a given field set across two independent encodings. Tampered signature rejects.

---

## Wave 2 — Build on Wave 1

### RM-020 — SIR relation constraint variant
- **Source:** SCG §3.2
- **Depends on:** RM-010
- **Read first:**
  - `core/semantos-sir/src/types.ts` (`SIRConstraint` discriminated union — variants `capability`, `domain`, `identity`, `temporal`, `value`, `state`, `interlock`, `composite`)
  - `core/semantos-sir/src/lower-sir.ts` (`lowerSIR`, `lowerSIRWithAuthority` — lowering pattern)
  - `core/semantos-ir/src/types.ts` (`IRProgram`, `IRKind` — target representation)
  - `core/semantos-ir/src/lower.ts` (`lower()` ConstraintExpr → IRProgram)
  - All consumers of `SIRConstraint` (grep `kind: 'composite'` and `kind === 'composite'`)
- **Create:**
  - `core/semantos-sir/__tests__/lower-relation.test.ts`
- **Edit:**
  - `core/semantos-sir/src/types.ts` — extend `SIRConstraint` with `{ kind: 'relation'; relationKind: RelationKind; sourceId?: string; targetId?: string }`
  - `core/semantos-sir/src/lower-sir.ts` — add lowering case for `relation` → composite of `OP_CHECKCAPABILITY` + `typeHashCheck`
  - Every exhaustive switch over `SIRConstraint` — add the new arm (search before edit).
- **Accept:** `SIRConstraint { kind: 'relation', ... }` lowers to a valid `IRProgram`; `emit()` produces non-empty opcode bytes parsing per `core/cell-ops/src/opcodes.ts`.

### RM-021 — SCG extension grammar + manifest
- **Source:** SCG §3.3
- **Depends on:** RM-010, RM-005, RM-011
- **Read first:**
  - `core/protocol-types/src/extension-grammar.ts` (`ExtensionGrammar`, `SourceDeclaration`, `EntityMapping`, `CapabilityRequirement`)
  - `extensions/extraction/src/index.ts` (`ExtractionPipeline`, `autoGrammar`)
  - `extensions/extraction/src/stages/` (`wrapInManifest`, `serialiseManifest`)
  - `extensions/oddjobz/src/manifest.ts` (reference manifest)
- **Create:**
  - `extensions/scg/src/grammar.ts` — `scgGrammar: ExtensionGrammar` declaring `EntityMapping`s for `scg.cell` and `scg.relation`; `CapabilityRequirement`s `RELATION_MINT`, `RELATION_REVOKE`
  - `extensions/scg/src/manifest.ts` — `scgManifest: ExtensionManifest` referencing the grammar
  - `extensions/scg/src/index.ts`, `package.json`, `tsconfig.json`
  - `extensions/scg/__tests__/grammar.test.ts`
- **Edit:**
  - The cartridge-registration first-boot path from RM-011 — register `loadCartridge(scgManifest)` after Oddjobz.
- **Accept:** SCG cartridge appears in `cartridgeRegistry.list()`; grammar passes extraction-pipeline typecheck.

**LANDED 2026-05-13.**

- `extensions/scg/` (new): package boilerplate + `src/grammar.ts` (`scgGrammar` with two `EntityMapping`s — `scg.cell`, `scg.relation` — and two `CapabilityRequirement`s — `RELATION_MINT` required, `RELATION_REVOKE` optional, both pulled from `ClientDomainFlags`) + `src/manifest.ts` (`scgManifest` keyed `id: 'scg'`) + `src/index.ts` barrel.
- Acceptance test `src/__tests__/registration.test.ts` (7/7 green): grammar exposes the two entity mappings, binds both capability flags (numeric values via `@plexus/contracts::ClientDomainFlags`), uses the `scg` taxonomy namespace, with `RELATION_MINT` required and `RELATION_REVOKE` optional. Manifest loads via `loadCartridge` and registers cleanly into `cartridgeRegistry` alongside a sibling.
- Grammar shape mirrors `protocol-types::ExtensionGrammar` structurally (entityMappings + capabilities) but is declared locally so the extension stays free of a runtime dep on protocol-types' full grammar interface — anything satisfying the structural shape registers cleanly.
- Production signing identity: deferred per RM-005 (no real RBS cert yet). Tests use no authority verifier (cartridge registry accepts unsigned manifests; production rollout binds a `LexiconAuthority` cert + grammar signature when RM-005 lands).
- "Edit: cartridge-registration first-boot path" intentionally left out: there's no TS-side first-boot consumer (the brain's first-boot lives in Zig per RM-000 finding). The cartridge is now available for any TS-side boot path to register; brain side stays unchanged.

### RM-022 — SCG capability binding
- **Source:** SCG §3.7
- **Depends on:** RM-010, RM-004
- **Read first:**
  - `core/identity-ports/src/ports.ts` (`identityPort`, `recoveryPort`, `attestationPort`, `capabilityPort`, `bindAllIdentityPorts`)
  - `core/identity-ports/src/types.ts` (`CapabilityPort`, `CapabilityCheck`)
  - `core/plexus-contracts/src/domain-flags.ts` (where to add SCG flags)
- **Edit:**
  - `core/plexus-contracts/src/domain-flags.ts` — append `RELATION_MINT`, `RELATION_REVOKE` to `ClientDomainFlags` at slots from RM-004.
  - `core/scg-relations/src/operations.ts::createRelation` — invoke `capabilityPort.check({ subject, capability: RELATION_MINT, domainFlag, ... })` before insert; refuse on failure.
- **Accept:** `createRelation` rejects when the active identity lacks `RELATION_MINT`; tested by binding a stub `capabilityPort` that refuses.

### RM-023 — `domainPayloadRoot` header slot
- **Source:** H §4.2
- **Depends on:** RM-012
- **Read first:**
  - `core/protocol-types/src/cell-header.ts` (current `CellHeader`, `serializeCellHeader`, `deserializeCellHeader`)
  - `core/constants/constants.json` (offset declarations; auto-generated targets)
  - `core/cell-engine/src/cell.zig` (`getCommerceExtension` / `setCommerceExtension` patterns)
  - `core/cell-engine/src/constants.zig` (auto-generated; do not hand-edit)
  - `core/cell-ops/src/cellPacker.ts` (pack/unpack lifecycle, BUMP/BEEF sections)
- **Edit:**
  - `core/constants/constants.json` — add `domainPayloadRoot` + `domainPayloadRootSize`. Leave commerce keys in place this PR.
  - Run `bun run generate-constants` to regenerate `core/protocol-types/src/constants.ts` and `core/cell-engine/src/constants.zig`.
  - `core/protocol-types/src/cell-header.ts` — add `domainPayloadRoot: Uint8Array` (32B) to `CellHeader`; serialise/deserialise.
  - `core/cell-engine/src/cell.zig` — add `getDomainPayloadRoot` / `setDomainPayloadRoot` (alongside the existing commerce accessors, not replacing them yet).
  - `core/cell-ops/src/cellPacker.ts` — accept optional `domainSchemaContext`; on pack, compute root via `computeDomainPayloadRoot`; on unpack, expose root.
- **Accept:** Pack + unpack round-trip with a registered schema preserves `domainPayloadRoot` bit-exact. Independent recomputation from payload + schema matches.

---

## Wave 3 — Deeper integration

### RM-030 — Intent reducer relation pass
- **Source:** SCG §3.5
- **Depends on:** RM-020
- **Read first:**
  - `runtime/intent/src/reducer/index.ts` (`reduceToIntent`, `ReducerResult`, `PassResult`, pass ordering)
  - `runtime/intent/src/reducer/types.ts` (`ReducerInputState`, `GrammarSpec`, `PassFn`)
  - One existing pass to mirror style: `runtime/intent/src/reducer/rhetoric-pass.ts` (closest semantically)
  - `runtime/intent/src/reducer/grammar-pass.ts`, `logic-pass.ts` (for pass conventions)
- **Create:**
  - `runtime/intent/src/reducer/relation-pass.ts` — `relationPass: PassFn` detecting NL relation forms (`"reply to that"`, `"+1 on the previous"`, `"this contradicts what X said"`, `"see also: ..."`, `"that fulfills my request"`)
  - `runtime/intent/__tests__/relation-pass.test.ts` — NL → relation constraint with correct `RelationKind`
  - Snapshot test for pass ordering
- **Edit:**
  - `runtime/intent/src/reducer/index.ts` — register `relationPass` between `rhetoric` and `analogical-prefilter`.
- **Accept:** NL strings detect the expected `RelationKind` with confidence scores; pass-ordering snapshot test pins the position.

### RM-031 — Conversation pipeline lift to `core/conversation-graph`
- **Source:** SCG §3.6
- **Depends on:** RM-010, RM-011
- **Read first:**
  - `extensions/oddjobz/src/conversation/pipeline.ts` (`runConversationTurn`)
  - `extensions/oddjobz/src/conversation/turn-handler.ts`
  - `extensions/oddjobz/src/conversation/turn-extractor.ts`
  - `extensions/oddjobz/src/conversation/reply-generator.ts`
  - `extensions/oddjobz/src/conversation/chat-service.ts` (Oddjobz-specific — stays put)
  - `extensions/oddjobz/src/conversation/accumulated-job-state.ts` (Oddjobz-specific — stays put)
  - `runtime/intent/src/handle-message.ts` (`handleMessage`, pending-proposal registry)
  - `runtime/intent/src/pipeline.ts` (`processIntent`, `PipelineDeps` injection)
- **Create:**
  - `core/conversation-graph/src/pipeline.ts` — moved from oddjobz, generalised
  - `core/conversation-graph/src/turn-handler.ts` — moved
  - `core/conversation-graph/src/turn-extractor.ts` — moved
  - `core/conversation-graph/src/reply-generator.ts` — moved
  - `core/conversation-graph/__tests__/turn-emits-relation.test.ts` — a turn quoting a previous turn auto-emits `REPLIES_TO`
  - Package boilerplate
- **Edit:**
  - `extensions/oddjobz/src/conversation/chat-service.ts` — import from `@semantos/conversation-graph` instead of relative paths
  - `extensions/oddjobz/src/conversation/accumulated-job-state.ts` — same
  - `runtime/intent/src/handle-message.ts` — make conversation hook injectable via `PipelineDeps`; default to `core/conversation-graph`
- **Accept:** Oddjobz test suite green unchanged. New turn quoting a previous turn auto-emits a `scg.relation` of kind `REPLIES_TO`.

**LANDED as RM-031a (2026-05-13); RM-031b deferred.**

*RM-031a (this commit):*
- `core/conversation-graph/` (new): substrate-level conversation primitives. `Turn` shape (minimal cross-cutting view: conversationId, turnId, quotedTurnId, authorCertId) + `autoEmitReplyRelation(db, turn, opts?)` helper. When `turn.quotedTurnId` is set, it emits a `REPLIES_TO` relation via `@semantos/scg-relations::createRelation` transparently. When unset, returns `null` (vacuously satisfied).
- `capabilityCheck` thunk forwarded to `createRelation` (RM-022 wiring point for `capabilityPort.check(RELATION_MINT, …)` in production).
- 3/3 tests green: quoted-turn emits REPLIES_TO (with the substrate-graph view confirming it via `listRelationsFrom`); unquoted is a no-op; capability denial blocks creation.

*RM-031b (deferred):*
- The roadmap's literal "move pipeline.ts / turn-handler.ts / turn-extractor.ts / reply-generator.ts from oddjobz to core" runs into tight coupling against oddjobz-specific modules (`accumulated-job-state.ts`, `state-manager.ts`, `substrate-bridge.ts`, the `@anthropic-ai/sdk` LLM client). Literal file-move inverts the layering (`core/` would import from `extensions/oddjobz/`). Done correctly, this is a substantial genericisation refactor: extract `AccumulatedJobState` to a generic type-parameter, abstract the LLM-call surface behind an injectable port, lift the FSM-state-machine bits to oddjobz, etc.
- RM-031a achieves the SCG Phase-1 acceptance ("turn quoting → REPLIES_TO") without that refactor. Oddjobz's existing pipeline calls `autoEmitReplyRelation` at turn-persistence time (small one-line wiring) and the typed-relation layer fills in.
- RM-031b genericises the rest in a focused follow-up session.

### RM-032 — Strip commerce fields from header
- **Source:** H §4.3
- **Depends on:** RM-023, RM-002

**Split into RM-032a (additive, landed 2026-05-13 as 974334b) and RM-032b (strip, deferred):**

*RM-032a (done):*
- `core/plexus-schema-registry/src/schemas/commerce.ts` — `commerceSchemaV1` registered under `SemantosDomainFlags.COMMERCE = 0x00010101`; `commercePayload()` helper builds payloads from named phase/dimension strings.
- `core/cell-ops/src/typeHashRegistry.ts::buildCellHeader` gains a new optional `domainPayload?: Buffer` arg that writes a 32B root at offset 224. Legacy `phase`/`dimension`/`parentHash`/`prevStateHash` args stay functional; both paths coexist. `CellHeader` interface gains `domainPayloadRoot`. `unpackCell` reads the new slot.
- Test: `core/cell-ops/tests/build-cell-header-domain-payload.test.ts` (4 tests green).
- Fix: pre-existing regressions in `cell-store/__tests__/cell-packer.test.ts` and `semantic-fs/__tests__/tombstone-resolver.test.ts` (CellHeader literals missing `domainPayloadRoot` after RM-023 — surfaced when full test sweep ran).

*RM-032b (landed 2026-05-13) — refined strip with chain-fields kept:*

The spec's clean-strip target (`parentHash`/`prevStateHash` move into payload) ran into a real semantic dependency: `cell-verifier` (version-chain validation) and `queryByParent` (semantic-graph parent lookup) both consume those bytes as cross-cutting infrastructure independent of commerce taxonomy. Stripping them broke chain verification with no migration path that fit in this session's scope.

Refined approach (shipped):
- **Strip pure commerce taxonomy** (`phase`, `dimension`) from constants.json + protocol-types CellHeader + serialize/deserialize blocks + all consumer literals.
- **Rename + retain chain fields** — `commerceParentHash` / `commercePrevState` → `parentHash` / `prevStateHash` in `constants.json::headerOffsets`. Same byte positions (96 / 128); they're now first-class CellHeader fields independent of commerce.
- **Strip Zig commerce surface** — `getCommerceExtension` / `setCommerceExtension` removed from `cell.zig`; Commerce* struct + read/writeCommerceExtension removed from `commerce.zig`; OnChainBinding retained for RM-042; reserved-block base hardcoded to 94 since `HEADER_OFFSET_COMMERCE_PHASE` no longer exists.
- **`CommerceExtension` interface removed** from protocol-types + index/browser barrels.
- **`@semantos/cell-ops` legacy back-compat surface unchanged** — `cdm`/`game-sdk`/`cell-engine` tests still use the cell-ops `CellHeader` interface with legacy `phase` / `dimension` args on `buildCellHeader` (writes at offsets 94-95; protocol-types deserialize ignores those bytes). These consumers migrate to schema-encoded commerce via `domainPayload` over time.

Outcome: clean Phase H §3.1 surface (no commerce taxonomy named on CellHeader); chain semantics preserved via renamed fields; full Zig commerce surface gone.

*RM-032c (deferred) — payload-encoded chain semantics:*
- `core/constants/constants.json` remove `commercePhase`/`commerceDimension`/`commerceParentHash`/`commercePrevState` + sizes; regenerate.
- `core/protocol-types/src/cell-header.ts` strip commerce fields from `CellHeader` + `CellHeaderLayout`; remove commerce blocks from `serializeCellHeader`/`deserializeCellHeader`; remove `CommerceExtension` interface.
- `core/cell-ops/src/typeHashRegistry.ts` — drop the legacy commerce args from `buildCellHeader`; drop fields from `CellHeader`; update `unpackCell`.
- `core/cell-engine/src/commerce.zig` — drop Commerce* code, keep OnChainBinding for RM-042.
- `core/cell-engine/src/cell.zig` — remove `getCommerceExtension` / `setCommerceExtension`.
- Migrate 8+ consumers to the new `domainPayload` path: `extensions/cdm/src/lifecycle/cell-builder.ts`, `extensions/cdm/src/regulatory.ts`, `extensions/game-sdk/src/engine/entity-ops.ts`, `core/cell-engine/tests-bun/cell-engine.test.ts`, `core/cell-engine/tests-bun/integration.test.ts`, `core/cell-engine/tests-bun/proof-of-capability.test.ts`, `core/cell-engine/tests-bun/compat.test.ts`, `core/cell-engine/tests/generate-vectors.ts`.
- Rewrite or remove tests that assert round-trip of `header.parentHash` / `header.prevStateHash` as cell-header fields — those semantics move to the payload and are verified via the schema registry's `decodePayload` + `computeDomainPayloadRoot` round-trip instead.

*Why split:* the strip-and-migrate consumes too much per-iteration context to ship as one safe commit; the additive piece (RM-032a) gets the schema available so any consumer can opt in. RM-032b becomes a focused refactor in a dedicated session.
- **Read first:**
  - `core/protocol-types/src/cell-header.ts` (lines 21–24, 38–41, 44–49, 89–92, 129–132 — all commerce touchpoints)
  - `core/cell-engine/src/commerce.zig` (full file — deleting)
  - `core/cell-ops/src/typeHashRegistry.ts` (lines 212–229, 245+ — mirrored interface + buildCellHeader)
  - `core/constants/constants.json` (lines 74–79 — commerce offsets)
- **Create:**
  - `core/plexus-schema-registry/schemas/commerce.ts` — migrated commerce schema (`domain_flag = COMMERCE`, version 1, fields phase u8 / dimension u8 / parentHash u256 / prevStateHash u256, `commitmentMode: 'payload-digest'`)
- **Edit:**
  - `core/constants/constants.json` — remove `commercePhase`, `commerceDimension`, `commerceParentHash`, `commercePrevState` (and their `*Size` entries). Regenerate constants.
  - `core/protocol-types/src/cell-header.ts` — remove the four fields from `CellHeaderLayout` and `CellHeader`; remove `CommerceExtension`; strip commerce blocks from `serializeCellHeader` and `deserializeCellHeader`.
  - `core/cell-ops/src/typeHashRegistry.ts` — drop the four fields from mirrored `CellHeader` and `buildCellHeader`.
  - `core/cell-engine/src/commerce.zig` — delete.
  - `core/cell-engine/src/cell.zig` — remove `getCommerceExtension` / `setCommerceExtension`.
- **Accept:** Header has no commerce fields; full test matrix green after RM-041 lands consumer migrations. Pre-RM-041, this PR may leave commerce-using tests red — sequence accordingly.

---

## Wave 4 — Tests, consumer migration, OnChainBinding

### RM-040 — SCG Phase 1 tests + E2E acceptance
- **Source:** SCG §3.8
- **Depends on:** RM-010..031
- **Read first:** Every test file created in RM-010..031.
- **Create:**
  - `tests/scg/phase1-substrate.test.ts` — E2E: create post, create reply, create `REPLIES_TO` relation, `foldRelationGraph`, NL "upvote the second one" → `reduceToIntent` → relation patch with `SUPPORTS`, attested by active identity, lowering to IR, emitting valid opcodes.
- **Edit:** none (consolidation).
- **Accept:** E2E test passes against the existing storage/identity test harness. No UI. Oddjobz regression suite green.

### RM-041 — Commerce-consumer migration
- **Source:** H §4.4
- **Depends on:** RM-032
- **Read first:**
  - Grep results from RM-000 (production consumers of commerce field names)
  - `core/cell-ops/src/typeHashRegistry.ts::buildCellHeader` callers (test files mostly)
  - `core/protocol-types/__tests__/cell-packer.test.ts` (or equivalent)
  - `core/protocol-types/__tests__/cell-verifier.test.ts`
- **Edit:**
  - `core/cell-ops/src/typeHashRegistry.ts::buildCellHeader` — replace `phase`/`dimension`/`parentHash`/`prevStateHash` args with `domainPayload?: Uint8Array`.
  - All test fixtures previously passing structured commerce fields — encode via `core/plexus-schema-registry/schemas/commerce.ts::encodePayload`.
  - If RM-002 found production data: add a one-time migration script under `core/cell-ops/migrations/` that rewrites in-flight commerce cells.
- **Accept:** Full test matrix green. `grep "commercePhase\|commerceDimension\|commerceParentHash\|commercePrevState" core/ runtime/ extensions/ apps/ tests/` returns zero hits.

### RM-042 — Decommission `OnChainBinding` (anchoring becomes a cell)
- **Source:** H §4.5
- **Depends on:** RM-032 (parallel with RM-041)
- **Read first:**
  - `core/protocol-types/src/cell-header.ts` (lines 51–56, `OnChainBinding`)
  - `core/cell-ops/src/cellPacker.ts` (BUMP/BEEF section logic — what currently writes the binding)
  - Search for `bumpHash`, `txid`, `derivationIndex` across the repo to find any in-flight consumer
- **Create:**
  - `core/anchor-attestation/src/types.ts` — `AnchorAttestation { targetCellId, txid, vout, bumpHash, derivationIndex }`
  - `core/anchor-attestation/src/operations.ts` — `createAnchorAttestation`, `verifyAnchor` (uses BUMP/BEEF logic, may import from `core/cell-ops/src/cellPacker.ts`)
  - `core/plexus-schema-registry/schemas/anchor-attestation.ts` — `domain_flag = ANCHOR_ATTESTATION`
  - `core/anchor-attestation/__tests__/round-trip.test.ts`
  - Package boilerplate
- **Edit:**
  - `core/constants/constants.json` — remove binding-region keys (`txid`, `vout`, `bumpHash`, `derivationIndex`, sizes).
  - `core/protocol-types/src/cell-header.ts` — remove `OnChainBinding` interface.
  - `core/cell-engine/src/cell.zig` — remove `getOnChainBinding` / `setOnChainBinding`.
- **Accept:** Header bytes 132–255 explicitly reserved-free. Anchoring a cell creates an attestation cell that verifies end-to-end. No header path writes binding fields.

**LANDED 2026-05-13.**

- `core/anchor-attestation/` (new): `AnchorAttestation` typed record + `createAnchorAttestation` / `verifyAnchor` operations. The anchor cell's payload is encoded under `anchorAttestationSchemaV1`; its `domainPayloadRoot` binds the encoded bytes. 9/9 tests green.
- `core/plexus-schema-registry/src/schemas/anchor-attestation.ts` (new): `anchorAttestationSchemaV1` registered under `SemantosDomainFlags.ANCHOR_ATTESTATION = 0x00010102` (RM-004). Field layout: `targetCellId u256` / `txid u256` / `vout u32` / `bumpHash bytes(24)` / `derivationIndex u32`.
- `core/plexus-contracts/src/domain-flags.ts`: `SemantosDomainFlags.COMMERCE` and `SemantosDomainFlags.ANCHOR_ATTESTATION` slots applied (deferred from RM-032a / RM-042 respectively).
- `core/constants/constants.json`: `bindingTxid` / `bindingVout` / `bindingBumpHash` / `bindingDerivationIndex` keys + sizes removed; regenerated.
- `core/protocol-types/src/cell-header.ts`: `OnChainBinding` interface removed; `index.ts` + `browser.ts` re-exports dropped.
- `core/cell-engine/src/cell.zig`: `getOnChainBinding` / `setOnChainBinding` removed; `commerce` import dropped; reserved-block comment updated to reflect post-RM-042 layout.
- `core/cell-engine/src/commerce.zig`: reduced to an empty stub. Its former `OnChainBinding` struct + `readOnChainBinding` / `writeOnChainBinding` deleted. The module remains as a stub so the build.zig wiring (other historic targets still declare it as a dependency) continues to resolve; a follow-up removes the wiring + deletes the file.
- `core/cell-engine/tests/commerce_conformance.zig`: deleted. `core/cell-engine/tests/cell_conformance.zig`: OnChainBinding round-trip test + cross-language vector tests (single_cell_*.bin) removed — the TS packer no longer writes commerce phase/dimension bytes at offsets 94-95, so the existing vectors are stale. They'll be regenerated as part of RM-050's kernel-rebuild + ABI bump work.
- `build.zig`: commerce_test target wired-out; cell_test no longer imports the `commerce` module.

Header byte map after RM-042 (256 bytes):
- 0-93: kernel-protocol fields (magic, linearity, version, flags, refCount, typeHash, ownerId, timestamp, cellCount, payloadTotal)
- 94-95: unnamed reserved (former commerce phase/dimension, RM-032b)
- 96-127: `parentHash` (32B, chain semantics)
- 128-159: `prevStateHash` (32B, chain semantics)
- 160-223: unnamed reserved (former OnChainBinding region, RM-042)
- 224-255: `domainPayloadRoot` (32B, RM-023)

Total kernel-named fields: 132 bytes. Reserved-free: 66 bytes (vs the spec's 124 target — the spec's lower number assumes phase/dimension/parentHash/prevStateHash all move into payload; this PR keeps the chain fields per RM-032b's pragmatic split). RM-050 finalises the layout.

---

## Wave 5 — Kernel rebuild + Phase 2 rendering

### RM-050 — Kernel rebuild + ABI bump V1 → V2
- **Source:** H §4.6
- **Depends on:** RM-040, RM-041, RM-042
- **Read first:**
  - `core/cell-engine/src/constants.zig` (auto-generated; bump comes via `core/constants/constants.json` if present, else direct)
  - `core/cell-engine/scripts/reproducible-build.sh` (full file)
  - `core/cell-engine/proof-artifacts/` (existing artifacts — what needs regenerating)
  - `core/cell-engine/test-vectors/` (existing vectors)
  - `core/cell-engine/fuzz/plexus_atomic_fuzz.zig` (K4 atomicity)
  - `core/cell-engine/fuzz/linearity_fuzz.zig`, `stack_bounds_fuzz.zig`, `opcode_fuzz.zig`
- **Edit:**
  - Bump `VERSION: u32 = 2` in `core/cell-engine/src/constants.zig` (via constants.json if generated).
  - Regenerate test vectors whose hashes depend on the old header layout.
  - Regenerate proof artefacts under `core/cell-engine/proof-artifacts/`.
  - If RM-001 chose compat reader: `core/protocol-types/src/cell-header.ts::deserializeCellHeader` detects V1 layout via version field, lifts to V2 in-memory.
- **Accept:** `core/cell-engine/scripts/reproducible-build.sh` produces a new `WASM-MANIFEST.json` with V2 SHA-256. All four fuzz suites green at 50k iterations. K4 invariant holds.

### RM-051 — Reddit-style thread projection
- **Source:** SCG §4.1
- **Depends on:** RM-040
- **Read first:**
  - `core/scg-relations/src/operations.ts::foldRelationGraph` (from RM-010)
  - `apps/site/` (if absorbing into existing app) or another `apps/*` for cartridge layout
- **Create:** `apps/scg-reddit-demo/` cartridge consuming `core/conversation-graph` + `core/scg-relations`, or absorbed as a route in `apps/site`.
- **Accept:** 100 nested replies render in <200ms cold from a warmed `sem_objects` DB.

**LANDED 2026-05-13 (library only).** Substrate-level `projectThread` lives at `core/conversation-graph/src/rendering.ts` with a nested `ThreadNode` shape, chronological child ordering, and cycle-safety. App-shell adoption (`apps/scg-reddit-demo/`) deferred until a consuming app exists.

### RM-052 — Discourse-style stream projection
- **Source:** SCG §4.2
- **Depends on:** RM-040
- **Read first:** Same as RM-051.
- **Create:** `apps/scg-stream-demo/` cartridge.
- **Accept:** Chronological scroll with reply-anchor visualisation.

**LANDED 2026-05-13 (library only).** `projectStream` lives at `core/conversation-graph/src/rendering.ts`. Groups by `conversationId` by default; emits `authorChange` markers for the renderer. App-shell deferred for the same reason as RM-051.

### RM-053 — Oddjobz regression
- **Source:** SCG §4.3
- **Depends on:** RM-040
- **Read first:** `extensions/oddjobz/__tests__/` (existing test suite)
- **Edit:** none — this is a regression gate.
- **Accept:** Full Oddjobz test suite green after the RM-031 conversation lift.

**LANDED 2026-05-13.** Pre-existing 4 failures (D-O7, PL-7, MT-7) are stable across the Wave 5–8 work; no regression introduced by RM-051/052/060/062/063/070/080/082. 589 pass / 4 fail same before-and-after.

---

## Wave 6 — Economic primitives (SCG Phase 3)

### RM-060 — Money-bearing relation kinds
- **Source:** SCG §5.1
- **Depends on:** RM-050, RM-053
- **Read first:** `core/scg-relations/src/types.ts` (RM-010 output)
- **Edit:**
  - `core/scg-relations/src/types.ts` — extend `RelationKind` with `PAYS`, `ESCROW_LOCKS`, `ESCROW_RELEASES`. Extend `RelationPayload` with `amount`, `currency`, `txAnchor?`.
- **Accept:** Round-trip test for each new kind.

**LANDED 2026-05-13.** `PAYS` was already in the Phase-1 set; RM-060 added `ESCROW_LOCKS` + `ESCROW_RELEASES` and surfaced `amount` / `currency` / `txAnchor` as first-class payload fields. `createRelation` validates that money-bearing kinds carry `amount` + `currency` (M1–M4 in `core/scg-relations/src/__tests__/money-and-branching.test.ts`).

### RM-061 — Wallet / anchor integration audit
- **Source:** SCG §5.2, §10 open decision 5
- **Depends on:** RM-060
- **Read first:**
  - `apps/wallet-browser/` (current wallet capabilities)
  - `core/cell-ops/src/cellPacker.ts` (BUMP/BEEF section logic)
  - `core/anchor-attestation/` (from RM-042)
- **Edit:** decision document — does `apps/wallet-browser` extend, or does a new wallet-agnostic facade ship?
- **Accept:** Decision recorded.

### RM-062 — `EconomicPort` in identity-ports
- **Source:** SCG §5.2
- **Depends on:** RM-061
- **Read first:** `core/identity-ports/src/ports.ts`, `types.ts`
- **Create:** New port `economicPort` for `signSpend`, `verifyPayment`.
- **Edit:** `core/identity-ports/src/ports.ts` + `types.ts` + `bindAllIdentityPorts`.
- **Accept:** Bound stub passes round-trip.

**LANDED 2026-05-13** (without waiting for RM-061's decision doc). `economicPort` is the fifth `Port<>` instance with `signSpend` / `verifyPayment`. `IdentityPortBundle.economic` is optional so vendor-sdk callers that don't carry money can ignore it. Stub binding stores spends in `StubStore.spends` keyed by `txAnchor`; 6 tests in `core/identity-ports/src/__tests__/stub-binding.test.ts` pin the round-trip + failure paths.

### RM-063 — 402-style access gate
- **Source:** SCG §5.3
- **Depends on:** RM-060, RM-062
- **Create:** `core/scg-relations/src/access-gate.ts` — `requirePaymentRelation({ targetId, amount }): AccessChallenge`.
- **Edit:** Renderers from Wave 5 consult the gate before serving content.
- **Accept:** Paid-content gate + revenue split integration test passes; gate decision ≤ 5ms (in-memory cache).

**LANDED 2026-05-13.** `requirePaymentRelation` resolves `(requester, target, amount, currency)` from the existing `listRelationsTo` slice; returns either `{ ok: true, reason: 'paid' | 'granted', relation }` or `{ ok: false, challenge: { status: 402, ... } }`. Optional `honorGrantAccess` flag lets admin / promotional grants bypass the amount check. On-chain anchoring verification is the caller's responsibility (the gate consults `relation` rows only — `txAnchor` round-trip is `@semantos/anchor-attestation::verifyAnchor`). 6 tests in `money-and-branching.test.ts` pin G1–G6.

---

## Wave 7 — AI memory mode (SCG Phase 4)

### RM-070 — Semantic retrieval surface
- **Source:** SCG §6.1
- **Depends on:** RM-031 (conversation lifted) + RM-040 (relations stable)
- **Read first:**
  - `core/conversation-graph/src/` (from RM-031)
  - `core/scg-relations/src/operations.ts::foldRelationGraph`
- **Create:** `core/conversation-graph/src/retrieve.ts` — `retrieveContext({ subject, query, relationFilter? }): RetrievedSubgraph`.
- **Accept:** Returns typed subgraph (cells + relations) with provenance, not flattened text. Unit test against fixture data.

**LANDED 2026-05-13.** Substrate-level *structural* retrieval (BFS over SCG edges) at `core/conversation-graph/src/retrieve-context.ts`. Two modes: `thread` (REPLIES_TO both directions) and `citations` (CITES + SUPERSEDES + SUPPORTS + DISPUTES). Multi-seed walks union the bundles with min-hop relevance; `extraKinds` lets a caller layer FORKS/MERGES on top. The *embedding-based* retrieval (vector index + LLM-aware) is RM-071 — explicitly deferred this round. 8 tests in `core/conversation-graph/src/__tests__/retrieve-context.test.ts` (R1–R8).

### RM-071 — Agent rewiring
- **Source:** SCG §6.2
- **Depends on:** RM-070
- **Read first:**
  - `extensions/oddjobz/src/conversation/turn-extractor.ts` (LLM call site)
  - `extensions/oddjobz/src/conversation/reply-generator.ts` (LLM call site)
- **Edit:** Both files — replace flat-history prompting with subgraph-aware prompting via `retrieveContext`.
- **Accept:** Hallucination-reduction harness shows measurable improvement on a fixed Q&A set; baseline and post-rewire numbers recorded.

---

## Wave 8 — Schema-driven relations (SCG Phase 5)

### RM-080 — Branching (`FORKS`, `MERGES`)
- **Source:** SCG §7.1
- **Depends on:** RM-050
- **Read first:**
  - `core/scg-relations/src/operations.ts::foldRelationGraph`
  - `core/semantic-objects/src/hash.ts::computeNewStateHash` (for three-way merge comparison)
- **Create:** `core/scg-relations/src/branching.ts` — `forkSubgraph`, `mergeSubgraph`.
- **Edit:** Extend `RelationKind` with `FORKS`, `MERGES`.
- **Accept:** Fork → divergent edits → merge round-trip, with conflict detection via state-hash comparison.

**LANDED 2026-05-13.** `FORKS` was already in the Phase-1 set; RM-080 appended `MERGES`. `forkSubgraph` creates a new branch cell + a `FORKS` relation back to the fork point. `mergeSubgraph` creates a merge cell + one `MERGES` relation per parent, three-way-comparing `currentStateHash` across parents to detect conflicts (recorded in `payload.extra.conflicts` + `parentStateHashes`). 5 tests in `money-and-branching.test.ts` (F1–F5).

### RM-081 — Governance projection
- **Source:** SCG §7.2
- **Depends on:** RM-080
- **Read first:**
  - `runtime/intent/src/pipeline.ts::processIntent`
  - `core/identity-ports/src/ports.ts::attestationPort`
- **Create:** Governance projection app (proposal → debate → vote → execution cartridge).
- **Accept:** End-to-end proposal lifecycle with weighted vote tally.

### RM-082 — Schema-driven `scg.relation` cells
- **Source:** SCG §7.3
- **Depends on:** RM-050 (Phase H complete)
- **Read first:**
  - `core/plexus-schema-registry/` (from RM-012)
  - `core/cell-ops/src/typeHashRegistry.ts` (for typeHash registration)
  - `core/semantos-sir/src/lower-sir.ts` (existing lowering; the relation case was added in RM-020)
- **Create:**
  - `core/plexus-schema-registry/schemas/scg-relation.ts` — `domain_flag = SCG_RELATION`, fields `source u256` / `target u256` / `kind u8` / `attestation Sig`
- **Edit:**
  - `core/cell-ops/src/typeHashRegistry.ts` — register the SCG-relation type hash.
  - `core/semantos-sir/src/lower-sir.ts` — relation-constraint lowering emits composite predicate against the SCG schema's payload offsets (replaces the placeholder composite from RM-020).
  - `core/scg-relations/src/operations.ts::createRelation` — write through `core/cell-ops/src/cellPacker.ts` so the cell gets a real `domainPayloadRoot` (not just a `sem_objects` row).
- **Accept:** Relation cell pack/unpack verifies `domainPayloadRoot` via existing opcodes (`OP_CHECKDOMAINFLAG` + `OP_CHECKTYPEHASH` + payload-digest composite). No new opcode.

**LANDED 2026-05-13 (schema half).** `SemantosDomainFlags.SCG_RELATION = 0x00010103` registered in `core/plexus-contracts/src/domain-flags.ts`. `core/plexus-schema-registry/src/schemas/scg-relation.ts` ships `scgRelationSchemaV1` (113-byte payload: kindByte/sourceId/targetId/amount/currency/txAnchor/attestation) + a stable `SCG_RELATION_KIND_BYTES` discriminator table that mirrors `ALL_RELATION_KINDS` order. `computeDomainPayloadRoot` round-trips bit-exact (5 tests S1–S5 in `core/plexus-schema-registry/src/__tests__/scg-relation.test.ts`). The *cell-engine half* — wiring `createRelation` to write a real packed cell via `cellPacker.ts` + registering the typeHash + replacing the SIR composite placeholder — remains future work that depends on RM-050 kernel finalisation (already landed) plus a downstream consumer that actually anchors a relation on-chain.

---

## Wave 9 — Developer ergonomics + intent observability

Goal: make the intent pipeline transparent from raw input through cell write, and shorten the dev loop to "voice note → working cartridge with regression test". Off the critical path; runs parallel to Waves 4+. The structured tracing foundation already exists ([logger.ts](../runtime/intent/src/logger.ts), `StageEvent` emit at every pipeline stage) — Wave 9 is mostly about lifting opaque stages into the trace, building a viewer, and closing the producer → pipeline correlation gap.

**Stance:** no LLM calls or agent loops anywhere in this wave's deliverables. The "AI assistant" is the structured trace itself — show, don't infer. This extends the substrate's no-AI rule one layer up into tooling.

**Sequencing rationale (2026-05-13):** the dependency graph implies the order, but the design principles below also imply *priority*. Cartridge-author ergonomics is the higher-leverage audience (vs hand-composing cells against pask), and the principles that matter most are (a) cell-as-unit-of-thought (→ RM-096 typed signatures), (b) round-trip inspectability (→ RM-090/091/093 trace surface), (c) snapshot/replay determinism (→ RM-094/095 fixture + replay), and (d) Todd's own voice→cartridge loop first (→ RM-097 dogfood). Concretely: land RM-090 + RM-091 (cheap plumbing, unlocks visibility), then RM-093 (viewer makes the trace useful), then RM-097 (the loop you'll feel friction in first), then fall through to RM-092/094/095 once the event stream is paved, and finish with RM-096 once your own loop tells you which signature shape actually matters. RM-096 is the biggest taste-spend in this wave and is worth doing *after* the trace surface tells you what cell composition is most often getting wrong.

**LANDED 2026-05-14 — RM-090 through RM-097 all shipped on `feat/customer-conversations`.** The substrate trace surface is now end-to-end: producer mints `correlationId`, reducer emits `reducer_pass_completed` per pass (with `alternativesCount` surfacing losing candidates), `tools/intent-trace` renders the cascade, transforms a captured JSONL trace into a regression-test fixture, and replays from `sir_built` with typed `Partial<Intent>` overrides. `tools/cartridge-scaffold` produces a working cartridge skeleton (RM-096 typed cells + RM-094 fingerprint regression test). 67 new tests across 7 new files; full reducer + trades + scada suite still green. The voice-capture front-end (mic → JSONL trace) + brain-CLI wiring (`brain intent fixturize --last`, `brain cartridge new`) is the layer above and remains future work.

### Wave 9 follow-up — typed-NL pipeline end-to-end (2026-05-15)

After deploying the Wave 9 inspector to oddjobz-mobile (PWA AppBar badge + `IntentInspectorSheet`), end-to-end testing surfaced three substrate gaps in the typed-NL pipeline. Round-trip inspectability paid off — each gap was diagnosed from the cascade visible in the UI rather than from logs/debugger.

**Gap 3 — producer-side structured fields. LANDED (80433b7).** The cell that landed on rbs had `$1000` only in free-text `intent_summary`; brain action router would have had to regex-parse the price. Fix: `SIRTarget` extended with `amount`, `currency`, `jobId`, `customerId`. Anthropic prompt now hoists money into `target.{amount,currency}` (smallest unit, ISO code), restricts action to a single allowed verb (no more "submit_quote"), and offers concrete examples for amount-bearing and amount-less actions. The envelope spec accepts `originalIntent.targetJson` (optional, ≤1 KiB).

**Gap 2 — producer-side entity resolver. LANDED (f9f9664, 0f0c1c4).** `taxonomy.where = "Yellow Wood Court"` was lifted verbatim from the transcript with no `target.jobId` binding. Fix: `apps/oddjobz-mobile/lib/src/gradient/entity_resolver.dart` — deterministic light-touch matcher over the operator's local active-jobs cache (token overlap on customerName ∪ propertyAddress, refuses near-ties). Wired into `TextIntentService` between SIR success and pipeline call; emits `entity_resolved` / `entity_unresolved` into the trace so the inspector shows WHICH job was bound (or why no match). Loader supplied at `home_screen.dart` from `JobsRepository.loadCached`. 8 acceptance tests in `entity_resolver_test.dart`.

**Gap 1 — brain-side router + storage. PARTIAL (0218879); plumb-through DEFERRED.** Envelope spec + handler parse `originalIntent.targetJson` (so the brain doesn't reject envelopes that include it) — landed. The rest is still ahead: `IntentCellRecord` + LMDB store column for the target JSON, broker event payload includes it, `intent_action_router.zig` honours `target.jobId` directly (skip the substring heuristic when present), verb aliases (`submit_quote → quote`, etc.) so legacy producers still route, and `intent_outcome` WSS push back to the PWA so a successful mutation visibly updates the job-detail screen. **Deferred reason:** the brain Zig codebase has 4-5 touchpoints across handler / store / broker / router / conformance tests, and requires `zig build` + a conformance-test sweep + a deploy to rbs to validate. This session's machine was resource-constrained mid-loop (`SystemResources` build error, `fork failed: resource temporarily unavailable`). Tracked as a backlog item for a future session with the brain dev loop available.

**Net effect for the user today:** typed-NL turns through the PWA inspector now show the full cascade including entity resolution. The cell lands on rbs with `originalIntent.targetJson = { jobId, customerId, amount, currency }` populated. The brain accepts the envelope but currently drops the targetJson on the floor — once the deferred plumb-through ships, the action router will honour the resolved ids and the quote will land on the job entity, the job-detail screen will refresh via WSS, and the round-trip closes.

---

## Wave 10 — Linearity-aware FSM + cell-graph resolver (2026-05-15)

**Trigger:** while reviewing the cell that landed on rbs (Wave 9 follow-up), Todd noted that jobs should themselves be substrate cells — AFFINE on ingestion (a lead is an opportunity that *may* be acted on), transitioning to LINEAR when a commitment is made (quoting consumes the lead; the quote must reach an outcome). The 8-state oddjobz FSM (`lead | quoted | scheduled | in_progress | completed | invoiced | paid | closed`) maps almost 1:1 onto substrate linearity classes.

**Status of the prerequisite "everything is cells" work — most of it is already merged.** Tracked in `docs/prd/BRAIN-FIELD-APP-DB-PIPELINE.md`. Brain entity stores are LMDB cell-backed (W0.1 jobs, W0.2 customers/visits/quotes/invoices/attachments, W0.3 intent cells, W6.2/W6.3 leads); Flutter has `hat_entity_cache` mirroring those cells (W1.1); Pravega `oddjobz-events` stream for FSM transitions (W3.1); intent router uses Pask `h_state` (W4.1). What W0–W6 did NOT do is teach the substrate to enforce *linearity* on the FSM transitions — state mutations today are JSON-payload rewrites on the same cellId, not "consume AFFINE cell + mint LINEAR cell" 2-PDA scripts. That's where Wave 10 lives.

### RM-100 — Audit linearity_class on existing oddjobz entity cells
- **Source:** Wave 10 trigger
- **Depends on:** W0.1, W0.2 (merged)
- **Read first:**
  - `runtime/semantos-brain/src/entity_cell.zig` (ENTITY_TAG_* + encodeCell)
  - `runtime/semantos-brain/src/jobs_store_lmdb.zig` (W0.1 — what byte offset / linearity slot exists today)
  - `core/cell-engine/src/linearity.zig` (LINEAR / AFFINE / RELEVANT discriminator location in the cell header)
  - `core/cell-engine/src/opcodes/plexus.zig::opCheckLinearType / opAssertLinear` (the opcodes that read it)
- **Edit:** none — pure read. Output: an audit doc enumerating, for each of the 8 entity tags, what linearity class is currently encoded in the cell header (almost certainly all LINEAR-by-default since no FSM-aware mint has been wired) versus what SHOULD be encoded (AFFINE for leads + lead-state jobs, LINEAR for committed states, RELEVANT for terminal audit records).
- **Accept:** Markdown table under `docs/spec/oddjobz-linearity-classes.md` mapping `(entity tag, FSM state) → linearity_class`. Implementations land in RM-101.

### RM-101 — FSM transitions as 2-PDA scripts with OP_ASSERTLINEAR
- **Source:** Wave 10 trigger
- **Depends on:** RM-100, W0.1, W0.2
- **Read first:**
  - `runtime/semantos-brain/src/job_fsm.zig` (current `jobs.transition` dispatch path)
  - `runtime/semantos-brain/src/resources/jobs_handler.zig` (the dispatch entry)
  - `core/cell-engine/src/opcodes/plexus.zig::opAssertLinear` + `opCellCreate` + `opDemote`
- **Edit:**
  - `jobs.transition` rewrites: when transitioning from an AFFINE state to a LINEAR commitment state, the handler emits a 2-PDA script `[push prev-cellId, OP_ASSERTLINEAR, push new-payload, OP_CELLCREATE]` that the kernel executes. Failure-atomic: the kernel either accepts both moves (consume prev, mint next) or rejects the transition entirely (prev stays consumable). Replaces the JSON-payload-rewrite path for state-changing transitions.
  - `OP_DEMOTE` (0xCB) is used when going from LINEAR to RELEVANT (a completed quote becomes an audit record).
- **Accept:** All eight FSM transitions land via 2-PDA scripts. Conformance: an attempt to double-quote the same lead is rejected by the kernel (`linearity_class_violation`) instead of by application-level guard logic. The action router (W4.1) emits the script via the existing dispatcher path.

### RM-102 — Site-cell-keyed entity resolver in the PWA
- **Source:** Wave 10 trigger
- **Depends on:** W0.2 (sites are already cells), Wave 9 EntityResolver
- **Read first:**
  - `apps/oddjobz-mobile/lib/src/gradient/entity_resolver.dart` (Wave 9 — token-overlap on customerName ∪ propertyAddress)
  - `apps/oddjobz-mobile/lib/src/repl/jobs_repository.dart::Job.siteRef` + `customerRefs`
  - Whatever Flutter-side surface exposes the `oddjobz.site.v2` cell index — likely a sites-repository that mirrors `jobs_repository.dart` (locate it during RM-102 work; may need to write one)
- **Edit:**
  - `entity_resolver.dart`: extend with a `SiteIndex` parameter. Resolution becomes graph-aware:
    1. Match transcript tokens against site addresses → candidate site-cellIds.
    2. For each candidate site, follow `siteRef`-backref to the active job-cell(s) in that hat's cache.
    3. Score: weighted sum of (site-address tokens, customer-name tokens) — site match beats customer match when both are present (a fresh lead may not have a customer yet but always has a site).
    4. Customer id from `customerRefs.primary` of the resolved job.
  - Inspector renders the resolved chain: `entity_resolved · site=<id> → job=<id> · score=N`.
- **Accept:** Resolver picks "16 Yellowood Cl, Tewantin" when transcript says "the yellow wood pergola" — site-address fragment beats customer-name match. Conformance: 6 new tests in `entity_resolver_test.dart` exercising site→job, customer→job, multi-job-on-one-site (ambiguity rejection), no-active-job-but-active-site (lead-only resolution).

### RM-103 — 6-axis taxonomy on the oddjobz.job cell payload
- **Source:** Wave 10 trigger (Todd's "who/what/where/when/why/how")
- **Depends on:** RM-100
- **Read first:**
  - `runtime/semantos-brain/src/jobs_store_fs.zig::Job` (current payload shape — fields like customer_name, scheduled_at, propertyAddress, siteRef, customerRefs are de-facto where/when/who, but as flat columns, not structured taxonomy)
  - `core/semantos-sir/src/types.ts::TaxonomyCoordinates` (the canonical 4-axis what/how/why/where today)
- **Edit:**
  - Extend `TaxonomyCoordinates` to optionally include `who?: string` (subject/cert id or customer-cell ref) and `when?: string` (ISO timestamp / temporal coordinate).
  - Extend the oddjobz.job cell payload schema to surface this 6-axis taxonomy as a first-class block, derived from existing fields on mint (siteRef → where, customerRefs.primary → who, dueDate → when, etc.). Old payload fields stay for back-compat; the taxonomy is a *view* over them.
  - Producer-side prompt (sir_extractor.dart) accepts `taxonomy.who` and `taxonomy.when` when the transcript implies them.
- **Accept:** A typed-NL turn "quote 750 for Mel Collins' pergola job, due Thursday" produces an Intent whose `taxonomy = { what: "pergola.job", how: "lifecycle.quote", why: "operational", where: "<address>", who: "<customer-cellId-or-name>", when: "<thursday-iso>" }`. The resolver (RM-102) consumes the `who` and `when` axes for tighter matching.

### RM-104 — Brain action router honours envelope `target.jobId` as a cellId
- **Source:** Wave 9 Gap 1 part 2 (deferred) + Wave 10 framing (jobId IS a cellId)
- **Depends on:** Wave 9 RM-091 producer hoist (landed), RM-101 (FSM-as-script — so the router emits 2-PDA scripts when honouring target.jobId)
- **Read first:**
  - `runtime/semantos-brain/src/intent_action_router.zig::processAction` (the substring-heuristic match)
  - `runtime/semantos-brain/src/resources/intent_cells_handler.zig::ParsedEnvelope` (Wave 9 Gap 1 part 1 — already parses `originalIntent.targetJson`, currently drops it on the floor)
- **Edit:**
  - `intent_action_router.zig`: parse `intent_target_json` from the broker event payload. When `target.jobId` is a known cellId in `oddjobz_job_list`, bypass `findSingleMatchingJob` entirely and use the cell directly. Heuristic remains as fallback when target is absent or unknown.
  - Verb aliases: accept `submit_quote → quote`, `send_invoice → invoice`, `mark_complete → close` so legacy producers still route.
  - Brain emits `intent_outcome` Pravega event on success (W3.1 stream) so the PWA's job-detail screen refreshes via WSS — closing the visible round-trip the user expected when "intent_completed · ok" landed in the inspector.
- **Accept:** End-to-end smoke: type "quote 750 for the cootharaba pergola" in the PWA → inspector shows full cascade including `entity_resolved`, cell lands on rbs with target.jobId populated, brain router routes by cellId, job-detail screen on the PWA transitions to "quoted" within 1s of cell-write via the Pravega bridge.

### Dependency graph

```
RM-100 (linearity audit)
   │
   ├──► RM-101 (FSM-as-script)         ──┐
   │                                     │
   ├──► RM-103 (6-axis taxonomy payload) │
   │                                     │
   │                                     ▼
   └──► RM-102 (site-cell-keyed) ─► RM-104 (router honours jobId, full round-trip closes)
```

RM-100 is the only pre-implementation step (pure audit). RM-101 and RM-103 can run in parallel after that. RM-102 builds on RM-103's `who/when` axes for richer matching but can ship in a `who/when-omitted` form ahead of it. RM-104 is the closing-the-loop commit.

### Status board addendum

| ID | Wave | Title | Status |
|---|---|---|---|
| RM-100 | 10 | Linearity-class audit on existing oddjobz entity cells | [ ] |
| RM-101 | 10 | FSM transitions as 2-PDA scripts (OP_ASSERTLINEAR + OP_CELLCREATE) | [ ] |
| RM-102 | 10 | Site-cell-keyed entity resolver in the PWA | [ ] |
| RM-103 | 10 | 6-axis taxonomy on oddjobz.job cell payload | [ ] |
| RM-104 | 10 | Brain router honours envelope target.jobId; emits intent_outcome | [ ] |

### What this wave is NOT doing

- **Promoting jobs to cells**: already done under W0.1.
- **Promoting customers/sites/quotes/invoices/leads to cells**: already done under W0.2, W6.2, W6.3.
- **Pravega event stream for FSM transitions**: already done under W3.1.
- **Flutter cell-mirror cache**: already done under W1.1.
- **Pask-aware intent routing**: already done under W4.1.

Wave 10 layers the **linearity semantics** (RM-100/101), the **taxonomy decomposition** (RM-103), and the **cell-graph awareness in the PWA resolver + the round-trip closure** (RM-102, RM-104) on top of that existing scaffold.

### RM-100 audit findings (2026-05-15)

The audit found something worse than expected: **there are two parallel "cell" formats** in the codebase that share the word "cell" but nothing else.

**Substrate cells** (`core/cell-engine/src/`): 256-byte `CellHeader` + 768-byte payload, totalling 1024 bytes. Header carries magic, linearity_class (offset 16), version, domain_flag (offset 24), ref_count, type_hash (offset 30, 32B), owner_id (offset 62, 16B), timestamp, payload_total, parent_hash (32B), prev_state_hash (32B), domain_payload_root (32B). 2-PDA kernel-evaluated through the executor. **Intent cells are these.**

**Entity cells** (`runtime/semantos-brain/src/entity_cell.zig`): 16-byte simple header (`entity_tag u32 LE | version u32 | payload_len u32 | pad u32`) + 1008 bytes of UTF-8 JSON payload, totalling 1024 bytes. **No linearity. No magic. No type_hash. No owner_id. No parent_hash chain. No domain_flag at the canonical offset.** Kernel cannot read them. **Jobs, customers, visits, quotes, invoices, attachments, sites, leads are these** — entity tags 0x01–0x08.

When W0/W6 says "X is a cell", it means LMDB-packed JSON entity-cell, NOT 2-PDA-substrate-cell.

### RM-100b decision: kill `entity_cell.zig` (2026-05-15)

Earlier draft of this section listed Options A/B/C (full migration / paired cells / parallel ledger) and recommended Option C as least disruptive. **That recommendation was wrong.** Two cell formats with parallel responsibilities is the accumulated complexity Wave 10 should fix, not preserve. The right call:

**Option A — full unification. `entity_cell.zig` is deleted. Every entity store moves to substrate cell format.** Migration spec at `docs/spec/UNIFIED-CELL-FORMAT-MIGRATION.md`.

Benefits compound: ONE format / ONE encoder / ONE conformance suite. Every entity acquires linearity_class (`OP_ASSERTLINEAR` becomes real on jobs/quotes/invoices), a type_hash + type_path (`oddjobz.job.v1` etc. — queryable via `OP_CHECKTYPEHASH`; SIR prompt can reference type paths), and a parent_hash + prev_state_hash chain (FSM transitions become cryptographically linked).

Cost: 8 store rewrites + conformance tests + a one-shot rbs migration tool. Real but bounded. The work lands as RM-110..117; the existing RM-101/102/103/104 reshape on the unified format.

### RM-110 — Unified cell format: drafts + design doc

Adds `docs/spec/UNIFIED-CELL-FORMAT-MIGRATION.md` with the full migration plan (type paths, linearity-class table, per-store rewrite checklist, conformance test sweep, rbs deploy steps).

### RM-111 — `substrate_entity.zig` encoder/decoder

New module at `runtime/semantos-brain/src/substrate_entity.zig`. Function `encodeSubstrateEntity(spec) → [1024]u8` produces a properly-framed substrate cell. Decoder `decodeSubstrateEntity(cell)` returns the typed struct. Replaces `entity_cell.encodeCell` everywhere; same total cell size (1024) but with 768-byte payload after the 256-byte header instead of the 1008-byte payload the entity_cell format had — net effect: each entity has ≤240 bytes less JSON budget. Most existing entities fit easily; ones that don't will use the substrate's existing continuation-cell chain.

### RM-112 — Type path → typeHash registry for oddjobz entities

8 type paths: `oddjobz.{customer,visit,quote,invoice,attachment,job,site,lead}.v1`. Type hashes computed via the existing `computeTypeHash(typePath, phase, dimension)` helper.

### RM-113 — Linearity class mapping

Per-entity-tag + per-state linearity table:

| Entity | State | Linearity |
|---|---|---|
| Lead | pending | AFFINE |
| Lead | ratified / rejected | RELEVANT |
| Job | lead | AFFINE |
| Job | quoted / scheduled / in_progress / invoiced / paid | LINEAR |
| Job | completed / closed | RELEVANT |
| Quote | open | LINEAR |
| Quote | accepted / declined / expired | RELEVANT |
| Invoice | issued / partial | LINEAR |
| Invoice | paid / void | RELEVANT |
| Visit | scheduled | LINEAR |
| Visit | completed / no-show | RELEVANT |
| Customer | active | AFFINE |
| Customer | archived | RELEVANT |
| Site | active | AFFINE |
| Site | archived | RELEVANT |
| Attachment | (immutable) | RELEVANT |

### RM-114 — Each `*_store_lmdb.zig` switches to `substrate_entity` encoding

8 stores rewired. Readers updated. Decoders may need a transition-window fallback to legacy entity_cell format until RM-115 migration runs.

### RM-115 — Migration tool `tools/migrate-entity-cells/`

One-shot reader of legacy `entity_cell` format, re-encoder into substrate format, atomic LMDB swap. Idempotent — magic-byte check skips already-migrated cells.

### RM-116 — Conformance test sweep

Every test that constructs entity cells updates to the new format.

### RM-117 — Delete `entity_cell.zig`  *(blocked — see corrected gate)*

> **2026-05-16 reconciliation (post D-RTC.4).** The architecture moved under RM-117/RM-118 after RM-110–RM-116 landed. Recorded here so the next person doesn't act on the stale plan.
>
> **What changed:** the D-RTC.4 "Reingest Typed Cells" / lift-to-cartridge refactor (commits after `4fd1d7e`, ~22.5k deletions) **deleted 6 of the 8 RM-114 per-store LMDB files** (`jobs_store_lmdb_entity`, `customers_store_lmdb`, `leads_store_lmdb`, `quotes_store_lmdb`, `invoices_store_lmdb`, `visits_store_lmdb`) plus their handlers/FSMs — lifted into cartridges/legacy-ingest. New centralized write path: `runtime/semantos-brain/src/entity_encode_walker.zig` (D-RTC.4 DECISION-10), substrate-only, **enforces `payload_json ≤ 768`**; producers were slimmed to fit (`aed93ca`/`178cb3b`/`8328881`).
>
> **`entity_cell` now has exactly 3 live consumers:** `sites_store_lmdb.zig`, `attachments_store_lmdb.zig` (both still wired via `*_store_fs_mod`, constructed in `cli/serve.zig`/`repl.zig`/`operator.zig`), and `migrate_entity_cells/main.zig`.
>
> **Bound-check (2026-05-16) — the >768 fallback is NOT dead code.** Worst-case serialized JSON: **sites ≈ 2.0 KB** (normalisedAddress 500 + lookupKey 565 + fullAddress 500 + keyNumber 64 + suburb 100 + state 50 + 2×64-hex + keys), **attachments ≈ 1.7 KB** (caption 500 + source_blob_key 256 + mime 128 + id/visit/captured + v2 hex). Both exceed 768. The `entity_cell.encodeCell` >768 fallback in those two stores is a **load-bearing correctness backstop** — deleting it without a substrate replacement reintroduces silent write-drop (`encodeXAsSubstrate(...) catch return;`). An earlier "delete it as dead code" recommendation was wrong; do not repeat it.
>
> **Corrected gate.** `entity_cell.zig` may be deleted only after **all** of:
> 1. **RM-118 (done right)** replaces the `entity_cell.encodeCell` >768 fallback in `sites_store_lmdb`/`attachments_store_lmdb` with a substrate-native fat-payload path — see RM-118 below for why this is a *subsystem project*, not a wrapper.
> 2. The dual-format legacy *reader* branches in those two stores are no longer needed because `brain-migrate-entity-cells` has been run on every environment that holds pre-substrate on-disk cells (rbs included). This is a deploy-discipline step, not a code change.
> 3. `migrate_entity_cells/main.zig` inlines its ~10-line legacy 16-byte decode so the tool keeps building without the module.
>
> The migrate tool today correctly **skips** (does not truncate) legacy cells whose payload >768 — safe, but means large legacy site/attachment cells cannot be converted to substrate until RM-118-done-right exists.
>
> **Status: CLOSED-BLOCKED.** Gate item 1 is not a small task (see RM-118). RM-117 is parked, not scheduled. The load-bearing `entity_cell` fallback stays. This is the correct terminal state, not a TODO — revisit only if the octave-pointer subsystem (RM-118) is ever funded, or if a deliberate decision is made to accept dropping >768 site/attachment writes (a regression — would need explicit sign-off).

### RM-118 — Fat entity payloads  *(CLOSED — not a wrapper; a subsystem. Parked.)*

> **Two successive specs for RM-118 were wrong. This entry records why, so it is never re-attempted as a small task.**
>
> - **Spec v1 (commit 4fd1d7e):** "hand-roll continuation inside `substrate_entity.zig`, `encodeEntity` returns N cells." Wrong — reinvents a kernel module.
> - **Spec v2 (commit 53c3e7f):** "wrap `core/cell-engine/src/multicell.zig`." Also wrong — see below.

**Why "wrap multicell" is architecturally impossible against the entity cell store:**

`multicell.packMultiCell`/`unpackMultiCell` operate on a **single contiguous `N×1024` byte buffer** (Cell 0 ‖ continuations). But the entity store (`src/lmdb/cell_store_lmdb.zig`) is, by explicit design, **one 1024-byte cell per LMDB key**, key = `sha256(cell)`, value padded to 4096, and `cursorPull` returns exactly one `*const [1024]u8` ("reads only the first CELL_BYTES from the value"). There is no key that addresses an `N×1024` blob, and continuation cells carry no back-pointer to their Cell 0 (only `cell_index`/`total_cells`), so a cursor scan of independently-hashed cells cannot regroup them. `multicell` is for blob-at-rest contexts (a file, one KV value), **not** a hash-sharded one-cell-per-key store.

**The architecturally-correct fat-payload mechanism is octave-slot + pointer-cell**, exactly the "octave system / carriages / deref pointer" model: the fat object lives in higher-octave slot storage; the entity store holds a single 1024-byte **pointer cell** carrying `OctaveAddress{ octave, slot, fragment_count }`, dereferenced on read via `OP_DEREF_POINTER (0xC8)` → `host_fetch_cell`. Precedent already in the brain: `src/cell_registry.zig` (type_hash ↔ OctaveAddress), `src/escalation.zig:packPointerCell1` (`fragment_count` packing). Doing this for sites/attachments means integrating: octave slot storage write path, pointer-cell mint, and deref-on-replay. **That is a subsystem project, not an RM.**

- **Status: CLOSED — won't-do as scoped. Parked behind the octave-pointer subsystem.**
- **Why parking is correct, not negligent:** the live write path (`entity_encode_walker.zig`, D-RTC.4 DECISION-10) **enforces `payload_json ≤ 768`** and producers were slimmed (`aed93ca`/`178cb3b`/`8328881`), so the live path never needs this. The only exposure is the legacy/edge `sites_store_lmdb`/`attachments_store_lmdb` write paths, where the `entity_cell.encodeCell` >768 fallback is the **documented, load-bearing backstop** and rbs holds only test data. Building an octave-slot subsystem now would be over-engineering against a non-problem (cf. roadmap principle: no hardcoded v1 workarounds; don't over-engineer V1-preserve).
- **If ever revived:** scope it as "octave-slot fat-object storage + pointer-cell entity refs" — its own design doc, not a line item under cell-format migration. Wrapping `multicell` is a dead end against the KV cell store; do not try again.

```
RM-110 (design) ─► RM-111 (substrate_entity) ─► RM-112 (type paths)
                                             ─► RM-113 (linearity table)
                                             ─► RM-114 (per-store rewrites — 6/8 since deleted by D-RTC.4) ─► RM-115 (migration tool)
                                                                            ─► RM-116 (conformance sweep)
RM-118 (CLOSED: octave-pointer subsystem, parked) ─╴╴╴ gates ╴╴╴► RM-117 (CLOSED-BLOCKED: delete entity_cell — parked)
```

**Wave-10 cell-format-migration line: terminal.** RM-110–RM-116 shipped. RM-117/RM-118 are correctly closed-blocked with the backstop documented. Nothing here is an open TODO.

### RM-090 — Reducer emits per-pass trace events
- **Source:** new (Wave 9)
- **Depends on:** RM-030 (reducer pass list stable)
- **Read first:**
  - `runtime/intent/src/reducer/index.ts` (PASSES loop, `passResults: PassResult[]` accumulation at lines 60–74)
  - `runtime/intent/src/reducer/types.ts` (`PassResult` interface — already has `pass`, `contribution`, `confidence`, `flags`)
  - `runtime/intent/src/logger.ts` (JSONL emit pattern, `StageEventBase`)
  - `runtime/intent/src/pipeline.ts:97-141` (`runStage` + `emit` reference)
- **Create:** none
- **Edit:**
  - `runtime/intent/src/reducer/types.ts` — extend `ReducerOptions` with optional `{ logger, correlationId, intentId? }`.
  - `runtime/intent/src/reducer/index.ts` — emit `reducer_pass_completed` per pass with `{ pass, confidence, flags, contributionKeys, durationMs }`. Data already exists; this is pure plumbing (~20 LOC).
- **Accept:** New test in `runtime/intent/src/__tests__/reducer-trades.test.ts` uses `createInMemoryLogger()` and asserts the dripping-tap fixture emits exactly 10 `reducer_pass_completed` events in pass order. Existing reducer tests still pass.

### RM-091 — Producers emit `intent_produced` with shared correlationId
- **Source:** new (Wave 9)
- **Depends on:** —
- **Read first:**
  - `runtime/intent/src/pipeline.ts:130-148` (current correlationId resolution: `intent.correlationId ?? ctx.correlationId ?? deps.uuid()`)
  - `runtime/intent/src/voice/voice-session.ts` (voice producer surface)
  - `runtime/shell/src/intent-adapters/shell-to-intent.ts` (shell producer)
  - Find oddjobz adapter that calls `reduceToIntent`: `grep -rn 'reduceToIntent' extensions/ apps/`
  - `runtime/intent/src/types.ts` (`Intent.correlationId` typing)
- **Create:** none
- **Edit:**
  - Each producer call site: generate `correlationId` once at the producer boundary, emit `intent_produced` with `{ source, rawInputDigest, intentId }`, pass the same `correlationId` to the reducer (RM-090 logger options) and onto the returned `Intent`.
  - `runtime/intent/src/types.ts` — document that `Intent.correlationId` SHOULD be set by producers; pipeline still tolerates absence by minting one.
- **Accept:** Gates test traces a voice-session → reducer → `processIntent` run end-to-end and asserts all events on the JSONL stream share a single `correlationId`. No orphan events.

### RM-092 — Candidate-set surfacing in rhetoric & relation passes
- **Source:** new (Wave 9)
- **Depends on:** RM-090
- **Read first:**
  - `runtime/intent/src/reducer/rhetoric-pass.ts`
  - `runtime/intent/src/reducer/relation-pass.ts` (R9 test already asserts "highest-confidence wins" — internal ranking exists, just isn't exposed)
  - `runtime/intent/src/reducer/__tests__/relation-pass.test.ts:R9`
  - `runtime/intent/src/reducer/types.ts` (`PassResult`)
- **Create:** none
- **Edit:**
  - `runtime/intent/src/reducer/types.ts` — add optional `alternatives?: ReadonlyArray<{ candidate: unknown; confidence: number; reason: string }>` to `PassResult`.
  - `rhetoric-pass.ts` + `relation-pass.ts` — populate `alternatives` whenever >1 binding scores above zero. Bound to a small constant (e.g. top 5) to keep traces compact.
  - RM-090 emitter — include `alternatives.length` in the per-pass event payload; full alternatives stay on the `PassResult` for in-process consumers.
- **Accept:** Extended R9 in `relation-pass.test.ts` asserts the losing candidates appear in `alternatives` ordered by descending confidence, all strictly below the winner. Closes the "silent collapse" failure mode flagged in the Wave 9 design discussion.

### RM-093 — CLI intent-trace viewer
- **Source:** new (Wave 9)
- **Depends on:** RM-090, RM-091
- **Read first:**
  - `runtime/intent/src/logger.ts` (JSONL event shape)
  - `tools/release/` (existing CLI-binary package conventions)
  - `runtime/semantos-brain/` cli.zig modularize pattern (memory: `semantos_cli_modularize_pattern.md`) — for command registration style
  - One captured JSONL trace (or generated via existing pipeline tests) to anchor the renderer's golden output
- **Create:**
  - `tools/intent-trace/` — new TS package, bin entry `intent-trace`. Subcommands: `tail <file|->`, `show <correlationId>`, `cascade <file>` (renders producer → 10 reducer passes → SIR → script → cells → result as an indented tree with per-stage durations and flags).
- **Edit:** none
- **Accept:** Piping a captured fixture-derived trace through `intent-trace cascade` produces a stable golden output checked into the package's tests. Rejection paths render the short-circuit event with its reason.

### RM-094 — Trace-to-fixture transform
- **Source:** new (Wave 9)
- **Depends on:** RM-093
- **Read first:**
  - `runtime/intent/src/__tests__/reducer-trades.test.ts` (current fixture shape)
  - `runtime/intent/src/reducer/__fixtures__/trades-fixtures.ts` (fixture inputs)
  - `tests/gates/intent-pipeline.test.ts` (G1–G7 gate assertion style)
- **Create:**
  - `tools/intent-trace/src/to-fixture.ts` — JSONL trace → TS fixture file. Output replays the producer input through `reduceToIntent` + `processIntent` and asserts the same event sequence (event types + ordering + key payload fields, ignoring durations and correlation IDs).
- **Edit:** none
- **Accept:** Capture a real trace, run `intent-trace fixturize trace.jsonl > regression.test.ts`, `bun test regression.test.ts` passes. Deliberately mutate `rhetoric-pass.ts` so the trade-categorisation flips; the regression test fails with a meaningful diff naming the offending pass.

### RM-095 — Re-run from stage with mutated payload
- **Source:** new (Wave 9)
- **Depends on:** RM-094
- **Read first:**
  - `runtime/intent/src/pipeline.ts` (`PipelineDeps` injection surface; current single entry point `processIntent`)
  - `runtime/intent/src/reducer/index.ts` (per-pass loop)
- **Create:**
  - `tools/intent-trace/src/replay.ts` — loads a JSONL trace, accepts `--from <stage>` + `--override <stage>=<jsonPath>` flags, replays forward using existing `PipelineDeps` stubs.
- **Edit:**
  - `runtime/intent/src/pipeline.ts` — add `runFromStage(stage, overriddenInput, ctx, deps)` if the existing single-entry API doesn't support partial replay. Keep it a thin re-entry point — do NOT duplicate stage logic. (See no-hardcoded-workarounds rule.)
- **Accept:** Test takes the dripping-tap trace, overrides the rhetoric-pass output to a different action, replays from `sir_built`, asserts a different `script_executed` event is emitted. The original pipeline path still emits the original sequence on an un-mutated replay.

### RM-096 — Typed cell signatures for cartridge authors
- **Source:** new (Wave 9)
- **Depends on:** RM-010 (`core/scg-relations` stable), RM-022 (capability binding)
- **Read first:**
  - `core/scg-relations/src/types.ts` (relation shape devs author against)
  - `core/cell-ops/src/opcodes.ts` (current cell-op definitions)
  - `core/cell-engine/src/opcodes/plexus.zig` (kernel-side opcode contract, for ground truth on stack effects)
  - `core/pask/bindings/ts/` (dev-facing pask surface)
- **Create:**
  - `core/cell-ops/src/cell-signature.ts` — typed pre/post stack-shape declaration helper. Cell authors declare `defineCell({ pre: [...], post: [...], body: ... })`; composition type-errors at the TS layer when a cell's `post` doesn't satisfy the next cell's `pre`.
- **Edit:**
  - `core/cell-ops/src/opcodes.ts` — annotate each existing opcode entry with its stack signature. No runtime change; types-only.
- **Accept:** Positive test composes two compatible cells and type-checks. Negative test (in `__tests__/cell-signature.test.ts` with `// @ts-expect-error`) asserts incompatible composition is a compile-time error. The cartridge author's dev surface (Wave 1 cartridge consumers) gains stack-shape autocomplete.

### RM-097 — Voice-note → cartridge dogfood loop
- **Source:** new (Wave 9) — driven by Todd's own dev workflow
- **Depends on:** RM-091, RM-093, RM-011 (`core/experience-cartridge`)
- **Read first:**
  - `runtime/intent/src/voice/voice-session.ts`
  - Voice-notes workflow per memory (`voice_notes_workflow.md`): two paths — capture-time-bound + inferred-from-content
  - `runtime/semantos-brain/` CLI surface (cli.zig modularize pattern)
  - `tools/release/` for bin-script + package conventions
- **Create:**
  - `tools/cartridge-scaffold/` — `brain cartridge new <name>` produces a working cartridge skeleton with: sample cells (using RM-096 typed signatures if landed), a fixture from the latest captured trace, and a regression test (using RM-094 trace-to-fixture).
- **Edit:** none
- **Accept:** Single-take loop: Todd records a voice note → `brain intent tail` (RM-093) shows the cascade → `brain intent fixturize --last` writes a fixture → `brain cartridge new <name> --from-fixture` scaffolds a cartridge → `bun test` against the new cartridge passes. Wall-clock under 60s for the minimal happy path. This becomes the canonical "is the dev loop healthy?" smoke test.

---

## Cross-cutting reads (read once, reference often)

These don't belong to any single item but every contributor should have skimmed them:

- `core/protocol-types/src/cell-header.ts` — header layout and the entry point for understanding what's "above" vs "below" the kernel
- `core/semantic-objects/src/schema.ts` — `sem_objects`, `sem_object_patches`, `sem_participants` (the existing graph substrate)
- `core/cell-engine/src/opcodes/plexus.zig` — Plexus opcode ranges 0xC0–0xCF (`OP_CHECKLINEARTYPE` 0xC0, `OP_CHECKAFFINETYPE` 0xC1, `OP_CHECKRELEVANTTYPE` 0xC2, `OP_CHECKCAPABILITY` 0xC3, `OP_CHECKIDENTITY` 0xC4, `OP_ASSERTLINEAR` 0xC5, `OP_CHECKDOMAINFLAG` 0xC6, `OP_CHECKTYPEHASH` 0xC7, `OP_DEREF_POINTER` 0xC8, `OP_READHEADER` 0xC9, `OP_CELLCREATE` 0xCA, `OP_DEMOTE` 0xCB, `OP_READPAYLOAD` 0xCC, `OP_SIGN` 0xCD, `OP_DECREMENT_BUDGET` 0xCE, `OP_REFILL_BUDGET` 0xCF) and 0xD0 `OP_CALLHOST` (host dispatch — `core/cell-engine/src/opcodes/hostcall.zig`)
- `core/cell-engine/src/executor.zig` — bounded-execution invariants (`MAX_SCRIPT_SIZE`, `DEFAULT_MAX_OPS`)
- `core/cell-engine/src/host.zig` — host fetch contract (the trust boundary for cross-cell reads)
- `core/semantos-sir/src/types.ts` — SIR primitives
- `core/semantos-sir/src/lexicons.ts` — lexicon registration pattern
- `runtime/intent/src/pipeline.ts` — `processIntent`, the orchestrator for the full NL → 2PDA gradient
- `runtime/intent/src/reducer/index.ts` — reducer pass list and ordering
- `core/identity-ports/src/ports.ts` — the four identity ports (identityPort, recoveryPort, attestationPort, capabilityPort)
- `outputs/scg-implementation-tracking.md` — SCG spec
- `outputs/phase-h-header-cleanup-spec.md` — Phase H spec

---

## Status board

| ID | Wave | Title | Status |
|---|---|---|---|
| RM-000 | 0 | Re-audit on current branch | [ ] |
| RM-001 | 0 | Decide: hard cut vs compat reader | [ ] |
| RM-002 | 0 | Decide: production commerce data exists? | [ ] |
| RM-003 | 0 | Decide: schema authority | [ ] |
| RM-004 | 0 | Allocate flag slots | [ ] |
| RM-005 | 0 | Decide: SCG grammar signing identity | [ ] |
| RM-010 | 1 | `core/scg-relations` package | [ ] |
| RM-011 | 1 | `core/experience-cartridge` package | [ ] |
| RM-012 | 1 | `core/plexus-schema-registry` package | [ ] |
| RM-020 | 2 | SIR relation constraint variant | [ ] |
| RM-021 | 2 | SCG grammar + manifest | [ ] |
| RM-022 | 2 | SCG capability binding | [ ] |
| RM-023 | 2 | `domainPayloadRoot` header slot | [ ] |
| RM-030 | 3 | Intent reducer relation pass | [ ] |
| RM-031 | 3 | Conversation lift to `core/conversation-graph` | [ ] |
| RM-032 | 3 | Strip commerce fields from header | [ ] |
| RM-040 | 4 | SCG Phase 1 tests + E2E | [ ] |
| RM-041 | 4 | Commerce-consumer migration | [ ] |
| RM-042 | 4 | Decommission `OnChainBinding` | [ ] |
| RM-050 | 5 | Kernel rebuild + ABI bump V2 | [ ] |
| RM-051 | 5 | Reddit projection | [x] library |
| RM-052 | 5 | Stream projection | [x] library |
| RM-053 | 5 | Oddjobz regression gate | [x] |
| RM-060 | 6 | Money-bearing relation kinds | [x] |
| RM-061 | 6 | Wallet / anchor audit | [ ] deferred |
| RM-062 | 6 | `EconomicPort` | [x] |
| RM-063 | 6 | 402-style access gate | [x] |
| RM-070 | 7 | Semantic retrieval surface | [x] structural |
| RM-071 | 7 | Agent rewiring | [ ] deferred |
| RM-080 | 8 | Branching | [x] |
| RM-081 | 8 | Governance projection | [ ] deferred |
| RM-082 | 8 | Schema-driven relation cells | [x] schema-half |
| RM-090 | 9 | Reducer emits per-pass trace events | [x] |
| RM-091 | 9 | Producers emit `intent_produced` + shared correlationId | [x] |
| RM-092 | 9 | Candidate-set surfacing in rhetoric/relation | [x] |
| RM-093 | 9 | CLI `intent-trace` viewer | [x] |
| RM-094 | 9 | Trace-to-fixture transform | [x] |
| RM-095 | 9 | Re-run from stage with mutated payload | [x] |
| RM-096 | 9 | Typed cell signatures for cartridge authors | [x] |
| RM-097 | 9 | Voice-note → cartridge dogfood loop | [x] |

---

## Sequencing notes

**The fastest critical path to Phase 1 working off-kernel** (no kernel changes needed): RM-000 → RM-004 → RM-010 → (RM-020 ∥ RM-021 ∥ RM-022) → RM-030 → RM-031 → RM-040. Wave 5 rendering follows.

**Phase H runs as its own current** in parallel to the SCG critical path: RM-000 → RM-001/002/003 → RM-012 → RM-023 → RM-032 → RM-041 / RM-042 → RM-050. Until RM-050 lands, SCG Wave 8 is blocked.

**Two engineers, rough split:** one drives the SCG path (RM-010, 011, 020, 021, 022, 030, 031, 040, 051–053), the other drives Phase H (RM-012, 023, 032, 041, 042, 050). They sync at RM-082 in Wave 8.

**One engineer**: do RM-012 before RM-010 if you want Phase H out of the way first (schema registry is greenfield and self-contained). Otherwise do RM-010 first and you have a shippable SCG Phase 1 before any header touching.

**Wave 9 entry point:** RM-090 + RM-091 are the unlock — both touch existing instrumented surfaces and produce immediate value (the JSONL stream becomes useful for debugging *today*, not just for the future viewer). RM-093 (CLI viewer) gives the first visible payoff. RM-094 → RM-095 is the time-travel debugger. RM-096 + RM-097 are an independent sub-track that can start whenever Wave 1 cartridge consumers are stable; doing them last is fine since they're about dev-loop *speed*, not pipeline *visibility*.

**Honest scope estimate for Wave 9:** ~1 week for RM-090..093 (instrumentation + viewer); +3–5 days for RM-094..095 (fixture transform + replay); RM-096 and RM-097 are larger because they require touching cartridge author surfaces, treat as 1–2 weeks each. Total wave: ~4–5 weeks of solo work, with RM-090..093 deliverable inside a single push.
