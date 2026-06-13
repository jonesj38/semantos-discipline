---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/navigator/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.387865+00:00
---

# packages/navigator/package.json

```json
{
  "name": "@semantos/navigator",
  "version": "0.1.0",
  "description": "Navigator — core navigation layer for Semantos. Renders any extension's types through tower model, elevation tracking, and consumer binding.",
  "type": "module",
  "main": "src/index.ts",
  "types": "src/index.ts",
  "exports": {
    ".": "./src/index.ts",
    "./types": "./src/types/navigator-types.ts"
  },
  "dependencies": {
    "@semantos/core": "file:../../"
  },
  "scripts": {
    "check": "tsc --noEmit",
    "test": "bun test"
  }
}

```
