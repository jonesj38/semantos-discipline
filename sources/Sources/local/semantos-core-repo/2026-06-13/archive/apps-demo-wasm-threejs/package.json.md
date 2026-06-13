---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-demo-wasm-threejs/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.687674+00:00
---

# archive/apps-demo-wasm-threejs/package.json

```json
{
  "name": "@semantos/demo-wasm-threejs",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "description": "Three.js scene driven by Semantos cells. Each rendered object is backed by a 2-PDA script executed in the WASM kernel.",
  "scripts": {
    "dev": "vite",
    "build": "tsc --noEmit && vite build",
    "preview": "vite preview",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "@semantos/cube-object": "workspace:*",
    "@semantos/identity-ports": "workspace:*",
    "three": "^0.165.0"
  },
  "devDependencies": {
    "@types/three": "^0.165.0",
    "typescript": "~5.8.0",
    "vite": "^5.4.0",
    "vitest": "^1.6.0"
  },
  "license": "UNLICENSED"
}

```
