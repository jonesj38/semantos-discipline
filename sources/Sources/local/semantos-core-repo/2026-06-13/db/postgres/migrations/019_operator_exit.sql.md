---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/migrations/019_operator_exit.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.139659+00:00
---

# db/postgres/migrations/019_operator_exit.sql

```sql
-- W7.8 — Operator exit: schema changes + cleanup function.
-- Run AFTER `brain exit-operator` succeeds (LMDB + NATS already cleaned).
--
-- Depends on: 001–018.

BEGIN;

-- ── Add 'exited' to valid status set ─────────────────────────────────────────
-- Drop and recreate the check constraint to include the new 'exited' state.

ALTER TABLE operators
    DROP CONSTRAINT IF EXISTS operators_status_valid;

ALTER TABLE operators
    ADD CONSTRAINT operators_status_valid
        CHECK (status IN ('active', 'suspended', 'exiting', 'exited'));

-- ── Add exited_at column ──────────────────────────────────────────────────────

ALTER TABLE operators
    ADD COLUMN IF NOT EXISTS exited_at TIMESTAMPTZ;

-- ── operator_exit function ────────────────────────────────────────────────────
-- Marks the operator as exited and deletes all operator-scoped rows from
-- every application table.  Refreshes op_metrics when done.
-- MUST be called AFTER `brain exit-operator` has cleaned LMDB + NATS.

CREATE OR REPLACE FUNCTION operator_exit(p_op_pkh TEXT)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    -- Mark operator as exited.
    UPDATE operators
       SET status    = 'exited',
           exited_at = now()
     WHERE op_pkh = p_op_pkh;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'operator_exit: op_pkh % not found', p_op_pkh;
    END IF;

    -- Delete all operator-scoped rows from application tables.
    DELETE FROM cells_lmdb_cache   WHERE op_pkh = p_op_pkh;
    DELETE FROM pask_node_view     WHERE op_pkh = p_op_pkh;
    DELETE FROM pask_entailment    WHERE op_pkh = p_op_pkh;
    DELETE FROM pask_stable_thread WHERE op_pkh = p_op_pkh;
    DELETE FROM session_chain      WHERE op_pkh = p_op_pkh;
    DELETE FROM action_cell_log    WHERE op_pkh = p_op_pkh;
    DELETE FROM audit_log_cache    WHERE op_pkh = p_op_pkh;

    -- Refresh the metrics view so the operator shows up as exited.
    REFRESH MATERIALIZED VIEW CONCURRENTLY op_metrics;
END;
$$;

-- ── operator_exit_verify function ────────────────────────────────────────────
-- Post-exit assertion helper.  Returns one row per table with the row count
-- that remains for the given op_pkh — all counts should be 0 after exit.

CREATE OR REPLACE FUNCTION operator_exit_verify(p_op_pkh TEXT)
RETURNS TABLE(
    table_name TEXT,
    remaining_rows BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 'cells_lmdb_cache'::TEXT,
           COUNT(*)::BIGINT
      FROM cells_lmdb_cache
     WHERE op_pkh = p_op_pkh

    UNION ALL

    SELECT 'pask_node_view'::TEXT,
           COUNT(*)::BIGINT
      FROM pask_node_view
     WHERE op_pkh = p_op_pkh

    UNION ALL

    SELECT 'pask_entailment'::TEXT,
           COUNT(*)::BIGINT
      FROM pask_entailment
     WHERE op_pkh = p_op_pkh

    UNION ALL

    SELECT 'pask_stable_thread'::TEXT,
           COUNT(*)::BIGINT
      FROM pask_stable_thread
     WHERE op_pkh = p_op_pkh

    UNION ALL

    SELECT 'session_chain'::TEXT,
           COUNT(*)::BIGINT
      FROM session_chain
     WHERE op_pkh = p_op_pkh

    UNION ALL

    SELECT 'action_cell_log'::TEXT,
           COUNT(*)::BIGINT
      FROM action_cell_log
     WHERE op_pkh = p_op_pkh

    UNION ALL

    SELECT 'audit_log_cache'::TEXT,
           COUNT(*)::BIGINT
      FROM audit_log_cache
     WHERE op_pkh = p_op_pkh;
END;
$$;

COMMIT;

```
