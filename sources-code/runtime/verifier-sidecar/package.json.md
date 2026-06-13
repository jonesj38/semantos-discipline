---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/verifier-sidecar/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.024845+00:00
---

# runtime/verifier-sidecar/package.json

```json
{
  "name": "@semantos/verifier-sidecar",
  "version": "0.6.0",
  "type": "module",
  "description": "Verifier Sidecar — BRC-100 signature, BRC-52 cert authenticity, identity-binding, and capability UTXO SPV checks at every adapter boundary. Phase 0.5 / D-V1.",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "runtime/verifier-sidecar"
  },
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "bin": {
    "verifier-sidecar": "./dist/server.js"
  },
  "exports": {
    ".": {
      "bun": "./src/index.ts",
      "types": "./dist/index.d.ts",
      "import": "./dist/index.js",
      "default": "./dist/index.js"
    },
    "./types": {
      "bun": "./src/types.ts",
      "types": "./dist/types.d.ts",
      "import": "./dist/types.js",
      "default": "./dist/types.js"
    },
    "./server": {
      "bun": "./src/server.ts",
      "types": "./dist/server.d.ts",
      "import": "./dist/server.js",
      "default": "./dist/server.js"
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
    "start": "bun run src/server.ts",
    "test": "bun test"
  },
  "dependencies": {
    "@plexus/contracts": "workspace:*",
    "@semantos/protocol-types": "workspace:*"
  },
  "peerDependencies": {
    "@bsv/sdk": "^2.0.0"
  },
  "devDependencies": {
    "@bsv/sdk": "^2.0.0",
    "bun-types": "^1.3.13",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
