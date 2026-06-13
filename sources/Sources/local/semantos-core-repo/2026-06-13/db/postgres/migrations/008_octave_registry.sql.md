---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/migrations/008_octave_registry.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.141295+00:00
---

# db/postgres/migrations/008_octave_registry.sql

```sql
-- 008_octave_registry.sql
--
-- M6.1: octave_registry — source of truth for octave cell routing.
--
-- Enforces:
--   K1 (linearity): linear cells may only be 'unspent' or 'spent';
--                   spent_at must be set iff state = 'spent'.
--   K7 (immutability): content_hash, linearity_type, octave_level are
--                      read-only after pack (enforced via trigger).

-- ── Types ─────────────────────────────────────────────────────────────

DO $$ BEGIN
  CREATE TYPE octave_level AS ENUM ('0', '1', '2');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE cell_state AS ENUM ('unspent', 'spent', 'locked', 'quarantined');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE linearity_type AS ENUM ('linear', 'affine', 'relevant', 'unrestricted');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── Table ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS octave_registry (
  -- Identity
  cell_id       BYTEA NOT NULL,               -- 32-byte cell hash (K6: hash-chain identifier)
  domain_flag   INTEGER NOT NULL,             -- 4-byte governance domain flag

  -- Octave routing
  octave_level  octave_level NOT NULL,        -- which storage tier
  octave_addr   TEXT,                         -- tier-specific address (null for octave_0)

  -- Content integrity (K7: immutable after pack)
  content_hash  BYTEA NOT NULL,               -- SHA-256 of 1024-byte cell body
  cell_size     INTEGER NOT NULL DEFAULT 1024 CHECK (cell_size = 1024),

  -- Linearity tracking (K1)
  linearity_type linearity_type NOT NULL DEFAULT 'unrestricted',
  state         cell_state NOT NULL DEFAULT 'unspent',

  -- Ownership
  owner_cert_id BYTEA,                        -- cert_id of the cell owner (nullable: system cells)

  -- Timing
  registered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  spent_at      TIMESTAMPTZ,                  -- set when state → 'spent'

  CONSTRAINT octave_registry_pkey PRIMARY KEY (cell_id, domain_flag),

  -- K1: linear cells can only be unspent or spent (not locked/quarantined in normal flow)
  CONSTRAINT k1_linear_state CHECK (
    linearity_type <> 'linear' OR state IN ('unspent', 'spent')
  ),

  -- K1: spent_at must be set iff state = 'spent'
  CONSTRAINT k1_spent_at_consistency CHECK (
    (state = 'spent' AND spent_at IS NOT NULL) OR
    (state <> 'spent' AND spent_at IS NULL)
  ),

  -- Octave addr: required for octave_1 and octave_2; null for octave_0
  CONSTRAINT octave_addr_required CHECK (
    (octave_level = '0' AND octave_addr IS NULL) OR
    octave_level IN ('1', '2')
  ),

  -- content_hash must be exactly 32 bytes
  CONSTRAINT content_hash_length CHECK (length(content_hash) = 32)
);

-- ── Indexes ───────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_octave_registry_domain  ON octave_registry(domain_flag);
CREATE INDEX IF NOT EXISTS idx_octave_registry_owner   ON octave_registry(owner_cert_id) WHERE owner_cert_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_octave_registry_unspent ON octave_registry(linearity_type, state) WHERE state = 'unspent';

-- ── K7 immutability trigger ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION enforce_cell_immutability()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.content_hash <> OLD.content_hash THEN
    RAISE EXCEPTION 'K7 violation: content_hash is immutable after pack';
  END IF;
  IF NEW.linearity_type <> OLD.linearity_type THEN
    RAISE EXCEPTION 'K7 violation: linearity_type is immutable after pack';
  END IF;
  IF NEW.octave_level <> OLD.octave_level THEN
    RAISE EXCEPTION 'K7 violation: octave_level is immutable after pack';
  END IF;
  RETURN NEW;
END;
$$;

DO $$ BEGIN
  CREATE TRIGGER trg_enforce_cell_immutability
    BEFORE UPDATE ON octave_registry
    FOR EACH ROW EXECUTE FUNCTION enforce_cell_immutability();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

```
