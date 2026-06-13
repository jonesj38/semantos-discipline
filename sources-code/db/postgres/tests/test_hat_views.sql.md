---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/tests/test_hat_views.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.136432+00:00
---

# db/postgres/tests/test_hat_views.sql

```sql
-- M5.16 tests — hat_cell_list + Oddjobz views + Helm read contexts
--
-- Tests:
--   W2.1-T-hat-cell-list-exists       — hat_cell_list function is callable
--   W2.1-T-hat-cell-list-domain-scope — '\x000101' returns only Oddjobz cells
--   W2.1-T-hat-cell-list-isolation    — '\x000102' returns different cells
--   W2.2-T-oddjobz-job-list           — oddjobz_job_list view is selectable
--   W2.2-T-oddjobz-active-jobs        — oddjobz_active_jobs view is selectable
--   W2.2-T-oddjobz-customer-index     — oddjobz_customer_index view is selectable
--   W2.2-T-oddjobz-site-index         — oddjobz_site_index view is selectable
--   W2.2-T-oddjobz-job-by-id          — oddjobz_job_by_id function is callable
--   W2.3-T-helm-oddjobz-jobs-active   — helm_oddjobz_jobs_active is selectable
--   W2.3-T-helm-oddjobz-scheduled-today — helm_oddjobz_jobs_scheduled_today is selectable
--   W2.3-T-helm-oddjobz-awaiting-invoice — helm_oddjobz_jobs_awaiting_invoice is selectable
--   W2.3-T-helm-oddjobz-customers-recent — helm_oddjobz_customers_recent is selectable
--   W2.3-T-helm-oddjobz-visits-upcoming  — helm_oddjobz_visits_upcoming is selectable
--   W2.3-T-helm-oddjobz-learned-concepts — learned_concepts filters by type_path prefix
--
-- Run via:
--   psql -v ON_ERROR_STOP=1 -f db/postgres/tests/test_hat_views.sql

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
\i db/postgres/migrations/015_teachback_verification.sql
\i db/postgres/migrations/016_hat_views.sql

-- ── Fixture data ──────────────────────────────────────────────────────────────
-- Seed cells_lmdb_cache with two domain flags:
--   domain_flag = 257  (\x000101 = 0*65536 + 1*256 + 1) → Oddjobz
--   domain_flag = 258  (\x000102 = 0*65536 + 1*256 + 2) → different hat
-- Also seed pask_node_view rows with matching cell_ids.

-- Oddjobz cell (domain_flag = 257)
INSERT INTO cells_lmdb_cache (cell_hash, type_hash, domain_flag, cell_bytes)
VALUES (
  decode(repeat('aa', 32), 'hex'),
  decode(repeat('bb', 32), 'hex'),
  257,
  decode(repeat('cc', 1024), 'hex')
) ON CONFLICT DO NOTHING;

-- Different-hat cell (domain_flag = 258)
INSERT INTO cells_lmdb_cache (cell_hash, type_hash, domain_flag, cell_bytes)
VALUES (
  decode(repeat('dd', 32), 'hex'),
  decode(repeat('ee', 32), 'hex'),
  258,
  decode(repeat('ff', 1024), 'hex')
) ON CONFLICT DO NOTHING;

-- A pask_node_view row for the Oddjobz cell, with elevated h_state
INSERT INTO pask_node_view (
  cell_id, user_cert_id, type_path, h_state, stability,
  interaction_count, is_stable, is_pruned, created_at, updated_at
)
VALUES (
  decode(repeat('aa', 32), 'hex'),
  decode(repeat('11', 32), 'hex'),
  'oddjobz.job',
  0.85,
  0.9,
  10,
  TRUE,
  FALSE,
  now(),
  now()
) ON CONFLICT (user_cert_id, cell_id) DO NOTHING;

-- A pask_stable_thread row for the Oddjobz cell
INSERT INTO pask_stable_thread (
  user_cert_id, cell_id, h_state, total_constraint_strength,
  interaction_count, stabilised_at
)
VALUES (
  decode(repeat('11', 32), 'hex'),
  decode(repeat('aa', 32), 'hex'),
  0.85,
  1.2,
  10,
  now()
) ON CONFLICT (user_cert_id, cell_id) DO NOTHING;

-- ── W2.1-T-hat-cell-list-exists ──────────────────────────────────────────────
-- hat_cell_list('\x000101') must be callable without error.

DO $$
DECLARE
  row_count INT;
BEGIN
  SELECT COUNT(*) INTO row_count
  FROM hat_cell_list('\x000101'::BYTEA);

  RAISE NOTICE 'W2.1-T-hat-cell-list-exists PASSED (rows: %)', row_count;
END $$;

\echo 'W2.1-T-hat-cell-list-exists PASSED'

-- ── W2.1-T-hat-cell-list-domain-scope ────────────────────────────────────────
-- hat_cell_list('\x000101') must return the Oddjobz cell (domain_flag=257)
-- and must NOT return the other-hat cell (domain_flag=258).

DO $$
DECLARE
  oddjobz_count  INT;
  other_count    INT;
BEGIN
  SELECT COUNT(*) INTO oddjobz_count
  FROM hat_cell_list('\x000101'::BYTEA)
  WHERE cell_hash = decode(repeat('aa', 32), 'hex');

  IF oddjobz_count <> 1 THEN
    RAISE EXCEPTION 'W2.1-T-hat-cell-list-domain-scope FAILED: expected Oddjobz cell, got % rows', oddjobz_count;
  END IF;

  SELECT COUNT(*) INTO other_count
  FROM hat_cell_list('\x000101'::BYTEA)
  WHERE cell_hash = decode(repeat('dd', 32), 'hex');

  IF other_count <> 0 THEN
    RAISE EXCEPTION 'W2.1-T-hat-cell-list-domain-scope FAILED: other-hat cell leaked through, got % rows', other_count;
  END IF;

  RAISE NOTICE 'W2.1-T-hat-cell-list-domain-scope PASSED';
END $$;

\echo 'W2.1-T-hat-cell-list-domain-scope PASSED'

-- ── W2.1-T-hat-cell-list-isolation ───────────────────────────────────────────
-- hat_cell_list('\x000102') must NOT return the Oddjobz cell (domain_flag=257).

DO $$
DECLARE
  oddjobz_count INT;
BEGIN
  SELECT COUNT(*) INTO oddjobz_count
  FROM hat_cell_list('\x000102'::BYTEA)
  WHERE cell_hash = decode(repeat('aa', 32), 'hex');

  IF oddjobz_count <> 0 THEN
    RAISE EXCEPTION 'W2.1-T-hat-cell-list-isolation FAILED: Oddjobz cell leaked into different hat, got % rows', oddjobz_count;
  END IF;

  RAISE NOTICE 'W2.1-T-hat-cell-list-isolation PASSED';
END $$;

\echo 'W2.1-T-hat-cell-list-isolation PASSED'

-- ── W2.2-T-oddjobz-job-list ──────────────────────────────────────────────────
-- oddjobz_job_list view is selectable; no error is sufficient.

DO $$
DECLARE
  row_count INT;
BEGIN
  SELECT COUNT(*) INTO row_count FROM oddjobz_job_list;
  RAISE NOTICE 'W2.2-T-oddjobz-job-list PASSED (rows: %)', row_count;
END $$;

\echo 'W2.2-T-oddjobz-job-list PASSED'

-- ── W2.2-T-oddjobz-active-jobs ───────────────────────────────────────────────
-- oddjobz_active_jobs view is selectable and surfaces Pask-ranked rows.
-- With our fixture (h_state=0.85 > 0.5), we expect 1 row.

DO $$
DECLARE
  row_count INT;
BEGIN
  SELECT COUNT(*) INTO row_count FROM oddjobz_active_jobs;

  IF row_count < 1 THEN
    RAISE EXCEPTION 'W2.2-T-oddjobz-active-jobs FAILED: expected >= 1 active row, got %', row_count;
  END IF;

  RAISE NOTICE 'W2.2-T-oddjobz-active-jobs PASSED (rows: %)', row_count;
END $$;

\echo 'W2.2-T-oddjobz-active-jobs PASSED'

-- ── W2.2-T-oddjobz-customer-index ────────────────────────────────────────────
-- oddjobz_customer_index view is selectable; zero rows is fine.

DO $$
DECLARE
  row_count INT;
BEGIN
  SELECT COUNT(*) INTO row_count FROM oddjobz_customer_index;
  RAISE NOTICE 'W2.2-T-oddjobz-customer-index PASSED (rows: %)', row_count;
END $$;

\echo 'W2.2-T-oddjobz-customer-index PASSED'

-- ── W2.2-T-oddjobz-site-index ────────────────────────────────────────────────
-- oddjobz_site_index view is selectable; zero rows is fine.

DO $$
DECLARE
  row_count INT;
BEGIN
  SELECT COUNT(*) INTO row_count FROM oddjobz_site_index;
  RAISE NOTICE 'W2.2-T-oddjobz-site-index PASSED (rows: %)', row_count;
END $$;

\echo 'W2.2-T-oddjobz-site-index PASSED'

-- ── W2.2-T-oddjobz-job-by-id ─────────────────────────────────────────────────
-- oddjobz_job_by_id(cell_hash BYTEA) function is callable.
-- Calling with the Oddjobz fixture hash must return 1 row.

DO $$
DECLARE
  row_count INT;
BEGIN
  SELECT COUNT(*) INTO row_count
  FROM oddjobz_job_by_id(decode(repeat('aa', 32), 'hex'));

  IF row_count <> 1 THEN
    RAISE EXCEPTION 'W2.2-T-oddjobz-job-by-id FAILED: expected 1 row, got %', row_count;
  END IF;

  RAISE NOTICE 'W2.2-T-oddjobz-job-by-id PASSED';
END $$;

\echo 'W2.2-T-oddjobz-job-by-id PASSED'

-- ── W2.3-T-helm-oddjobz-jobs-active ──────────────────────────────────────────
-- helm_oddjobz_jobs_active is selectable (oddjobz.jobs.active context).

DO $$
DECLARE
  row_count INT;
BEGIN
  SELECT COUNT(*) INTO row_count FROM helm_oddjobz_jobs_active;
  RAISE NOTICE 'W2.3-T-helm-oddjobz-jobs-active PASSED (rows: %)', row_count;
END $$;

\echo 'W2.3-T-helm-oddjobz-jobs-active PASSED'

-- ── W2.3-T-helm-oddjobz-scheduled-today ──────────────────────────────────────
-- helm_oddjobz_jobs_scheduled_today is selectable (oddjobz.jobs.scheduled_today).

DO $$
DECLARE
  row_count INT;
BEGIN
  SELECT COUNT(*) INTO row_count FROM helm_oddjobz_jobs_scheduled_today;
  RAISE NOTICE 'W2.3-T-helm-oddjobz-scheduled-today PASSED (rows: %)', row_count;
END $$;

\echo 'W2.3-T-helm-oddjobz-scheduled-today PASSED'

-- ── W2.3-T-helm-oddjobz-awaiting-invoice ─────────────────────────────────────
-- helm_oddjobz_jobs_awaiting_invoice is selectable (oddjobz.jobs.awaiting_invoice).

DO $$
DECLARE
  row_count INT;
BEGIN
  SELECT COUNT(*) INTO row_count FROM helm_oddjobz_jobs_awaiting_invoice;
  RAISE NOTICE 'W2.3-T-helm-oddjobz-awaiting-invoice PASSED (rows: %)', row_count;
END $$;

\echo 'W2.3-T-helm-oddjobz-awaiting-invoice PASSED'

-- ── W2.3-T-helm-oddjobz-customers-recent ─────────────────────────────────────
-- helm_oddjobz_customers_recent is selectable (oddjobz.customers.recent).

DO $$
DECLARE
  row_count INT;
BEGIN
  SELECT COUNT(*) INTO row_count FROM helm_oddjobz_customers_recent;
  RAISE NOTICE 'W2.3-T-helm-oddjobz-customers-recent PASSED (rows: %)', row_count;
END $$;

\echo 'W2.3-T-helm-oddjobz-customers-recent PASSED'

-- ── W2.3-T-helm-oddjobz-visits-upcoming ──────────────────────────────────────
-- helm_oddjobz_visits_upcoming is selectable (oddjobz.visits.upcoming).

DO $$
DECLARE
  row_count INT;
BEGIN
  SELECT COUNT(*) INTO row_count FROM helm_oddjobz_visits_upcoming;
  RAISE NOTICE 'W2.3-T-helm-oddjobz-visits-upcoming PASSED (rows: %)', row_count;
END $$;

\echo 'W2.3-T-helm-oddjobz-visits-upcoming PASSED'

-- ── W2.3-T-helm-oddjobz-learned-concepts ─────────────────────────────────────
-- helm_oddjobz_learned_concepts must only surface stable threads whose
-- type_path starts with 'oddjobz.'.
-- Our fixture has type_path='oddjobz.job' on cell_id=repeat('aa',32),
-- so we expect exactly 1 row.

DO $$
DECLARE
  row_count INT;
BEGIN
  SELECT COUNT(*) INTO row_count FROM helm_oddjobz_learned_concepts;

  IF row_count <> 1 THEN
    RAISE EXCEPTION 'W2.3-T-helm-oddjobz-learned-concepts FAILED: expected 1 row, got %', row_count;
  END IF;

  RAISE NOTICE 'W2.3-T-helm-oddjobz-learned-concepts PASSED (rows: %)', row_count;
END $$;

\echo 'W2.3-T-helm-oddjobz-learned-concepts PASSED'

ROLLBACK;

\echo ''
\echo 'All W2.1+W2.2+W2.3 hat_views tests PASSED'

```
