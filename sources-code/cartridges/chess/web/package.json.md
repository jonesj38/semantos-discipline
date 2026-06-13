---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/web/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.426525+00:00
---

# cartridges/chess/web/package.json

```json
{
  "name": "@semantos/world-app-chess-game",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "description": "Chess Game — a world application. Backgammon-style doubling-cube chess running inside a Semantos world region (cell-relay room + chess cartridge verbs). Cube rendered via core/cube-object so the live linearity colour reflects the kernel's substructural type.",
  "semantos": {
    "worldApp": true,
    "protocol": "world-beam",
    "relay": "cell-relay",
    "cartridge": "chess"
  },
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "typecheck": "tsc --noEmit -p tsconfig.json",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "@semantos/cube-object": "workspace:*",
    "@semantos/world-sdk": "workspace:*",
    "svelte": "^5.55.4",
    "three": "^0.165.0",
    "@noble/hashes": "^1.4.0"
  },
  "devDependencies": {
    "@sveltejs/vite-plugin-svelte": "^5.1.1",
    "@types/three": "^0.165.0",
    "typescript": "~5.8.0",
    "vite": "^6.4.2",
    "vitest": "^1.6.0"
  },
  "license": "UNLICENSED"
}

```
