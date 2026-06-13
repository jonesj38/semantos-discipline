---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/oddjobtodd-legacy/plexus-core/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.976930+00:00
---

# archive/oddjobtodd-legacy/plexus-core/package.json

```json
{
  "name": "@dusk-inc/plexus-core",
  "version": "0.2.0",
  "description": "Plexus semantic layer: type system, compiler, kernel interface, recovery protocol, and metering FSM. Sits on top of @bsv/sdk.",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "files": ["dist", "src"],
  "scripts": {
    "build": "tsc",
    "check": "tsc --noEmit",
    "clean": "rm -rf dist"
  },
  "keywords": [
    "plexus",
    "semantic-objects",
    "linear-types",
    "brc-108",
    "2pda",
    "wasm"
  ],
  "author": "Dusk Inc <questions@dusk-inc.com>",
  "license": "UNLICENSED",
  "peerDependencies": {
    "@bsv/sdk": "^2.0.0"
  },
  "devDependencies": {
    "@bsv/sdk": "^2.0.0",
    "typescript": "^5.4.0"
  }
}

```
