---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/lexicon-core/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.793515+00:00
---

# core/lexicon-core/package.json

```json
{
  "name": "@semantos/lexicon-core",
  "version": "0.1.0",
  "type": "module",
  "description": "Foundational Lexicon interface + runtime injectivity verifier. Zero runtime dependencies. Lifted out of @semantos/semantos-sir so downstream lexicon authors (scg-relations, future domains) can depend on the interface without dragging in the SIR lowering stack.",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "core/lexicon-core"
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
    "bun-types": "^1.3.13",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
