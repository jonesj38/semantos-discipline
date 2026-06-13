---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/anchor-attestation/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.800096+00:00
---

# core/anchor-attestation/package.json

```json
{
  "name": "@semantos/anchor-attestation",
  "version": "0.1.0",
  "type": "module",
  "description": "Anchor-attestation cell type (Phase H RM-042). Anchoring a cell on-chain produces an AnchorAttestation cell whose payload binds (targetCellId, txid, anchorHeight, vout, derivationIndex) via anchorAttestationSchemaV2 at Plexus. Replaces the OnChainBinding header region.",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "core/anchor-attestation"
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
    "./audit-chain": {
      "bun": "./src/audit-chain/index.ts",
      "types": "./dist/audit-chain/index.d.ts",
      "import": "./dist/audit-chain/index.js",
      "default": "./dist/audit-chain/index.js"
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
    "@semantos/plexus-schema-registry": "workspace:*",
    "@plexus/vendor-sdk": "workspace:*"
  },
  "devDependencies": {
    "@bsv/sdk": "^1.7.6",
    "bun-types": "^1.3.13",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
