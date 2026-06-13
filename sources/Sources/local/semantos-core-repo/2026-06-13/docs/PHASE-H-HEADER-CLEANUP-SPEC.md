---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/PHASE-H-HEADER-CLEANUP-SPEC.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.334132+00:00
---

# Phase H — Cell Header Cleanup & Plexus Domain Schema Registry

**Type:** Protocol refactor + new platform capability
**Repo:** `/Users/toddprice/projects/semantos-core`
**Owner:** Todd Price
**Status:** Drafted, not started
**Independence:** Standalone. Not blocked by SCG. Required prerequisite for SCG Phase 5, but Phase H has independent architectural value.

---

## 1. Executive summary

The cell header at `core/protocol-types/src/cell-header.ts` is 256 bytes. Sixty-six of those bytes (offsets 94–159) are hardcoded to commerce-domain semantics: `commercePhase`, `commerceDimension`, `commerceParentHash`, `commercePrevState`. Another ninety-six bytes (160–255) are reserved for an unused `OnChainBinding` region (`txid`, `vout`, `bumpHash`, `derivationIndex`). The 2PDA kernel does not read any of these fields — they are opaque bytes to Zig — yet they commit the protocol to specific domain meaning at a layer that should be domain-agnostic.

Phase H removes them, introduces a Plexus-resident **domain schema registry** that maps `domain_flag → payload field layout`, and replaces the stripped fields with one generic `domainPayloadRoot: u256` slot that binds payload bytes to the header under whatever schema the cell's domain selects. The header shrinks from 256 bytes of mixed-concern layout to ≤128 bytes of kernel-protocol fields plus one bound digest. Commerce semantics migrate to a payload schema registered at Plexus under `domain_flag = COMMERCE`. Recovery works because schemas are persisted under the vendor identity in the same store as the certs.

The kernel doesn't change. No new opcodes, no Zig logic touched beyond removing dead getter/setter pairs. Verification of "this cell's payload matches what was committed" uses existing `OP_CHECKTYPEHASH` + `OP_CHECKDOMAINFLAG` + payload-digest composite predicates that any extension can author.

---

## 2. Problem statement

### 2.1 Symptom
The cell header bakes commerce-specific fields into the protocol structure. Every future domain (governance, SCG relations, escrow, attestation) either has to similarly bake its fields into the header — bloating it further and forcing breaking changes — or hack around the commerce slots by overloading them via flag bits. Both options are wrong; the header should be domain-agnostic and let the domain flag select the interpretation.

### 2.2 Audit findings

A targeted audit of the codebase produced these facts:

**Kernel does not read commerce fields.** `core/cell-engine/src/commerce.zig` treats the 162-byte region (bytes 94–255) as an opaque reserved block accessed via `getCommerceExtension` / `setCommerceExtension`. The executor in `core/cell-engine/src/executor.zig` does not dispatch on `phase` or `dimension`. No opcode in the 0xC0–0xCF range reads commerce data.

**TypeScript does not read commerce fields by name in production.** `serializeCellHeader` and `deserializeCellHeader` in `core/protocol-types/src/cell-header.ts` (lines 89–92, 129–132) write and read them. `core/cell-ops/src/typeHashRegistry.ts::buildCellHeader` (lines 224–227 and 245+) constructs them. Test fixtures (`cell-packer.test.ts`, `cell-verifier.test.ts`) set them. No production reader treats `commercePhase` / `commerceDimension` / `commerceParentHash` / `commercePrevState` as semantically meaningful fields.

**The `OnChainBinding` region is unused in production.** Bytes 160–255 are declared in `core/protocol-types/src/cell-header.ts` (lines 51–56) for `txid`, `vout`, `bumpHash`, `derivationIndex` and wrapped by `core/cell-engine/src/commerce.zig` accessors, but never written or read outside test scaffolding.

