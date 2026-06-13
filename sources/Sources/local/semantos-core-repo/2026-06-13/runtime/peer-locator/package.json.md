---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/peer-locator/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.027063+00:00
---

# runtime/peer-locator/package.json

```json
{
  "name": "@semantos/peer-locator",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "description": "BCA → wss endpoint resolution for Phase 35B federation. DNS-first with cache, plus a static map-backed locator for tests and bootstrapping.",
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
  "dependencies": {},
  "devDependencies": {
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
