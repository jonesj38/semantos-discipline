---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/api/envelope.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.310213+00:00
---

# runtime/node/src/api/envelope.ts

```ts
/**
 * API response envelope — wraps all admin API responses.
 *
 * Cross-references:
 *   Phase 26G PRD (D26G.4) — response format specification
 */

export interface ApiEnvelope<T = unknown> {
  data: T;
  timestamp: number;
  error?: { code: string; message: string };
}

export function success<T>(data: T): Response {
  const envelope: ApiEnvelope<T> = {
    data,
    timestamp: Date.now(),
  };
  return Response.json(envelope);
}

export function error(code: string, message: string, status: number): Response {
  const envelope: ApiEnvelope<null> = {
    data: null,
    timestamp: Date.now(),
    error: { code, message },
  };
  return Response.json(envelope, { status });
}

```
