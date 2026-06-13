---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.033400+00:00
---

# runtime/intent/package.json

```json
{
  "name": "@semantos/intent",
  "version": "0.6.0",
  "type": "module",
  "description": "Universal intent pipeline — one substrate for NL, voice, shell, UI, governance, and network inputs. Intent → SIR → IR → bytes → cell engine → IntentResult, with correlation-ID observability at every stage boundary.",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "runtime/intent"
  },
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "bun": "./src/index.ts",
      "types": "./dist/index.d.ts",
      "import": "./dist/index.js",
      "default": "./dist/index.js"
    },
    "./types": {
      "bun": "./src/types.ts",
      "types": "./dist/types.d.ts",
      "import": "./dist/types.js",
      "default": "./dist/types.js"
    },
    "./logger": {
      "bun": "./src/logger.ts",
      "types": "./dist/logger.d.ts",
      "import": "./dist/logger.js",
      "default": "./dist/logger.js"
    },
    "./reducer": {
      "bun": "./src/reducer/index.ts",
      "types": "./dist/reducer/index.d.ts",
      "import": "./dist/reducer/index.js",
      "default": "./dist/reducer/index.js"
    },
    "./reducer/types": {
      "bun": "./src/reducer/types.ts",
      "types": "./dist/reducer/types.d.ts",
      "import": "./dist/reducer/types.js",
      "default": "./dist/reducer/types.js"
    },
    "./*": {
      "bun": "./src/*",
      "types": "./dist/*.d.ts",
      "import": "./dist/*",
      "default": "./dist/*"
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
    "test": "bun test"
  },
  "dependencies": {
    "@semantos/scg-relations": "workspace:*",
    "@semantos/semantos-sir": "workspace:*",
    "@semantos/protocol-types": "workspace:*",
    "@semantos/hrr": "workspace:*"
  },
  "devDependencies": {
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
