---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/STRUCTURED-TYPEHASH-CANONICAL.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.735815+00:00
---

# Canonical Structured TypeHash

**Status:** Decision record — pre-implementation
**Date:** 2026-05-25
**Authors:** Todd Price, with scoping by Claude
**Supersedes:** Implicit "flat SHA-256 of dotted name or colon-triple" conventions in `core/protocol-types/src/mnca/cell-types.ts`, `cartridges/oddjobz/brain/src/cell-types/type-hash.ts`, `core/cell-ops/src/typeHashRegistry.ts`, and `scripts/compute-type-hashes.ts`.

---

## 1. Context

The 32-byte `typeHash` field at cell-header offset 30 is currently computed by **at least three different rules** depending on caller:

| Caller | Rule | Wire result |
|---|---|---|
| MNCA (`core/protocol-types/src/mnca/`) | `SHA256("mnca.snapshot")` | flat opaque 32 bytes |
| Oddjobz / Tessera (`defineCellType`) | `SHA256("whatPath:howSlug:instPath")` | flat opaque 32 bytes |
| Extensions (`scripts/compute-type-hashes.ts`) | `SHA256(category \|\| name)` | flat opaque 32 bytes |

All three pipelines produce **opaque flat hashes**. The bytes carry no structure a relay, LMDB range scan, or projection layer can exploit without dereferencing back to a string identifier. Every "find all cells of type X" query is therefore either an exact-match lookup or a full scan.

Two structural debts compound the problem:

1. **Format fragmentation** — the dotted and colon-triple formats are aliases for the same intent (cell-type identity) but live in incompatible code paths. No adapter is acceptable; the existence of two formats reflects two separate definition pipelines that need to converge.
2. **Authority diffusion** — `defineCellType` (TS) is currently treated as source of truth, with `glossary.yml` and `typeHashRegistry.ts` as parity-tested mirrors. MNCA, chess fixtures, and the extension script bypass this entirely. Zig consumes hardcoded strings or hex literals.

---

## 2. Decision

### 2.1 Structured hash construction

`typeHash` is constructed as four concatenated 8-byte truncated SHA-256 digests of cumulative path segments:

```
typeHash[ 0: 8] = sha256(segment1)[0:8]    // namespace
typeHash[ 8:16] = sha256(segment2)[0:8]    // domain
typeHash[16:24] = sha256(segment3)[0:8]    // sub-type
typeHash[24:32] = sha256(segment4)[0:8]    // qualifier / version
```

Empty segments hash the empty string (`sha256("")[0:8]` — a specific deterministic constant). The construction is **NOT** wrapped in an outer hash; the 32 bytes ARE the four truncated inner hashes concatenated directly. Wrapping would collapse the structure back to opaque.

### 2.2 Reserved wildcard prefix

The 8-byte sequence `0x0000000000000000` (raw zeros, distinct from `sha256("")[0:8]`) is **reserved** as an explicit routing wildcard. A typeHash whose `bytes[0:8]` are raw zeros signals "no namespace owner — promiscuous routing, any subscriber may pick this up." Used for max-coverage compute fan-out (e.g. Skyminer multi-device parallel MNCA).

Empty segments in normal usage hash to `sha256("")[0:8]` and route normally. Only the explicit raw-zero prefix is wildcard.

### 2.3 Manifest as single source of truth

Cell type identities are declared **only** in cartridge manifests (`cartridge.json`), under a unified `cellTypes[]` array. They are not in the kernel binary. They are not in TypeScript source. They are not in Zig comptime. They are read from manifests at cartridge-load time.

Each `cellTypes[]` entry has **required** identity fields plus **optional** UI-surface fields. Entries whose `displayName` is present surface to the UI; entries without it are pure cell-types (workflow/event-shaped, no UI navigation).

