---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-36F-CONNECTOR-REFERENCE-IMPL.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.661235+00:00
---

# Phase 36F — Connector Reference Implementation (PropertyMe)

**Version**: 1.0
**Date**: April 2026
**Status**: Pending Phase 36A-36D gate passes
**Duration**: 2 weeks (with 3-day buffer)
**Prerequisites**: Phase 36A (grammar schema), Phase 36B (extraction pipeline), Phase 36D (governance model) — all must be complete. Phase 36E (UI) recommended but not required.
**Master document**: `PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md`
**Branch**: `phase-36f-connector-reference-impl`

---

## Context

Phase 36 builds the extension ecosystem by extracting the pattern of domain-specific connectors into a reusable framework: declarative Extension Grammar JSON, a staged extraction pipeline, hierarchical governance, and a marketplace. Phases 36A (schema), 36B (pipeline), 36C (inference agent), and 36D (governance) define the architecture. This phase proves the architecture works end-to-end by building the first real connector: **PropertyMe**.

PropertyMe is a property management SaaS API used by Australian property managers. It exposes entities like Properties, Leases, Tenants, Owners, MaintenanceRequests, Inspections, Documents, and Contacts. This connector serves three purposes:

1. **Validation** — proves that Extension Grammar + Extraction Pipeline + Governance Model can handle a real-world API with all its complexity (authentication, pagination, rate limits, complex field mappings, FSM state transitions, relationships)
2. **Reference** — establishes the gold standard for how third-party developers should build connectors, with clear patterns, documented trade-offs, and complete examples
3. **Revenue** — this is a first-party extension sold on the Semantos marketplace, shipped with the property management product, generating recurring subscription revenue

The connector MUST be built entirely through the framework. No special-casing, no bypass of the pipeline, no hardcoded logic. If the framework can't handle PropertyMe, the framework is incomplete.

---

## PropertyMe API Overview

**Source system**: PropertyMe REST API v2 (Australian property management SaaS)

**Authentication**: OAuth2 (client_id, client_secret, tenant_id)

**Pagination**: Cursor-based with configurable page size

**Rate limiting**: 100 requests per minute

**Core entities** (10+ types):
- `Property` — address, title reference, zoning, status
- `Lease` — tenant, term, rent, bond, break clauses
- `Tenant` — contact, payment history, references
- `Owner` — landlord, banking details, communication preference
- `MaintenanceRequest` — description, photos, urgency, status FSM
- `Inspection` — type, scheduled/completed date, condition report
- `Document` — lease, invoice, certificate, photo
- `Contact` — shared contact management
- `Invoice` — tradie billing, line items
- `Receipt` — payment receipts, bond credits
- `OwnerStatement` — financial summary for landlord

**Relationships** (critical for extraction correctness):
- Property has_many Leases
- Lease belongs_to Property, has_many Tenants
- Property has_many MaintenanceRequests
- MaintenanceRequest belongs_to Property + Tenant
- Inspection belongs_to Property + Lease
- Document has polymorphic parent_id + parent_type
- Owner references Property (1:many)

**State machine example (MaintenanceRequest)**:
```
new → triaged → awaiting_approval → approved → dispatched →
  in_progress → completed → invoiced → closed
```

Maps to Semantos commerce phases: SOURCE → PARSE → TYPECHECK → ACTION → OUTCOME

---

## Deliverables

### D36F.1 — PropertyMe Extension Grammar

**File**: `configs/extensions/propertyme/grammar.json`

Complete Extension Grammar JSON per Phase 36A schema. No stubs, no placeholders.

**Structure** (complete JSON with all sections):

