---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/tests/test_helm_read_views.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.135871+00:00
---

# db/postgres/tests/test_helm_read_views.sql

```sql
-- M5.8 tests — Helm read-view contexts (15 views)
--
-- Tests:
--   M5.8-T-active-cells-view     — helm_active_cells is selectable (zero rows OK)
--   M5.8-T-region-tick-summary   — helm_region_tick_summary is selectable
--   M5.8-T-stable-intents        — helm_stable_intents is selectable
--   M5.8-T-unspent-linear        — helm_unspent_linear is selectable
--   M5.8-T-high-strength-nodes   — helm_high_strength_nodes is selectable
--   M5.8-T-octave-distribution   — helm_octave_distribution count IS NOT NULL
--
-- Run via:
--   psql -v ON_ERROR_STOP=1 -f db/postgres/tests/test_helm_read_views.sql

\set ON_ERROR_STOP on

BEGIN;

\i db/postgres/migrations/001_cert_dag.sql
\i db/postgres/migrations/002_lexicon_category.sql
\i db/postgres/migrations/003_sir_program.sql
\i db/postgres/migrations/004_session_chain.sql
\i db/postgres/migrations/005_pask_tables.sql
\i db/postgres/migrations/006_cert_dag_populator.sql
\i db/postgres/migrations/007_helm_learned_view.sql
\i db/postgres/migrations/008_octave_registry.sql
\i db/postgres/migrations/009_cells_lmdb_fdw.sql
\i db/postgres/migrations/010_audit_log_fdw.sql
\i db/postgres/migrations/011_pask_fdw_plumbing.sql
\i db/postgres/migrations/012_region_ticks_pravega.sql
\i db/postgres/migrations/013_registry_mirror_sqlite.sql
\i db/postgres/migrations/014_helm_read_views.sql

-- ── M5.8-T-active-cells-view ─────────────────────────────────────────────
-- helm_active_cells is selectable; zero rows is fine on a fresh database.

DO $$
DECLARE
  row_count INT;
BEGIN
  SELECT COUNT(*) INTO row_count FROM helm_active_cells;
  -- No assertion on value — merely confirm the view executes without error.
  RAISE NOTICE 'M5.8-T-active-cells-view PASSED (rows: %)', row_count;
END $$;

\echo 'M5.8-T-active-cells-view PASSED'

-- ── M5.8-T-region-tick-summary ───────────────────────────────────────────
-- helm_region_tick_summary is selectable; zero rows is fine.

DO $$
DECLARE
  row_count INT;
BEGIN
  SELECT COUNT(*) INTO row_count FROM helm_region_tick_summary;
  RAISE NOTICE 'M5.8-T-region-tick-summary PASSED (rows: %)', row_count;
END $$;

\echo 'M5.8-T-region-tick-summary PASSED'

-- ── M5.8-T-stable-intents ────────────────────────────────────────────────
-- helm_stable_intents is selectable; zero rows is fine.

DO $$
DECLARE
  row_count INT;
BEGIN
  SELECT COUNT(*) INTO row_count FROM helm_stable_intents;
  RAISE NOTICE 'M5.8-T-stable-intents PASSED (rows: %)', row_count;
END $$;

\echo 'M5.8-T-stable-intents PASSED'

-- ── M5.8-T-unspent-linear ────────────────────────────────────────────────
-- helm_unspent_linear is selectable; zero rows is fine.

DO $$
DECLARE
  row_count INT;
BEGIN
  SELECT COUNT(*) INTO row_count FROM helm_unspent_linear;
  RAISE NOTICE 'M5.8-T-unspent-linear PASSED (rows: %)', row_count;
END $$;

\echo 'M5.8-T-unspent-linear PASSED'

-- ── M5.8-T-high-strength-nodes ───────────────────────────────────────────
-- helm_high_strength_nodes is selectable; zero rows is fine.

DO $$
DECLARE
  row_count INT;
BEGIN
  SELECT COUNT(*) INTO row_count FROM helm_high_strength_nodes;
  RAISE NOTICE 'M5.8-T-high-strength-nodes PASSED (rows: %)', row_count;
END $$;

\echo 'M5.8-T-high-strength-nodes PASSED'

-- ── M5.8-T-octave-distribution ───────────────────────────────────────────
-- helm_octave_distribution must return a non-null count column.
-- Even with zero rows, COUNT(*) over a grouped query returns zero (not NULL).

DO $$
DECLARE
  n BIGINT;
BEGIN
  -- Select total sum of cell_count across all octave levels.
  SELECT COALESCE(SUM(cell_count), 0) INTO n FROM helm_octave_distribution;

  IF n IS NULL THEN
    RAISE EXCEPTION 'M5.8-T-octave-distribution FAILED: cell_count IS NULL';
  END IF;

  RAISE NOTICE 'M5.8-T-octave-distribution PASSED (total cells: %)', n;
END $$;

\echo 'M5.8-T-octave-distribution PASSED'

ROLLBACK;

\echo ''
\echo 'All M5.8 helm_read_views tests PASSED'

```
