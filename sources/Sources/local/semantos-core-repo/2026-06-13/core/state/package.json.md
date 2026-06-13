---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/state/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.809601+00:00
---

# core/state/package.json

```json
{
  "name": "@semantos/state",
  "version": "0.1.0",
  "type": "module",
  "private": true,
  "description": "Shared atomic-state primitives: atom, derived, effect, port, registry, eventBus, slice.",
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "core/state"
  },
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "bun": "./src/index.ts",
      "types": "./dist/index.d.ts",
      "import": "./dist/index.js",
      "default": "./dist/index.js"
    }
  },
  "files": [
    "dist",
    "src",
    "README.md"
  ],
  "scripts": {
    "build": "tsc -p tsconfig.build.json",
    "check": "tsc --noEmit",
    "clean": "rm -rf dist",
    "test": "bun test src/__tests__"
  },
  "devDependencies": {
    "bun-types": "^1.3.13",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
