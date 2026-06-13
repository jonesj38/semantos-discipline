---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/pask-vault-obsidian/pask-vault-obsidian/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.488988+00:00
---

# packages/pask-vault-obsidian/pask-vault-obsidian/package.json

```json
{
  "name": "@semantos/pask-vault-obsidian",
  "version": "0.1.0",
  "type": "module",
  "private": true,
  "description": "Obsidian vault adapter for the Pask constraint graph — DB3 of the Dimensional Second Brain workstream.",
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
    "plugin",
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
