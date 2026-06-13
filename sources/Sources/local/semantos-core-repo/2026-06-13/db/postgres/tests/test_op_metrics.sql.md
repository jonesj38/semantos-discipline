---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/tests/test_op_metrics.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.138396+00:00
---

# db/postgres/tests/test_op_metrics.sql

```sql
-- W7.6: op_metrics materialized view tests
--
-- Run against semantos DB after applying 001..018 migrations.
-- Expected: no rows returned (all assertions pass).

-- Setup: ensure boot operator exists (idempotent)
INSERT INTO operators (op_pkh) VALUES ('0000000000000000') ON CONFLICT DO NOTHING;

-- 1. Materialized view exists
SELECT 'FAIL: op_metrics view missing' AS result
WHERE NOT EXISTS (
    SELECT 1 FROM pg_matviews WHERE matviewname = 'op_metrics'
);

-- 2. Unique index exists (required for CONCURRENTLY refresh)
SELECT 'FAIL: op_metrics_op_pkh_idx missing' AS result
WHERE NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE tablename = 'op_metrics' AND indexname = 'op_metrics_op_pkh_idx'
);

-- 3. Boot operator always appears in the view
SELECT 'FAIL: boot operator missing from op_metrics' AS result
WHERE NOT EXISTS (
    SELECT 1 FROM op_metrics WHERE op_pkh = '0000000000000000'
);

-- 4. All expected columns present
SELECT 'FAIL: expected column missing from op_metrics: ' || col AS result
FROM (VALUES
    ('op_pkh'), ('apex_domain'), ('status'), ('cell_count'), ('cell_bytes'),
    ('pask_node_count'), ('pask_edge_count'), ('events_24h'),
    ('session_count'), ('last_session_at'), ('refreshed_at')
) AS t(col)
WHERE NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'op_metrics' AND column_name = t.col
);

-- 5. Counts are non-negative
SELECT 'FAIL: negative metric in op_metrics' AS result
FROM op_metrics
WHERE cell_count < 0
   OR cell_bytes < 0
   OR pask_node_count < 0
   OR pask_edge_count < 0
   OR events_24h < 0
   OR session_count < 0
LIMIT 1;

-- 6. op_metrics_top view exists
SELECT 'FAIL: op_metrics_top view missing' AS result
WHERE NOT EXISTS (
    SELECT 1 FROM pg_views WHERE viewname = 'op_metrics_top'
);

-- Done
SELECT 'op_metrics tests passed' AS result;

```
