---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.023761+00:00
---

# runtime/session-protocol/package.json

```json
{
  "name": "@semantos/session-protocol",
  "version": "0.6.0",
  "type": "module",
  "description": "Domain-neutral multi-party session protocol: discovery, formation, runtime, broadcast, transport seam, optional metering hook. Consumed by apps (poker-agent, media-protocol) and parameterised by a StateMachine plug-in.",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "runtime/session-protocol"
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
    "./types": {
      "bun": "./src/types.ts",
      "types": "./dist/types.d.ts",
      "import": "./dist/types.js",
      "default": "./dist/types.js"
    },
    "./signer": {
      "bun": "./src/signer.ts",
      "types": "./dist/signer.d.ts",
      "import": "./dist/signer.js",
      "default": "./dist/signer.js"
    },
    "./adapters/*": {
      "bun": "./src/adapters/*",
      "types": "./dist/adapters/*.d.ts",
      "import": "./dist/adapters/*",
      "default": "./dist/adapters/*"
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
    "@semantos/conversation-graph": "workspace:*",
    "@semantos/identity-ports": "workspace:*",
    "@semantos/protocol-types": "workspace:*",
    "werift": "^0.23.0"
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
