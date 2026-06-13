---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/migrations/0000_calendar_init.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.478066+00:00
---

# packages/calendar/migrations/0000_calendar_init.sql

```sql
-- @semantos/calendar-ext — initial migration.
--
-- The canonical substrate tables (sem_objects, sem_object_patches,
-- sem_object_states, sem_participants) ship with @semantos/semantic-objects.
-- Apply its migration before this one:
--
--   psql $CALENDAR_DATABASE_URL -f node_modules/@semantos/semantic-objects/migrations/0000_init.sql
--   psql $CALENDAR_DATABASE_URL -f node_modules/@semantos/calendar-ext/migrations/0000_calendar_init.sql
--
-- This migration is intentionally empty — the calendar extension contributes
-- no new tables. Schedules, hats, holds, and bookings are all sem_objects
-- rows + patches written via @semantos/semantic-objects's operations.
--
-- At deploy time, call:
--   await seedSchedule(db, { ownerCertId, timezone, scheduleObjectId })
--   await seedHats(db, readSeedEnv())
-- to UPSERT the schedule + hat topology.

-- Intentionally no DDL statements here.
SELECT 1;

```
