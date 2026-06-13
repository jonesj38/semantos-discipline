---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.684132+00:00
---

# archive/apps-settlement/package.json

```json
{
  "name": "@semantos/settlement",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "description": "BSV settlement layer: border-router aggregation, CBOR encoding, Merkle batching, and WebSocket relay",
  "main": "src/index.ts",
  "types": "src/index.ts",
  "scripts": {
    "build": "tsc",
    "check": "tsc --noEmit",
    "test": "bun test",
    "start:border-router": "bun run src/border-router.ts"
  },
  "dependencies": {
    "@semantos/cell-ops": "workspace:*",
    "@semantos/protocol-types": "workspace:*",
    "@semantos/game-sdk": "workspace:*",
    "@semantos/poker-agent": "workspace:*",
    "express": "^4.18.0",
    "cors": "^2.8.5",
    "ws": "^8.16.0",
    "cbor-x": "^1.5.0"
  },
  "devDependencies": {
    "@types/express": "^4.17.0",
    "@types/cors": "^2.8.0",
    "@types/ws": "^8.5.0"
  },
  "license": "UNLICENSED"
}

```
