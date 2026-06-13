---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/migrations/001_cert_dag.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.144595+00:00
---

# db/postgres/migrations/001_cert_dag.sql

```sql
-- M5.1 — Postgres schema: cert_dag, intent, intent_edge.
--
-- Acceptance: DDL applies cleanly; recursive CTE walks 100 levels of
-- cert_dag in < 100 ms on 1 M rows.
--
-- Idempotency: all objects use CREATE TABLE IF NOT EXISTS / CREATE OR REPLACE.
-- Re-running this file against a database where M5.1 is already applied must
-- be a no-op with no errors.
--
-- K-invariant notes:
--   K1 linearity: enforced by the caller; cert_dag itself is append-only
--     (no UPDATE/DELETE in normal operation — audit via Pravega change feed).
--   K6 hash-chain integrity: parent_cert_hash FK creates the chain; the
--     trigger below prevents changing an existing cert row.
--   K7 immutability: once a cert_hash row is written, it must not be
--     mutated; enforced by the prevent_cert_update trigger.

BEGIN;

-- ── cert_dag ─────────────────────────────────────────────────────────
-- Directed acyclic graph of identity certificates.
-- Each node is a single certificate; parent_cert_hash forms the issuance chain.

CREATE TABLE IF NOT EXISTS cert_dag (
    cert_hash          BYTEA        NOT NULL,
    issuer_pub         BYTEA        NOT NULL,
    subject_pub        BYTEA        NOT NULL,
    cert_type          TEXT         NOT NULL,
    cert_bytes         BYTEA        NOT NULL,
    issued_at          TIMESTAMPTZ  NOT NULL,
    -- NULL for root / self-signed certs.
    parent_cert_hash   BYTEA        REFERENCES cert_dag (cert_hash) ON DELETE RESTRICT,
    -- Opaque application metadata (revocation status, trust level, etc.).
    metadata           JSONB,

    CONSTRAINT cert_dag_pkey             PRIMARY KEY (cert_hash),
    CONSTRAINT cert_dag_type_check       CHECK (cert_type IN (
        'identity', 'capability', 'delegation', 'revocation', 'session'
    )),
    CONSTRAINT cert_dag_no_self_parent   CHECK (cert_hash <> parent_cert_hash)
);

-- B+tree index on cert_hash is implicit from the PRIMARY KEY.
-- Additional index for ancestry traversal (parent → children lookups).
CREATE INDEX IF NOT EXISTS cert_dag_parent_idx ON cert_dag (parent_cert_hash)
    WHERE parent_cert_hash IS NOT NULL;

-- Compound index for per-subject cert lookups (intent reducer queries).
CREATE INDEX IF NOT EXISTS cert_dag_subject_idx ON cert_dag (subject_pub, issued_at DESC);

-- K7 immutability: reject any UPDATE on cert_dag rows.
CREATE OR REPLACE FUNCTION prevent_cert_update() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'cert_dag rows are immutable (K7); use INSERT for new certs';
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'cert_dag_immutable' AND tgrelid = 'cert_dag'::regclass
    ) THEN
        CREATE TRIGGER cert_dag_immutable
            BEFORE UPDATE ON cert_dag
            FOR EACH ROW EXECUTE FUNCTION prevent_cert_update();
    END IF;
END;
$$;

-- ── Helper function: cert_ancestors(root) ────────────────────────────
-- Returns all ancestors of a given cert (inclusive of root) using a
-- recursive CTE. Depth column counts upward from 0 at the root.
--
-- Performance target: < 100 ms for a 100-level chain on 1 M rows.
-- The cert_dag_parent_idx above is what makes this fast; the index
-- makes each recursive step an index seek rather than a seq scan.

CREATE OR REPLACE FUNCTION cert_ancestors(start_hash BYTEA)
RETURNS TABLE (
    cert_hash          BYTEA,
    parent_cert_hash   BYTEA,
    depth              INT
)
LANGUAGE SQL STABLE AS $$
    WITH RECURSIVE ancestors AS (
        -- Base: the starting cert itself.
        SELECT
            c.cert_hash,
            c.parent_cert_hash,
            0 AS depth
        FROM cert_dag c
        WHERE c.cert_hash = start_hash

        UNION ALL

        -- Recursive: walk up the issuance chain one step at a time.
        SELECT
            c.cert_hash,
            c.parent_cert_hash,
            a.depth + 1
        FROM cert_dag c
        JOIN ancestors a ON c.cert_hash = a.parent_cert_hash
    )
    SELECT cert_hash, parent_cert_hash, depth FROM ancestors;
$$;

-- ── intent ───────────────────────────────────────────────────────────
-- An intent is an input to Bert's intent reducer.  It carries a free-form
-- JSONB payload; the reducer produces a SIR program (see M5.3).

CREATE TABLE IF NOT EXISTS intent (
    intent_hash   BYTEA        NOT NULL,
    payload       JSONB        NOT NULL,
    created_at    TIMESTAMPTZ  NOT NULL,
    -- NULL until the reducer has processed this intent.
    sir_program_hash  BYTEA,

    CONSTRAINT intent_pkey  PRIMARY KEY (intent_hash)
);

CREATE INDEX IF NOT EXISTS intent_created_idx ON intent (created_at DESC);

-- ── intent_edge ───────────────────────────────────────────────────────
-- Directed dependency graph between intents.
-- edge_type describes the semantic relationship.

CREATE TABLE IF NOT EXISTS intent_edge (
    from_intent  BYTEA  NOT NULL REFERENCES intent (intent_hash) ON DELETE CASCADE,
    to_intent    BYTEA  NOT NULL REFERENCES intent (intent_hash) ON DELETE CASCADE,
    edge_type    TEXT   NOT NULL,

    CONSTRAINT intent_edge_pkey        PRIMARY KEY (from_intent, to_intent, edge_type),
    CONSTRAINT intent_edge_no_self     CHECK (from_intent <> to_intent),
    CONSTRAINT intent_edge_type_check  CHECK (edge_type IN (
        'depends_on', 'conflicts_with', 'produces', 'consumes'
    ))
);

CREATE INDEX IF NOT EXISTS intent_edge_to_idx ON intent_edge (to_intent);

COMMIT;

```
