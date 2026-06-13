---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.690840+00:00
---

# archive/apps-world-client/package.json

```json
{
  "name": "@semantos/world-client",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "description": "Three.js client for the OTP world-host.",
  "scripts": {
    "dev": "vite",
    "build": "tsc --noEmit && vite build",
    "preview": "vite preview",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "@bsv/sdk": "^2.0.13",
    "@semantos/cube-object": "workspace:*",
    "@semantos/identity-ports": "workspace:*",
    "@semantos/protocol-types": "workspace:*",
    "@semantos/world-sdk": "workspace:*",
    "@sqlite.org/sqlite-wasm": "^3.53.0-build1",
    "phoenix": "^1.7.14",
    "three": "^0.165.0"
  },
  "devDependencies": {
    "@types/phoenix": "^1.6.5",
    "@types/three": "^0.165.0",
    "typescript": "~5.8.0",
    "vite": "^5.4.0",
    "vitest": "^1.6.0"
  },
  "license": "UNLICENSED"
}

```
