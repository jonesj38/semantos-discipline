---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/STRUCTURED-TYPEHASH-TESSERA-MANIFEST-DRAFT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.730323+00:00
---

# Tessera cartridge.json — proposed shape under D11/D12

**Status:** Draft, pre-T2.a implementation
**Date:** 2026-05-25
**Purpose:** Worked example showing the unified `cellTypes[]` shape against every Tessera cell type. Companion to `STRUCTURED-TYPEHASH-ODDJOBZ-MANIFEST-DRAFT.md`.

---

## Source-of-truth audit

Unlike oddjobz (TS authority via `defineCellType`), tessera's authority is split:

| field | source | notes |
|---|---|---|
| `name` | both `cartridge.json` + `tessera_cells.zig` (consistent) | ✓ |
| `linearity` | both (consistent — no drift) | ✓ |
| `description` | `cartridge.json` only | UI surface |
| `how_slug` | `cartridges/tessera/brain/tessera_cell_specs.zig:TRIPLES` (Zig only) | proposed canon per file comment "the *proposed* tessera type-hash triple canon" |
| `inst_path` | same Zig TRIPLES table | proposed canon, contains `.v1` suffixes |

The `tessera_cell_specs.zig` TRIPLES table is the closest thing to triple authority; cartridge.json has no triple data today. T2.a folds the Zig TRIPLES into the manifest with `.v1` stripped per D12.

---

## Proposed `cellTypes[]` (10 entries)

```jsonc
{
  // ... existing cartridge.json header fields stay (id, version, description,
  // capabilitiesPath, consumes, experience, flowsDir, hatRoles, name,
  // promptsDir, provides, role, shellGrammar, taxonomyPath, verbs, version,
  // wssSubprotocols). objectTypesDir field is DELETED (dead code).

  "cellTypes": [
    {
      "name": "tessera.grape-lot",
      "triple": {
        "segment1": "tessera",
        "segment2": "grape-lot",
        "segment3": "harvest",
        "segment4": ""
      },
      "linearity": "AFFINE",
      "description": "AFFINE origin cell — partial consumption into barrels; remainder spendable."
    },
    {
      "name": "tessera.barrel",
      "triple": {
        "segment1": "tessera",
        "segment2": "barrel",
        "segment3": "rack",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "description": "LINEAR cell consumed entirely at bottling."
    },
    {
      "name": "tessera.bottle",
      "triple": {
        "segment1": "tessera",
        "segment2": "bottle",
        "segment3": "bottle",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "description": "LINEAR cell; one tamper-break ends its open trajectory."
    },
    {
      "name": "tessera.case",
      "triple": {
        "segment1": "tessera",
        "segment2": "case",
        "segment3": "assemble",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "description": "LINEAR cell assembled from N bottles via typed SemanticRelation."
    },
    {
      "name": "tessera.pallet",
      "triple": {
        "segment1": "tessera",
        "segment2": "pallet",
        "segment3": "palletize",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "description": "LINEAR cell; split into cases = a new pallet cell consuming the old."
    },
    {
      "name": "tessera.shipment",
      "triple": {
        "segment1": "tessera",
        "segment2": "shipment",
        "segment3": "ship",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "description": "LINEAR cell; closed once destination receives."
    },
    {
      "name": "tessera.care-event",
      "triple": {
        "segment1": "tessera",
        "segment2": "care-event",
        "segment3": "care-record",
        "segment4": ""
      },
      "linearity": "AFFINE",
      "description": "AFFINE cell; logger readings accumulate against one shipment."
    },
    {
      "name": "tessera.scan-event",
      "triple": {
        "segment1": "tessera",
        "segment2": "scan-event",
        "segment3": "scan",
        "segment4": ""
      },
      "linearity": "RELEVANT",
      "description": "RELEVANT cell; must exist for the Care Score view to render."
    },
    {
      "name": "tessera.tamper-event",
      "triple": {
        "segment1": "tessera",
        "segment2": "tamper-event",
        "segment3": "tamper",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "description": "LINEAR cell; single transition intact → broken."
    },
    {
      "name": "tessera.tasting-note",
      "triple": {
        "segment1": "tessera",
        "segment2": "tasting-note",
        "segment3": "taste",
        "segment4": ""
      },
      "linearity": "DEBUG",
      "description": "DEBUG cell; read-only, opaque to FSMs and capability flow."
    }
  ]
}
```

---

## Notes for T2.a implementation

1. **No linearity drift** — cartridge.json and `tessera_cells.zig` agree. Migration just adds triples; no value changes.

2. **No `displayName` on any entry**. Tessera doesn't currently surface entities to a UI navigation; the cellTypes are workflow/event-shaped (grape-lot → barrel → bottle pipeline). If a UI is added later, displayName grows in place on the relevant entries.

3. **Linearity values include `RELEVANT` and `DEBUG`** which oddjobz doesn't use. The new manifest schema must allow all `LinearityType` values (`LINEAR | AFFINE | PERSISTENT | RELEVANT | DEBUG`). The kernel's `linearity.zig` is the authority.

4. **Zig downstream**: `tessera_cell_specs.zig:TRIPLES` becomes a build-time reflection of manifest (or gets deleted entirely, with `specForIndex()` reading from a generated header). Punt to follow-up — out of T2.a scope.

5. **`tessera.bottle` segment3 = "bottle"** is the only entry where segment2 == segment3 (entity name == operation). Could be improved with a more action-oriented slug (e.g. "bottle-fill") but preserving the Zig source as-is for the migration.

6. **`care-record` (segment3 for care-event)** is the only multi-word how_slug. Preserved as-is.

7. **All `.v1` suffixes dropped from `inst_path`** per D12. The Zig source had `inst.origin.grape-lot.v1`, etc. Under the new model, version is not part of the typeHash; segment4 stays empty. The `inst_path` concept itself dissolves into segment3+segment4 — we don't try to preserve "inst.origin.grape-lot" anywhere because the only consumer was the colon-triple `whatPath:howSlug:instPath` flat hash.
