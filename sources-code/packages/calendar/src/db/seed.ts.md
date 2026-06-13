---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/db/seed.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.484976+00:00
---

# packages/calendar/src/db/seed.ts

```ts
/**
 * Seed the schedule + hat topology at deploy time.
 *
 * The schedule is ONE `sem_objects` row (`object_kind: 'schedule'`). Each
 * operator hat is also a `sem_objects` row (`object_kind: 'hat'`) — hats
 * carry display/timezone metadata but don't own patch streams.
 *
 * Env contract (consumed by VPS-BOOTSTRAP's seed step):
 *   CAL_OWNER_CERT_ID        — operator cert that owns the schedule
 *   CAL_SCHEDULE_OBJECT_ID   — id for the schedule (default: 'schedule-primary')
 *   CAL_TIMEZONE             — IANA tz (default: 'UTC')
 *   CAL_OPERATOR_HAT_ID      — root hat id (default: 'operator')
 *   CAL_OPERATOR_DISPLAY_NAME
 *   CAL_CHILD_HATS           — JSON array of {id, displayName, weekendsEnabled?}
 */
import {
  createObject,
  getObject,
  addParticipant,
  listParticipants,
  type Database,
} from '@semantos/semantic-objects';
import {
  DEFAULT_SCHEDULE_OBJECT_ID,
  resolveScheduleObjectId,
} from '../domain/schedule.js';
import { createHat, getHat } from '../domain/hat.js';

export interface SeedInput {
  ownerCertId: string;
  timezone?: string;
  scheduleObjectId?: string;
  operatorHatId?: string;
  operatorDisplayName?: string;
  childHats?: Array<{
    id: string;
    displayName: string;
    weekendsEnabled?: boolean;
  }>;
}

export function readSeedEnv(env: NodeJS.ProcessEnv = process.env): SeedInput {
  const ownerCertId = env.CAL_OWNER_CERT_ID;
  if (!ownerCertId) {
    throw new Error('CAL_OWNER_CERT_ID is required to seed the calendar');
  }
  const childHatsRaw = env.CAL_CHILD_HATS;
  let childHats: SeedInput['childHats'] = [];
  if (childHatsRaw) {
    try {
      childHats = JSON.parse(childHatsRaw);
      if (!Array.isArray(childHats)) {
        throw new Error('CAL_CHILD_HATS must be a JSON array');
      }
    } catch (err) {
      throw new Error(
        `CAL_CHILD_HATS is not valid JSON: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
  }
  return {
    ownerCertId,
    timezone: env.CAL_TIMEZONE ?? 'UTC',
    scheduleObjectId: env.CAL_SCHEDULE_OBJECT_ID ?? DEFAULT_SCHEDULE_OBJECT_ID,
    operatorHatId: env.CAL_OPERATOR_HAT_ID ?? 'operator',
    operatorDisplayName: env.CAL_OPERATOR_DISPLAY_NAME ?? 'Operator',
    childHats,
  };
}

export interface SchedulePayload {
  operatorCertId: string;
  timezone: string;
  createdAtIso: string;
}

/**
 * Seed the schedule object + operator as admin participant. Idempotent.
 */
export async function seedSchedule(
  db: Database,
  input: { ownerCertId: string; timezone?: string; scheduleObjectId?: string },
): Promise<void> {
  const scheduleId = input.scheduleObjectId ?? resolveScheduleObjectId();
  const existing = await getObject<SchedulePayload>(db, scheduleId);
  if (!existing) {
    await createObject<SchedulePayload>(db, {
      id: scheduleId,
      objectKind: 'schedule',
      payload: {
        operatorCertId: input.ownerCertId,
        timezone: input.timezone ?? 'UTC',
        createdAtIso: new Date().toISOString(),
      },
      createdByCertId: input.ownerCertId,
    });
  }

  const existingParticipants = await listParticipants(db, scheduleId);
  const already = existingParticipants.find(
    (p) => p.identityRef === input.ownerCertId && p.participantRole === 'admin',
  );
  if (!already) {
    await addParticipant(db, {
      objectId: scheduleId,
      identityRef: input.ownerCertId,
      identityKind: 'cert',
      participantRole: 'admin',
      displayName: 'Operator',
    });
  }
}

/**
 * Seed the hat topology: one operator + N child hats. Idempotent — hats
 * that already exist are skipped (no overwrite of their payload).
 */
export async function seedHats(db: Database, input: SeedInput): Promise<void> {
  const tz = input.timezone ?? 'UTC';
  const operatorId = input.operatorHatId ?? 'operator';
  const operatorName = input.operatorDisplayName ?? 'Operator';

  const existingOperator = await getHat(db, operatorId);
  if (!existingOperator) {
    await createHat(db, {
      id: operatorId,
      displayName: operatorName,
      timezone: tz,
      weekendsEnabled: false,
      ownerCertId: input.ownerCertId,
    });
  }

  for (const child of input.childHats ?? []) {
    const existing = await getHat(db, child.id);
    if (existing) continue;
    await createHat(db, {
      id: child.id,
      parentHatId: operatorId,
      displayName: child.displayName,
      timezone: tz,
      weekendsEnabled: child.weekendsEnabled ?? false,
      ownerCertId: input.ownerCertId,
    });
  }
}

/**
 * One-shot: seed schedule + hats together.
 */
export async function seedAll(db: Database, input: SeedInput): Promise<void> {
  await seedSchedule(db, {
    ownerCertId: input.ownerCertId,
    timezone: input.timezone,
    scheduleObjectId: input.scheduleObjectId,
  });
  await seedHats(db, input);
}

```
