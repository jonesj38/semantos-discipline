---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.025672+00:00
---

# runtime/services/package.json

```json
{
  "name": "@semantos/runtime-services",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "description": "Renderer-agnostic stores and services for Semantos. Extracted from @semantos/loom so that React-, Svelte-, and headless consumers can share one source of truth.",
  "main": "src/index.ts",
  "exports": {
    ".": {
      "bun": "./src/index.ts",
      "import": "./src/index.ts",
      "default": "./src/index.ts"
    },
    "./types": {
      "bun": "./src/types/loom.ts",
      "import": "./src/types/loom.ts",
      "default": "./src/types/loom.ts"
    },
    "./config": {
      "bun": "./src/config/extensionConfig.ts",
      "import": "./src/config/extensionConfig.ts",
      "default": "./src/config/extensionConfig.ts"
    },
    "./config/verticalConfig": {
      "bun": "./src/config/verticalConfig.js",
      "import": "./src/config/verticalConfig.js",
      "default": "./src/config/verticalConfig.js"
    },
    "./services/*": {
      "bun": "./src/services/*",
      "import": "./src/services/*",
      "default": "./src/services/*"
    },
    "./state/*": {
      "bun": "./src/state/*",
      "import": "./src/state/*",
      "default": "./src/state/*"
    },
    "./plexus/*": {
      "bun": "./src/plexus/*",
      "import": "./src/plexus/*",
      "default": "./src/plexus/*"
    },
    "./host-exec-registry": {
      "bun": "./src/host-exec-registry.ts",
      "import": "./src/host-exec-registry.ts",
      "default": "./src/host-exec-registry.ts"
    },
    "./host-exec-types": {
      "bun": "./src/host-exec-types.ts",
      "import": "./src/host-exec-types.ts",
      "default": "./src/host-exec-types.ts"
    },
    "./verb-registry": {
      "bun": "./src/verb-registry.ts",
      "import": "./src/verb-registry.ts",
      "default": "./src/verb-registry.ts"
    },
    "./*": {
      "bun": "./src/*",
      "import": "./src/*",
      "default": "./src/*"
    }
  },
  "scripts": {
    "check": "tsc --noEmit",
    "test": "bun test src/services/loom/__tests__ src/services/intent-classifier/__tests__ src/services/config-store/__tests__ src/services/__tests__"
  },
  "dependencies": {
    "@plexus/contracts": "workspace:*",
    "@plexus/vendor-sdk": "workspace:*",
    "@semantos/protocol-types": "workspace:*",
    "@semantos/semantos-sir": "workspace:*",
    "@semantos/pask": "workspace:*",
    "@semantos/state": "workspace:*"
  },
  "devDependencies": {
    "bun-types": "^1.3.13",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
