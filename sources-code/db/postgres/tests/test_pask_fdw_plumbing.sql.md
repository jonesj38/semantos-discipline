---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/tests/test_pask_fdw_plumbing.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.134223+00:00
---

# db/postgres/tests/test_pask_fdw_plumbing.sql

```sql
-- M5.11 tests — pask FDW plumbing (refresh functions + prune)
--
-- Tests:
--   M5.11-FDW-T-refresh-nodes        — refresh_pask_nodes with 2 entries → 2 rows; idempotent on repeat
--   M5.11-FDW-T-refresh-edges        — refresh_pask_edges with 1 edge → 1 row in pask_entailment
--   M5.11-FDW-T-refresh-stable-threads — refresh_pask_stable_threads with 1 thread → 1 row
--   M5.11-FDW-T-prune-stale          — node with old updated_at is marked is_pruned = true
--   M5.11-FDW-T-upsert-updates-h-state — refresh with same cell_id but new h_state updates the row
--
-- Run via:
--   psql -v ON_ERROR_STOP=1 -f db/postgres/tests/test_pask_fdw_plumbing.sql

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

-- ── M5.11-FDW-T-refresh-nodes: refresh_pask_nodes inserts 2 nodes; upsert idempotent ──

DO $$
DECLARE
  inserted   INT;
  second     INT;
  node_count INT;
  payload    JSONB;
BEGIN
  -- cell_id and user_cert_id: 32 bytes each (64 hex chars)
  payload := jsonb_build_array(
    jsonb_build_object(
      'cell_id',          lpad('a1', 64, 'a1'),
      'user_cert_id',     lpad('b1', 64, 'b1'),
      'type_path',        'semantos.concept.entity',
      'h_state',          0.75,
      'stability',        0.6,
      'interaction_count', 10,
      'is_stable',        true,
      'is_pruned',        false,
      'created_at',       '2024-01-01T00:00:00Z',
      'updated_at',       '2024-01-02T00:00:00Z'
    ),
    jsonb_build_object(
      'cell_id',          lpad('a2', 64, 'a2'),
      'user_cert_id',     lpad('b1', 64, 'b1'),
      'type_path',        'semantos.concept.action',
      'h_state',          0.5,
      'stability',        0.4,
      'interaction_count', 5,
      'is_stable',        false,
      'is_pruned',        false,
      'created_at',       '2024-01-01T00:00:00Z',
      'updated_at',       '2024-01-02T00:00:00Z'
    )
  );

  SELECT refresh_pask_nodes(payload) INTO inserted;

  IF inserted <> 2 THEN
    RAISE EXCEPTION 'M5.11-FDW-T-refresh-nodes FAILED: expected 2 inserted, got %', inserted;
  END IF;

  SELECT COUNT(*) INTO node_count FROM pask_node_view;

  IF node_count <> 2 THEN
    RAISE EXCEPTION 'M5.11-FDW-T-refresh-nodes FAILED: expected 2 rows in pask_node_view, got %', node_count;
  END IF;

  -- Second call with same payload — upsert must succeed and return 2 (rows affected)
  SELECT refresh_pask_nodes(payload) INTO second;

  IF second <> 2 THEN
    RAISE EXCEPTION 'M5.11-FDW-T-refresh-nodes FAILED: upsert expected 2 on repeat, got %', second;
  END IF;

  -- Row count must still be 2 (no duplicates)
  SELECT COUNT(*) INTO node_count FROM pask_node_view;

  IF node_count <> 2 THEN
    RAISE EXCEPTION 'M5.11-FDW-T-refresh-nodes FAILED: expected 2 rows after upsert, got %', node_count;
  END IF;
END $$;

\echo 'M5.11-FDW-T-refresh-nodes PASSED'

-- ── M5.11-FDW-T-refresh-edges: refresh_pask_edges inserts 1 edge ─────

DO $$
DECLARE
  inserted   INT;
  edge_count INT;
  node_payload JSONB;
  edge_payload JSONB;
BEGIN
  -- Must insert the referenced nodes first (FK constraint)
  node_payload := jsonb_build_array(
    jsonb_build_object(
      'cell_id',           lpad('c1', 64, 'c1'),
      'user_cert_id',      lpad('d1', 64, 'd1'),
      'type_path',         'semantos.concept.entity',
      'h_state',           0.8,
      'stability',         0.7,
      'interaction_count', 3,
      'is_stable',         true,
      'is_pruned',         false,
      'created_at',        '2024-01-01T00:00:00Z',
      'updated_at',        '2024-01-02T00:00:00Z'
    ),
    jsonb_build_object(
      'cell_id',           lpad('c2', 64, 'c2'),
      'user_cert_id',      lpad('d1', 64, 'd1'),
      'type_path',         'semantos.concept.relation',
      'h_state',           0.6,
      'stability',         0.5,
      'interaction_count', 2,
      'is_stable',         false,
      'is_pruned',         false,
      'created_at',        '2024-01-01T00:00:00Z',
      'updated_at',        '2024-01-02T00:00:00Z'
    )
  );

  PERFORM refresh_pask_nodes(node_payload);

  edge_payload := jsonb_build_array(
    jsonb_build_object(
      'from_cell_id',      lpad('c1', 64, 'c1'),
      'to_cell_id',        lpad('c2', 64, 'c2'),
      'user_cert_id',      lpad('d1', 64, 'd1'),
      'constraint_weight', 0.9,
      'delta_trend',       0.1,
      'interaction_count', 4,
      'last_updated',      '2024-01-02T00:00:00Z'
    )
  );

  SELECT refresh_pask_edges(edge_payload) INTO inserted;

  IF inserted <> 1 THEN
    RAISE EXCEPTION 'M5.11-FDW-T-refresh-edges FAILED: expected 1 inserted, got %', inserted;
  END IF;

  SELECT COUNT(*) INTO edge_count FROM pask_entailment;

  IF edge_count <> 1 THEN
    RAISE EXCEPTION 'M5.11-FDW-T-refresh-edges FAILED: expected 1 row in pask_entailment, got %', edge_count;
  END IF;
END $$;

\echo 'M5.11-FDW-T-refresh-edges PASSED'

-- ── M5.11-FDW-T-refresh-stable-threads: inserts 1 stable thread ──────

DO $$
DECLARE
  inserted      INT;
  thread_count  INT;
  node_payload  JSONB;
  thread_payload JSONB;
BEGIN
  -- Insert the referenced node first
  node_payload := jsonb_build_array(
    jsonb_build_object(
      'cell_id',           lpad('e1', 64, 'e1'),
      'user_cert_id',      lpad('f1', 64, 'f1'),
      'type_path',         'semantos.concept.stable',
      'h_state',           0.95,
      'stability',         0.9,
      'interaction_count', 20,
      'is_stable',         true,
      'is_pruned',         false,
      'created_at',        '2024-01-01T00:00:00Z',
      'updated_at',        '2024-01-02T00:00:00Z'
    )
  );

  PERFORM refresh_pask_nodes(node_payload);

  thread_payload := jsonb_build_array(
    jsonb_build_object(
      'user_cert_id',              lpad('f1', 64, 'f1'),
      'cell_id',                   lpad('e1', 64, 'e1'),
      'h_state',                   0.95,
      'total_constraint_strength', 1.5,
      'interaction_count',         20,
      'stabilised_at',             '2024-01-02T00:00:00Z',
      'snapshot_version',          42
    )
  );

  SELECT refresh_pask_stable_threads(thread_payload) INTO inserted;

  IF inserted <> 1 THEN
    RAISE EXCEPTION 'M5.11-FDW-T-refresh-stable-threads FAILED: expected 1 inserted, got %', inserted;
  END IF;

  SELECT COUNT(*) INTO thread_count FROM pask_stable_thread;

  IF thread_count <> 1 THEN
    RAISE EXCEPTION 'M5.11-FDW-T-refresh-stable-threads FAILED: expected 1 row in pask_stable_thread, got %', thread_count;
  END IF;
END $$;

\echo 'M5.11-FDW-T-refresh-stable-threads PASSED'

-- ── M5.11-FDW-T-prune-stale: prune_pask_stale_nodes marks old nodes ──

DO $$
DECLARE
  pruned_count INT;
  is_pruned_val BOOLEAN;
  node_payload  JSONB;
  user_id       BYTEA;
  cutoff        TIMESTAMPTZ;
BEGIN
  -- Insert a node with an old updated_at
  node_payload := jsonb_build_array(
    jsonb_build_object(
      'cell_id',           lpad('11', 64, '11'),
      'user_cert_id',      lpad('22', 64, '22'),
      'type_path',         'semantos.concept.stale',
      'h_state',           0.3,
      'stability',         0.1,
      'interaction_count', 1,
      'is_stable',         false,
      'is_pruned',         false,
      'created_at',        '2023-01-01T00:00:00Z',
      'updated_at',        '2023-01-01T00:00:00Z'
    )
  );

  PERFORM refresh_pask_nodes(node_payload);

  user_id := decode(lpad('22', 64, '22'), 'hex');
  cutoff  := '2024-01-01T00:00:00Z';

  SELECT prune_pask_stale_nodes(user_id, cutoff) INTO pruned_count;

  IF pruned_count <> 1 THEN
    RAISE EXCEPTION 'M5.11-FDW-T-prune-stale FAILED: expected 1 pruned, got %', pruned_count;
  END IF;

  SELECT is_pruned INTO is_pruned_val
  FROM pask_node_view
  WHERE cell_id      = decode(lpad('11', 64, '11'), 'hex')
    AND user_cert_id = user_id;

  IF is_pruned_val IS NOT TRUE THEN
    RAISE EXCEPTION 'M5.11-FDW-T-prune-stale FAILED: expected is_pruned = true';
  END IF;
END $$;

\echo 'M5.11-FDW-T-prune-stale PASSED'

-- ── M5.11-FDW-T-upsert-updates-h-state: upsert updates h_state ───────

DO $$
DECLARE
  h_val        DOUBLE PRECISION;
  node_payload JSONB;
BEGIN
  -- Insert with h_state = 0.5
  node_payload := jsonb_build_array(
    jsonb_build_object(
      'cell_id',           lpad('33', 64, '33'),
      'user_cert_id',      lpad('44', 64, '44'),
      'type_path',         'semantos.concept.evolving',
      'h_state',           0.5,
      'stability',         0.3,
      'interaction_count', 7,
      'is_stable',         false,
      'is_pruned',         false,
      'created_at',        '2024-01-01T00:00:00Z',
      'updated_at',        '2024-01-01T00:00:00Z'
    )
  );

  PERFORM refresh_pask_nodes(node_payload);

  -- Refresh again with h_state = 0.9 (same cell_id/user_cert_id)
  node_payload := jsonb_build_array(
    jsonb_build_object(
      'cell_id',           lpad('33', 64, '33'),
      'user_cert_id',      lpad('44', 64, '44'),
      'type_path',         'semantos.concept.evolving',
      'h_state',           0.9,
      'stability',         0.8,
      'interaction_count', 15,
      'is_stable',         true,
      'is_pruned',         false,
      'created_at',        '2024-01-01T00:00:00Z',
      'updated_at',        '2024-01-02T00:00:00Z'
    )
  );

  PERFORM refresh_pask_nodes(node_payload);

  SELECT h_state INTO h_val
  FROM pask_node_view
  WHERE cell_id      = decode(lpad('33', 64, '33'), 'hex')
    AND user_cert_id = decode(lpad('44', 64, '44'), 'hex');

  IF h_val IS DISTINCT FROM 0.9 THEN
    RAISE EXCEPTION 'M5.11-FDW-T-upsert-updates-h-state FAILED: expected h_state = 0.9, got %', h_val;
  END IF;
END $$;

\echo 'M5.11-FDW-T-upsert-updates-h-state PASSED'

ROLLBACK;

\echo ''
\echo 'All M5.11-FDW tests PASSED'

```