```json
{
  "metaSchemaVersion": "1.0.0",
  "grammarId": "com.semantos.propertyme",
  "grammarVersion": "1.0.0",
  "displayName": "PropertyMe Connector",
  "description": "Real-time property management data extraction from PropertyMe API. Covers properties, leases, tenants, maintenance requests, inspections, and compliance tracking.",
  "author": {
    "certId": "semantos-core-first-party",
    "name": "Semantos Inc.",
    "contact": "support@semantos.io"
  },
  "extends": null,
  
  "source": {
    "protocol": "rest",
    "baseUrlTemplate": "https://api.propertyme.com/v2",
    "auth": {
      "type": "oauth2",
      "requiredCredentials": ["client_id", "client_secret", "tenant_id"],
      "oauth2Config": {
        "authorizationUrl": "https://auth.propertyme.com/oauth/authorize",
        "tokenUrl": "https://auth.propertyme.com/oauth/token",
        "scopes": ["read:properties", "read:leases", "read:tenants", "read:maintenance", "read:inspections"]
      }
    },
    "rateLimits": {
      "requestsPerMinute": 100,
      "concurrentRequests": 5
    },
    "pagination": {
      "type": "cursor",
      "pageSize": 50,
      "cursorField": "next_cursor",
      "totalField": "total_count"
    },
    "entities": [
      {
        "entityId": "property",
        "displayName": "Property",
        "endpoint": {
          "list": "/properties",
          "get": "/properties/{id}",
          "webhookEvent": "property.updated"
        },
        "method": "GET",
        "responseShape": {
          "dataPath": "$.data.properties",
          "idField": "id",
          "timestampField": "updated_at"
        },
        "fields": [
          {
            "sourceFieldName": "id",
            "sourceType": "string",
            "required": true,
            "description": "Unique property identifier"
          },
          {
            "sourceFieldName": "address",
            "sourceType": "object",
            "required": true,
            "description": "Property address object with street_number, street_name, street_type, suburb, state, postcode"
          },
          {
            "sourceFieldName": "property_type",
            "sourceType": "enum",
            "required": true,
            "enumValues": ["house", "unit", "townhouse", "land", "commercial"],
            "description": "Type of property"
          },
          {
            "sourceFieldName": "bedrooms",
            "sourceType": "number",
            "required": false
          },
          {
            "sourceFieldName": "bathrooms",
            "sourceType": "number",
            "required": false
          },
          {
            "sourceFieldName": "parking",
            "sourceType": "number",
            "required": false
          },
          {
            "sourceFieldName": "status",
            "sourceType": "enum",
            "required": true,
            "enumValues": ["active", "archived", "under_management", "pending_settlement"]
          },
          {
            "sourceFieldName": "title_reference",
            "sourceType": "string",
            "required": false
          },
          {
            "sourceFieldName": "zoning",
            "sourceType": "string",
            "required": false
          },
          {
            "sourceFieldName": "insurance_provider",
            "sourceType": "string",
            "required": false
          },
          {
            "sourceFieldName": "insurance_expiry",
            "sourceType": "date",
            "required": false
          }
        ],
        "relationships": [
          {
            "targetEntityId": "lease",
            "type": "has_many",
            "foreignKey": "property_id",
            "foreignKeyLocation": "target"
          },
          {
            "targetEntityId": "maintenance_request",
            "type": "has_many",
            "foreignKey": "property_id",
            "foreignKeyLocation": "target"
          },
          {
            "targetEntityId": "inspection",
            "type": "has_many",
            "foreignKey": "property_id",
            "foreignKeyLocation": "target"
          },
          {
            "targetEntityId": "owner",
            "type": "has_many",
            "foreignKey": "property_id",
            "foreignKeyLocation": "target"
          }
        ]
      },
      {
        "entityId": "lease",
        "displayName": "Lease",
        "endpoint": {
          "list": "/leases",
          "get": "/leases/{id}",
          "webhookEvent": "lease.updated"
        },
        "method": "GET",
        "responseShape": {
          "dataPath": "$.data.leases",
          "idField": "id",
          "timestampField": "updated_at"
        },
        "fields": [
          {
            "sourceFieldName": "id",
            "sourceType": "string",
            "required": true
          },
          {
            "sourceFieldName": "property_id",
            "sourceType": "string",
            "required": true,
            "description": "Foreign key to Property"
          },
          {
            "sourceFieldName": "tenant_ids",
            "sourceType": "array",
            "required": true,
            "description": "Array of tenant IDs on this lease"
          },
          {
            "sourceFieldName": "start_date",
            "sourceType": "date",
            "required": true
          },
          {
            "sourceFieldName": "end_date",
            "sourceType": "date",
            "required": true
          },
          {
            "sourceFieldName": "rent_amount",
            "sourceType": "number",
            "required": true,
            "description": "Weekly rent in cents"
          },
          {
            "sourceFieldName": "rent_frequency",
            "sourceType": "enum",
            "required": true,
            "enumValues": ["weekly", "fortnightly", "monthly"]
          },
          {
            "sourceFieldName": "bond_amount",
            "sourceType": "number",
            "required": false
          },
          {
            "sourceFieldName": "bond_lodgement_ref",
            "sourceType": "string",
            "required": false
          },
          {
            "sourceFieldName": "break_clause",
            "sourceType": "boolean",
            "required": false
          },
          {
            "sourceFieldName": "break_notice_period",
            "sourceType": "number",
            "required": false,
            "description": "Days notice required for break"
          },
          {
            "sourceFieldName": "renewal_date",
            "sourceType": "date",
            "required": false
          },
          {
            "sourceFieldName": "renewal_status",
            "sourceType": "enum",
            "required": false,
            "enumValues": ["pending", "renewed", "expired", "terminated"]
          },
          {
            "sourceFieldName": "status",
            "sourceType": "enum",
            "required": true,
            "enumValues": ["draft", "active", "expiring", "expired", "terminated", "break_notice"]
          }
        ],
        "relationships": [
          {
            "targetEntityId": "property",
            "type": "belongs_to",
            "foreignKey": "property_id",
            "foreignKeyLocation": "source"
          },
          {
            "targetEntityId": "tenant",
            "type": "has_many",
            "foreignKey": "id",
            "foreignKeyLocation": "source"
          }
        ]
      },
      {
        "entityId": "tenant",
        "displayName": "Tenant",
        "endpoint": {
          "list": "/tenants",
          "get": "/tenants/{id}"
        },
        "method": "GET",
        "responseShape": {
          "dataPath": "$.data.tenants",
          "idField": "id",
          "timestampField": "updated_at"
        },
        "fields": [
          {
            "sourceFieldName": "id",
            "sourceType": "string",
            "required": true
          },
          {
            "sourceFieldName": "name",
            "sourceType": "string",
            "required": true
          },
          {
            "sourceFieldName": "phone",
            "sourceType": "string",
            "required": false
          },
          {
            "sourceFieldName": "email",
            "sourceType": "string",
            "required": false
          },
          {
            "sourceFieldName": "emergency_contact",
            "sourceType": "string",
            "required": false
          },
          {
            "sourceFieldName": "id_verified",
            "sourceType": "boolean",
            "required": false
          },
          {
            "sourceFieldName": "payment_history",
            "sourceType": "enum",
            "required": false,
            "enumValues": ["good", "late_occasional", "late_frequent", "arrears"]
          },
          {
            "sourceFieldName": "status",
            "sourceType": "enum",
            "required": true,
            "enumValues": ["prospective", "active", "vacating", "former"]
          }
        ]
      },
      {
        "entityId": "owner",
        "displayName": "Owner",
        "endpoint": {
          "list": "/owners",
          "get": "/owners/{id}"
        },
        "method": "GET",
        "responseShape": {
          "dataPath": "$.data.owners",
          "idField": "id",
          "timestampField": "updated_at"
        },
        "fields": [
          {
            "sourceFieldName": "id",
            "sourceType": "string",
            "required": true
          },
          {
            "sourceFieldName": "name",
            "sourceType": "string",
            "required": true
          },
          {
            "sourceFieldName": "phone",
            "sourceType": "string",
            "required": false
          },
          {
            "sourceFieldName": "email",
            "sourceType": "string",
            "required": false
          },
          {
            "sourceFieldName": "entity_type",
            "sourceType": "enum",
            "required": true,
            "enumValues": ["individual", "company", "trust", "smsf"]
          },
          {
            "sourceFieldName": "abn",
            "sourceType": "string",
            "required": false
          },
          {
            "sourceFieldName": "maintenance_approval_threshold",
            "sourceType": "number",
            "required": false,
            "description": "Dollar amount in cents — above this requires approval"
          },
          {
            "sourceFieldName": "status",
            "sourceType": "enum",
            "required": true,
            "enumValues": ["active", "archived"]
          }
        ]
      },
      {
        "entityId": "maintenance_request",
        "displayName": "Maintenance Request",
        "endpoint": {
          "list": "/maintenance-requests",
          "get": "/maintenance-requests/{id}",
          "webhookEvent": "maintenance.created"
        },
        "method": "GET",
        "responseShape": {
          "dataPath": "$.data.maintenance_requests",
          "idField": "id",
          "timestampField": "updated_at"
        },
        "fields": [
          {
            "sourceFieldName": "id",
            "sourceType": "string",
            "required": true
          },
          {
            "sourceFieldName": "property_id",
            "sourceType": "string",
            "required": true
          },
          {
            "sourceFieldName": "lease_id",
            "sourceType": "string",
            "required": false
          },
          {
            "sourceFieldName": "tenant_id",
            "sourceType": "string",
            "required": false
          },
          {
            "sourceFieldName": "description",
            "sourceType": "string",
            "required": true
          },
          {
            "sourceFieldName": "category",
            "sourceType": "string",
            "required": true,
            "description": "Service category path: services.trades.plumbing, etc."
          },
          {
            "sourceFieldName": "urgency",
            "sourceType": "enum",
            "required": true,
            "enumValues": ["emergency", "urgent", "routine", "cosmetic"]
          },
          {
            "sourceFieldName": "reported_by",
            "sourceType": "enum",
            "required": true,
            "enumValues": ["tenant", "inspection", "owner", "pm"]
          },
          {
            "sourceFieldName": "responsible_party",
            "sourceType": "enum",
            "required": true,
            "enumValues": ["landlord", "tenant", "strata", "insurance"]
          },
          {
            "sourceFieldName": "estimated_cost",
            "sourceType": "number",
            "required": false,
            "description": "Estimated cost in cents"
          },
          {
            "sourceFieldName": "approval_status",
            "sourceType": "enum",
            "required": true,
            "enumValues": ["pending_pm", "pending_owner", "approved", "declined"]
          },
          {
            "sourceFieldName": "status",
            "sourceType": "enum",
            "required": true,
            "enumValues": ["new", "triaged", "awaiting_approval", "approved", "dispatched", "in_progress", "completed", "invoiced", "closed"]
          }
        ],
        "relationships": [
          {
            "targetEntityId": "property",
            "type": "belongs_to",
            "foreignKey": "property_id",
            "foreignKeyLocation": "source"
          },
          {
            "targetEntityId": "tenant",
            "type": "belongs_to",
            "foreignKey": "tenant_id",
            "foreignKeyLocation": "source"
          }
        ]
      },
      {
        "entityId": "inspection",
        "displayName": "Inspection",
        "endpoint": {
          "list": "/inspections",
          "get": "/inspections/{id}"
        },
        "method": "GET",
        "responseShape": {
          "dataPath": "$.data.inspections",
          "idField": "id",
          "timestampField": "updated_at"
        },
        "fields": [
          {
            "sourceFieldName": "id",
            "sourceType": "string",
            "required": true
          },
          {
            "sourceFieldName": "property_id",
            "sourceType": "string",
            "required": true
          },
          {
            "sourceFieldName": "lease_id",
            "sourceType": "string",
            "required": false
          },
          {
            "sourceFieldName": "inspection_type",
            "sourceType": "enum",
            "required": true,
            "enumValues": ["routine", "entry", "exit", "pre_sale", "compliance"]
          },
          {
            "sourceFieldName": "scheduled_date",
            "sourceType": "datetime",
            "required": true
          },
          {
            "sourceFieldName": "completed_date",
            "sourceType": "datetime",
            "required": false
          },
          {
            "sourceFieldName": "overall_condition",
            "sourceType": "enum",
            "required": false,
            "enumValues": ["excellent", "good", "fair", "poor"]
          },
          {
            "sourceFieldName": "status",
            "sourceType": "enum",
            "required": true,
            "enumValues": ["scheduled", "in_progress", "draft_report", "published", "acknowledged"]
          }
        ]
      },
      {
        "entityId": "document",
        "displayName": "Document",
        "endpoint": {
          "list": "/documents",
          "get": "/documents/{id}"
        },
        "method": "GET",
        "responseShape": {
          "dataPath": "$.data.documents",
          "idField": "id",
          "timestampField": "updated_at"
        },
        "fields": [
          {
            "sourceFieldName": "id",
            "sourceType": "string",
            "required": true
          },
          {
            "sourceFieldName": "parent_id",
            "sourceType": "string",
            "required": true,
            "description": "ID of parent object (property, lease, maintenance request, etc.)"
          },
          {
            "sourceFieldName": "parent_type",
            "sourceType": "enum",
            "required": true,
            "enumValues": ["property", "lease", "maintenance_request", "inspection"]
          },
          {
            "sourceFieldName": "document_type",
            "sourceType": "enum",
            "required": true,
            "enumValues": ["lease", "condition_report", "invoice", "certificate", "photo", "correspondence", "notice"]
          },
          {
            "sourceFieldName": "filename",
            "sourceType": "string",
            "required": true
          },
          {
            "sourceFieldName": "mime_type",
            "sourceType": "string",
            "required": true
          },
          {
            "sourceFieldName": "storage_url",
            "sourceType": "string",
            "required": true,
            "description": "URL to access the document"
          },
          {
            "sourceFieldName": "status",
            "sourceType": "enum",
            "required": true,
            "enumValues": ["draft", "current", "superseded", "archived"]
          }
        ]
      }
    ]
  },

  "objectTypes": [
    {
      "typePath": "property.dwelling",
      "displayName": "Property",
      "description": "A residential or commercial property under management",
      "linearity": "RELEVANT",
      "phases": ["SOURCE", "PARSE", "TYPECHECK", "ACTION", "OUTCOME"],
      "initialPhase": "SOURCE",
      "payloadSchema": {
        "id": { "type": "string" },
        "address": { "type": "string" },
        "propertyType": { "type": "enum", "enum": ["house", "unit", "townhouse", "land", "commercial"] },
        "bedrooms": { "type": "number" },
        "bathrooms": { "type": "number" },
        "parking": { "type": "number" },
        "titleReference": { "type": "string" },
        "zoning": { "type": "string" },
        "insuranceProvider": { "type": "string" },
        "insuranceExpiry": { "type": "date" },
        "status": { "type": "string" }
      },
      "capabilities": {
        "read": [0, 1],
        "write": [0, 1],
        "approve": [0]
      }
    },
    {
      "typePath": "property.lease",
      "displayName": "Lease",
      "description": "A lease agreement between landlord and tenant(s)",
      "linearity": "LINEAR",
      "phases": ["SOURCE", "ACTIVE", "EXPIRING", "EXPIRED", "TERMINATED"],
      "initialPhase": "SOURCE",
      "payloadSchema": {
        "id": { "type": "string" },
        "propertyId": { "type": "string" },
        "tenantIds": { "type": "array" },
        "startDate": { "type": "date" },
        "endDate": { "type": "date" },
        "rentAmount": { "type": "number" },
        "rentFrequency": { "type": "enum", "enum": ["weekly", "fortnightly", "monthly"] },
        "bondAmount": { "type": "number" },
        "breakClause": { "type": "boolean" },
        "status": { "type": "string" }
      },
      "capabilities": {
        "read": [0, 1],
        "write": [0, 1],
        "renew": [0]
      }
    },
    {
      "typePath": "property.tenant",
      "displayName": "Tenant",
      "description": "A person or entity renting a property",
      "linearity": "RELEVANT",
      "phases": ["SOURCE", "ACTIVE", "VACATING", "FORMER"],
      "initialPhase": "SOURCE",
      "payloadSchema": {
        "id": { "type": "string" },
        "name": { "type": "string" },
        "phone": { "type": "string" },
        "email": { "type": "string" },
        "idVerified": { "type": "boolean" },
        "paymentHistory": { "type": "string" },
        "status": { "type": "string" }
      },
      "capabilities": {
        "read": [0, 1],
        "write": [0],
        "reference_check": [0]
      }
    },
    {
      "typePath": "property.owner",
      "displayName": "Owner",
      "description": "A property owner or landlord",
      "linearity": "RELEVANT",
      "phases": ["SOURCE", "ACTIVE", "ARCHIVED"],
      "initialPhase": "SOURCE",
      "payloadSchema": {
        "id": { "type": "string" },
        "name": { "type": "string" },
        "phone": { "type": "string" },
        "email": { "type": "string" },
        "entityType": { "type": "enum", "enum": ["individual", "company", "trust", "smsf"] },
        "abn": { "type": "string" },
        "maintenanceApprovalThreshold": { "type": "number" },
        "status": { "type": "string" }
      },
      "capabilities": {
        "read": [0, 1],
        "write": [0],
        "approve_maintenance": [0]
      }
    },
    {
      "typePath": "property.maintenance-request",
      "displayName": "Maintenance Request",
      "description": "A request for property maintenance or repair",
      "linearity": "AFFINE",
      "phases": ["SOURCE", "TRIAGED", "AWAITING_APPROVAL", "APPROVED", "DISPATCHED", "IN_PROGRESS", "COMPLETED", "INVOICED", "CLOSED"],
      "initialPhase": "SOURCE",
      "payloadSchema": {
        "id": { "type": "string" },
        "propertyId": { "type": "string" },
        "tenantId": { "type": "string" },
        "description": { "type": "string" },
        "category": { "type": "string" },
        "urgency": { "type": "enum", "enum": ["emergency", "urgent", "routine", "cosmetic"] },
        "estimatedCost": { "type": "number" },
        "approvalStatus": { "type": "string" },
        "status": { "type": "string" }
      },
      "capabilities": {
        "create": [0, 1],
        "triage": [0],
        "approve": [0],
        "dispatch": [0],
        "complete": [0]
      }
    },
    {
      "typePath": "property.inspection",
      "displayName": "Inspection",
      "description": "A property inspection with condition report",
      "linearity": "AFFINE",
      "phases": ["SOURCE", "SCHEDULED", "IN_PROGRESS", "DRAFT_REPORT", "PUBLISHED", "ACKNOWLEDGED"],
      "initialPhase": "SOURCE",
      "payloadSchema": {
        "id": { "type": "string" },
        "propertyId": { "type": "string" },
        "inspectionType": { "type": "enum", "enum": ["routine", "entry", "exit", "pre_sale", "compliance"] },
        "scheduledDate": { "type": "datetime" },
        "completedDate": { "type": "datetime" },
        "overallCondition": { "type": "enum", "enum": ["excellent", "good", "fair", "poor"] },
        "status": { "type": "string" }
      },
      "capabilities": {
        "create": [0],
        "schedule": [0],
        "report": [0],
        "publish": [0]
      }
    },
    {
      "typePath": "property.document",
      "displayName": "Document",
      "description": "A document attached to a property, lease, or maintenance request",
      "linearity": "RELEVANT",
      "phases": ["SOURCE", "CURRENT", "SUPERSEDED", "ARCHIVED"],
      "initialPhase": "SOURCE",
      "payloadSchema": {
        "id": { "type": "string" },
        "parentId": { "type": "string" },
        "parentType": { "type": "string" },
        "documentType": { "type": "string" },
        "filename": { "type": "string" },
        "mimeType": { "type": "string" },
        "storageUrl": { "type": "string" },
        "status": { "type": "string" }
      },
      "capabilities": {
        "read": [0, 1],
        "upload": [0],
        "delete": [0]
      }
    }
  ],

  "entityMappings": [
    {
      "sourceEntityId": "property",
      "targetObjectType": "property.dwelling",
      "fieldMappings": [
        {
          "sourceField": "id",
          "targetField": "id",
          "required": true
        },
        {
          "sourceField": "address",
          "targetField": "address",
          "transform": {
            "type": "concat",
            "parts": [
              { "sourceField": "address.street_number" },
              { "literal": " " },
              { "sourceField": "address.street_name" },
              { "literal": " " },
              { "sourceField": "address.street_type" },
              { "literal": ", " },
              { "sourceField": "address.suburb" },
              { "literal": " " },
              { "sourceField": "address.state" },
              { "literal": " " },
              { "sourceField": "address.postcode" }
            ]
          },
          "required": true
        },
        {
          "sourceField": "property_type",
          "targetField": "propertyType",
          "required": true
        },
        {
          "sourceField": "bedrooms",
          "targetField": "bedrooms",
          "required": false
        },
        {
          "sourceField": "bathrooms",
          "targetField": "bathrooms",
          "required": false
        },
        {
          "sourceField": "parking",
          "targetField": "parking",
          "required": false
        },
        {
          "sourceField": "title_reference",
          "targetField": "titleReference",
          "required": false
        },
        {
          "sourceField": "zoning",
          "targetField": "zoning",
          "required": false
        },
        {
          "sourceField": "insurance_provider",
          "targetField": "insuranceProvider",
          "required": false
        },
        {
          "sourceField": "insurance_expiry",
          "targetField": "insuranceExpiry",
          "coerce": {
            "from": "date",
            "to": "date",
            "format": "YYYY-MM-DD"
          },
          "required": false
        },
        {
          "sourceField": "status",
          "targetField": "status",
          "required": true
        }
      ],
      "taxonomy": {
        "what": "what.asset.property.dwelling",
        "how": "how.management.property-management",
        "why": "why.property.portfolio-tracking"
      }
    },
    {
      "sourceEntityId": "lease",
      "targetObjectType": "property.lease",
      "fieldMappings": [
        {
          "sourceField": "id",
          "targetField": "id",
          "required": true
        },
        {
          "sourceField": "property_id",
          "targetField": "propertyId",
          "required": true
        },
        {
          "sourceField": "tenant_ids",
          "targetField": "tenantIds",
          "required": true
        },
        {
          "sourceField": "start_date",
          "targetField": "startDate",
          "coerce": { "from": "date", "to": "date", "format": "YYYY-MM-DD" },
          "required": true
        },
        {
          "sourceField": "end_date",
          "targetField": "endDate",
          "coerce": { "from": "date", "to": "date", "format": "YYYY-MM-DD" },
          "required": true
        },
        {
          "sourceField": "rent_amount",
          "targetField": "rentAmount",
          "transform": {
            "type": "compute",
            "expression": "source.rent_amount / 100"
          },
          "required": true
        },
        {
          "sourceField": "rent_frequency",
          "targetField": "rentFrequency",
          "required": true
        },
        {
          "sourceField": "bond_amount",
          "targetField": "bondAmount",
          "transform": {
            "type": "compute",
            "expression": "source.bond_amount ? source.bond_amount / 100 : null"
          },
          "required": false
        },
        {
          "sourceField": "break_clause",
          "targetField": "breakClause",
          "required": false
        },
        {
          "sourceField": "status",
          "targetField": "status",
          "required": true
        }
      ],
      "taxonomy": {
        "what": "what.agreement.property.lease",
        "how": "how.contract.fixed-term",
        "why": "why.tenancy.residential"
      },
      "phaseMapping": {
        "draft": "SOURCE",
        "active": "ACTIVE",
        "expiring": "EXPIRING",
        "expired": "EXPIRED",
        "terminated": "TERMINATED"
      }
    },
    {
      "sourceEntityId": "tenant",
      "targetObjectType": "property.tenant",
      "fieldMappings": [
        {
          "sourceField": "id",
          "targetField": "id",
          "required": true
        },
        {
          "sourceField": "name",
          "targetField": "name",
          "required": true
        },
        {
          "sourceField": "phone",
          "targetField": "phone",
          "required": false
        },
        {
          "sourceField": "email",
          "targetField": "email",
          "required": false
        },
        {
          "sourceField": "id_verified",
          "targetField": "idVerified",
          "required": false
        },
        {
          "sourceField": "payment_history",
          "targetField": "paymentHistory",
          "required": false
        },
        {
          "sourceField": "status",
          "targetField": "status",
          "required": true
        }
      ],
      "taxonomy": {
        "what": "what.identity.property.tenant",
        "how": "how.identity.person",
        "why": "why.tenancy.occupant"
      }
    },
    {
      "sourceEntityId": "owner",
      "targetObjectType": "property.owner",
      "fieldMappings": [
        {
          "sourceField": "id",
          "targetField": "id",
          "required": true
        },
        {
          "sourceField": "name",
          "targetField": "name",
          "required": true
        },
        {
          "sourceField": "phone",
          "targetField": "phone",
          "required": false
        },
        {
          "sourceField": "email",
          "targetField": "email",
          "required": false
        },
        {
          "sourceField": "entity_type",
          "targetField": "entityType",
          "required": true
        },
        {
          "sourceField": "abn",
          "targetField": "abn",
          "required": false
        },
        {
          "sourceField": "maintenance_approval_threshold",
          "targetField": "maintenanceApprovalThreshold",
          "transform": {
            "type": "compute",
            "expression": "source.maintenance_approval_threshold ? source.maintenance_approval_threshold / 100 : null"
          },
          "required": false
        },
        {
          "sourceField": "status",
          "targetField": "status",
          "required": true
        }
      ],
      "taxonomy": {
        "what": "what.identity.property.owner",
        "how": "how.identity.person-or-entity",
        "why": "why.property.landlord"
      }
    },
    {
      "sourceEntityId": "maintenance_request",
      "targetObjectType": "property.maintenance-request",
      "fieldMappings": [
        {
          "sourceField": "id",
          "targetField": "id",
          "required": true
        },
        {
          "sourceField": "property_id",
          "targetField": "propertyId",
          "required": true
        },
        {
          "sourceField": "tenant_id",
          "targetField": "tenantId",
          "required": false
        },
        {
          "sourceField": "description",
          "targetField": "description",
          "required": true
        },
        {
          "sourceField": "category",
          "targetField": "category",
          "required": true
        },
        {
          "sourceField": "urgency",
          "targetField": "urgency",
          "required": true
        },
        {
          "sourceField": "estimated_cost",
          "targetField": "estimatedCost",
          "transform": {
            "type": "compute",
            "expression": "source.estimated_cost ? source.estimated_cost / 100 : null"
          },
          "required": false
        },
        {
          "sourceField": "approval_status",
          "targetField": "approvalStatus",
          "required": true
        },
        {
          "sourceField": "status",
          "targetField": "status",
          "required": true
        }
      ],
      "taxonomy": {
        "what": "what.service.property.maintenance",
        "how": "how.dispatch.reactive",
        "why": "why.maintenance.repair"
      },
      "phaseMapping": {
        "new": "SOURCE",
        "triaged": "TRIAGED",
        "awaiting_approval": "AWAITING_APPROVAL",
        "approved": "APPROVED",
        "dispatched": "DISPATCHED",
        "in_progress": "IN_PROGRESS",
        "completed": "COMPLETED",
        "invoiced": "INVOICED",
        "closed": "CLOSED"
      }
    },
    {
      "sourceEntityId": "inspection",
      "targetObjectType": "property.inspection",
      "fieldMappings": [
        {
          "sourceField": "id",
          "targetField": "id",
          "required": true
        },
        {
          "sourceField": "property_id",
          "targetField": "propertyId",
          "required": true
        },
        {
          "sourceField": "inspection_type",
          "targetField": "inspectionType",
          "required": true
        },
        {
          "sourceField": "scheduled_date",
          "targetField": "scheduledDate",
          "coerce": { "from": "datetime", "to": "datetime", "format": "YYYY-MM-DDTHH:mm:ssZ" },
          "required": true
        },
        {
          "sourceField": "completed_date",
          "targetField": "completedDate",
          "coerce": { "from": "datetime", "to": "datetime", "format": "YYYY-MM-DDTHH:mm:ssZ" },
          "required": false
        },
        {
          "sourceField": "overall_condition",
          "targetField": "overallCondition",
          "required": false
        },
        {
          "sourceField": "status",
          "targetField": "status",
          "required": true
        }
      ],
      "taxonomy": {
        "what": "what.assessment.property.inspection",
        "how": "how.inspection.routine",
        "why": "why.compliance.condition-report"
      },
      "phaseMapping": {
        "scheduled": "SCHEDULED",
        "in_progress": "IN_PROGRESS",
        "draft_report": "DRAFT_REPORT",
        "published": "PUBLISHED",
        "acknowledged": "ACKNOWLEDGED"
      }
    },
    {
      "sourceEntityId": "document",
      "targetObjectType": "property.document",
      "fieldMappings": [
        {
          "sourceField": "id",
          "targetField": "id",
          "required": true
        },
        {
          "sourceField": "parent_id",
          "targetField": "parentId",
          "required": true
        },
        {
          "sourceField": "parent_type",
          "targetField": "parentType",
          "required": true
        },
        {
          "sourceField": "document_type",
          "targetField": "documentType",
          "required": true
        },
        {
          "sourceField": "filename",
          "targetField": "filename",
          "required": true
        },
        {
          "sourceField": "mime_type",
          "targetField": "mimeType",
          "required": true
        },
        {
          "sourceField": "storage_url",
          "targetField": "storageUrl",
          "required": true
        },
        {
          "sourceField": "status",
          "targetField": "status",
          "required": true
        }
      ],
      "taxonomy": {
        "what": "what.document.property.attachment",
        "how": "how.storage.cloud-reference",
        "why": "why.compliance.evidence"
      }
    }
  ],

  "capabilities": [
    {
      "capability": "network.outbound",
      "reason": "PropertyMe connector must call PropertyMe REST API to fetch entities",
      "required": true
    },
    {
      "capability": "storage.write",
      "reason": "Connector writes extracted semantic objects to the cell store",
      "required": true
    },
    {
      "capability": "identity.read",
      "reason": "Connector reads consumer identity to fetch credentials from the binding",
      "required": true
    }
  ],

  "taxonomyNamespace": "property-management",
  "taxonomyExtensions": null,
  "migrations": null
}
```

