---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.393247+00:00
---

# packages/game-sdk/package.json

```json
{
  "name": "@semantos/game-sdk",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "description": "Game engine SDK: entities, inventories, trades, state machines, and policies over the cell engine",
  "main": "src/index.ts",
  "types": "src/index.ts",
  "scripts": {
    "build": "tsc",
    "check": "tsc --noEmit"
  },
  "dependencies": {
    "@semantos/cell-ops": "workspace:*",
    "@semantos/plexus-schema-registry": "workspace:*",
    "@semantos/protocol-types": "workspace:*",
    "@semantos/state": "workspace:*",
    "bitecs": "^0.4.0"
  },
  "license": "UNLICENSED"
}

```
