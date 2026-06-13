---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/conversation-graph/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.807743+00:00
---

# core/conversation-graph/package.json

```json
{
  "name": "@semantos/conversation-graph",
  "version": "0.1.0",
  "type": "module",
  "description": "Conversation-graph substrate (SCG Phase 1 / RM-031). Generic turn / hook interfaces + auto-emission of REPLIES_TO relations when a turn quotes a prior turn. Extensions consume these types from their domain-specific conversation pipelines (e.g. oddjobz's chat-service).",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "core/conversation-graph"
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
    "@semantos/scg-relations": "workspace:*",
    "@semantos/semantic-objects": "workspace:*",
    "drizzle-orm": "^0.33.0"
  },
  "devDependencies": {
    "@electric-sql/pglite": "^0.4.1",
    "@semantos/intent": "workspace:*",
    "@semantos/semantos-ir": "workspace:*",
    "@semantos/semantos-sir": "workspace:*",
    "bun-types": "^1.3.13",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
