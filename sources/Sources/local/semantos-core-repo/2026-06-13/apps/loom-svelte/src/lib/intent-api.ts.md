---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/intent-api.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.077736+00:00
---

# apps/loom-svelte/src/lib/intent-api.ts

```ts
/**
 * intent-api.ts — typed HTTP client for /api/v1/intent/*.
 *
 * Matches the JSON shape produced by runtime/semantos-brain/src/intent_http.zig.
 * classify → { verb, confidence, params, correlation_id }
 */

export interface IntentClassification {
  verb: string;
  confidence: number;
  params: Record<string, unknown>;
  correlation_id: string;
}

export interface ClassifyError {
  kind: 'network' | 'bad_request' | 'unauthorised' | 'server_error';
  message: string;
}

export type ClassifyResult =
  | { ok: true; classification: IntentClassification }
  | { ok: false; error: ClassifyError };

/**
 * POST /api/v1/intent/classify
 * Body: { text: string, source?: string }
 */
export async function classify(
  brainBase: string,
  bearer: string,
  text: string,
  source?: string,
): Promise<ClassifyResult> {
  try {
    const body: Record<string, string> = { text };
    if (source) body.source = source;

    const res = await fetch(`${brainBase}/api/v1/intent/classify`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${bearer}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });

    if (res.status === 400) {
      const err = await res.json().catch(() => ({ error: 'bad request' })) as { error?: string };
      return { ok: false, error: { kind: 'bad_request', message: err.error ?? 'Bad request' } };
    }
    if (res.status === 401) {
      return { ok: false, error: { kind: 'unauthorised', message: 'Unauthorised' } };
    }
    if (!res.ok) {
      return { ok: false, error: { kind: 'server_error', message: `HTTP ${res.status}` } };
    }

    const classification = await res.json() as IntentClassification;
    return { ok: true, classification };
  } catch (e) {
    return { ok: false, error: { kind: 'network', message: String(e) } };
  }
}

```
