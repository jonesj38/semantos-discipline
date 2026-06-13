---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/migrations/003_sir_program.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.140749+00:00
---

# db/postgres/migrations/003_sir_program.sql

```sql
-- M5.3 — Postgres schema: sir_program, host_reputation.
--
-- Acceptance: JSONB validation triggers in place.
-- SIR = Semantic Intent Representation; the output of Bert's intent reducer.
-- OIR = Optimised Intent Representation; a compiled form (bytecode_hash points
--       to the LMDB cell that holds the actual bytecode bytes).

BEGIN;

-- ── sir_program ───────────────────────────────────────────────────────
-- Immutable record of a compiled SIR program.
-- sir_json must conform to the SIR schema: {version, ops, inputs, outputs}.

CREATE TABLE IF NOT EXISTS sir_program (
    sir_hash        BYTEA        NOT NULL,
    sir_json        JSONB        NOT NULL,
    -- Hash of the compiled OIR bytecode cell in LMDB (M5.5 provides the FDW).
    bytecode_hash   BYTEA        NOT NULL,
    created_at      TIMESTAMPTZ  NOT NULL,
    -- Optional: which intent produced this SIR.
    intent_hash     BYTEA        REFERENCES intent (intent_hash) ON DELETE SET NULL,

    CONSTRAINT sir_program_pkey PRIMARY KEY (sir_hash)
);

CREATE INDEX IF NOT EXISTS sir_program_intent_idx ON sir_program (intent_hash)
    WHERE intent_hash IS NOT NULL;

CREATE INDEX IF NOT EXISTS sir_program_created_idx ON sir_program (created_at DESC);

-- Validate SIR JSON structure: must contain version (integer), ops (array),
-- inputs (array), outputs (array).
CREATE OR REPLACE FUNCTION validate_sir_json() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF (NEW.sir_json->>'version') IS NULL THEN
        RAISE EXCEPTION 'SIR JSON must contain "version" key';
    END IF;
    IF jsonb_typeof(NEW.sir_json->'ops') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'SIR JSON "ops" must be an array';
    END IF;
    IF jsonb_typeof(NEW.sir_json->'inputs') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'SIR JSON "inputs" must be an array';
    END IF;
    IF jsonb_typeof(NEW.sir_json->'outputs') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'SIR JSON "outputs" must be an array';
    END IF;
    RETURN NEW;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'sir_program_validate' AND tgrelid = 'sir_program'::regclass
    ) THEN
        CREATE TRIGGER sir_program_validate
            BEFORE INSERT ON sir_program
            FOR EACH ROW EXECUTE FUNCTION validate_sir_json();
    END IF;
END;
$$;

-- K7-style immutability: SIR programs are append-only; reject UPDATEs.
CREATE OR REPLACE FUNCTION prevent_sir_update() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'sir_program rows are immutable; use INSERT for new programs';
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'sir_program_immutable' AND tgrelid = 'sir_program'::regclass
    ) THEN
        CREATE TRIGGER sir_program_immutable
            BEFORE UPDATE ON sir_program
            FOR EACH ROW EXECUTE FUNCTION prevent_sir_update();
    END IF;
END;
$$;

-- ── host_reputation ───────────────────────────────────────────────────
-- Per-host (sovereign node) reputation score used by the intent router
-- to weight host selection.  Score is in [0, 100].

CREATE TABLE IF NOT EXISTS host_reputation (
    host_pub      BYTEA        NOT NULL,
    score         SMALLINT     NOT NULL DEFAULT 50,
    last_updated  TIMESTAMPTZ  NOT NULL,
    -- Opaque evidence JSON for the last reputation adjustment.
    evidence      JSONB,

    CONSTRAINT host_reputation_pkey   PRIMARY KEY (host_pub),
    CONSTRAINT host_score_range       CHECK (score >= 0 AND score <= 100)
);

CREATE INDEX IF NOT EXISTS host_reputation_score_idx ON host_reputation (score DESC);

COMMIT;

```
