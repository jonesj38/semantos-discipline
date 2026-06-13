---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/oddjobtodd/vite.config.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.046771+00:00
---

# apps/oddjobtodd/vite.config.ts

```ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    port: Number(process.env.PORT) || 5174,
    host: true,
  },
  build: {
    rollupOptions: {
      output: {
        // Fixed asset names so the site.json static routes don't need
        // updating on every build.
        entryFileNames: 'assets/app.js',
        chunkFileNames: 'assets/[name].js',
        assetFileNames: 'assets/[name][extname]',
      },
    },
  },
});

```
