---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.386449+00:00
---

# packages/games/package.json

```json
{
  "name": "@semantos/games",
  "version": "0.0.1",
  "private": true,
  "type": "module",
  "main": "src/index.ts",
  "types": "src/index.ts",
  "exports": {
    ".": "./src/index.ts",
    "./cli/game-commands": "./src/cli/game-commands.ts",
    "./shell-handler": "./src/shell-handler.ts"
  },
  "dependencies": {
    "@semantos/game-sdk": "workspace:*",
    "@semantos/cell-engine": "workspace:*",
    "@semantos/policy-runtime": "workspace:*",
    "@semantos/protocol-types": "workspace:*",
    "@semantos/runtime-services": "workspace:*",
    "@semantos/shell": "workspace:*",
    "@semantos/state": "workspace:*",
    "rot-js": "^2.2.0"
  }
}

```
