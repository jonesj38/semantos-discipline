---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/migrations/012_region_ticks_pravega.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.142115+00:00
---

# db/postgres/migrations/012_region_ticks_pravega.sql

```sql
-- 012_region_ticks_pravega.sql
--
-- M5.6: region_ticks_pravega FDW-lite staging table + refresh/prune functions
--
-- Implements the "FDW-lite" refresh pattern for the Pravega `region_ticks`
-- stream.  A background Go gateway periodically reads Pravega segments and
-- calls refresh_region_ticks_pravega(JSONB) to upsert events into the staging
-- table.  No native C extension or Python runtime required.
--
-- Wire schema (from runtime/wsh/src/region_tick_producer.zig):
--   region_id    TEXT   — region identifier
--   tick         u64    — monotonic tick counter within the region
--   ts_ms        u64    — wall-clock timestamp (milliseconds since epoch)
--   merkle_root  TEXT   — 64 hex chars → 32 bytes BYTEA
--
-- Functions provided:
--   refresh_region_ticks_pravega(events JSONB) RETURNS INT
--   prune_region_ticks_before(cutoff_ms BIGINT) RETURNS INT
--
-- Source-of-truth:
--   docs/prd/M5.6 — FDW spike: region_ticks_pravega foreign table.
--   Follows the pattern of 009_cells_lmdb_fdw.sql, 010_audit_log_fdw.sql,
--   and 011_pask_fdw_plumbing.sql.

-- ── region_ticks_pravega ──────────────────────────────────────────────────
--
-- Staging table for Pravega region-tick events.
-- PRIMARY KEY (region_id, tick) enforces exactly-once semantics per tick.

CREATE TABLE IF NOT EXISTS region_ticks_pravega (
    region_id        TEXT        NOT NULL,
    tick             BIGINT      NOT NULL,
    ts_ms            BIGINT      NOT NULL,
    merkle_root      BYTEA       NOT NULL,
    ingested_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (region_id, tick)
);

-- Supports efficient range scans: most-recent ticks first within a region.
CREATE INDEX IF NOT EXISTS idx_rtp_region_tick
    ON region_ticks_pravega (region_id, tick DESC);

-- ── refresh_region_ticks_pravega ──────────────────────────────────────────
--
-- refresh_region_ticks_pravega(events JSONB) RETURNS INT
--
-- Accepts a JSONB array of tick-event objects emitted by the Pravega
-- region_ticks stream.  Each element:
--   region_id    TEXT   — region identifier
--   tick         u64    — as a JSON number (fits BIGINT)
--   ts_ms        u64    — milliseconds since epoch
--   merkle_root  TEXT   — 64 hex chars; decoded to 32-byte BYTEA via
--                         decode(value, 'hex')
--
-- Upsert semantics: ON CONFLICT (region_id, tick) the row is updated so
-- that replaying the same Pravega segment twice is idempotent.
-- Returns total rows inserted or updated.

CREATE OR REPLACE FUNCTION refresh_region_ticks_pravega(events JSONB)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
  event    JSONB;
  affected INT := 0;
  n        INT;
BEGIN
  FOR event IN SELECT jsonb_array_elements(events)
  LOOP
    INSERT INTO region_ticks_pravega (
      region_id,
      tick,
      ts_ms,
      merkle_root
    )
    VALUES (
      event->>'region_id',
      (event->>'tick')::BIGINT,
      (event->>'ts_ms')::BIGINT,
      decode(event->>'merkle_root', 'hex')
    )
    ON CONFLICT (region_id, tick) DO UPDATE SET
      ts_ms       = EXCLUDED.ts_ms,
      merkle_root = EXCLUDED.merkle_root,
      ingested_at = now();

    GET DIAGNOSTICS n = ROW_COUNT;
    affected := affected + n;
  END LOOP;

  RETURN affected;
END;
$$;

-- ── prune_region_ticks_before ─────────────────────────────────────────────
--
-- prune_region_ticks_before(cutoff_ms BIGINT) RETURNS INT
--
-- Hard-deletes rows where ts_ms < cutoff_ms.  Used by the refresh pipeline
-- to bound table growth after a configurable retention window.
-- Returns count of rows deleted.

CREATE OR REPLACE FUNCTION prune_region_ticks_before(cutoff_ms BIGINT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
  deleted INT;
BEGIN
  DELETE FROM region_ticks_pravega
  WHERE ts_ms < cutoff_ms;

  GET DIAGNOSTICS deleted = ROW_COUNT;
  RETURN deleted;
END;
$$;

```
