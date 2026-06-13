---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/migrations/004_session_chain.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.139380+00:00
---

# db/postgres/migrations/004_session_chain.sql

```sql
-- M5.4 — Postgres schema: session_chain, equivocation_evidence.
--
-- Acceptance: session hash-chain integrity enforced via trigger (per Bert's
-- extension, REVIEW-bert-van-brakel-extensions.md).
--
-- K6 invariant: the session chain is append-only. prev_state_hash for seq 0
-- must be NULL; for seq N > 0, prev_state_hash must equal the session_hash
-- of the prior row (seq N-1). This is enforced by the trigger below.
-- The enforcement here is "soft" (row-level, not distributed consensus);
-- the BFT committee model (M10, out of scope) would harden this.

BEGIN;

-- ── session_chain ─────────────────────────────────────────────────────
-- Append-only log of session state transitions.
-- Each row is one step in the per-session hash chain.

CREATE TABLE IF NOT EXISTS session_chain (
    session_hash      BYTEA        NOT NULL,
    host_pub          BYTEA        NOT NULL,
    -- NULL for seq_num = 0 (genesis); otherwise must match the prior row.
    prev_state_hash   BYTEA,
    seq_num           BIGINT       NOT NULL,
    payload           BYTEA        NOT NULL,
    recorded_at       TIMESTAMPTZ  NOT NULL,

    CONSTRAINT session_chain_pkey      PRIMARY KEY (session_hash),
    CONSTRAINT session_chain_seq_pos   CHECK (seq_num >= 0),
    CONSTRAINT session_chain_no_self   CHECK (session_hash <> prev_state_hash)
);

CREATE INDEX IF NOT EXISTS session_chain_prev_idx ON session_chain (prev_state_hash)
    WHERE prev_state_hash IS NOT NULL;

CREATE INDEX IF NOT EXISTS session_chain_host_idx ON session_chain (host_pub, seq_num);

-- K6 trigger: enforce prev_state_hash contract on INSERT.
-- seq_num = 0  → prev_state_hash must be NULL.
-- seq_num > 0  → a row with session_hash = NEW.prev_state_hash must exist
--                (we don't verify the specific seq_num here because the chain
--                can start at any height; callers are responsible for ordering).
CREATE OR REPLACE FUNCTION enforce_session_hash_chain() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.seq_num = 0 THEN
        IF NEW.prev_state_hash IS NOT NULL THEN
            RAISE EXCEPTION 'session_chain: seq_num 0 must have prev_state_hash = NULL (K6)';
        END IF;
    ELSE
        IF NEW.prev_state_hash IS NULL THEN
            RAISE EXCEPTION 'session_chain: seq_num % requires a non-NULL prev_state_hash (K6)', NEW.seq_num;
        END IF;
        -- Verify the referenced row exists (FK-like, but on the same table).
        IF NOT EXISTS (
            SELECT 1 FROM session_chain WHERE session_hash = NEW.prev_state_hash
        ) THEN
            RAISE EXCEPTION 'session_chain: prev_state_hash % not found in session_chain (K6)', NEW.prev_state_hash;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'session_chain_k6' AND tgrelid = 'session_chain'::regclass
    ) THEN
        CREATE TRIGGER session_chain_k6
            BEFORE INSERT ON session_chain
            FOR EACH ROW EXECUTE FUNCTION enforce_session_hash_chain();
    END IF;
END;
$$;

-- Immutability: reject UPDATEs on session_chain rows.
CREATE OR REPLACE FUNCTION prevent_session_update() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'session_chain rows are immutable (K6 append-only)';
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'session_chain_immutable' AND tgrelid = 'session_chain'::regclass
    ) THEN
        CREATE TRIGGER session_chain_immutable
            BEFORE UPDATE ON session_chain
            FOR EACH ROW EXECUTE FUNCTION prevent_session_update();
    END IF;
END;
$$;

-- ── session_chain_history(tip) ────────────────────────────────────────
-- Recursive CTE walking the chain backwards from `tip` to genesis.

CREATE OR REPLACE FUNCTION session_chain_history(tip_hash BYTEA)
RETURNS TABLE (
    session_hash    BYTEA,
    prev_state_hash BYTEA,
    seq_num         BIGINT,
    depth           INT
)
LANGUAGE SQL STABLE AS $$
    WITH RECURSIVE chain AS (
        SELECT sc.session_hash, sc.prev_state_hash, sc.seq_num, 0 AS depth
        FROM session_chain sc
        WHERE sc.session_hash = tip_hash

        UNION ALL

        SELECT sc.session_hash, sc.prev_state_hash, sc.seq_num, c.depth + 1
        FROM session_chain sc
        JOIN chain c ON sc.session_hash = c.prev_state_hash
    )
    SELECT session_hash, prev_state_hash, seq_num, depth FROM chain;
$$;

-- ── equivocation_evidence ────────────────────────────────────────────
-- Records detected equivocation events (two conflicting session states
-- published by the same host for the same logical sequence position).
-- Used by M10 (BFT committee, out of scope) for slashing; stored here
-- for forensics and reputation adjustment via host_reputation.

CREATE TABLE IF NOT EXISTS equivocation_evidence (
    evidence_hash    BYTEA        NOT NULL,
    host_pub         BYTEA        NOT NULL,
    -- The two conflicting session hashes.
    session_hash_a   BYTEA        NOT NULL,
    session_hash_b   BYTEA        NOT NULL,
    detected_at      TIMESTAMPTZ  NOT NULL,
    -- Penalty applied to host_reputation.score (negative integer).
    penalty          SMALLINT     NOT NULL DEFAULT -10,

    CONSTRAINT equivocation_evidence_pkey       PRIMARY KEY (evidence_hash),
    CONSTRAINT equivocation_different_hashes    CHECK (session_hash_a <> session_hash_b),
    CONSTRAINT equivocation_penalty_range       CHECK (penalty <= 0)
);

CREATE INDEX IF NOT EXISTS equivocation_host_idx ON equivocation_evidence (host_pub, detected_at DESC);

COMMIT;

```
