---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-legacy-cli/src/audit-sink.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.700100+00:00
---

# archive/apps-legacy-cli/src/audit-sink.ts

```ts
/**
 * Filesystem-backed audit sink for the Phase 1 CLI.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI1 (audit log)
 * and runtime/semantos-brain/src/audit_log.zig — same JSON-line schema so a
 * Phase 2 cutover to the Semantos Brain broker reads the same `~/.semantos/
 * audit.log` without conversion.
 *
 * One JSON object per line:
 *
 *   { "ts": <unix-ms>, "module": "legacy-ingest", "op": "...",
 *     "result": "ok|denied|error",
 *     "providerId": "...", "grantId": "...", "hatId": "...",
 *     "detail": "..." }
 *
 * The orchestrator + stores summarise args (e.g. "redirect=https://..."
 * not the full client config) before calling audit() — never logs
 * plaintext credentials. This sink just appends.
 */

import { appendFileSync, mkdirSync, existsSync, chmodSync } from 'node:fs';
import { dirname } from 'node:path';
import type { AuditEntry } from '@semantos/legacy-ingest';

export interface FileAuditSinkOpts {
  /** Path to the log file. Defaults to <root>/audit.log. */
  path: string;
}

export class FileAuditSink {
  private readonly path: string;

  constructor(opts: FileAuditSinkOpts) {
    this.path = opts.path;
    const dir = dirname(this.path);
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true, mode: 0o700 });
    if (!existsSync(this.path)) {
      // Create with restrictive perms so a future operator-shared host
      // doesn't leak audit context.
      appendFileSync(this.path, '', { mode: 0o600 });
      chmodSync(this.path, 0o600);
    }
  }

  /** Sink shape — one call per audit event. */
  append = (entry: AuditEntry): void => {
    appendFileSync(this.path, JSON.stringify(entry) + '\n');
  };
}

/** Convenience: build the default sink and return its `.append` fn. */
export function defaultAuditSink(rootDir: string): (entry: AuditEntry) => void {
  const sink = new FileAuditSink({ path: `${rootDir}/audit.log` });
  return sink.append;
}

```
