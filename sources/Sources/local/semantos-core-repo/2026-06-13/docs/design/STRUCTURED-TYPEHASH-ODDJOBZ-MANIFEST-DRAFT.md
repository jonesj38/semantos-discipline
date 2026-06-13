---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/STRUCTURED-TYPEHASH-ODDJOBZ-MANIFEST-DRAFT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.727233+00:00
---

# Oddjobz cartridge.json — proposed shape under D11/D12

**Status:** Draft, pre-T2.a implementation
**Date:** 2026-05-25
**Purpose:** Worked example showing the unified `cellTypes[]` shape against every Oddjobz cell type. Decision record §2.3 specifies the shape; this document shows it applied to a real cartridge before code lands.

---

## Linearity audit (TS as authority)

Cross-checked from `cartridges/oddjobz/brain/src/cell-types/*.ts` `defineCellType` calls:

| cell type | linearity (TS) | linearity (current cartridge.json) | drift? |
|---|---|---|---|
| attachment | LINEAR | (not in cartridge.json) | new |
| customer | PERSISTENT | AFFINE | **YES — TS wins** |
| estimate | AFFINE | (not in cartridge.json) | new |
| invoice | LINEAR | (not in cartridge.json) | new |
| job | LINEAR | AFFINE | **YES — TS wins** |
| lead | AFFINE | (not in cartridge.json) | new |
| message | PERSISTENT | (not in cartridge.json) | new |
| pricing_policy | PERSISTENT | (not in cartridge.json) | new |
| quote | LINEAR | (not in cartridge.json) | new |
| site | PERSISTENT | AFFINE | **YES — TS wins** |
| visit | LINEAR | (not in cartridge.json) | new |

The current cartridge.json was wrong for site/customer/job (all marked AFFINE; TS says PERSISTENT/PERSISTENT/LINEAR). CC5.B2b half-migration carried the schemas correctly but the linearity values drifted. T2.a fixes this by using TS values as authority.

---

## Proposed `cellTypes[]` (11 entries)

```jsonc
{
  // ... existing cartridge.json header fields stay (id, version, description,
  // capabilitiesPath, consumes, experience, flowsDir, name, promptsDir,
  // ratificationThreshold, role, taxonomyPath, ui, verbs, version,
  // wssSubprotocols). objectTypesDir field is DELETED (dead code).
  // objectTypes[] is DELETED (folded into cellTypes[] below).

  "cellTypes": [
    {
      "name": "oddjobz.site",
      "triple": {
        "segment1": "oddjobz",
        "segment2": "site",
        "segment3": "locate",
        "segment4": ""
      },
      "linearity": "PERSISTENT",
      "displayName": "Site",
      "primaryAnchor": true,
      "description": "A physical location where jobs are performed. The most stable node in the graph — tenants/agencies cycle but the address persists; route optimisation and accumulated site-knowledge anchor here.",
      "phases": ["active"],
      "initialPhase": "active",
      "payloadSchema": { /* … existing schema from current objectTypes[0] verbatim … */ }
    },
    {
      "name": "oddjobz.customer",
      "triple": {
        "segment1": "oddjobz",
        "segment2": "customer",
        "segment3": "identify",
        "segment4": ""
      },
      "linearity": "PERSISTENT",
      "displayName": "Customer",
      "description": "A person or organisation paying for work.",
      "payloadSchema": { /* … existing schema from current objectTypes[1] verbatim … */ }
    },
    {
      "name": "oddjobz.job",
      "triple": {
        "segment1": "oddjobz",
        "segment2": "job",
        "segment3": "worktrack",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "displayName": "Job",
      "description": "A unit of work in the trades vertical.",
      "payloadSchema": { /* … existing schema from current objectTypes[2] verbatim … */ }
    },
    {
      "name": "oddjobz.attachment",
      "triple": {
        "segment1": "oddjobz",
        "segment2": "attachment",
        "segment3": "capture",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "description": "Binary artifact (photo/document) captured at a Visit."
    },
    {
      "name": "oddjobz.estimate",
      "triple": {
        "segment1": "oddjobz",
        "segment2": "estimate",
        "segment3": "estimate",
        "segment4": ""
      },
      "linearity": "AFFINE",
      "displayName": "Estimate",
      "description": "Rough-order-of-magnitude pricing before formal quote."
    },
    {
      "name": "oddjobz.invoice",
      "triple": {
        "segment1": "oddjobz",
        "segment2": "invoice",
        "segment3": "bill",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "displayName": "Invoice",
      "description": "Billable charge issued post-completion."
    },
    {
      "name": "oddjobz.lead",
      "triple": {
        "segment1": "oddjobz",
        "segment2": "lead",
        "segment3": "ratify",
        "segment4": ""
      },
      "linearity": "AFFINE",
      "displayName": "Lead",
      "description": "Pre-job interest — ratifies into Job once accepted."
    },
    {
      "name": "oddjobz.message",
      "triple": {
        "segment1": "oddjobz",
        "segment2": "message",
        "segment3": "communicate",
        "segment4": ""
      },
      "linearity": "PERSISTENT",
      "description": "Chat/voice/image message between customer ↔ operator."
    },
    {
      "name": "oddjobz.pricing_policy",
      "triple": {
        "segment1": "oddjobz",
        "segment2": "pricing_policy",
        "segment3": "pricing-policy",
        "segment4": ""
      },
      "linearity": "PERSISTENT",
      "description": "Tenant-wide pricing rules (rates, markups, discounts)."
    },
    {
      "name": "oddjobz.quote",
      "triple": {
        "segment1": "oddjobz",
        "segment2": "quote",
        "segment3": "price",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "displayName": "Quote",
      "description": "Formal priced offer to a customer for a job."
    },
    {
      "name": "oddjobz.visit",
      "triple": {
        "segment1": "oddjobz",
        "segment2": "visit",
        "segment3": "inspect",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "displayName": "Visit",
      "description": "An operator's on-site visit — origin of attachments and notes."
    }
  ]
}
```

---

## Notes for T2.a implementation

1. **`pricing_policy` segment-naming inconsistency carried over**: `segment2` is `pricing_policy` (underscore, matching `name`), `segment3` is `pricing-policy` (hyphen, matching `howSlug`). Existing code uses both — not normalising in this migration to avoid an unrelated wire change. Future cleanup task if desired.

2. **8 new entries have no `payloadSchema` yet**. They live as TS-only `defineCellType()` validators today. T2.a focuses on identity migration — schema migration is a separate follow-up task per cell type as schemas stabilise.

3. **`primaryAnchor: true` is only on Site** in the existing cartridge.json — preserving that. Customer/Job were entity-level in the old `objectTypes[]` but didn't carry `primaryAnchor`. Drift not introduced.

4. **3 linearity drift fixes** in this migration: site AFFINE → PERSISTENT, customer AFFINE → PERSISTENT, job AFFINE → LINEAR. These reflect TS authority. Watch test surface for downstream consumers that branch on linearity.

5. **`displayName` is set on entries that surface in the UI today**: site, customer, job, estimate, invoice, lead, quote, visit. Skipped for attachment, message, pricing_policy (currently no UI navigation surface).

6. **No `.v1` suffix anywhere** per D12. The TS files retain `.v1` in their `name` field currently (`oddjobz.job.v1`); T2.a renames those when the TS `defineCellType()` calls are refactored to read from manifest.
