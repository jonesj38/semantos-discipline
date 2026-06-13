---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/migrations/013_registry_mirror_sqlite.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.142923+00:00
---

# db/postgres/migrations/013_registry_mirror_sqlite.sql

```sql
-- 013_registry_mirror_sqlite.sql
--
-- M6.4: registry_mirror_sqlite — browser-side registry mirror staging table.
--
-- Receives registry-change events from the registry-changes Pravega stream
-- and materialises the current state of octave_registry for browser clients.
-- The adapter pushes rows from this table to the browser's SQLite instance.
--
-- Event schema (from M6.3 RegistryChangeProducer):
--   kind          TEXT   — 'insert' | 'update' | 'state_change'
--   cell_id       TEXT   — hex encoding of the cell_id BYTEA primary key
--   domain_flag   u32    — domain partition flag
--   new_state     TEXT   — 'unspent' | 'spent' | 'locked' | 'quarantined'
--   octave_level  u8     — 0, 1, or 2
--   seq           u64    — monotonic sequence number from the Pravega event
--   ts_ms         u64    — wall-clock timestamp (ms since epoch)
--
-- Functions provided:
--   refresh_registry_mirror(events JSONB) RETURNS INT
--   prune_registry_mirror_spent(older_than_ms BIGINT) RETURNS INT
--
-- Source-of-truth:
--   docs/prd/M6.4 — SQLite browser-side registry mirror.
--   Follows the pattern of 012_region_ticks_pravega.sql.

-- ── registry_mirror_sqlite ────────────────────────────────────────────────
--
-- Staging table that mirrors the current state of octave_registry rows.
-- PRIMARY KEY (cell_id_hex, domain_flag) matches the octave_registry PK
-- (cell_id BYTEA, domain_flag INTEGER), stored here as hex text for easy
-- JSON serialisation to browser SQLite.

CREATE TABLE IF NOT EXISTS registry_mirror_sqlite (
  cell_id_hex   TEXT        NOT NULL,          -- hex encoding of cell_id BYTEA
  domain_flag   INTEGER     NOT NULL,
  state         TEXT        NOT NULL,          -- 'unspent','spent','locked','quarantined'
  octave_level  INTEGER     NOT NULL,          -- 0, 1, or 2
  seq           BIGINT      NOT NULL,          -- from the Pravega event
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT registry_mirror_sqlite_pkey PRIMARY KEY (cell_id_hex, domain_flag),
  CONSTRAINT registry_mirror_state_valid CHECK (state IN ('unspent','spent','locked','quarantined')),
  CONSTRAINT registry_mirror_octave_valid CHECK (octave_level IN (0,1,2))
);

-- Supports efficient domain-scoped queries from the adapter.
CREATE INDEX IF NOT EXISTS idx_rms_domain ON registry_mirror_sqlite(domain_flag);

-- Partial index on unspent rows — the hot path for pointer-cell escalation checks.
CREATE INDEX IF NOT EXISTS idx_rms_state  ON registry_mirror_sqlite(state) WHERE state = 'unspent';

-- ── refresh_registry_mirror ───────────────────────────────────────────────
--
-- refresh_registry_mirror(events JSONB) RETURNS INT
--
-- Accepts a JSONB array of registry-change event objects from the Pravega
-- registry-changes stream.  Each element matches the M6.3 event schema.
--
-- Upsert semantics:
--   • On first insert for (cell_id_hex, domain_flag): always inserts.
--   • On conflict: only updates when EXCLUDED.seq > existing seq (ordering
--     guard).  This makes replaying old Pravega segments idempotent and
--     ensures out-of-order delivery cannot revert a newer state.
--
-- Returns count of rows actually inserted or updated (rows where seq guard
-- passed).  Returns 0 for events that were skipped due to stale seq.

CREATE OR REPLACE FUNCTION refresh_registry_mirror(events JSONB) RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE
  ev JSONB;
  n  INT := 0;
BEGIN
  FOR ev IN SELECT * FROM jsonb_array_elements(events)
  LOOP
    INSERT INTO registry_mirror_sqlite (cell_id_hex, domain_flag, state, octave_level, seq)
    VALUES (
      ev->>'cell_id',
      (ev->>'domain_flag')::INTEGER,
      ev->>'new_state',
      (ev->>'octave_level')::INTEGER,
      (ev->>'seq')::BIGINT
    )
    ON CONFLICT (cell_id_hex, domain_flag) DO UPDATE
      SET state        = EXCLUDED.state,
          octave_level = EXCLUDED.octave_level,
          seq          = EXCLUDED.seq,
          updated_at   = now()
      WHERE EXCLUDED.seq > registry_mirror_sqlite.seq;

    IF FOUND THEN n := n + 1; END IF;
  END LOOP;
  RETURN n;
END;
$$;

-- ── prune_registry_mirror_spent ───────────────────────────────────────────
--
-- prune_registry_mirror_spent(older_than_ms BIGINT) RETURNS INT
--
-- Hard-deletes spent rows whose updated_at is older than older_than_ms
-- milliseconds ago.  Used by the adapter to bound table growth after cells
-- are confirmed spent by the network.
--
-- Passing older_than_ms=0 removes all spent rows regardless of age
-- (elapsed milliseconds > 0 is always true once any time has passed;
-- in tests with a freshly inserted row the sub-millisecond elapsed time
-- satisfies the >= comparison via the > 0 effective boundary).
--
-- Returns count of rows deleted.

CREATE OR REPLACE FUNCTION prune_registry_mirror_spent(older_than_ms BIGINT) RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE n INT;
BEGIN
  DELETE FROM registry_mirror_sqlite
  WHERE state = 'spent'
    AND EXTRACT(EPOCH FROM (now() - updated_at)) * 1000 >= older_than_ms;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

```
