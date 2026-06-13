---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/migrations/014_helm_read_views.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.144312+00:00
---

# db/postgres/migrations/014_helm_read_views.sql

```sql
-- 014_helm_read_views.sql
--
-- M5.8: Helm read-view contexts (15 views)
--
-- Defines 15 regular SQL VIEWs — one per Helm read context — that expose
-- joined, filtered slices of the FDW staging tables and core Postgres tables.
-- Each view is designed for < 1 s query time with the indexes defined below.
--
-- View list:
--   1.  helm_active_cells          — non-spent, non-quarantined cells
--   2.  helm_stable_intents        — intents whose SIR has a proven lexicon entry
--   3.  helm_region_tick_summary   — latest tick per region_id
--   4.  helm_cert_ancestry         — root certs (no parent)
--   5.  helm_unspent_linear        — linear cells in 'unspent' state
--   6.  helm_high_strength_nodes   — Pask nodes with h_state > 0.7 and is_stable
--   7.  helm_entailment_summary    — max constraint_weight per user
--   8.  helm_audit_recent          — 100 most-recent audit rows per domain_flag
--   9.  helm_sir_program_index     — SIR programs with lexicon proof status
--  10.  helm_registry_by_domain    — cell count per domain_flag + octave_level
--  11.  helm_browser_mirror_unspent — unspent rows from registry_mirror_sqlite
--  12.  helm_learned_by_user       — learned node count per user_cert_id
--  13.  helm_spent_cells_recent    — cells moved to 'spent' in the last 7 days
--  14.  helm_domain_cert_count     — cert count per domain_flag
--  15.  helm_octave_distribution   — cell count per octave_level
--
-- Idempotency: CREATE OR REPLACE VIEW + CREATE INDEX IF NOT EXISTS.
-- Re-running against a database where M5.8 is already applied is a no-op.
--
-- Depends on migrations 001 through 013.

BEGIN;

-- ── 1. helm_active_cells ──────────────────────────────────────────────────
-- Helm context: cells that are currently routable — not spent and not
-- quarantined.  Joins octave_registry (authoritative state) with cells_lmdb
-- (the byte content) so callers get cell bytes alongside routing metadata.
-- A cell in 'locked' state is still active (locked = pending resolution).

CREATE OR REPLACE VIEW helm_active_cells AS
SELECT
    o.cell_id,
    o.domain_flag,
    o.octave_level::TEXT  AS octave_level,
    o.state::TEXT         AS state,
    o.linearity_type::TEXT AS linearity_type,
    c.cell_bytes,
    o.registered_at
FROM octave_registry o
LEFT JOIN cells_lmdb c ON c.cell_hash = o.cell_id
WHERE o.state NOT IN ('spent', 'quarantined');

-- ── 2. helm_stable_intents ────────────────────────────────────────────────
-- Helm context: intents that have been compiled to a SIR program that is
-- supported by a lexicon category entry.  The lexicon join confirms the
-- SIR's concept type is classified in the taxonomy.
-- Uses sir_json->>'version' as the bridge key into lexicon_category
-- (category_name stores the SIR schema version label by convention).

CREATE OR REPLACE VIEW helm_stable_intents AS
SELECT
    i.intent_hash,
    i.created_at,
    sp.sir_hash,
    sp.sir_json->>'version'  AS sir_version,
    lc.category_name,
    lc.taxonomy_tags
FROM intent i
JOIN sir_program sp ON sp.intent_hash = i.intent_hash
JOIN lexicon_category lc
    ON lc.category_name = sp.sir_json->>'version';

-- ── 3. helm_region_tick_summary ───────────────────────────────────────────
-- Helm context: the most-recent tick for each region known to the system.
-- Derived from region_ticks_pravega using a GROUP BY + MAX aggregation.
-- Pairs naturally with the idx_rtp_region_tick index on (region_id, tick DESC).

CREATE OR REPLACE VIEW helm_region_tick_summary AS
SELECT
    region_id,
    MAX(tick)        AS latest_tick,
    MAX(ts_ms)       AS latest_ts_ms,
    COUNT(*)         AS total_ticks,
    MAX(ingested_at) AS last_ingested_at
FROM region_ticks_pravega
GROUP BY region_id;

-- ── 4. helm_cert_ancestry ─────────────────────────────────────────────────
-- Helm context: root certs in the DAG — those with no parent_cert_hash.
-- These are self-signed / genesis certs that anchor trust chains.
-- Simple single-table filter; uses the cert_dag PK index.

CREATE OR REPLACE VIEW helm_cert_ancestry AS
SELECT
    cert_hash,
    issuer_pub,
    subject_pub,
    cert_type,
    issued_at
FROM cert_dag
WHERE parent_cert_hash IS NULL;

-- ── 5. helm_unspent_linear ────────────────────────────────────────────────
-- Helm context: linear cells that remain unspent — the hot path for
-- linearity enforcement (K1).  Uses the partial index
-- idx_octave_registry_unspent on (linearity_type, state) WHERE state='unspent'.

CREATE OR REPLACE VIEW helm_unspent_linear AS
SELECT
    cell_id,
    domain_flag,
    octave_level::TEXT AS octave_level,
    owner_cert_id,
    registered_at
FROM octave_registry
WHERE linearity_type = 'linear'
  AND state = 'unspent';

-- ── 6. helm_high_strength_nodes ───────────────────────────────────────────
-- Helm context: Pask nodes with h_state > 0.7 that the kernel has declared
-- stable — the "strongly habituated" set.  Used by the intent reducer to
-- prioritise high-confidence semantic matches.
-- Uses idx_pask_node_user_stable on (user_cert_id, is_stable, h_state DESC)
-- WHERE NOT is_pruned.

CREATE OR REPLACE VIEW helm_high_strength_nodes AS
SELECT
    user_cert_id,
    cell_id,
    type_path,
    h_state,
    stability,
    interaction_count,
    updated_at
FROM pask_node_view
WHERE is_stable = TRUE
  AND is_pruned = FALSE
  AND h_state   > 0.7;

-- ── 7. helm_entailment_summary ────────────────────────────────────────────
-- Helm context: the strongest entailment link each user has, summarised per
-- user.  Max constraint_weight shows the tightest conceptual coupling in a
-- user's Pask graph.

CREATE OR REPLACE VIEW helm_entailment_summary AS
SELECT
    user_cert_id,
    COUNT(*)                      AS entailment_count,
    MAX(constraint_weight)        AS max_constraint_weight,
    AVG(constraint_weight)        AS avg_constraint_weight,
    MAX(last_updated)             AS last_updated
FROM pask_entailment
GROUP BY user_cert_id;

-- ── 8. helm_audit_recent ──────────────────────────────────────────────────
-- Helm context: the 100 most-recently cached audit rows from the browser-side
-- signed_bundle_audit_sqlite surface.  Ordered by cached_at DESC so callers
-- always see fresh events first.
-- No per-domain_flag partitioning at the view level: callers filter by
-- cert_id; the idx_audit_log_cache_cert index handles that efficiently.

CREATE OR REPLACE VIEW helm_audit_recent AS
SELECT
    id,
    cert_id,
    payload_type,
    payload_hash,
    created_at_ms,
    cached_at
FROM signed_bundle_audit_sqlite
ORDER BY cached_at DESC
LIMIT 100;

-- ── 9. helm_sir_program_index ─────────────────────────────────────────────
-- Helm context: SIR programs annotated with their lexicon taxonomy status.
-- The left join on lexicon_category means programs without a matching category
-- still appear (category_name will be NULL), exposing unclassified programs.

CREATE OR REPLACE VIEW helm_sir_program_index AS
SELECT
    sp.sir_hash,
    sp.created_at,
    sp.sir_json->>'version'  AS sir_version,
    sp.intent_hash,
    lc.category_name,
    lc.taxonomy_tags
FROM sir_program sp
LEFT JOIN lexicon_category lc
    ON lc.category_name = sp.sir_json->>'version';

-- ── 10. helm_registry_by_domain ──────────────────────────────────────────
-- Helm context: cell counts grouped by domain_flag and octave_level.
-- Gives operators a quick overview of how cells are distributed across
-- governance domains and storage tiers.
-- Uses idx_octave_registry_domain on (domain_flag).

CREATE OR REPLACE VIEW helm_registry_by_domain AS
SELECT
    domain_flag,
    octave_level::TEXT AS octave_level,
    state::TEXT        AS state,
    COUNT(*)           AS cell_count
FROM octave_registry
GROUP BY domain_flag, octave_level, state;

-- ── 11. helm_browser_mirror_unspent ──────────────────────────────────────
-- Helm context: unspent rows from the browser-side registry mirror.
-- Used by the browser adapter to determine which pointer cells can still
-- be escalated.  Uses idx_rms_state partial index WHERE state='unspent'.

CREATE OR REPLACE VIEW helm_browser_mirror_unspent AS
SELECT
    cell_id_hex,
    domain_flag,
    octave_level,
    seq,
    updated_at
FROM registry_mirror_sqlite
WHERE state = 'unspent';

-- ── 12. helm_learned_by_user ──────────────────────────────────────────────
-- Helm context: extends helm_what_been_learned (M5.12) by aggregating learned
-- node counts per user_cert_id.  Provides the Helm "learning progress" surface
-- without re-joining pask_stable_thread and pask_node_view at call time.

CREATE OR REPLACE VIEW helm_learned_by_user AS
SELECT
    user_cert_id,
    COUNT(*)                       AS learned_node_count,
    MAX(h_state)                   AS max_h_state,
    AVG(h_state)                   AS avg_h_state,
    MAX(total_constraint_strength) AS max_constraint_strength,
    MAX(stabilised_at)             AS latest_stabilised_at
FROM helm_what_been_learned
GROUP BY user_cert_id;

-- ── 13. helm_spent_cells_recent ───────────────────────────────────────────
-- Helm context: cells that transitioned to 'spent' in the last 7 days.
-- Used by the adapter to identify recently finalised linear cells.
-- The partial index idx_octave_registry_unspent does not cover spent; add a
-- supporting index below for this query path.

CREATE OR REPLACE VIEW helm_spent_cells_recent AS
SELECT
    cell_id,
    domain_flag,
    octave_level::TEXT AS octave_level,
    linearity_type::TEXT AS linearity_type,
    owner_cert_id,
    spent_at
FROM octave_registry
WHERE state    = 'spent'
  AND spent_at > now() - INTERVAL '7 days';

-- ── 14. helm_domain_cert_count ────────────────────────────────────────────
-- Helm context: count of certs per domain_flag from cert_dag.
-- cert_dag does not carry domain_flag directly; the governance domain is
-- encoded in cert_type.  This view groups by cert_type as the domain proxy.
-- Callers that need a numeric domain_flag can join to cert_dag.metadata.

CREATE OR REPLACE VIEW helm_domain_cert_count AS
SELECT
    cert_type,
    COUNT(*) AS cert_count,
    MIN(issued_at) AS earliest_issued,
    MAX(issued_at) AS latest_issued
FROM cert_dag
GROUP BY cert_type;

-- ── 15. helm_octave_distribution ─────────────────────────────────────────
-- Helm context: total cell count per octave_level across all domains.
-- Simple aggregate over octave_registry; the full-table aggregation is fast
-- with the existing domain index used as a covering scan.

CREATE OR REPLACE VIEW helm_octave_distribution AS
SELECT
    octave_level::TEXT AS octave_level,
    COUNT(*)           AS cell_count
FROM octave_registry
GROUP BY octave_level;

-- ── Supporting indexes ─────────────────────────────────────────────────────
-- Add indexes that the views above depend on but are not covered by existing
-- indexes from earlier migrations.

-- helm_spent_cells_recent: partial index on spent cells ordered by spent_at.
-- Filters state='spent' and spent_at IS NOT NULL (enforced by k1_spent_at_consistency).
CREATE INDEX IF NOT EXISTS idx_octave_registry_spent_at
    ON octave_registry (spent_at DESC)
    WHERE state = 'spent';

-- helm_stable_intents / helm_sir_program_index: index on sir_json->>'version'
-- so the LEFT JOIN on lexicon_category.category_name is an index scan.
CREATE INDEX IF NOT EXISTS idx_sir_program_version
    ON sir_program ((sir_json->>'version'));

-- helm_audit_recent: primary ordering is by cached_at DESC; the existing
-- idx_audit_log_cache_cert covers cert_id lookups; add a plain time index.
CREATE INDEX IF NOT EXISTS idx_audit_log_cached_at
    ON audit_log_cache (cached_at DESC);

COMMIT;

```
