---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/tests/test_teachback_verification.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.136151+00:00
---

# db/postgres/tests/test_teachback_verification.sql

```sql
-- M5.14 tests — teachback verification (verify_teachback_completeness)
--
-- Tests:
--   M5.14-T-pg-missing-hash  — action_cell_log row with NULL sir_program_hash → issue='missing_hash'
--   M5.14-T-pg-zeroed-hash   — action_cell_log row with all-zero hash → issue='zeroed_hash'
--   M5.14-T-pg-orphan-hash   — non-zero hash with no sir_program row → issue='orphan_hash'
--   M5.14-T-pg-clean         — valid sir_program + matching action_cell_log row → zero rows returned
--
-- Run via:
--   psql -v ON_ERROR_STOP=1 -f db/postgres/tests/test_teachback_verification.sql

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
\i db/postgres/migrations/015_teachback_verification.sql

-- Clean up any rows left from previous runs of this test script.
DELETE FROM action_cell_log  WHERE cell_id_hex LIKE 'deadbeef0%';
DELETE FROM sir_program      WHERE sir_hash     = decode(repeat('cc', 32), 'hex');

-- ── M5.14-T-pg-missing-hash ──────────────────────────────────────────────────
-- Insert an action_cell_log row with NULL sir_program_hash.
-- verify_teachback_completeness() must return that row with issue='missing_hash'.

DO $$
DECLARE
  row_count  INT;
  found_id   TEXT;
  found_iss  TEXT;
BEGIN
  INSERT INTO action_cell_log (cell_id_hex, sir_program_hash)
  VALUES ('deadbeef01', NULL);

  SELECT COUNT(*) INTO row_count
  FROM verify_teachback_completeness()
  WHERE cell_id_hex = 'deadbeef01' AND issue = 'missing_hash';

  IF row_count <> 1 THEN
    RAISE EXCEPTION 'M5.14-T-pg-missing-hash FAILED: expected 1 row with issue=missing_hash, got %', row_count;
  END IF;
END $$;

\echo 'M5.14-T-pg-missing-hash PASSED'

-- ── M5.14-T-pg-zeroed-hash ───────────────────────────────────────────────────
-- Insert an action_cell_log row with all-zero (32-byte) sir_program_hash.
-- verify_teachback_completeness() must return that row with issue='zeroed_hash'.

DO $$
DECLARE
  row_count  INT;
BEGIN
  INSERT INTO action_cell_log (cell_id_hex, sir_program_hash)
  VALUES ('deadbeef02', decode(repeat('00', 32), 'hex'));

  SELECT COUNT(*) INTO row_count
  FROM verify_teachback_completeness()
  WHERE cell_id_hex = 'deadbeef02' AND issue = 'zeroed_hash';

  IF row_count <> 1 THEN
    RAISE EXCEPTION 'M5.14-T-pg-zeroed-hash FAILED: expected 1 row with issue=zeroed_hash, got %', row_count;
  END IF;
END $$;

\echo 'M5.14-T-pg-zeroed-hash PASSED'

-- ── M5.14-T-pg-orphan-hash ───────────────────────────────────────────────────
-- Insert an action_cell_log row with a non-zero hash that has no matching
-- sir_program row. verify_teachback_completeness() must return issue='orphan_hash'.

DO $$
DECLARE
  row_count  INT;
  orphan_hash BYTEA := decode(repeat('ab', 32), 'hex');
BEGIN
  INSERT INTO action_cell_log (cell_id_hex, sir_program_hash)
  VALUES ('deadbeef03', orphan_hash);

  SELECT COUNT(*) INTO row_count
  FROM verify_teachback_completeness()
  WHERE cell_id_hex = 'deadbeef03' AND issue = 'orphan_hash';

  IF row_count <> 1 THEN
    RAISE EXCEPTION 'M5.14-T-pg-orphan-hash FAILED: expected 1 row with issue=orphan_hash, got %', row_count;
  END IF;
END $$;

\echo 'M5.14-T-pg-orphan-hash PASSED'

-- ── M5.14-T-pg-clean ─────────────────────────────────────────────────────────
-- Insert a valid sir_program row, then an action_cell_log row referencing its
-- sir_hash. verify_teachback_completeness() must return zero rows for that cell.

DO $$
DECLARE
  row_count  INT;
  clean_hash BYTEA := decode(repeat('cc', 32), 'hex');
BEGIN
  INSERT INTO sir_program (sir_hash, sir_json, bytecode_hash, created_at)
  VALUES (
    clean_hash,
    '{"version": 1, "ops": [], "inputs": [], "outputs": []}'::JSONB,
    decode(repeat('dd', 32), 'hex'),
    now()
  );

  INSERT INTO action_cell_log (cell_id_hex, sir_program_hash)
  VALUES ('deadbeef04', clean_hash);

  SELECT COUNT(*) INTO row_count
  FROM verify_teachback_completeness()
  WHERE cell_id_hex = 'deadbeef04';

  IF row_count <> 0 THEN
    RAISE EXCEPTION 'M5.14-T-pg-clean FAILED: expected 0 rows for clean cell, got %', row_count;
  END IF;
END $$;

\echo 'M5.14-T-pg-clean PASSED'

ROLLBACK;

\echo ''
\echo 'All M5.14 teachback verification tests PASSED'

```