---

### D36F.2 — PropertyMe Object Types Configuration

**File**: `configs/extensions/propertyme/types.json`

Object type definitions for all PropertyMe entities, with complete linearity assignments, commerce phases, FSM transitions, and capability requirements. See D36F.1 payloadSchema definitions — convert each to ObjectTypeDeclaration per Phase 36A spec.

---

### D36F.3 — PropertyMe Fetch Adapter Configuration

**File**: `configs/extensions/propertyme/fetch-adapter.json`

OAuth2 token acquisition flow, cursor-based pagination implementation, rate limiter configuration (100 req/min), webhook listener setup for real-time updates (property.updated, lease.updated, maintenance.created, inspection.updated), and error handling rules:
- Retry on 429 (rate limit) with exponential backoff
- Retry on 503 (service unavailable) with backoff
- Fail on 401 (auth expired) → trigger token refresh flow via ConsumerBinding
- Fail on 404 (not found) → log and skip
- Fail on 400 (bad request) → validation error in evidence chain

---

### D36F.4 — PropertyMe Field Transforms

**File**: `packages/protocol-types/src/adapters/propertyme-field-transforms.ts`

TypeScript implementations of all FieldTransform types declared in the grammar:

- **Address composition** (`concat`): street_number + street_name + street_type + suburb + state + postcode → "123 Main Street, Sydney NSW 2000"
- **Rent calculation** (`compute`): weekly_rent → fortnightly/monthly via multiplier based on frequency
- **Status mapping** (`map_enum`): PropertyMe's maintenance statuses → Semantos commerce phases (new → SOURCE, triaged → PARSE, etc.)
- **Date normalization** (`coerce`): PropertyMe's various date formats → ISO 8601
- **Cost normalization** (`compute`): PropertyMe's cents-based amounts (e.g., 28000 cents) → dollar amounts (280.00)