```json
// cartridges/<cartridge-name>/cartridge.json
{
  "cellTypes": [
    {
      // identity (required for every entry)
      "name": "oddjobz.job",
      "triple": {
        "segment1": "oddjobz",
        "segment2": "job",
        "segment3": "worktrack",
        "segment4": ""
      },
      "linearity": "AFFINE",

      // UI surface (optional — present when this cellType is UI-facing)
      "displayName": "Job",
      "primaryAnchor": true,
      "description": "A unit of work in the trades vertical.",
      "payloadSchema": { ... },
      "phases": ["active", "completed"],
      "initialPhase": "active"
    },
    {
      // pure cell-type — no UI surface
      "name": "oddjobz.attachment",
      "triple": {
        "segment1": "oddjobz",
        "segment2": "attachment",
        "segment3": "capture",
        "segment4": ""
      },
      "linearity": "LINEAR"
    }
  ]
}
```

The brain loader reads the manifest, calls the kernel's `buildTypeHash` for each `cellTypes[]` entry, and registers `{typeHash → typeDef}` in a runtime map. The cell engine routes by lookup against this map. The legacy `objectTypes[]` array is **deleted** in the migration — its data folds into `cellTypes[]` entries with the UI fields populated.

**Versioning is not a typeHash concern.** Names do not carry `.v1` / `.v2` suffixes; `segment4` does not carry version. Cartridges evolve their payload schemas in place where possible; when a genuinely-breaking change is needed, they pick a new triple at a different position. Multiple co-existing versions of the same logical type are not supported — operational simplicity beats migration luxury.

### 2.4 Authority direction

There is no "TS primary" or "Zig primary." Both languages **read from the manifest** and both compute hashes via parallel implementations of `buildTypeHash` (Zig comptime in the kernel, TS runtime in cartridge tooling). A parity test asserts both implementations produce byte-identical hex for the same triple.

The TS `defineCellType()` helper is retained as a developer convenience that **either emits a manifest entry** (build-time) **or reads an existing manifest entry** (load-time). It is not a source of truth.

---

## 3. Architecture

### 3.1 What lives in the kernel binary (comptime)

- `buildTypeHash(s1, s2, s3, s4) -> [32]u8` — pure function, no state
- Cell engine wire format constants (header offsets, sizes — unchanged)
- Pask graph engine
- Cartridge loader
- The reserved wildcard sentinel value

**Zero cell-type identities ship in the binary.** The binary holds the algorithm. Cartridges declare the data.

### 3.2 What lives in cartridge manifests (load-time)

- `cellTypes[]` unified array — every cell type the cartridge ships. Required fields: `name`, `triple`, `linearity`. Optional UI fields: `displayName`, `primaryAnchor`, `description`, `payloadSchema`, `phases`, `initialPhase`.
- The hash is **never serialised in the manifest** — it is always computed from the triple at load time. This prevents drift between declared triple and embedded hash.
- The dead `objectTypesDir` field (a no-op in current code) is removed.
- The legacy `objectTypes[]` array is removed (data folded into `cellTypes[]` entries with UI fields populated).

### 3.3 Routing tiers

| Tier | What handles it | typeHash prefix shape |
|---|---|---|
| Kernel primitives | Cell engine, pask, cartridge loader | n/a — not cell-typed |
| Substrate cartridges | mnca, future hrr / conversation-engine / jetstream | `<substrate-name>.*` |
| Domain cartridges | oddjobz, nonprofit-os, tessera | `<domain-name>.*` |
| Cross-domain compute | MNCA over domain data | `<domain>.mnca.*` (locality) |
| Promiscuous fan-out | Compute-anywhere broadcasts | raw `0x00 × 8` wildcard prefix |

### 3.4 Load-time flow

```
1. Brain starts, loads kernel binary (buildTypeHash available)
2. User opts in to a cartridge (e.g. oddjobz)
3. Brain reads cartridges/oddjobz/cartridge.json
4. For each objectType entry:
     hash = buildTypeHash(triple.segment1, ..., triple.segment4)
     registry.set(hash, {typeDef, schema, linearity, ...})
5. Cell engine receives a cell → reads typeHash at offset 30
   → looks up in registry → routes/decodes accordingly
6. Relay receives a cell → peeks bytes 30:38 (8 bytes) → checks
   prefix subscription → forwards or drops without full lookup
```

