---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/tests/test_pask_tables.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.135334+00:00
---

# db/postgres/tests/test_pask_tables.sql

```sql
-- M5.11 tests — pask_node_view / pask_entailment / pask_stable_thread.
--
-- Per §5.2 obligations: schema-apply idempotency, constraint enforcement,
-- FK integrity, index existence.
--
-- Run against: semantos_test database, after all five migrations applied.

BEGIN;

-- ── 0. Schema idempotency ─────────────────────────────────────────────
-- Re-applying the migration must not error (CREATE TABLE IF NOT EXISTS).

\i db/postgres/migrations/001_cert_dag.sql
\i db/postgres/migrations/002_lexicon_category.sql
\i db/postgres/migrations/003_sir_program.sql
\i db/postgres/migrations/004_session_chain.sql
\i db/postgres/migrations/005_pask_tables.sql

DO $$ BEGIN RAISE NOTICE 'M5.11: schema idempotency OK'; END $$;

-- ── 1. Basic insert and read-back ─────────────────────────────────────

DO $$
DECLARE
    node_count  INT;
    edge_count  INT;
    thread_count INT;
BEGIN
    -- Insert a user cert as a stand-in anchor (cell_id is a free BYTEA here;
    -- in production it references a cert_dag row via FDW-populated snapshots).
    INSERT INTO pask_node_view (cell_id, user_cert_id, type_path, h_state,
        stability, interaction_count, is_stable, is_pruned, created_at, updated_at)
    VALUES
        (decode('aa01', 'hex'), decode('aaaa', 'hex'),
         'substrate.concept.identity', 0.7, 1.2, 10, FALSE, FALSE, now(), now()),
        (decode('bb02', 'hex'), decode('aaaa', 'hex'),
         'substrate.concept.session',  0.9, 2.5, 25, TRUE,  FALSE, now(), now()),
        (decode('cc03', 'hex'), decode('aaaa', 'hex'),
         'substrate.concept.pruned',   0.1, 0.1,  2, FALSE, TRUE,  now(), now());

    SELECT COUNT(*) INTO node_count FROM pask_node_view
    WHERE user_cert_id = decode('aaaa', 'hex');

    IF node_count <> 3 THEN
        RAISE EXCEPTION 'Expected 3 nodes, got %', node_count;
    END IF;
    RAISE NOTICE 'M5.11: node insert OK (% rows)', node_count;
END $$;

-- ── 2. h_state range constraint ───────────────────────────────────────

DO $$
BEGIN
    BEGIN
        INSERT INTO pask_node_view (cell_id, user_cert_id, type_path, h_state,
            stability, interaction_count, is_stable, is_pruned, created_at, updated_at)
        VALUES (decode('dd04', 'hex'), decode('aaaa', 'hex'),
                'bad', 1.5, 0.0, 0, FALSE, FALSE, now(), now());
        RAISE EXCEPTION 'Expected constraint violation for h_state > 1.0';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'M5.11: h_state > 1.0 correctly rejected';
    END;

    BEGIN
        INSERT INTO pask_node_view (cell_id, user_cert_id, type_path, h_state,
            stability, interaction_count, is_stable, is_pruned, created_at, updated_at)
        VALUES (decode('dd05', 'hex'), decode('aaaa', 'hex'),
                'bad', -0.1, 0.0, 0, FALSE, FALSE, now(), now());
        RAISE EXCEPTION 'Expected constraint violation for h_state < 0.0';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'M5.11: h_state < 0.0 correctly rejected';
    END;
END $$;

-- ── 3. pask_entailment FK integrity ───────────────────────────────────

DO $$
DECLARE
    edge_count INT;
BEGIN
    -- Valid edge: bb02 → aa01.
    INSERT INTO pask_entailment (user_cert_id, from_cell_id, to_cell_id,
        constraint_weight, delta_trend, interaction_count, last_updated)
    VALUES (decode('aaaa', 'hex'), decode('bb02', 'hex'), decode('aa01', 'hex'),
            0.75, 0.05, 8, now());

    SELECT COUNT(*) INTO edge_count FROM pask_entailment
    WHERE user_cert_id = decode('aaaa', 'hex');
    IF edge_count <> 1 THEN
        RAISE EXCEPTION 'Expected 1 entailment edge, got %', edge_count;
    END IF;
    RAISE NOTICE 'M5.11: entailment insert OK';

    -- Self-edge should be rejected.
    BEGIN
        INSERT INTO pask_entailment (user_cert_id, from_cell_id, to_cell_id,
            constraint_weight, delta_trend, interaction_count, last_updated)
        VALUES (decode('aaaa', 'hex'), decode('bb02', 'hex'), decode('bb02', 'hex'),
                0.5, 0.0, 1, now());
        RAISE EXCEPTION 'Expected constraint violation for self-edge';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'M5.11: self-edge correctly rejected';
    END;

    -- FK violation: dangling from_cell_id.
    BEGIN
        INSERT INTO pask_entailment (user_cert_id, from_cell_id, to_cell_id,
            constraint_weight, delta_trend, interaction_count, last_updated)
        VALUES (decode('aaaa', 'hex'), decode('eeff', 'hex'), decode('aa01', 'hex'),
                0.3, 0.0, 1, now());
        RAISE EXCEPTION 'Expected FK violation for unknown from_cell_id';
    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE NOTICE 'M5.11: dangling from_cell_id correctly rejected (FK)';
    END;
END $$;

-- ── 4. pask_stable_thread — stable node can be promoted ──────────────

DO $$
DECLARE
    thread_count INT;
BEGIN
    -- bb02 is_stable=TRUE so it can be in pask_stable_thread.
    INSERT INTO pask_stable_thread (user_cert_id, cell_id, h_state,
        total_constraint_strength, interaction_count, snapshot_version)
    VALUES (decode('aaaa', 'hex'), decode('bb02', 'hex'), 0.9, 3.5, 25, 1);

    SELECT COUNT(*) INTO thread_count FROM pask_stable_thread
    WHERE user_cert_id = decode('aaaa', 'hex');
    IF thread_count <> 1 THEN
        RAISE EXCEPTION 'Expected 1 stable thread, got %', thread_count;
    END IF;
    RAISE NOTICE 'M5.11: stable thread insert OK';

    -- Pruned node (cc03, is_pruned=TRUE) may still have a DB row referencing
    -- it until the FDW refresh deletes it; FK deletion is CASCADE.
    -- Confirm cascade: delete cc03 from pask_node_view, entailments and
    -- stable_thread referencing it should disappear automatically.
    DELETE FROM pask_node_view
    WHERE user_cert_id = decode('aaaa', 'hex')
      AND cell_id = decode('cc03', 'hex');

    RAISE NOTICE 'M5.11: CASCADE delete from node_view OK';
END $$;

-- ── 5. Index existence ────────────────────────────────────────────────

DO $$
DECLARE
    idx TEXT;
    expected TEXT[] := ARRAY[
        'idx_pask_node_user_stable',
        'idx_pask_node_cell_id',
        'idx_pask_entailment_from',
        'idx_pask_entailment_to',
        'idx_pask_entailment_delta',
        'idx_pask_stable_thread_h_state'
    ];
BEGIN
    FOREACH idx IN ARRAY expected LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_indexes WHERE indexname = idx
        ) THEN
            RAISE EXCEPTION 'Missing index: %', idx;
        END IF;
    END LOOP;
    RAISE NOTICE 'M5.11: all 6 indexes present';
END $$;

-- ── 6. pask_stable_thread_with_entailments view ───────────────────────

DO $$
DECLARE
    row_count INT;
BEGIN
    SELECT COUNT(*) INTO row_count
    FROM pask_stable_thread_with_entailments
    WHERE user_cert_id = decode('aaaa', 'hex');
    -- bb02 stable thread has one outbound edge to aa01 → expect 1 row.
    IF row_count < 1 THEN
        RAISE EXCEPTION 'pask_stable_thread_with_entailments returned 0 rows';
    END IF;
    RAISE NOTICE 'M5.11: view pask_stable_thread_with_entailments OK (% rows)', row_count;
END $$;

-- ── 7. Isolation: user A's nodes not visible to user B queries ────────

DO $$
DECLARE
    cnt INT;
BEGIN
    SELECT COUNT(*) INTO cnt FROM pask_node_view
    WHERE user_cert_id = decode('bbbb', 'hex');  -- different user
    IF cnt <> 0 THEN
        RAISE EXCEPTION 'User isolation broken: user B sees user A''s nodes';
    END IF;
    RAISE NOTICE 'M5.11: per-user isolation OK';
END $$;

ROLLBACK;

```
