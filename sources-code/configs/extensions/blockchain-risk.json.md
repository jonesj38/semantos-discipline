---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/configs/extensions/blockchain-risk.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.381100+00:00
---

# configs/extensions/blockchain-risk.json

```json
{
  "id": "blockchain-risk",
  "name": "Blockchain Risk (BREM-Agent)",
  "objectTypes": [
    {
      "typeHash": "985959785319747668373cc6dee294b11db782b03cdd90a2851fbdc0637c6b7b",
      "name": "Project",
      "icon": "box",
      "linearity": "AFFINE",
      "archetype": "thing",
      "visibility": {
        "states": ["draft", "published"],
        "defaultState": "draft",
        "publishTransition": {
          "fromLinearity": "AFFINE",
          "toLinearity": "RELEVANT",
          "requiredCapabilities": [5, 9]
        },
        "revokePreservesEvidence": true
      },
      "accessPolicy": {
        "default": "private",
        "overridable": false
      },
      "defaultCapabilities": [
        8,
        5,
        10,
        9
      ],
      "fields": [
        {
          "name": "projectName",
          "type": "string"
        },
        {
          "name": "protocolFamily",
          "type": "enum",
          "values": [
            "defi",
            "nft",
            "payment",
            "identity",
            "bridge",
            "oracle",
            "dao",
            "other"
          ]
        },
        {
          "name": "governanceModel",
          "type": "enum",
          "values": [
            "foundation",
            "dao",
            "corporation",
            "hybrid",
            "unknown"
          ]
        },
        {
          "name": "overallScore",
          "type": "number",
          "min": 0,
          "max": 5
        },
        {
          "name": "riskBand",
          "type": "enum",
          "values": [
            "LOW",
            "MODERATE",
            "HIGH",
            "CRITICAL"
          ]
        },
        {
          "name": "assessmentStatus",
          "type": "enum",
          "values": [
            "draft",
            "in_progress",
            "review",
            "complete",
            "challenged"
          ]
        },
        {
          "name": "naScore",
          "type": "number",
          "min": 0,
          "max": 5
        },
        {
          "name": "ncScore",
          "type": "number",
          "min": 0,
          "max": 5
        },
        {
          "name": "nsScore",
          "type": "number",
          "min": 0,
          "max": 5
        },
        {
          "name": "seScore",
          "type": "number",
          "min": 0,
          "max": 5
        },
        {
          "name": "smScore",
          "type": "number",
          "min": 0,
          "max": 5
        },
        {
          "name": "sfScore",
          "type": "number",
          "min": 0,
          "max": 5
        },
        {
          "name": "lsScore",
          "type": "number",
          "min": 0,
          "max": 5
        },
        {
          "name": "lrScore",
          "type": "number",
          "min": 0,
          "max": 5
        },
        {
          "name": "lpScore",
          "type": "number",
          "min": 0,
          "max": 5
        }
      ],
      "maxCells": 4
    },
    {
      "typeHash": "4685dc6b3c3fe383bd4c66564a7cf3e95a8849640f9fda5b32db805112c41e80",
      "name": "CellState",
      "icon": "box",
      "linearity": "LINEAR",
      "archetype": "action",
      "defaultCapabilities": [
        5,
        10
      ],
      "fields": [
        {
          "name": "cellKey",
          "type": "enum",
          "values": [
            "na",
            "nc",
            "ns",
            "se",
            "sm",
            "sf",
            "ls",
            "lr",
            "lp"
          ]
        },
        {
          "name": "score",
          "type": "number",
          "min": 0,
          "max": 5
        },
        {
          "name": "evidenceQuality",
          "type": "enum",
          "values": [
            "none",
            "weak",
            "moderate",
            "strong"
          ]
        },
        {
          "name": "isGated",
          "type": "boolean"
        }
      ]
    },
    {
      "typeHash": "b6ce788d9786917c9d19adaa0d904213365607c7f683d7277f508dcf142b4cc2",
      "name": "Report",
      "icon": "file-text",
      "linearity": "RELEVANT",
      "archetype": "instrument",
      "defaultCapabilities": [
        5,
        9
      ],
      "fields": [
        {
          "name": "reportType",
          "type": "enum",
          "values": [
            "initial",
            "update",
            "final",
            "challenge_response"
          ]
        },
        {
          "name": "generatedAt",
          "type": "datetime"
        },
        {
          "name": "summary",
          "type": "string"
        }
      ]
    },
    {
      "typeHash": "73335329a675b3e3c1c92feeefcfbcbb7ca03f98cd8b7e7b9c36964f70b988fc",
      "name": "MitigationInstrument",
      "icon": "receipt",
      "linearity": "RELEVANT",
      "archetype": "instrument",
      "defaultCapabilities": [
        5,
        9
      ],
      "fields": [
        {
          "name": "mitigationType",
          "type": "enum",
          "values": [
            "insurance",
            "audit",
            "escrow",
            "monitoring",
            "compliance",
            "technical"
          ]
        },
        {
          "name": "targetCell",
          "type": "enum",
          "values": [
            "na",
            "nc",
            "ns",
            "se",
            "sm",
            "sf",
            "ls",
            "lr",
            "lp"
          ]
        },
        {
          "name": "impactEstimate",
          "type": "number",
          "min": 0,
          "max": 5
        },
        {
          "name": "status",
          "type": "enum",
          "values": [
            "proposed",
            "active",
            "expired",
            "rejected"
          ]
        }
      ]
    }
  ],
  "capabilities": [
    {
      "id": 8,
      "name": "DATA_SOVEREIGNTY",
      "description": "Project data controls"
    },
    {
      "id": 5,
      "name": "ATTESTATION",
      "description": "Evidence attestation"
    },
    {
      "id": 10,
      "name": "METERING",
      "description": "Usage metering"
    },
    {
      "id": 9,
      "name": "SCHEMA_SIGNING",
      "description": "Schema signing"
    }
  ],
  "scripts": [
    {
      "id": "classify-project",
      "name": "Classify Project",
      "description": "Classify protocol family and governance model"
    },
    {
      "id": "extract-evidence",
      "name": "Extract Evidence",
      "description": "Extract scoring evidence from documents"
    },
    {
      "id": "merge-cell-state",
      "name": "Merge Cell State",
      "description": "Merge multiple cell state patches"
    },
    {
      "id": "score-project",
      "name": "Score Project",
      "description": "Run asymmetric scoring with domain ceilings"
    },
    {
      "id": "generate-mitigations",
      "name": "Generate Mitigations",
      "description": "Produce de-risking instruments"
    }
  ],
  "commercePhases": [
    "SOURCE",
    "PARSE",
    "AST",
    "TYPECHECK",
    "CODEGEN",
    "OUTCOME"
  ],
  "policies": [
    {
      "id": "asymmetric-weights",
      "name": "Asymmetric Weights",
      "version": 1,
      "weights": {
        "nc": 8.22,
        "se": 4.53,
        "na": 2.1,
        "ns": 1.87,
        "sm": 1.45,
        "sf": 1.32,
        "ls": 1.2,
        "lr": 1.1,
        "lp": 1
      },
      "thresholds": {
        "overallMinScore": 2.5,
        "domainCeiling": 3,
        "criticalThreshold": 4,
        "highThreshold": 3,
        "moderateThreshold": 2
      },
      "activatedAt": "2026-01-01T00:00:00Z"
    }
  ],
  "flows": [
    {
      "id": "new-assessment",
      "name": "New Project Assessment",
      "triggerIntents": ["create.project", "assess.project"],
      "requiredCapabilities": [5, 8],
      "steps": [
        {
          "id": "ask-project-name",
          "prompt": "What is the project name?",
          "field": "projectName",
          "extractionSchema": { "projectName": "string" },
          "validation": "required"
        },
        {
          "id": "ask-protocol-family",
          "prompt": "Protocol family? (DeFi, NFT, payment, bridge, oracle, DAO, other)",
          "field": "protocolFamily",
          "extractionSchema": { "protocolFamily": "string" },
          "validation": "required"
        }
      ],
      "onComplete": { "type": "create", "objectType": "Project" }
    },
    {
      "id": "extract-evidence",
      "name": "Extract Evidence",
      "triggerIntents": ["extract.evidence", "add.evidence"],
      "requiredCapabilities": [5],
      "steps": [
        {
          "id": "ask-source",
          "prompt": "Paste or describe the evidence source.",
          "field": "evidenceSource",
          "extractionSchema": { "evidenceSource": "string" },
          "validation": "required"
        }
      ],
      "onComplete": { "type": "patch", "patchFields": ["evidenceSource"] }
    }
  ]
}

```
