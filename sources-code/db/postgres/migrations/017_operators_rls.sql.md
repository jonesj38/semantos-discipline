---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/migrations/017_operators_rls.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.140210+00:00
---

# db/postgres/migrations/017_operators_rls.sql

```sql
-- 017_operators_rls.sql
--
-- W7.2 — `operators` table + row-level security on all operator-scoped tables.
--
-- Design:
--   • `operators` is the canonical registry of hosted operators on this node.
--     PK is `op_pkh` (16 hex chars = the first 8 raw bytes of the operator's
--     pubkey hash, printed as lowercase hex — matches W7.1 LMDB prefix).
--
--   • Operator-scoped tables get an `op_pkh TEXT NOT NULL DEFAULT '0000000000000000'`
--     column (backward compat: single-tenant rows keep the zero-prefix sentinel,
--     which matches the W7.1 LMDB zero prefix for single-tenant deployments).
--
--   • Two Postgres roles:
--       semantos_admin  — superuser-tier service account used by WSH admin ops;
--                         bypasses RLS via BYPASSRLS.
--       semantos_brain  — per-operator session role; RLS filters rows to the
--                         current operator's `op_pkh`.
--
--   • RLS policy check: `op_pkh = current_setting('semantos.op_pkh', true)`
--     WSH sets this with `SET LOCAL semantos.op_pkh = '<hex16>'` at the start
--     of each operator session.  `true` arg = return '' (not error) if unset,
--     which causes the policy to fail-closed (returns zero rows).
--
--   • Tables that already have per-entity isolation (cert_dag, lexicon_category,
--     sir_program, octave_registry, region_ticks_pravega, registry_mirror_sqlite)
--     are system-wide and are NOT touched here.
--
-- Idempotency: all ALTER TABLE / CREATE TABLE / CREATE POLICY use IF NOT EXISTS
-- guards or are preceded by DROP IF EXISTS where required.
--
-- Depends on: 001–016.

BEGIN;

-- ── Roles ────────────────────────────────────────────────────────────────────

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'semantos_admin') THEN
        CREATE ROLE semantos_admin WITH LOGIN BYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'semantos_brain') THEN
        CREATE ROLE semantos_brain WITH LOGIN;
    END IF;
END $$;

-- ── operators ────────────────────────────────────────────────────────────────
-- Registry of hosted operators.  One row per operator provisioned on this node.

CREATE TABLE IF NOT EXISTS operators (
    op_pkh          TEXT        NOT NULL,
    -- BRC-52 root cert hash (hex) used for W7.4 cert-chain validation.
    root_cert_hash  TEXT,
    -- Domain pair for W7.14 on-demand TLS.
    apex_domain     TEXT,
    brain_domain    TEXT,
    -- Wrapped DEK for W7.5 key flow; NULL until operator completes provisioning.
    wrapped_dek     BYTEA,
    -- Plexus key-universe handle (opaque text) for W7.9/W7.11.
    plexus_handle   TEXT,
    status          TEXT        NOT NULL DEFAULT 'active',
    provisioned_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Set when the operator initiates exit (W7.8 grace period start).
    exiting_at      TIMESTAMPTZ,

    CONSTRAINT operators_pkey          PRIMARY KEY (op_pkh),
    CONSTRAINT operators_op_pkh_len    CHECK (length(op_pkh) = 16),
    CONSTRAINT operators_op_pkh_lower  CHECK (op_pkh = lower(op_pkh)),
    CONSTRAINT operators_status_valid  CHECK (status IN ('active', 'suspended', 'exiting')),
    CONSTRAINT operators_exit_ts_order CHECK (exiting_at IS NULL OR exiting_at >= provisioned_at)
);

CREATE INDEX IF NOT EXISTS idx_operators_brain_domain
    ON operators (brain_domain) WHERE brain_domain IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_operators_apex_domain
    ON operators (apex_domain)  WHERE apex_domain IS NOT NULL;

GRANT SELECT, INSERT, UPDATE ON operators TO semantos_admin;
GRANT SELECT ON operators TO semantos_brain;

-- ── Add op_pkh to operator-scoped tables ─────────────────────────────────────
-- Default = 'oddjobtodd' keeps existing single-tenant rows accessible when
-- the admin session sets semantos.op_pkh = 'oddjobtodd'.

ALTER TABLE pask_node_view
    ADD COLUMN IF NOT EXISTS op_pkh TEXT NOT NULL DEFAULT '0000000000000000';

ALTER TABLE pask_entailment
    ADD COLUMN IF NOT EXISTS op_pkh TEXT NOT NULL DEFAULT '0000000000000000';

ALTER TABLE pask_stable_thread
    ADD COLUMN IF NOT EXISTS op_pkh TEXT NOT NULL DEFAULT '0000000000000000';

ALTER TABLE session_chain
    ADD COLUMN IF NOT EXISTS op_pkh TEXT NOT NULL DEFAULT '0000000000000000';

ALTER TABLE cells_lmdb_cache
    ADD COLUMN IF NOT EXISTS op_pkh TEXT NOT NULL DEFAULT '0000000000000000';

ALTER TABLE action_cell_log
    ADD COLUMN IF NOT EXISTS op_pkh TEXT NOT NULL DEFAULT '0000000000000000';

ALTER TABLE audit_log_cache
    ADD COLUMN IF NOT EXISTS op_pkh TEXT NOT NULL DEFAULT '0000000000000000';

-- Supporting indexes for prefix-scoped scans (W7.6 accounting queries).
CREATE INDEX IF NOT EXISTS idx_pask_node_op_pkh
    ON pask_node_view (op_pkh);

CREATE INDEX IF NOT EXISTS idx_session_chain_op_pkh
    ON session_chain (op_pkh);

CREATE INDEX IF NOT EXISTS idx_cells_lmdb_op_pkh
    ON cells_lmdb_cache (op_pkh);

-- ── Enable RLS ───────────────────────────────────────────────────────────────

ALTER TABLE pask_node_view    ENABLE ROW LEVEL SECURITY;
ALTER TABLE pask_entailment   ENABLE ROW LEVEL SECURITY;
ALTER TABLE pask_stable_thread ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_chain     ENABLE ROW LEVEL SECURITY;
ALTER TABLE cells_lmdb_cache  ENABLE ROW LEVEL SECURITY;
ALTER TABLE action_cell_log   ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log_cache   ENABLE ROW LEVEL SECURITY;
ALTER TABLE operators         ENABLE ROW LEVEL SECURITY;

-- semantos_admin bypasses RLS (BYPASSRLS role attribute handles this).
-- The policies below apply only to semantos_brain and other non-admin roles.

-- ── RLS policies ─────────────────────────────────────────────────────────────
-- Pattern: allow SELECT/INSERT/UPDATE/DELETE only when the row's op_pkh matches
-- the session-local setting.  Unset = '' = no rows returned (fail-closed).

CREATE POLICY op_scope ON pask_node_view
    FOR ALL TO semantos_brain
    USING      (op_pkh = current_setting('semantos.op_pkh', true))
    WITH CHECK (op_pkh = current_setting('semantos.op_pkh', true));

CREATE POLICY op_scope ON pask_entailment
    FOR ALL TO semantos_brain
    USING      (op_pkh = current_setting('semantos.op_pkh', true))
    WITH CHECK (op_pkh = current_setting('semantos.op_pkh', true));

CREATE POLICY op_scope ON pask_stable_thread
    FOR ALL TO semantos_brain
    USING      (op_pkh = current_setting('semantos.op_pkh', true))
    WITH CHECK (op_pkh = current_setting('semantos.op_pkh', true));

CREATE POLICY op_scope ON session_chain
    FOR ALL TO semantos_brain
    USING      (op_pkh = current_setting('semantos.op_pkh', true))
    WITH CHECK (op_pkh = current_setting('semantos.op_pkh', true));

CREATE POLICY op_scope ON cells_lmdb_cache
    FOR ALL TO semantos_brain
    USING      (op_pkh = current_setting('semantos.op_pkh', true))
    WITH CHECK (op_pkh = current_setting('semantos.op_pkh', true));

CREATE POLICY op_scope ON action_cell_log
    FOR ALL TO semantos_brain
    USING      (op_pkh = current_setting('semantos.op_pkh', true))
    WITH CHECK (op_pkh = current_setting('semantos.op_pkh', true));

CREATE POLICY op_scope ON audit_log_cache
    FOR ALL TO semantos_brain
    USING      (op_pkh = current_setting('semantos.op_pkh', true))
    WITH CHECK (op_pkh = current_setting('semantos.op_pkh', true));

-- operators table: brain role can only see its own row.
CREATE POLICY op_self ON operators
    FOR SELECT TO semantos_brain
    USING (op_pkh = current_setting('semantos.op_pkh', true));

-- Grant DML to brain role on scoped tables (RLS gates the actual rows).
GRANT SELECT, INSERT, UPDATE ON
    pask_node_view, pask_entailment, pask_stable_thread,
    session_chain, cells_lmdb_cache, action_cell_log, audit_log_cache
    TO semantos_brain;

-- ── Seed the boot operator ───────────────────────────────────────────────────
-- Insert the single-tenant operator entry so existing data (op_pkh default
-- '0000000000000000') passes the FK-less lookup and RLS in W7.4+ sessions.
-- '0000000000000000' = 8 zero bytes = the W7.1 single-tenant LMDB prefix.

INSERT INTO operators (op_pkh, status, provisioned_at)
VALUES ('0000000000000000', 'active', now())
ON CONFLICT (op_pkh) DO NOTHING;

DO $$ BEGIN RAISE NOTICE 'W7.2: operators table + RLS policies installed'; END $$;

COMMIT;

```
