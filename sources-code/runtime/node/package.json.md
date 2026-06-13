---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.030057+00:00
---

# runtime/node/package.json

```json
{
  "name": "@semantos/node",
  "version": "0.1.0",
  "description": "Semantos node daemon, admin API, and CLI",
  "type": "module",
  "bin": {
    "semantos": "./src/cli.ts",
    "semantos-node": "./src/daemon.ts"
  },
  "main": "./src/index.ts",
  "types": "./dist/index.d.ts",
  "scripts": {
    "build": "tsc"
  },
  "dependencies": {
    "@semantos/peer-locator": "workspace:*",
    "@semantos/protocol-types": "workspace:*",
    "@semantos/session-protocol": "workspace:*",
    "@semantos/shell": "workspace:*",
    "@semantos/ws-node-adapter": "workspace:*"
  },
  "devDependencies": {
    "typescript": "~5.8.0"
  }
}

```
