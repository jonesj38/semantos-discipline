---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/attention-api.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.080467+00:00
---

# apps/loom-svelte/src/lib/attention-api.ts

```ts
/**
 * attention-api.ts — client for the helm's attention surface.
 *
 * REWORKED (SH9, 2026-06-07): the REST /api/v1/attention/* surface was
 * DELETED on origin/main (PR #921, "superseded by the generic attention.poll").
 * This client now calls the WSS namespace-scoped `attention.poll` over the
 * /api/v1/wallet JSON-RPC socket (the same transport oddjobz-query uses).
 *
 * ⚠ INFERRED WIRE CONTRACT — pinned from brain comments
 * (attention_poll_handler.poll(namespaces); serve.zig "wss_backend.attention
 * serves the new attention.poll method"), NOT verified against a live brain
 * in-loop. Verify before relying on it; adjust parseAttentionPoll if the
 * envelope differs.
 *   method = "attention.poll"
 *   params = { namespaces: string[] }                  // caller's in-scope namespaces
 *   result = AttentionSignal[]  OR  { items: AttentionSignal[] }  (parsed tolerantly)
 * Signal shape = what attention_source_registry.zig sources emit:
 *   { kind, score, ref, summary, expiresAt?, raw? }
 *
 * Telemetry: the old POST /api/v1/attention/interact was ALSO deleted; there
 * is no poll-era interaction endpoint, so interaction telemetry is dropped
 * here and deferred to SH11 (the learning loop).
 */

import { WssJsonRpcTransport } from './oddjobz-query';

/** A scored attention signal from the brain's namespace-scoped poll. */
export interface AttentionSignal {
  /** Short source label, e.g. "dispatch" | "message" | "job". */
  kind: string;
  /** Relevance score, 0..1. */
  score: number;
  /** Opaque ref the helm can act on (e.g. a cellId / object id). */
  ref: string;
  /** One-line human summary rendered on the card. */
  summary: string;
  /** Optional expiry (ms epoch). */
  expiresAt?: number;
  /** Source-defined extra payload. */
  raw?: unknown;
}

/** Transport seam — structurally the oddjobz WssJsonRpcTransport. */
export interface AttentionPollTransport {
  request(method: string, params: Record<string, unknown>): Promise<unknown>;
}

function num(v: unknown, dflt = 0): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : dflt;
}
function str(v: unknown, dflt = ''): string {
  return typeof v === 'string' ? v : dflt;
}

/**
 * Tolerantly parse the attention.poll result into AttentionSignal[]. Accepts a
 * bare array OR a { items: [...] } envelope (the exact shape is inferred — see
 * header). Drops entries with neither a ref nor a summary. Pure — unit-tested.
 */
export function parseAttentionPoll(result: unknown): AttentionSignal[] {
  const arr: unknown[] = Array.isArray(result)
    ? result
    : result && typeof result === 'object' && Array.isArray((result as { items?: unknown[] }).items)
      ? (result as { items: unknown[] }).items
      : [];
  const out: AttentionSignal[] = [];
  for (const e of arr) {
    if (!e || typeof e !== 'object') continue;
    const o = e as Record<string, unknown>;
    const ref = str(o.ref);
    const summary = str(o.summary);
    if (!ref && !summary) continue; // junk entry
    out.push({
      kind: str(o.kind, 'signal'),
      score: num(o.score),
      ref,
      summary,
      expiresAt: typeof o.expiresAt === 'number' ? o.expiresAt : undefined,
      raw: o.raw,
    });
  }
  return out;
}

/**
 * Poll the in-scope attention sources. Returns [] on any error (caller shows
 * the empty state). `namespaces` is the caller's scope, e.g. ["shell"] or
 * ["shell","oddjobz"].
 */
export async function pollAttention(
  transport: AttentionPollTransport,
  namespaces: string[],
): Promise<AttentionSignal[]> {
  try {
    const result = await transport.request('attention.poll', { namespaces });
    return parseAttentionPoll(result);
  } catch {
    return [];
  }
}

/** Build the production WSS transport for the attention poll. */
export function attentionWssTransport(brainBase: string, bearer: string): AttentionPollTransport {
  const wssUrl = brainBase.replace(/^http/, 'ws') + '/api/v1/wallet';
  return new WssJsonRpcTransport({ wssUrl, bearer });
}

```
