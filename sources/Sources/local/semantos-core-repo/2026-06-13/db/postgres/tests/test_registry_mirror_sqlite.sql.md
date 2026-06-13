---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/tests/test_registry_mirror_sqlite.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.139024+00:00
---

# db/postgres/tests/test_registry_mirror_sqlite.sql

```sql
-- M6.4 tests — registry_mirror_sqlite browser-side registry mirror
--
-- Tests:
--   M6.4-T-refresh-inserts      — refresh with 1-item array → returns 1, row present
--   M6.4-T-refresh-idempotent   — same event twice → second call returns 0 (seq not higher)
--   M6.4-T-seq-ordering         — higher seq updates state; lower seq does NOT overwrite
--   M6.4-T-state-valid          — insert 'unspent' then update to 'spent' → state='spent'
--   M6.4-T-prune-spent          — insert spent row, prune_registry_mirror_spent(0) → returns 1, row gone
--
-- Run via:
--   psql -v ON_ERROR_STOP=1 -f db/postgres/tests/test_registry_mirror_sqlite.sql

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
\i db/postgres/migrations/013_registry_mirror_sqlite.sql

-- ── M6.4-T-refresh-inserts ───────────────────────────────────────────────
-- Call refresh_registry_mirror with a single insert event; assert return=1
-- and the row is present in the table.

DO $$
DECLARE
  inserted  INT;
  row_state TEXT;
  payload   JSONB;
BEGIN
  payload := jsonb_build_array(
    jsonb_build_object(
      'kind',         'insert',
      'cell_id',      'aabb',
      'domain_flag',  1,
      'new_state',    'unspent',
      'octave_level', 0,
      'seq',          0,
      'ts_ms',        1000
    )
  );

  SELECT refresh_registry_mirror(payload) INTO inserted;

  IF inserted <> 1 THEN
    RAISE EXCEPTION 'M6.4-T-refresh-inserts FAILED: expected return=1, got %', inserted;
  END IF;

  SELECT state INTO row_state
  FROM registry_mirror_sqlite
  WHERE cell_id_hex = 'aabb' AND domain_flag = 1;

  IF row_state IS NULL THEN
    RAISE EXCEPTION 'M6.4-T-refresh-inserts FAILED: row not found after insert';
  END IF;

  IF row_state <> 'unspent' THEN
    RAISE EXCEPTION 'M6.4-T-refresh-inserts FAILED: expected state=unspent, got %', row_state;
  END IF;
END $$;

\echo 'M6.4-T-refresh-inserts PASSED'

-- ── M6.4-T-refresh-idempotent ────────────────────────────────────────────
-- Call refresh_registry_mirror twice with the identical event (same seq).
-- The second call must return 0 because seq is not higher than existing.

DO $$
DECLARE
  first_count  INT;
  second_count INT;
  payload      JSONB;
BEGIN
  payload := jsonb_build_array(
    jsonb_build_object(
      'kind',         'insert',
      'cell_id',      'ccdd',
      'domain_flag',  2,
      'new_state',    'unspent',
      'octave_level', 1,
      'seq',          10,
      'ts_ms',        2000
    )
  );

  SELECT refresh_registry_mirror(payload) INTO first_count;
  SELECT refresh_registry_mirror(payload) INTO second_count;

  IF first_count <> 1 THEN
    RAISE EXCEPTION 'M6.4-T-refresh-idempotent FAILED: first call expected 1, got %', first_count;
  END IF;

  IF second_count <> 0 THEN
    RAISE EXCEPTION 'M6.4-T-refresh-idempotent FAILED: second call expected 0 (idempotent), got %', second_count;
  END IF;
END $$;

\echo 'M6.4-T-refresh-idempotent PASSED'

-- ── M6.4-T-seq-ordering ──────────────────────────────────────────────────
-- Insert a row at seq=5. A higher-seq event (seq=10) MUST update state.
-- A lower-seq event (seq=3) must NOT overwrite the state set by seq=10.

DO $$
DECLARE
  state_after_high TEXT;
  state_after_low  TEXT;
  payload_base     JSONB;
  payload_high     JSONB;
  payload_low      JSONB;
BEGIN
  -- Initial insert at seq=5, state='unspent'
  payload_base := jsonb_build_array(
    jsonb_build_object(
      'kind',         'insert',
      'cell_id',      'eeff',
      'domain_flag',  3,
      'new_state',    'unspent',
      'octave_level', 0,
      'seq',          5,
      'ts_ms',        3000
    )
  );
  PERFORM refresh_registry_mirror(payload_base);

  -- Higher seq=10 event updates state to 'locked'
  payload_high := jsonb_build_array(
    jsonb_build_object(
      'kind',         'state_change',
      'cell_id',      'eeff',
      'domain_flag',  3,
      'new_state',    'locked',
      'octave_level', 0,
      'seq',          10,
      'ts_ms',        4000
    )
  );
  PERFORM refresh_registry_mirror(payload_high);

  SELECT state INTO state_after_high
  FROM registry_mirror_sqlite
  WHERE cell_id_hex = 'eeff' AND domain_flag = 3;

  IF state_after_high <> 'locked' THEN
    RAISE EXCEPTION 'M6.4-T-seq-ordering FAILED: expected state=locked after high-seq, got %', state_after_high;
  END IF;

  -- Lower seq=3 event tries to set state back to 'spent' — must be ignored
  payload_low := jsonb_build_array(
    jsonb_build_object(
      'kind',         'state_change',
      'cell_id',      'eeff',
      'domain_flag',  3,
      'new_state',    'spent',
      'octave_level', 0,
      'seq',          3,
      'ts_ms',        1000
    )
  );
  PERFORM refresh_registry_mirror(payload_low);

  SELECT state INTO state_after_low
  FROM registry_mirror_sqlite
  WHERE cell_id_hex = 'eeff' AND domain_flag = 3;

  IF state_after_low <> 'locked' THEN
    RAISE EXCEPTION 'M6.4-T-seq-ordering FAILED: low-seq must not overwrite; expected locked, got %', state_after_low;
  END IF;
END $$;

\echo 'M6.4-T-seq-ordering PASSED'

-- ── M6.4-T-state-valid ───────────────────────────────────────────────────
-- Insert a row with state='unspent', then apply an update event with
-- state='spent' at a higher seq. Final state must be 'spent'.

DO $$
DECLARE
  final_state TEXT;
  payload_ins JSONB;
  payload_upd JSONB;
BEGIN
  payload_ins := jsonb_build_array(
    jsonb_build_object(
      'kind',         'insert',
      'cell_id',      '1122',
      'domain_flag',  4,
      'new_state',    'unspent',
      'octave_level', 2,
      'seq',          100,
      'ts_ms',        5000
    )
  );
  PERFORM refresh_registry_mirror(payload_ins);

  payload_upd := jsonb_build_array(
    jsonb_build_object(
      'kind',         'state_change',
      'cell_id',      '1122',
      'domain_flag',  4,
      'new_state',    'spent',
      'octave_level', 2,
      'seq',          200,
      'ts_ms',        6000
    )
  );
  PERFORM refresh_registry_mirror(payload_upd);

  SELECT state INTO final_state
  FROM registry_mirror_sqlite
  WHERE cell_id_hex = '1122' AND domain_flag = 4;

  IF final_state <> 'spent' THEN
    RAISE EXCEPTION 'M6.4-T-state-valid FAILED: expected state=spent, got %', final_state;
  END IF;
END $$;

\echo 'M6.4-T-state-valid PASSED'

-- ── M6.4-T-prune-spent ───────────────────────────────────────────────────
-- Insert a row with state='spent'. Call prune_registry_mirror_spent(0)
-- (older_than_ms=0 prunes all spent rows instantly). Assert return=1 and
-- the row is gone from the table.

DO $$
DECLARE
  pruned    INT;
  row_count INT;
  payload   JSONB;
BEGIN
  payload := jsonb_build_array(
    jsonb_build_object(
      'kind',         'state_change',
      'cell_id',      '3344',
      'domain_flag',  5,
      'new_state',    'spent',
      'octave_level', 0,
      'seq',          50,
      'ts_ms',        7000
    )
  );
  PERFORM refresh_registry_mirror(payload);

  -- Confirm row was inserted
  SELECT COUNT(*) INTO row_count
  FROM registry_mirror_sqlite
  WHERE cell_id_hex = '3344' AND domain_flag = 5;

  IF row_count <> 1 THEN
    RAISE EXCEPTION 'M6.4-T-prune-spent FAILED: setup: expected 1 row before prune, got %', row_count;
  END IF;

  -- Prune with older_than_ms=0 → prunes all spent rows (elapsed > 0 ms)
  SELECT prune_registry_mirror_spent(0) INTO pruned;

  IF pruned < 1 THEN
    RAISE EXCEPTION 'M6.4-T-prune-spent FAILED: expected prune to return >=1, got %', pruned;
  END IF;

  SELECT COUNT(*) INTO row_count
  FROM registry_mirror_sqlite
  WHERE cell_id_hex = '3344' AND domain_flag = 5;

  IF row_count <> 0 THEN
    RAISE EXCEPTION 'M6.4-T-prune-spent FAILED: expected row gone after prune, count=%', row_count;
  END IF;
END $$;

\echo 'M6.4-T-prune-spent PASSED'

ROLLBACK;

\echo ''
\echo 'All M6.4 registry_mirror_sqlite tests PASSED'

```
