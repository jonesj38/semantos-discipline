---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/crystallization/config.full.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.544507+00:00
---

# tools/crystallization/config.full.json

```json
{
  "project": "Semantos-Full",
  "epochs": [
    {
      "name": "shomee-alpha",
      "path": "/Users/toddprice/projects/shomee-alpha",
      "dateRange": ["2025-04-01", "2025-04-30"],
      "_note": "The original broad platform: wallet, BSV daemon, containers, apps"
    },
    {
      "name": "civ-stack",
      "path": "/Users/toddprice/projects/shomee-alpha/packages",
      "dateRange": ["2025-05-01", "2025-05-27"],
      "_note": "Explosion of the 80-package CIV stack"
    },
    {
      "name": "semantic-seed",
      "path": "/Users/toddprice/projects/shomee-alpha/packages/semantic-seed",
      "_note": "Focused Bitcoin transaction semantics — BRC42, BEEF counterparty, canonical pipeline"
    },
    {
      "name": "semantos",
      "path": "/Users/toddprice/projects/semantos",
      "_note": "Bitcoin Script as Forth semantic OS — Craig Wright macros, linear types, semantic objects"
    },
    {
      "name": "cashlanes",
      "path": "/Users/toddprice/projects/cashlanes",
      "_note": "Payment channel tributary — BRC-100, FSM, VPP/IXP metering, 2-of-2 multisig"
    },
    {
      "name": "semantos-core",
      "path": "/Users/toddprice/projects/semantos-core",
      "_note": "Cognition layer — Pask, HRR, intent reducer, conversation payments"
    }
  ],
  "vocabularyFile": "vocab/semantos.json",
  "amplificationThreshold": 5,
  "minMentions": 3,
  "burstFactor": 3,
  "paskMinCoocs": 3
}

```
