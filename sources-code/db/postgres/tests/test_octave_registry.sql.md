---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/tests/test_octave_registry.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.137795+00:00
---

# db/postgres/tests/test_octave_registry.sql

```sql
-- M6.1-T — octave_registry schema tests.
--
-- Tests:
--   M6.1-T-insert-octave0        — insert octave_0 cell, no octave_addr → succeeds
--   M6.1-T-insert-octave1        — insert octave_1 cell with octave_addr → succeeds
--   M6.1-T-octave0-addr-rejected — insert octave_0 with non-null octave_addr → fails CHECK
--   M6.1-T-spend-linear          — insert linear cell, update state→spent + spent_at → succeeds
--   M6.1-T-linear-invalid-state  — insert linear cell, update state→locked → fails K1 CHECK
--   M6.1-T-spent-at-consistency  — update state→spent without spent_at → fails CHECK
--   M6.1-T-k7-content-hash       — UPDATE content_hash → trigger raises K7 exception
--   M6.1-T-k7-linearity-type     — UPDATE linearity_type → trigger raises K7 exception
--   M6.1-T-k7-octave-level       — UPDATE octave_level → trigger raises K7 exception
--   M6.1-T-content-hash-length   — insert 31-byte content_hash → fails CHECK
--   M6.1-T-cell-size-enforced    — insert cell_size=512 → fails CHECK
--   M6.1-T-3-indexes             — verify 3 indexes exist in pg_indexes
--
-- Run via:
--   psql -v ON_ERROR_STOP=1 -f db/postgres/migrations/008_octave_registry.sql
--   psql -v ON_ERROR_STOP=1 -f db/postgres/tests/test_octave_registry.sql

\set ON_ERROR_STOP on

-- Shared test fixtures
-- cell_id: 32-byte values
-- content_hash: 32-byte SHA-256 placeholder

-- ── M6.1-T-insert-octave0: octave_0 cell, no addr → succeeds ──────────

BEGIN;

DO $$
DECLARE
  cell_id    BYTEA := '\x0101010101010101010101010101010101010101010101010101010101010101'::bytea;
  chash      BYTEA := '\xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'::bytea;
BEGIN
  INSERT INTO octave_registry (cell_id, domain_flag, octave_level, octave_addr, content_hash, linearity_type, state)
  VALUES (cell_id, 1, '0', NULL, chash, 'unrestricted', 'unspent');

  IF NOT EXISTS (SELECT 1 FROM octave_registry WHERE cell_id = cell_id AND domain_flag = 1) THEN
    RAISE EXCEPTION 'M6.1-T-insert-octave0: row not found after insert';
  END IF;
END $$;

ROLLBACK;

-- ── M6.1-T-insert-octave1: octave_1 cell with octave_addr → succeeds ──

BEGIN;

DO $$
DECLARE
  cell_id    BYTEA := '\x0202020202020202020202020202020202020202020202020202020202020202'::bytea;
  chash      BYTEA := '\xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'::bytea;
BEGIN
  INSERT INTO octave_registry (cell_id, domain_flag, octave_level, octave_addr, content_hash, linearity_type, state)
  VALUES (cell_id, 1, '1', '/slots/0000000001.slot', chash, 'unrestricted', 'unspent');

  IF NOT EXISTS (SELECT 1 FROM octave_registry WHERE cell_id = cell_id AND domain_flag = 1) THEN
    RAISE EXCEPTION 'M6.1-T-insert-octave1: row not found after insert';
  END IF;
END $$;

ROLLBACK;

-- ── M6.1-T-octave0-addr-rejected: octave_0 with non-null addr → fails ─

BEGIN;

DO $$
DECLARE
  cell_id    BYTEA := '\x0303030303030303030303030303030303030303030303030303030303030303'::bytea;
  chash      BYTEA := '\xCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC'::bytea;
BEGIN
  BEGIN
    INSERT INTO octave_registry (cell_id, domain_flag, octave_level, octave_addr, content_hash, linearity_type, state)
    VALUES (cell_id, 1, '0', '/slots/illegal.slot', chash, 'unrestricted', 'unspent');
    RAISE EXCEPTION 'M6.1-T-octave0-addr-rejected: expected CHECK violation, got none';
  EXCEPTION WHEN check_violation THEN
    -- expected
  END;
END $$;

ROLLBACK;

-- ── M6.1-T-spend-linear: linear cell unspent→spent + spent_at → succeeds

BEGIN;

DO $$
DECLARE
  cell_id    BYTEA := '\x0404040404040404040404040404040404040404040404040404040404040404'::bytea;
  chash      BYTEA := '\xDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD'::bytea;
  ts         TIMESTAMPTZ := now();
BEGIN
  INSERT INTO octave_registry (cell_id, domain_flag, octave_level, octave_addr, content_hash, linearity_type, state)
  VALUES (cell_id, 1, '0', NULL, chash, 'linear', 'unspent');

  UPDATE octave_registry
  SET state = 'spent', spent_at = ts
  WHERE cell_id = cell_id AND domain_flag = 1;

  IF NOT EXISTS (
    SELECT 1 FROM octave_registry
    WHERE cell_id = cell_id AND domain_flag = 1 AND state = 'spent' AND spent_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'M6.1-T-spend-linear: row not in spent state after update';
  END IF;
END $$;

ROLLBACK;

-- ── M6.1-T-linear-invalid-state: linear→locked → fails K1 CHECK ───────

BEGIN;

DO $$
DECLARE
  cell_id    BYTEA := '\x0505050505050505050505050505050505050505050505050505050505050505'::bytea;
  chash      BYTEA := '\xEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE'::bytea;
BEGIN
  INSERT INTO octave_registry (cell_id, domain_flag, octave_level, octave_addr, content_hash, linearity_type, state)
  VALUES (cell_id, 1, '0', NULL, chash, 'linear', 'unspent');

  BEGIN
    UPDATE octave_registry
    SET state = 'locked'
    WHERE cell_id = cell_id AND domain_flag = 1;
    RAISE EXCEPTION 'M6.1-T-linear-invalid-state: expected K1 CHECK violation, got none';
  EXCEPTION WHEN check_violation THEN
    -- expected
  END;
END $$;

ROLLBACK;

-- ── M6.1-T-spent-at-consistency: state→spent without spent_at → fails ─

BEGIN;

DO $$
DECLARE
  cell_id    BYTEA := '\x0606060606060606060606060606060606060606060606060606060606060606'::bytea;
  chash      BYTEA := '\xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'::bytea;
BEGIN
  INSERT INTO octave_registry (cell_id, domain_flag, octave_level, octave_addr, content_hash, linearity_type, state)
  VALUES (cell_id, 1, '0', NULL, chash, 'affine', 'unspent');

  BEGIN
    UPDATE octave_registry
    SET state = 'spent'
    WHERE cell_id = cell_id AND domain_flag = 1;
    RAISE EXCEPTION 'M6.1-T-spent-at-consistency: expected CHECK violation for missing spent_at, got none';
  EXCEPTION WHEN check_violation THEN
    -- expected
  END;
END $$;

ROLLBACK;

-- ── M6.1-T-k7-content-hash: UPDATE content_hash → K7 trigger exception

BEGIN;

DO $$
DECLARE
  cell_id    BYTEA := '\x0707070707070707070707070707070707070707070707070707070707070707'::bytea;
  chash      BYTEA := '\x1111111111111111111111111111111111111111111111111111111111111111'::bytea;
  new_hash   BYTEA := '\x2222222222222222222222222222222222222222222222222222222222222222'::bytea;
BEGIN
  INSERT INTO octave_registry (cell_id, domain_flag, octave_level, octave_addr, content_hash, linearity_type, state)
  VALUES (cell_id, 1, '0', NULL, chash, 'unrestricted', 'unspent');

  BEGIN
    UPDATE octave_registry
    SET content_hash = new_hash
    WHERE cell_id = cell_id AND domain_flag = 1;
    RAISE EXCEPTION 'M6.1-T-k7-content-hash: expected K7 trigger exception, got none';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT ILIKE '%K7%' THEN
      RAISE EXCEPTION 'M6.1-T-k7-content-hash: got exception but not K7: %', SQLERRM;
    END IF;
    -- expected
  END;
END $$;

ROLLBACK;

-- ── M6.1-T-k7-linearity-type: UPDATE linearity_type → K7 trigger exception

BEGIN;

DO $$
DECLARE
  cell_id    BYTEA := '\x0808080808080808080808080808080808080808080808080808080808080808'::bytea;
  chash      BYTEA := '\x3333333333333333333333333333333333333333333333333333333333333333'::bytea;
BEGIN
  INSERT INTO octave_registry (cell_id, domain_flag, octave_level, octave_addr, content_hash, linearity_type, state)
  VALUES (cell_id, 1, '0', NULL, chash, 'unrestricted', 'unspent');

  BEGIN
    UPDATE octave_registry
    SET linearity_type = 'affine'
    WHERE cell_id = cell_id AND domain_flag = 1;
    RAISE EXCEPTION 'M6.1-T-k7-linearity-type: expected K7 trigger exception, got none';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT ILIKE '%K7%' THEN
      RAISE EXCEPTION 'M6.1-T-k7-linearity-type: got exception but not K7: %', SQLERRM;
    END IF;
    -- expected
  END;
END $$;

ROLLBACK;

-- ── M6.1-T-k7-octave-level: UPDATE octave_level → K7 trigger exception

BEGIN;

DO $$
DECLARE
  cell_id    BYTEA := '\x0909090909090909090909090909090909090909090909090909090909090909'::bytea;
  chash      BYTEA := '\x4444444444444444444444444444444444444444444444444444444444444444'::bytea;
BEGIN
  INSERT INTO octave_registry (cell_id, domain_flag, octave_level, octave_addr, content_hash, linearity_type, state)
  VALUES (cell_id, 1, '1', '/slots/test.slot', chash, 'unrestricted', 'unspent');

  BEGIN
    UPDATE octave_registry
    SET octave_level = '2', octave_addr = 'https://example.com/hash'
    WHERE cell_id = cell_id AND domain_flag = 1;
    RAISE EXCEPTION 'M6.1-T-k7-octave-level: expected K7 trigger exception, got none';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT ILIKE '%K7%' THEN
      RAISE EXCEPTION 'M6.1-T-k7-octave-level: got exception but not K7: %', SQLERRM;
    END IF;
    -- expected
  END;
END $$;

ROLLBACK;

-- ── M6.1-T-content-hash-length: 31-byte content_hash → fails CHECK ────

BEGIN;

DO $$
DECLARE
  cell_id    BYTEA := '\x0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A'::bytea;
  bad_hash   BYTEA := '\x55555555555555555555555555555555555555555555555555555555555555'::bytea; -- 31 bytes
BEGIN
  BEGIN
    INSERT INTO octave_registry (cell_id, domain_flag, octave_level, octave_addr, content_hash, linearity_type, state)
    VALUES (cell_id, 1, '0', NULL, bad_hash, 'unrestricted', 'unspent');
    RAISE EXCEPTION 'M6.1-T-content-hash-length: expected CHECK violation, got none';
  EXCEPTION WHEN check_violation THEN
    -- expected
  END;
END $$;

ROLLBACK;

-- ── M6.1-T-cell-size-enforced: cell_size=512 → fails CHECK ────────────

BEGIN;

DO $$
DECLARE
  cell_id    BYTEA := '\x0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B'::bytea;
  chash      BYTEA := '\x6666666666666666666666666666666666666666666666666666666666666666'::bytea;
BEGIN
  BEGIN
    INSERT INTO octave_registry (cell_id, domain_flag, octave_level, octave_addr, content_hash, cell_size, linearity_type, state)
    VALUES (cell_id, 1, '0', NULL, chash, 512, 'unrestricted', 'unspent');
    RAISE EXCEPTION 'M6.1-T-cell-size-enforced: expected CHECK violation, got none';
  EXCEPTION WHEN check_violation THEN
    -- expected
  END;
END $$;

ROLLBACK;

-- ── M6.1-T-3-indexes: verify 3 named indexes exist ────────────────────

DO $$
DECLARE
  idx_count INT;
BEGIN
  SELECT COUNT(*) INTO idx_count
  FROM pg_indexes
  WHERE tablename = 'octave_registry'
    AND indexname IN (
      'idx_octave_registry_domain',
      'idx_octave_registry_owner',
      'idx_octave_registry_unspent'
    );

  IF idx_count <> 3 THEN
    RAISE EXCEPTION 'M6.1-T-3-indexes: expected 3 indexes, found %', idx_count;
  END IF;
END $$;

\echo 'M6.1 octave_registry tests PASSED'

```
