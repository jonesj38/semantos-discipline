---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/tests/test_cells_lmdb_fdw.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.135604+00:00
---

# db/postgres/tests/test_cells_lmdb_fdw.sql

```sql
-- M5.5 tests — cells_lmdb FDW (staging + view + refresh function)
--
-- Tests:
--   M5.5-T-insert          — refresh_cells_lmdb with 2 cells → 2 rows in cells_lmdb_cache
--   M5.5-T-view-query      — SELECT cell_bytes FROM cells_lmdb WHERE type_hash = $x
--   M5.5-T-idempotent      — second call with same cells → 0 newly inserted
--   M5.5-T-type-hash-index — idx_cells_lmdb_type_hash present in pg_indexes
--   M5.5-T-cell-bytes-size — inserted cell_bytes length matches the payload sent
--
-- Run via:
--   psql -v ON_ERROR_STOP=1 -f db/postgres/migrations/009_cells_lmdb_fdw.sql
--   psql -v ON_ERROR_STOP=1 -f db/postgres/tests/test_cells_lmdb_fdw.sql

\set ON_ERROR_STOP on

-- ── M5.5-T-insert: refresh_cells_lmdb inserts 2 cells ────────────────

BEGIN;

DO $$
DECLARE
  inserted INT;
  payload  JSONB;
BEGIN
  -- Two 1024-byte cells encoded as hex strings in JSONB.
  -- cell_hash: 32 bytes each (64 hex chars)
  -- type_hash: 32 bytes each (64 hex chars)
  -- cell_bytes: 1024 bytes each (2048 hex chars) — we use repeating patterns
  payload := jsonb_build_array(
    jsonb_build_object(
      'cell_hash',   lpad('aa', 64, 'aa'),
      'type_hash',   lpad('bb', 64, 'bb'),
      'domain_flag', 1,
      'cell_bytes',  lpad('cc', 2048, 'cc')
    ),
    jsonb_build_object(
      'cell_hash',   lpad('dd', 64, 'dd'),
      'type_hash',   lpad('ee', 64, 'ee'),
      'domain_flag', 2,
      'cell_bytes',  lpad('ff', 2048, 'ff')
    )
  );

  SELECT refresh_cells_lmdb(payload) INTO inserted;

  IF inserted <> 2 THEN
    RAISE EXCEPTION 'M5.5-T-insert FAILED: expected 2 inserted, got %', inserted;
  END IF;

  -- Verify row count in cache table
  IF (SELECT COUNT(*) FROM cells_lmdb_cache) <> 2 THEN
    RAISE EXCEPTION 'M5.5-T-insert FAILED: expected 2 rows in cells_lmdb_cache';
  END IF;
END $$;

ROLLBACK;

\echo 'M5.5-T-insert PASSED'

-- ── M5.5-T-view-query: SELECT via cells_lmdb view by type_hash ───────

BEGIN;

DO $$
DECLARE
  inserted  INT;
  payload   JSONB;
  th        BYTEA;
  found_len INT;
BEGIN
  payload := jsonb_build_array(
    jsonb_build_object(
      'cell_hash',   lpad('11', 64, '11'),
      'type_hash',   lpad('22', 64, '22'),
      'domain_flag', 0,
      'cell_bytes',  lpad('33', 2048, '33')
    ),
    jsonb_build_object(
      'cell_hash',   lpad('44', 64, '44'),
      'type_hash',   lpad('55', 64, '55'),
      'domain_flag', 0,
      'cell_bytes',  lpad('66', 2048, '66')
    )
  );

  SELECT refresh_cells_lmdb(payload) INTO inserted;

  -- Query via view using type_hash of the first cell
  th := decode(lpad('22', 64, '22'), 'hex');

  SELECT length(cell_bytes) INTO found_len
  FROM cells_lmdb
  WHERE type_hash = th
  LIMIT 1;

  IF found_len IS NULL THEN
    RAISE EXCEPTION 'M5.5-T-view-query FAILED: no row found for type_hash';
  END IF;

  IF found_len <> 1024 THEN
    RAISE EXCEPTION 'M5.5-T-view-query FAILED: expected cell_bytes length 1024, got %', found_len;
  END IF;
END $$;

ROLLBACK;

\echo 'M5.5-T-view-query PASSED'

-- ── M5.5-T-idempotent: second call returns 0 ─────────────────────────

BEGIN;

DO $$
DECLARE
  first_insert  INT;
  second_insert INT;
  payload       JSONB;
BEGIN
  payload := jsonb_build_array(
    jsonb_build_object(
      'cell_hash',   lpad('ab', 64, 'ab'),
      'type_hash',   lpad('cd', 64, 'cd'),
      'domain_flag', 3,
      'cell_bytes',  lpad('ef', 2048, 'ef')
    )
  );

  SELECT refresh_cells_lmdb(payload) INTO first_insert;
  SELECT refresh_cells_lmdb(payload) INTO second_insert;

  IF first_insert <> 1 THEN
    RAISE EXCEPTION 'M5.5-T-idempotent FAILED: first insert expected 1, got %', first_insert;
  END IF;

  IF second_insert <> 0 THEN
    RAISE EXCEPTION 'M5.5-T-idempotent FAILED: second insert expected 0, got %', second_insert;
  END IF;
END $$;

ROLLBACK;

\echo 'M5.5-T-idempotent PASSED'

-- ── M5.5-T-type-hash-index: index present in pg_indexes ──────────────

DO $$
DECLARE
  idx_count INT;
BEGIN
  SELECT COUNT(*) INTO idx_count
  FROM pg_indexes
  WHERE indexname = 'idx_cells_lmdb_type_hash';

  IF idx_count = 0 THEN
    RAISE EXCEPTION 'M5.5-T-type-hash-index FAILED: idx_cells_lmdb_type_hash not found in pg_indexes';
  END IF;
END $$;

\echo 'M5.5-T-type-hash-index PASSED'

-- ── M5.5-T-cell-bytes-size: inserted cell_bytes length is 1024 ───────

BEGIN;

DO $$
DECLARE
  inserted INT;
  payload  JSONB;
  stored_len INT;
BEGIN
  -- A full 1024-byte cell: 2048 hex chars
  payload := jsonb_build_array(
    jsonb_build_object(
      'cell_hash',   lpad('ba', 64, 'ba'),
      'type_hash',   lpad('dc', 64, 'dc'),
      'domain_flag', 7,
      'cell_bytes',  lpad('fe', 2048, 'fe')
    )
  );

  SELECT refresh_cells_lmdb(payload) INTO inserted;

  SELECT length(cell_bytes) INTO stored_len
  FROM cells_lmdb_cache
  WHERE cell_hash = decode(lpad('ba', 64, 'ba'), 'hex');

  IF stored_len IS NULL THEN
    RAISE EXCEPTION 'M5.5-T-cell-bytes-size FAILED: row not found';
  END IF;

  -- The payload encodes exactly 1024 bytes (2048 hex chars)
  IF stored_len <> 1024 THEN
    RAISE EXCEPTION 'M5.5-T-cell-bytes-size FAILED: expected 1024 bytes, got %', stored_len;
  END IF;
END $$;

ROLLBACK;

\echo 'M5.5-T-cell-bytes-size PASSED'

\echo ''
\echo 'All M5.5 tests PASSED'

```