**No domain-schema registry exists.** `core/plexus-contracts/src/domain-flags.ts` declares flag constants (`EDGE_CREATION=1`, `SIGNING=2`, etc.) but does not associate them with field layouts. `core/plexus-vendor-sdk/src/store.ts` has a `domain_flag` column on the cert table but no per-domain payload-schema lookups. The schema-descriptor table is the missing piece.

**Blast radius is small.** Roughly 11–15 files touched, almost all serialization and tests. No kernel changes. Effort is low to moderate; biggest single work item is designing the schema registry, which is greenfield.

### 2.3 Why now

The architectural cost compounds with every new domain. SCG's Phase 5 already had to design around this — earlier drafts proposed `flags`-bit hacks and 16B truncated roots to fit relation semantics into the commerce-shaped header. Those workarounds become unnecessary the moment commerce moves out. Doing the cleanup now spares every future domain the same negotiation.

---

## 3. Design

### 3.1 Slim header

The post-refactor `CellHeader` carries only protocol-level fields the kernel reads or that bind the cell's identity:

| Field | Size | Offset | Notes |
|---|---|---|---|
| `magic` | 16 | 0 | Existing |
| `linearity` | 4 | 16 | Existing — read by `OP_CHECKLINEARTYPE` |
| `version` | 4 | 20 | Existing |
| `flags` | 4 | 24 | Existing |
| `domain_flag` | 4 | 28 | Existing — read by `OP_CHECKDOMAINFLAG`; now also selects the payload schema |
| `refCount` | 2 | 32 | Existing |
| reserved | 2 | 34 | alignment |
| `typeHash` | 32 | 36 | Existing — read by `OP_CHECKTYPEHASH` |
| `ownerId` | 16 | 68 | Existing |
| `timestamp` | 8 | 84 | Existing |
| `cellCount` | 4 | 92 | Existing |
| `totalSize` | 4 | 96 | Existing |
| `domainPayloadRoot` | 32 | 100 | **New** — full 32B SHA-256 over payload bytes per the domain's schema |
| reserved | 124 | 132 | free for future protocol fields |

Total kernel-protocol header: 132 bytes. Reserved-for-future region: 124 bytes. Header total stays 256 bytes for layout stability, but byte 132 onwards is explicitly reserved-free, not domain-allocated.

Offsets above are illustrative; actual offsets land during the constants regeneration in §4.2. The constraint is: every field the kernel reads stays at a fixed offset (kernel opcodes are hardcoded against `constants.zig`), and `domain_flag` keeps its kernel-readable position so `OP_CHECKDOMAINFLAG` still works.

### 3.2 Plexus domain schema registry

A new package `core/plexus-schema-registry` holds the mapping `(domain_flag, version) → DomainSchema`. A `DomainSchema` is a descriptor listing the payload's fields:

```
DomainSchema {
  domainFlag: u32
  version: u32
  fields: FieldDescriptor[]      // ordered, packed layout
  commitmentMode: 'payload-digest' | 'merkle-root'
  signature?: Sig                // signed by the schema authority
}

FieldDescriptor {
  name: string
  offset: u32                    // within payload
  size: u32
  type: 'u8' | 'u16' | 'u32' | 'u64' | 'u256' | 'bytes' | 'utf8'
}
```