---

## 4. MNCA reclassification

### 4.1 MNCA is a substrate cartridge

MNCA is **not core**. It is a substrate-level cartridge: a reusable compute pattern (cellular automaton over cells) that domain cartridges may opt into. Comparable to pask in role (general reusable mechanism), but higher in the stack — pask is kernel graph engine (every cell ride uses it); MNCA is opt-in compute (only cartridges that want CA dynamics load it).

**Action:** move MNCA cell type definitions out of `core/protocol-types/src/mnca/` and into `cartridges/mnca/`. Wire format primitives (tile codec byte layouts, header offsets specific to MNCA tile encoding) **stay in `core/protocol-types/`** because they are kernel-level format contracts that pask and the cell engine need to understand for transport.

### 4.2 MNCA path convention

MNCA cell types embed the source data's cartridge in `segment1`, so the structured hash routes MNCA computations to the relevant domain's relay mesh by default (locality of reference).

```
oddjobz MNCA tile tick:
  segment1: "oddjobz"        ← routes to oddjobz mesh
  segment2: "mnca"
  segment3: "tile"
  segment4: "tick"

nonprofit-os MNCA snapshot:
  segment1: "nonprofit-os"
  segment2: "mnca"
  segment3: "snapshot"
  segment4: "v1"

Standalone substrate MNCA (no domain source):
  segment1: "mnca"           ← routes to MNCA-substrate mesh
  segment2: "standalone"
  segment3: "tile"
  segment4: "tick"

Promiscuous fan-out compute:
  raw 0x00 × 8 prefix        ← anyone, please
  (remaining 24 bytes still identify the operation)
```

This convention means a domain cartridge's MNCA traffic stays inside that cartridge's relay mesh by default — relays subscribed to `oddjobz.*` naturally pick up `oddjobz.mnca.*` without needing a separate subscription. Standalone substrate MNCA gets its own mesh. Wildcard is explicit and opt-in per cell.

---

## 5. Migration plan

Five steps, each its own PR, each leaves existing tests green:

### Step 1 — Implement `buildTypeHash` in kernel

- New: `core/cell-engine/src/type_hash.zig` (Zig comptime + runtime)
- New: `core/protocol-types/src/type-hash.ts` (TS, calls `@noble/hashes/sha256`)
- New: parity test that asserts Zig and TS produce byte-identical output for a fixed table of (s1, s2, s3, s4) → hex vectors
- Reserved wildcard constant exported from both
- No callers change yet

### Step 2 — Migrate Oddjobz / Tessera cartridges to manifest-declared triples

- Add `triple: {segment1, segment2, segment3, segment4}` to every `objectTypes[]` entry in `cartridges/oddjobz/cartridge.json` and `cartridges/tessera/cartridge.json`
- Brain loader reads triple → calls `buildTypeHash` → registers
- `defineCellType()` TS helper refactored to read from manifest (or emit-and-verify against it)
- Delete `core/cell-ops/src/typeHashRegistry.ts` (registry becomes a runtime map populated from manifests, not a checked-in source file)
- Glossary.yml regenerated from manifests via a build script (becomes a derived render, not a parallel source — same pattern as `lexicons.yml` per CC0b)

### Step 3 — Migrate MNCA to cartridge layout

- Create `cartridges/mnca/cartridge.json` with all MNCA cell types declared as triples using the source-cartridge convention
- Move TS cell type defs from `core/protocol-types/src/mnca/cell-types.ts` to `cartridges/mnca/brain/src/cell-types/`
- Keep tile codec wire format in `core/protocol-types/src/mnca/`
- Delete `computeMncaTypeHash` — callers route through manifest-loaded registry
- Update MNCA known-answer test vectors

### Step 4 — Migrate test fixtures and extension script

- `chess.stake.v1` and `semantos:test:linear-cell` test fixtures: declare in a `test/fixtures/cartridge.json` manifest, register via the same loader path
- Delete `scripts/compute-type-hashes.ts` — extensions migrate to the manifest model. Extension configs that previously had `category` field grow a proper `triple` declaration
- All `nobleSha256(encode("..."))` calls in test files refactored to load via fixture cartridge

