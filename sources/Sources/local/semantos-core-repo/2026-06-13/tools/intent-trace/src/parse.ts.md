---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/intent-trace/src/parse.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.549957+00:00
---

# tools/intent-trace/src/parse.ts

```ts
/**
 * RM-093 — JSONL trace parser.
 *
 * Reads a stream of newline-delimited StageEvent records (the shape
 * `runtime/intent/src/logger.ts::createJsonlStderrLogger` writes) and
 * returns them as typed objects. Blank lines + lines that don't parse
 * as JSON objects are skipped silently — production traces interleave
 * with other stderr noise often enough that strict-mode would be
 * miserable to use.
 *
 * No dependency on `@semantos/intent` to keep the CLI installable
 * without the whole substrate.
 */

export interface TraceEvent {
  ts: string;
  correlationId: string;
  intentId: string | null;
  stage: string;
  durationMs: number;
  hatId: string | null;
  source: string;
  data: Record<string, unknown>;
}

/** Parse a single JSONL line. Returns null for non-event lines. */
export function parseLine(line: string): TraceEvent | null {
  const s = line.trim();
  if (!s) return null;
  if (s[0] !== '{') return null;
  let obj: unknown;
  try {
    obj = JSON.parse(s);
  } catch {
    return null;
  }
  if (!isTraceEvent(obj)) return null;
  return obj;
}

/** Parse a full JSONL blob (e.g. read from a file). */
export function parseTrace(text: string): TraceEvent[] {
  const out: TraceEvent[] = [];
  for (const line of text.split(/\r?\n/)) {
    const ev = parseLine(line);
    if (ev) out.push(ev);
  }
  return out;
}

/** Group parsed events by `correlationId`, preserving arrival order. */
export function groupByCorrelation(events: TraceEvent[]): Map<string, TraceEvent[]> {
  const map = new Map<string, TraceEvent[]>();
  for (const e of events) {
    const k = e.correlationId;
    if (!map.has(k)) map.set(k, []);
    map.get(k)!.push(e);
  }
  return map;
}

function isTraceEvent(v: unknown): v is TraceEvent {
  if (!v || typeof v !== 'object') return false;
  const o = v as Record<string, unknown>;
  return (
    typeof o.ts === 'string' &&
    typeof o.correlationId === 'string' &&
    (o.intentId === null || typeof o.intentId === 'string') &&
    typeof o.stage === 'string' &&
    typeof o.durationMs === 'number' &&
    typeof o.data === 'object' &&
    o.data !== null
  );
}

```
