---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/__tests__/freeness.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.481091+00:00
---

# packages/calendar/src/__tests__/freeness.test.ts

```ts
import { describe, expect, test, beforeEach, afterEach } from 'bun:test';
import { makeTestDb, d } from './setup.js';
import type { Database } from '@semantos/semantic-objects';
import {
  findFreeWindows,
  isWithinWorkingHours,
  DEFAULT_WORKING_HOURS,
} from '../policy/freeness.js';
import { bookSlot } from '../api/index.js';
import { createHat } from '../domain/hat.js';

describe('policy/freeness', () => {
  let db: Database;
  let close: () => Promise<void>;
  beforeEach(async () => { ({ db, close } = await makeTestDb()); });
  afterEach(async () => { await close(); });

  test('F1 isWithinWorkingHours Tue 10:00 UTC is true', () => {
    expect(
      isWithinWorkingHours(d('2026-03-10T10:00Z'), d('2026-03-10T11:00Z'), 'UTC', DEFAULT_WORKING_HOURS),
    ).toBe(true);
  });

  test('F2 Sunday is false (default working hours)', () => {
    expect(
      isWithinWorkingHours(d('2026-03-15T10:00Z'), d('2026-03-15T11:00Z'), 'UTC', DEFAULT_WORKING_HOURS),
    ).toBe(false);
  });

  test('F3 before 08:00 is false', () => {
    expect(
      isWithinWorkingHours(d('2026-03-10T07:00Z'), d('2026-03-10T08:00Z'), 'UTC', DEFAULT_WORKING_HOURS),
    ).toBe(false);
  });

  test('F4 after 18:00 is false', () => {
    expect(
      isWithinWorkingHours(d('2026-03-10T17:30Z'), d('2026-03-10T19:00Z'), 'UTC', DEFAULT_WORKING_HOURS),
    ).toBe(false);
  });

  test('F5 findFreeWindows returns windows on empty calendar', async () => {
    await createHat(db, {
      id: 'utc-hat',
      displayName: 'UTC hat',
      timezone: 'UTC',
      ownerCertId: 'cert-utc',
    });
    const windows = await findFreeWindows(db, {
      hatId: 'utc-hat',
      fromAt: d('2026-03-10T00:00Z'),
      toAt: d('2026-03-11T00:00Z'),
      durationMinutes: 60,
      limit: 3,
    });
    expect(windows.length).toBeGreaterThan(0);
    for (const w of windows) {
      expect(w.startAt.getUTCHours()).toBeGreaterThanOrEqual(8);
      expect(w.endAt.getUTCHours()).toBeLessThanOrEqual(18);
    }
  });

  test('F6 findFreeWindows skips an occupied slot (different hat, same stream)', async () => {
    await createHat(db, {
      id: 'utc-hat',
      displayName: 'UTC hat',
      timezone: 'UTC',
      ownerCertId: 'cert-utc',
    });
    // Block 10–12 via a DIFFERENT hat — should still block because it's the same stream.
    await bookSlot(db, {
      hatId: 'todd-handyman',
      startAt: d('2026-03-10T10:00Z'),
      endAt: d('2026-03-10T12:00Z'),
      subjectKind: 'manual',
      subjectId: 'blk',
      bookedByCertId: 'cert-todd',
    });
    const windows = await findFreeWindows(db, {
      hatId: 'utc-hat',
      fromAt: d('2026-03-10T09:00Z'),
      toAt: d('2026-03-10T14:00Z'),
      durationMinutes: 60,
      limit: 10,
    });
    for (const w of windows) {
      expect(
        w.startAt.getTime() >= d('2026-03-10T12:00Z').getTime() ||
          w.endAt.getTime() <= d('2026-03-10T10:00Z').getTime(),
      ).toBe(true);
    }
  });

  test('F7 limit caps returned windows', async () => {
    await createHat(db, {
      id: 'utc-hat',
      displayName: 'UTC hat',
      timezone: 'UTC',
      ownerCertId: 'cert-utc',
    });
    const windows = await findFreeWindows(db, {
      hatId: 'utc-hat',
      fromAt: d('2026-03-10T00:00Z'),
      toAt: d('2026-03-12T00:00Z'),
      durationMinutes: 60,
      limit: 2,
    });
    expect(windows.length).toBeLessThanOrEqual(2);
  });

  test('F8 weekendsEnabled opens Sat/Sun', async () => {
    await createHat(db, {
      id: 'utc-247',
      displayName: 'UTC 24-7',
      timezone: 'UTC',
      weekendsEnabled: true,
      ownerCertId: 'cert-utc',
    });
    const windows = await findFreeWindows(db, {
      hatId: 'utc-247',
      fromAt: d('2026-03-14T00:00Z'), // Saturday
      toAt: d('2026-03-15T00:00Z'),
      durationMinutes: 60,
      limit: 1,
    });
    expect(windows.length).toBe(1);
  });
});

```
