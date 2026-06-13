---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/tailwind.config.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.695239+00:00
---

# archive/apps-loom-react/tailwind.config.ts

```ts
import type { Config } from 'tailwindcss';
import path from 'path';
import { fileURLToPath } from 'url';

// Resolve content globs relative to this config file, not process.cwd().
// (Vite is launched from the repo root for monorepo resolution, so relative
// globs like './src/**' would otherwise match the wrong package.)
const here = path.dirname(fileURLToPath(import.meta.url));

export default {
  content: [
    path.join(here, 'index.html'),
    path.join(here, 'src/**/*.{ts,tsx}'),
  ],
  theme: {
    extend: {
      colors: {
        linear: { DEFAULT: '#22c55e', light: '#bbf7d0' },
        affine: { DEFAULT: '#3b82f6', light: '#bfdbfe' },
        relevant: { DEFAULT: '#eab308', light: '#fef08a' },
        debug: { DEFAULT: '#6b7280', light: '#e5e7eb' },
        swarm: {
          nit: '#3366ff',
          maniac: '#ff3333',
          calculator: '#33cc33',
          apex: '#ffcc00',
          anchor: '#ffcc00',
          bg: '#0a0a0a',
          panel: '#1a1a2e',
          border: '#333355',
          success: '#22dd22',
          warning: '#dd9922',
          error: '#dd2222',
        },
      },
    },
  },
  plugins: [],
} satisfies Config;

```
