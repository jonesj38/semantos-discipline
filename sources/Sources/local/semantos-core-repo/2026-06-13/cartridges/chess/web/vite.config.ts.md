---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/web/vite.config.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.426250+00:00
---

# cartridges/chess/web/vite.config.ts

```ts
import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

export default defineConfig({
  plugins: [svelte()],
  server: {
    port: 3100,
    open: true,
  },
  build: {
    target: 'esnext',
    outDir: 'dist',
    rollupOptions: {
      output: {
        // Three.js is by far the heaviest dep and is only needed once
        // a game is in progress (CubePanel mounts after Create/Join).
        // Splitting it out drops the initial bundle from ~640 KB → ~80 KB
        // so the lobby loads instantly; the three chunk arrives in
        // parallel with the user's lobby interactions.
        manualChunks: {
          three: ['three'],
        },
      },
    },
  },
  resolve: {
    alias: {
      $lib: '/src/svelte/lib',
    },
    // The world-sdk / cube-object workspaces ship source-only — their
    // `bun` export condition points at `./src/...ts`, while `import`
    // points at uncompiled `./dist/...js` paths. Add `bun` so vite picks
    // the source entries instead of trying to resolve the missing
    // dist/. Same shape as jam-room (which Bun also runs).
    conditions: ['bun', 'import', 'module', 'browser', 'default'],
  },
});

```
