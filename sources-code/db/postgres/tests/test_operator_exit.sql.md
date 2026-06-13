---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/tests/test_operator_exit.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.133672+00:00
---

# db/postgres/tests/test_operator_exit.sql

```sql
-- W7.8: operator exit schema + function tests
--
-- Run against semantos DB after applying 001..019 migrations.
-- Expected: no FAIL rows returned (all assertions pass).

-- 1. 'exited' is a valid status value for the operators table.
DO $$
BEGIN
    -- Insert a dummy operator with 'exited' status to verify the constraint.
    INSERT INTO operators (op_pkh, status)
    VALUES ('ffffffffffffffff', 'exited')
    ON CONFLICT (op_pkh) DO UPDATE SET status = 'exited';

    -- Clean up.
    DELETE FROM operators WHERE op_pkh = 'ffffffffffffffff';
END $$;

SELECT 'FAIL: exited is not a valid status (check constraint rejects it)' AS result
WHERE EXISTS (
    SELECT 1
    FROM information_schema.check_constraints
    WHERE constraint_name = 'operators_status_valid'
      AND check_clause NOT LIKE '%exited%'
);

-- 2. exited_at column exists on operators.
SELECT 'FAIL: exited_at column missing from operators' AS result
WHERE NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name  = 'operators'
      AND column_name = 'exited_at'
);

-- 3. operator_exit function exists.
SELECT 'FAIL: operator_exit function missing' AS result
WHERE NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'operator_exit'
      AND n.nspname = 'public'
);

-- 4. operator_exit_verify function exists.
SELECT 'FAIL: operator_exit_verify function missing' AS result
WHERE NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'operator_exit_verify'
      AND n.nspname = 'public'
);

-- 5. op_metrics view includes exited operators.
--    Insert a minimal exited operator, refresh the view, verify it appears.
DO $$
BEGIN
    INSERT INTO operators (op_pkh, status, exited_at)
    VALUES ('eeeeeeeeeeeeeeee', 'exited', now())
    ON CONFLICT (op_pkh) DO UPDATE SET status = 'exited', exited_at = now();

    REFRESH MATERIALIZED VIEW CONCURRENTLY op_metrics;
END $$;

SELECT 'FAIL: exited operator missing from op_metrics' AS result
WHERE NOT EXISTS (
    SELECT 1 FROM op_metrics WHERE op_pkh = 'eeeeeeeeeeeeeeee' AND status = 'exited'
);

-- Clean up test operator.
DELETE FROM operators WHERE op_pkh = 'eeeeeeeeeeeeeeee';
REFRESH MATERIALIZED VIEW CONCURRENTLY op_metrics;

-- Done
SELECT 'operator_exit tests passed' AS result;

```
