---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/refresh-worker.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.128396+00:00
---

# runtime/legacy-ingest/src/refresh-worker.ts

```ts
/**
 * Token-refresh background worker — LI1 deliverable 3.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI1 deliverable 3.
 *
 * Periodically scans all grants for upcoming expiry and refreshes them
 * before they expire. The default lead time is 5 minutes — enough to
 * absorb network jitter without stale-token failures.
 *
 * Failure surfaces as an audit-log entry; the operator sees the failed
 * refresh in `legacy status` and can re-run `legacy connect <provider>`
 * to re-grant.
 */

import type { LegacyGrant, ProviderId } from './types';
import { audit } from './audit';
import { LegacyGrantStore } from './grant-store';
import { OAuthOrchestrator, OAuthError } from './oauth';

export interface RefreshWorkerOpts {
  store: LegacyGrantStore;
  orchestrator: OAuthOrchestrator;
  /** Provider ids to scan. Empty array = all known providers. */
  providers: ProviderId[];
  /** Refresh when the token has < this much time left (ms). Default 5 min. */
  leadTimeMs?: number;
  /** Polling interval (ms). Default 60s. */
  intervalMs?: number;
  /** Failures since last success — surfaces in `legacy status`. */
  onFailure?: (grant: LegacyGrant, error: unknown) => void;
}

export class RefreshWorker {
  private timer: ReturnType<typeof setInterval> | null = null;
  private readonly opts: Required<Omit<RefreshWorkerOpts, 'onFailure'>> & {
    onFailure: NonNullable<RefreshWorkerOpts['onFailure']>;
  };

  constructor(opts: RefreshWorkerOpts) {
    this.opts = {
      ...opts,
      leadTimeMs: opts.leadTimeMs ?? 5 * 60 * 1000,
      intervalMs: opts.intervalMs ?? 60_000,
      onFailure: opts.onFailure ?? (() => {}),
    };
  }

  start(): void {
    if (this.timer) return;
    this.timer = setInterval(() => void this.tick(), this.opts.intervalMs);
    void this.tick();
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  /** One scan-and-refresh pass. Exposed for tests. */
  async tick(): Promise<void> {
    const now = Date.now();
    for (const providerId of this.opts.providers) {
      let grants: LegacyGrant[];
      try {
        grants = await this.opts.store.listByProvider(providerId);
      } catch (err) {
        await audit('refresh.list', 'error', {
          providerId,
          detail: err instanceof Error ? err.message : 'unknown',
        });
        continue;
      }
      for (const grant of grants) {
        const remaining = grant.token.expiresAt - now;
        if (remaining > this.opts.leadTimeMs) continue;
        if (!grant.token.refreshToken) {
          await audit('refresh.skip', 'denied', {
            providerId,
            grantId: grant.grantId,
            detail: 'no_refresh_token',
          });
          continue;
        }
        try {
          await this.opts.orchestrator.refresh(grant);
        } catch (err) {
          this.opts.onFailure(grant, err);
          if (err instanceof OAuthError) {
            await audit('refresh.failure', 'error', {
              providerId,
              grantId: grant.grantId,
              detail: err.code,
            });
          } else {
            await audit('refresh.failure', 'error', {
              providerId,
              grantId: grant.grantId,
              detail: err instanceof Error ? err.message : 'unknown',
            });
          }
        }
      }
    }
  }
}

```
