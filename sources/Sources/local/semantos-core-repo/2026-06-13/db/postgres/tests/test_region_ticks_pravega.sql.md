---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/tests/test_region_ticks_pravega.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.135056+00:00
---

# db/postgres/tests/test_region_ticks_pravega.sql

```sql
-- M5.6 tests — region_ticks_pravega FDW-lite (refresh + prune)
--
-- Tests:
--   M5.6-T-refresh-inserts-rows   — refresh with 3-item array → count=3 and rows present
--   M5.6-T-refresh-idempotent     — refresh twice with same data → only 3 rows (no duplicates)
--   M5.6-T-ordering-preserved     — ticks 3,1,2 same region → ORDER BY tick ASC yields 1,2,3
--   M5.6-T-merkle-root-decode     — inserted merkle_root BYTEA length = 32 bytes
--   M5.6-T-prune-deletes-old      — prune_region_ticks_before removes rows below cutoff_ms
--
-- Run via:
--   psql -v ON_ERROR_STOP=1 -f db/postgres/tests/test_region_ticks_pravega.sql

\set ON_ERROR_STOP on

BEGIN;

\i db/postgres/migrations/001_cert_dag.sql
\i db/postgres/migrations/002_lexicon_category.sql
\i db/postgres/migrations/003_sir_program.sql
\i db/postgres/migrations/004_session_chain.sql
\i db/postgres/migrations/005_pask_tables.sql
\i db/postgres/migrations/006_cert_dag_populator.sql
\i db/postgres/migrations/007_helm_learned_view.sql
\i db/postgres/migrations/008_octave_registry.sql
\i db/postgres/migrations/009_cells_lmdb_fdw.sql
\i db/postgres/migrations/010_audit_log_fdw.sql
\i db/postgres/migrations/011_pask_fdw_plumbing.sql
\i db/postgres/migrations/012_region_ticks_pravega.sql

-- ── M5.6-T-refresh-inserts-rows ──────────────────────────────────────────
-- Call refresh with a 3-item JSONB array; assert count=3 and rows present.

DO $$
DECLARE
  inserted   INT;
  row_count  INT;
  payload    JSONB;
BEGIN
  payload := jsonb_build_array(
    jsonb_build_object(
      'region_id',   'region-alpha',
      'tick',        1,
      'ts_ms',       1700000001000,
      'merkle_root', lpad('', 64, 'ab')
    ),
    jsonb_build_object(
      'region_id',   'region-alpha',
      'tick',        2,
      'ts_ms',       1700000002000,
      'merkle_root', lpad('', 64, 'cd')
    ),
    jsonb_build_object(
      'region_id',   'region-beta',
      'tick',        1,
      'ts_ms',       1700000003000,
      'merkle_root', lpad('', 64, 'ef')
    )
  );

  SELECT refresh_region_ticks_pravega(payload) INTO inserted;

  IF inserted <> 3 THEN
    RAISE EXCEPTION 'M5.6-T-refresh-inserts-rows FAILED: expected count=3, got %', inserted;
  END IF;

  SELECT COUNT(*) INTO row_count FROM region_ticks_pravega;

  IF row_count <> 3 THEN
    RAISE EXCEPTION 'M5.6-T-refresh-inserts-rows FAILED: expected 3 rows in table, got %', row_count;
  END IF;
END $$;

\echo 'M5.6-T-refresh-inserts-rows PASSED'

-- ── M5.6-T-refresh-idempotent ────────────────────────────────────────────
-- Call refresh twice with the same 3-item payload; assert only 3 rows remain.

DO $$
DECLARE
  first_count  INT;
  second_count INT;
  row_count    INT;
  payload      JSONB;
BEGIN
  payload := jsonb_build_array(
    jsonb_build_object(
      'region_id',   'region-idem',
      'tick',        10,
      'ts_ms',       1700000010000,
      'merkle_root', lpad('', 64, '11')
    ),
    jsonb_build_object(
      'region_id',   'region-idem',
      'tick',        11,
      'ts_ms',       1700000011000,
      'merkle_root', lpad('', 64, '22')
    ),
    jsonb_build_object(
      'region_id',   'region-idem',
      'tick',        12,
      'ts_ms',       1700000012000,
      'merkle_root', lpad('', 64, '33')
    )
  );

  SELECT refresh_region_ticks_pravega(payload) INTO first_count;
  SELECT refresh_region_ticks_pravega(payload) INTO second_count;

  SELECT COUNT(*) INTO row_count
  FROM region_ticks_pravega
  WHERE region_id = 'region-idem';

  IF row_count <> 3 THEN
    RAISE EXCEPTION 'M5.6-T-refresh-idempotent FAILED: expected 3 rows after double refresh, got %', row_count;
  END IF;
END $$;

\echo 'M5.6-T-refresh-idempotent PASSED'

-- ── M5.6-T-ordering-preserved ────────────────────────────────────────────
-- Insert ticks 3, 1, 2 for the same region; select ORDER BY tick ASC → 1, 2, 3.

DO $$
DECLARE
  t1  BIGINT;
  t2  BIGINT;
  t3  BIGINT;
  payload JSONB;
BEGIN
  payload := jsonb_build_array(
    jsonb_build_object(
      'region_id',   'region-order',
      'tick',        3,
      'ts_ms',       1700000030000,
      'merkle_root', lpad('', 64, 'aa')
    ),
    jsonb_build_object(
      'region_id',   'region-order',
      'tick',        1,
      'ts_ms',       1700000010000,
      'merkle_root', lpad('', 64, 'bb')
    ),
    jsonb_build_object(
      'region_id',   'region-order',
      'tick',        2,
      'ts_ms',       1700000020000,
      'merkle_root', lpad('', 64, 'cc')
    )
  );

  PERFORM refresh_region_ticks_pravega(payload);

  SELECT tick INTO t1 FROM region_ticks_pravega
  WHERE region_id = 'region-order' ORDER BY tick ASC LIMIT 1 OFFSET 0;

  SELECT tick INTO t2 FROM region_ticks_pravega
  WHERE region_id = 'region-order' ORDER BY tick ASC LIMIT 1 OFFSET 1;

  SELECT tick INTO t3 FROM region_ticks_pravega
  WHERE region_id = 'region-order' ORDER BY tick ASC LIMIT 1 OFFSET 2;

  IF t1 <> 1 OR t2 <> 2 OR t3 <> 3 THEN
    RAISE EXCEPTION 'M5.6-T-ordering-preserved FAILED: expected 1,2,3 got %,%,%', t1, t2, t3;
  END IF;
END $$;

\echo 'M5.6-T-ordering-preserved PASSED'

-- ── M5.6-T-merkle-root-decode ────────────────────────────────────────────
-- Inserted merkle_root (64 hex chars) must be stored as 32-byte BYTEA.

DO $$
DECLARE
  blen   INT;
  payload JSONB;
BEGIN
  payload := jsonb_build_array(
    jsonb_build_object(
      'region_id',   'region-merkle',
      'tick',        99,
      'ts_ms',       1700000099000,
      'merkle_root', lpad('', 64, 'de')
    )
  );

  PERFORM refresh_region_ticks_pravega(payload);

  SELECT octet_length(merkle_root) INTO blen
  FROM region_ticks_pravega
  WHERE region_id = 'region-merkle' AND tick = 99;

  IF blen <> 32 THEN
    RAISE EXCEPTION 'M5.6-T-merkle-root-decode FAILED: expected 32 bytes, got %', blen;
  END IF;
END $$;

\echo 'M5.6-T-merkle-root-decode PASSED'

-- ── M5.6-T-prune-deletes-old ─────────────────────────────────────────────
-- Insert rows with old and new ts_ms; prune with cutoff; assert old rows gone,
-- new rows retained.

DO $$
DECLARE
  deleted   INT;
  remaining INT;
  payload   JSONB;
BEGIN
  payload := jsonb_build_array(
    -- old row: ts_ms = 1000 (below cutoff 5000)
    jsonb_build_object(
      'region_id',   'region-prune',
      'tick',        1,
      'ts_ms',       1000,
      'merkle_root', lpad('', 64, 'a0')
    ),
    -- old row: ts_ms = 4999 (below cutoff 5000)
    jsonb_build_object(
      'region_id',   'region-prune',
      'tick',        2,
      'ts_ms',       4999,
      'merkle_root', lpad('', 64, 'b0')
    ),
    -- new row: ts_ms = 5000 (at cutoff, NOT pruned — cutoff is exclusive)
    jsonb_build_object(
      'region_id',   'region-prune',
      'tick',        3,
      'ts_ms',       5000,
      'merkle_root', lpad('', 64, 'c0')
    ),
    -- new row: ts_ms = 9999 (above cutoff)
    jsonb_build_object(
      'region_id',   'region-prune',
      'tick',        4,
      'ts_ms',       9999,
      'merkle_root', lpad('', 64, 'd0')
    )
  );

  PERFORM refresh_region_ticks_pravega(payload);

  -- Prune rows with ts_ms < 5000
  SELECT prune_region_ticks_before(5000) INTO deleted;

  IF deleted <> 2 THEN
    RAISE EXCEPTION 'M5.6-T-prune-deletes-old FAILED: expected 2 deleted, got %', deleted;
  END IF;

  SELECT COUNT(*) INTO remaining
  FROM region_ticks_pravega
  WHERE region_id = 'region-prune';

  IF remaining <> 2 THEN
    RAISE EXCEPTION 'M5.6-T-prune-deletes-old FAILED: expected 2 rows remaining, got %', remaining;
  END IF;
END $$;

\echo 'M5.6-T-prune-deletes-old PASSED'

ROLLBACK;

\echo ''
\echo 'All M5.6 region_ticks_pravega tests PASSED'

```
