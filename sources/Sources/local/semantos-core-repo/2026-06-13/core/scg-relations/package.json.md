---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/scg-relations/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.792715+00:00
---

# core/scg-relations/package.json

```json
{
  "name": "@semantos/scg-relations",
  "version": "0.1.0",
  "type": "module",
  "description": "Semantos Conversation Graph (SCG) — typed relations on the sem_objects substrate. Phase 1 bolt-on: relations are sem_objects rows of objectKind='scg.relation', no schema migration.",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "core/scg-relations"
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
    "@semantos/identity-ports": "workspace:*",
    "@semantos/lexicon-core": "workspace:*",
    "@semantos/semantic-objects": "workspace:*",
    "drizzle-orm": "^0.33.0"
  },
  "devDependencies": {
    "@electric-sql/pglite": "^0.4.1",
    "bun-types": "^1.3.13",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
