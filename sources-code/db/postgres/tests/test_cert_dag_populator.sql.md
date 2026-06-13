---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/tests/test_cert_dag_populator.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.137522+00:00
---

# db/postgres/tests/test_cert_dag_populator.sql

```sql
-- M5.9-T — cert_dag populator tests.
--
-- Tests:
--   M5.9-T-insert              — 3 entries → 3 rows inserted, 3 returned
--   M5.9-T-idempotent          — same 3 entries again → 0 newly inserted
--   M5.9-T-partial-idempotent  — 2 old + 1 new → 1 newly inserted
--   M5.9-T-parent-chain        — parent inserted first, child references it via FK
--   M5.9-T-view                — cert_dag_summary returns correct counts per cert_type
--
-- Run after applying migrations 001 through 006:
--   psql -v ON_ERROR_STOP=1 -f db/postgres/tests/test_cert_dag_populator.sql

\set ON_ERROR_STOP on

-- ── M5.9-T-insert: 3 entries → 3 rows ────────────────────────────────

BEGIN;

DO $$
DECLARE
  inserted INT;
  row_count INT;
  entries JSONB := '[
    {
      "cert_hash":       "0101010101010101010101010101010101010101010101010101010101010101",
      "issuer_pub":      "aabb",
      "subject_pub":     "ccdd",
      "cert_type":       "identity",
      "cert_bytes":      "deadbeef",
      "issued_at":       "2025-01-01T00:00:00Z",
      "parent_cert_hash": null,
      "metadata":        null
    },
    {
      "cert_hash":       "0202020202020202020202020202020202020202020202020202020202020202",
      "issuer_pub":      "aabb",
      "subject_pub":     "eeff",
      "cert_type":       "capability",
      "cert_bytes":      "cafebabe",
      "issued_at":       "2025-01-02T00:00:00Z",
      "parent_cert_hash": null,
      "metadata":        {"level": 1}
    },
    {
      "cert_hash":       "0303030303030303030303030303030303030303030303030303030303030303",
      "issuer_pub":      "aabb",
      "subject_pub":     "1122",
      "cert_type":       "delegation",
      "cert_bytes":      "baadf00d",
      "issued_at":       "2025-01-03T00:00:00Z",
      "parent_cert_hash": null,
      "metadata":        null
    }
  ]'::jsonb;
BEGIN
  SELECT populate_cert_dag_from_jsonb(entries) INTO inserted;

  IF inserted <> 3 THEN
    RAISE EXCEPTION 'M5.9-T-insert: expected 3 inserted, got %', inserted;
  END IF;

  SELECT COUNT(*) INTO row_count FROM cert_dag
  WHERE cert_hash IN (
    decode('0101010101010101010101010101010101010101010101010101010101010101', 'hex'),
    decode('0202020202020202020202020202020202020202020202020202020202020202', 'hex'),
    decode('0303030303030303030303030303030303030303030303030303030303030303', 'hex')
  );

  IF row_count <> 3 THEN
    RAISE EXCEPTION 'M5.9-T-insert: expected 3 rows in cert_dag, got %', row_count;
  END IF;

  RAISE NOTICE 'M5.9-T-insert PASSED (inserted=%, rows=%)', inserted, row_count;
END $$;

ROLLBACK;

-- ── M5.9-T-idempotent: re-insert same 3 entries → 0 newly inserted ───

BEGIN;

DO $$
DECLARE
  inserted1 INT;
  inserted2 INT;
  entries JSONB := '[
    {
      "cert_hash":       "0404040404040404040404040404040404040404040404040404040404040404",
      "issuer_pub":      "aabb",
      "subject_pub":     "ccdd",
      "cert_type":       "identity",
      "cert_bytes":      "deadbeef",
      "issued_at":       "2025-02-01T00:00:00Z",
      "parent_cert_hash": null,
      "metadata":        null
    },
    {
      "cert_hash":       "0505050505050505050505050505050505050505050505050505050505050505",
      "issuer_pub":      "aabb",
      "subject_pub":     "eeff",
      "cert_type":       "capability",
      "cert_bytes":      "cafebabe",
      "issued_at":       "2025-02-02T00:00:00Z",
      "parent_cert_hash": null,
      "metadata":        null
    },
    {
      "cert_hash":       "0606060606060606060606060606060606060606060606060606060606060606",
      "issuer_pub":      "aabb",
      "subject_pub":     "1122",
      "cert_type":       "session",
      "cert_bytes":      "baadf00d",
      "issued_at":       "2025-02-03T00:00:00Z",
      "parent_cert_hash": null,
      "metadata":        null
    }
  ]'::jsonb;
BEGIN
  SELECT populate_cert_dag_from_jsonb(entries) INTO inserted1;
  IF inserted1 <> 3 THEN
    RAISE EXCEPTION 'M5.9-T-idempotent: first call expected 3, got %', inserted1;
  END IF;

  -- Second call with identical entries must insert 0 new rows.
  SELECT populate_cert_dag_from_jsonb(entries) INTO inserted2;
  IF inserted2 <> 0 THEN
    RAISE EXCEPTION 'M5.9-T-idempotent: second call expected 0, got %', inserted2;
  END IF;

  RAISE NOTICE 'M5.9-T-idempotent PASSED (first=%, second=%)', inserted1, inserted2;
END $$;

ROLLBACK;

-- ── M5.9-T-partial-idempotent: 2 old + 1 new → 1 newly inserted ──────

BEGIN;

DO $$
DECLARE
  inserted1 INT;
  inserted2 INT;
  batch1 JSONB := '[
    {
      "cert_hash":       "0707070707070707070707070707070707070707070707070707070707070707",
      "issuer_pub":      "aabb",
      "subject_pub":     "ccdd",
      "cert_type":       "identity",
      "cert_bytes":      "deadbeef",
      "issued_at":       "2025-03-01T00:00:00Z",
      "parent_cert_hash": null,
      "metadata":        null
    },
    {
      "cert_hash":       "0808080808080808080808080808080808080808080808080808080808080808",
      "issuer_pub":      "aabb",
      "subject_pub":     "eeff",
      "cert_type":       "identity",
      "cert_bytes":      "cafebabe",
      "issued_at":       "2025-03-02T00:00:00Z",
      "parent_cert_hash": null,
      "metadata":        null
    }
  ]'::jsonb;
  batch2 JSONB := '[
    {
      "cert_hash":       "0707070707070707070707070707070707070707070707070707070707070707",
      "issuer_pub":      "aabb",
      "subject_pub":     "ccdd",
      "cert_type":       "identity",
      "cert_bytes":      "deadbeef",
      "issued_at":       "2025-03-01T00:00:00Z",
      "parent_cert_hash": null,
      "metadata":        null
    },
    {
      "cert_hash":       "0808080808080808080808080808080808080808080808080808080808080808",
      "issuer_pub":      "aabb",
      "subject_pub":     "eeff",
      "cert_type":       "identity",
      "cert_bytes":      "cafebabe",
      "issued_at":       "2025-03-02T00:00:00Z",
      "parent_cert_hash": null,
      "metadata":        null
    },
    {
      "cert_hash":       "0909090909090909090909090909090909090909090909090909090909090909",
      "issuer_pub":      "aabb",
      "subject_pub":     "3344",
      "cert_type":       "revocation",
      "cert_bytes":      "ff00ff00",
      "issued_at":       "2025-03-03T00:00:00Z",
      "parent_cert_hash": null,
      "metadata":        null
    }
  ]'::jsonb;
BEGIN
  SELECT populate_cert_dag_from_jsonb(batch1) INTO inserted1;
  IF inserted1 <> 2 THEN
    RAISE EXCEPTION 'M5.9-T-partial-idempotent: batch1 expected 2, got %', inserted1;
  END IF;

  -- batch2 has the 2 existing rows + 1 new row → should return 1.
  SELECT populate_cert_dag_from_jsonb(batch2) INTO inserted2;
  IF inserted2 <> 1 THEN
    RAISE EXCEPTION 'M5.9-T-partial-idempotent: batch2 expected 1, got %', inserted2;
  END IF;

  RAISE NOTICE 'M5.9-T-partial-idempotent PASSED (batch1=%, batch2=%)', inserted1, inserted2;
END $$;

ROLLBACK;

-- ── M5.9-T-parent-chain: child references parent via FK ──────────────

BEGIN;

DO $$
DECLARE
  inserted INT;
  row_count INT;
  parent_hash TEXT := 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  child_hash  TEXT := 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  entries JSONB;
BEGIN
  -- Insert parent first (no parent_cert_hash).
  entries := jsonb_build_array(
    jsonb_build_object(
      'cert_hash',        parent_hash,
      'issuer_pub',       'aabb',
      'subject_pub',      'ccdd',
      'cert_type',        'identity',
      'cert_bytes',       'deadbeef',
      'issued_at',        '2025-04-01T00:00:00Z',
      'parent_cert_hash', NULL,
      'metadata',         NULL
    )
  );
  SELECT populate_cert_dag_from_jsonb(entries) INTO inserted;
  IF inserted <> 1 THEN
    RAISE EXCEPTION 'M5.9-T-parent-chain: parent insert expected 1, got %', inserted;
  END IF;

  -- Insert child referencing parent.
  entries := jsonb_build_array(
    jsonb_build_object(
      'cert_hash',        child_hash,
      'issuer_pub',       'ccdd',
      'subject_pub',      'eeff',
      'cert_type',        'delegation',
      'cert_bytes',       'cafebabe',
      'issued_at',        '2025-04-02T00:00:00Z',
      'parent_cert_hash', parent_hash,
      'metadata',         NULL
    )
  );
  SELECT populate_cert_dag_from_jsonb(entries) INTO inserted;
  IF inserted <> 1 THEN
    RAISE EXCEPTION 'M5.9-T-parent-chain: child insert expected 1, got %', inserted;
  END IF;

  -- Verify parent_cert_hash FK is set correctly.
  SELECT COUNT(*) INTO row_count FROM cert_dag
  WHERE cert_hash = decode(child_hash, 'hex')
    AND parent_cert_hash = decode(parent_hash, 'hex');

  IF row_count <> 1 THEN
    RAISE EXCEPTION 'M5.9-T-parent-chain: child does not reference parent correctly';
  END IF;

  RAISE NOTICE 'M5.9-T-parent-chain PASSED';
END $$;

ROLLBACK;

-- ── M5.9-T-view: cert_dag_summary counts ─────────────────────────────

BEGIN;

DO $$
DECLARE
  identity_total   INT;
  capability_total INT;
  entries JSONB := '[
    {
      "cert_hash":       "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      "issuer_pub":      "aabb",
      "subject_pub":     "ccdd",
      "cert_type":       "identity",
      "cert_bytes":      "deadbeef",
      "issued_at":       "2025-05-01T00:00:00Z",
      "parent_cert_hash": null,
      "metadata":        null
    },
    {
      "cert_hash":       "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      "issuer_pub":      "aabb",
      "subject_pub":     "eeff",
      "cert_type":       "identity",
      "cert_bytes":      "cafebabe",
      "issued_at":       "2025-05-02T00:00:00Z",
      "parent_cert_hash": null,
      "metadata":        null
    },
    {
      "cert_hash":       "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
      "issuer_pub":      "aabb",
      "subject_pub":     "1122",
      "cert_type":       "capability",
      "cert_bytes":      "baadf00d",
      "issued_at":       "2025-05-03T00:00:00Z",
      "parent_cert_hash": null,
      "metadata":        null
    }
  ]'::jsonb;
BEGIN
  PERFORM populate_cert_dag_from_jsonb(entries);

  SELECT total INTO identity_total
  FROM cert_dag_summary
  WHERE cert_type = 'identity';

  SELECT total INTO capability_total
  FROM cert_dag_summary
  WHERE cert_type = 'capability';

  IF identity_total IS NULL OR identity_total < 2 THEN
    RAISE EXCEPTION 'M5.9-T-view: expected >= 2 identity certs, got %', COALESCE(identity_total::text, 'NULL');
  END IF;

  IF capability_total IS NULL OR capability_total < 1 THEN
    RAISE EXCEPTION 'M5.9-T-view: expected >= 1 capability cert, got %', COALESCE(capability_total::text, 'NULL');
  END IF;

  RAISE NOTICE 'M5.9-T-view PASSED (identity=%, capability=%)', identity_total, capability_total;
END $$;

ROLLBACK;

\echo 'M5.9 cert_dag populator tests PASSED'

```
