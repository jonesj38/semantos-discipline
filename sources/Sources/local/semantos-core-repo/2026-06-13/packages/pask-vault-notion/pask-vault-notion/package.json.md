---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/pask-vault-notion/pask-vault-notion/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.442194+00:00
---

# packages/pask-vault-notion/pask-vault-notion/package.json

```json
{
  "name": "@semantos/pask-vault-notion",
  "version": "0.1.0",
  "type": "module",
  "private": true,
  "description": "Notion workspace adapter for the Pask constraint graph — DB4 of the Dimensional Second Brain workstream.",
  "main": "src/index.ts",
  "types": "src/index.ts",
  "exports": {
    ".": {
      "bun": "./src/index.ts",
      "types": "./dist/index.d.ts",
      "import": "./dist/index.js",
      "default": "./dist/index.js"
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
    "@semantos/runtime-services": "workspace:*"
  },
  "devDependencies": {
    "bun-types": "^1.3.13",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
