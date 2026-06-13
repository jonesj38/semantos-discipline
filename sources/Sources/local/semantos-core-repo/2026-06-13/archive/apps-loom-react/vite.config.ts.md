---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/vite.config.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.695743+00:00
---

# archive/apps-loom-react/vite.config.ts

```ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { nodePolyfills } from 'vite-plugin-node-polyfills';
import path from 'path';
import fs from 'fs';

// Optional HTTPS for LAN dev (crypto.subtle requires a secure context).
// Generate certs with: openssl req -x509 -newkey rsa:2048 -keyout certs/key.pem \
//   -out certs/cert.pem -days 365 -nodes -subj "/CN=semantos-dev"
const certDir = path.resolve(__dirname, 'certs');
const httpsConfig = fs.existsSync(path.join(certDir, 'cert.pem'))
  ? {
      key: fs.readFileSync(path.join(certDir, 'key.pem')),
      cert: fs.readFileSync(path.join(certDir, 'cert.pem')),
    }
  : undefined;

export default defineConfig({
  plugins: [
    react(),
    nodePolyfills({
      // Polyfill Node.js built-ins so transitive deps resolve in browser.
      // Exclude `fs` and `fs/promises` — we handle those via the `fs/promises`
      // alias below (the polyfiller's subpath-import resolution mis-joins
      // `empty.js/promises` and the build fails to load it).
      exclude: ['fs', 'fs/promises'],
    }),
  ],
  resolve: {
    // Prefer .ts over compiled .js when both exist side-by-side (protocol-types ships both)
    extensions: ['.mjs', '.mts', '.ts', '.tsx', '.js', '.jsx', '.json'],
    alias: [
      // Named-package aliases
      // Phase 3 restructure: cross-tier sibling paths changed from
      // ../pkg/src to ../../<tier>/pkg/src. apps/loom/ stays depth-2
      // so ../../src to the repo root is unchanged.
      { find: '@semantos/core', replacement: path.resolve(__dirname, '../../src') },
      { find: '@semantos/cell-ops', replacement: path.resolve(__dirname, '../../core/cell-ops/src') },
      // Browser-safe barrel: constants + core types only, no cell-ops (Node.js crypto/Buffer)
      { find: '@semantos/protocol-types/browser', replacement: path.resolve(__dirname, '../../core/protocol-types/src/browser') },
      { find: '@semantos/protocol-types', replacement: path.resolve(__dirname, '../../core/protocol-types/src') },
      { find: '@semantos/cell-engine', replacement: path.resolve(__dirname, '../../core/cell-engine/bindings') },
      { find: '@semantos/pask', replacement: path.resolve(__dirname, '../../core/pask/bindings/ts/src') },
      { find: '@semantos/shell', replacement: path.resolve(__dirname, '../../runtime/shell/src/browser.ts') },
      { find: '@semantos/loom', replacement: path.resolve(__dirname, 'src/services/index.ts') },
      { find: '@semantos/games', replacement: path.resolve(__dirname, '../../packages/games/src') },
      // @semantos/extraction has Node-only deps; the browser router-browser
      // never imports it, but other transitive imports might pick it up.
      { find: '@semantos/extraction', replacement: path.resolve(__dirname, 'src/stubs/extraction-browser.ts') },
      { find: '@configs', replacement: path.resolve(__dirname, '../../configs') },
      // Stub fs/promises so node-fs-adapter.ts (reached via dynamic import in create-adapter)
      // doesn't break the browser build. The adapter is never called in browser context.
      { find: 'fs/promises', replacement: path.resolve(__dirname, 'src/stubs/fs-promises.ts') },
    ],
  },
  build: {
    rollupOptions: {
      // d3-force is optional (swarm view only) and not installed — externalize so build succeeds
      external: ['d3-force'],
    },
  },
  optimizeDeps: {
    exclude: ['@semantos/protocol-types'],
  },
  server: {
    port: 3000,
    host: true,
    https: httpsConfig,
    hmr: {
      overlay: false,
    },
    proxy: {
      '/api': 'http://localhost:3001',
      '/ws': {
        target: 'ws://localhost:3001',
        ws: true,
      },
    },
  },
});

```
