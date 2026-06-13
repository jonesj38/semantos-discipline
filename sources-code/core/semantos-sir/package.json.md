---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-sir/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.791901+00:00
---

# core/semantos-sir/package.json

```json
{
  "name": "@semantos/semantos-sir",
  "version": "0.6.0",
  "type": "module",
  "description": "Semantic IR — jural category types and SIR-to-OIR lowering pass with trust-tier enforcement",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "core/semantos-sir"
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
  "dependencies": {
    "@semantos/lexicon-core": "workspace:*",
    "@semantos/scg-relations": "workspace:*",
    "@semantos/semantos-ir": "workspace:*"
  },
  "devDependencies": {
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
