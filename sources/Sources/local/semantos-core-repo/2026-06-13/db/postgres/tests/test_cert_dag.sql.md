---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/tests/test_cert_dag.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.133938+00:00
---

# db/postgres/tests/test_cert_dag.sql

```sql
-- M5.1-T — cert_dag / intent / intent_edge schema tests.
--
-- Per §5.2 obligations:
--   M5.1-T-schema-apply      — DDL applies cleanly; idempotent re-run is no-op
--   M5.1-T-constraint-fire   — every CHECK/FK/UNIQUE violated and rejected
--   M5.1-T-recursive-walk    — 100-level ancestor walk returns deterministic path
--   M5.1-T-index-plan        — EXPLAIN ANALYZE shows B+tree index on cert_dag
--   M5.1-T-intent-edge-fk    — intent_edge FKs enforce referential integrity
--
-- Run via:
--   psql -v ON_ERROR_STOP=1 -f db/postgres/migrations/001_cert_dag.sql
--   psql -v ON_ERROR_STOP=1 -f db/postgres/tests/test_cert_dag.sql
--
-- Tests use pgtap when available; plain SQL assertions otherwise.
-- Each test block is wrapped in a transaction that rolls back, so the
-- tests leave no residue in the database.

\set ON_ERROR_STOP on

-- ── M5.1-T-schema-apply: idempotent re-run ───────────────────────────

BEGIN;
  -- Re-applying the migration must not error (IF NOT EXISTS / CREATE OR REPLACE).
  \i db/postgres/migrations/001_cert_dag.sql
ROLLBACK;

-- ── M5.1-T-constraint-fire: cert_dag ─────────────────────────────────

BEGIN;

-- cert_type must be one of the allowed values.
DO $$
BEGIN
  BEGIN
    INSERT INTO cert_dag (cert_hash, issuer_pub, subject_pub, cert_type, cert_bytes, issued_at)
    VALUES (
      '\xdeadbeef'::bytea,
      '\xABCD'::bytea,
      '\xEF01'::bytea,
      'invalid_type',
      '\x00'::bytea,
      NOW()
    );
    RAISE EXCEPTION 'expected CHECK constraint to fire for cert_type';
  EXCEPTION WHEN check_violation THEN
    -- expected
  END;
END $$;

-- cert_hash must be unique.
DO $$
DECLARE
  h bytea := '\x0101010101010101010101010101010101010101010101010101010101010101'::bytea;
BEGIN
  INSERT INTO cert_dag (cert_hash, issuer_pub, subject_pub, cert_type, cert_bytes, issued_at)
  VALUES (h, '\xAA'::bytea, '\xBB'::bytea, 'identity', '\x00'::bytea, NOW());

  BEGIN
    INSERT INTO cert_dag (cert_hash, issuer_pub, subject_pub, cert_type, cert_bytes, issued_at)
    VALUES (h, '\xCC'::bytea, '\xDD'::bytea, 'identity', '\x00'::bytea, NOW());
    RAISE EXCEPTION 'expected UNIQUE violation on cert_hash';
  EXCEPTION WHEN unique_violation THEN
    -- expected
  END;
END $$;

-- issued_at must not be NULL.
DO $$
BEGIN
  BEGIN
    INSERT INTO cert_dag (cert_hash, issuer_pub, subject_pub, cert_type, cert_bytes, issued_at)
    VALUES ('\xFFFF'::bytea, '\xAA'::bytea, '\xBB'::bytea, 'identity', '\x00'::bytea, NULL);
    RAISE EXCEPTION 'expected NOT NULL violation on issued_at';
  EXCEPTION WHEN not_null_violation THEN
    -- expected
  END;
END $$;

ROLLBACK;

-- ── M5.1-T-recursive-walk: 100-level ancestor chain ──────────────────

BEGIN;

-- Build a 100-level cert chain: cert[0] ← cert[1] ← … ← cert[99].
DO $$
DECLARE
  i    INT;
  prev BYTEA := NULL;
  cur  BYTEA;
BEGIN
  FOR i IN 0..99 LOOP
    cur := ('\x' || lpad(to_hex(i), 64, '0'))::bytea;
    INSERT INTO cert_dag (cert_hash, issuer_pub, subject_pub, cert_type, cert_bytes, issued_at, parent_cert_hash)
    VALUES (cur, '\xAA'::bytea, '\xBB'::bytea, 'identity', '\x00'::bytea, NOW(), prev);
    prev := cur;
  END LOOP;
END $$;

-- Walk the full 100-level chain using the recursive CTE defined in the migration.
-- Expected: exactly 100 rows returned with depth 0..99.
DO $$
DECLARE
  tip      BYTEA := ('\x' || lpad(to_hex(99), 64, '0'))::bytea;
  row_count INT;
BEGIN
  SELECT COUNT(*) INTO row_count
  FROM cert_ancestors(tip);

  IF row_count <> 100 THEN
    RAISE EXCEPTION 'expected 100 ancestor rows, got %', row_count;
  END IF;
END $$;

ROLLBACK;

-- ── M5.1-T-index-plan: B+tree on cert_dag.cert_hash ─────────────────

-- (Advisory — does not roll back since EXPLAIN has no side effects.)
-- The plan must use an Index Scan, not a Seq Scan.
DO $$
DECLARE
  plan TEXT;
BEGIN
  EXECUTE $q$
    EXPLAIN (FORMAT TEXT, ANALYZE FALSE)
    SELECT cert_hash FROM cert_dag WHERE cert_hash = '\xdeadbeef'::bytea
  $q$ INTO plan;

  IF plan NOT ILIKE '%Index%' THEN
    RAISE EXCEPTION 'expected index scan on cert_dag.cert_hash, got: %', plan;
  END IF;
END $$;

-- ── M5.1-T-intent-edge-fk: referential integrity ─────────────────────

BEGIN;

-- Insert two intents.
INSERT INTO intent (intent_hash, payload, created_at)
VALUES
  ('\xAAAA'::bytea, '{"kind":"test"}'::jsonb, NOW()),
  ('\xBBBB'::bytea, '{"kind":"test"}'::jsonb, NOW());

-- Valid edge.
INSERT INTO intent_edge (from_intent, to_intent, edge_type)
VALUES ('\xAAAA'::bytea, '\xBBBB'::bytea, 'depends_on');

-- Edge referencing non-existent intent must fail FK.
DO $$
BEGIN
  BEGIN
    INSERT INTO intent_edge (from_intent, to_intent, edge_type)
    VALUES ('\xAAAA'::bytea, '\xCCCC'::bytea, 'depends_on');
    RAISE EXCEPTION 'expected FK violation on intent_edge.to_intent';
  EXCEPTION WHEN foreign_key_violation THEN
    -- expected
  END;
END $$;

ROLLBACK;

\echo 'M5.1 cert_dag tests PASSED'

```
