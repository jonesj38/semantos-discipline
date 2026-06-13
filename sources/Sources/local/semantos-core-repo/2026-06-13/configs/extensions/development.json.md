---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/configs/extensions/development.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.381359+00:00
---

# configs/extensions/development.json

```json
{
  "id": "development",
  "name": "Development Workbench",
  "objectTypes": [
    {
      "typeHash": "9f7fc81707d7492026634f7ac6b00ef4bd271a5c44b2cd08a19d35f38492dfbf",
      "name": "Generic Object",
      "icon": "box",
      "linearity": "DEBUG",
      "defaultCapabilities": [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10
      ],
      "fields": [
        {
          "name": "label",
          "type": "string"
        },
        {
          "name": "data",
          "type": "string"
        }
      ]
    }
  ],
  "capabilities": [
    {
      "id": 1,
      "name": "EDGE_CREATION",
      "description": "Create edges/connections"
    },
    {
      "id": 2,
      "name": "SIGNING",
      "description": "Digital signatures"
    },
    {
      "id": 3,
      "name": "ENCRYPTION",
      "description": "Encrypt payloads"
    },
    {
      "id": 4,
      "name": "MESSAGING",
      "description": "Send/receive messages"
    },
    {
      "id": 5,
      "name": "ATTESTATION",
      "description": "Evidence attestation"
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
      "description": "Data controls"
    },
    {
      "id": 9,
      "name": "SCHEMA_SIGNING",
      "description": "Schema signing"
    },
    {
      "id": 10,
      "name": "METERING",
      "description": "Usage metering"
    }
  ],
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
  ]
}

```
