---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/audit.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.127261+00:00
---

# runtime/legacy-ingest/src/audit.ts

```ts
/**
 * Legacy-ingest audit log.
 *
 * Mirrors the Brain 2 host_audit pattern (cf. runtime/semantos-brain/src/audit_log.zig)
 * but lives in TS so it works wherever the legacy-ingest service runs
 * (browser, node, bun-shell). One JSON object per line; never logs
 * plaintext secrets — the orchestrator summarises before recording.
 *
 * Sink is pluggable: production wires it to the BRAIN host_audit broker
 * via a host-import; tests pass an in-memory sink and assert.
 */

export type AuditResult = 'ok' | 'denied' | 'error';

export interface AuditEntry {
  readonly ts: number;
  readonly module: 'legacy-ingest';
  readonly op: string;
  readonly result: AuditResult;
  readonly providerId?: string;
  readonly grantId?: string;
  readonly hatId?: string | null;
  readonly detail?: string;
}

export type AuditSink = (entry: AuditEntry) => void | Promise<void>;

let sink: AuditSink = () => {};

export function setAuditSink(fn: AuditSink): void {
  sink = fn;
}

export async function audit(
  op: string,
  result: AuditResult,
  fields: Omit<AuditEntry, 'ts' | 'module' | 'op' | 'result'> = {},
): Promise<void> {
  const entry: AuditEntry = {
    ts: Date.now(),
    module: 'legacy-ingest',
    op,
    result,
    ...fields,
  };
  try {
    await sink(entry);
  } catch {
    // Audit failures are non-fatal — never block an OAuth flow on a
    // log write. The default sink is a no-op so the only failure path
    // is host-injected sinks; those should self-heal.
  }
}

```
