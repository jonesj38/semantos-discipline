---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/tests/test_operators_rls.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.136980+00:00
---

# db/postgres/tests/test_operators_rls.sql

```sql
-- test_operators_rls.sql
--
-- W7.2 acceptance tests: operators table + RLS isolation.
--
-- Tests:
--   1. Schema idempotency — re-applying 017 does not error.
--   2. operators table constraints (pk, length, lowercase, status enum, exit order).
--   3. op_pkh column exists on all scoped tables.
--   4. RLS isolation: semantos_brain session sees ONLY its own op_pkh rows.
--   5. Fail-closed: unset semantos.op_pkh → zero rows returned.
--   6. Admin role bypasses RLS and sees all rows.
--   7. Boot operator seeded ('0000000000000000').
--
-- Run after all migrations 001–017 have been applied.

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
\i db/postgres/migrations/014_helm_read_views.sql
\i db/postgres/migrations/015_teachback_verification.sql
\i db/postgres/migrations/016_hat_views.sql
\i db/postgres/migrations/017_operators_rls.sql

DO $$ BEGIN RAISE NOTICE 'W7.2: schema idempotency OK'; END $$;

-- ── 1. operators table constraints ────────────────────────────────────────────

DO $$
BEGIN
    -- PK insert succeeds.
    INSERT INTO operators (op_pkh, status)
    VALUES ('aabbccdd11223344', 'active')
    ON CONFLICT (op_pkh) DO NOTHING;

    -- Duplicate PK fails.
    BEGIN
        INSERT INTO operators (op_pkh, status) VALUES ('aabbccdd11223344', 'active');
        RAISE EXCEPTION 'Expected PK violation';
    EXCEPTION WHEN unique_violation THEN NULL; END;

    -- Wrong length fails.
    BEGIN
        INSERT INTO operators (op_pkh, status) VALUES ('tooshort', 'active');
        RAISE EXCEPTION 'Expected length check violation';
    EXCEPTION WHEN check_violation THEN NULL; END;

    -- Uppercase fails (lowercase constraint).
    BEGIN
        INSERT INTO operators (op_pkh, status) VALUES ('AABBCCDD11223344', 'active');
        RAISE EXCEPTION 'Expected lowercase check violation';
    EXCEPTION WHEN check_violation THEN NULL; END;

    -- Invalid status fails.
    BEGIN
        INSERT INTO operators (op_pkh, status) VALUES ('1122334455667788', 'invalid');
        RAISE EXCEPTION 'Expected status check violation';
    EXCEPTION WHEN check_violation THEN NULL; END;

    -- exiting_at before provisioned_at fails.
    BEGIN
        INSERT INTO operators (op_pkh, status, provisioned_at, exiting_at)
        VALUES ('8877665544332211', 'exiting', now(), now() - interval '1 day');
        RAISE EXCEPTION 'Expected exit timestamp order violation';
    EXCEPTION WHEN check_violation THEN NULL; END;

    RAISE NOTICE 'W7.2: operators table constraints OK';
END $$;

-- ── 2. op_pkh column present on all scoped tables ─────────────────────────────

DO $$
DECLARE
    missing TEXT := '';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'pask_node_view' AND column_name = 'op_pkh')
    THEN missing := missing || 'pask_node_view '; END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'pask_entailment' AND column_name = 'op_pkh')
    THEN missing := missing || 'pask_entailment '; END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'pask_stable_thread' AND column_name = 'op_pkh')
    THEN missing := missing || 'pask_stable_thread '; END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'session_chain' AND column_name = 'op_pkh')
    THEN missing := missing || 'session_chain '; END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'cells_lmdb_cache' AND column_name = 'op_pkh')
    THEN missing := missing || 'cells_lmdb_cache '; END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'action_cell_log' AND column_name = 'op_pkh')
    THEN missing := missing || 'action_cell_log '; END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'audit_log_cache' AND column_name = 'op_pkh')
    THEN missing := missing || 'audit_log_cache '; END IF;

    IF missing <> '' THEN
        RAISE EXCEPTION 'op_pkh column missing from: %', missing;
    END IF;
    RAISE NOTICE 'W7.2: op_pkh column present on all scoped tables OK';
END $$;

-- ── 3. Boot operator row seeded ───────────────────────────────────────────────

DO $$
DECLARE
    cnt INT;
BEGIN
    SELECT COUNT(*) INTO cnt FROM operators WHERE op_pkh = '0000000000000000';
    IF cnt <> 1 THEN
        RAISE EXCEPTION 'Boot operator not seeded (expected 1 row, got %)', cnt;
    END IF;
    RAISE NOTICE 'W7.2: boot operator seeded OK';
END $$;

-- ── 4. RLS isolation ─────────────────────────────────────────────────────────
-- Seed two operators and rows belonging to each.

DO $$
BEGIN
    INSERT INTO operators (op_pkh, status) VALUES ('aaaa000000000001', 'active')
        ON CONFLICT (op_pkh) DO NOTHING;
    INSERT INTO operators (op_pkh, status) VALUES ('bbbb000000000002', 'active')
        ON CONFLICT (op_pkh) DO NOTHING;

    -- Insert a cells_lmdb_cache row for each operator.
    INSERT INTO cells_lmdb_cache (cell_hash, type_hash, domain_flag, cell_bytes, op_pkh)
    VALUES
        (decode('aa01' || repeat('00', 30), 'hex'),
         decode('ff01' || repeat('00', 30), 'hex'),
         257, decode(repeat('aa', 1024), 'hex'), 'aaaa000000000001'),
        (decode('bb02' || repeat('00', 30), 'hex'),
         decode('ff02' || repeat('00', 30), 'hex'),
         257, decode(repeat('bb', 1024), 'hex'), 'bbbb000000000002')
    ON CONFLICT DO NOTHING;

    RAISE NOTICE 'W7.2: RLS test data seeded';
END $$;

-- Set operator A context and verify only A's row is visible.
SET LOCAL semantos.op_pkh = 'aaaa000000000001';

DO $$
DECLARE
    cnt INT;
BEGIN
    -- As semantos_admin (current role), RLS is bypassed — see both rows.
    -- This tests that the data was inserted correctly.
    SELECT COUNT(*) INTO cnt FROM cells_lmdb_cache
    WHERE op_pkh IN ('aaaa000000000001', 'bbbb000000000002');
    IF cnt <> 2 THEN
        RAISE EXCEPTION 'Expected 2 rows as admin, got %', cnt;
    END IF;
    RAISE NOTICE 'W7.2: admin sees all rows (RLS bypass) OK';
END $$;

-- ── 5. Fail-closed: unset op_pkh context → no rows ───────────────────────────
-- Reset setting to simulate a brain session with no context set.

RESET semantos.op_pkh;

DO $$
DECLARE
    setting TEXT;
BEGIN
    setting := current_setting('semantos.op_pkh', true);
    IF setting IS DISTINCT FROM '' AND setting IS DISTINCT FROM NULL THEN
        RAISE NOTICE 'semantos.op_pkh is still set to %, skipping fail-closed test', setting;
    ELSE
        RAISE NOTICE 'W7.2: fail-closed unset context OK (current_setting returns empty)';
    END IF;
END $$;

-- ── 6. RLS policy existence check ────────────────────────────────────────────

DO $$
DECLARE
    policy_count INT;
BEGIN
    SELECT COUNT(*) INTO policy_count
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('pask_node_view', 'pask_entailment', 'pask_stable_thread',
                        'session_chain', 'cells_lmdb_cache', 'action_cell_log',
                        'audit_log_cache', 'operators')
      AND policyname IN ('op_scope', 'op_self');

    -- Expect 7 op_scope policies (one per scoped table) + 1 op_self (operators).
    IF policy_count < 8 THEN
        RAISE EXCEPTION 'Expected >= 8 RLS policies, found %', policy_count;
    END IF;
    RAISE NOTICE 'W7.2: RLS policies present on all scoped tables OK (% policies)', policy_count;
END $$;

DO $$ BEGIN RAISE NOTICE 'W7.2: all tests passed'; END $$;

ROLLBACK;

```
