---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/scripts/dev-server.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.643481+00:00
---

# cartridges/wallet-headers/brain/scripts/dev-server.ts

```ts
// dev-server.ts — serves dist/ and proxies ARC requests to avoid CORS/extension issues.
// Usage (from anywhere): bun cartridges/wallet-headers/brain/scripts/dev-server.ts
// Then open http://localhost:8080/wallet.html
//
// Port is 8080 to match wallet-page.ts's ARC_URL logic: the page only routes
// ARC through the local /arc proxy when the origin is :8080 (otherwise it
// hits gorillapool direct, which CORS-blocks in the browser). dist/ is
// resolved from THIS script's location, so the CWD doesn't matter.

import { join } from 'node:path';

const PORT = Number(process.env.WALLET_DEV_PORT ?? 8080);
const DIST_DIR = join(import.meta.dir, '..', 'dist');
const ARC_UPSTREAM = 'https://arc.taal.com';
const ARC_API_KEY = 'mainnet_61d0aaf737c32c42d858de6dbd59c336';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

const MIME: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json',
};

function ext(path: string): string {
  const dot = path.lastIndexOf('.');
  return dot >= 0 ? path.slice(dot) : '';
}

Bun.serve({
  port: PORT,
  async fetch(req) {
    const url = new URL(req.url);

    if (req.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    // ARC proxy — POST /arc/v1/tx → arc.taal.com/v1/tx (with API key added server-side)
    if (url.pathname === '/arc/v1/tx' && req.method === 'POST') {
      const body = await req.text();
      let upstream: Response;
      try {
        upstream = await fetch(`${ARC_UPSTREAM}/v1/tx`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${ARC_API_KEY}`,
          },
          body,
        });
      } catch (e) {
        return new Response(JSON.stringify({ error: `ARC unreachable: ${(e as Error).message}` }), {
          status: 502,
          headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
        });
      }
      const respBody = await upstream.text();
      return new Response(respBody, {
        status: upstream.status,
        headers: {
          'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json',
          ...CORS_HEADERS,
        },
      });
    }

    // ARC status proxy — GET /arc/v1/tx/{txid} → arc.taal.com (with API key).
    if (url.pathname.startsWith('/arc/v1/tx/') && req.method === 'GET') {
      const txid = url.pathname.slice('/arc/v1/tx/'.length);
      let upstream: Response;
      try {
        upstream = await fetch(`${ARC_UPSTREAM}/v1/tx/${txid}`, {
          headers: { 'Authorization': `Bearer ${ARC_API_KEY}` },
        });
      } catch (e) {
        return new Response(JSON.stringify({ error: `ARC unreachable: ${(e as Error).message}` }), {
          status: 502, headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
        });
      }
      const respBody = await upstream.text();
      return new Response(respBody, {
        status: upstream.status,
        headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json', ...CORS_HEADERS },
      });
    }

    // Static file serving from dist/ (resolved from this script, not CWD).
    const filePath = url.pathname === '/' ? '/wallet.html' : url.pathname;
    const file = Bun.file(join(DIST_DIR, filePath));
    if (await file.exists()) {
      return new Response(file, {
        headers: { 'Content-Type': MIME[ext(filePath)] ?? 'application/octet-stream' },
      });
    }

    return new Response('Not found', { status: 404 });
  },
});

console.log(`Semantos wallet dev server: http://localhost:${PORT}/wallet.html`);
console.log(`Serving: ${DIST_DIR}`);
console.log(`ARC proxy: http://localhost:${PORT}/arc/v1/tx → ${ARC_UPSTREAM}/v1/tx`);

```
