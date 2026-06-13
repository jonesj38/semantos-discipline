---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cell-relay/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.387314+00:00
---

# packages/cell-relay/package.json

```json
{
  "name": "@semantos/cell-relay",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "description": "Wire-protocol types + client SDK for the per-room append-only signed-cell relay (cell-relay-beam, demo-collab-versioning).",
  "main": "src/index.ts",
  "types": "src/index.ts",
  "exports": {
    ".": "./src/index.ts",
    "./client": "./src/client.ts",
    "./jsonl": "./src/jsonl.ts",
    "./cell": "./src/cell.ts",
    "./types": "./src/types.ts"
  },
  "scripts": {
    "check": "tsc --noEmit",
    "build": "tsc"
  },
  "license": "UNLICENSED"
}

```
