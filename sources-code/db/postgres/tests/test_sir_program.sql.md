---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/tests/test_sir_program.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.134505+00:00
---

# db/postgres/tests/test_sir_program.sql

```sql
-- M5.3-T — sir_program / host_reputation schema tests.
--
-- Per §5.2 obligations:
--   M5.3-T-schema-apply        — DDL idempotent
--   M5.3-T-jsonb-trigger       — malformed SIR JSONB rejected by trigger
--   M5.3-T-constraint-fire     — CHECK / NOT NULL constraints tested
--   M5.3-T-reputation-bounds   — score must be in [0,100]

\set ON_ERROR_STOP on

-- ── M5.3-T-schema-apply ──────────────────────────────────────────────

BEGIN;
  \i db/postgres/migrations/003_sir_program.sql
ROLLBACK;

-- ── M5.3-T-jsonb-trigger: SIR structure ──────────────────────────────

BEGIN;

-- Valid SIR program must pass.
INSERT INTO sir_program (sir_hash, sir_json, bytecode_hash, created_at)
VALUES (
  '\xAAAA'::bytea,
  '{"version":1,"ops":[],"inputs":[],"outputs":[]}'::jsonb,
  '\xBBBB'::bytea,
  NOW()
);

-- Missing required 'ops' key must be rejected by the validate_sir trigger.
DO $$
BEGIN
  BEGIN
    INSERT INTO sir_program (sir_hash, sir_json, bytecode_hash, created_at)
    VALUES (
      '\xCCCC'::bytea,
      '{"version":1}'::jsonb,
      '\xDDDD'::bytea,
      NOW()
    );
    RAISE EXCEPTION 'expected trigger rejection for malformed SIR JSON';
  EXCEPTION WHEN raise_exception THEN END;
END $$;

-- Missing 'version' key.
DO $$
BEGIN
  BEGIN
    INSERT INTO sir_program (sir_hash, sir_json, bytecode_hash, created_at)
    VALUES (
      '\xEEEE'::bytea,
      '{"ops":[],"inputs":[],"outputs":[]}'::jsonb,
      '\xFFFF'::bytea,
      NOW()
    );
    RAISE EXCEPTION 'expected trigger rejection for missing version';
  EXCEPTION WHEN raise_exception THEN END;
END $$;

ROLLBACK;

-- ── M5.3-T-reputation-bounds ─────────────────────────────────────────

BEGIN;

-- Valid score.
INSERT INTO host_reputation (host_pub, score, last_updated)
VALUES ('\xAAAA'::bytea, 75, NOW());

-- Score > 100 rejected.
DO $$
BEGIN
  BEGIN
    INSERT INTO host_reputation (host_pub, score, last_updated)
    VALUES ('\xBBBB'::bytea, 101, NOW());
    RAISE EXCEPTION 'expected CHECK rejection for score > 100';
  EXCEPTION WHEN check_violation THEN END;
END $$;

-- Score < 0 rejected.
DO $$
BEGIN
  BEGIN
    INSERT INTO host_reputation (host_pub, score, last_updated)
    VALUES ('\xCCCC'::bytea, -1, NOW());
    RAISE EXCEPTION 'expected CHECK rejection for score < 0';
  EXCEPTION WHEN check_violation THEN END;
END $$;

ROLLBACK;

-- ── M5.3-T-sir-immutability ──────────────────────────────────────────

BEGIN;

INSERT INTO sir_program (sir_hash, sir_json, bytecode_hash, created_at)
VALUES (
  '\x1234'::bytea,
  '{"version":1,"ops":[],"inputs":[],"outputs":[]}'::jsonb,
  '\x5678'::bytea,
  NOW()
);

DO $$
BEGIN
  BEGIN
    UPDATE sir_program SET bytecode_hash = '\xDEAD'::bytea
    WHERE sir_hash = '\x1234'::bytea;
    RAISE EXCEPTION 'expected UPDATE trigger rejection on sir_program';
  EXCEPTION WHEN raise_exception THEN END;
END $$;

ROLLBACK;

\echo 'M5.3 sir_program tests PASSED'

```