No arbitrary code execution. All transforms are declarative and safely interpretable.

---

### D36F.5 — PropertyMe Governance Setup

**File**: `configs/extensions/propertyme/governance.json`

Governance configuration:
- Author governance: Semantos first-party (author_only patch acceptance policy)
- L0 constraint validation: passes all platform meta-schema requirements
- Version: 1.0.0 (first stable release)
- Sample ConsumerBinding for testing (with mock PropertyMe API credentials)
- Patch acceptance rules: only Semantos can approve grammar changes to v1.x

---

### D36F.6 — End-to-End Integration Tests

**File**: `packages/__tests__/phase36f-propertyme-connector.test.ts`

Gate tests using StubFetchAdapter (mock PropertyMe API responses). All 14 tests must pass:

- **T1**: Grammar validates via `validateExtensionGrammar()`
- **T2**: Grammar produces valid ExtensionConfig via bridge
- **T3**: Pipeline fetches (stub) → parses → typechecks → commits for Property entity
- **T4**: Pipeline handles all 7 entity types (Property, Lease, Tenant, Owner, MaintenanceRequest, Inspection, Document)
- **T5**: MaintenanceRequest FSM transitions through all commerce phases correctly (SOURCE → TRIAGED → AWAITING_APPROVAL → APPROVED → DISPATCHED → IN_PROGRESS → COMPLETED → INVOICED → CLOSED)
- **T6**: Field transforms produce correct output (address composition, rent calc, cost normalization, date normalization, status mapping)
- **T7**: Relationships resolved correctly (Lease linked to Property, Tenant linked to Lease, MaintenanceRequest linked to Property + Tenant)
- **T8**: Evidence chains complete for all extracted objects (source record, parse record, typecheck record, commit record all present)
- **T9**: Idempotent re-extraction creates patches (idempotency key: entity ID + source timestamp), not duplicate objects
- **T10**: ConsumerBinding creation with mock credentials passes L1 constraints (OAuth2 fields present, tenant_id set)
- **T11**: Governance setup validates against L0 policy (author is Semantos, version is semver, grammar is AFFINE)
- **T12**: Shell commands work: `semantos extract propertyme --dry-run` parses grammar, simulates fetch, prints patch count
- **T13**: Incremental extraction (`--since` flag) only fetches records updated since timestamp
- **T14**: Error handling: 429 rate limit → retry, 401 auth error → refresh token via binding, 400 validation error → skip record

