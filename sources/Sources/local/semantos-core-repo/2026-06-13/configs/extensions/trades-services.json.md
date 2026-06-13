---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/configs/extensions/trades-services.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.382136+00:00
---

# configs/extensions/trades-services.json

```json
{
  "id": "trades-services",
  "name": "Trades & Services (OddJobTodd)",
  "objectTypes": [
    {
      "typeHash": "fde9975a0730079ece230341749e03a1e259a41163de15c23d2ff25ee0789e0d",
      "name": "Job",
      "icon": "briefcase",
      "linearity": "AFFINE",
      "archetype": "action",
      "conversationEnabled": true,
      "visibility": {
        "states": [
          "draft",
          "published",
          "revoked"
        ],
        "defaultState": "draft",
        "publishTransition": {
          "fromLinearity": "AFFINE",
          "toLinearity": "RELEVANT",
          "requiredCapabilities": [
            2,
            5
          ]
        },
        "revokePreservesEvidence": true
      },
      "accessPolicy": {
        "default": "hat-scoped",
        "overridable": true
      },
      "linearityTransitions": [
        {
          "from": "AFFINE",
          "to": "LINEAR",
          "trigger": "bookable"
        }
      ],
      "defaultCapabilities": [
        4,
        5,
        10
      ],
      "fields": [
        {
          "name": "status",
          "type": "enum",
          "values": [
            "new_lead",
            "partial_intake",
            "awaiting_customer",
            "ready_for_review",
            "estimate_presented",
            "estimate_accepted",
            "bookable",
            "scheduled",
            "in_progress",
            "complete",
            "invoiced",
            "paid"
          ]
        },
        {
          "name": "urgency",
          "type": "enum",
          "values": [
            "emergency",
            "urgent",
            "next_week",
            "next_2_weeks",
            "flexible",
            "when_convenient"
          ]
        },
        {
          "name": "effortBand",
          "type": "enum",
          "values": [
            "quick",
            "short",
            "quarter_day",
            "half_day",
            "full_day",
            "multi_day"
          ]
        },
        {
          "name": "categoryPath",
          "type": "string"
        },
        {
          "name": "customerFitScore",
          "type": "number",
          "min": 0,
          "max": 100,
          "requiredCapabilities": [
            5
          ]
        },
        {
          "name": "quoteWorthinessScore",
          "type": "number",
          "min": 0,
          "max": 100,
          "requiredCapabilities": [
            5
          ]
        },
        {
          "name": "recommendation",
          "type": "enum",
          "values": [
            "ignore",
            "only_if_nearby",
            "needs_site_visit",
            "probably_bookable",
            "worth_quoting",
            "priority_lead"
          ],
          "requiredCapabilities": [
            5
          ]
        },
        {
          "name": "confidenceScore",
          "type": "number",
          "min": 0,
          "max": 100,
          "requiredCapabilities": [
            5
          ]
        }
      ],
      "category": "services.trades"
    },
    {
      "typeHash": "ea8a344c87042019a2708127c7b3551d67dde0989d072eb66c4138aff6571a6d",
      "name": "Quote/ROM",
      "icon": "file-text",
      "linearity": "AFFINE",
      "archetype": "instrument",
      "visibility": {
        "states": [
          "draft",
          "published",
          "revoked"
        ],
        "defaultState": "draft",
        "publishTransition": {
          "fromLinearity": "AFFINE",
          "toLinearity": "RELEVANT",
          "requiredCapabilities": [
            2,
            9
          ]
        },
        "revokePreservesEvidence": true
      },
      "accessPolicy": {
        "default": "private",
        "overridable": true
      },
      "linearityTransitions": [
        {
          "from": "AFFINE",
          "to": "RELEVANT",
          "trigger": "presented"
        }
      ],
      "defaultCapabilities": [
        2,
        9
      ],
      "fields": [
        {
          "name": "estimateType",
          "type": "enum",
          "values": [
            "auto_rom",
            "operator_rom",
            "formal_quote"
          ]
        },
        {
          "name": "effortBand",
          "type": "string"
        },
        {
          "name": "costMin",
          "type": "number"
        },
        {
          "name": "costMax",
          "type": "number"
        },
        {
          "name": "materialsNote",
          "type": "string"
        }
      ],
      "category": "inst.quote"
    },
    {
      "typeHash": "1c8ac867f052ea4adb4598c4e3789bbf7b5f758cc7ebab7cfe746f180f43f91e",
      "name": "Visit",
      "icon": "map-pin",
      "linearity": "LINEAR",
      "archetype": "action",
      "conversationEnabled": true,
      "defaultCapabilities": [
        1,
        5
      ],
      "fields": [
        {
          "name": "visitType",
          "type": "enum",
          "values": [
            "inspection",
            "quote_visit",
            "scheduled_work",
            "return_visit",
            "emergency"
          ]
        },
        {
          "name": "scheduledStart",
          "type": "datetime"
        },
        {
          "name": "outcome",
          "type": "enum",
          "values": [
            "completed",
            "partial",
            "rescheduled",
            "no_access",
            "cancelled"
          ]
        }
      ]
    },
    {
      "typeHash": "b7dadfd3ce9dc111ec8b2e6ebd2d52b29a0ca593c2b3ea8874a52cb036a23b77",
      "name": "Invoice",
      "icon": "receipt",
      "linearity": "RELEVANT",
      "archetype": "instrument",
      "defaultCapabilities": [
        2,
        10
      ],
      "fields": [
        {
          "name": "status",
          "type": "enum",
          "values": [
            "draft",
            "sent",
            "viewed",
            "partial",
            "paid",
            "overdue"
          ]
        },
        {
          "name": "amount",
          "type": "number"
        },
        {
          "name": "sentAt",
          "type": "datetime"
        },
        {
          "name": "paidAt",
          "type": "datetime"
        }
      ],
      "category": "inst.invoice"
    },
    {
      "typeHash": "bf3763383aaf43069885db20b386631c6d5d8b8481df2a26769e9de5fe2f9c82",
      "name": "Customer",
      "icon": "user",
      "linearity": "AFFINE",
      "archetype": "thing",
      "conversationEnabled": true,
      "defaultCapabilities": [
        4,
        8
      ],
      "fields": [
        {
          "name": "name",
          "type": "string"
        },
        {
          "name": "phone",
          "type": "string",
          "requiredCapabilities": [
            8
          ]
        },
        {
          "name": "email",
          "type": "string",
          "requiredCapabilities": [
            8
          ]
        },
        {
          "name": "preferredChannel",
          "type": "enum",
          "values": [
            "sms",
            "email",
            "phone",
            "whatsapp",
            "messenger",
            "webchat"
          ]
        },
        {
          "name": "isRepeatCustomer",
          "type": "boolean"
        }
      ]
    },
    {
      "typeHash": "40040cb181f7f0ee5add2b52e8467c6652477f7ce12af39fe380b5084b64f4fe",
      "name": "Property",
      "icon": "home",
      "linearity": "AFFINE",
      "archetype": "thing",
      "conversationEnabled": true,
      "defaultCapabilities": [
        1
      ],
      "fields": [
        {
          "name": "address",
          "type": "string"
        },
        {
          "name": "suburb",
          "type": "string"
        },
        {
          "name": "postcode",
          "type": "string"
        },
        {
          "name": "propertyType",
          "type": "enum",
          "values": [
            "house",
            "unit",
            "land",
            "commercial",
            "other"
          ]
        },
        {
          "name": "ownerIdentityId",
          "type": "string"
        }
      ]
    },
    {
      "typeHash": "fa7955814e32aed3a240ee46fcd053dd48f320d4e6e18d2b2774e491c5f75834",
      "name": "Site",
      "icon": "home",
      "linearity": "AFFINE",
      "archetype": "thing",
      "defaultCapabilities": [
        1
      ],
      "fields": [
        {
          "name": "suburb",
          "type": "string"
        },
        {
          "name": "postcode",
          "type": "string"
        },
        {
          "name": "suburbGroup",
          "type": "enum",
          "values": [
            "core",
            "extended",
            "outside",
            "unknown"
          ]
        },
        {
          "name": "accessNotes",
          "type": "string"
        }
      ]
    }
  ],
  "capabilities": [
    {
      "id": 4,
      "name": "MESSAGING",
      "description": "Chat intake, SMS, WhatsApp"
    },
    {
      "id": 5,
      "name": "ATTESTATION",
      "description": "Evidence chain from AI extraction"
    },
    {
      "id": 10,
      "name": "METERING",
      "description": "Token/effort tracking"
    },
    {
      "id": 2,
      "name": "SIGNING",
      "description": "Quote issuance, invoice signing"
    },
    {
      "id": 9,
      "name": "SCHEMA_SIGNING",
      "description": "Policy version attestation"
    },
    {
      "id": 1,
      "name": "EDGE_CREATION",
      "description": "Site/visit creation"
    },
    {
      "id": 8,
      "name": "DATA_SOVEREIGNTY",
      "description": "Customer data controls"
    }
  ],
  "scripts": [
    {
      "id": "extract-message",
      "name": "Extract Message",
      "description": "Run LLM extraction on incoming message",
      "requiredCapabilities": [
        5
      ]
    },
    {
      "id": "generate-rom",
      "name": "Generate ROM",
      "description": "Produce rough-order-of-magnitude estimate",
      "requiredCapabilities": [
        2,
        9
      ]
    },
    {
      "id": "run-scoring",
      "name": "Run Scoring Pipeline",
      "description": "Customer fit \u2192 quote worthiness \u2192 recommendation",
      "requiredCapabilities": [
        5
      ]
    },
    {
      "id": "transition-state",
      "name": "Transition Job State",
      "description": "FSM state change with audit event",
      "requiredCapabilities": [
        2
      ]
    }
  ],
  "commercePhases": [
    "SOURCE",
    "PARSE",
    "TYPECHECK",
    "ACTION",
    "OUTCOME"
  ],
  "taxonomy": {
    "dimensions": [
      {
        "id": "what",
        "name": "Service Category",
        "rootPath": "services",
        "nodes": [
          {
            "path": "services.trades",
            "name": "Trades",
            "children": [
              {
                "path": "services.trades.carpentry",
                "name": "Carpentry"
              },
              {
                "path": "services.trades.doors_windows",
                "name": "Doors & Windows"
              },
              {
                "path": "services.trades.fencing",
                "name": "Fencing"
              },
              {
                "path": "services.trades.painting",
                "name": "Painting"
              },
              {
                "path": "services.trades.plumbing",
                "name": "Plumbing"
              },
              {
                "path": "services.trades.tiling",
                "name": "Tiling"
              },
              {
                "path": "services.trades.roofing",
                "name": "Roofing"
              },
              {
                "path": "services.trades.electrical",
                "name": "Electrical"
              },
              {
                "path": "services.trades.gardening",
                "name": "Gardening"
              },
              {
                "path": "services.trades.cleaning",
                "name": "Cleaning"
              }
            ]
          }
        ]
      },
      {
        "id": "how",
        "name": "Transaction Type",
        "rootPath": "tx",
        "nodes": [
          {
            "path": "tx.hire",
            "name": "Hire (Service)"
          },
          {
            "path": "tx.sale",
            "name": "Sale (Supply & Install)"
          }
        ]
      },
      {
        "id": "instrument",
        "name": "Instrument",
        "rootPath": "inst",
        "nodes": [
          {
            "path": "inst.quote",
            "name": "Quote",
            "children": [
              {
                "path": "inst.quote.rom",
                "name": "Rough Order of Magnitude"
              },
              {
                "path": "inst.quote.formal",
                "name": "Formal Quote"
              }
            ]
          },
          {
            "path": "inst.invoice",
            "name": "Invoice",
            "children": [
              {
                "path": "inst.invoice.tax-invoice",
                "name": "Tax Invoice"
              }
            ]
          }
        ]
      }
    ]
  },
  "policies": [
    {
      "id": "scoring-v1",
      "name": "Default Scoring Policy",
      "version": 1,
      "weights": {
        "fit.baseline": 50,
        "fit.acceptedRomBonus": 20,
        "fit.rejectedRomPenalty": -15,
        "worthiness.coreSuburbPoints": 25,
        "worthiness.extendedSuburbPoints": 15,
        "worthiness.fitContributionMultiplier": 0.3
      },
      "thresholds": {
        "priorityLeadMinWorthiness": 70,
        "priorityLeadMinFit": 60,
        "probablyBookableMinWorthiness": 55,
        "probablyBookableMinFit": 45,
        "worthQuotingMinWorthiness": 40,
        "worthQuotingMinFit": 35,
        "fitHardRejectThreshold": 20
      },
      "activatedAt": "2026-01-01T00:00:00Z"
    },
    {
      "id": "pricing-v1",
      "name": "Auto-ROM Pricing Policy",
      "version": 1,
      "description": "Generates a ballpark range (ROM) from effort band, travel distance, and category. The homeowner sees a value-based range, not hourly rates. Hourly is only the calculation baseline.",
      "baseRates": {
        "quick": {
          "min": 80,
          "max": 120
        },
        "short": {
          "min": 150,
          "max": 250
        },
        "quarter_day": {
          "min": 280,
          "max": 400
        },
        "half_day": {
          "min": 450,
          "max": 650
        },
        "full_day": {
          "min": 750,
          "max": 1100
        },
        "multi_day": {
          "min": 1200,
          "max": 0,
          "note": "requires_formal_quote"
        }
      },
      "travelModifiers": {
        "core": {
          "surcharge": 0,
          "label": "No travel surcharge"
        },
        "extended": {
          "surcharge": 60,
          "label": "+$60 travel"
        },
        "outside": {
          "surcharge": 0,
          "decline": true,
          "label": "Outside service area"
        }
      },
      "categoryModifiers": {
        "services.trades.plumbing": {
          "factor": 1.0
        },
        "services.trades.electrical": {
          "factor": 1.15,
          "note": "licensed trade premium"
        },
        "services.trades.roofing": {
          "factor": 1.2,
          "note": "height/safety premium"
        },
        "services.trades.carpentry": {
          "factor": 1.0
        },
        "services.trades.painting": {
          "factor": 0.9
        },
        "services.trades.tiling": {
          "factor": 1.05
        },
        "services.trades.fencing": {
          "factor": 1.0
        },
        "services.trades.cleaning": {
          "factor": 0.85
        },
        "services.trades.gardening": {
          "factor": 0.8
        },
        "services.trades.doors_windows": {
          "factor": 1.0
        }
      },
      "complexityModifiers": {
        "2_story": {
          "factor": 1.2,
          "label": "Two-story access"
        },
        "tricky_access": {
          "factor": 1.15,
          "label": "Difficult access"
        },
        "emergency": {
          "factor": 1.5,
          "label": "Emergency callout"
        }
      },
      "sizingQuestions": {
        "_doc": "Category-specific fields needed to refine the effort band. If the homeowner hasn't provided these, the system should ask conversationally before generating a ROM.",
        "services.trades.cleaning": {
          "required": [
            "bedrooms",
            "stories"
          ],
          "optional": [
            "gutterMetres",
            "lastCleaned"
          ],
          "effortMap": {
            "1-2bed_single": "quick",
            "3bed_single": "short",
            "4bed_single": "quarter_day",
            "3bed_2story": "quarter_day",
            "4bed_2story": "half_day",
            "5plus_or_large": "half_day"
          },
          "prompts": {
            "bedrooms": "How many bedrooms?",
            "stories": "Single or double story?",
            "gutterMetres": "Any idea roughly how many metres of guttering? (don't worry if not)",
            "lastCleaned": "When were they last cleaned?"
          }
        },
        "services.trades.plumbing": {
          "required": [
            "jobScope"
          ],
          "optional": [
            "fixtureCount",
            "accessDifficulty"
          ],
          "effortMap": {
            "single_fixture": "quick",
            "multi_fixture": "short",
            "repipe_section": "half_day",
            "full_repipe": "full_day"
          },
          "prompts": {
            "jobScope": "Is this a single fixture (tap, toilet) or something bigger?",
            "fixtureCount": "How many fixtures need work?",
            "accessDifficulty": "Is it easy to get to or is it under the house / in a wall?"
          }
        },
        "services.trades.electrical": {
          "required": [
            "jobScope"
          ],
          "optional": [
            "pointCount",
            "switchboardAge"
          ],
          "effortMap": {
            "single_point": "quick",
            "few_points": "short",
            "room_rewire": "half_day",
            "switchboard_upgrade": "half_day",
            "full_rewire": "multi_day"
          },
          "prompts": {
            "jobScope": "Is this a single power point/light, a few points, or a bigger job like a rewire?",
            "pointCount": "How many points or lights need doing?",
            "switchboardAge": "Do you know roughly how old the switchboard is?"
          }
        },
        "services.trades.painting": {
          "required": [
            "scope",
            "bedrooms"
          ],
          "optional": [
            "sqMetres",
            "ceilings"
          ],
          "effortMap": {
            "single_room": "quarter_day",
            "2_3_rooms": "full_day",
            "whole_interior": "multi_day",
            "exterior": "multi_day",
            "touch_up": "quick"
          },
          "prompts": {
            "scope": "Is this a single room, a few rooms, whole house, or exterior?",
            "bedrooms": "How many bedrooms in the house?",
            "sqMetres": "Any idea on the room size in square metres?",
            "ceilings": "Do the ceilings need doing too?"
          }
        },
        "services.trades.fencing": {
          "required": [
            "metreage",
            "fenceType"
          ],
          "optional": [
            "existingRemoval",
            "slopeGrade"
          ],
          "effortMap": {
            "under_10m": "quarter_day",
            "10_20m": "half_day",
            "20_40m": "full_day",
            "over_40m": "multi_day"
          },
          "prompts": {
            "metreage": "Roughly how many metres of fencing?",
            "fenceType": "What type \u2014 colorbond, timber, pool fencing?",
            "existingRemoval": "Does old fencing need removing?",
            "slopeGrade": "Is the ground flat or sloped?"
          }
        },
        "services.trades.gardening": {
          "required": [
            "scope"
          ],
          "optional": [
            "yardSize",
            "greenWaste"
          ],
          "effortMap": {
            "mow_and_edge": "quick",
            "garden_tidy": "short",
            "major_cleanup": "half_day",
            "landscaping": "multi_day"
          },
          "prompts": {
            "scope": "Is this a regular mow, a garden tidy-up, or something bigger?",
            "yardSize": "How big is the yard roughly?",
            "greenWaste": "Will there be much green waste to take away?"
          }
        },
        "_default": {
          "required": [
            "jobScope"
          ],
          "optional": [],
          "effortMap": {
            "small": "quick",
            "medium": "short",
            "large": "half_day",
            "major": "full_day"
          },
          "prompts": {
            "jobScope": "Can you give me a rough idea of the scope \u2014 small fix, medium job, or something bigger?"
          }
        }
      },
      "presentation": {
        "roundTo": 10,
        "rangeLabel": "Typically runs",
        "disclaimer": "This is a ballpark figure based on similar jobs in your area. The final price may vary once the tradie assesses the job on site."
      },
      "activatedAt": "2026-01-01T00:00:00Z"
    }
  ],
  "flows": [
    {
      "id": "create-job",
      "name": "New Job Intake",
      "triggerIntents": [
        "create.job",
        "need.service",
        "request.quote"
      ],
      "requiredCapabilities": [
        4,
        5
      ],
      "steps": [
        {
          "id": "ask-service-type",
          "prompt": "What type of service is needed?",
          "field": "categoryPath",
          "extractionSchema": {
            "categoryPath": "string"
          },
          "validation": "required"
        },
        {
          "id": "ask-urgency",
          "prompt": "How urgent is this? (emergency, urgent, next week, flexible...)",
          "field": "urgency",
          "extractionSchema": {
            "urgency": "string"
          },
          "validation": "required"
        },
        {
          "id": "ask-details",
          "prompt": "Any specific details about the work needed?",
          "field": "description",
          "extractionSchema": {
            "description": "string"
          },
          "validation": "optional"
        }
      ],
      "onComplete": {
        "type": "create",
        "objectType": "Job"
      }
    },
    {
      "id": "generate-estimate",
      "name": "Generate Estimate",
      "triggerIntents": [
        "create.quote",
        "generate.rom"
      ],
      "requiredCapabilities": [
        2,
        9
      ],
      "steps": [
        {
          "id": "ask-estimate-type",
          "prompt": "Rough order of magnitude or formal quote?",
          "field": "estimateType",
          "extractionSchema": {
            "estimateType": "string"
          },
          "validation": "required"
        },
        {
          "id": "ask-materials",
          "prompt": "Any materials or special requirements to note?",
          "field": "materialsNote",
          "extractionSchema": {
            "materialsNote": "string"
          },
          "validation": "optional"
        }
      ],
      "onComplete": {
        "type": "create",
        "objectType": "Quote/ROM"
      }
    },
    {
      "id": "schedule-visit",
      "name": "Schedule Visit",
      "triggerIntents": [
        "schedule.visit",
        "create.visit"
      ],
      "requiredCapabilities": [
        1
      ],
      "steps": [
        {
          "id": "ask-visit-type",
          "prompt": "What type of visit? (inspection, quote visit, scheduled work, return visit, emergency)",
          "field": "visitType",
          "extractionSchema": {
            "visitType": "string"
          },
          "validation": "required"
        },
        {
          "id": "ask-when",
          "prompt": "When should the visit be scheduled?",
          "field": "scheduledStart",
          "extractionSchema": {
            "scheduledStart": "string"
          },
          "validation": "required"
        }
      ],
      "onComplete": {
        "type": "create",
        "objectType": "Visit"
      }
    },
    {
      "id": "publish-job",
      "name": "Publish Job",
      "triggerIntents": [
        "publish",
        "make.public",
        "share"
      ],
      "requiredCapabilities": [
        2,
        5
      ],
      "steps": [
        {
          "id": "confirm-publish",
          "prompt": "Publishing will make this object visible and transition it to RELEVANT linearity. Confirm? (yes/no)",
          "field": "confirmed",
          "extractionSchema": {
            "confirmed": "boolean"
          },
          "validation": "required"
        }
      ],
      "onComplete": {
        "type": "transition",
        "linearityTransition": "AFFINE_TO_RELEVANT"
      }
    },
    {
      "id": "revoke-job",
      "name": "Revoke Job",
      "triggerIntents": [
        "revoke",
        "retract",
        "hide",
        "unpublish"
      ],
      "requiredCapabilities": [
        2
      ],
      "steps": [
        {
          "id": "confirm-revoke",
          "prompt": "Are you sure you want to revoke? Evidence chain will be preserved.",
          "field": "confirmed",
          "extractionSchema": {
            "confirmed": "boolean"
          },
          "validation": "required"
        }
      ],
      "onComplete": {
        "type": "transition",
        "linearityTransition": "REVOKE"
      }
    }
  ],
  "extensionTier": "application",
  "coordinationModes": [
    {
      "mode": "do",
      "context": "manage",
      "objectTypes": [
        "fde9975a0730079ece230341749e03a1e259a41163de15c23d2ff25ee0789e0d",
        "ea8a344c87042019a2708127c7b3551d67dde0989d072eb66c4138aff6571a6d",
        "1c8ac867f052ea4adb4598c4e3789bbf7b5f758cc7ebab7cfe746f180f43f91e"
      ],
      "flows": [
        "create-job",
        "generate-estimate",
        "schedule-visit",
        "publish-job",
        "revoke-job"
      ],
      "label": "Jobs & Visits"
    },
    {
      "mode": "do",
      "context": "transact",
      "objectTypes": [
        "b7dadfd3ce9dc111ec8b2e6ebd2d52b29a0ca593c2b3ea8874a52cb036a23b77"
      ],
      "label": "Invoices"
    },
    {
      "mode": "do",
      "context": "offer",
      "objectTypes": [
        "fde9975a0730079ece230341749e03a1e259a41163de15c23d2ff25ee0789e0d"
      ],
      "flows": [
        "publish-job",
        "revoke-job"
      ],
      "label": "Published Jobs"
    },
    {
      "mode": "find",
      "context": "network",
      "objectTypes": [
        "bf3763383aaf43069885db20b386631c6d5d8b8481df2a26769e9de5fe2f9c82",
        "40040cb181f7f0ee5add2b52e8467c6652477f7ce12af39fe380b5084b64f4fe",
        "fa7955814e32aed3a240ee46fcd053dd48f320d4e6e18d2b2774e491c5f75834"
      ],
      "label": "Contacts & Sites"
    }
  ]
}

```
