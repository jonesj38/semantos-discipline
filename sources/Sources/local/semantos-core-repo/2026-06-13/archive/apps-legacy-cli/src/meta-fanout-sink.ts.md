---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-legacy-cli/src/meta-fanout-sink.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.697710+00:00
---

# archive/apps-legacy-cli/src/meta-fanout-sink.ts

```ts
/**
 * D-OJ-conv-meta-inbox-bridge — meta-scoped canonical fan-out sink.
 *
 * Composes the legacy `JsonlConversationTurnPatchSink.append` with the
 * canonical `makeCanonicalTurnSink` from the `@semantos/oddjobz` cartridge.
 *
 * ## Meta-scope filter
 *
 * The canonical sink fires ONLY for events where `event.providerId === 'meta'`
 * (channels `meta_messenger` / `meta_instagram`). Widget events
 * (`providerId === 'widget'`) are intentionally EXCLUDED: the cartridge's
 * `intake-handler.ts` already owns canonical `'widget'` turns (#555), so
 * wiring widget here too would DOUBLE-WRITE. This is the explicit scope
 * decision from Todd (2026-05-22): widget de-dup is deferred and evidence-based.
 *
 * ## Fan-out discipline
 *
 * Both sides of the fan-out fire for EVERY event (legacy sink for all providers,
 * canonical sink for meta-only). The canonical sink failure is ISOLATED: a
 * canonical-sink error MUST NOT break the legacy `messagePatchSink.append` or
 * the reply. This mirrors the bridge's swallow-errors discipline.
 *
 * ## DATABASE_URL gate
 *
 * When `db` is `null` (i.e. `getDatabaseOrNull()` returned null because
 * `DATABASE_URL` is unset), `makeMetaFanOutSink` returns a NO-OP canonical
 * side, and only the legacy sink fires. This means:
 *   - The sink is safe to land in production BEFORE `DATABASE_URL` is set.
 *   - It activates automatically once (a) `DATABASE_URL` is set and
 *     (b) meta webhooks deliver.
 *
 * ## Meta-account dormancy
 *
 * Todd's Meta account is currently RESTRICTED (not yet unrestricted).
 * Live meta DM traffic may not flow until he enables it. This wiring is
 * therefore ADDITIVE + GATED + DORMANT-UNTIL-ENABLED.
 *
 * ## No self-call deadlock
 *
 * `makeCanonicalTurnSink(db)` writes directly to Postgres (external). It
 * does NOT call back into the brain's HTTP/REPL. Per project memory
 * `semantos_brain_single_threaded_reactor`, the legacy-cli is its own
 * process (one-shot/serve), not the brain reactor.
 */

import type { ConversationTurnEvent, ConversationTurnSink } from '@semantos/legacy-ingest';
import type { Database } from '@semantos/semantic-objects';
import { makeCanonicalTurnSink } from '@semantos/oddjobz/conversation/legacy-ingest-bridge';

export interface MakeMetaFanOutSinkOpts {
  /**
   * The legacy sink to call for ALL events (both meta and widget).
   * This is `messagePatchSink.append` from `bootstrap.ts`.
   */
  readonly legacySink: ConversationTurnSink;

  /**
   * Database handle from `getDatabaseOrNull()`. When `null`, the
   * canonical side is a no-op (legacy sink unaffected).
   */
  readonly db: Database | null;

  /**
   * Override for the canonical sink (for tests that inject a pre-built
   * canonical sink). When provided, `db` is ignored.
   */
  readonly canonicalSinkOverride?: ConversationTurnSink | null;
}

/**
 * Create a fan-out `ConversationTurnSink` that:
 *   1. Always calls `legacySink(event)` (legacy JSONL path — ALL providers).
 *   2. For META events only (`event.providerId === 'meta'`), also calls
 *      the canonical sink to persist the turn via `makeCanonicalTurnSink`.
 *   3. Canonical sink failures are isolated — legacy always fires.
 *   4. When `db === null`, the canonical side is a no-op.
 *
 * This is the composition-root wiring for D-OJ-conv-meta-inbox-bridge.
 */
export function makeMetaFanOutSink(opts: MakeMetaFanOutSinkOpts): ConversationTurnSink {
  const { legacySink, db, canonicalSinkOverride } = opts;

  // Resolve the canonical sink: injected override → db → null no-op
  const canonicalSink: ConversationTurnSink | null =
    canonicalSinkOverride !== undefined
      ? canonicalSinkOverride
      : db !== null
        ? makeCanonicalTurnSink(db)
        : null;

  return async (event: ConversationTurnEvent): Promise<void> => {
    // 1. Legacy sink fires for ALL providers unconditionally.
    //    Do not let canonical failures reach this await.
    await Promise.resolve(legacySink(event));

    // 2. Canonical sink fires for META channels only.
    //    Isolated: failure here MUST NOT propagate.
    if (event.providerId !== 'meta') return;
    if (!canonicalSink) return;

    try {
      await canonicalSink(event);
    } catch {
      // Best-effort: swallow canonical-sink failures. The legacy JSONL
      // path is the authoritative durable log; this canonical sink is additive.
    }
  };
}

```
