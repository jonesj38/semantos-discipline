---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/package.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.579892+00:00
---

# cartridges/jambox/web/package.json

```json
{
  "name": "@semantos/world-app-jam-room",
  "version": "0.2.0",
  "private": true,
  "type": "module",
  "description": "Jam Room — a world application. Collaborative music sequencer running inside a Semantos world region (BEAM-backed). 4-channel mixer, clip launcher, synths, BSV anchoring.",
  "semantos": {
    "worldApp": true,
    "protocol": "world-beam",
    "relay": "cell-relay"
  },
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "typecheck": "tsc --noEmit -p tsconfig.json",
    "test": "vitest run",
    "test:watch": "vitest",
    "test:gate-g": "vitest run __tests__/phase-g-gate.test.ts",
    "audit:bundle": "bun run scripts/audit-bundle.ts",
    "gen-parity": "bun run scripts/gen-scale-colour-parity.ts"
  },
  "dependencies": {
    "@bsv/sdk": "^1.4.0",
    "@semantos/world-sdk": "workspace:*",
    "phoenix": "^1.7.0",
    "svelte": "^5.55.4",
    "three": "^0.165.0"
  },
  "devDependencies": {
    "@sveltejs/vite-plugin-svelte": "^5.1.1",
    "@types/three": "^0.165.0",
    "@vitest/snapshot": "^1.6.0",
    "typescript": "~5.8.0",
    "vite": "^6.4.2",
    "vitest": "^1.6.0"
  },
  "license": "UNLICENSED"
}

```
