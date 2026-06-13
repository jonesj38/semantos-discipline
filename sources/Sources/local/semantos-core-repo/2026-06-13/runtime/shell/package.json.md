---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.034014+00:00
---

# runtime/shell/package.json

```json
{
  "name": "@semantos/shell",
  "version": "19.0.0",
  "description": "Semantic shell: typed CLI/REPL for semantic objects",
  "type": "module",
  "bin": {
    "semantos-shell": "./dist/index.js"
  },
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "bun": "./src/index.ts",
      "import": "./dist/index.js",
      "default": "./dist/index.js"
    },
    "./parser": {
      "bun": "./src/parser.ts",
      "import": "./dist/parser.js",
      "default": "./dist/parser.js"
    },
    "./types": {
      "bun": "./src/types.ts",
      "import": "./dist/types.js",
      "default": "./dist/types.js"
    },
    "./error-codes": {
      "bun": "./src/error-codes.ts",
      "import": "./dist/error-codes.js",
      "default": "./dist/error-codes.js"
    }
  },
  "scripts": {
    "build": "tsc",
    "dev": "node --watch dist/index.js",
    "test": "bun test"
  },
  "dependencies": {
    "@semantos/runtime-services": "workspace:*",
    "@semantos/semantos-ir": "workspace:*",
    "@semantos/intent": "workspace:*",
    "@semantos/cell-engine": "workspace:*",
    "@semantos/session-protocol": "workspace:*",
    "@semantos/state": "workspace:*"
  },
  "devDependencies": {
    "bun-types": "^1.3.13",
    "typescript": "^5.3.3"
  }
}

```
