---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.032573+00:00
---

# runtime/ws-node-adapter/package.json

```json
{
  "name": "@semantos/ws-node-adapter",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "description": "NetworkAdapter over WSS with license-handshake envelope auth — the node-to-node federation layer for Phase 35B.",
  "main": "src/index.ts",
  "exports": {
    ".": {
      "bun": "./src/index.ts",
      "import": "./src/index.ts",
      "default": "./src/index.ts"
    },
    "./*": {
      "bun": "./src/*",
      "import": "./src/*",
      "default": "./src/*"
    }
  },
  "scripts": {
    "check": "tsc --noEmit",
    "test": "bun test"
  },
  "dependencies": {
    "@semantos/peer-locator": "workspace:*",
    "@semantos/protocol-types": "workspace:*",
    "@semantos/session-protocol": "workspace:*",
    "cbor-x": "^1.6.0"
  },
  "devDependencies": {
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
