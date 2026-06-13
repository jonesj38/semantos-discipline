---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-ir/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.806915+00:00
---

# core/semantos-ir/package.json

```json
{
  "name": "@semantos/semantos-ir",
  "version": "0.6.0",
  "type": "module",
  "description": "ANF intermediate representation for the cell engine constraint compiler — nanopass lower + emit pipeline",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "core/semantos-ir"
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
    "./expr": {
      "bun": "./src/expr.ts",
      "types": "./dist/expr.d.ts",
      "import": "./dist/expr.js",
      "default": "./dist/expr.js"
    },
    "./types": {
      "bun": "./src/types.ts",
      "types": "./dist/types.d.ts",
      "import": "./dist/types.js",
      "default": "./dist/types.js"
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
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
