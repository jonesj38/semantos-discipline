---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/tests/test_audit_log_fdw.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.133389+00:00
---

# db/postgres/tests/test_audit_log_fdw.sql

```sql
-- M5.7 tests — signed_bundle_audit_sqlite FDW (staging + view + refresh function)
--
-- Tests:
--   M5.7-T-insert      — refresh_audit_log with 3 entries → 3 rows in audit_log_cache
--   M5.7-T-view        — SELECT * FROM signed_bundle_audit_sqlite WHERE cert_id = $x
--   M5.7-T-idempotent  — second call with same entries → 0 newly inserted
--   M5.7-T-nonce-unique— two entries with same cert_id+nonce → second silently skipped
--   M5.7-T-index       — idx_audit_log_cache_cert present in pg_indexes
--
-- Run via:
--   psql -v ON_ERROR_STOP=1 -f db/postgres/migrations/010_audit_log_fdw.sql
--   psql -v ON_ERROR_STOP=1 -f db/postgres/tests/test_audit_log_fdw.sql

\set ON_ERROR_STOP on

-- ── M5.7-T-insert: refresh_audit_log inserts 3 entries ───────────────

BEGIN;

DO $$
DECLARE
  inserted INT;
  payload  JSONB;
BEGIN
  -- cert_id, nonce, envelope_hash, payload_hash, signature: hex-encoded bytes
  -- created_at_ms: unix milliseconds as bigint
  payload := jsonb_build_array(
    jsonb_build_object(
      'cert_id',       lpad('a1', 64, 'a1'),
      'nonce',         lpad('b1', 32, 'b1'),
      'envelope_hash', lpad('c1', 64, 'c1'),
      'payload_type',  'signed_bundle_v1',
      'payload_hash',  lpad('d1', 64, 'd1'),
      'created_at_ms', 1700000001000,
      'signature',     lpad('e1', 128, 'e1')
    ),
    jsonb_build_object(
      'cert_id',       lpad('a2', 64, 'a2'),
      'nonce',         lpad('b2', 32, 'b2'),
      'envelope_hash', lpad('c2', 64, 'c2'),
      'payload_type',  'signed_bundle_v1',
      'payload_hash',  lpad('d2', 64, 'd2'),
      'created_at_ms', 1700000002000,
      'signature',     lpad('e2', 128, 'e2')
    ),
    jsonb_build_object(
      'cert_id',       lpad('a3', 64, 'a3'),
      'nonce',         lpad('b3', 32, 'b3'),
      'envelope_hash', lpad('c3', 64, 'c3'),
      'payload_type',  'signed_bundle_v2',
      'payload_hash',  lpad('d3', 64, 'd3'),
      'created_at_ms', 1700000003000,
      'signature',     lpad('e3', 128, 'e3')
    )
  );

  SELECT refresh_audit_log(payload) INTO inserted;

  IF inserted <> 3 THEN
    RAISE EXCEPTION 'M5.7-T-insert FAILED: expected 3 inserted, got %', inserted;
  END IF;

  IF (SELECT COUNT(*) FROM audit_log_cache) <> 3 THEN
    RAISE EXCEPTION 'M5.7-T-insert FAILED: expected 3 rows in audit_log_cache';
  END IF;
END $$;

ROLLBACK;

\echo 'M5.7-T-insert PASSED'

-- ── M5.7-T-view: SELECT via signed_bundle_audit_sqlite by cert_id ────

BEGIN;

DO $$
DECLARE
  inserted   INT;
  payload    JSONB;
  cert_a     BYTEA;
  row_count  INT;
BEGIN
  -- Insert 2 rows for cert_a, 1 row for cert_b
  payload := jsonb_build_array(
    jsonb_build_object(
      'cert_id',       lpad('f0', 64, 'f0'),
      'nonce',         lpad('01', 32, '01'),
      'envelope_hash', lpad('11', 64, '11'),
      'payload_type',  'signed_bundle_v1',
      'payload_hash',  lpad('21', 64, '21'),
      'created_at_ms', 1700000100000,
      'signature',     lpad('31', 128, '31')
    ),
    jsonb_build_object(
      'cert_id',       lpad('f0', 64, 'f0'),
      'nonce',         lpad('02', 32, '02'),
      'envelope_hash', lpad('12', 64, '12'),
      'payload_type',  'signed_bundle_v1',
      'payload_hash',  lpad('22', 64, '22'),
      'created_at_ms', 1700000200000,
      'signature',     lpad('32', 128, '32')
    ),
    jsonb_build_object(
      'cert_id',       lpad('f1', 64, 'f1'),
      'nonce',         lpad('03', 32, '03'),
      'envelope_hash', lpad('13', 64, '13'),
      'payload_type',  'signed_bundle_v2',
      'payload_hash',  lpad('23', 64, '23'),
      'created_at_ms', 1700000300000,
      'signature',     lpad('33', 128, '33')
    )
  );

  SELECT refresh_audit_log(payload) INTO inserted;

  cert_a := decode(lpad('f0', 64, 'f0'), 'hex');

  SELECT COUNT(*) INTO row_count
  FROM signed_bundle_audit_sqlite
  WHERE cert_id = cert_a;

  IF row_count <> 2 THEN
    RAISE EXCEPTION 'M5.7-T-view FAILED: expected 2 rows for cert_a, got %', row_count;
  END IF;
END $$;

ROLLBACK;

\echo 'M5.7-T-view PASSED'

-- ── M5.7-T-idempotent: second call returns 0 ─────────────────────────

BEGIN;

DO $$
DECLARE
  first_insert  INT;
  second_insert INT;
  payload       JSONB;
BEGIN
  payload := jsonb_build_array(
    jsonb_build_object(
      'cert_id',       lpad('cc', 64, 'cc'),
      'nonce',         lpad('dd', 32, 'dd'),
      'envelope_hash', lpad('ee', 64, 'ee'),
      'payload_type',  'signed_bundle_v1',
      'payload_hash',  lpad('ff', 64, 'ff'),
      'created_at_ms', 1700000999000,
      'signature',     lpad('aa', 128, 'aa')
    )
  );

  SELECT refresh_audit_log(payload) INTO first_insert;
  SELECT refresh_audit_log(payload) INTO second_insert;

  IF first_insert <> 1 THEN
    RAISE EXCEPTION 'M5.7-T-idempotent FAILED: first insert expected 1, got %', first_insert;
  END IF;

  IF second_insert <> 0 THEN
    RAISE EXCEPTION 'M5.7-T-idempotent FAILED: second insert expected 0, got %', second_insert;
  END IF;
END $$;

ROLLBACK;

\echo 'M5.7-T-idempotent PASSED'

-- ── M5.7-T-nonce-unique: same cert_id+nonce → second silently skipped

BEGIN;

DO $$
DECLARE
  inserted INT;
  payload  JSONB;
  row_count INT;
BEGIN
  -- Two entries with same cert_id+nonce but different envelope_hash/signature
  payload := jsonb_build_array(
    jsonb_build_object(
      'cert_id',       lpad('bb', 64, 'bb'),
      'nonce',         lpad('cc', 32, 'cc'),
      'envelope_hash', lpad('11', 64, '11'),
      'payload_type',  'signed_bundle_v1',
      'payload_hash',  lpad('22', 64, '22'),
      'created_at_ms', 1700001000000,
      'signature',     lpad('33', 128, '33')
    ),
    jsonb_build_object(
      'cert_id',       lpad('bb', 64, 'bb'),
      'nonce',         lpad('cc', 32, 'cc'),
      'envelope_hash', lpad('44', 64, '44'),
      'payload_type',  'signed_bundle_v2',
      'payload_hash',  lpad('55', 64, '55'),
      'created_at_ms', 1700001001000,
      'signature',     lpad('66', 128, '66')
    )
  );

  SELECT refresh_audit_log(payload) INTO inserted;

  -- Only 1 should be inserted; the second is silently skipped (ON CONFLICT DO NOTHING)
  IF inserted <> 1 THEN
    RAISE EXCEPTION 'M5.7-T-nonce-unique FAILED: expected 1 inserted (duplicate skipped), got %', inserted;
  END IF;

  SELECT COUNT(*) INTO row_count
  FROM audit_log_cache
  WHERE cert_id = decode(lpad('bb', 64, 'bb'), 'hex')
    AND nonce   = decode(lpad('cc', 32, 'cc'), 'hex');

  IF row_count <> 1 THEN
    RAISE EXCEPTION 'M5.7-T-nonce-unique FAILED: expected 1 row in cache, got %', row_count;
  END IF;
END $$;

ROLLBACK;

\echo 'M5.7-T-nonce-unique PASSED'

-- ── M5.7-T-index: idx_audit_log_cache_cert present in pg_indexes ─────

DO $$
DECLARE
  idx_count INT;
BEGIN
  SELECT COUNT(*) INTO idx_count
  FROM pg_indexes
  WHERE indexname = 'idx_audit_log_cache_cert';

  IF idx_count = 0 THEN
    RAISE EXCEPTION 'M5.7-T-index FAILED: idx_audit_log_cache_cert not found in pg_indexes';
  END IF;
END $$;

\echo 'M5.7-T-index PASSED'

\echo ''
\echo 'All M5.7 tests PASSED'

```
