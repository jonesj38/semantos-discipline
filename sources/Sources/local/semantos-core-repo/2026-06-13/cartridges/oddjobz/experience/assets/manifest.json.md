---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/assets/manifest.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.454714+00:00
---

# cartridges/oddjobz/experience/assets/manifest.json

```json
{
  "id": "oddjobz",
  "name": "Trades & Services",
  "version": "0.1.0",
  "domainFlag": "0x000101",
  "metadata": {
    "description": "Lead → quote → job → invoice for trades operators.",
    "author": "Semantos",
    "documentation": "docs/design/ODDJOBZ-EXTENSION-PLAN.md"
  },
  "hatRoles": [
    "admin",
    "operator"
  ],
  "requiredCapabilities": [],
  "grammar": {
    "extensionId": "odd-job-todd",
    "trustClass": "interpretive",
    "proofRequirement": "attestation",
    "defaultTaxonomyWhat": "maintenance.job",
    "lexicon": {
      "name": "jural",
      "categories": [
        "declaration",
        "obligation",
        "power",
        "condition",
        "transfer"
      ]
    },
    "objectTypes": [
      {
        "name": "maintenance.job",
        "description": "A property maintenance work order."
      },
      {
        "name": "maintenance.quote",
        "description": "A priced estimate for a job."
      },
      {
        "name": "maintenance.visit",
        "description": "A scheduled site visit."
      },
      {
        "name": "maintenance.invoice",
        "description": "An invoice for completed work."
      }
    ],
    "actions": [
      {
        "name": "report_issue",
        "category": "declaration",
        "authoredBy": [
          "tenant"
        ],
        "description": "Tenant reports a maintenance issue."
      },
      {
        "name": "request_photos",
        "category": "obligation",
        "authoredBy": [
          "pm",
          "rea"
        ],
        "description": "PM/REA asks for photos."
      },
      {
        "name": "attach_photos",
        "category": "declaration",
        "authoredBy": [
          "tenant"
        ],
        "description": "Tenant attaches photos."
      },
      {
        "name": "request_quote",
        "category": "declaration",
        "authoredBy": [
          "pm",
          "rea"
        ],
        "description": "Solicit a quote."
      },
      {
        "name": "submit_quote",
        "category": "declaration",
        "authoredBy": [
          "tradesperson"
        ],
        "description": "Tradesperson submits a quote."
      },
      {
        "name": "approve_quote",
        "category": "power",
        "authoredBy": [
          "landlord",
          "rea"
        ],
        "description": "Authorise a quote."
      },
      {
        "name": "schedule_visit",
        "category": "condition",
        "authoredBy": [
          "pm",
          "tradesperson"
        ],
        "description": "Schedule a site visit."
      },
      {
        "name": "mark_work_complete",
        "category": "declaration",
        "authoredBy": [
          "tradesperson"
        ],
        "description": "Mark job work complete."
      },
      {
        "name": "issue_invoice",
        "category": "transfer",
        "authoredBy": [
          "tradesperson"
        ],
        "description": "Issue an invoice."
      },
      {
        "name": "pay_invoice",
        "category": "transfer",
        "authoredBy": [
          "pm",
          "landlord"
        ],
        "description": "Pay the invoice."
      }
    ]
  },
  "ui": {
    "surfacingMode": "default",
    "verbs": [
      {
        "modal": "do",
        "label": "New job",
        "intentType": "oddjobz.job.create",
        "subtitle": "log a new job",
        "icon": "build",
        "dispatch": {
          "cellType": "oddjobz.job",
          "triple": [
            "oddjobz",
            "job",
            "worktrack",
            ""
          ],
          "defaultPayload": {
            "state": "lead",
            "customer_name": "",
            "created_at": ""
          }
        }
      },
      {
        "modal": "do",
        "label": "New quote",
        "intentType": "oddjobz.quote.create",
        "subtitle": "draft a quote for a customer",
        "icon": "request_quote",
        "dispatch": {
          "cellType": "oddjobz.quote",
          "triple": [
            "oddjobz",
            "quote",
            "price",
            ""
          ],
          "defaultPayload": {
            "state": "draft",
            "job_id": "",
            "cost_min": 0,
            "cost_max": 0,
            "notes": ""
          }
        }
      },
      {
        "modal": "do",
        "label": "Log visit",
        "intentType": "oddjobz.visit.create",
        "subtitle": "record a site visit",
        "icon": "location_on",
        "dispatch": {
          "cellType": "oddjobz.visit",
          "triple": [
            "oddjobz",
            "visit",
            "schedule",
            ""
          ],
          "defaultPayload": {
            "state": "scheduled",
            "job_id": "",
            "scheduled_at": ""
          }
        }
      },
      {
        "modal": "do",
        "label": "Send invoice",
        "intentType": "oddjobz.invoice.create",
        "subtitle": "invoice completed work",
        "icon": "receipt_long",
        "dispatch": {
          "cellType": "oddjobz.invoice",
          "triple": [
            "oddjobz",
            "invoice",
            "bill",
            ""
          ],
          "defaultPayload": {
            "state": "draft",
            "job_id": "",
            "amount": 0
          }
        }
      },
      {
        "modal": "find",
        "label": "Find customer",
        "intentType": "oddjobz.customer.find",
        "subtitle": "look up a contact",
        "icon": "person_search",
        "query": {
          "typeHash": "oddjobz.customer.v2",
          "collectionTitle": "Customers",
          "titleField": "display_name",
          "subtitleField": "phone"
        }
      },
      {
        "modal": "find",
        "label": "Find job",
        "intentType": "oddjobz.job.find",
        "subtitle": "lookup by site, status, etc.",
        "icon": "search",
        "query": {
          "typeHash": "oddjobz.job.v2",
          "collectionTitle": "Jobs",
          "titleField": "customer_name",
          "subtitleField": "property_address",
          "filter": {
            "state": "open"
          }
        }
      }
    ]
  }
}

```
