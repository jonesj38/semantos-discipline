---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.634299+00:00
---

# cartridges/tessera/brain/package.json

```json
{
  "name": "@semantos/tessera",
  "version": "0.0.1",
  "type": "module",
  "description": "Tessera care-chain provenance cartridge. Substrate-consuming cartridge for grape-to-glass-shaped traceability over physically handed-off objects. Consumes the four Phase-26 adapter interfaces (StorageAdapter, IdentityAdapter, AnchorAdapter, NetworkAdapter) and federates SignedBundle<TesseraPatch> via NetworkAdapter.",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "cartridges/tessera/brain"
  },
  "main": "./src/index.ts",
  "types": "./src/index.ts",
  "exports": {
    ".": {
      "bun": "./src/index.ts",
      "default": "./src/index.ts"
    },
    "./capabilities": {
      "bun": "./src/capabilities.ts",
      "default": "./src/capabilities.ts"
    },
    "./manifest": {
      "bun": "./src/manifest.ts",
      "default": "./src/manifest.ts"
    }
  },
  "scripts": {
    "build": "tsc",
    "check": "tsc --noEmit",
    "test": "bun test"
  },
  "files": [
    "src",
    "manifest.json",
    "zig/build.zig",
    "zig/build.zig.zon",
    "zig/src",
    "README.md"
  ],
  "license": "UNLICENSED"
}

```
