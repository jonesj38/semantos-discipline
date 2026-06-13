---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/migrations/009_cells_lmdb_fdw.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.142655+00:00
---

# db/postgres/migrations/009_cells_lmdb_fdw.sql

```sql
-- 009_cells_lmdb_fdw.sql
--
-- M5.5: cells_lmdb FDW (staging pattern)
--
-- Implements a "FDW-lite" pattern: a background process periodically exports
-- cells from LMDB and calls refresh_cells_lmdb(cells JSONB) to populate the
-- staging table. The cells_lmdb view provides the SQL-queryable surface.
--
-- Callers use:
--   SELECT cell_bytes FROM cells_lmdb WHERE type_hash = $1
--
-- The refresh function accepts a JSONB array where each element has:
--   cell_hash   TEXT  — hex-encoded 32-byte hash
--   type_hash   TEXT  — hex-encoded 32-byte type discriminator (cell header offset 64)
--   domain_flag INT   — governance domain flag
--   cell_bytes  TEXT  — hex-encoded cell body (1024 bytes = 2048 hex chars)

-- ── Staging table ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS cells_lmdb_cache (
  cell_hash   BYTEA       PRIMARY KEY,              -- 32 bytes
  type_hash   BYTEA       NOT NULL,                 -- 32 bytes (cell header offset 64)
  domain_flag INTEGER     NOT NULL,
  cell_bytes  BYTEA       NOT NULL,                 -- 1024 bytes (canonical cell size)
  cached_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Indexes ───────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_cells_lmdb_type_hash ON cells_lmdb_cache(type_hash);

-- ── View — the "foreign table" surface ───────────────────────────────

CREATE OR REPLACE VIEW cells_lmdb AS
  SELECT cell_hash, type_hash, domain_flag, cell_bytes, cached_at
  FROM cells_lmdb_cache;

-- ── Refresh function ──────────────────────────────────────────────────
--
-- refresh_cells_lmdb(cells JSONB) RETURNS INT
--
-- Accepts a JSONB array of cell objects (hex-encoded fields).
-- Inserts new rows; skips duplicates (ON CONFLICT DO NOTHING).
-- Returns the count of newly inserted rows.

CREATE OR REPLACE FUNCTION refresh_cells_lmdb(cells JSONB)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
  cell      JSONB;
  inserted  INT := 0;
  n         INT;
BEGIN
  FOR cell IN SELECT jsonb_array_elements(cells)
  LOOP
    INSERT INTO cells_lmdb_cache (cell_hash, type_hash, domain_flag, cell_bytes)
    VALUES (
      decode(cell->>'cell_hash',   'hex'),
      decode(cell->>'type_hash',   'hex'),
      (cell->>'domain_flag')::INTEGER,
      decode(cell->>'cell_bytes',  'hex')
    )
    ON CONFLICT (cell_hash) DO NOTHING;

    GET DIAGNOSTICS n = ROW_COUNT;
    inserted := inserted + n;
  END LOOP;

  RETURN inserted;
END;
$$;

```
