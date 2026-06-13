---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.493343+00:00
---

# packages/cdm/cdm/package.json

```json
{
  "name": "@semantos/cdm",
  "version": "0.1.0",
  "private": true,
  "description": "ISDA CDM lifecycle engine, regulatory reporting, ISDA policy compilation, and FpML bridge",
  "main": "src/index.ts",
  "types": "src/index.ts",
  "exports": {
    ".": "./src/index.ts",
    "./lifecycle": "./src/lifecycle.ts",
    "./regulatory": "./src/regulatory.ts",
    "./types": "./src/types.ts",
    "./bridge/index": "./src/bridge/index.ts",
    "./shell-handler": "./src/shell-handler.ts"
  },
  "dependencies": {
    "@semantos/core": "file:../../",
    "@semantos/plexus-schema-registry": "workspace:*",
    "@semantos/runtime-services": "workspace:*",
    "@semantos/shell": "workspace:*",
    "@semantos/state": "workspace:*"
  },
  "license": "UNLICENSED"
}

```
