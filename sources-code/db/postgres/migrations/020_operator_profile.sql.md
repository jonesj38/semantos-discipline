---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/migrations/020_operator_profile.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.143765+00:00
---

# db/postgres/migrations/020_operator_profile.sql

```sql
-- 020_operator_profile.sql
--
-- S8 — Semantos Sites 1.0.
-- Adds JSONB profile columns for cached strategy cells and site_status
-- lifecycle tracking to the `operators` table.
--
-- Profile columns hold the rendered payload of each strategy cell so the
-- site renderer can serve operator profiles without hitting the cell DAG on
-- every request.  site_status gates the public visibility of a site.
--
-- Idempotency: all ALTER TABLE uses ADD COLUMN IF NOT EXISTS.
-- Depends on: 001–019.

BEGIN;

-- ── Profile JSONB columns ─────────────────────────────────────────────────────
-- Each column caches the most-recently-published strategy cell payload for the
-- operator.  NULL until the operator publishes the corresponding cell.

ALTER TABLE operators
    ADD COLUMN IF NOT EXISTS profile_lbc      JSONB;   -- strategy.lbc cell payload

ALTER TABLE operators
    ADD COLUMN IF NOT EXISTS profile_icp      JSONB;   -- strategy.icp cell payload

ALTER TABLE operators
    ADD COLUMN IF NOT EXISTS profile_services JSONB;   -- strategy.services cell payload (array)

ALTER TABLE operators
    ADD COLUMN IF NOT EXISTS profile_pricing  JSONB;   -- strategy.pricing cell payload

-- ── site_status column ────────────────────────────────────────────────────────
-- Lifecycle state for the operator's public site.
--   draft  — not yet published; renderer returns 404 for public requests.
--   live   — publicly visible; renderer serves the profile.
--   paused — temporarily hidden; renderer returns 503 for public requests.

ALTER TABLE operators
    ADD COLUMN IF NOT EXISTS site_status TEXT NOT NULL DEFAULT 'draft'
        CONSTRAINT operators_site_status_valid
            CHECK (site_status IN ('draft', 'live', 'paused'));

-- ── Index for renderer "list all live sites" query ────────────────────────────

CREATE INDEX IF NOT EXISTS operators_site_status_idx
    ON operators (site_status)
    WHERE site_status = 'live';

-- ── Role grants ───────────────────────────────────────────────────────────────
-- semantos_admin already has SELECT, INSERT, UPDATE on operators (017).
-- Grant UPDATE on the new profile + site_status columns to semantos_admin so
-- the brain service can push cell cache updates.
-- semantos_brain has SELECT on operators (017); RLS (op_self policy) gates rows.
-- No additional column-level grants needed — table-level grants already cover
-- the new columns for both roles.

-- Explicit notice so the grant intent is visible in migration logs even though
-- the table-level grants from 017 already cover the new columns.
DO $$ BEGIN
    RAISE NOTICE 'S8 (020): profile columns + site_status added to operators; '
                 'table-level grants (017) already cover new columns for '
                 'semantos_admin and semantos_brain';
END $$;

COMMIT;

```
