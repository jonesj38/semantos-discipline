---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.389436+00:00
---

# packages/extraction/package.json

```json
{
  "name": "@semantos/extraction",
  "version": "0.1.0",
  "description": "Semantic extraction pipeline: fetch, parse, typecheck, infer, commit",
  "type": "module",
  "main": "./src/index.ts",
  "types": "./src/index.ts",
  "exports": {
    ".": {
      "bun": "./src/index.ts",
      "import": "./dist/index.js",
      "default": "./dist/index.js"
    },
    "./shell-handler": {
      "bun": "./src/shell-handler.ts",
      "import": "./dist/shell-handler.js",
      "default": "./dist/shell-handler.js"
    },
    "./intent-adapters": {
      "bun": "./src/intent-adapters/index.ts",
      "import": "./dist/intent-adapters/index.js",
      "default": "./dist/intent-adapters/index.js"
    }
  },
  "scripts": {
    "build": "tsc",
    "test": "bun test",
    "auto-grammar": "bun run bin/auto-grammar.ts"
  },
  "dependencies": {
    "@anthropic-ai/sdk": "^0.37.0",
    "@semantos/intent": "workspace:*",
    "@semantos/protocol-types": "workspace:*",
    "@semantos/runtime-services": "workspace:*",
    "@semantos/semantos-sir": "workspace:*",
    "@semantos/shell": "workspace:*"
  },
  "devDependencies": {
    "typescript": "^5.3.3"
  }
}

```
