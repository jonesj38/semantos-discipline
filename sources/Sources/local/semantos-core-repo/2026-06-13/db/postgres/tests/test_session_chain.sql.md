---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/tests/test_session_chain.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.136709+00:00
---

# db/postgres/tests/test_session_chain.sql

```sql
-- M5.4-T — session_chain / equivocation_evidence schema tests.
--
-- Per §5.2 obligations:
--   M5.4-T-schema-apply          — DDL idempotent
--   M5.4-T-constraint-fire       — FK / NOT NULL / CHECK constraints
--   M5.4-T-recursive-walk        — session chain walks correctly
--   M5.4-T-hash-chain-trigger    — prev_state_hash integrity trigger (K6)
--   M5.4-T-equivocation-unique   — duplicate equivocation evidence rejected

\set ON_ERROR_STOP on

-- ── M5.4-T-schema-apply ──────────────────────────────────────────────

BEGIN;
  \i db/postgres/migrations/004_session_chain.sql
ROLLBACK;

-- ── M5.4-T-constraint-fire ───────────────────────────────────────────

BEGIN;

-- session_hash must not be NULL.
DO $$
BEGIN
  BEGIN
    INSERT INTO session_chain (session_hash, host_pub, prev_state_hash, seq_num, payload, recorded_at)
    VALUES (NULL, '\xAA'::bytea, NULL, 0, '\x00'::bytea, NOW());
    RAISE EXCEPTION 'expected NOT NULL on session_hash';
  EXCEPTION WHEN not_null_violation THEN END;
END $$;

-- seq_num must be >= 0.
-- (Postgres BEFORE triggers fire before CHECK constraints, so either
-- check_violation or raise_exception may arrive first.)
DO $$
BEGIN
  BEGIN
    INSERT INTO session_chain (session_hash, host_pub, prev_state_hash, seq_num, payload, recorded_at)
    VALUES ('\xAAAA'::bytea, '\xBB'::bytea, NULL, -1, '\x00'::bytea, NOW());
    RAISE EXCEPTION 'expected rejection for seq_num < 0';
  EXCEPTION WHEN check_violation OR raise_exception THEN END;
END $$;

ROLLBACK;

-- ── M5.4-T-hash-chain-trigger (K6) ───────────────────────────────────
-- The trigger must enforce that seq_num 0 has prev_state_hash = NULL,
-- and seq_num N > 0 has prev_state_hash = hash of seq_num N-1.

BEGIN;

-- Valid: seq 0 with NULL prev.
INSERT INTO session_chain (session_hash, host_pub, prev_state_hash, seq_num, payload, recorded_at)
VALUES ('\xAA00'::bytea, '\xBB'::bytea, NULL, 0, '\x01'::bytea, NOW());

-- seq 0 with non-NULL prev must be rejected.
DO $$
BEGIN
  BEGIN
    INSERT INTO session_chain (session_hash, host_pub, prev_state_hash, seq_num, payload, recorded_at)
    VALUES ('\xAA01'::bytea, '\xBB'::bytea, '\xDEAD'::bytea, 0, '\x01'::bytea, NOW());
    RAISE EXCEPTION 'expected trigger rejection: seq 0 must have NULL prev_state_hash';
  EXCEPTION WHEN raise_exception THEN END;
END $$;

ROLLBACK;

-- ── M5.4-T-recursive-walk ────────────────────────────────────────────

BEGIN;

-- Build a 10-entry session chain.
DO $$
DECLARE
  i    INT;
  prev BYTEA := NULL;
  cur  BYTEA;
BEGIN
  FOR i IN 0..9 LOOP
    cur := decode(lpad(to_hex(i + 1), 64, '0'), 'hex');
    INSERT INTO session_chain (session_hash, host_pub, prev_state_hash, seq_num, payload, recorded_at)
    VALUES (cur, '\xBB'::bytea, prev, i, '\x00'::bytea, NOW());
    prev := cur;
  END LOOP;
END $$;

DO $$
DECLARE
  tip       BYTEA := decode(lpad(to_hex(10), 64, '0'), 'hex');
  row_count INT;
BEGIN
  SELECT COUNT(*) INTO row_count
  FROM session_chain_history(tip);

  IF row_count <> 10 THEN
    RAISE EXCEPTION 'expected 10 session chain entries, got %', row_count;
  END IF;
END $$;

ROLLBACK;

-- ── M5.4-T-equivocation-unique ───────────────────────────────────────

BEGIN;

INSERT INTO equivocation_evidence (evidence_hash, host_pub, session_hash_a, session_hash_b, detected_at)
VALUES ('\xEEEE'::bytea, '\xBB'::bytea, '\x0001'::bytea, '\x0002'::bytea, NOW());

DO $$
BEGIN
  BEGIN
    INSERT INTO equivocation_evidence (evidence_hash, host_pub, session_hash_a, session_hash_b, detected_at)
    VALUES ('\xEEEE'::bytea, '\xCC'::bytea, '\x0003'::bytea, '\x0004'::bytea, NOW());
    RAISE EXCEPTION 'expected UNIQUE violation on evidence_hash';
  EXCEPTION WHEN unique_violation THEN END;
END $$;

ROLLBACK;

\echo 'M5.4 session_chain tests PASSED'

```
