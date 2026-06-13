---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.453114+00:00
---

# cartridges/oddjobz/brain/package.json

```json
{
  "name": "@semantos/oddjobz",
  "version": "0.1.0",
  "type": "module",
  "description": "Oddjobz cell types + state machines for the trades/services vertical. The 8 typed cells (job, quote, visit, invoice, customer, site, estimate, message) with stable type-hashes, conformance vectors, and linearity flags per ODDJOBZ-EXTENSION-PLAN.md §O2.",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "cartridges/oddjobz/brain"
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
    "./lexicon": {
      "bun": "./src/lexicon.ts",
      "types": "./dist/lexicon.d.ts",
      "import": "./dist/lexicon.js",
      "default": "./dist/lexicon.js"
    },
    "./conversation/legacy-ingest-bridge": {
      "bun": "./src/conversation/legacy-ingest-bridge.ts",
      "types": "./dist/conversation/legacy-ingest-bridge.d.ts",
      "import": "./dist/conversation/legacy-ingest-bridge.js",
      "default": "./dist/conversation/legacy-ingest-bridge.js"
    },
    "./conversation/db": {
      "bun": "./src/conversation/db.ts",
      "types": "./dist/conversation/db.d.ts",
      "import": "./dist/conversation/db.js",
      "default": "./dist/conversation/db.js"
    },
    "./conversation/conversation-turn-patch": {
      "bun": "./src/conversation/conversation-turn-patch.ts",
      "types": "./dist/conversation/conversation-turn-patch.d.ts",
      "import": "./dist/conversation/conversation-turn-patch.js",
      "default": "./dist/conversation/conversation-turn-patch.js"
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
    "test": "bun test",
    "gen:vectors": "bun tools/gen-vectors.ts",
    "gen:cap-vectors": "bun tools/gen-cap-vectors.ts",
    "gen:fsm-vectors": "bun tools/gen-fsm-vectors.ts"
  },
  "dependencies": {
    "@anthropic-ai/sdk": "^0.37.0",
    "@semantos/conversation-graph": "workspace:*",
    "@semantos/intent": "workspace:*",
    "@semantos/legacy-ingest": "workspace:*",
    "@semantos/protocol-types": "workspace:*",
    "@semantos/scg-relations": "workspace:*",
    "@semantos/semantic-objects": "workspace:*",
    "@semantos/semantos-sir": "workspace:*",
    "drizzle-orm": "^0.33.0",
    "postgres": "^3.4.0"
  },
  "devDependencies": {
    "bun-types": "^1.3.13",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
