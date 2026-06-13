---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/migrations/016_hat_views.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.143209+00:00
---

# db/postgres/migrations/016_hat_views.sql

```sql
-- 016_hat_views.sql
--
-- W2.1 + W2.2 + W2.3: Universal hat view scaffold + Oddjobz hat views + Helm contexts
--
-- W2.1  hat_cell_list(p_domain_flag BYTEA) RETURNS SETOF cells_lmdb
--         Joins cells_lmdb_cache with pask_node_view filtered by domain flag.
--         The BYTEA parameter is the canonical 3-byte governance domain flag,
--         converted to INTEGER for comparison with cells_lmdb_cache.domain_flag.
--
-- W2.2  Oddjobz-specific views built on hat_cell_list('\x000101'):
--         oddjobz_job_list        — all Oddjobz cells with type_path 'oddjobz.job*'
--         oddjobz_job_by_id       — job lookup by cell_hash (function)
--         oddjobz_customer_index  — cells with type_path 'oddjobz.customer*'
--         oddjobz_site_index      — cells with type_path 'oddjobz.site*'
--         oddjobz_active_jobs     — jobs with h_state > 0.5 (Pask-ranked)
--
-- W2.3  Helm read contexts as named views (oddjobz.* namespace):
--         helm_oddjobz_jobs_active          — oddjobz.jobs.active
--         helm_oddjobz_jobs_scheduled_today — oddjobz.jobs.scheduled_today
--         helm_oddjobz_jobs_awaiting_invoice— oddjobz.jobs.awaiting_invoice
--         helm_oddjobz_customers_recent     — oddjobz.customers.recent
--         helm_oddjobz_visits_upcoming      — oddjobz.visits.upcoming
--         helm_oddjobz_learned_concepts     — oddjobz.learned_concepts
--
-- Oddjobz domain flag: \x000101 = 0×65536 + 1×256 + 1 = 257 (INTEGER)
--
-- Type-path conventions (Oddjobz cells carry these in pask_node_view):
--   'oddjobz.job'              — a job record
--   'oddjobz.job.scheduled'    — a scheduled job (has a scheduled date in payload)
--   'oddjobz.job.invoice'      — a job awaiting invoice
--   'oddjobz.customer'         — a customer record
--   'oddjobz.visit'            — a site visit record
--
-- Idempotency: CREATE OR REPLACE FUNCTION / VIEW, CREATE INDEX IF NOT EXISTS.
-- Depends on migrations 001–015.

BEGIN;

-- ── Performance index ─────────────────────────────────────────────────────────
-- Supports hat_cell_list domain_flag equality scans on cells_lmdb_cache.
-- On a 1M-cell dataset this index keeps the scan < 500 ms.
CREATE INDEX IF NOT EXISTS idx_cells_lmdb_domain_flag
    ON cells_lmdb_cache (domain_flag);

-- Supports oddjobz type_path prefix lookups on pask_node_view.
CREATE INDEX IF NOT EXISTS idx_pask_node_type_path
    ON pask_node_view (type_path text_pattern_ops)
    WHERE NOT is_pruned;

-- Supports pask_stable_thread → pask_node_view join for learned_concepts.
CREATE INDEX IF NOT EXISTS idx_pask_stable_thread_cell
    ON pask_stable_thread (cell_id);

-- ── W2.1: hat_cell_list ───────────────────────────────────────────────────────
--
-- hat_cell_list(p_domain_flag BYTEA) RETURNS TABLE(...)
--
-- Returns all cells for the given domain flag, enriched with their
-- Pask node metadata.  p_domain_flag is the canonical BYTEA representation
-- (e.g. '\x000101' for Oddjobz).  It is converted to INTEGER for comparison
-- with cells_lmdb_cache.domain_flag via big-endian byte decoding.
--
-- Conversion: interpret up to 4 bytes big-endian → INTEGER.
-- '\x000101' → (0 << 16) | (1 << 8) | 1 = 257
--
-- LEFT JOIN on pask_node_view: cells with no Pask node still appear
-- (h_state = 0.0, is_stable = FALSE, is_pruned = FALSE).
--
-- Performance: idx_cells_lmdb_domain_flag on cells_lmdb_cache(domain_flag)
-- + idx_pask_node_cell_id on pask_node_view(cell_id) WHERE NOT is_pruned.
-- Expected < 500 ms on 1M-cell dataset with selective domain_flag predicate.

CREATE OR REPLACE FUNCTION hat_cell_list(p_domain_flag BYTEA)
RETURNS TABLE (
    cell_hash          BYTEA,
    type_hash          BYTEA,
    domain_flag        INTEGER,
    cell_bytes         BYTEA,
    cached_at          TIMESTAMPTZ,
    -- pask columns (NULL when no Pask node exists for this cell)
    pask_user_cert_id  BYTEA,
    pask_type_path     TEXT,
    pask_h_state       DOUBLE PRECISION,
    pask_stability     DOUBLE PRECISION,
    pask_is_stable     BOOLEAN,
    pask_is_pruned     BOOLEAN,
    pask_updated_at    TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
  SELECT
      c.cell_hash,
      c.type_hash,
      c.domain_flag,
      c.cell_bytes,
      c.cached_at,
      pn.user_cert_id        AS pask_user_cert_id,
      pn.type_path           AS pask_type_path,
      COALESCE(pn.h_state,          0.0)   AS pask_h_state,
      COALESCE(pn.stability,        0.0)   AS pask_stability,
      COALESCE(pn.is_stable,        FALSE) AS pask_is_stable,
      COALESCE(pn.is_pruned,        FALSE) AS pask_is_pruned,
      pn.updated_at          AS pask_updated_at
  FROM cells_lmdb_cache c
  LEFT JOIN pask_node_view pn
         ON pn.cell_id = c.cell_hash
        AND pn.is_pruned = FALSE
  WHERE c.domain_flag = (
      -- Convert BYTEA → INTEGER (big-endian, up to 4 bytes)
      SELECT SUM(get_byte(p_domain_flag, i) * (256 ^ (length(p_domain_flag) - 1 - i))::BIGINT)::INTEGER
      FROM generate_series(0, length(p_domain_flag) - 1) AS s(i)
  );
$$;

-- ── W2.2: Oddjobz domain constant ────────────────────────────────────────────
-- Oddjobz domain flag '\x000101' = integer 257.
-- All W2.2 views call hat_cell_list with this literal.

-- ── W2.2: oddjobz_job_list ───────────────────────────────────────────────────
-- All Oddjobz cells whose type_path begins with 'oddjobz.job'.
-- Ordered by Pask h_state descending so highest-confidence jobs come first.

CREATE OR REPLACE VIEW oddjobz_job_list AS
SELECT
    cell_hash,
    type_hash,
    cell_bytes,
    cached_at,
    pask_user_cert_id,
    pask_type_path,
    pask_h_state,
    pask_is_stable,
    pask_updated_at
FROM hat_cell_list('\x000101'::BYTEA)
WHERE pask_type_path LIKE 'oddjobz.job%'
   OR pask_type_path IS NULL  -- cells with no Pask node yet
ORDER BY pask_h_state DESC NULLS LAST;

-- ── W2.2: oddjobz_job_by_id ──────────────────────────────────────────────────
-- Lookup a single Oddjobz job by its cell_hash.
-- Returns at most one row (cell_hash is the PK of cells_lmdb_cache).

CREATE OR REPLACE FUNCTION oddjobz_job_by_id(p_cell_hash BYTEA)
RETURNS TABLE (
    cell_hash         BYTEA,
    type_hash         BYTEA,
    cell_bytes        BYTEA,
    cached_at         TIMESTAMPTZ,
    pask_user_cert_id BYTEA,
    pask_type_path    TEXT,
    pask_h_state      DOUBLE PRECISION,
    pask_is_stable    BOOLEAN,
    pask_updated_at   TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
  SELECT
      cell_hash,
      type_hash,
      cell_bytes,
      cached_at,
      pask_user_cert_id,
      pask_type_path,
      pask_h_state,
      pask_is_stable,
      pask_updated_at
  FROM hat_cell_list('\x000101'::BYTEA)
  WHERE cell_hash = p_cell_hash;
$$;

-- ── W2.2: oddjobz_customer_index ─────────────────────────────────────────────
-- All Oddjobz customer cells (type_path LIKE 'oddjobz.customer%').
-- Ordered by Pask h_state descending (most-engaged customers first).

CREATE OR REPLACE VIEW oddjobz_customer_index AS
SELECT
    cell_hash,
    type_hash,
    cell_bytes,
    cached_at,
    pask_user_cert_id,
    pask_type_path,
    pask_h_state,
    pask_is_stable,
    pask_updated_at
FROM hat_cell_list('\x000101'::BYTEA)
WHERE pask_type_path LIKE 'oddjobz.customer%'
ORDER BY pask_h_state DESC NULLS LAST;

-- ── W2.2: oddjobz_site_index ─────────────────────────────────────────────────
-- All Oddjobz site cells (type_path LIKE 'oddjobz.site%').

CREATE OR REPLACE VIEW oddjobz_site_index AS
SELECT
    cell_hash,
    type_hash,
    cell_bytes,
    cached_at,
    pask_user_cert_id,
    pask_type_path,
    pask_h_state,
    pask_is_stable,
    pask_updated_at
FROM hat_cell_list('\x000101'::BYTEA)
WHERE pask_type_path LIKE 'oddjobz.site%'
ORDER BY pask_h_state DESC NULLS LAST;

-- ── W2.2: oddjobz_active_jobs ────────────────────────────────────────────────
-- Jobs the operator has recently interacted with: Pask-ranked by h_state > 0.5.
-- These are jobs where the kernel's habituated state indicates recency and
-- relevance — the operator's interaction history is encoded in h_state.
-- Ordered by h_state DESC to surface the most-recently-engaged jobs first.

CREATE OR REPLACE VIEW oddjobz_active_jobs AS
SELECT
    cell_hash,
    type_hash,
    cell_bytes,
    cached_at,
    pask_user_cert_id,
    pask_type_path,
    pask_h_state,
    pask_stability,
    pask_is_stable,
    pask_updated_at
FROM hat_cell_list('\x000101'::BYTEA)
WHERE pask_h_state > 0.5
  AND (pask_type_path LIKE 'oddjobz.job%' OR pask_type_path IS NULL)
ORDER BY pask_h_state DESC NULLS LAST;

-- ── W2.3: Helm read contexts ──────────────────────────────────────────────────
-- Named helm_oddjobz_* views corresponding to the Helm read context keys:
--   oddjobz.jobs.active          → helm_oddjobz_jobs_active
--   oddjobz.jobs.scheduled_today → helm_oddjobz_jobs_scheduled_today
--   oddjobz.jobs.awaiting_invoice→ helm_oddjobz_jobs_awaiting_invoice
--   oddjobz.customers.recent     → helm_oddjobz_customers_recent
--   oddjobz.visits.upcoming      → helm_oddjobz_visits_upcoming
--   oddjobz.learned_concepts     → helm_oddjobz_learned_concepts

-- helm_oddjobz_jobs_active — oddjobz.jobs.active
-- Jobs with elevated Pask h_state (operator has recently worked on them).
-- Alias for oddjobz_active_jobs; exists as a named view for Helm context lookup.
CREATE OR REPLACE VIEW helm_oddjobz_jobs_active AS
SELECT * FROM oddjobz_active_jobs;

-- helm_oddjobz_jobs_scheduled_today — oddjobz.jobs.scheduled_today
-- Jobs scheduled for today, identified by type_path = 'oddjobz.job.scheduled'.
-- The scheduling metadata (date) is encoded in cell_bytes; the type_path
-- discriminator signals the cell carries scheduling information.
-- Callers that need the date decode cell_bytes in the application layer.
-- Ordered by Pask h_state DESC for operator-relevance ranking.
CREATE OR REPLACE VIEW helm_oddjobz_jobs_scheduled_today AS
SELECT
    cell_hash,
    type_hash,
    cell_bytes,
    cached_at,
    pask_user_cert_id,
    pask_type_path,
    pask_h_state,
    pask_is_stable,
    pask_updated_at
FROM hat_cell_list('\x000101'::BYTEA)
WHERE pask_type_path LIKE 'oddjobz.job.scheduled%'
ORDER BY pask_h_state DESC NULLS LAST;

-- helm_oddjobz_jobs_awaiting_invoice — oddjobz.jobs.awaiting_invoice
-- Jobs marked as awaiting invoice (type_path = 'oddjobz.job.invoice').
-- These cells require invoice generation; surfaced here for the billing workflow.
CREATE OR REPLACE VIEW helm_oddjobz_jobs_awaiting_invoice AS
SELECT
    cell_hash,
    type_hash,
    cell_bytes,
    cached_at,
    pask_user_cert_id,
    pask_type_path,
    pask_h_state,
    pask_is_stable,
    pask_updated_at
FROM hat_cell_list('\x000101'::BYTEA)
WHERE pask_type_path LIKE 'oddjobz.job.invoice%'
ORDER BY pask_h_state DESC NULLS LAST;

-- helm_oddjobz_customers_recent — oddjobz.customers.recent
-- Customers the operator has recently engaged with, ranked by Pask h_state.
-- "Recent" is determined by the kernel — higher h_state means more recent
-- or more frequent interaction.
CREATE OR REPLACE VIEW helm_oddjobz_customers_recent AS
SELECT
    cell_hash,
    type_hash,
    cell_bytes,
    cached_at,
    pask_user_cert_id,
    pask_type_path,
    pask_h_state,
    pask_is_stable,
    pask_updated_at
FROM hat_cell_list('\x000101'::BYTEA)
WHERE pask_type_path LIKE 'oddjobz.customer%'
  AND pask_h_state > 0.3
ORDER BY pask_h_state DESC NULLS LAST
LIMIT 50;

-- helm_oddjobz_visits_upcoming — oddjobz.visits.upcoming
-- Upcoming site visits (type_path LIKE 'oddjobz.visit%').
-- Visit scheduling metadata is in cell_bytes; the type_path discriminator
-- identifies visit cells.  Ordered by h_state for operator-relevance.
CREATE OR REPLACE VIEW helm_oddjobz_visits_upcoming AS
SELECT
    cell_hash,
    type_hash,
    cell_bytes,
    cached_at,
    pask_user_cert_id,
    pask_type_path,
    pask_h_state,
    pask_is_stable,
    pask_updated_at
FROM hat_cell_list('\x000101'::BYTEA)
WHERE pask_type_path LIKE 'oddjobz.visit%'
ORDER BY pask_h_state DESC NULLS LAST;

-- helm_oddjobz_learned_concepts — oddjobz.learned_concepts
-- Stable Pask threads for Oddjobz cells whose type_path starts with 'oddjobz.'.
-- Joins pask_stable_thread with pask_node_view to get type_path.
-- These are concepts the kernel has stabilised — the operator's durable knowledge.
-- Ordered by h_state DESC so the most strongly-habituated concepts surface first.
CREATE OR REPLACE VIEW helm_oddjobz_learned_concepts AS
SELECT
    st.user_cert_id,
    st.cell_id,
    pn.type_path,
    st.h_state,
    st.total_constraint_strength,
    st.interaction_count,
    st.stabilised_at,
    st.snapshot_version
FROM pask_stable_thread st
JOIN pask_node_view pn
  ON pn.user_cert_id = st.user_cert_id
 AND pn.cell_id      = st.cell_id
 AND pn.is_pruned    = FALSE
WHERE pn.type_path LIKE 'oddjobz.%'
ORDER BY st.h_state DESC;

COMMIT;

```
