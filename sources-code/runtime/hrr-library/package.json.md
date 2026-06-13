---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/hrr-library/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.028959+00:00
---

# runtime/hrr-library/package.json

```json
{
  "name": "@semantos/hrr-library",
  "version": "0.1.0",
  "type": "module",
  "description": "In-memory HRR vector library indexed per (domain_flag, jural_category), populated from NATS stable_transition + intent_outcome events",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "runtime/hrr-library"
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
    "@semantos/hrr": "workspace:*",
    "@semantos/semantos-ir": "workspace:*"
  },
  "devDependencies": {
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
