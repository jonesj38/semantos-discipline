---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/extractor/cell-schema.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.157112+00:00
---

# runtime/legacy-ingest/src/extractor/cell-schema.json

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "$id": "https://semantos.dev/schema/reingest/cell-schema.v1.json",
  "title": "Reingest typed-cell schema",
  "description": "Canonical contract for LLM-produced reingest payloads. Mirrors the cell-shape tables in docs/prd/D-Reingest-Typed-Cells.md. D-RTC.4 cell encoding validates against this before invoking substrate_entity.encodeCell.",
  "definitions": {
    "ContactRole": {
      "type": "string",
      "enum": [
        "site_owner",
        "tenant",
        "property_manager",
        "agent",
        "contractor",
        "witness",
        "unknown"
      ],
      "description": "Reingest contact role taxonomy. Maps from the legacy ProposalContact.role (tenant|agent|owner|pm|other) at the D-RTC.4 encoding boundary: owner→site_owner, pm→property_manager, other→unknown."
    },
    "Contact": {
      "type": "object",
      "properties": {
        "name": { "type": "string", "minLength": 1 },
        "role": { "$ref": "#/definitions/ContactRole" },
        "email": { "type": ["string", "null"], "format": "email" },
        "phone": { "type": ["string", "null"] },
        "notes": { "type": ["string", "null"] }
      },
      "required": ["name", "role"],
      "additionalProperties": false
    },
    "JobIntent": {
      "type": "string",
      "enum": [
        "quote_request",
        "work_order",
        "maintenance_order",
        "thread_followup",
        "not_a_job"
      ],
      "description": "WHY the email is in the inbox. Only the first three create job cells; the latter two short-circuit."
    },
    "Site": {
      "description": "TAG_SITE = 0x07. Indexed by lookupKey for dedupe.",
      "type": "object",
      "properties": {
        "lookupKey": {
          "type": "string",
          "minLength": 1,
          "description": "<normalizedAddress>|<keyNumber> — derived by D-RTC.1b deriveLookupKey()"
        },
        "normalizedAddress": {
          "type": "string",
          "minLength": 1,
          "description": "Output of D-RTC.1a normalizeAddress(). Stable canonical form."
        },
        "keyNumber": {
          "type": ["string", "null"],
          "description": "Sub-address discriminator (unit/lot/office number)."
        },
        "rawAddress": {
          "type": "string",
          "minLength": 1,
          "description": "Original free-text address as it appeared in the email."
        }
      },
      "required": ["lookupKey", "normalizedAddress", "rawAddress"],
      "additionalProperties": false
    },
    "Customer": {
      "description": "TAG_CUSTOMER = 0x01. One per role-classified contact, linked to a site.",
      "type": "object",
      "properties": {
        "name": { "type": "string", "minLength": 1 },
        "email": { "type": ["string", "null"], "format": "email" },
        "phone": { "type": ["string", "null"] },
        "role": { "$ref": "#/definitions/ContactRole" },
        "linkedSiteId": {
          "type": ["string", "null"],
          "pattern": "^[0-9a-f]{64}$",
          "description": "Hex site_cell_id from D-RTC.1b. Null when the contact isn't tied to a site (rare)."
        },
        "notes": {
          "type": ["string", "null"],
          "description": "LLM-summarised — e.g. 'prefers SMS, weekdays only'."
        }
      },
      "required": ["name", "role"],
      "additionalProperties": false
    },
    "Job": {
      "description": "TAG_JOB = 0x06. The keystone cell — chat resolution (\"quote 500 for the pergola job\") indexes on this.",
      "type": "object",
      "properties": {
        "siteRef": {
          "type": ["string", "null"],
          "pattern": "^[0-9a-f]{64}$",
          "description": "Hex site_cell_id (D-RTC.1b proposedCellId or matched existing)."
        },
        "customerRefs": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "cellId": { "type": "string", "pattern": "^[0-9a-f]{64}$" },
              "role": { "$ref": "#/definitions/ContactRole" },
              "primary": { "type": "boolean" }
            },
            "required": ["cellId", "role", "primary"],
            "additionalProperties": false
          },
          "minItems": 0
        },
        "workOrderNumber": {
          "type": ["string", "null"],
          "description": "Verbatim WO# from the source PDF — e.g. '07487', 'RJR-2025-0142'."
        },
        "services": {
          "type": "array",
          "items": { "type": "string", "minLength": 1 },
          "description": "Short service tags — 'plumbing', 'roof-repair', 'pergola', 'leak-investigation'. Drives chat-resolution match ('quote the pergola job' → this cell)."
        },
        "issuanceDate": {
          "type": ["string", "null"],
          "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}$",
          "description": "ISO YYYY-MM-DD from 'Created:' line."
        },
        "dueDate": {
          "type": ["string", "null"],
          "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}$",
          "description": "ISO YYYY-MM-DD from 'Due:' line."
        },
        "intent": { "$ref": "#/definitions/JobIntent" },
        "summary": {
          "type": "string",
          "minLength": 1,
          "description": "Free-form summary in operator voice."
        },
        "displayName": {
          "type": "string",
          "minLength": 1,
          "description": "What helm + mobile show in the JobList. Usually point_of_contact."
        },
        "rawPdfBlobSha256": {
          "type": ["string", "null"],
          "pattern": "^[0-9a-f]{64}$",
          "description": "Content hash of the source PDF in the blob-store. Retains the verbatim PDF."
        },
        "hasPictures": {
          "type": "boolean",
          "description": "True if any image attachment was detected — even if extraction failed."
        },
        "pictureCount": {
          "type": ["number", "null"],
          "description": "Best-effort count of distinct images."
        }
      },
      "required": ["intent", "summary", "displayName", "services", "customerRefs", "hasPictures"],
      "additionalProperties": false
    },
    "Attachment": {
      "description": "TAG_ATTACHMENT = 0x05. One per file attached to the source email; PDFs always retained verbatim.",
      "type": "object",
      "properties": {
        "mimeType": { "type": "string", "minLength": 1 },
        "filename": { "type": ["string", "null"] },
        "blobSha256": {
          "type": "string",
          "pattern": "^[0-9a-f]{64}$",
          "description": "Content-addressed hash; bytes live in blob-store."
        },
        "parentCellId": {
          "type": "string",
          "pattern": "^[0-9a-f]{64}$",
          "description": "The job (or customer) cell this attaches to."
        },
        "extractionStatus": {
          "type": "string",
          "enum": [
            "stored_verbatim",
            "image_extracted",
            "pdf_text_extracted",
            "failed"
          ]
        },
        "hasPictures": {
          "type": "boolean",
          "description": "Mirrors parent job's hasPictures for index speed."
        }
      },
      "required": ["mimeType", "blobSha256", "parentCellId", "extractionStatus", "hasPictures"],
      "additionalProperties": false
    },
    "ReingestProposal": {
      "description": "What the upgraded extractor produces — a graph of cells. D-RTC.4 lowers this into substrate_entity.encodeCell calls.",
      "type": "object",
      "properties": {
        "intent": { "$ref": "#/definitions/JobIntent" },
        "site": { "anyOf": [{ "$ref": "#/definitions/Site" }, { "type": "null" }] },
        "customers": {
          "type": "array",
          "items": { "$ref": "#/definitions/Customer" }
        },
        "job": { "anyOf": [{ "$ref": "#/definitions/Job" }, { "type": "null" }] },
        "attachments": {
          "type": "array",
          "items": { "$ref": "#/definitions/Attachment" }
        }
      },
      "required": ["intent", "customers", "attachments"],
      "additionalProperties": false
    }
  }
}

```
