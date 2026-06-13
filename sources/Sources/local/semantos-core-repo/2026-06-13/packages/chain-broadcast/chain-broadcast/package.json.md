---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/chain-broadcast/chain-broadcast/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.518577+00:00
---

# packages/chain-broadcast/chain-broadcast/package.json

```json
{
  "name": "@semantos/chain-broadcast",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "description": "On-chain anchoring services: cell → BSV transaction, MAPI/ARC broadcast, BEEF store, chain-tip parent dedup. Reusable by any extension/app that needs to push cells to BSV at bulk.",
  "main": "src/index.ts",
  "exports": {
    ".": {
      "bun": "./src/index.ts",
      "import": "./src/index.ts",
      "default": "./src/index.ts"
    },
    "./beef-store": {
      "bun": "./src/beef-store.ts",
      "import": "./src/beef-store.ts",
      "default": "./src/beef-store.ts"
    },
    "./cell-tx-builder": {
      "bun": "./src/cell-tx-builder.ts",
      "import": "./src/cell-tx-builder.ts",
      "default": "./src/cell-tx-builder.ts"
    },
    "./mapi-broadcaster": {
      "bun": "./src/mapi-broadcaster.ts",
      "import": "./src/mapi-broadcaster.ts",
      "default": "./src/mapi-broadcaster.ts"
    },
    "./chain-tip-manager": {
      "bun": "./src/chain-tip-manager.ts",
      "import": "./src/chain-tip-manager.ts",
      "default": "./src/chain-tip-manager.ts"
    }
  },
  "scripts": {
    "check": "tsc --noEmit",
    "test": "bun test"
  },
  "dependencies": {
    "@semantos/protocol-types": "workspace:*",
    "@semantos/session-protocol": "workspace:*"
  },
  "peerDependencies": {
    "@bsv/sdk": "^2.0.0"
  },
  "devDependencies": {
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
