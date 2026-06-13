---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-world-sdk/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.683559+00:00
---

# archive/packages-world-sdk/package.json

```json
{
  "name": "@semantos/world-sdk",
  "version": "0.6.0",
  "private": true,
  "type": "module",
  "description": "Protocol types, relay client, and cell DAG for Semantos world applications. Framework-agnostic; works in browsers and Node.",
  "exports": {
    ".": {
      "bun": "./src/index.ts",
      "types": "./dist/index.d.ts",
      "import": "./dist/index.js"
    },
    "./world-types": {
      "bun": "./src/world-types.ts",
      "types": "./dist/world-types.d.ts",
      "import": "./dist/world-types.js"
    },
    "./signed-bundle": {
      "bun": "./src/signed-bundle.ts",
      "types": "./dist/signed-bundle.d.ts",
      "import": "./dist/signed-bundle.js"
    },
    "./relay": {
      "bun": "./src/relay/index.ts",
      "types": "./dist/relay/index.d.ts",
      "import": "./dist/relay/index.js"
    },
    "./dag": {
      "bun": "./src/dag/index.ts",
      "types": "./dist/dag/index.d.ts",
      "import": "./dist/dag/index.js"
    }
  },
  "scripts": {
    "build": "tsc",
    "check": "tsc --noEmit"
  },
  "dependencies": {
    "@bsv/sdk": "^2.0.13",
    "@semantos/protocol-types": "workspace:*"
  },
  "devDependencies": {
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
