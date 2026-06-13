---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/vectors/vectors.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.998684+00:00
---

# core/cell-engine/tests/vectors/vectors.json

```json
{
  "vectors": [
    {
      "name": "single_cell_linear",
      "description": "LINEAR object, 32-byte payload, minimal",
      "linearity": 1,
      "phase": 1,
      "dimension": 1,
      "payloadSize": 32,
      "timestamp": "1700000000000",
      "typeHash": "2b8a61188311fa557346b43eaaea8fbe4b0f79404e8ea6f12a2ac008a4444761",
      "ownerId": "0123456789abcdef0000000000000000",
      "parentHash": null,
      "prevStateHash": null,
      "cellCount": 1,
      "fileSize": 1024
    },
    {
      "name": "single_cell_affine",
      "description": "AFFINE object, full 768-byte payload",
      "linearity": 2,
      "phase": 2,
      "dimension": 0,
      "payloadSize": 768,
      "timestamp": "1700000000000",
      "typeHash": "2b8a61188311fa557346b43eaaea8fbe4b0f79404e8ea6f12a2ac008a4444761",
      "ownerId": "0123456789abcdef0000000000000000",
      "parentHash": null,
      "prevStateHash": null,
      "cellCount": 1,
      "fileSize": 1024
    },
    {
      "name": "single_cell_relevant",
      "description": "RELEVANT object with commerce extension populated",
      "linearity": 3,
      "phase": 5,
      "dimension": 3,
      "payloadSize": 256,
      "timestamp": "1700000000000",
      "typeHash": "2b8a61188311fa557346b43eaaea8fbe4b0f79404e8ea6f12a2ac008a4444761",
      "ownerId": "0123456789abcdef0000000000000000",
      "parentHash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "prevStateHash": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "cellCount": 1,
      "fileSize": 1024
    },
    {
      "name": "multi_cell_3",
      "description": "3-cell object with BUMP and DATA continuations",
      "linearity": 1,
      "phase": 6,
      "dimension": 2,
      "payloadSize": 512,
      "timestamp": "1700000000000",
      "typeHash": "2b8a61188311fa557346b43eaaea8fbe4b0f79404e8ea6f12a2ac008a4444761",
      "ownerId": "0123456789abcdef0000000000000000",
      "parentHash": null,
      "prevStateHash": null,
      "cellCount": 3,
      "fileSize": 3072
    }
  ],
  "phaseNames": [
    "source",
    "parse",
    "ast",
    "typecheck",
    "optimise",
    "codegen",
    "action",
    "outcome",
    "unknown"
  ],
  "fixedTimestamp": "1700000000000"
}
```
