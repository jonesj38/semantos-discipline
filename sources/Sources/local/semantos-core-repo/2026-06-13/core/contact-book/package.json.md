---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/contact-book/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.801938+00:00
---

# core/contact-book/package.json

```json
{
  "name": "@semantos/contact-book",
  "version": "0.1.0",
  "type": "module",
  "private": true,
  "description": "Contacts book for Semantos — maps human-readable identities (name/email) to BRC-52 cert IDs, backed by StorageAdapter with DAG discovery via identityPort and ECDH edge establishment.",
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "core/contact-book"
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
    "./stub": {
      "bun": "./src/stub-binding.ts",
      "types": "./dist/stub-binding.d.ts",
      "import": "./dist/stub-binding.js",
      "default": "./dist/stub-binding.js"
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
    "test": "bun test src/__tests__"
  },
  "dependencies": {
    "@semantos/identity-ports": "workspace:*",
    "@semantos/protocol-types": "workspace:*",
    "@semantos/state": "workspace:*"
  },
  "devDependencies": {
    "bun-types": "^1.3.13",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
