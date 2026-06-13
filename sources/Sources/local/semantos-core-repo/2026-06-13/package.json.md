---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.310231+00:00
---

# package.json

```json
{
  "name": "@semantos/core",
  "version": "0.6.0",
  "description": "Semantos core: semantic object type system, compiler, kernel WASM interface, recovery protocol, metering FSM, and capability tokens. Sits on top of @bsv/sdk.",
  "engines": {
    "node": ">=18.0.0"
  },
  "packageManager": "pnpm@10.9.0",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com",
    "access": "restricted"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/semantos/semantos-core.git"
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
    "build": "tsc",
    "check": "tsc --noEmit",
    "clean": "rm -rf dist",
    "generate-constants": "bun core/constants/generate.ts",
    "gate": "cd tests/gates && bun test ./phase0-gate.test.ts",
    "test:cards": "bun test scripts/lib/__tests__/",
    "build:bridge": "bun build apps/navigation_app/bsv-app/kernel-bridge.ts --outfile apps/navigation_app/bsv-app/kernel-bridge.js --target=browser --minify",
    "gate:architecture": "cd tests/gates && bun test ./import-boundaries.test.ts",
    "onboard:check": "bun run gate && bun run gate:architecture",
    "swarm:demo": "bun run runtime/session-protocol/src/swarm/demo/paid-swarm-demo.ts",
    "swarm:test": "bun test core/protocol-types/__tests__/swarm-manifest.test.ts runtime/session-protocol/src/swarm/__tests__/"
  },
  "keywords": [
    "semantos",
    "semantic-objects",
    "linear-types",
    "brc-108",
    "2pda",
    "wasm",
    "plexus"
  ],
  "author": "Todd Price <todd.price.aus@gmail.com>",
  "license": "UNLICENSED",
  "workspaces": [
    "core/*",
    "core/pask/bindings/ts",
    "runtime/*",
    "extensions/*",
    "cartridges/*/brain",
    "cartridges/*/web",
    "apps/*",
    "archive/*",
    "packages/*"
  ],
  "peerDependencies": {
    "@bsv/sdk": "^2.0.0"
  },
  "devDependencies": {
    "@bsv/sdk": "^2.0.0",
    "@changesets/changelog-github": "^0.6.0",
    "@changesets/cli": "^2.31.0",
    "@types/node": "^20.0.0",
    "glob": "^13.0.6",
    "ts-morph": "^28.0.0",
    "typescript": "~5.8.0"
  },
  "dependencies": {
    "@anthropic-ai/sdk": "^0.99.0",
    "geotiff": "^3.0.5",
    "yaml": "^2.9.0"
  }
}

```
