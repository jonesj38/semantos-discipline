---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.642202+00:00
---

# cartridges/wallet-headers/brain/package.json

```json
{
  "name": "@semantos/wallet-browser",
  "version": "0.1.0",
  "private": true,
  "description": "Semantos wallet — vanilla browser bundle (W5). Hidden iframe at wallet.semantos.{tld}/bridge + popup for UI prompts; speaks BRC-100 over postMessage.",
  "type": "module",
  "scripts": {
    "build:wasm": "cd ../../../core/cell-engine && zig build -Dembedded=true && mkdir -p ../../cartridges/wallet-headers/brain/dist && cp zig-out/bin/cell-engine-embedded.wasm ../../cartridges/wallet-headers/brain/dist/ && cp zig-out/bin/cell-engine-embedded.wasm ../../cartridges/wallet-headers/brain/dist/wallet-engine.wasm",
    "build:bridge": "bun build src/bridge.ts --outfile dist/wallet-bridge.js --target=browser --minify --format=esm",
    "build:popup": "bun build src/popup.ts --outfile dist/wallet-popup.js --target=browser --minify --format=esm",
    "build:page": "bun build src/wallet-page.ts --outfile dist/wallet-page.js --target=browser --minify --format=esm",
    "build:html": "bun run scripts/copy-html.ts",
    "build": "bun run build:wasm && bun run build:bridge && bun run build:popup && bun run build:page && bun run build:html",
    "test": "bun test"
  },
  "dependencies": {
    "@noble/hashes": "^1.7.1",
    "@noble/secp256k1": "^2.2.3"
  },
  "devDependencies": {
    "bun-types": "^1.3.13",
    "fake-indexeddb": "^6.0.0",
    "typescript": "~5.8.0"
  }
}

```
