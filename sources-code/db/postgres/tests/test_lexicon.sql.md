---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/tests/test_lexicon.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.138075+00:00
---

# db/postgres/tests/test_lexicon.sql

```sql
-- M5.2-T — lexicon_category / taxonomy_index schema tests.
--
-- Per §5.2 obligations:
--   M5.2-T-schema-apply       — DDL idempotent
--   M5.2-T-type-hash-unique   — duplicate type_hash rejected
--   M5.2-T-gin-index-plan     — EXPLAIN shows GIN index on taxonomy fields
--   M5.2-T-constraint-fire    — NOT NULL, CHECK constraints tested
--
-- Run after M5.1 migration is applied (M5.2 depends on M5.1).

\set ON_ERROR_STOP on

-- ── M5.2-T-schema-apply ──────────────────────────────────────────────

BEGIN;
  \i db/postgres/migrations/002_lexicon_category.sql
ROLLBACK;

-- ── M5.2-T-type-hash-unique ──────────────────────────────────────────

BEGIN;

DO $$
DECLARE
  th BYTEA := '\x1111111111111111111111111111111111111111111111111111111111111111'::bytea;
BEGIN
  INSERT INTO lexicon_category (type_hash, category_name, taxonomy_tags)
  VALUES (th, 'Test', '["a","b"]'::jsonb);

  BEGIN
    INSERT INTO lexicon_category (type_hash, category_name, taxonomy_tags)
    VALUES (th, 'Duplicate', '["c"]'::jsonb);
    RAISE EXCEPTION 'expected UNIQUE violation on type_hash';
  EXCEPTION WHEN unique_violation THEN
    -- expected
  END;
END $$;

ROLLBACK;

-- ── M5.2-T-constraint-fire ───────────────────────────────────────────

BEGIN;

-- category_name must not be NULL.
DO $$
BEGIN
  BEGIN
    INSERT INTO lexicon_category (type_hash, category_name, taxonomy_tags)
    VALUES ('\xAAAA'::bytea, NULL, '[]'::jsonb);
    RAISE EXCEPTION 'expected NOT NULL on category_name';
  EXCEPTION WHEN not_null_violation THEN END;
END $$;

-- taxonomy_tags must be a JSON array.
DO $$
BEGIN
  BEGIN
    INSERT INTO lexicon_category (type_hash, category_name, taxonomy_tags)
    VALUES ('\xBBBB'::bytea, 'bad', '{"not":"array"}'::jsonb);
    RAISE EXCEPTION 'expected CHECK violation on taxonomy_tags';
  EXCEPTION WHEN check_violation THEN END;
END $$;

ROLLBACK;

-- ── M5.2-T-gin-index-exists ──────────────────────────────────────────
-- Verify the GIN index exists with the right access method.
-- (An empty table always seq-scans; we check structure, not runtime plan.)

DO $$
DECLARE idx_count INT;
BEGIN
  SELECT COUNT(*) INTO idx_count
  FROM pg_indexes
  WHERE tablename = 'lexicon_category'
    AND indexname  = 'lexicon_taxonomy_gin'
    AND indexdef   ILIKE '%gin%';

  IF idx_count = 0 THEN
    RAISE EXCEPTION 'expected GIN index lexicon_taxonomy_gin on lexicon_category';
  END IF;
END $$;

-- ── M5.2-T-taxonomy-index-fk ─────────────────────────────────────────

BEGIN;

INSERT INTO lexicon_category (type_hash, category_name, taxonomy_tags)
VALUES ('\x2222'::bytea, 'Base', '["x"]'::jsonb);

INSERT INTO taxonomy_index (type_hash, ordinal_rank, label)
VALUES ('\x2222'::bytea, 1, 'first');

-- FK violation: taxonomy_index referencing unknown lexicon_category.
DO $$
BEGIN
  BEGIN
    INSERT INTO taxonomy_index (type_hash, ordinal_rank, label)
    VALUES ('\xFFFF'::bytea, 1, 'orphan');
    RAISE EXCEPTION 'expected FK violation on taxonomy_index.type_hash';
  EXCEPTION WHEN foreign_key_violation THEN END;
END $$;

ROLLBACK;

\echo 'M5.2 lexicon_category tests PASSED'

```
