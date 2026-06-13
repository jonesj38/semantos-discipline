---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/migrations/005_pask_tables.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.141831+00:00
---

# db/postgres/migrations/005_pask_tables.sql

```sql
-- M5.11 — Postgres schema: pask_node_view, pask_entailment, pask_stable_thread.
--
-- These tables are the queryable Postgres surface of the Paskian Learning
-- System (PLS) kernel at core/pask/. They are materialised views of the
-- Pask Store's Node and Edge arrays, decoded from the LMDB Pask snapshot
-- using the compile-time-locked offsets from core/pask/src/main.zig.
--
-- Struct sizes (locked by comptime asserts in the kernel):
--   Node:         208 B  (cell_id[64] + h_state + stability + ...)
--   Edge:         40 B   (from_idx + to_idx + constraint_weight + delta_trend + ...)
--   StableThread: 32 B   (node_idx + h_state + total_constraint_strength + ...)
--
-- The FDW plumbing (Multicorn or custom extension) that populates these tables
-- from the live LMDB snapshot is M5.11's acceptance gate; this migration
-- creates the target schema the FDW writes into.
--
-- Source-of-truth:
--   docs/prd/analyses/SEMANTOS-DB-PASKIAN-ADDENDUM.md §3, §5.
--
-- References cert_dag (M5.1) for cell_id FK lookups.

BEGIN;

-- ── pask_node_view ────────────────────────────────────────────────────
-- Materialised view of the Pask Store Node array.
-- One row per active (non-pruned) node in the current user's Pask graph.
-- Refreshed from the LMDB Pask snapshot via FDW on snapshot commit.

CREATE TABLE IF NOT EXISTS pask_node_view (
    cell_id             BYTEA           NOT NULL,
    user_cert_id        BYTEA           NOT NULL,
    type_path           TEXT            NOT NULL DEFAULT '',
    h_state             DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    stability           DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    interaction_count   INT             NOT NULL DEFAULT 0,
    is_stable           BOOLEAN         NOT NULL DEFAULT FALSE,
    is_pruned           BOOLEAN         NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ     NOT NULL,
    updated_at          TIMESTAMPTZ     NOT NULL,
    snapshot_version    BIGINT          NOT NULL DEFAULT 0,

    CONSTRAINT pask_node_view_pkey PRIMARY KEY (user_cert_id, cell_id),
    CONSTRAINT pask_node_cell_id_nonempty CHECK (length(cell_id) > 0),
    CONSTRAINT pask_node_h_state_range CHECK (h_state >= 0.0 AND h_state <= 1.0),
    CONSTRAINT pask_node_stability_range CHECK (stability >= 0.0),
    CONSTRAINT pask_node_interaction_count_positive CHECK (interaction_count >= 0),
    CONSTRAINT pask_node_snapshot_version_positive CHECK (snapshot_version >= 0)
);

-- Index for efficient "give me all stable threads for this user" queries
-- (Bert's intent reducer primary access pattern).
CREATE INDEX IF NOT EXISTS idx_pask_node_user_stable
    ON pask_node_view (user_cert_id, is_stable, h_state DESC)
    WHERE NOT is_pruned;

-- Index for "find node by cell_id across all users" (federation join).
CREATE INDEX IF NOT EXISTS idx_pask_node_cell_id
    ON pask_node_view (cell_id)
    WHERE NOT is_pruned;

-- ── pask_entailment ───────────────────────────────────────────────────
-- Materialised view of the Pask Store Edge array.
-- One row per active edge between two concepts in the user's Pask graph.
-- from_cell_id → to_cell_id means "from concept entails to concept"
-- with the given constraint_weight and recency (delta_trend).

CREATE TABLE IF NOT EXISTS pask_entailment (
    user_cert_id        BYTEA           NOT NULL,
    from_cell_id        BYTEA           NOT NULL,
    to_cell_id          BYTEA           NOT NULL,
    constraint_weight   DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    delta_trend         DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    interaction_count   INT             NOT NULL DEFAULT 0,
    last_updated        TIMESTAMPTZ     NOT NULL,
    snapshot_version    BIGINT          NOT NULL DEFAULT 0,

    CONSTRAINT pask_entailment_pkey PRIMARY KEY (user_cert_id, from_cell_id, to_cell_id),
    CONSTRAINT pask_entailment_no_self_edge CHECK (from_cell_id <> to_cell_id),
    CONSTRAINT pask_entailment_weight_range CHECK (constraint_weight >= 0.0 AND constraint_weight <= 1.0),
    CONSTRAINT pask_entailment_count_positive CHECK (interaction_count >= 0),

    CONSTRAINT pask_entailment_from_fk
        FOREIGN KEY (user_cert_id, from_cell_id)
        REFERENCES pask_node_view (user_cert_id, cell_id)
        ON DELETE CASCADE,

    CONSTRAINT pask_entailment_to_fk
        FOREIGN KEY (user_cert_id, to_cell_id)
        REFERENCES pask_node_view (user_cert_id, cell_id)
        ON DELETE CASCADE
);

-- Bert's intent reducer primary access: "given concept X, what does it
-- entail?" and "what concepts are most tightly coupled to X?"
CREATE INDEX IF NOT EXISTS idx_pask_entailment_from
    ON pask_entailment (user_cert_id, from_cell_id, constraint_weight DESC);

CREATE INDEX IF NOT EXISTS idx_pask_entailment_to
    ON pask_entailment (user_cert_id, to_cell_id, constraint_weight DESC);

-- Hot path: find freshest (highest delta_trend) edges for a user.
CREATE INDEX IF NOT EXISTS idx_pask_entailment_delta
    ON pask_entailment (user_cert_id, delta_trend DESC);

-- ── pask_stable_thread ────────────────────────────────────────────────
-- The system's "what has been learned" surface.
-- One row per node the Pask kernel has declared stable
-- (h_state stopped changing across stability_window_ms).
-- Subset of pask_node_view where is_stable = TRUE, with pre-computed
-- total_constraint_strength from all inbound/outbound edges.

CREATE TABLE IF NOT EXISTS pask_stable_thread (
    user_cert_id                BYTEA           NOT NULL,
    cell_id                     BYTEA           NOT NULL,
    h_state                     DOUBLE PRECISION NOT NULL,
    total_constraint_strength   DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    interaction_count           INT             NOT NULL DEFAULT 0,
    stabilised_at               TIMESTAMPTZ     NOT NULL DEFAULT now(),
    snapshot_version            BIGINT          NOT NULL DEFAULT 0,

    CONSTRAINT pask_stable_thread_pkey PRIMARY KEY (user_cert_id, cell_id),

    -- Must reference a live, non-pruned node.
    CONSTRAINT pask_stable_thread_node_fk
        FOREIGN KEY (user_cert_id, cell_id)
        REFERENCES pask_node_view (user_cert_id, cell_id)
        ON DELETE CASCADE,

    CONSTRAINT pask_stable_thread_h_state_range CHECK (h_state >= 0.0 AND h_state <= 1.0),
    CONSTRAINT pask_stable_thread_strength_positive CHECK (total_constraint_strength >= 0.0)
);

-- Helm "what's been learned" view primary access: descending h_state.
CREATE INDEX IF NOT EXISTS idx_pask_stable_thread_h_state
    ON pask_stable_thread (user_cert_id, h_state DESC);

-- ── helper view ───────────────────────────────────────────────────────
-- Denormalised view Bert's reducer queries: stable threads + their top-3
-- outbound entailments. Not a materialised view (refresh cost); use
-- straight SQL or a fast re-query in the reducer.

CREATE OR REPLACE VIEW pask_stable_thread_with_entailments AS
SELECT
    st.user_cert_id,
    st.cell_id,
    st.h_state,
    st.total_constraint_strength,
    st.interaction_count,
    st.stabilised_at,
    e.to_cell_id           AS entails_cell_id,
    e.constraint_weight,
    e.delta_trend
FROM pask_stable_thread st
LEFT JOIN LATERAL (
    SELECT to_cell_id, constraint_weight, delta_trend
    FROM pask_entailment pe
    WHERE pe.user_cert_id = st.user_cert_id
      AND pe.from_cell_id = st.cell_id
    ORDER BY constraint_weight DESC
    LIMIT 3
) e ON TRUE;

COMMIT;

```
