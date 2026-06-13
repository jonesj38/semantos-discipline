---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.796531+00:00
---

# core/protocol-types/package.json

```json
{
  "name": "@semantos/protocol-types",
  "version": "0.6.0",
  "type": "module",
  "description": "Shared types and constants for the Semantos Cell Engine — bridge over @semantos/core",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "core/protocol-types"
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
    "./browser": {
      "bun": "./src/browser.ts",
      "types": "./dist/browser.d.ts",
      "import": "./dist/browser.js",
      "default": "./dist/browser.js"
    },
    "./network": {
      "bun": "./src/network.ts",
      "types": "./dist/network.d.ts",
      "import": "./dist/network.js",
      "default": "./dist/network.js"
    },
    "./cell-token": {
      "bun": "./src/cell-token.ts",
      "types": "./dist/cell-token.d.ts",
      "import": "./dist/cell-token.js",
      "default": "./dist/cell-token.js"
    },
    "./bsv/access-grant": {
      "bun": "./src/bsv/access-grant.ts",
      "types": "./dist/bsv/access-grant.d.ts",
      "import": "./dist/bsv/access-grant.js",
      "default": "./dist/bsv/access-grant.js"
    },
    "./signed-bundle": {
      "bun": "./src/signed-bundle/index.ts",
      "types": "./dist/signed-bundle/index.d.ts",
      "import": "./dist/signed-bundle/index.js",
      "default": "./dist/signed-bundle/index.js"
    },
    "./field-tree": {
      "bun": "./src/field-tree/index.ts",
      "types": "./dist/field-tree/index.d.ts",
      "import": "./dist/field-tree/index.js",
      "default": "./dist/field-tree/index.js"
    },
    "./disclosure": {
      "bun": "./src/disclosure/index.ts",
      "types": "./dist/disclosure/index.d.ts",
      "import": "./dist/disclosure/index.js",
      "default": "./dist/disclosure/index.js"
    },
    "./xmpp": {
      "bun": "./src/xmpp/index.ts",
      "types": "./dist/xmpp/index.d.ts",
      "import": "./dist/xmpp/index.js",
      "default": "./dist/xmpp/index.js"
    },
    "./license": {
      "bun": "./src/license.ts",
      "types": "./dist/license.d.ts",
      "import": "./dist/license.js",
      "default": "./dist/license.js"
    },
    "./adapters/node-fs-adapter": {
      "bun": "./src/adapters/node-fs-adapter.ts",
      "types": "./dist/adapters/node-fs-adapter.d.ts",
      "import": "./dist/adapters/node-fs-adapter.js",
      "default": "./dist/adapters/node-fs-adapter.js"
    },
    "./adapters/udp-transport": {
      "bun": "./src/adapters/udp-transport.ts",
      "types": "./dist/adapters/udp-transport.d.ts",
      "import": "./dist/adapters/udp-transport.js",
      "default": "./dist/adapters/udp-transport.js"
    },
    "./ports": {
      "bun": "./src/ports/index.ts",
      "types": "./dist/ports/index.d.ts",
      "import": "./dist/ports/index.js",
      "default": "./dist/ports/index.js"
    },
    "./bca": {
      "bun": "./src/bca.ts",
      "types": "./dist/bca.d.ts",
      "import": "./dist/bca.js",
      "default": "./dist/bca.js"
    },
    "./identity": {
      "bun": "./src/identity.ts",
      "types": "./dist/identity.d.ts",
      "import": "./dist/identity.js",
      "default": "./dist/identity.js"
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
    "test": "bun test src/cell-store/__tests__ src/semantic-fs/__tests__ src/wallet-client/__tests__ src/identity-adapters/local/__tests__"
  },
  "dependencies": {
    "@bsv/sdk": "^2.0.0",
    "@semantos/cell-ops": "workspace:*",
    "@semantos/core": "file:../..",
    "@semantos/state": "workspace:*",
    "cbor-x": "^1.6.0"
  },
  "devDependencies": {
    "@semantos/plexus-schema-registry": "workspace:*",
    "bun-types": "^1.3.13",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
