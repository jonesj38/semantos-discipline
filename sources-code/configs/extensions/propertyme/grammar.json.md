---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/configs/extensions/propertyme/grammar.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.382760+00:00
---

# configs/extensions/propertyme/grammar.json

```json
{
  "metaSchemaVersion": "1.0.0",
  "grammarId": "com.semantos.propertyme",
  "grammarVersion": "1.0.0",
  "displayName": "PropertyMe Property Management",
  "description": "Semantos connector for PropertyMe — real property management with addresses, people, leases, maintenance, and inspections.",
  "author": {
    "certId": "semantos-core-team",
    "name": "Semantos Core Team",
    "contact": "extensions@semantos.io"
  },
  "source": {
    "protocol": "rest",
    "baseUrlTemplate": "https://api.propertyme.com/v2",
    "auth": {
      "type": "oauth2",
      "requiredCredentials": ["client_id", "client_secret", "tenant_id"],
      "oauth2Config": {
        "authorizationUrl": "https://auth.propertyme.com/oauth/authorize",
        "tokenUrl": "https://auth.propertyme.com/oauth/token",
        "scopes": ["properties:read", "leases:read", "tenants:read", "maintenance:read", "inspections:read", "owners:read"]
      }
    },
    "rateLimits": {
      "requestsPerSecond": 10,
      "requestsPerMinute": 300,
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
          { "sourceFieldName": "id", "sourceType": "string", "required": true, "description": "Property ID" },
          { "sourceFieldName": "street_address", "sourceType": "string", "required": true, "description": "Street address" },
          { "sourceFieldName": "city", "sourceType": "string", "required": true, "description": "City" },
          { "sourceFieldName": "state", "sourceType": "string", "required": true, "description": "State/province" },
          { "sourceFieldName": "zip", "sourceType": "string", "required": true, "description": "ZIP/postal code" },
          { "sourceFieldName": "country", "sourceType": "string", "required": true, "description": "Country code (ISO 3166)" },
          { "sourceFieldName": "latitude", "sourceType": "number", "required": false, "description": "Latitude" },
          { "sourceFieldName": "longitude", "sourceType": "number", "required": false, "description": "Longitude" },
          { "sourceFieldName": "bedrooms", "sourceType": "number", "required": true, "description": "Number of bedrooms" },
          { "sourceFieldName": "bathrooms", "sourceType": "number", "required": true, "description": "Number of bathrooms" },
          { "sourceFieldName": "square_footage", "sourceType": "number", "required": true, "description": "Total square footage" },
          { "sourceFieldName": "year_built", "sourceType": "number", "required": false, "description": "Year of construction" },
          { "sourceFieldName": "property_type", "sourceType": "enum", "required": true, "description": "Property type", "enumValues": ["apartment", "house", "condo", "townhouse", "commercial"] },
          { "sourceFieldName": "owner_id", "sourceType": "string", "required": true, "description": "Owner reference" },
          { "sourceFieldName": "updated_at", "sourceType": "datetime", "required": true, "description": "Last update timestamp" }
        ],
        "relationships": [
          { "targetEntityId": "owner", "type": "belongs_to", "foreignKey": "owner_id", "foreignKeyLocation": "source" },
          { "targetEntityId": "lease", "type": "has_many", "foreignKey": "property_id", "foreignKeyLocation": "target" },
          { "targetEntityId": "maintenance_request", "type": "has_many", "foreignKey": "property_id", "foreignKeyLocation": "target" },
          { "targetEntityId": "inspection", "type": "has_many", "foreignKey": "property_id", "foreignKeyLocation": "target" }
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
          { "sourceFieldName": "id", "sourceType": "string", "required": true, "description": "Lease ID" },
          { "sourceFieldName": "tenant_id", "sourceType": "string", "required": true, "description": "Tenant reference" },
          { "sourceFieldName": "property_id", "sourceType": "string", "required": true, "description": "Property reference" },
          { "sourceFieldName": "monthly_rent", "sourceType": "number", "required": true, "description": "Monthly rent in dollars" },
          { "sourceFieldName": "term_months", "sourceType": "number", "required": true, "description": "Lease term in months" },
          { "sourceFieldName": "start_date", "sourceType": "date", "required": true, "description": "Lease start date" },
          { "sourceFieldName": "end_date", "sourceType": "date", "required": true, "description": "Lease end date" },
          { "sourceFieldName": "status", "sourceType": "enum", "required": true, "description": "Lease status", "enumValues": ["draft", "active", "expired", "terminated"] },
          { "sourceFieldName": "security_deposit", "sourceType": "number", "required": false, "description": "Security deposit amount" },
          { "sourceFieldName": "updated_at", "sourceType": "datetime", "required": true, "description": "Last update timestamp" }
        ],
        "relationships": [
          { "targetEntityId": "tenant", "type": "belongs_to", "foreignKey": "tenant_id", "foreignKeyLocation": "source" },
          { "targetEntityId": "property", "type": "belongs_to", "foreignKey": "property_id", "foreignKeyLocation": "source" }
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
          { "sourceFieldName": "id", "sourceType": "string", "required": true, "description": "Tenant ID" },
          { "sourceFieldName": "first_name", "sourceType": "string", "required": true, "description": "Given name" },
          { "sourceFieldName": "last_name", "sourceType": "string", "required": true, "description": "Family name" },
          { "sourceFieldName": "email", "sourceType": "string", "required": true, "description": "Email address" },
          { "sourceFieldName": "phone", "sourceType": "string", "required": false, "description": "Phone number" },
          { "sourceFieldName": "date_of_birth", "sourceType": "date", "required": false, "description": "Date of birth" },
          { "sourceFieldName": "emergency_contact", "sourceType": "string", "required": false, "description": "Emergency contact name" },
          { "sourceFieldName": "emergency_phone", "sourceType": "string", "required": false, "description": "Emergency contact phone" },
          { "sourceFieldName": "updated_at", "sourceType": "datetime", "required": true, "description": "Last update timestamp" }
        ]
      },
      {
        "entityId": "maintenance_request",
        "displayName": "Maintenance Request",
        "endpoint": {
          "list": "/maintenance-requests",
          "get": "/maintenance-requests/{id}",
          "webhookEvent": "maintenance.updated"
        },
        "method": "GET",
        "responseShape": {
          "dataPath": "$.data.maintenance_requests",
          "idField": "id",
          "timestampField": "updated_at"
        },
        "fields": [
          { "sourceFieldName": "id", "sourceType": "string", "required": true, "description": "Request ID" },
          { "sourceFieldName": "property_id", "sourceType": "string", "required": true, "description": "Property reference" },
          { "sourceFieldName": "description", "sourceType": "string", "required": true, "description": "Work description" },
          { "sourceFieldName": "estimated_cost", "sourceType": "number", "required": false, "description": "Estimated cost" },
          { "sourceFieldName": "actual_cost", "sourceType": "number", "required": false, "description": "Actual cost" },
          { "sourceFieldName": "reported_date", "sourceType": "date", "required": true, "description": "Date reported" },
          { "sourceFieldName": "completed_date", "sourceType": "date", "required": false, "description": "Date completed" },
          { "sourceFieldName": "status", "sourceType": "enum", "required": true, "description": "Request status", "enumValues": ["pending", "approved", "in_progress", "completed", "cancelled"] },
          { "sourceFieldName": "priority", "sourceType": "enum", "required": true, "description": "Priority level", "enumValues": ["low", "medium", "high", "emergency"] },
          { "sourceFieldName": "category", "sourceType": "string", "required": false, "description": "Maintenance category" },
          { "sourceFieldName": "updated_at", "sourceType": "datetime", "required": true, "description": "Last update timestamp" }
        ],
        "relationships": [
          { "targetEntityId": "property", "type": "belongs_to", "foreignKey": "property_id", "foreignKeyLocation": "source" }
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
          { "sourceFieldName": "id", "sourceType": "string", "required": true, "description": "Inspection ID" },
          { "sourceFieldName": "property_id", "sourceType": "string", "required": true, "description": "Property reference" },
          { "sourceFieldName": "inspector_name", "sourceType": "string", "required": true, "description": "Inspector name" },
          { "sourceFieldName": "inspection_date", "sourceType": "date", "required": true, "description": "Inspection date" },
          { "sourceFieldName": "inspection_type", "sourceType": "enum", "required": true, "description": "Inspection type", "enumValues": ["routine", "move_in", "move_out", "maintenance", "annual"] },
          { "sourceFieldName": "result", "sourceType": "enum", "required": true, "description": "Inspection result", "enumValues": ["pass", "pass_with_notes", "fail", "pending"] },
          { "sourceFieldName": "notes", "sourceType": "string", "required": false, "description": "Inspector notes" },
          { "sourceFieldName": "updated_at", "sourceType": "datetime", "required": true, "description": "Last update timestamp" }
        ],
        "relationships": [
          { "targetEntityId": "property", "type": "belongs_to", "foreignKey": "property_id", "foreignKeyLocation": "source" }
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
          { "sourceFieldName": "id", "sourceType": "string", "required": true, "description": "Owner ID" },
          { "sourceFieldName": "first_name", "sourceType": "string", "required": true, "description": "Given name" },
          { "sourceFieldName": "last_name", "sourceType": "string", "required": true, "description": "Family name" },
          { "sourceFieldName": "email", "sourceType": "string", "required": true, "description": "Email address" },
          { "sourceFieldName": "phone", "sourceType": "string", "required": false, "description": "Phone number" },
          { "sourceFieldName": "company_name", "sourceType": "string", "required": false, "description": "Company name if business entity" },
          { "sourceFieldName": "tax_id", "sourceType": "string", "required": false, "description": "Tax identification number" },
          { "sourceFieldName": "updated_at", "sourceType": "datetime", "required": true, "description": "Last update timestamp" }
        ],
        "relationships": [
          { "targetEntityId": "property", "type": "has_many", "foreignKey": "owner_id", "foreignKeyLocation": "target" }
        ]
      }
    ]
  },
  "objectTypes": [
    {
      "typePath": "property.listing",
      "displayName": "Property Listing",
      "description": "Real property with location, structure, and ownership details",
      "linearity": "AFFINE",
      "phases": ["draft", "active", "inactive", "archived"],
      "initialPhase": "draft",
      "payloadSchema": {
        "streetAddress": { "type": "string", "description": "Street address" },
        "city": { "type": "string", "description": "City" },
        "state": { "type": "string", "description": "State/province" },
        "zip": { "type": "string", "description": "ZIP/postal code" },
        "country": { "type": "string", "description": "Country code (ISO 3166)" },
        "latitude": { "type": "number", "description": "Latitude coordinate" },
        "longitude": { "type": "number", "description": "Longitude coordinate" },
        "bedrooms": { "type": "number", "description": "Number of bedrooms" },
        "bathrooms": { "type": "number", "description": "Number of bathrooms" },
        "squareFootage": { "type": "number", "description": "Total square footage" },
        "yearBuilt": { "type": "number", "description": "Year of construction" },
        "propertyType": { "type": "enum", "description": "Property type", "enum": ["apartment", "house", "condo", "townhouse", "commercial"] },
        "totalRooms": { "type": "number", "description": "Total room count (bedrooms + bathrooms)" }
      },
      "capabilities": {
        "read": [1],
        "write": [1, 2]
      },
      "transitions": [
        { "fromPhase": "draft", "toPhase": "active" },
        { "fromPhase": "active", "toPhase": "inactive" },
        { "fromPhase": "inactive", "toPhase": "active" },
        { "fromPhase": "inactive", "toPhase": "archived" }
      ]
    },
    {
      "typePath": "property.lease",
      "displayName": "Lease Agreement",
      "description": "Tenancy agreement between landlord and tenant",
      "linearity": "LINEAR",
      "phases": ["draft", "active", "expired", "terminated"],
      "initialPhase": "draft",
      "payloadSchema": {
        "tenantId": { "type": "string", "description": "Tenant reference ID" },
        "propertyId": { "type": "string", "description": "Property reference ID" },
        "monthlyRent": { "type": "number", "description": "Monthly rent in dollars" },
        "termMonths": { "type": "number", "description": "Lease term in months" },
        "startDate": { "type": "date", "description": "Lease commencement date" },
        "endDate": { "type": "date", "description": "Lease expiration date" },
        "securityDeposit": { "type": "number", "description": "Security deposit amount" },
        "status": { "type": "enum", "description": "Lease status", "enum": ["draft", "active", "expired", "terminated"] }
      },
      "capabilities": {
        "read": [1],
        "write": [1, 2],
        "sign": [2, 9]
      },
      "transitions": [
        { "fromPhase": "draft", "toPhase": "active", "guard": { "type": "capability", "field": "identity.capabilities", "operator": "includes_all", "value": [2, 9] } },
        { "fromPhase": "active", "toPhase": "expired", "guard": { "type": "time", "field": "object.endDate", "operator": "lt", "value": "now()" } },
        { "fromPhase": "active", "toPhase": "terminated" }
      ]
    },
    {
      "typePath": "property.tenant",
      "displayName": "Tenant",
      "description": "Individual tenant with contact and identity information",
      "linearity": "AFFINE",
      "phases": ["active", "inactive"],
      "initialPhase": "active",
      "payloadSchema": {
        "firstName": { "type": "string", "description": "Given name" },
        "lastName": { "type": "string", "description": "Family name" },
        "email": { "type": "string", "description": "Email address" },
        "phone": { "type": "string", "description": "Phone number" },
        "dateOfBirth": { "type": "date", "description": "Date of birth" },
        "emergencyContact": { "type": "string", "description": "Emergency contact name" },
        "emergencyPhone": { "type": "string", "description": "Emergency contact phone" }
      },
      "capabilities": {
        "read": [1, 8],
        "write": [1, 8]
      }
    },
    {
      "typePath": "property.maintenance-request",
      "displayName": "Maintenance Request",
      "description": "Property maintenance task or repair request",
      "linearity": "AFFINE",
      "phases": ["pending", "approved", "in_progress", "completed", "cancelled"],
      "initialPhase": "pending",
      "payloadSchema": {
        "propertyId": { "type": "string", "description": "Property reference" },
        "description": { "type": "string", "description": "Work description" },
        "estimatedCost": { "type": "number", "description": "Estimated cost in dollars" },
        "actualCost": { "type": "number", "description": "Actual cost in dollars" },
        "reportedDate": { "type": "date", "description": "Date reported" },
        "completedDate": { "type": "date", "description": "Date completed" },
        "status": { "type": "enum", "description": "Request status", "enum": ["pending", "approved", "in_progress", "completed", "cancelled"] },
        "priority": { "type": "enum", "description": "Priority level", "enum": ["low", "medium", "high", "emergency"] },
        "category": { "type": "string", "description": "Maintenance category" }
      },
      "capabilities": {
        "read": [1],
        "write": [1, 5],
        "approve": [1, 5, 2]
      },
      "transitions": [
        { "fromPhase": "pending", "toPhase": "approved" },
        { "fromPhase": "approved", "toPhase": "in_progress" },
        { "fromPhase": "in_progress", "toPhase": "completed" },
        { "fromPhase": "pending", "toPhase": "cancelled" },
        { "fromPhase": "approved", "toPhase": "cancelled" }
      ]
    },
    {
      "typePath": "property.inspection",
      "displayName": "Property Inspection",
      "description": "Scheduled property inspection with findings",
      "linearity": "LINEAR",
      "phases": ["scheduled", "in_progress", "completed"],
      "initialPhase": "scheduled",
      "payloadSchema": {
        "propertyId": { "type": "string", "description": "Property reference" },
        "inspectorName": { "type": "string", "description": "Inspector name" },
        "inspectionDate": { "type": "date", "description": "Inspection date" },
        "inspectionType": { "type": "enum", "description": "Inspection type", "enum": ["routine", "move_in", "move_out", "maintenance", "annual"] },
        "result": { "type": "enum", "description": "Inspection result", "enum": ["pass", "pass_with_notes", "fail", "pending"] },
        "notes": { "type": "string", "description": "Inspector notes" }
      },
      "capabilities": {
        "read": [1],
        "write": [1, 5]
      },
      "transitions": [
        { "fromPhase": "scheduled", "toPhase": "in_progress" },
        { "fromPhase": "in_progress", "toPhase": "completed" }
      ]
    },
    {
      "typePath": "property.owner",
      "displayName": "Property Owner",
      "description": "Property owner (individual or business entity)",
      "linearity": "AFFINE",
      "phases": ["active", "inactive"],
      "initialPhase": "active",
      "payloadSchema": {
        "firstName": { "type": "string", "description": "Given name" },
        "lastName": { "type": "string", "description": "Family name" },
        "email": { "type": "string", "description": "Email address" },
        "phone": { "type": "string", "description": "Phone number" },
        "companyName": { "type": "string", "description": "Company name if business entity" },
        "taxId": { "type": "string", "description": "Tax identification number" }
      },
      "capabilities": {
        "read": [1, 8],
        "write": [1, 8]
      }
    }
  ],
  "entityMappings": [
    {
      "sourceEntityId": "property",
      "targetObjectType": "property.listing",
      "fieldMappings": [
        { "sourceField": "street_address", "targetField": "streetAddress", "required": true },
        { "sourceField": "city", "targetField": "city", "required": true },
        { "sourceField": "state", "targetField": "state", "required": true },
        { "sourceField": "zip", "targetField": "zip", "required": true },
        { "sourceField": "country", "targetField": "country", "required": true },
        { "sourceField": "latitude", "targetField": "latitude", "required": false },
        { "sourceField": "longitude", "targetField": "longitude", "required": false },
        { "sourceField": "bedrooms", "targetField": "bedrooms", "required": true },
        { "sourceField": "bathrooms", "targetField": "bathrooms", "required": true },
        { "sourceField": "square_footage", "targetField": "squareFootage", "required": true },
        { "sourceField": "year_built", "targetField": "yearBuilt", "required": false },
        { "sourceField": "property_type", "targetField": "propertyType", "required": true },
        {
          "sourceField": "bedrooms",
          "targetField": "totalRooms",
          "required": false,
          "transform": {
            "type": "compute",
            "expression": "source.bedrooms + source.bathrooms"
          }
        }
      ],
      "taxonomy": {
        "what": "what.asset.property.listing",
        "how": "how.technical.api.rest",
        "why": "why.integration.data-sync"
      }
    },
    {
      "sourceEntityId": "lease",
      "targetObjectType": "property.lease",
      "fieldMappings": [
        { "sourceField": "tenant_id", "targetField": "tenantId", "required": true },
        { "sourceField": "property_id", "targetField": "propertyId", "required": true },
        { "sourceField": "monthly_rent", "targetField": "monthlyRent", "required": true },
        { "sourceField": "term_months", "targetField": "termMonths", "required": true },
        { "sourceField": "start_date", "targetField": "startDate", "required": true, "coerce": { "from": "date", "to": "date", "format": "YYYY-MM-DD" } },
        { "sourceField": "end_date", "targetField": "endDate", "required": true, "coerce": { "from": "date", "to": "date", "format": "YYYY-MM-DD" } },
        { "sourceField": "security_deposit", "targetField": "securityDeposit", "required": false },
        { "sourceField": "status", "targetField": "status", "required": true }
      ],
      "taxonomy": {
        "what": "what.instrument.lease",
        "how": "how.technical.api.rest",
        "why": "why.integration.data-sync"
      },
      "phaseMapping": {
        "draft": "draft",
        "active": "active",
        "expired": "expired",
        "terminated": "terminated"
      }
    },
    {
      "sourceEntityId": "tenant",
      "targetObjectType": "property.tenant",
      "fieldMappings": [
        { "sourceField": "first_name", "targetField": "firstName", "required": true },
        { "sourceField": "last_name", "targetField": "lastName", "required": true },
        { "sourceField": "email", "targetField": "email", "required": true },
        { "sourceField": "phone", "targetField": "phone", "required": false },
        { "sourceField": "date_of_birth", "targetField": "dateOfBirth", "required": false },
        { "sourceField": "emergency_contact", "targetField": "emergencyContact", "required": false },
        { "sourceField": "emergency_phone", "targetField": "emergencyPhone", "required": false }
      ],
      "taxonomy": {
        "what": "what.identity.person.tenant",
        "how": "how.technical.api.rest",
        "why": "why.integration.data-sync"
      }
    },
    {
      "sourceEntityId": "maintenance_request",
      "targetObjectType": "property.maintenance-request",
      "fieldMappings": [
        { "sourceField": "property_id", "targetField": "propertyId", "required": true },
        { "sourceField": "description", "targetField": "description", "required": true },
        { "sourceField": "estimated_cost", "targetField": "estimatedCost", "required": false },
        { "sourceField": "actual_cost", "targetField": "actualCost", "required": false },
        { "sourceField": "reported_date", "targetField": "reportedDate", "required": true },
        { "sourceField": "completed_date", "targetField": "completedDate", "required": false },
        { "sourceField": "status", "targetField": "status", "required": true },
        { "sourceField": "priority", "targetField": "priority", "required": true },
        { "sourceField": "category", "targetField": "category", "required": false }
      ],
      "taxonomy": {
        "what": "what.service.property.maintenance",
        "how": "how.technical.api.rest",
        "why": "why.maintenance.repair"
      },
      "phaseMapping": {
        "pending": "pending",
        "approved": "approved",
        "in_progress": "in_progress",
        "completed": "completed",
        "cancelled": "cancelled"
      }
    },
    {
      "sourceEntityId": "inspection",
      "targetObjectType": "property.inspection",
      "fieldMappings": [
        { "sourceField": "property_id", "targetField": "propertyId", "required": true },
        { "sourceField": "inspector_name", "targetField": "inspectorName", "required": true },
        { "sourceField": "inspection_date", "targetField": "inspectionDate", "required": true },
        { "sourceField": "inspection_type", "targetField": "inspectionType", "required": true },
        { "sourceField": "result", "targetField": "result", "required": true },
        { "sourceField": "notes", "targetField": "notes", "required": false }
      ],
      "taxonomy": {
        "what": "what.service.property.inspection",
        "how": "how.technical.api.rest",
        "why": "why.compliance.inspection"
      }
    },
    {
      "sourceEntityId": "owner",
      "targetObjectType": "property.owner",
      "fieldMappings": [
        { "sourceField": "first_name", "targetField": "firstName", "required": true },
        { "sourceField": "last_name", "targetField": "lastName", "required": true },
        { "sourceField": "email", "targetField": "email", "required": true },
        { "sourceField": "phone", "targetField": "phone", "required": false },
        { "sourceField": "company_name", "targetField": "companyName", "required": false },
        { "sourceField": "tax_id", "targetField": "taxId", "required": false }
      ],
      "taxonomy": {
        "what": "what.identity.person.owner",
        "how": "how.technical.api.rest",
        "why": "why.integration.data-sync"
      }
    }
  ],
  "capabilities": [
    { "capability": "network.outbound", "reason": "Fetch data from PropertyMe REST API", "required": true },
    { "capability": "storage.write", "reason": "Store extracted semantic objects", "required": true },
    { "capability": "storage.read", "reason": "Read existing objects for deduplication", "required": true },
    { "capability": "identity.read", "reason": "Read tenant/owner identity for hat mapping", "required": false }
  ],
  "taxonomyNamespace": "property-management",
  "taxonomyExtensions": [
    {
      "axis": "what",
      "parentPath": "what.service.property",
      "nodes": [
        {
          "segment": "maintenance",
          "displayName": "Property Maintenance",
          "description": "Maintenance and repair services for properties",
          "children": [
            { "segment": "plumbing", "displayName": "Plumbing", "description": "Plumbing repairs and installations" },
            { "segment": "electrical", "displayName": "Electrical", "description": "Electrical repairs and installations" },
            { "segment": "hvac", "displayName": "HVAC", "description": "Heating, ventilation, and air conditioning" },
            { "segment": "general", "displayName": "General Repairs", "description": "General property repairs" }
          ]
        },
        {
          "segment": "inspection",
          "displayName": "Property Inspection",
          "description": "Property condition inspections and assessments"
        }
      ]
    }
  ]
}

```
