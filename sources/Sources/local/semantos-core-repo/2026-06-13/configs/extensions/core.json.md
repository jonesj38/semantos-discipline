---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/configs/extensions/core.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.380795+00:00
---

# configs/extensions/core.json

```json
{
  "id": "core",
  "name": "Semantos Core",
  "objectTypes": [
    {
      "typeHash": "7d92d02dacdd3bc9af6857c0373674164963a5a6c73409deb7aaaf6203b008ab",
      "name": "Thing",
      "icon": "box",
      "linearity": "AFFINE",
      "archetype": "thing",
      "defaultCapabilities": [],
      "fields": [
        {
          "name": "name",
          "type": "string"
        },
        {
          "name": "description",
          "type": "string"
        }
      ]
    },
    {
      "typeHash": "64cff1319d2fd2cbb7a1e84ccecf22c1cc07b24435cdb522f8c0aa525d6002a6",
      "name": "Action",
      "icon": "zap",
      "linearity": "LINEAR",
      "archetype": "action",
      "conversationEnabled": true,
      "defaultCapabilities": [],
      "fields": [
        {
          "name": "name",
          "type": "string"
        },
        {
          "name": "status",
          "type": "enum",
          "values": [
            "pending",
            "active",
            "complete"
          ]
        }
      ]
    },
    {
      "typeHash": "6fdf3c9bc6189bcb86e731f340a32bbc071d672fee4026b1d97ccce9283edb25",
      "name": "Instrument",
      "icon": "file-text",
      "linearity": "RELEVANT",
      "archetype": "instrument",
      "defaultCapabilities": [
        2
      ],
      "fields": [
        {
          "name": "name",
          "type": "string"
        },
        {
          "name": "type",
          "type": "string"
        }
      ]
    },
    {
      "typeHash": "540724e9ecd4c88fb8a29d9abba51a77767a7f0ee727091e6f068868d7ff9c41",
      "name": "Dispute",
      "icon": "alert-triangle",
      "linearity": "AFFINE",
      "archetype": "action",
      "conversationEnabled": true,
      "visibility": {
        "states": [
          "draft",
          "published"
        ],
        "defaultState": "draft",
        "publishTransition": {
          "fromLinearity": "AFFINE",
          "toLinearity": "RELEVANT"
        },
        "revokePreservesEvidence": false
      },
      "linearityTransitions": [
        {
          "from": "AFFINE",
          "to": "RELEVANT",
          "trigger": "resolved"
        }
      ],
      "defaultCapabilities": [
        5,
        1
      ],
      "fields": [
        {
          "name": "subjectObjectId",
          "type": "string"
        },
        {
          "name": "claimantHatId",
          "type": "string"
        },
        {
          "name": "respondentHatId",
          "type": "string"
        },
        {
          "name": "status",
          "type": "enum",
          "values": [
            "open",
            "evidence",
            "review",
            "resolved"
          ]
        },
        {
          "name": "resolution",
          "type": "enum",
          "values": [
            "pending",
            "upheld",
            "dismissed",
            "split"
          ]
        }
      ],
      "category": "governance.dispute"
    },
    {
      "typeHash": "66cd01587f2b0dac42a4da379b4cbd48b731808c58eac35c4ed37472bc4312f3",
      "name": "Ballot",
      "icon": "vote",
      "linearity": "AFFINE",
      "archetype": "action",
      "conversationEnabled": true,
      "linearityTransitions": [
        {
          "from": "AFFINE",
          "to": "RELEVANT",
          "trigger": "finalized"
        }
      ],
      "defaultCapabilities": [
        5
      ],
      "fields": [
        {
          "name": "motion",
          "type": "string"
        },
        {
          "name": "quorum",
          "type": "number",
          "min": 1
        },
        {
          "name": "votesFor",
          "type": "number",
          "min": 0
        },
        {
          "name": "votesAgainst",
          "type": "number",
          "min": 0
        },
        {
          "name": "status",
          "type": "enum",
          "values": [
            "open",
            "quorum_reached",
            "finalized"
          ]
        }
      ],
      "category": "governance.ballot"
    },
    {
      "typeHash": "d402e700ffaa30815ac7d0ba8c2c1c07d9fc128cac530a5f13891e869ea09356",
      "name": "Stake",
      "icon": "lock",
      "linearity": "LINEAR",
      "archetype": "instrument",
      "defaultCapabilities": [
        10
      ],
      "fields": [
        {
          "name": "amount",
          "type": "number",
          "min": 0
        },
        {
          "name": "subjectObjectId",
          "type": "string"
        },
        {
          "name": "stakerHatId",
          "type": "string"
        },
        {
          "name": "status",
          "type": "enum",
          "values": [
            "active",
            "forfeited",
            "returned"
          ]
        }
      ],
      "category": "governance.stake"
    },
    {
      "typeHash": "9f2345714fa3ae7aa146f7eacc0c5c83fc6ba5e088fefa8c5b73177926a4cca5",
      "name": "Resolution",
      "icon": "check-circle",
      "linearity": "RELEVANT",
      "archetype": "instrument",
      "defaultCapabilities": [
        5,
        2
      ],
      "fields": [
        {
          "name": "disputeObjectId",
          "type": "string"
        },
        {
          "name": "outcome",
          "type": "enum",
          "values": [
            "upheld",
            "dismissed",
            "split"
          ]
        },
        {
          "name": "reasoning",
          "type": "string"
        }
      ],
      "category": "governance.resolution"
    },
    {
      "typeHash": "11fcdd9b9f943f6497355b64213d5e7ccc6ee1967cc08664189e63394c0ccab6",
      "name": "TaxonomyNode",
      "icon": "tag",
      "linearity": "RELEVANT",
      "archetype": "thing",
      "defaultCapabilities": [
        5
      ],
      "fields": [
        {
          "name": "axis",
          "type": "enum",
          "values": [
            "what",
            "how",
            "why"
          ]
        },
        {
          "name": "path",
          "type": "string"
        },
        {
          "name": "name",
          "type": "string"
        },
        {
          "name": "parentPath",
          "type": "string"
        },
        {
          "name": "functionType",
          "type": "string"
        },
        {
          "name": "primaryOutputs",
          "type": "string"
        },
        {
          "name": "requiredInputs",
          "type": "string"
        }
      ],
      "category": "taxonomy.node"
    },
    {
      "typeHash": "6e7b4c491ebdfec2d180dab317d4bd07a9f60af1d0510eb49899f33f4d9c44fd",
      "name": "PaymentChannel",
      "icon": "zap",
      "linearity": "LINEAR",
      "archetype": "instrument",
      "conversationEnabled": true,
      "defaultCapabilities": [
        10,
        4
      ],
      "fields": [
        {
          "name": "counterpartyCertId",
          "type": "string"
        },
        {
          "name": "fundingSatoshis",
          "type": "number",
          "min": 0
        },
        {
          "name": "fundingDeadline",
          "type": "number"
        },
        {
          "name": "policyObjectId",
          "type": "string"
        },
        {
          "name": "channelCertId",
          "type": "string"
        },
        {
          "name": "counterpartyEdgeId",
          "type": "string"
        },
        {
          "name": "currentTick",
          "type": "number",
          "min": 0
        },
        {
          "name": "cumulativeSatoshis",
          "type": "number",
          "min": 0
        },
        {
          "name": "status",
          "type": "enum",
          "values": [
            "prefunding",
            "funding",
            "active",
            "settling",
            "settled",
            "disputed",
            "closed"
          ]
        },
        {
          "name": "meterUnit",
          "type": "string"
        },
        {
          "name": "disputeId",
          "type": "string"
        },
        {
          "name": "ballotId",
          "type": "string"
        },
        {
          "name": "settlementTxId",
          "type": "string"
        },
        {
          "name": "settlementConfirmed",
          "type": "boolean"
        }
      ],
      "category": "metering.channel"
    },
    {
      "typeHash": "85d65cebbd63c4da52dcc2adddbca105f77482c371b98891e0b3997fe625625d",
      "name": "GovernancePolicy",
      "icon": "shield",
      "linearity": "RELEVANT",
      "archetype": "instrument",
      "constitution": true,
      "defaultCapabilities": [
        9,
        5
      ],
      "fields": [
        {
          "name": "metaSchemaVersion",
          "type": "string"
        },
        {
          "name": "requiredCapabilitiesWhitelist",
          "type": "array"
        },
        {
          "name": "taxonomyNamespaceReservations",
          "type": "array"
        },
        {
          "name": "marketplaceListingRequirements",
          "type": "object"
        },
        {
          "name": "breakingChangeBallotQuorum",
          "type": "number",
          "min": 1
        },
        {
          "name": "emergencyDeprecationPolicy",
          "type": "object"
        },
        {
          "name": "effectiveDate",
          "type": "string"
        },
        {
          "name": "governedByHatId",
          "type": "string"
        }
      ],
      "category": "governance.policy"
    },
    {
      "typeHash": "de3dd504f5a11bad9038e9e078846b464675ff271a4bd41caffdb01e6ad7709f",
      "name": "ChannelPolicy",
      "icon": "shield",
      "linearity": "RELEVANT",
      "archetype": "instrument",
      "defaultCapabilities": [
        10,
        9
      ],
      "fields": [
        {
          "name": "name",
          "type": "string"
        },
        {
          "name": "minFundingSatoshis",
          "type": "number",
          "min": 0
        },
        {
          "name": "maxChannelDurationSeconds",
          "type": "number",
          "min": 0
        },
        {
          "name": "disputeWindowSeconds",
          "type": "number",
          "min": 0
        },
        {
          "name": "settlementFeePercent",
          "type": "number",
          "min": 0
        },
        {
          "name": "meterUnit",
          "type": "string"
        },
        {
          "name": "pricePerUnit",
          "type": "number",
          "min": 0
        },
        {
          "name": "autoSettleThreshold",
          "type": "number",
          "min": 0
        }
      ],
      "category": "metering.policy"
    },
    {
      "typeHash": "d5840aa6852670e439420bd483124f7fb4ed94df15fdacc76e831655ecfd3f87",
      "name": "ConsumerBinding",
      "icon": "link",
      "linearity": "AFFINE",
      "archetype": "thing",
      "scope": "node",
      "defaultCapabilities": [
        2
      ],
      "fields": [
        {
          "name": "extensionManifestId",
          "type": "string"
        },
        {
          "name": "grammarVersionPinned",
          "type": "string"
        },
        {
          "name": "credentialsEncrypted",
          "type": "object"
        },
        {
          "name": "fieldOverrides",
          "type": "array"
        },
        {
          "name": "taxonomyOverrides",
          "type": "array"
        },
        {
          "name": "autoUpdateGrammar",
          "type": "boolean"
        },
        {
          "name": "lastExtractionTimestamp",
          "type": "string"
        },
        {
          "name": "status",
          "type": "enum",
          "values": [
            "active",
            "paused",
            "deprecated"
          ]
        }
      ],
      "category": "extension.consumer-binding"
    },
    {
      "typeHash": "f2923ed12b918b9ceda061c765349738e2ed9a62eaded7067271c5aa44802364",
      "name": "Document",
      "icon": "file-text",
      "linearity": "AFFINE",
      "archetype": "instrument",
      "visibility": {
        "states": [
          "draft",
          "published"
        ],
        "defaultState": "draft",
        "revokePreservesEvidence": true,
        "publishTransition": {
          "fromLinearity": "AFFINE",
          "toLinearity": "RELEVANT"
        }
      },
      "defaultCapabilities": [
        2
      ],
      "fields": [
        {
          "name": "title",
          "type": "string"
        },
        {
          "name": "content",
          "type": "string"
        },
        {
          "name": "format",
          "type": "enum",
          "values": [
            "markdown",
            "plaintext"
          ]
        }
      ],
      "category": "core.document"
    },
    {
      "typeHash": "cf9352953c21cb39fbf47375f7f51293d9e63a512de79f24a0fac5da919b8e66",
      "name": "Event",
      "icon": "calendar",
      "linearity": "AFFINE",
      "archetype": "instrument",
      "visibility": {
        "states": [
          "draft",
          "published",
          "revoked"
        ],
        "defaultState": "draft",
        "revokePreservesEvidence": true,
        "publishTransition": {
          "fromLinearity": "AFFINE",
          "toLinearity": "RELEVANT"
        }
      },
      "defaultCapabilities": [
        2
      ],
      "fields": [
        {
          "name": "title",
          "type": "string"
        },
        {
          "name": "date",
          "type": "string"
        },
        {
          "name": "time",
          "type": "string"
        },
        {
          "name": "duration",
          "type": "string"
        },
        {
          "name": "location",
          "type": "string"
        },
        {
          "name": "description",
          "type": "string"
        },
        {
          "name": "recurrence",
          "type": "enum",
          "values": [
            "none",
            "daily",
            "weekly",
            "monthly",
            "yearly"
          ]
        },
        {
          "name": "status",
          "type": "enum",
          "values": [
            "tentative",
            "confirmed",
            "cancelled"
          ]
        }
      ],
      "category": "core.event"
    },
    {
      "typeHash": "4b8f8f568f22ff2897414854e13bff6b5686748c8640d5e6a35b4ddf68848475",
      "name": "Channel",
      "icon": "radio",
      "linearity": "AFFINE",
      "archetype": "instrument",
      "visibility": {
        "states": [
          "draft",
          "published",
          "revoked"
        ],
        "defaultState": "draft",
        "revokePreservesEvidence": true,
        "publishTransition": {
          "fromLinearity": "AFFINE",
          "toLinearity": "RELEVANT"
        }
      },
      "defaultCapabilities": [
        2
      ],
      "fields": [
        {
          "name": "name",
          "type": "string"
        },
        {
          "name": "topic",
          "type": "string"
        },
        {
          "name": "description",
          "type": "string"
        },
        {
          "name": "category",
          "type": "string"
        },
        {
          "name": "visibility",
          "type": "enum",
          "values": [
            "public",
            "unlisted",
            "private"
          ]
        }
      ],
      "category": "core.channel"
    },
    {
      "typeHash": "6bcd26da8e4b2b134657268c571f49ced46dd283a4b35b182e184125808b4c71",
      "name": "Stream",
      "icon": "activity",
      "linearity": "AFFINE",
      "archetype": "instrument",
      "visibility": {
        "states": [
          "draft",
          "published",
          "revoked"
        ],
        "defaultState": "draft",
        "revokePreservesEvidence": true,
        "publishTransition": {
          "fromLinearity": "AFFINE",
          "toLinearity": "RELEVANT"
        }
      },
      "defaultCapabilities": [
        2
      ],
      "fields": [
        {
          "name": "name",
          "type": "string"
        },
        {
          "name": "description",
          "type": "string"
        },
        {
          "name": "cadence",
          "type": "enum",
          "values": [
            "realtime",
            "hourly",
            "daily",
            "weekly",
            "adhoc"
          ]
        },
        {
          "name": "category",
          "type": "string"
        }
      ],
      "category": "core.stream"
    },
    {
      "typeHash": "a3660a678f5bf5bb466ead8bec13d363e149b4f19be079816e1f626ecd90216f",
      "name": "Page",
      "icon": "file",
      "linearity": "AFFINE",
      "archetype": "instrument",
      "visibility": {
        "states": [
          "draft",
          "published",
          "revoked"
        ],
        "defaultState": "draft",
        "revokePreservesEvidence": true,
        "publishTransition": {
          "fromLinearity": "AFFINE",
          "toLinearity": "RELEVANT"
        }
      },
      "defaultCapabilities": [
        2
      ],
      "fields": [
        {
          "name": "title",
          "type": "string"
        },
        {
          "name": "slug",
          "type": "string"
        },
        {
          "name": "summary",
          "type": "string"
        },
        {
          "name": "content",
          "type": "string"
        },
        {
          "name": "format",
          "type": "enum",
          "values": [
            "markdown",
            "plaintext"
          ]
        }
      ],
      "category": "core.page"
    }
  ],
  "capabilities": [
    {
      "id": 1,
      "name": "EDGE_CREATION",
      "description": "Create graph edges"
    },
    {
      "id": 2,
      "name": "SIGNING",
      "description": "Sign objects and instruments"
    },
    {
      "id": 3,
      "name": "ENCRYPTION",
      "description": "Encrypt payloads"
    },
    {
      "id": 4,
      "name": "MESSAGING",
      "description": "Send and receive messages"
    },
    {
      "id": 5,
      "name": "ATTESTATION",
      "description": "Create attestations"
    },
    {
      "id": 6,
      "name": "CHILD_CREATION",
      "description": "Create child objects"
    },
    {
      "id": 7,
      "name": "PERMISSION_GRANT",
      "description": "Grant permissions"
    },
    {
      "id": 8,
      "name": "DATA_SOVEREIGNTY",
      "description": "Control data access"
    },
    {
      "id": 9,
      "name": "SCHEMA_SIGNING",
      "description": "Sign schemas and policies"
    },
    {
      "id": 10,
      "name": "METERING",
      "description": "Track usage and effort"
    }
  ],
  "flows": [
    {
      "id": "file-dispute",
      "name": "File Dispute",
      "triggerIntents": [
        "dispute",
        "challenge",
        "flag",
        "report"
      ],
      "requiredCapabilities": [
        5
      ],
      "steps": [
        {
          "id": "ask-subject",
          "prompt": "Which object are you disputing?",
          "field": "subjectObjectId",
          "extractionSchema": {
            "subjectObjectId": "string"
          },
          "validation": "required"
        },
        {
          "id": "ask-reason",
          "prompt": "What is the basis of your dispute?",
          "field": "reasoning",
          "extractionSchema": {
            "reasoning": "string"
          },
          "validation": "required"
        }
      ],
      "onComplete": {
        "type": "create",
        "objectType": "Dispute"
      }
    },
    {
      "id": "cast-vote",
      "name": "Cast Vote",
      "triggerIntents": [
        "vote",
        "approve",
        "reject",
        "support",
        "oppose"
      ],
      "requiredCapabilities": [
        5
      ],
      "steps": [
        {
          "id": "ask-direction",
          "prompt": "Vote for or against?",
          "field": "voteDirection",
          "extractionSchema": {
            "voteDirection": "string"
          },
          "validation": "required"
        }
      ],
      "onComplete": {
        "type": "patch",
        "patchFields": [
          "votesFor",
          "votesAgainst"
        ]
      }
    },
    {
      "id": "stake",
      "name": "Place Stake",
      "triggerIntents": [
        "stake",
        "back",
        "wager"
      ],
      "requiredCapabilities": [
        10
      ],
      "steps": [
        {
          "id": "ask-amount",
          "prompt": "How much do you want to stake?",
          "field": "amount",
          "extractionSchema": {
            "amount": "number"
          },
          "validation": "required"
        },
        {
          "id": "ask-subject",
          "prompt": "What are you staking on?",
          "field": "subjectObjectId",
          "extractionSchema": {
            "subjectObjectId": "string"
          },
          "validation": "required"
        }
      ],
      "onComplete": {
        "type": "create",
        "objectType": "Stake"
      }
    },
    {
      "id": "propose-category",
      "name": "Propose Taxonomy Category",
      "triggerIntents": [
        "propose.category",
        "add.category",
        "suggest.type",
        "new.category"
      ],
      "requiredCapabilities": [
        5
      ],
      "steps": [
        {
          "id": "ask-axis",
          "prompt": "Which axis should this category be on? (what/how/why)",
          "field": "axis",
          "extractionSchema": {
            "axis": "string"
          },
          "validation": "required"
        },
        {
          "id": "ask-parent",
          "prompt": "What is the parent path for this category? (e.g. what.service or how.technical)",
          "field": "parentPath",
          "extractionSchema": {
            "parentPath": "string"
          },
          "validation": "required"
        },
        {
          "id": "ask-name",
          "prompt": "What should this category be called?",
          "field": "nodeName",
          "extractionSchema": {
            "nodeName": "string"
          },
          "validation": "required"
        },
        {
          "id": "ask-rationale",
          "prompt": "Why should this category exist? What production function does it serve?",
          "field": "rationale",
          "extractionSchema": {
            "rationale": "string"
          },
          "validation": "required"
        }
      ],
      "onComplete": {
        "type": "create",
        "objectType": "Ballot"
      }
    },
    {
      "id": "challenge-classification",
      "name": "Challenge Classification",
      "triggerIntents": [
        "challenge.classification",
        "reclassify",
        "wrong.category",
        "misclassified"
      ],
      "requiredCapabilities": [
        5
      ],
      "steps": [
        {
          "id": "ask-subject",
          "prompt": "Which object's classification do you want to challenge?",
          "field": "subjectObjectId",
          "extractionSchema": {
            "subjectObjectId": "string"
          },
          "validation": "required"
        },
        {
          "id": "ask-proposed-what",
          "prompt": "What should the WHAT coordinate be? (leave blank to keep current)",
          "field": "proposedWhat",
          "extractionSchema": {
            "proposedWhat": "string"
          },
          "validation": "optional"
        },
        {
          "id": "ask-proposed-how",
          "prompt": "What should the HOW coordinate(s) be? (comma-separated, leave blank to keep current)",
          "field": "proposedHow",
          "extractionSchema": {
            "proposedHow": "string"
          },
          "validation": "optional"
        },
        {
          "id": "ask-proposed-why",
          "prompt": "What should the WHY coordinate(s) be? (comma-separated, leave blank to keep current)",
          "field": "proposedWhy",
          "extractionSchema": {
            "proposedWhy": "string"
          },
          "validation": "optional"
        },
        {
          "id": "ask-reasoning",
          "prompt": "Explain why this reclassification is correct.",
          "field": "reasoning",
          "extractionSchema": {
            "reasoning": "string"
          },
          "validation": "required"
        }
      ],
      "onComplete": {
        "type": "create",
        "objectType": "Dispute"
      }
    },
    {
      "id": "compliance-demo",
      "name": "Linearity Compliance Demo",
      "triggerIntents": [
        "demo.compliance",
        "demo.linearity",
        "create.linear",
        "test.linearity"
      ],
      "steps": [
        {
          "id": "s1-name",
          "prompt": "Creating a LINEAR object (single-use token). Give it a name:",
          "field": "name",
          "validation": "required",
          "stepAction": {
            "type": "create",
            "objectType": "Action"
          }
        },
        {
          "id": "s2-consume",
          "prompt": "LINEAR object created and selected. Type 'consume' to use it (this is a one-time operation):",
          "field": "consumeConfirm",
          "stepAction": {
            "type": "consume"
          }
        },
        {
          "id": "s3-double-consume",
          "prompt": "Object consumed successfully. Now try consuming again — type 'consume' to see linearity enforcement:",
          "field": "doubleConsumeConfirm",
          "stepAction": {
            "type": "consume"
          }
        },
        {
          "id": "s4-inspect",
          "prompt": "Type 'inspect' to view the full evidence chain and BSV anchor proof:",
          "field": "inspectConfirm"
        }
      ],
      "onComplete": {
        "type": "inspect"
      }
    },
    {
      "id": "channel-open",
      "name": "Open Payment Channel",
      "triggerIntents": [
        "open.channel",
        "new.channel",
        "start.channel",
        "metering"
      ],
      "requiredCapabilities": [
        10
      ],
      "steps": [
        {
          "id": "ask-counterparty",
          "prompt": "Who is the counterparty for this channel? (provide their cert ID)",
          "field": "counterpartyCertId",
          "extractionSchema": {
            "counterpartyCertId": "string"
          },
          "validation": "required"
        },
        {
          "id": "ask-funding",
          "prompt": "How many satoshis to fund this channel with?",
          "field": "fundingSatoshis",
          "extractionSchema": {
            "fundingSatoshis": "number"
          },
          "validation": "required"
        },
        {
          "id": "ask-policy",
          "prompt": "Which policy object ID governs this channel?",
          "field": "policyObjectId",
          "extractionSchema": {
            "policyObjectId": "string"
          },
          "validation": "required"
        }
      ],
      "onComplete": {
        "type": "create",
        "objectType": "PaymentChannel"
      }
    }
  ],
  "channelLifecycle": {
    "flowId": "metering.channel_lifecycle",
    "displayName": "Channel Lifecycle",
    "initialPhase": "prefunding",
    "phases": [
      {
        "phaseId": "prefunding",
        "displayName": "Prefunding",
        "transitions": [
          {
            "targetPhase": "funding",
            "displayName": "Fund Channel",
            "guard": {
              "type": "capability",
              "field": "identity.capabilities",
              "operator": "includes_all",
              "value": [
                2,
                8
              ]
            }
          },
          {
            "targetPhase": "cancelled",
            "displayName": "Cancel",
            "guard": {
              "type": "relationship",
              "field": "identity.certId",
              "operator": "eq",
              "value": "object.ownerCertId"
            }
          }
        ]
      },
      {
        "phaseId": "funding",
        "displayName": "Funding",
        "transitions": [
          {
            "targetPhase": "active",
            "displayName": "Activate",
            "guard": {
              "type": "value",
              "field": "object.fundingSatoshis",
              "operator": "gte",
              "value": "policy.minFundingSatoshis"
            }
          },
          {
            "targetPhase": "expired",
            "displayName": "Expire",
            "guard": {
              "type": "time",
              "field": "object.fundingDeadline",
              "operator": "lt",
              "value": "now()"
            }
          }
        ]
      },
      {
        "phaseId": "active",
        "displayName": "Active",
        "transitions": [
          {
            "targetPhase": "active",
            "displayName": "Transact",
            "guard": {
              "type": "capability",
              "field": "identity.capabilities",
              "operator": "includes_all",
              "value": [
                3
              ]
            }
          },
          {
            "targetPhase": "settling",
            "displayName": "Settle",
            "guard": {
              "type": "capability",
              "field": "identity.capabilities",
              "operator": "includes_all",
              "value": [
                9
              ]
            }
          },
          {
            "targetPhase": "disputed",
            "displayName": "Raise Dispute",
            "guard": {
              "type": "capability",
              "field": "identity.capabilities",
              "operator": "includes_all",
              "value": [
                6,
                7
              ]
            }
          }
        ]
      },
      {
        "phaseId": "settling",
        "displayName": "Settling",
        "transitions": [
          {
            "targetPhase": "settled",
            "displayName": "Settle",
            "guard": {
              "type": "contextual",
              "field": "settlement.signaturesCollected",
              "operator": "eq",
              "value": true
            }
          },
          {
            "targetPhase": "disputed",
            "displayName": "Dispute Settlement",
            "guard": {
              "type": "time",
              "field": "settlement.disputeWindowEnd",
              "operator": "gte",
              "value": "now()"
            }
          }
        ]
      },
      {
        "phaseId": "disputed",
        "displayName": "Disputed",
        "transitions": [
          {
            "targetPhase": "settling",
            "displayName": "Resolve to Settlement",
            "guard": {
              "type": "contextual",
              "field": "ballot.resolution",
              "operator": "eq",
              "value": "settlement_approved"
            }
          },
          {
            "targetPhase": "closed",
            "displayName": "Force Close",
            "guard": {
              "type": "contextual",
              "field": "ballot.resolution",
              "operator": "eq",
              "value": "force_close"
            }
          }
        ]
      },
      {
        "phaseId": "settled",
        "displayName": "Settled",
        "transitions": [
          {
            "targetPhase": "closed",
            "displayName": "Close",
            "guard": {
              "type": "contextual",
              "field": "settlement.confirmedOnChain",
              "operator": "eq",
              "value": true
            }
          }
        ]
      },
      {
        "phaseId": "closed",
        "displayName": "Closed",
        "transitions": []
      },
      {
        "phaseId": "cancelled",
        "displayName": "Cancelled",
        "transitions": []
      },
      {
        "phaseId": "expired",
        "displayName": "Expired",
        "transitions": []
      }
    ]
  },
  "scripts": [],
  "commercePhases": [
    "SOURCE",
    "PARSE",
    "AST",
    "TYPECHECK",
    "OPTIMISE",
    "CODEGEN",
    "ACTION",
    "OUTCOME"
  ],
  "extensionTier": "application",
  "coordinationModes": [
    {
      "mode": "do",
      "context": "create",
      "objectTypes": [
        "7d92d02dacdd3bc9af6857c0373674164963a5a6c73409deb7aaaf6203b008ab",
        "64cff1319d2fd2cbb7a1e84ccecf22c1cc07b24435cdb522f8c0aa525d6002a6",
        "6fdf3c9bc6189bcb86e731f340a32bbc071d672fee4026b1d97ccce9283edb25",
        "6e4368c9d4341432e747fa26deca8e2cedf26266b04caed2b942e45dd65e1b1a",
        "633320619b7813b5af7e2337144a034a7fd0c1971f05f1fde033e83b33623774"
      ],
      "label": "Core Objects"
    },
    {
      "mode": "do",
      "context": "transact",
      "objectTypes": [
        "209c049c6d7146b83592ccd9c08ea88137bff15af0f86a93aed01b120158d6df"
      ],
      "label": "Payment Channels"
    },
    {
      "mode": "talk",
      "context": "broadcast",
      "objectTypes": [
        "20fbf01b5bde306b952696a9a010e2b67e6e22236c08299bdfd3a4b190212d8b",
        "7f905e14b65431d19cda513bba469724c116ca59d5907d0cf25bc1e57c34f112",
        "2ee00446cc56e97851e28cf12a648250198e71fe18e985b8394e7334ada7f608"
      ],
      "flows": [
        "file-dispute",
        "cast-vote",
        "stake",
        "propose-category",
        "challenge-classification"
      ],
      "label": "Governance"
    },
    {
      "mode": "find",
      "context": "market",
      "objectTypes": [
        "bb542f0f500fabf87848cb9b0f735bc893f718a1d0bb1dd39569d7e214ef6dde"
      ],
      "label": "Taxonomy Browse"
    },
    {
      "mode": "find",
      "context": "truth",
      "objectTypes": [
        "85d65cebbd63c4da52dcc2adddbca105f77482c371b98891e0b3997fe625625d"
      ],
      "label": "Governance Policies"
    },
    {
      "mode": "find",
      "context": "network",
      "objectTypes": [
        "d5840aa6852670e439420bd483124f7fb4ed94df15fdacc76e831655ecfd3f87"
      ],
      "label": "Consumer Bindings"
    }
  ]
}

```
