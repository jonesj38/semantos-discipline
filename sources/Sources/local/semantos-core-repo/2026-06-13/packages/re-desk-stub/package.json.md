---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/re-desk-stub/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.394326+00:00
---

# packages/re-desk-stub/package.json

```json
{
  "name": "@semantos/re-desk-stub",
  "version": "0.1.0",
  "type": "module",
  "description": "Stub property-management vertical extension. Single MaintenanceRequest cell type, single capability, single state machine — minimal scaffolding sufficient to validate the chapter-29 federation primitive (cross-vertical dispatch envelope) end-to-end with the full oddjobz extension. Ships D-O11 phase O11a per ODDJOBZ-EXTENSION-PLAN.md §3 phase O11.",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "packages/re-desk-stub"
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
    "@semantos/oddjobz": "workspace:*"
  },
  "devDependencies": {
    "bun-types": "^1.3.13",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
