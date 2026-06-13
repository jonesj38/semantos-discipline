---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/crystallization/config.example.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.545017+00:00
---

# tools/crystallization/config.example.json

```json
{
  "_comment": "Example config for full Semantos multi-epoch analysis. Requires both repos checked out.",
  "project": "Semantos",
  "epochs": [
    {
      "name": "Genesis",
      "path": "/path/to/semantos",
      "dateRange": ["2023-01-01", "2023-12-31"]
    },
    {
      "name": "Overlay",
      "path": "/path/to/semantos",
      "dateRange": ["2024-01-01", "2024-06-30"]
    },
    {
      "name": "Cognition",
      "path": "/path/to/semantos",
      "dateRange": ["2024-07-01", "2024-12-31"]
    },
    {
      "name": "Core",
      "path": "/path/to/semantos-core"
    }
  ],
  "vocabularyFile": "vocab/semantos.json",
  "amplificationThreshold": 10,
  "minMentions": 3,
  "burstFactor": 3,
  "paskMinCoocs": 3
}

```
