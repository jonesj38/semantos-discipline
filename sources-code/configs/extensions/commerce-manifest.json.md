---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/configs/extensions/commerce-manifest.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.381872+00:00
---

# configs/extensions/commerce-manifest.json

```json
{
  "id": "commerce",
  "name": "Commerce & Marketplace",
  "version": "1.0.0",
  "taxonomyPath": "taxonomy/commerce.json",
  "flowsDir": "flows",
  "promptsDir": "prompts",
  "objectsDir": "objects",
  "requiredCapabilities": ["SIGNING", "ATTESTATION", "METERING"],
  "hatRoles": {
    "founder": {
      "description": "Business owner with L1 author privileges",
      "governanceLevel": "L1",
      "capabilities": ["create_service", "manage_team", "update_org", "publish_manifest"]
    },
    "tradie": {
      "description": "Team member with extraction operator privileges",
      "governanceLevel": "L2",
      "capabilities": ["claim_order", "update_order", "complete_service"]
    },
    "customer": {
      "description": "Service consumer with L2 binding",
      "governanceLevel": "L2",
      "capabilities": ["browse_services", "book_service", "settle_payment", "submit_review"]
    },
    "viewer": {
      "description": "Read-only access to public business information",
      "governanceLevel": "L2",
      "capabilities": ["browse_services", "view_reviews"]
    }
  },
  "metadata": {
    "author": "Semantos Platform",
    "description": "Consumer commerce, service marketplace, and business identity management",
    "phase": "Semantic Shell Phase 3",
    "createdAt": "2026-04-01T00:00:00Z"
  },
  "governanceConfig": {
    "grammarUpdatePolicy": "ballot",
    "breakingChangeThreshold": 66,
    "deprecationMinDays": 30,
    "constraintRules": {
      "order": {
        "requiredFields": ["status", "serviceId", "customerId", "totalAmount"],
        "statusTransitions": {
          "pending": ["accepted", "cancelled"],
          "accepted": ["in_progress", "cancelled"],
          "in_progress": ["completed", "disputed"],
          "completed": ["reviewed"],
          "reviewed": [],
          "disputed": ["completed", "cancelled"],
          "cancelled": []
        }
      },
      "service": {
        "requiredFields": ["name", "categoryPath", "priceType"],
        "maxBasePrice": 100000,
        "validPriceTypes": ["fixed", "hourly", "rom"]
      },
      "review": {
        "requiredFields": ["orderId", "rating"],
        "ratingRange": [1, 5],
        "maxOnePerCustomerPerOrg": true,
        "requiresVerifiedPurchase": true
      },
      "payment": {
        "requiredFields": ["orderId", "amount", "status"],
        "validMethods": ["brc100", "invoice", "cash"]
      }
    },
    "versionCompatibility": {
      "backwardCompatible": true,
      "minSupportedVersion": "1.0.0",
      "migrationPolicy": "automatic"
    }
  },
  "manifestLinearity": "AFFINE",
  "grammar": {
    "version": "1.0.0",
    "objectSchemas": {
      "Service": { "ref": "commerce.json#/objectTypes/0" },
      "Product": { "ref": "commerce.json#/objectTypes/1" },
      "Order": { "ref": "commerce.json#/objectTypes/2" },
      "Payment": { "ref": "commerce.json#/objectTypes/3" },
      "Review": { "ref": "commerce.json#/objectTypes/4" },
      "Rating": { "ref": "commerce.json#/objectTypes/5" }
    }
  }
}

```
