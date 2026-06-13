---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/inference/api-probe.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.464302+00:00
---

# packages/extraction/src/inference/api-probe.ts

```ts
/**
 * G-3 — API probe runner.
 *
 * Issues sample HTTP requests to a live endpoint and builds an EntityGraph
 * from the observed response shapes. No credentials required for read
 * endpoints — the auth scheme is declared in the grammar separately.
 *
 * Heuristic field typing:
 *   - ISO timestamp strings  → datetime
 *   - ISO date strings        → date
 *   - UUID strings            → string (id-flavoured)
 *   - Integer strings         → number
 *   - Short strings with few distinct values → enum candidate
 *   - boolean                 → boolean
 *   - null/undefined mix      → string (required=false)
 *   - arrays                  → array
 *   - nested objects          → spawns a new entity node
 *
 * See docs/textbook/33-automated-grammar-synthesis.md §Stage 1 (live probing)
 */

import { analyzeStructure } from './structure-analyzer';
import type { EntityGraph, RawResponse } from './types';

// ---------------------------------------------------------------------------
// Options
// ---------------------------------------------------------------------------

export interface ApiProbeOptions {
  /** Base URL of the target API. */
  baseUrl: string;
  /**
   * Paths to probe (relative to baseUrl). If omitted, the runner
   * attempts common list-endpoint patterns: /, /items, /list.
   */
  paths?: string[];
  /** Number of sample requests per endpoint (default 5). */
  probeCount?: number;
  /** Request timeout per probe in milliseconds (default 5000). */
  timeoutMs?: number;
  /** Optional headers (e.g. Authorization) for authenticated endpoints. */
  headers?: Record<string, string>;
}

export interface ApiProbeResult {
  entityGraph: EntityGraph;
  rawResponses: RawResponse[];
  probeErrors: Array<{ path: string; error: string }>;
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

/**
 * Probe a live API endpoint and return an EntityGraph.
 *
 * The probe runner calls up to `probeCount` requests per path and passes
 * the collected RawResponses to StructureAnalyzer (D36C.1). This makes
 * the live-probe path and the Swagger-ingester path interchangeable from
 * the perspective of downstream stages.
 */
export async function probeApi(options: ApiProbeOptions): Promise<ApiProbeResult> {
  const {
    baseUrl,
    paths = guessListPaths(),
    probeCount = 5,
    timeoutMs = 5000,
    headers = {},
  } = options;

  const rawResponses: RawResponse[] = [];
  const probeErrors: Array<{ path: string; error: string }> = [];

  for (const path of paths) {
    const url = `${baseUrl.replace(/\/$/, '')}/${path.replace(/^\//, '')}`;
    for (let i = 0; i < probeCount; i++) {
      try {
        const response = await fetchWithTimeout(url, { headers }, timeoutMs);
        if (response.ok) {
          const body = await response.json();
          rawResponses.push({
            url,
            statusCode: response.status,
            sampledAt: new Date().toISOString(),
            body,
            headers: Object.fromEntries(response.headers.entries()),
          });
          // Only need one successful response per path for structure inference
          break;
        }
      } catch (err) {
        probeErrors.push({ path, error: String(err) });
        break;
      }
    }
  }

  const entityGraph = analyzeStructure(rawResponses);
  return { entityGraph, rawResponses, probeErrors };
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

async function fetchWithTimeout(
  url: string,
  init: RequestInit,
  timeoutMs: number,
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Common list-endpoint path patterns to try when no paths are specified.
 * Ordered by likelihood — most REST APIs expose resources at the root or
 * a /v1/ prefix.
 */
function guessListPaths(): string[] {
  return [
    '/',
    '/v1',
    '/api',
    '/api/v1',
    '/items',
    '/list',
    '/resources',
  ];
}

```