---

### D36F.7 — Developer Guide

**File**: `configs/extensions/propertyme/DEVELOPER-GUIDE.md`

Documentation for third-party developers showing how to build a connector using the PropertyMe connector as a reference implementation. Sections:

1. **Overview** — what a connector is, how it fits in the ecosystem, the three purposes (validation, reference, revenue)
2. **Extension Grammar JSON** — complete walkthrough of the PropertyMe grammar, explaining each section
3. **Entity Mapping** — how to map source API fields to semantic object payloads, with PropertyMe examples
4. **Field Transforms** — how to use transform types (concat, split, lookup, template, enum_map, compute) with PropertyMe examples
5. **Object Types** — linearity assignments (RELEVANT, LINEAR, AFFINE), phase FSMs, capability requirements
6. **Fetch Configuration** — OAuth2, pagination, rate limits, error handling, with PropertyMe specifics
7. **Governance** — author governance, L0 validation, ConsumerBinding setup
8. **Testing** — writing tests with StubFetchAdapter, mocking API responses
9. **Shell Commands** — `semantos extract propertyme`, `--dry-run`, `--since`, validation and debugging
10. **Publishing** — submitting to marketplace, versioning strategy, patch acceptance
11. **Common Patterns** — address composition, cost calculation, date normalization, polymorphic entities, cross-entity relationships
12. **Pitfalls** — Don't hardcode logic in transformations. Don't skip field mappings. Don't forget relationships. Don't ignore error handling.

