---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/consciousness/consciousness/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.720763+00:00
---

# archive/consciousness/consciousness/package.json

```json
{
  "name": "@semantos/consciousness",
  "version": "0.1.0",
  "description": "Consciousness Process — self-improvement extension for Semantos. Models the self as a semantic object undergoing release/receive cycles.",
  "type": "module",
  "main": "src/index.ts",
  "types": "src/index.ts",
  "exports": {
    ".": "./src/index.ts",
    "./types": "./src/types/consciousness-objects.ts",
    "./tower": "./src/tower-data.ts",
    "./extraction": "./src/extraction.ts"
  },
  "dependencies": {
    "@semantos/core": "file:../../",
    "@semantos/navigator": "workspace:*"
  },
  "scripts": {
    "check": "tsc --noEmit",
    "test": "bun test"
  }
}

```
