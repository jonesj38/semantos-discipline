---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/cartridge.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.412562+00:00
---

# cartridges/oddjobz/cartridge.json

```json
{
  "id": "oddjobz",
  "name": "Oddjobz",
  "version": "0.1.0",
  "ratificationThreshold": 0.85,
  "role": "experience",
  "experience": {
    "flutterPackage": "cartridges/oddjobz/experience"
  },
  "description": "Trades / services vertical cartridge \u2014 8 canonical cell types (job, quote, visit, invoice, customer, site, estimate, message) with stable type-hashes, conformance vectors, and linearity flags per ODDJOBZ-EXTENSION-PLAN.md \u00a7O2.",
  "taxonomyPath": "brain/src/cell-types/index.ts",
  "flowsDir": "brain/src/state-machines",
  "promptsDir": "brain/src/prompts",
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
      "description": "A physical location where jobs are performed. The most stable node in the graph \u2014 tenants/agencies cycle but the address persists; route optimisation and accumulated site-knowledge anchor here.",
      "payloadSchema": {
        "normalisedAddress": {
          "type": "string",
          "tier": "core",
          "description": "Canonical normalised address \u2014 the primary surfacing string"
        },
        "fullAddress": {
          "type": "string",
          "tier": "core",
          "description": "Original full address as provided/extracted"
        },
        "lookupKey": {
          "type": "string",
          "tier": "core",
          "description": "Deterministic dedupe key derived from normalisedAddress + postcode"
        },
        "suburb": {
          "type": "string",
          "tier": "core",
          "description": "Suburb / locality (nullable on the wire)"
        },
        "postcode": {
          "type": "string",
          "tier": "core",
          "description": "Postcode / ZIP (nullable on the wire)"
        },
        "state": {
          "type": "string",
          "tier": "core",
          "description": "Geographic state / region (e.g. QLD, NSW). NOT an FSM state \u2014 sites have only the trivial 'active' phase."
        },
        "keyNumber": {
          "type": "string",
          "tier": "operator-extensible",
          "description": "REA/property-manager key-number reference (Todd 2026-05-20: REA-side; not universal but relevant if oddjobz is used by an REA operator)."
        },
        "signedBy": {
          "type": "string",
          "tier": "core",
          "description": "BRC-100 signer pubkey (hex-encoded, nullable on the wire)"
        },
        "signature": {
          "type": "string",
          "tier": "core",
          "description": "BRC-100 signature over the canonical payload (nullable on the wire)"
        }
      },
      "phases": [
        "active"
      ],
      "initialPhase": "active"
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
      "description": "A person or organization in the job graph \u2014 role-tagged (tenant/agent/owner/pm/sub-tradie/other). Linked to a site via siteRef.",
      "payloadSchema": {
        "id": {
          "type": "string",
          "tier": "core",
          "description": "Stable customer identifier (UUID)"
        },
        "display_name": {
          "type": "string",
          "tier": "core",
          "description": "Display name (person or organization)"
        },
        "phone": {
          "type": "string",
          "tier": "core",
          "description": "Primary phone (raw form)"
        },
        "email": {
          "type": "string",
          "tier": "core",
          "description": "Primary email"
        },
        "address": {
          "type": "string",
          "tier": "core",
          "description": "Mailing / contact address (may differ from the linked site)"
        },
        "notes": {
          "type": "string",
          "tier": "operator-extensible",
          "description": "Free-form notes. FLAGGED (Todd 2026-05-20): conceptually these are conversational events that accrue per-job \u2014 quoting/invoicing context, shopping lists, dependencies/blockers. End-state: migrate to scg / conversation cells anchored to job+customer (CC6+ work)."
        },
        "created_at": {
          "type": "datetime",
          "tier": "core",
          "description": "ISO 8601 creation timestamp"
        },
        "role": {
          "type": "enum",
          "enum": [
            "tenant",
            "agent",
            "owner",
            "pm",
            "sub-tradie",
            "other"
          ],
          "tier": "core",
          "description": "Relationship role to the job/site"
        },
        "normalisedPhone": {
          "type": "string",
          "tier": "core",
          "description": "E.164-normalised phone for dedupe (nullable on the wire)"
        },
        "sourceProvenance": {
          "type": "object",
          "tier": "core",
          "description": "Where this customer record came from \u2014 { providerId, providerItemId, extractedAt }. Audit metadata; universal."
        },
        "siteRef": {
          "type": "string",
          "tier": "core",
          "description": "Graph ref to the linked site cell (hex cellId, 64 chars; nullable on the wire)"
        },
        "signedBy": {
          "type": "string",
          "tier": "core",
          "description": "BRC-100 signer pubkey (nullable on the wire)"
        },
        "signature": {
          "type": "string",
          "tier": "core",
          "description": "BRC-100 signature (nullable on the wire)"
        }
      },
      "phases": [
        "active"
      ],
      "initialPhase": "active"
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
      "description": "A unit of work at a site \u2014 the central work-FSM cell. State transitions append versioned cells; the FSM operates on state strings only and is orthogonal to this payload's field shape (see CC5-SCHEMA-SECTION-IMPL-SPEC \u00a72.1).",
      "payloadSchema": {
        "customer_name": {
          "type": "string",
          "tier": "core",
          "description": "Denormalised display name of the primary customer (for list rendering)"
        },
        "state": {
          "type": "enum",
          "enum": [
            "lead",
            "qualified",
            "visit_pending",
            "visit_scheduled",
            "visited",
            "quoted",
            "authorized",
            "scheduled",
            "in_progress",
            "completed",
            "invoiced",
            "paid",
            "closed"
          ],
          "tier": "core",
          "description": "FSM state \u2014 one of the 13 canonical job phases. The FSM (job_fsm.zig) gates transitions on this field only; never inspects other payload fields."
        },
        "scheduled_at": {
          "type": "datetime",
          "tier": "core",
          "description": "When the job is/was scheduled (ISO 8601; empty string when not yet scheduled)"
        },
        "created_at": {
          "type": "datetime",
          "tier": "core",
          "description": "ISO 8601 creation timestamp"
        },
        "workOrderNumber": {
          "type": "string",
          "tier": "operator-extensible",
          "description": "REA/PM-issued work-order number (e.g. PropertyMe WO#). PM-shape \u2014 not universal across trades."
        },
        "issuanceDate": {
          "type": "date",
          "tier": "operator-extensible",
          "description": "Date the WO was issued by the upstream PM system. PM-shape."
        },
        "dueDate": {
          "type": "date",
          "tier": "core",
          "description": "When the job is due. Universal across trades; the source-adapter fills it (REA WO 'Due:' line, urgency-derived, operator-set, or contract-recurrence)."
        },
        "billingParty": {
          "type": "object",
          "tier": "operator-extensible",
          "description": "Who pays the bill \u2014 { type: 'agency'|'owner', name: string }. PM-shape; not relevant for direct-to-customer trades."
        },
        "hasPhotos": {
          "type": "boolean",
          "tier": "operator-extensible",
          "description": "Whether the job has photo attachments. FLAGGED (Todd 2026-05-20): this is *workflow surfacing*, not a stored fact. End-state: CC7's renderer derives it from attachmentRefs.filter(image) instead of storing."
        },
        "photoCount": {
          "type": "number",
          "tier": "operator-extensible",
          "description": "Count of photo attachments. Same future-derived note as hasPhotos."
        },
        "propertyKey": {
          "type": "string",
          "tier": "operator-extensible",
          "description": "PM key-number reference (e.g. 'key #177'). PM-shape \u2014 duplicates site.keyNumber for job-detail convenience."
        },
        "siteRef": {
          "type": "string",
          "tier": "core",
          "description": "Graph ref to the site cell (hex cellId, 64 chars). REQUIRED \u2014 the primary anchor; per CC7 \u00a73.5 site is oddjobz's surfacing primary."
        },
        "customerRefs": {
          "type": "array",
          "tier": "core",
          "description": "Array of { cellId, role, primary } refs to customer cells linked to this job. Exactly one entry MUST have primary: true."
        },
        "attachmentRefs": {
          "type": "array",
          "tier": "core",
          "description": "Array of attachment cellIds (hex, 64 chars each). Graph ref."
        },
        "signedBy": {
          "type": "string",
          "tier": "core",
          "description": "BRC-100 signer pubkey (nullable on the wire)"
        },
        "signature": {
          "type": "string",
          "tier": "core",
          "description": "BRC-100 signature (nullable on the wire)"
        }
      },
      "phases": [
        "lead",
        "qualified",
        "visit_pending",
        "visit_scheduled",
        "visited",
        "quoted",
        "authorized",
        "scheduled",
        "in_progress",
        "completed",
        "invoiced",
        "paid",
        "closed"
      ],
      "initialPhase": "lead"
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
      "description": "Pre-job interest \u2014 ratifies into Job once accepted."
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
      "description": "Chat/voice/image message between customer and operator."
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
      "description": "An operator on-site visit \u2014 origin of attachments and notes."
    }
  ],
  "capabilitiesPath": "brain/src/capabilities.ts",
  "wssSubprotocols": [],
  "verbs": [
    {
      "name": "oddjobz.ratify_proposal",
      "capability_required": "cap.oddjobz.quote"
    },
    {
      "name": "jobs.transition",
      "capability_required": "cap.oddjobz.dispatch"
    },
    {
      "name": "quotes.draft",
      "capability_required": "cap.oddjobz.quote"
    },
    {
      "name": "invoices.send",
      "capability_required": "cap.oddjobz.invoice"
    }
  ],
  "consumes": {
    "StorageAdapter": "required \u2014 for jobs/quotes/invoices/customers/leads/visits stores (post-DLO.3 migration)",
    "IdentityAdapter": "required \u2014 for hat-rooted authority on per-cell ownership"
  },
  "brain": {
    "handlers": [
      { "module": "registration" }
    ]
  },
  "ui": {
    "primaryAnchor": "oddjobz.site",
    "hierarchy": [
      "oddjobz.site",
      "oddjobz.customer",
      "oddjobz.job",
      "oddjobz.attachment"
    ],
    "surfacingMode": "default",
    "verbs": [
      { "modal": "do", "label": "New job", "intentType": "oddjobz.job.create", "subtitle": "log a new job", "icon": "build" },
      { "modal": "do", "label": "New quote", "intentType": "oddjobz.quote.create", "subtitle": "draft a quote for a customer", "icon": "request_quote" },
      { "modal": "do", "label": "Log visit", "intentType": "oddjobz.visit.create", "subtitle": "record a site visit", "icon": "location_on" },
      { "modal": "do", "label": "Send invoice", "intentType": "oddjobz.invoice.create", "subtitle": "invoice completed work", "icon": "receipt_long" },
      { "modal": "find", "label": "Find customer", "intentType": "oddjobz.customer.find", "subtitle": "look up a contact", "icon": "person_search" },
      { "modal": "find", "label": "Find job", "intentType": "oddjobz.job.find", "subtitle": "lookup by site, status, etc.", "icon": "search" }
    ]
  },
  "peerView": {
    "label": "Customer",
    "pluralLabel": "Customers",
    "emptyState": "No customers yet — they appear when you send your first quote.",
    "filterEdgeTypes": ["REQUESTS_ACTION", "FULFILLS"],
    "defaultFace": "commercial",
    "primaryEdgeTypes": ["REQUESTS_ACTION", "FULFILLS", "TRANSFER"],
    "verbs": ["oddjobz.job.create", "oddjobz.quote.draft"]
  },
  "_notes": {
    "boot_loading": "Brain-core's extensions.zig currently registers oddjobz via hardcoded BUILTIN_MANIFESTS for V1 production safety. After DLO.1c lands the full delivery/revocation flow, this cartridge.json becomes the primary registration source and the hardcoded path is removed (DLO.6 audit gate). The runtime install convention remains <data_dir>/extensions/<id>/ (a separate filesystem contract from this repo source home \u2014 CC4 source-tree-only collapse).",
    "manifest_format": "Phase 36A ExtensionManifest config.json shape per core/protocol-types/src/extension-manifest.ts.",
    "cc5_b2a_objecttypes": "objectTypes[] added 2026-05-20 (CC5.B2a; PR will follow). ADDITIVE: objectTypesDir stays for CC0a back-compat; the .v2.ts files are NOT deleted in this PR (that's CC5.B2b). tier judgments per Todd 2026-05-20; primaryAnchor=site per CC7 v0.3 \u00a73.5; schema-extension-mechanism (a) per CARTRIDGE-SCHEMA-EXTENSION-MECHANISM.md \u2014 plumber/cleaner trade overlays are (b), pending CC6.",
    "cc7_derived_fields_followup": "hasPhotos/photoCount tier-flagged operator-extensible but conceptually derived from attachmentRefs \u2014 CC7 renderer follow-up.",
    "scg_notes_migration_followup": "customer.notes tier-flagged operator-extensible but conceptually conversational events \u2014 should migrate to scg/conversation cells anchored to job+customer in a later wave."
  }
}

```
