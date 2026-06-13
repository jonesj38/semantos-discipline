---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/tests/test_byod_domains.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.137258+00:00
---

# db/postgres/tests/test_byod_domains.sql

```sql
-- W7.14 — BYOD domain column and index acceptance tests.
--
-- Verifies that 017_operators_rls.sql created the expected columns and
-- indexes for bring-your-own-domain support.

BEGIN;

-- 1. apex_domain column exists and accepts a valid FQDN.
DO $$
BEGIN
    ASSERT (
        SELECT COUNT(*) > 0
          FROM information_schema.columns
         WHERE table_name = 'operators'
           AND column_name = 'apex_domain'
    ), 'operators.apex_domain column missing';
END $$;

-- 2. brain_domain column exists and accepts a valid FQDN.
DO $$
BEGIN
    ASSERT (
        SELECT COUNT(*) > 0
          FROM information_schema.columns
         WHERE table_name = 'operators'
           AND column_name = 'brain_domain'
    ), 'operators.brain_domain column missing';
END $$;

-- 3. brain_domain index exists (used for SNI routing lookup).
DO $$
BEGIN
    ASSERT (
        SELECT COUNT(*) > 0
          FROM pg_indexes
         WHERE tablename = 'operators'
           AND indexname  = 'idx_operators_brain_domain'
    ), 'idx_operators_brain_domain index missing';
END $$;

-- 4. apex_domain index exists.
DO $$
BEGIN
    ASSERT (
        SELECT COUNT(*) > 0
          FROM pg_indexes
         WHERE tablename = 'operators'
           AND indexname  = 'idx_operators_apex_domain'
    ), 'idx_operators_apex_domain index missing';
END $$;

-- 5. brain_domain is nullable (operators without BYOD use NULL).
DO $$
BEGIN
    ASSERT (
        SELECT is_nullable = 'YES'
          FROM information_schema.columns
         WHERE table_name  = 'operators'
           AND column_name = 'brain_domain'
    ), 'operators.brain_domain should be nullable';
END $$;

ROLLBACK;

```