Schemas are:
- **Registered** at domain-flag allocation time (atomically, in the same transaction — §6.4).
- **Persisted** under the vendor identity via `core/plexus-vendor-sdk/src/store.ts` so they're part of the recoverable identity bundle.
- **Versioned** independently so a domain can add fields without breaking old cells; `OP_CHECKTYPEHASH` already pins each cell to a specific type hash that encodes the schema version.
- **Signed** by a schema authority (likely the domain owner's `Brc52Cert`), borrowing the existing `LexiconAuthority` pattern from `core/semantos-sir/src/authority.ts`.

### 3.3 `domainPayloadRoot`

Computed at cell creation as a hash over the payload bytes, where the payload bytes are laid out per the schema for the cell's `(domain_flag, version)`. Stored at a fixed offset in the header so existing kernel opcodes can compare it via stack ops. Verification is a composite predicate:
1. `OP_CHECKDOMAINFLAG` — cell is the expected domain.
2. `OP_CHECKTYPEHASH` — type hash matches (encodes the schema version).
3. Push the payload onto the stack as a witness.
4. Hash the witness, compare to `domainPayloadRoot` via existing hash/compare ops.
5. Read fields from the witness at offsets declared by the schema.

The kernel verifies the binding (the witness matches what the header committed to) without knowing the schema. The schema is consulted off-kernel by the script author or by domain-aware tooling.

### 3.4 Anchoring becomes its own cell type

The `OnChainBinding` region (`txid`, `vout`, `bumpHash`, `derivationIndex`) is stripped from the header. Anchoring a cell on-chain produces an `AnchorAttestation` cell whose payload binds `(target_cell_id, txid, vout, bumpHash, derivationIndex)`. Anchoring becomes a relation rather than a header field. Symmetric with SCG, and avoids burning 96 header bytes on a feature that not every cell will use.

---

## 4. Phased plan

### 4.0 Sequencing

Strict ordering by dependency:

```
H.1 schema registry  ──►  H.2 domainPayloadRoot  ──►  H.3 strip commerce  ──►  H.4 migrate consumers
                                                                                      │
                                                                                      ▼
                                                                              H.5 decommission OnChainBinding
                                                                                      │
                                                                                      ▼
                                                                              H.6 kernel rebuild + ABI bump
```

H.5 can move in parallel with H.4 if owners differ. H.6 must be last — it's the kernel WASM rebuild + manifest regen that locks the new layout.

### 4.1 H.1 — `core/plexus-schema-registry` (new package)

**Greenfield. No dependencies.**

Files to create:
- `core/plexus-schema-registry/src/types.ts` — `DomainSchema`, `FieldDescriptor`, `SchemaLookupKey`.
- `core/plexus-schema-registry/src/registry.ts` — `SchemaRegistry { register(schema): RegisterResult; lookup(flag, version): DomainSchema | null; list(): DomainSchema[]; verify(schema): VerifyResult }`. In-memory primary store with persistence callback.
- `core/plexus-schema-registry/src/persistence.ts` — adapter to `core/plexus-vendor-sdk/src/store.ts`. CRUD via a new `domain_schemas` SQLite table.
- `core/plexus-schema-registry/src/encoding.ts` — `encodePayload(schema, fields) → Uint8Array`, `decodePayload(schema, bytes) → Record<string, unknown>`. Endianness and packing rules.
- `core/plexus-schema-registry/src/hash.ts` — `computeDomainPayloadRoot(schema, fields) → Uint8Array` (32B SHA-256 over the encoded payload).
- `core/plexus-schema-registry/schemas/index.ts` — barrel for built-in schemas (commerce, anchor, scg-relation).
- `core/plexus-schema-registry/__tests__/round-trip.test.ts` — encode then decode is identity; root matches across implementations.
- `core/plexus-schema-registry/__tests__/recovery.test.ts` — register schema, persist, evict in-memory, restore from store, lookup succeeds.
- `core/plexus-schema-registry/__tests__/signature.test.ts` — schema with valid `LexiconAuthority`-style signature accepts; tampered schema rejects.
- `core/plexus-schema-registry/package.json`, `tsconfig.json`, vitest config — match sibling `core/*` conventions.

Edits:
- `core/plexus-vendor-sdk/src/store.ts` — add `domain_schemas` table with columns `(domain_flag, version, fields_json, commitment_mode, signature, created_at)`. CRUD via the registry's persistence adapter, not direct.
- `core/plexus-contracts/src/domain-flags.ts` — add a JSDoc note that flag allocation must now register a schema in the same transaction. Add `SCHEMA_AUTHORITY` flag constant for self-describing schemas.

Acceptance:
- A schema can be registered, persisted, evicted from memory, restored from disk, looked up by `(flag, version)`, and produces a deterministic `domainPayloadRoot` for a given field set across two independent encodings.

### 4.2 H.2 — Generic `domainPayloadRoot` header slot

**Depends on H.1.**

Edits:
- `core/constants/constants.json` — add `domainPayloadRoot` offset + size (32B). Leave the commerce keys in place for one PR (overlap window) so H.3 can run independently.
- Run `bun run generate-constants` to regenerate `core/protocol-types/src/constants.ts` and `core/cell-engine/src/constants.zig`.
- `core/protocol-types/src/cell-header.ts` — add `domainPayloadRoot: Uint8Array` (32B) to `CellHeader`. Update `serializeCellHeader` to write the new field and `deserializeCellHeader` to read it.
- `core/cell-engine/src/cell.zig` — add `getDomainPayloadRoot` / `setDomainPayloadRoot` accessors. Do not yet remove `getCommerceExtension` / `setCommerceExtension` (that's H.3).
- `core/cell-ops/src/cellPacker.ts` — on pack, accept an optional `domainSchemaContext` arg; if provided, compute the root via `computeDomainPayloadRoot` from §4.1 and write it to the header. On unpack, expose the root for verifier predicates.

Acceptance:
- A round-trip: pack a cell with a registered schema, verify `serializeCellHeader → deserializeCellHeader` preserves `domainPayloadRoot` bit-exactly. Compute the root independently from payload + schema and confirm it matches.

### 4.3 H.3 — Strip commerce fields from the header

**Depends on H.2.**

Edits:
- `core/constants/constants.json` — remove `commercePhase`, `commerceDimension`, `commerceParentHash`, `commercePrevState` and their `*Size` entries (lines 74–79 per the audit). Regenerate.
- `core/protocol-types/src/cell-header.ts` — remove `commercePhase`, `commerceDimension`, `commerceParentHash`, `commercePrevState` from `CellHeaderLayout` (lines 21–24) and from the `CellHeader` interface (lines 38–41). Remove the `CommerceExtension` interface (lines 44–49). Strip the commerce-write block from `serializeCellHeader` (lines 89–92) and the commerce-read block from `deserializeCellHeader` (lines 129–132).
- `core/cell-ops/src/typeHashRegistry.ts` — drop `phase`, `dimension`, `parentHash`, `prevStateHash` from the mirrored `CellHeader` interface (lines 224–227) and from `buildCellHeader`.
- `core/cell-engine/src/commerce.zig` — delete file.
- `core/cell-engine/src/cell.zig` — remove `getCommerceExtension` / `setCommerceExtension`.
- Register the migrated commerce schema: add `core/plexus-schema-registry/schemas/commerce.ts` declaring `{ domainFlag: COMMERCE, version: 1, fields: [{name: 'phase', offset: 0, size: 1, type: 'u8'}, {name: 'dimension', offset: 1, size: 1, type: 'u8'}, {name: 'parentHash', offset: 2, size: 32, type: 'u256'}, {name: 'prevStateHash', offset: 34, size: 32, type: 'u256'}], commitmentMode: 'payload-digest' }`.

Acceptance:
- Header total kernel-protocol bytes ≤ 132. The 256-byte total is preserved, with bytes 132–255 explicitly reserved-free (documented in `CellHeader` jsdoc).
- A commerce cell constructed via the new pattern (payload-encoded under the registered schema) round-trips and produces the same `domainPayloadRoot` deterministically.
- All existing test suites green.

### 4.4 H.4 — Migrate commerce consumers

**Depends on H.3.**

The audit found no production reads of commerce fields by name, but the codebase has test fixtures and the `buildCellHeader` test helper that populate them. Migrate:

- `core/cell-ops/src/typeHashRegistry.ts::buildCellHeader` — replace `phase` / `dimension` / `parentHash` / `prevStateHash` arguments with a `domainPayload?: Uint8Array` argument. Callers that previously passed structured commerce fields now construct a payload via the commerce schema's `encodePayload`.
- `core/protocol-types/__tests__/cell-packer.test.ts` and friends — rework fixtures to use the schema-encoded payload form.
- `core/protocol-types/__tests__/cell-verifier.test.ts` — same.
- Any other test that constructs a `CellHeader` with hardcoded commerce values — sweep with `grep -r "commercePhase\\|commerceDimension\\|commerceParentHash\\|commercePrevState" core/ runtime/ extensions/ apps/ tests/` before opening the PR.

Acceptance:
- Full test matrix green.
- No grep hits for the four field names anywhere outside the deleted files.

### 4.5 H.5 — Decommission `OnChainBinding`

**Can run in parallel with H.4. Depends on H.3 (for header layout being stable post-strip).**

Recommended path (option (b) from earlier scoping): anchoring becomes its own cell type.

Files to create:
- `core/anchor-attestation/src/types.ts` — `AnchorAttestation { targetCellId: u256; txid: u256; vout: u32; bumpHash: u256; derivationIndex: u32 }`.
- `core/anchor-attestation/src/operations.ts` — `createAnchorAttestation`, `verifyAnchor` (uses BSV BUMP/BEEF logic already in `core/cell-ops/src/cellPacker.ts`).
- `core/plexus-schema-registry/schemas/anchor-attestation.ts` — declare the schema under `domain_flag = ANCHOR_ATTESTATION`.

Edits:
- `core/constants/constants.json` — remove the 160–255 binding-region keys (`txid`, `vout`, `bumpHash`, `derivationIndex` and their `*Size` entries).
- `core/protocol-types/src/cell-header.ts` — remove the `OnChainBinding` interface (lines 51–56).
- `core/cell-engine/src/cell.zig` — remove `getOnChainBinding` / `setOnChainBinding`.
- `core/cell-engine/src/commerce.zig` — already deleted in H.3. If any binding-specific Zig logic lived there, port the BUMP/BEEF logic into a new `core/cell-engine/src/anchor.zig` if needed (or keep entirely off-kernel since anchoring is verified off-kernel anyway).

Acceptance:
- Header free region grows to bytes 132–255 (124 bytes reserved-free).
- An `AnchorAttestation` cell can be constructed, persisted, and verified end-to-end. The original cell is anchored not by mutating its header but by pointing an attestation cell at it.

### 4.6 H.6 — Kernel rebuild + ABI bump

**Depends on H.1–H.5.**

Edits:
- `core/cell-engine/src/constants.zig` — bump `VERSION: u32 = 2`.
- Run `core/cell-engine/scripts/reproducible-build.sh` to regenerate the WASM binary, `WASM-MANIFEST.json` SHA-256, and any baked-in artefacts.
- Update `core/cell-engine/proof-artifacts/` — regenerate proofs that depend on header layout.
- Update `core/cell-engine/test-vectors/` — fixtures whose hashes depend on the old header bytes need new vectors.
- Re-run `core/cell-engine/fuzz/plexus_atomic_fuzz.zig` to confirm the K4 invariant (failed ops leave stack unchanged) still holds against the new constants.

Acceptance:
- Kernel rebuilds reproducibly. New `WASM-MANIFEST.json` published. All fuzz suites green at 50k iterations.

---

## 5. What does NOT change

To bound scope explicitly:

- **No new opcodes.** The 0xC0–0xCF range is untouched.
- **Existing opcodes unchanged.** `OP_CHECKLINEARTYPE`, `OP_CHECKCAPABILITY`, `OP_CHECKDOMAINFLAG`, `OP_CHECKTYPEHASH`, `OP_DEREF_POINTER`, `OP_CALLHOST` all keep their current semantics. They get one more thing to read against — `domainPayloadRoot` — but read it via the same stack-bytes mechanism as everything else.
- **No change to identity ports.** Phase H is below the identity layer.
- **No change to `sem_objects` schema.** Phase H is below `core/semantic-objects`.
- **No change to the reducer pipeline.** Phase H is below `runtime/intent`.

This is purely a protocol-layer cleanup with a new sibling capability (the schema registry).

---

## 6. Cross-cutting concerns

### 6.1 Header version & kernel ABI

The kernel currently exposes a single global `VERSION: u32 = 1` in `core/cell-engine/src/constants.zig`. Phase H is a layout-changing event and **must** bump to `VERSION = 2`. The dispatcher's `else => unreachable` posture means an old kernel hitting a new cell crashes hard.

Two policies for the cutover:
- **Hard cut.** Set a date; after that date, only new-format cells are produced and all kernels are required to be V2. Simpler but requires coordinated rollout.
- **Compat reader.** Ship a transitional `deserializeCellHeader` that detects the old layout (e.g., by magic bytes or version field) and lifts old cells into the new in-memory shape, with no commitment to writing them. New cells always written in V2. After all old cells age out, drop the reader.

Recommend hard cut if there's no production data; compat reader if commerce cells exist in the wild.

### 6.2 Recovery story

Schemas are recoverable iff they're backed up under the vendor identity *before* the key is lost. §4.1's `core/plexus-schema-registry/src/persistence.ts` writes to `core/plexus-vendor-sdk/src/store.ts`; the existing identity backup mechanism must include the `domain_schemas` table. Verify with `core/plexus-vendor-sdk/src/store.ts`'s backup-and-restore harness before §4.1 lands.

Make schema-registration and domain-flag-allocation atomic: a domain flag exists in `core/plexus-contracts/src/domain-flags.ts` **if and only if** a schema is registered in the registry. This rules out the failure mode where a key holds capabilities under a flag whose schema is lost.

### 6.3 Determinism

`domainPayloadRoot` must be computed deterministically across implementations. Pin:
- Endianness (little-endian throughout, matching existing kernel convention).
- Field ordering (schema's declared order, no implicit sorts).
- Padding (explicit; if a schema declares overlapping or sparse offsets, validation rejects at registration time).
- Hash function: SHA-256 unless the kernel grows another hash primitive.

`core/plexus-schema-registry/src/hash.ts` should expose a test-suite of cross-implementation vectors so a Zig or Rust reimplementation can be verified.

### 6.4 Schema versioning rules

- Adding fields at the end of a schema's payload requires a new `version` and a new `typeHash`. Existing cells reference the old version's type hash and remain valid.
- Reordering, removing, or changing the type of any existing field is a breaking change — register a new schema as a new domain, not as a new version of the existing one.
- The registry's `verify(schema)` enforces these rules at registration time.

### 6.5 Performance budgets

- Schema lookup: ≤ 1µs in-memory after warm; ≤ 50µs cold from SQLite.
- `computeDomainPayloadRoot` for a 1KB payload: ≤ 100µs.
- `serializeCellHeader` / `deserializeCellHeader`: must not regress from current p99.

---

## 7. Risk register

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| H-R1 | Unaudited commerce consumer breaks after strip | L | M | Pre-PR re-audit on the actual branch (grep all four field names across core/, runtime/, extensions/, apps/, tests/). Full test matrix before merge. |
| H-R2 | Schema registry recovery fails — vendor backup missed `domain_schemas` table | M | H | Schema persistence (§4.1) lands *before* any domain registers; atomic flag-allocation + schema-registration; backup harness covers the new table. |
| H-R3 | Production commerce data exists and fails verification post-cut | M | M | Audit before H.3 PR. If data exists: ship one-time migration that re-encodes existing commerce cells under the registered schema and recomputes their `domainPayloadRoot`. Otherwise green-field cut. |
| H-R4 | Kernel ABI bump (V1 → V2) catches an in-flight integration off-guard | M | M | Coordinate kernel version bump with downstream teams; ship compat reader during transition window (§6.1). |
| H-R5 | Schema-version drift between two clients of the same domain | L | M | `typeHash` already pins each cell to a specific schema version. Mismatched versions fail `OP_CHECKTYPEHASH`. |
| H-R6 | `domainPayloadRoot` collision allows payload substitution | L | H | Full 32B SHA-256, no truncation. Standard cryptographic assumption. |
| H-R7 | Anchor-attestation cell type (§4.5) collides with future BSV anchoring assumptions | L | M | Design `AnchorAttestation` so it's purely additive — original cell unchanged, attestation cell carries all anchor metadata. |
| H-R8 | Greenfield package proliferation (`plexus-schema-registry`, `anchor-attestation`) increases dep graph | L | L | Both packages are small (≤ 10 files each) and depend on existing core/ packages. No external runtime deps. |

---

## 8. Open decisions

1. **Hard cut vs compat reader for the V1→V2 ABI bump.** §6.1. Decision before H.6.

2. **Does production commerce data exist?** H-R3 hinges on this. Decision before H.3.

3. **Schema authority.** Who signs schemas? Reuse `LexiconAuthority` (a `Brc52Cert` pattern, per `core/semantos-sir/src/authority.ts`) or introduce a new authority kind? Recommend reuse. Decision during H.1.

4. **Schema mutability.** Can a registered schema ever be *replaced* (vs deprecated by a new version)? Recommend no — registered schemas are append-only. Decision during H.1.

5. **`OnChainBinding` migration path.** §4.5 recommends option (b): anchoring becomes its own cell type. Confirm no in-flight code expects header-resident binding fields. If anchoring is going to be a hot path, weigh option (b)'s extra cell against option (c)'s reserved-free region.

6. **Final reclaimed-bytes layout.** §3.1 sketches a layout. Lock the exact offsets during H.2 constants regeneration; preserve `domain_flag` and `typeHash` offsets so kernel opcodes don't need recompiling.

7. **`anchor-attestation` package location.** New top-level `core/anchor-attestation`, or a sub-module of `core/cell-ops`? Recommend new package — keeps the BSV-specific logic out of the generic cell-ops layer.

8. **Naming.** `domainPayloadRoot` is functional but verbose. Alternatives: `payloadCommitment`, `schemaRoot`. Decide before H.2 ships into public surface.

---

## 9. Acceptance criteria (Phase H done)

- [ ] `core/plexus-schema-registry` package merged, with COMMERCE schema registered, persisted, signed, and round-trip tested.
- [ ] Cell header reduced to ≤ 132 bytes of kernel-protocol fields plus `domainPayloadRoot`; bytes 132–255 documented as reserved-free.
- [ ] All four commerce field names absent from grep across `core/`, `runtime/`, `extensions/`, `apps/`, `tests/`.
- [ ] `core/cell-engine/src/commerce.zig` deleted; `OnChainBinding` interface removed.
- [ ] `AnchorAttestation` cell type implemented and verified, or the decision recorded that anchoring stays out of the protocol entirely.
- [ ] Kernel `VERSION = 2`, WASM binary rebuilt reproducibly, manifest published, fuzz suites green.
- [ ] Plexus vendor backup-and-restore covers the new `domain_schemas` table; recovery integration test passes.
- [ ] At least one non-commerce domain (recommend SCG_RELATION or a placeholder) registered against the new registry to prove the pattern generalises.

---

## 10. Footnotes for downstream specs

- **SCG Phase 5.** The schema-driven relation cell design in SCG Phase 5 depends on Phase H being done. Cross-reference: `outputs/scg-implementation-tracking.md §7`.
- **Future domains.** Any new domain (governance, escrow, attestation, identity recovery extensions) should now ship its schema through `core/plexus-schema-registry` rather than negotiating header offsets. Document this as a pattern in the registry's README.
- **PRD §6 ("Core Conceptual Model").** Add a "Cell Header" subsection stating the header is domain-agnostic and that domain semantics live in payload schemas at Plexus. Note this is a deliberate design choice, not an implementation detail.
- **PRD §14 ("Storage Model").** Add Plexus schema registry as a storage tier: `domain_flag → DomainSchema` mappings persisted under the vendor identity, recoverable on key restore.
