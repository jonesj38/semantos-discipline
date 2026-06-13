---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/health-check.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.304198+00:00
---

# runtime/node/src/health-check.ts

```ts
#!/usr/bin/env bun
/**
 * Docker HEALTHCHECK script.
 *
 * Makes an HTTP request to the admin API status endpoint.
 * Exits 0 on success, 1 on failure.
 */

const port = process.env.SEMANTOS_ADMIN_PORT ?? '6443';
const url = `http://localhost:${port}/api/node/status`;

try {
  const res = await fetch(url, { signal: AbortSignal.timeout(4000) });
  if (res.ok) {
    process.exit(0);
  }
  process.exit(1);
} catch {
  process.exit(1);
}

```