---

## Source Files / References

| Alias | Path | What to read |
|-------|------|--------------|
| `GRAMMAR:SCHEMA` | `docs/prd/PHASE-36A-EXTENSION-GRAMMAR-SCHEMA.md` | ExtensionGrammar JSON schema spec |
| `PIPELINE` | `docs/prd/PHASE-36B-SEMANTIC-EXTRACTION-PIPELINE.md` | Five-stage fetch → parse → typecheck → infer → commit pipeline |
| `GOVERNANCE` | `docs/prd/PHASE-36D-EXTENSION-GOVERNANCE-MODEL.md` | L0/L1/L2 hierarchical governance, ConsumerBinding |
| `MASTER` | `docs/prd/PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md` | Architecture overview, dependencies |
| `PLATFORM` | `docs/PLATFORM-ARCHITECTURE.md` | Property management vertical, MaintenanceRequest FSM, dispatch model |
| `PROPERTY-MAPPING` | `docs/design/SHOMEE-TO-SEMANTOS-MAPPING.md` | Object type linearity patterns, evidence chains |
| `PROTOCOL-TYPES` | `packages/protocol-types/src/extension-grammar.ts` | ExtensionGrammar, FieldTransform, FieldMapping types |
| `PIPELINE-IMPL` | `packages/protocol-types/src/adapters/fetch-adapter.ts` | FetchAdapter interface |
| `TYPES:STORAGE` | `packages/protocol-types/src/storage.ts` | StorageAdapter interface for commit stage |

