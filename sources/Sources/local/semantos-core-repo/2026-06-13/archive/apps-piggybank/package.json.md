---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-piggybank/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.685135+00:00
---

# archive/apps-piggybank/package.json

```json
{
  "name": "@semantos/piggybank",
  "version": "0.1.0",
  "description": "BSV piggy bank protocol: chore/reward system with offline SPV, Plexus identity, and multi-device sync. Shared types for ESP32 firmware, Flutter app, and web dashboard.",
  "main": "src/index.ts",
  "types": "dist/index.d.ts",
  "exports": {
    ".": {
      "bun": "./src/index.ts",
      "import": "./dist/index.js",
      "default": "./dist/index.js"
    },
    "./*": {
      "bun": "./src/*",
      "import": "./dist/*",
      "default": "./dist/*"
    }
  },
  "files": ["dist", "src"],
  "scripts": {
    "build": "tsc",
    "check": "tsc --noEmit"
  },
  "keywords": [
    "piggybank",
    "bsv",
    "chores",
    "rewards",
    "esp32",
    "flutter",
    "offline-spv",
    "plexus"
  ],
  "author": "Todd Price <todd.price.aus@gmail.com>",
  "license": "UNLICENSED",
  "dependencies": {
    "@semantos/core": "file:../../"
  },
  "peerDependencies": {
    "@bsv/sdk": "^2.0.0"
  }
}

```
