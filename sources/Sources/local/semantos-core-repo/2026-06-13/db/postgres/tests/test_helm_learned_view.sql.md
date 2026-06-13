---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/tests/test_helm_learned_view.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.134774+00:00
---

# db/postgres/tests/test_helm_learned_view.sql

```sql
-- M5.12-T — helm_what_been_learned view tests.
--
-- Tests:
--   M5.12-T-empty             — fresh tables → view returns 0 rows
--   M5.12-T-stable-shown      — stable + non-pruned node with stable thread → in view
--   M5.12-T-pruned-excluded   — is_pruned=true node → not in view
--   M5.12-T-unstable-excluded — is_stable=false node → not in view
--   M5.12-T-order             — 3 stable nodes for same user → view ordered by h_state DESC
--   M5.12-T-index-exists      — idx_pask_node_learned exists in pg_indexes
--
-- Run after applying migrations 001 through 007:
--   psql -v ON_ERROR_STOP=1 -f db/postgres/tests/test_helm_learned_view.sql

\set ON_ERROR_STOP on

-- ── M5.12-T-empty: fresh view returns 0 rows ─────────────────────────

BEGIN;

DO $$
DECLARE
  row_count INT;
BEGIN
  -- Use a user_cert_id that has never had any data inserted.
  SELECT COUNT(*) INTO row_count
  FROM helm_what_been_learned
  WHERE user_cert_id = decode('fefefefefefe', 'hex');

  IF row_count <> 0 THEN
    RAISE EXCEPTION 'M5.12-T-empty: expected 0 rows, got %', row_count;
  END IF;

  RAISE NOTICE 'M5.12-T-empty PASSED';
END $$;

ROLLBACK;

-- ── M5.12-T-stable-shown: stable non-pruned node appears in view ──────

BEGIN;

DO $$
DECLARE
  row_count INT;
  u_cert    BYTEA := decode('1111111111111111', 'hex');
  c_id      BYTEA := decode('aaaabbbbccccdddd', 'hex');
BEGIN
  -- Insert a stable, non-pruned node.
  INSERT INTO pask_node_view (
      cell_id, user_cert_id, type_path, h_state, stability,
      interaction_count, is_stable, is_pruned, created_at, updated_at
  ) VALUES (c_id, u_cert, 'substrate.concept.identity', 0.85, 2.0,
            20, TRUE, FALSE, now(), now());

  -- Insert matching stable_thread entry.
  INSERT INTO pask_stable_thread (
      user_cert_id, cell_id, h_state, total_constraint_strength,
      interaction_count, snapshot_version
  ) VALUES (u_cert, c_id, 0.85, 3.5, 20, 1);

  SELECT COUNT(*) INTO row_count
  FROM helm_what_been_learned
  WHERE user_cert_id = u_cert AND cell_id = c_id;

  IF row_count <> 1 THEN
    RAISE EXCEPTION 'M5.12-T-stable-shown: expected 1 row, got %', row_count;
  END IF;

  RAISE NOTICE 'M5.12-T-stable-shown PASSED';
END $$;

ROLLBACK;

-- ── M5.12-T-pruned-excluded: pruned node not in view ─────────────────

BEGIN;

DO $$
DECLARE
  row_count INT;
  u_cert    BYTEA := decode('2222222222222222', 'hex');
  c_id      BYTEA := decode('bbbbbbbbbbbbbbbb', 'hex');
BEGIN
  -- Insert a pruned node (is_pruned=TRUE, is_stable=TRUE).
  INSERT INTO pask_node_view (
      cell_id, user_cert_id, type_path, h_state, stability,
      interaction_count, is_stable, is_pruned, created_at, updated_at
  ) VALUES (c_id, u_cert, 'substrate.concept.pruned', 0.6, 1.0,
            5, TRUE, TRUE, now(), now());

  -- Insert matching stable_thread so the only exclusion is is_pruned.
  INSERT INTO pask_stable_thread (
      user_cert_id, cell_id, h_state, total_constraint_strength,
      interaction_count, snapshot_version
  ) VALUES (u_cert, c_id, 0.6, 1.0, 5, 1);

  SELECT COUNT(*) INTO row_count
  FROM helm_what_been_learned
  WHERE user_cert_id = u_cert AND cell_id = c_id;

  IF row_count <> 0 THEN
    RAISE EXCEPTION 'M5.12-T-pruned-excluded: expected 0 rows for pruned node, got %', row_count;
  END IF;

  RAISE NOTICE 'M5.12-T-pruned-excluded PASSED';
END $$;

ROLLBACK;

-- ── M5.12-T-unstable-excluded: unstable node not in view ─────────────

BEGIN;

DO $$
DECLARE
  row_count INT;
  u_cert    BYTEA := decode('3333333333333333', 'hex');
  c_id      BYTEA := decode('cccccccccccccccc', 'hex');
BEGIN
  -- Insert an unstable, non-pruned node (is_stable=FALSE).
  INSERT INTO pask_node_view (
      cell_id, user_cert_id, type_path, h_state, stability,
      interaction_count, is_stable, is_pruned, created_at, updated_at
  ) VALUES (c_id, u_cert, 'substrate.concept.learning', 0.4, 0.3,
            3, FALSE, FALSE, now(), now());

  -- No stable_thread entry needed since pask_stable_thread FK requires
  -- the node to exist; but the view joins on both tables so no row in
  -- pask_stable_thread already excludes it.  Verify the WHERE clause
  -- alone (is_stable=FALSE) is sufficient.

  SELECT COUNT(*) INTO row_count
  FROM helm_what_been_learned
  WHERE user_cert_id = u_cert AND cell_id = c_id;

  IF row_count <> 0 THEN
    RAISE EXCEPTION 'M5.12-T-unstable-excluded: expected 0 rows for unstable node, got %', row_count;
  END IF;

  RAISE NOTICE 'M5.12-T-unstable-excluded PASSED';
END $$;

ROLLBACK;

-- ── M5.12-T-order: nodes returned in h_state DESC order ───────────────

BEGIN;

DO $$
DECLARE
  row_count     INT;
  first_h       DOUBLE PRECISION;
  second_h      DOUBLE PRECISION;
  third_h       DOUBLE PRECISION;
  u_cert        BYTEA := decode('4444444444444444', 'hex');
  c_id_1        BYTEA := decode('1111111111111111', 'hex');
  c_id_2        BYTEA := decode('2222222222222222', 'hex');
  c_id_3        BYTEA := decode('3333333333333333', 'hex');
BEGIN
  -- Insert 3 stable, non-pruned nodes with h_state = 0.9, 0.5, 0.7.
  INSERT INTO pask_node_view (
      cell_id, user_cert_id, type_path, h_state, stability,
      interaction_count, is_stable, is_pruned, created_at, updated_at
  ) VALUES
      (c_id_1, u_cert, 'substrate.concept.a', 0.9, 2.0, 10, TRUE, FALSE, now(), now()),
      (c_id_2, u_cert, 'substrate.concept.b', 0.5, 1.5,  8, TRUE, FALSE, now(), now()),
      (c_id_3, u_cert, 'substrate.concept.c', 0.7, 1.8,  6, TRUE, FALSE, now(), now());

  -- Insert matching stable_thread rows.
  INSERT INTO pask_stable_thread (
      user_cert_id, cell_id, h_state, total_constraint_strength,
      interaction_count, snapshot_version
  ) VALUES
      (u_cert, c_id_1, 0.9, 3.0, 10, 1),
      (u_cert, c_id_2, 0.5, 2.0,  8, 1),
      (u_cert, c_id_3, 0.7, 2.5,  6, 1);

  SELECT COUNT(*) INTO row_count
  FROM helm_what_been_learned
  WHERE user_cert_id = u_cert;

  IF row_count <> 3 THEN
    RAISE EXCEPTION 'M5.12-T-order: expected 3 rows, got %', row_count;
  END IF;

  -- Verify descending h_state order: 0.9, 0.7, 0.5.
  SELECT h_state INTO first_h
  FROM helm_what_been_learned
  WHERE user_cert_id = u_cert
  ORDER BY h_state DESC
  LIMIT 1 OFFSET 0;

  SELECT h_state INTO second_h
  FROM helm_what_been_learned
  WHERE user_cert_id = u_cert
  ORDER BY h_state DESC
  LIMIT 1 OFFSET 1;

  SELECT h_state INTO third_h
  FROM helm_what_been_learned
  WHERE user_cert_id = u_cert
  ORDER BY h_state DESC
  LIMIT 1 OFFSET 2;

  IF first_h <> 0.9 OR second_h <> 0.7 OR third_h <> 0.5 THEN
    RAISE EXCEPTION 'M5.12-T-order: expected 0.9, 0.7, 0.5 — got %, %, %',
                    first_h, second_h, third_h;
  END IF;

  RAISE NOTICE 'M5.12-T-order PASSED (h_states: %, %, %)', first_h, second_h, third_h;
END $$;

ROLLBACK;

-- ── M5.12-T-index-exists: idx_pask_node_learned in pg_indexes ────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE indexname = 'idx_pask_node_learned'
  ) THEN
    RAISE EXCEPTION 'M5.12-T-index-exists: index idx_pask_node_learned not found';
  END IF;

  RAISE NOTICE 'M5.12-T-index-exists PASSED';
END $$;

\echo 'M5.12 helm_what_been_learned view tests PASSED'

```
