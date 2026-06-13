---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/vite.config.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.579361+00:00
---

# cartridges/jambox/web/vite.config.ts

```ts
import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

export default defineConfig({
  plugins: [svelte()],
  server: {
    port: 3000,
    open: true,
  },
  build: {
    target: 'esnext',
    outDir: 'dist',
  },
  resolve: {
    alias: {
      '$lib': '/src/svelte/lib',
    },
  },
});

```
