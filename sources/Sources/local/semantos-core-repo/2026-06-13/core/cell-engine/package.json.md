---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.805779+00:00
---

# core/cell-engine/package.json

```json
{
  "name": "@semantos/cell-engine",
  "version": "0.1.0",
  "private": true,
  "description": "Zig/WASM 2-PDA cell engine with TypeScript bindings for Bun and browser",
  "main": "bindings/index.ts",
  "files": [
    "dist",
    "bindings",
    "src"
  ],
  "scripts": {
    "build:wasm": "mkdir -p dist && cp zig-out/bin/cell-engine.wasm dist/cell-engine.wasm && ([ -f zig-out/bin/cell-engine-embedded.wasm ] && cp zig-out/bin/cell-engine-embedded.wasm dist/cell-engine-embedded.wasm || true)"
  },
  "dependencies": {
    "@semantos/cell-ops": "workspace:*",
    "@semantos/core": "file:../../",
    "@semantos/plexus-schema-registry": "workspace:*",
    "@semantos/protocol-types": "workspace:*"
  },
  "devDependencies": {
    "@bsv/sdk": "^2.0.0",
    "typescript": "^5.4.0"
  },
  "license": "UNLICENSED"
}

```
