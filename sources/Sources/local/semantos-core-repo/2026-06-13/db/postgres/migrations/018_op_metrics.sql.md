---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/migrations/018_op_metrics.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.141023+00:00
---

# db/postgres/migrations/018_op_metrics.sql

```sql
-- W7.6: op_metrics materialized view
--
-- Per-operator resource-accounting snapshot.  Refreshed hourly via:
--   REFRESH MATERIALIZED VIEW CONCURRENTLY op_metrics;
-- (schedule via pg_cron or systemd timer on the brain host).
--
-- Source tables populated by W7.2 (op_pkh columns on cache tables)
-- and by the WSH brain as it writes cell / pask / audit data to Postgres.
--
-- Unique index on op_pkh enables CONCURRENTLY refresh (no table lock).

CREATE MATERIALIZED VIEW IF NOT EXISTS op_metrics AS
SELECT
    o.op_pkh,
    o.apex_domain,
    o.status,
    o.provisioned_at,

    -- Cell-layer metrics
    COALESCE(c.cell_count,  0)                          AS cell_count,
    COALESCE(c.cell_byte_total, 0)                      AS cell_bytes,

    -- Pask graph size
    COALESCE(pn.node_count, 0)                          AS pask_node_count,
    COALESCE(pe.edge_count, 0)                          AS pask_edge_count,

    -- Event rate (action cells logged in last 24 h)
    COALESCE(al.events_24h, 0)                          AS events_24h,

    -- Session activity
    COALESCE(sc.session_count, 0)                       AS session_count,
    sc.last_session_at,

    -- Snapshot
    now()                                               AS refreshed_at

FROM operators o

LEFT JOIN (
    SELECT  op_pkh,
            COUNT(*)                                    AS cell_count,
            SUM(octet_length(cell_bytes))               AS cell_byte_total
    FROM    cells_lmdb_cache
    GROUP BY op_pkh
) c ON c.op_pkh = o.op_pkh

LEFT JOIN (
    SELECT  op_pkh,
            COUNT(*) AS node_count
    FROM    pask_node_view
    GROUP BY op_pkh
) pn ON pn.op_pkh = o.op_pkh

LEFT JOIN (
    SELECT  op_pkh,
            COUNT(*) AS edge_count
    FROM    pask_entailment
    GROUP BY op_pkh
) pe ON pe.op_pkh = o.op_pkh

LEFT JOIN (
    SELECT  op_pkh,
            COUNT(*) FILTER (WHERE logged_at >= now() - INTERVAL '24 hours') AS events_24h
    FROM    action_cell_log
    GROUP BY op_pkh
) al ON al.op_pkh = o.op_pkh

LEFT JOIN (
    SELECT  op_pkh,
            COUNT(*)           AS session_count,
            MAX(recorded_at)   AS last_session_at
    FROM    session_chain
    GROUP BY op_pkh
) sc ON sc.op_pkh = o.op_pkh
;

-- Unique index required for REFRESH CONCURRENTLY
CREATE UNIQUE INDEX IF NOT EXISTS op_metrics_op_pkh_idx ON op_metrics (op_pkh);

-- Convenience view for admin dashboard: top-N by cell count
CREATE OR REPLACE VIEW op_metrics_top AS
SELECT  op_pkh,
        apex_domain,
        status,
        cell_count,
        cell_bytes,
        pask_node_count,
        pask_edge_count,
        events_24h,
        session_count,
        last_session_at,
        refreshed_at
FROM    op_metrics
ORDER BY cell_count DESC, pask_node_count DESC
;

```
