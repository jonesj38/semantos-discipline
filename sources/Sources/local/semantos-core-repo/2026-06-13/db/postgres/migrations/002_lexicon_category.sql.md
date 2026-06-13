---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/migrations/002_lexicon_category.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.140487+00:00
---

# db/postgres/migrations/002_lexicon_category.sql

```sql
-- M5.2 — Postgres schema: lexicon_category, taxonomy_index.
--
-- Acceptance: type_hash uniqueness enforced; GIN index on taxonomy fields.
-- Depends on: M5.1 (cert_dag must exist for the intent FK reference in M5.9).
--
-- Idempotency: CREATE TABLE/INDEX IF NOT EXISTS throughout.

BEGIN;

-- ── lexicon_category ─────────────────────────────────────────────────
-- Maps a cell's type_hash (16-byte truncated SHA-256 of the type descriptor)
-- to a human-readable category and a set of taxonomy tags used by the
-- intent reducer for classification and routing.

CREATE TABLE IF NOT EXISTS lexicon_category (
    type_hash        BYTEA   NOT NULL,
    category_name    TEXT    NOT NULL,
    -- JSON array of string tags, e.g. ["identity","credential","revocable"].
    taxonomy_tags    JSONB   NOT NULL DEFAULT '[]'::jsonb,
    -- Optional free-form description for human consumers.
    description      TEXT,
    -- When this entry was last updated by the type registry.
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT lexicon_category_pkey        PRIMARY KEY (type_hash),
    -- taxonomy_tags must be a JSON array (not an object or scalar).
    CONSTRAINT lexicon_tags_is_array        CHECK (jsonb_typeof(taxonomy_tags) = 'array')
);

-- GIN index so `taxonomy_tags @> '["identity"]'::jsonb` is fast.
CREATE INDEX IF NOT EXISTS lexicon_taxonomy_gin ON lexicon_category
    USING GIN (taxonomy_tags jsonb_path_ops);

-- B+tree for category_name prefix searches.
CREATE INDEX IF NOT EXISTS lexicon_category_name_idx ON lexicon_category (category_name);

-- ── taxonomy_index ───────────────────────────────────────────────────
-- Ordered ranking of type_hashes within a taxonomy tag.
-- Supports the intent reducer's "find best match" queries.

CREATE TABLE IF NOT EXISTS taxonomy_index (
    type_hash      BYTEA    NOT NULL REFERENCES lexicon_category (type_hash) ON DELETE CASCADE,
    ordinal_rank   INT      NOT NULL,
    label          TEXT     NOT NULL,

    CONSTRAINT taxonomy_index_pkey   PRIMARY KEY (type_hash, ordinal_rank),
    CONSTRAINT taxonomy_rank_pos     CHECK (ordinal_rank > 0)
);

CREATE INDEX IF NOT EXISTS taxonomy_rank_idx ON taxonomy_index (ordinal_rank, label);

COMMIT;

```
