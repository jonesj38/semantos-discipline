---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/identity-ports/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.801142+00:00
---

# core/identity-ports/package.json

```json
{
  "name": "@semantos/identity-ports",
  "version": "0.1.0",
  "type": "module",
  "private": true,
  "description": "Application-facing port surface for Plexus identity, recovery, attestation, and capability services. Stub binding for tests/demos; vendor-sdk binding wraps @plexus/vendor-sdk for production.",
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "core/identity-ports"
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
    },
    "./vendor-sdk": {
      "bun": "./src/vendor-sdk-binding.ts",
      "types": "./dist/vendor-sdk-binding.d.ts",
      "import": "./dist/vendor-sdk-binding.js",
      "default": "./dist/vendor-sdk-binding.js"
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
    "@plexus/contracts": "workspace:*",
    "@plexus/vendor-sdk": "workspace:*",
    "@semantos/state": "workspace:*"
  },
  "devDependencies": {
    "bun-types": "^1.3.13",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
