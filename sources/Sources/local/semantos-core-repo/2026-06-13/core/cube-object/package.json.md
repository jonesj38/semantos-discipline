---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cube-object/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.808540+00:00
---

# core/cube-object/package.json

```json
{
  "name": "@semantos/cube-object",
  "version": "0.1.0",
  "type": "module",
  "private": true,
  "description": "The cube as a renderable semantic object — Three.js mesh + linearity-typed surface + identity-port-aware coloring. Shared by apps/demo-wasm-threejs (object demo) and apps/world-client (world demo).",
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git",
    "directory": "core/cube-object"
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
    "./linearity": {
      "bun": "./src/linearity.ts",
      "types": "./dist/linearity.d.ts",
      "import": "./dist/linearity.js",
      "default": "./dist/linearity.js"
    },
    "./mesh": {
      "bun": "./src/cube-mesh.ts",
      "types": "./dist/cube-mesh.d.ts",
      "import": "./dist/cube-mesh.js",
      "default": "./dist/cube-mesh.js"
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
    "test": "bun test src/__tests__"
  },
  "dependencies": {
    "@semantos/identity-ports": "workspace:*",
    "@semantos/state": "workspace:*"
  },
  "peerDependencies": {
    "three": "^0.165.0"
  },
  "devDependencies": {
    "@types/three": "^0.165.0",
    "bun-types": "^1.3.13",
    "three": "^0.165.0",
    "typescript": "~5.8.0"
  },
  "license": "UNLICENSED"
}

```
