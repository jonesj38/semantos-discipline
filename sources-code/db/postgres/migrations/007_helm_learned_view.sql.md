---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/migrations/007_helm_learned_view.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.141564+00:00
---

# db/postgres/migrations/007_helm_learned_view.sql

```sql
-- M5.12 — Helm "what's been learned" view.
--
-- Surfaces the current stable, non-pruned threads for each user in
-- descending h_state order.  Joins pask_node_view (the live Pask snapshot)
-- with pask_stable_thread (the kernel's confirmed-stable set).
--
-- Performance contract: query on a single user_cert_id must complete in < 1 s
-- on a typical deployment.  The partial index idx_pask_node_learned on
-- pask_node_view(user_cert_id, h_state DESC) WHERE NOT is_pruned AND is_stable
-- is the key enabler — the planner uses it for the inner join side, reducing
-- the join to an index scan + small sort.
--
-- Idempotency: CREATE OR REPLACE VIEW + CREATE INDEX IF NOT EXISTS.
-- Re-running against a database where M5.12 is already applied is a no-op.

BEGIN;

-- ── helm_what_been_learned ────────────────────────────────────────────
-- The Helm context surface: one row per (user, cell) pair that is both
-- declared stable by the Pask kernel AND present in pask_stable_thread
-- (i.e. has a confirmed stabilisation record with constraint strength).
--
-- Columns:
--   user_cert_id              — owning identity cert (FK to cert_dag)
--   cell_id                   — the Pask node / semantic concept
--   type_path                 — dot-separated concept type hierarchy
--   h_state                   — current habituated-state score [0,1]
--   stability                 — accumulated stability measure
--   interaction_count         — total interactions that shaped this node
--   total_constraint_strength — sum of inbound+outbound edge weights
--   stabilised_at             — timestamp the kernel declared it stable
--   snapshot_version          — Pask snapshot version at last write

CREATE OR REPLACE VIEW helm_what_been_learned AS
SELECT
    pnv.user_cert_id,
    pnv.cell_id,
    pnv.type_path,
    pnv.h_state,
    pnv.stability,
    pnv.interaction_count,
    pst.total_constraint_strength,
    pst.stabilised_at,
    pst.snapshot_version
FROM pask_node_view pnv
JOIN pask_stable_thread pst
    ON  pst.user_cert_id = pnv.user_cert_id
    AND pst.cell_id      = pnv.cell_id
WHERE pnv.is_pruned = FALSE
  AND pnv.is_stable  = TRUE
ORDER BY pnv.user_cert_id, pnv.h_state DESC;

-- ── Performance index ─────────────────────────────────────────────────
-- Partial B+tree index on pask_node_view for the Helm query hot path.
-- Covers the WHERE clause (is_pruned=FALSE, is_stable=TRUE) and the
-- ORDER BY (h_state DESC) so the planner can satisfy the join without
-- a sort step on most queries.
--
-- Note: PostgreSQL does not support indexes on views; the index is placed
-- on the underlying table pask_node_view (source of M5.11).

CREATE INDEX IF NOT EXISTS idx_pask_node_learned
    ON pask_node_view (user_cert_id, h_state DESC)
    WHERE is_pruned = FALSE AND is_stable = TRUE;

COMMIT;

```
