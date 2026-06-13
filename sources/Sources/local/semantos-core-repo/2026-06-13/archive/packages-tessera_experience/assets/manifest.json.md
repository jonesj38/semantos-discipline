---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-tessera_experience/assets/manifest.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.826951+00:00
---

# archive/packages-tessera_experience/assets/manifest.json

```json
{
  "id": "tessera",
  "name": "Tessera — Care Chain",
  "version": "0.0.1",
  "domainFlag": "0x00010400",
  "metadata": {
    "description": "Care-chain provenance cartridge. Grape-to-glass-shaped traceability over physically handed-off objects whose value depends on a verifiable care chain — wine, premium coffee, cold-chain pharma, art transit. Substrate-consuming.",
    "author": "Semantos",
    "documentation": "docs/prd/TESSERA-CARTRIDGE.md"
  },
  "hatRoles": [
    "producer",
    "field-worker",
    "distributor",
    "dock-handler",
    "retailer",
    "club-member"
  ],
  "requiredCapabilities": [],
  "grammar": {
    "extensionId": "tessera",
    "trustClass": "interpretive",
    "proofRequirement": "attestation",
    "defaultTaxonomyWhat": "tessera.bottle",
    "lexicon": {
      "name": "tessera",
      "categories": [
        "harvest",
        "ferment",
        "rack",
        "blend",
        "addition",
        "bottle",
        "label",
        "custody-transfer",
        "care-event",
        "excursion",
        "tamper-event",
        "scan",
        "tasting-note"
      ]
    },
    "objectTypes": [
      {
        "name": "tessera.grape-lot",
        "description": "AFFINE origin cell — partial consumption into barrels; remainder spendable."
      },
      {
        "name": "tessera.barrel",
        "description": "LINEAR cell consumed entirely at bottling."
      },
      {
        "name": "tessera.bottle",
        "description": "LINEAR cell; one tamper-break ends its open trajectory."
      },
      {
        "name": "tessera.case",
        "description": "LINEAR cell assembled from N bottles via typed SemanticRelation."
      },
      {
        "name": "tessera.pallet",
        "description": "LINEAR cell; split into cases = a new pallet cell consuming the old."
      },
      {
        "name": "tessera.shipment",
        "description": "LINEAR cell; closed once destination receives."
      },
      {
        "name": "tessera.care-event",
        "description": "AFFINE cell; logger readings accumulate against one shipment."
      },
      {
        "name": "tessera.scan-event",
        "description": "RELEVANT cell; must exist for the Care Score view to render."
      },
      {
        "name": "tessera.tamper-event",
        "description": "LINEAR cell; single transition intact → broken."
      },
      {
        "name": "tessera.tasting-note",
        "description": "DEBUG cell; read-only, opaque to FSMs and capability flow."
      }
    ],
    "actions": [
      {
        "name": "harvest",
        "category": "harvest",
        "authoredBy": [
          "producer",
          "field-worker"
        ],
        "description": "Record a harvest event for a grape lot."
      },
      {
        "name": "rack",
        "category": "rack",
        "authoredBy": [
          "producer"
        ],
        "description": "Record a racking / cellar transfer between barrels."
      },
      {
        "name": "blend",
        "category": "blend",
        "authoredBy": [
          "producer"
        ],
        "description": "Declare a blend transition consuming N barrels into one (K15 conservation)."
      },
      {
        "name": "bottle",
        "category": "bottle",
        "authoredBy": [
          "producer"
        ],
        "description": "Produce N LINEAR bottle cells from one barrel."
      },
      {
        "name": "assemble_case",
        "category": "label",
        "authoredBy": [
          "producer",
          "distributor"
        ],
        "description": "Assemble a case from N bottles."
      },
      {
        "name": "transfer_custody",
        "category": "custody-transfer",
        "authoredBy": [
          "producer",
          "distributor",
          "retailer"
        ],
        "description": "Transfer custody of a case / pallet / shipment."
      },
      {
        "name": "record_care_event",
        "category": "care-event",
        "authoredBy": [
          "distributor",
          "dock-handler"
        ],
        "description": "Record an AFFINE care event (logger reading or thermo flag)."
      },
      {
        "name": "tamper",
        "category": "tamper-event",
        "authoredBy": [
          "club-member"
        ],
        "description": "Mark a bottle tamper-loop seal broken (self-authorising)."
      },
      {
        "name": "consumer_scan",
        "category": "scan",
        "authoredBy": [
          "club-member"
        ],
        "description": "Scan a bottle — produces a RELEVANT scan-event cell."
      },
      {
        "name": "add_tasting_note",
        "category": "tasting-note",
        "authoredBy": [
          "club-member"
        ],
        "description": "Attach a DEBUG-class tasting note to a bottle."
      },
      {
        "name": "confirm_receipt",
        "category": "custody-transfer",
        "authoredBy": [
          "club-member",
          "retailer"
        ],
        "description": "Confirm inbound custody, closing the transfer."
      },
      {
        "name": "report_quality_issue",
        "category": "care-event",
        "authoredBy": [
          "club-member",
          "retailer"
        ],
        "description": "Report a quality issue against a bottle (open read-issue)."
      },
      {
        "name": "thermo_flag",
        "category": "care-event",
        "authoredBy": [
          "dock-handler"
        ],
        "description": "Manual care-event for a flipped thermochromic sticker."
      }
    ]
  }
}

```
