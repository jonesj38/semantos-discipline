---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/postcss.config.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.695490+00:00
---

# archive/apps-loom-react/postcss.config.js

```js
import { fileURLToPath } from 'url';
import path from 'path';

// Vite is launched from the repo root (wrapper script cd's there for
// monorepo module resolution), so Tailwind's default cwd-based config
// lookup finds nothing. Point it explicitly at the colocated config.
const here = path.dirname(fileURLToPath(import.meta.url));

export default {
  plugins: {
    tailwindcss: { config: path.join(here, 'tailwind.config.ts') },
    autoprefixer: {},
  },
};

```
