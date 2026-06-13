---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/serve.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.580174+00:00
---

# cartridges/jambox/web/serve.ts

```ts
/**
 * Tiny Bun static server for jam-room. Bun bundles src/main.ts → public/main.js;
 * this serves the index + bundle + style. Refresh to pick up bundle changes.
 */

import { join } from 'node:path';
import { existsSync, readFileSync } from 'node:fs';

const ROOT = import.meta.dir;

/** Read .env.local at start so the page can use VITE_* vars without a bundler. */
function loadEnv(): Record<string, string> {
  const out: Record<string, string> = {};
  const path = join(ROOT, '.env.local');
  if (!existsSync(path)) return out;
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (!m || line.trim().startsWith('#')) continue;
    out[m[1]] = m[2].replace(/^["']|["']$/g, '');
  }
  return out;
}
const ENV = loadEnv();
const ENV_SCRIPT = `<script>window.JAM_ENV = ${JSON.stringify(ENV)};</script>`;

const MIME: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js':   'application/javascript',
  '.css':  'text/css; charset=utf-8',
  '.svg':  'image/svg+xml',
  '.json': 'application/json',
};

function mimeFor(path: string): string {
  const ext = path.slice(path.lastIndexOf('.'));
  return MIME[ext] ?? 'application/octet-stream';
}

const server = Bun.serve({
  port: 5180,
  async fetch(req) {
    const url = new URL(req.url);
    let p = url.pathname;
    if (p === '/' || p === '/index.html') p = '/index.html';

    // Try project root, then public/, then src/.
    const candidates = [
      p === '/index.html' ? join(ROOT, 'index.html') : null,
      join(ROOT, 'public', p),
      join(ROOT, p.replace(/^\//, '')),
    ].filter((x): x is string => !!x);
    const found = candidates.find(existsSync);
    if (!found) return new Response('not found', { status: 404 });

    if (found.endsWith('index.html')) {
      const text = await Bun.file(found).text();
      const rewritten = text.replace(
        '<script type="module" src="./src/main.ts"></script>',
        `${ENV_SCRIPT}\n    <script type="module" src="/main.js"></script>`,
      );
      return new Response(rewritten, { headers: { 'content-type': MIME['.html'] } });
    }
    return new Response(Bun.file(found), {
      headers: { 'content-type': mimeFor(found) },
    });
  },
});

console.log(`jam-room serving on http://localhost:${server.port}`);
console.log(`  rooms: append ?room=<name>&as=<handle> to share with collaborators`);

```
