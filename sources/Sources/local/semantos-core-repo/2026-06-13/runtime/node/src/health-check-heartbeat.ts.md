---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/health-check-heartbeat.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.303934+00:00
---

# runtime/node/src/health-check-heartbeat.ts

```ts
#!/usr/bin/env bun
/**
 * Docker health check — reads heartbeat timestamp file.
 *
 * Exits 0 if heartbeat is fresh (< 30s old), 1 otherwise.
 * Used in docker-compose.hackathon.yml HEALTHCHECK.
 *
 * Cross-references:
 *   docker-multicast-adapter.ts — writes /tmp/semantos-heartbeat
 *   Phase H1 PRD — DH1.5
 */

import { readFileSync } from 'node:fs';

const HEARTBEAT_FILE = process.env.HEARTBEAT_FILE ?? '/tmp/semantos-heartbeat';
const MAX_AGE_MS = 30_000;

try {
  const content = readFileSync(HEARTBEAT_FILE, 'utf-8').trim();
  const ts = Number(content);
  if (Number.isNaN(ts)) {
    console.error('[health] Invalid heartbeat timestamp');
    process.exit(1);
  }
  const age = Date.now() - ts;
  if (age > MAX_AGE_MS) {
    console.error(`[health] Heartbeat stale: ${age}ms > ${MAX_AGE_MS}ms`);
    process.exit(1);
  }
  console.log(`[health] OK (age: ${age}ms)`);
  process.exit(0);
} catch (err: unknown) {
  console.error(`[health] Cannot read heartbeat: ${(err as Error).message}`);
  process.exit(1);
}

```