### Step 5 — Cut over to structured `|8|8|8|8|` construction

- Change `buildTypeHash` in both Zig and TS from flat `SHA256(concat-with-delimiter)` to the structured 4-segment construction
- Regenerate glossary.yml (all hex values change)
- Regenerate MNCA known-answer test vectors
- Verify `domainFlagFromTypeHash` and `anchorProtocolHash` still pass — they consume 32 bytes as a blob; bytes [0:3] now come from `sha256(namespace)[0:3]`, semantics unchanged
- Wire-breaking change accepted: any pre-existing persisted cells will not match new hashes on exact lookup. V1 production on `rbs` is test data; no migration required.

---

## 6. What does NOT change

- Cell header wire format — still 32 bytes at offset 30
- `cell-header.ts` serialization / deserialization
- BSV anchor derivation (`anchorProtocolHash` takes 32 bytes as input)
- `domainFlagFromTypeHash` (still uses bytes 0..2, now from `sha256(segment1)[0:3]`)
- `OutputStore` / `typeHashHex` IndexedDB column (still 64-char hex string)
- Cartridge manifest schema for fields other than `objectTypes[].triple`
- Wire format observable by relays beyond cell header
- The lexicon / SIR axis (orthogonal — categorises speech-act intents, not cell-type identities)

---

## 7. Indexing and routing wins unlocked

This section is informational — it describes what becomes possible once the structured hash ships, justifying the work.

### 7.1 LMDB prefix scans

`cellsByType` index becomes range-scannable by namespace prefix. A query "all `nonprofit-os.fund.*` cells" is a prefix scan on bytes 0:16, not a full scan.

### 7.2 Relay routing as 4-level trie

A relay peeks 8 bytes of the typeHash field (cell offset 30:38) to decide namespace membership without reading the cell payload or resolving any string. Sub-namespace decisions cost another 8-byte peek. Exact-type subscription matching costs the full 32 bytes. Hierarchical routing topology emerges from the wire format with zero additional metadata.

### 7.3 SQL projection columns

The Postgres projection layer (`sem_objects` and successors) can add four indexed columns for the four segments and serve "all type X across any cartridge" queries via direct indexed lookups instead of full-text path matching.

### 7.4 Promiscuous compute fan-out

The reserved `0x00 × 8` wildcard prefix gives explicit "compute anywhere" semantics for parallel substrate workloads. Required for the Skyminer multi-device demo.

---

## 8. Open items deferred to implementation

These are real decisions but they don't block this record. Resolve during Step 1 or Step 2:

1. **Manifest schema for `triple`** — current draft uses `{segment1, segment2, segment3, segment4}` for explicitness; alternative is `["seg1", "seg2", "seg3", "seg4"]` array. Pick one before Step 2.
2. **Glossary render pipeline** — write the script that regenerates `glossary.yml` from all loaded manifests, with deterministic ordering. Required at end of Step 2.
3. **Cartridge load order vs typeHash collisions** — if two cartridges declare identical triples, the brain must reject the second cartridge with a clear error. Design the error path during Step 2.
4. **MNCA `cartridges/mnca/` layout** — does MNCA need a Zig component (for hot-path tile compute), a TS-only brain component (for cell registration), or both? Resolve during Step 3.
5. **Reserved wildcard policy** — who is permitted to mint cells with the raw-zero prefix? Probably substrate-cartridge cells only; domain cartridges should not be able to broadcast promiscuously without explicit operator permission. Capability check during Step 5.

---

## 9. Out of scope

- Versioning of the structured construction itself. If we ever need a different segmentation scheme, that's a future decision record.
- Network-level relay subscription protocol (how relays declare which prefixes they handle). Tracked separately in routing work.
- Cell payload migration tools for the wire-breaking change. Decided: no migration, V1 production is test data.
- Lexicon / SIR convergence with cell-type identity. Orthogonal axis; no current need to bind.
