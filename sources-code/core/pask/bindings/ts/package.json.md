---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/bindings/ts/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.933308+00:00
---

# core/pask/bindings/ts/package.json

```json
{
  "name": "@semantos/pask",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "description": "TS bindings for the Pask WASM kernel — Paskian learning over the cell graph.",
  "main": "src/index.ts",
  "types": "src/index.ts",
  "exports": {
    ".": "./src/index.ts",
    "./adapter": "./src/adapter.ts",
    "./loader": "./src/loader.ts"
  },
  "scripts": {
    "build": "tsc",
    "check": "tsc --noEmit"
  },
  "files": [
    "src",
    "../../zig-out/bin/pask.wasm",
    "../../zig-out/bin/pask-wasi.wasm"
  ],
  "license": "UNLICENSED"
}

```
