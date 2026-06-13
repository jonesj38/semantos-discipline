---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.511207+00:00
---

# packages/dispatch/dispatch/package.json

```json
{
  "name": "@semantos/dispatch",
  "version": "0.1.0",
  "type": "module",
  "description": "Dispatch envelope bridge primitive — the cross-vertical federation seam. Defines the dispatch.envelope.v1, dispatch.accepted.v1, and dispatch.completion.v1 cell types and a transport-agnostic handler that routes envelope payloads to registered receiving extensions. Ships D-O11 phase O11b per ODDJOBZ-EXTENSION-PLAN.md §3 phase O11.",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "packages/dispatch"
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
    "./cell-types": {
      "bun": "./src/cell-types/index.ts",
      "types": "./dist/cell-types/index.d.ts",
      "import": "./dist/cell-types/index.js",
      "default": "./dist/cell-types/index.js"
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
    "tests/vectors",
    "README.md"
  ],
  "scripts": {
    "build": "tsc -p tsconfig.build.json",
    "check": "tsc --noEmit",
    "clean": "rm -rf dist",
    "test": "bun test"
  },
  "dependencies": {
    "@semantos/oddjobz": "workspace:*",
    "@semantos/re-desk-stub": "workspace:*"
  },
  "devDependencies": {
    "bun-types": "^1.3.13",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
