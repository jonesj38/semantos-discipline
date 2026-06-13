---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/logger.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.344919+00:00
---

# runtime/intent/src/logger.ts

```ts
/**
 * Intent pipeline — observability.
 *
 * ~30 LOC budget per docs/INTENT-PIPELINE.md §"Default sink". The
 * pipeline calls `logger.emit(event)` at every stage boundary;
 * every event carries the Intent's correlationId. A failed turn
 * becomes a single grep.
 *
 * Two built-in sinks:
 *   - createJsonlStderrLogger() — zero-infra default; one JSON
 *     line per event on stderr, ships to any collector tomorrow
 *     without code changes.
 *   - createInMemoryLogger() — tests assert against .events[].
 *
 * Production deployments plug in structured sinks by implementing
 * the Logger interface; pipeline code doesn't change.
 */

import type { StageEvent, Logger } from './types';

// Re-export so consumers can import Logger from here without going
// through types.ts. types.ts forward-declares the same interface to
// avoid a circular dep with IntentContext.
export type { Logger, StageEvent } from './types';

/** Default sink: one JSON line per event on stderr. */
export function createJsonlStderrLogger(): Logger {
  return {
    emit(event: StageEvent): void {
      // Bun/Node both expose process.stderr.write; fall back to
      // console.error for any unusual runtime.
      const line = JSON.stringify(event);
      const stderr =
        typeof process !== 'undefined' && process.stderr
          ? process.stderr
          : null;
      if (stderr) {
        stderr.write(line + '\n');
      } else {
        // eslint-disable-next-line no-console
        console.error(line);
      }
    },
  };
}

/** In-memory sink for tests. Events accumulate in insertion order. */
export interface InMemoryLogger extends Logger {
  readonly events: readonly StageEvent[];
  clear(): void;
}

export function createInMemoryLogger(): InMemoryLogger {
  const events: StageEvent[] = [];
  return {
    emit(event: StageEvent): void {
      events.push(event);
    },
    get events(): readonly StageEvent[] {
      return events;
    },
    clear(): void {
      events.length = 0;
    },
  };
}

```
