---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/crystallization/config.core-only.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.546917+00:00
---

# tools/crystallization/config.core-only.json

```json
{
  "_comment": "Single-repo config for semantos-core. Run from the repo root.",
  "project": "Semantos-Core",
  "epochs": [
    {
      "name": "March-April",
      "path": "../..",
      "dateRange": ["2026-03-27", "2026-04-20"]
    },
    {
      "name": "April-May",
      "path": "../..",
      "dateRange": ["2026-04-21", "2026-05-31"]
    }
  ],
  "vocabularyFile": "vocab/semantos.json",
  "amplificationThreshold": 3,
  "minMentions": 2,
  "burstFactor": 3,
  "paskMinCoocs": 2
}

```
