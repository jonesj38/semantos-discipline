---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/cartridge.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.415472+00:00
---

# cartridges/tessera/cartridge.json

```json
{
  "id": "tessera",
  "name": "Tessera",
  "version": "0.0.1",
  "role": "experience",
  "experience": {
    "flutterPackage": "packages/tessera_experience"
  },
  "description": "Care-chain provenance cartridge. Grape-to-glass-shaped traceability over physically handed-off objects whose value depends on a verifiable care chain \u2014 wine, premium coffee, cold-chain pharma, art transit. Substrate-consuming.",
  "taxonomyPath": "brain/src/taxonomy.json",
  "flowsDir": "brain/src/flows",
  "promptsDir": "brain/src/prompts",
  "capabilitiesPath": "brain/src/capabilities.ts",
  "provides": [],
  "wssSubprotocols": [],
  "verbs": [
    {
      "name": "tessera.harvest",
      "capability_required": "cap.tessera.harvest",
      "category": "harvest",
      "hats": [
        "producer",
        "field-worker"
      ],
      "description": "Record a harvest event for a grape lot."
    },
    {
      "name": "tessera.rack",
      "capability_required": "cap.tessera.rack",
      "category": "rack",
      "hats": [
        "producer"
      ],
      "description": "Record a racking / cellar transfer between barrels."
    },
    {
      "name": "tessera.blend",
      "capability_required": "cap.tessera.blend-declare",
      "category": "blend",
      "hats": [
        "producer"
      ],
      "description": "Declare a blend transition consuming N barrels into one (K15 conservation)."
    },
    {
      "name": "tessera.bottle",
      "capability_required": "cap.tessera.bottle",
      "category": "bottle",
      "hats": [
        "producer"
      ],
      "description": "Produce N LINEAR bottle cells from one barrel."
    },
    {
      "name": "tessera.assemble-case",
      "capability_required": "cap.tessera.assemble",
      "category": "label",
      "hats": [
        "producer",
        "distributor"
      ],
      "description": "Assemble a case from N bottles."
    },
    {
      "name": "tessera.transfer-custody",
      "capability_required": "cap.tessera.custody",
      "category": "custody-transfer",
      "hats": [
        "producer",
        "distributor",
        "retailer"
      ],
      "description": "Transfer custody of a case / pallet / shipment."
    },
    {
      "name": "tessera.record-care-event",
      "capability_required": "cap.tessera.care-record",
      "category": "care-event",
      "hats": [
        "distributor",
        "dock-handler"
      ],
      "description": "Record an AFFINE care event (logger reading or thermo flag)."
    },
    {
      "name": "tessera.tamper",
      "capability_required": null,
      "category": "tamper-event",
      "hats": [
        "club-member"
      ],
      "description": "Mark a bottle tamper-loop seal broken (self-authorising)."
    },
    {
      "name": "tessera.consumer-scan",
      "capability_required": "cap.tessera.scan",
      "category": "scan",
      "hats": [
        "club-member"
      ],
      "description": "Scan a bottle \u2014 produces a RELEVANT scan-event cell."
    },
    {
      "name": "tessera.add-tasting-note",
      "capability_required": null,
      "category": "tasting-note",
      "hats": [
        "club-member"
      ],
      "description": "Attach a DEBUG-class tasting note to a bottle."
    },
    {
      "name": "tessera.confirm-receipt",
      "capability_required": "cap.tessera.custody",
      "category": "custody-transfer",
      "hats": [
        "club-member",
        "retailer"
      ],
      "description": "Confirm inbound custody, closing the transfer."
    },
    {
      "name": "tessera.report-quality-issue",
      "capability_required": null,
      "category": "care-event",
      "hats": [
        "club-member",
        "retailer"
      ],
      "description": "Report a quality issue against a bottle (open read-issue)."
    },
    {
      "name": "tessera.thermo-flag",
      "capability_required": "cap.tessera.care-record",
      "category": "care-event",
      "hats": [
        "dock-handler"
      ],
      "description": "Manual care-event for a flipped thermochromic sticker."
    }
  ],
  "consumes": {
    "StorageAdapter": "required \u2014 for bottle / case / pallet / shipment / care-event cell stores",
    "IdentityAdapter": "required \u2014 for BCA derivation + BRC-52 cert binding on every patch",
    "AnchorAdapter": "required \u2014 for SPV-verifiable cell anchoring (consumer scan budget)",
    "NetworkAdapter": "required \u2014 for cross-operator SignedBundle<TesseraPatch> federation"
  },
  "hatRoles": [
    "producer",
    "field-worker",
    "distributor",
    "dock-handler",
    "retailer",
    "club-member"
  ],
  "shellGrammar": {
    "trustClass": "interpretive",
    "proofRequirement": "attestation",
    "defaultTaxonomyWhat": "tessera.bottle"
  },
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
      "description": "AFFINE origin cell \u2014 partial consumption into barrels; remainder spendable."
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
      "description": "LINEAR cell; single transition intact \u2192 broken."
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
  ],
  "_notes": {
    "scaffold_only": "V0.2 scaffold. The 13 walker implementations, 9 cell types, 8 capability flags, and 7 hat surfaces ship via V0.3 (post-loader cohort) + V1 / V2 / V3 / V4 / V5 deliverables per docs/canon/commissions/wave-tessera.md. V0.3/V0.5 follow the cartridges/oddjobz/brain/ golden-path pattern (FSM walkers + StorageAdapter-consumer stores under brain/zig/, cell-types under brain/src/cell-types/) registered via the experience-cartridge SDK \u2014 no brain-core code. The scaffold lights up A9 Tessera as DESIGN-status in /api/v1/info discovery.",
    "manifest_format": "Phase 36A ExtensionManifest shape per core/protocol-types/src/extension-manifest.ts. Golden-path cartridge layout mirrors cartridges/oddjobz/: this cartridge.json (top-level descriptor) + brain/ bundle (src/, zig/, tests/, package.json, brain/release.config.ts).",
    "greenfield": "Per TESSERA-CARTRIDGE.md \u00a70.1: tessera NEVER appears in runtime/semantos-brain/src/. CI gate tests/gates/no-tessera-in-brain-core.test.ts (V0.1) enforces this for every commit.",
    "hat_roles": "Six operator hats surface in the canonical Semantos PWA hat switcher via the HatRegistry (populated from this field at boot). The seventh hat, tessera.consumer, is intentionally NOT listed \u2014 it is the standalone anonymous NFC-tap PWA (V1.6), no login, no shell composition. Shell-side manifest mirror: packages/tessera_experience/assets/manifest.json.",
    "manifest_canonical": "D-Manifest-canonical (resolved for tessera): THIS file is the single source of truth. The Flutter shell manifest + bundle (packages/tessera_experience/assets/{manifest.json,bundle.json}) are GENERATED from this file by tools/cartridge-manifest/generate.ts \u2014 never hand-edited. The generator derives the shell domainFlag from core/constants/constants.json extensionPages TESSERA_PAGE (0x00010400, unified \u2014 supersedes the earlier interim 0x000105; collision-free vs jambox 0x000104=260 since byDomainFlag compares parsed ints) and the lexicon categories from core/semantos-sir ALL_LEXICONS (V0.4 TesseraLexicon). CI gate tests/gates/manifest-consistency.test.ts fails if the committed shell assets drift from a regenerate. Per-verb `hats`/`category`/`description` and the `shellGrammar` + `cellTypes` blocks exist so the shell manifest is fully derivable. Open follow-up: validateExtensionManifest() in core/protocol-types is hollow (ignores verbs/consumes) \u2014 ecosystem-wide fix tracked separately."
  }
}

```
