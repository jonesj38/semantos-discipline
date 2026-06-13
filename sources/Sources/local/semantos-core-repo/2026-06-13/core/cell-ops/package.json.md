---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.795687+00:00
---

# core/cell-ops/package.json

```json
{
  "name": "@semantos/cell-ops",
  "version": "0.6.0",
  "type": "module",
  "description": "TypeScript cell operations: type hash registry, cell packing, merkle envelopes, opcodes, WASM binding interface",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "core/cell-ops"
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
    "./packer": {
      "bun": "./src/packer/index.ts",
      "types": "./dist/packer/index.d.ts",
      "import": "./dist/packer/index.js",
      "default": "./dist/packer/index.js"
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
  "devDependencies": {
    "@semantos/plexus-schema-registry": "workspace:*",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
