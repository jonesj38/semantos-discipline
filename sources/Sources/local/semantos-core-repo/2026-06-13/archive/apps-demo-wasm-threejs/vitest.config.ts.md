---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-demo-wasm-threejs/vitest.config.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.689054+00:00
---

# archive/apps-demo-wasm-threejs/vitest.config.ts

```ts
import { defineConfig } from 'vitest/config';
import { resolve } from 'node:path';

const REPO_ROOT = resolve(__dirname, '..', '..');

export default defineConfig({
  resolve: {
    // Point workspace packages at their TypeScript source so vitest can
    // resolve them without a prior build step. The packages export a "bun"
    // condition that pnpm / Bun understand but Vitest's Node runner does not.
    alias: {
      '@semantos/identity-ports/stub': resolve(
        REPO_ROOT,
        'core/identity-ports/src/stub-binding.ts',
      ),
      '@semantos/identity-ports': resolve(
        REPO_ROOT,
        'core/identity-ports/src/index.ts',
      ),
      '@semantos/state': resolve(REPO_ROOT, 'core/state/src/index.ts'),
      '@plexus/contracts': resolve(REPO_ROOT, 'core/plexus-contracts/src/index.ts'),
      '@plexus/vendor-sdk': resolve(
        REPO_ROOT,
        'core/plexus-vendor-sdk/src/index.ts',
      ),
    },
  },
  test: {
    environment: 'jsdom',
    globals: false,
    include: ['src/__tests__/**/*.test.ts'],
  },
});

```
