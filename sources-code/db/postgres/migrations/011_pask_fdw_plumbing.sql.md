---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/migrations/011_pask_fdw_plumbing.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.139925+00:00
---

# db/postgres/migrations/011_pask_fdw_plumbing.sql

```sql
-- 011_pask_fdw_plumbing.sql
--
-- M5.11: Pask FDW plumbing (staging pattern)
--
-- Implements the "FDW-lite" refresh pattern for the Pask kernel tables
-- created in 005_pask_tables.sql. A background process periodically
-- exports Pask data from the LMDB Pask snapshot (via M1.11's
-- LmdbPaskSnapshotStore) and calls these functions to upsert into the
-- target schema.
--
-- Functions provided:
--   refresh_pask_nodes(entries JSONB)          RETURNS INT
--   refresh_pask_edges(entries JSONB)          RETURNS INT
--   refresh_pask_stable_threads(entries JSONB) RETURNS INT
--   prune_pask_stale_nodes(user_cert_id BYTEA, cutoff_ts TIMESTAMPTZ) RETURNS INT
--
-- All binary fields (cell_id, user_cert_id, from_cell_id, to_cell_id)
-- arrive as hex strings and are stored as BYTEA via decode(value, 'hex').
--
-- Source-of-truth:
--   docs/prd/analyses/SEMANTOS-DB-PASKIAN-ADDENDUM.md §5.2 (FDW plumbing).
--   Follows the pattern of 009_cells_lmdb_fdw.sql and 010_audit_log_fdw.sql.

-- ── refresh_pask_nodes ────────────────────────────────────────────────
--
-- refresh_pask_nodes(entries JSONB) RETURNS INT
--
-- Accepts a JSONB array of node objects decoded from the Pask LMDB snapshot.
-- Each element matches the pask_node_view column set:
--   cell_id, user_cert_id   TEXT  — hex-encoded BYTEA (32 bytes each)
--   type_path               TEXT
--   h_state                 FLOAT (0.0–1.0)
--   stability               FLOAT (≥0.0)
--   interaction_count       INT   (≥0)
--   is_stable               BOOL
--   is_pruned               BOOL
--   created_at, updated_at  TEXT  — ISO-8601 timestamp
--
-- INSERT ON CONFLICT (user_cert_id, cell_id) DO UPDATE — nodes evolve over time.
-- Returns total rows inserted or updated.

CREATE OR REPLACE FUNCTION refresh_pask_nodes(entries JSONB)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
  entry    JSONB;
  affected INT := 0;
  n        INT;
BEGIN
  FOR entry IN SELECT jsonb_array_elements(entries)
  LOOP
    INSERT INTO pask_node_view (
      cell_id,
      user_cert_id,
      type_path,
      h_state,
      stability,
      interaction_count,
      is_stable,
      is_pruned,
      created_at,
      updated_at
    )
    VALUES (
      decode(entry->>'cell_id',      'hex'),
      decode(entry->>'user_cert_id', 'hex'),
      entry->>'type_path',
      (entry->>'h_state')::DOUBLE PRECISION,
      (entry->>'stability')::DOUBLE PRECISION,
      (entry->>'interaction_count')::INT,
      (entry->>'is_stable')::BOOLEAN,
      (entry->>'is_pruned')::BOOLEAN,
      (entry->>'created_at')::TIMESTAMPTZ,
      (entry->>'updated_at')::TIMESTAMPTZ
    )
    ON CONFLICT (user_cert_id, cell_id) DO UPDATE SET
      h_state           = EXCLUDED.h_state,
      stability         = EXCLUDED.stability,
      interaction_count = EXCLUDED.interaction_count,
      is_stable         = EXCLUDED.is_stable,
      is_pruned         = EXCLUDED.is_pruned,
      updated_at        = EXCLUDED.updated_at;

    GET DIAGNOSTICS n = ROW_COUNT;
    affected := affected + n;
  END LOOP;

  RETURN affected;
END;
$$;

-- ── refresh_pask_edges ────────────────────────────────────────────────
--
-- refresh_pask_edges(entries JSONB) RETURNS INT
--
-- Accepts a JSONB array of edge objects decoded from the Pask LMDB snapshot.
-- Each element:
--   from_cell_id, to_cell_id, user_cert_id  TEXT  — hex-encoded BYTEA
--   constraint_weight                         FLOAT (0.0–1.0)
--   delta_trend                               FLOAT
--   interaction_count                         INT   (≥0)
--   last_updated                              TEXT  — ISO-8601 timestamp
--
-- INSERT ON CONFLICT (user_cert_id, from_cell_id, to_cell_id) DO UPDATE —
-- edges evolve as the Pask kernel learns.
-- Returns total rows inserted or updated.

CREATE OR REPLACE FUNCTION refresh_pask_edges(entries JSONB)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
  entry    JSONB;
  affected INT := 0;
  n        INT;
BEGIN
  FOR entry IN SELECT jsonb_array_elements(entries)
  LOOP
    INSERT INTO pask_entailment (
      user_cert_id,
      from_cell_id,
      to_cell_id,
      constraint_weight,
      delta_trend,
      interaction_count,
      last_updated
    )
    VALUES (
      decode(entry->>'user_cert_id', 'hex'),
      decode(entry->>'from_cell_id', 'hex'),
      decode(entry->>'to_cell_id',   'hex'),
      (entry->>'constraint_weight')::DOUBLE PRECISION,
      (entry->>'delta_trend')::DOUBLE PRECISION,
      (entry->>'interaction_count')::INT,
      (entry->>'last_updated')::TIMESTAMPTZ
    )
    ON CONFLICT (user_cert_id, from_cell_id, to_cell_id) DO UPDATE SET
      constraint_weight = EXCLUDED.constraint_weight,
      delta_trend       = EXCLUDED.delta_trend,
      interaction_count = EXCLUDED.interaction_count,
      last_updated      = EXCLUDED.last_updated;

    GET DIAGNOSTICS n = ROW_COUNT;
    affected := affected + n;
  END LOOP;

  RETURN affected;
END;
$$;

-- ── refresh_pask_stable_threads ───────────────────────────────────────
--
-- refresh_pask_stable_threads(entries JSONB) RETURNS INT
--
-- Accepts a JSONB array of stable-thread objects.
-- Each element:
--   user_cert_id, cell_id             TEXT   — hex-encoded BYTEA
--   h_state                           FLOAT  (0.0–1.0)
--   total_constraint_strength         FLOAT  (≥0.0)
--   interaction_count                 INT    (≥0)
--   stabilised_at                     TEXT   — ISO-8601 timestamp
--   snapshot_version                  BIGINT (≥0)
--
-- INSERT ON CONFLICT (user_cert_id, cell_id) DO UPDATE.
-- Returns total rows inserted or updated.

CREATE OR REPLACE FUNCTION refresh_pask_stable_threads(entries JSONB)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
  entry    JSONB;
  affected INT := 0;
  n        INT;
BEGIN
  FOR entry IN SELECT jsonb_array_elements(entries)
  LOOP
    INSERT INTO pask_stable_thread (
      user_cert_id,
      cell_id,
      h_state,
      total_constraint_strength,
      interaction_count,
      stabilised_at,
      snapshot_version
    )
    VALUES (
      decode(entry->>'user_cert_id', 'hex'),
      decode(entry->>'cell_id',      'hex'),
      (entry->>'h_state')::DOUBLE PRECISION,
      (entry->>'total_constraint_strength')::DOUBLE PRECISION,
      (entry->>'interaction_count')::INT,
      (entry->>'stabilised_at')::TIMESTAMPTZ,
      (entry->>'snapshot_version')::BIGINT
    )
    ON CONFLICT (user_cert_id, cell_id) DO UPDATE SET
      h_state                   = EXCLUDED.h_state,
      total_constraint_strength = EXCLUDED.total_constraint_strength,
      interaction_count         = EXCLUDED.interaction_count,
      stabilised_at             = EXCLUDED.stabilised_at,
      snapshot_version          = EXCLUDED.snapshot_version;

    GET DIAGNOSTICS n = ROW_COUNT;
    affected := affected + n;
  END LOOP;

  RETURN affected;
END;
$$;

-- ── prune_pask_stale_nodes ────────────────────────────────────────────
--
-- prune_pask_stale_nodes(user_cert_id BYTEA, cutoff_ts TIMESTAMPTZ) RETURNS INT
--
-- Soft-prunes stale nodes for a given user after a snapshot refresh.
-- Marks nodes as is_pruned = true where:
--   updated_at < cutoff_ts AND is_pruned = false
--
-- Called by the refresh pipeline after refresh_pask_nodes() to retire
-- nodes that were absent from the latest Pask snapshot.
-- Returns count of rows marked pruned.

CREATE OR REPLACE FUNCTION prune_pask_stale_nodes(
  p_user_cert_id BYTEA,
  p_cutoff_ts    TIMESTAMPTZ
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
  pruned INT;
BEGIN
  UPDATE pask_node_view
  SET    is_pruned = true
  WHERE  user_cert_id = p_user_cert_id
    AND  updated_at   < p_cutoff_ts
    AND  is_pruned    = false;

  GET DIAGNOSTICS pruned = ROW_COUNT;
  RETURN pruned;
END;
$$;

```
