---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/scg/brain/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.555842+00:00
---

# cartridges/scg/brain/package.json

```json
{
  "name": "@semantos/scg",
  "version": "0.1.0",
  "type": "module",
  "description": "Semantos Conversation Graph extension (RM-021). Declares the SCG grammar + manifest so the cartridge registry can mount SCG-aware conversations alongside other extensions (Oddjobz, future Reddit/Discourse projections). Pairs with @semantos/scg-relations for the actual relation primitives.",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "cartridges/scg/brain"
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
    "@plexus/contracts": "workspace:*",
    "@semantos/experience-cartridge": "workspace:*",
    "@semantos/lexicon-core": "workspace:*",
    "@semantos/scg-relations": "workspace:*"
  },
  "devDependencies": {
    "bun-types": "^1.3.13",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
