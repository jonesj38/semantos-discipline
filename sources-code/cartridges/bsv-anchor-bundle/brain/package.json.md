---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.442217+00:00
---

# cartridges/bsv-anchor-bundle/brain/package.json

```json
{
  "name": "@semantos/bsv-anchor-bundle",
  "version": "0.0.1",
  "type": "module",
  "description": "BSV anchor backend cartridge. Implements the Phase 26C AnchorAdapter interface using BSV as the timestamping + verification chain. Bundles wallet (BRC-42 + signing), payment policy, refund tx, and SPV header sync. Default substrate-exposing cartridge in the sovereign-BSV-node distro variant.",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "cartridges/bsv-anchor-bundle/brain"
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
    },
    "./idempotent-batch-anchorer": {
      "bun": "./src/idempotent-batch-anchorer.ts",
      "default": "./src/idempotent-batch-anchorer.ts"
    },
    "./anchor-history-chain": {
      "bun": "./src/anchor-history-chain.ts",
      "default": "./src/anchor-history-chain.ts"
    }
  },
  "dependencies": {
    "@semantos/anchor-attestation": "workspace:*",
    "@semantos/protocol-types": "workspace:*",
    "@plexus/vendor-sdk": "workspace:*"
  },
  "devDependencies": {
    "@bsv/sdk": "^1.7.6"
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
