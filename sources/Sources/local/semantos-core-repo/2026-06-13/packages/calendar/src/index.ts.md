---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.477436+00:00
---

# packages/calendar/src/index.ts

```ts
/**
 * @semantos/calendar-ext — calendar as a semantic object.
 *
 * One schedule aggregate owns a single append-only patch stream.
 * Every hold/book/release/cancel is a patch. State = fold the stream.
 * Hats attribute patches (metadata) but don't own their own streams.
 *
 * See README.md for the model + rationale.
 */
export * from './api/index.js';
export { seedSchedule, seedHats, seedAll, readSeedEnv } from './db/seed.js';
export type { SeedInput, SchedulePayload } from './db/seed.js';
export {
  createHat,
  getHat,
  listHats,
  hatIdOf,
  deriveHatCertId,
  buildHatCert,
  type HatPayload,
  type HatRecord,
  type HatCertBacking,
  type HatCertSpec,
  type CreateHatInput,
} from './domain/hat.js';
export { CalendarLexicon, type CalendarCategory } from './lexicon/index.js';

// A5 — CalendarGuard factory for @semantos/intent.handleMessage injection.
export { createCalendarGuard } from './guard.js';
export type { CalendarGuardOptions } from './guard.js';

export type { Database } from '@semantos/semantic-objects';

```