---

## Completion Criteria

- [ ] PropertyMe grammar at `configs/extensions/propertyme/grammar.json` valid per validateExtensionGrammar()
- [ ] Grammar declares all 7 source entities with all fields and relationships
- [ ] Grammar declares all 7 object types with linearity, phases, payloadSchema, capabilities
- [ ] All entity mappings complete with field-level mappings and transforms
- [ ] All field transforms correctly implement address composition, cost calculation, date normalization, status mapping
- [ ] PropertyMe types configuration at `configs/extensions/propertyme/types.json` complete
- [ ] Fetch adapter config handles OAuth2, pagination, rate limits, error handling, webhooks
- [ ] Governance config passes L0/L1 validation
- [ ] Tests T1–T14 all pass
- [ ] Developer guide covers all sections with PropertyMe examples
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] All commits follow `phase-36f/D36F.N:` naming convention
- [ ] Branch is `phase-36f-connector-reference-impl`

---

## What NOT to Do

- **Don't hardcode PropertyMe logic in the extraction pipeline.** Everything goes through the grammar. If you're writing `if (entity === 'property')` in the pipeline code, you've failed. The pipeline interprets the grammar; it doesn't know about PropertyMe.
- **Don't skip entities.** All 7 PropertyMe entities must be mapped and integrated. Incomplete coverage means the reference doesn't prove the framework works.
- **Don't mock the grammar.** Use the real grammar.json at runtime. Only mock API responses in tests (StubFetchAdapter).
- **Don't bypass field transforms.** PropertyMe has real-world transformation needs (address composition, cost normalization). If you hardcode these, you've not validated the transform system.
- **Don't skip governance validation.** First-party extensions still go through L0 validation. Don't assume exemptions.
- **Don't write a generic developer guide.** Every pattern in the guide must reference actual PropertyMe implementation. Developers copy examples; vague guidance produces broken connectors.
- **Don't skip relationship resolution.** Leases reference Properties, MaintenanceRequests reference both Properties and Tenants. Relationships must be fully resolved in the evidence chain.

---

## Next Phase

Phase 36E builds the Extension Manager UI: marketplace registry, install/update/remove, governance dashboard, version compatibility matrix, trust signals (Glow weight, object count, version history). Phase 36F proves the framework works; 36E makes it user-facing.
