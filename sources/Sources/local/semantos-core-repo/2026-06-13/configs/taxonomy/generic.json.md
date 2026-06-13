---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/configs/taxonomy/generic.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.379656+00:00
---

# configs/taxonomy/generic.json

```json
{
  "extensionId": "generic",
  "inject": [
    {
      "parentId": "create",
      "nodes": [
        {
          "id": "thing",
          "label": "Create Thing",
          "description": "Generic AFFINE object — a named entity with fields",
          "examples": ["create an object", "make a new thing"]
        },
        {
          "id": "action",
          "label": "Create Action",
          "description": "Generic LINEAR task or process — consumed when completed",
          "examples": ["create a task", "new action"]
        },
        {
          "id": "instrument",
          "label": "Create Instrument",
          "description": "Generic RELEVANT document or contract — immutable reference",
          "examples": ["create a document", "new instrument"]
        }
      ]
    },
    {
      "parentId": "navigate",
      "nodes": [
        {
          "id": "objects",
          "label": "Browse Objects",
          "description": "List all objects in the current workspace",
          "examples": ["show me everything", "list all objects", "what do I have"]
        }
      ]
    },
    {
      "parentId": "query",
      "nodes": [
        {
          "id": "freeform",
          "label": "Freeform Query",
          "description": "Ask any question about the current objects or state",
          "examples": ["what is this", "tell me about", "explain"]
        }
      ]
    },
    {
      "parentId": "inspect",
      "nodes": [
        {
          "id": "evidence",
          "label": "View Evidence Chain",
          "description": "Inspect an object's full patch history and evidence chain",
          "examples": ["show evidence chain", "view audit trail", "show me the history"]
        }
      ]
    }
  ]
}

```
