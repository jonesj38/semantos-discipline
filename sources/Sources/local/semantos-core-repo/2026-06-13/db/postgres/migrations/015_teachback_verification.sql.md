---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/migrations/015_teachback_verification.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.144032+00:00
---

# db/postgres/migrations/015_teachback_verification.sql

```sql
-- M5.14: Teachback verification — verify sir_program_hash completeness.
--
-- Adds a verification query surface for M5-T condition 6:
-- for every action-phase cell logged in Postgres, its sir_program_hash
-- must map to an existing sir_program row.

-- action_cell_log: staging table for action-phase cells seen during load.
-- The LMDB FDW adapter writes here when it encounters a phase=0x06 cell.
CREATE TABLE IF NOT EXISTS action_cell_log (
  cell_id_hex       TEXT NOT NULL,
  sir_program_hash  BYTEA,         -- first 32 bytes of payload, NULL if missing
  logged_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT action_cell_log_pkey PRIMARY KEY (cell_id_hex)
);

-- verify_teachback_completeness() RETURNS TABLE(cell_id_hex TEXT, issue TEXT)
-- Returns rows for every action_cell_log entry where teachback is broken:
--   - sir_program_hash IS NULL (missing hash)
--   - sir_program_hash is all-zero (zeroed hash)
--   - no sir_program row exists with that sir_hash (orphan hash)
CREATE OR REPLACE FUNCTION verify_teachback_completeness()
RETURNS TABLE(cell_id_hex TEXT, issue TEXT)
LANGUAGE sql AS $$
  SELECT acl.cell_id_hex, 'missing_hash' AS issue
  FROM action_cell_log acl
  WHERE acl.sir_program_hash IS NULL
  UNION ALL
  SELECT acl.cell_id_hex, 'zeroed_hash' AS issue
  FROM action_cell_log acl
  WHERE acl.sir_program_hash IS NOT NULL
    AND acl.sir_program_hash = decode(repeat('00', 32), 'hex')
  UNION ALL
  SELECT acl.cell_id_hex, 'orphan_hash' AS issue
  FROM action_cell_log acl
  LEFT JOIN sir_program sp ON sp.sir_hash = acl.sir_program_hash
  WHERE acl.sir_program_hash IS NOT NULL
    AND acl.sir_program_hash != decode(repeat('00', 32), 'hex')
    AND sp.sir_hash IS NULL;
$$;

```
