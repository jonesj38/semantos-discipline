---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/demo/serve.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.747076+00:00
---

# docs/demo/serve.ts

```ts
// serve.ts — static server for the singularity demo pages (docs/demo/).
// `/` serves mnca-grid.html. Resolves files from this script's directory so
// CWD doesn't matter. Usage: bun docs/demo/serve.ts
import { join } from 'node:path';

const PORT = Number(process.env.DEMO_PORT ?? 4321);
const DIR = import.meta.dir;
const MIME: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json',
};
const ext = (p: string): string => (p.lastIndexOf('.') >= 0 ? p.slice(p.lastIndexOf('.')) : '');

Bun.serve({
  port: PORT,
  async fetch(req) {
    const url = new URL(req.url);
    // `/` → the hero "one cell · six layers" view; grid lives at /mnca-grid.html.
    const path = url.pathname === '/' ? '/cell-journey.html' : url.pathname;
    const file = Bun.file(join(DIR, path));
    if (await file.exists()) {
      return new Response(file, { headers: { 'Content-Type': MIME[ext(path)] ?? 'application/octet-stream' } });
    }
    return new Response('Not found', { status: 404 });
  },
});
console.log(`demo server: http://localhost:${PORT}/`);

```
