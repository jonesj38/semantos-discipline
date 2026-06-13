---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/migrations/010_audit_log_fdw.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.143491+00:00
---

# db/postgres/migrations/010_audit_log_fdw.sql

```sql
-- 010_audit_log_fdw.sql
--
-- M5.7: signed_bundle_audit_sqlite FDW (staging pattern)
--
-- Implements a "FDW-lite" pattern: browser-side audit rows (produced by
-- sqlite-audit-log.ts, M2.5) are periodically exported and ingested via
-- refresh_audit_log(entries JSONB). The signed_bundle_audit_sqlite view
-- provides the SQL-queryable surface.
--
-- Callers use:
--   SELECT * FROM signed_bundle_audit_sqlite WHERE cert_id = $1
--
-- The refresh function accepts a JSONB array where each element has:
--   cert_id       TEXT    — hex-encoded cert identifier
--   nonce         TEXT    — hex-encoded nonce (anti-replay)
--   envelope_hash TEXT    — hex-encoded hash of the signed envelope
--   payload_type  TEXT    — e.g. 'signed_bundle_v1'
--   payload_hash  TEXT    — hex-encoded hash of the payload
--   created_at_ms BIGINT  — unix timestamp in milliseconds
--   signature     TEXT    — hex-encoded signature bytes

-- ── Staging table ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS audit_log_cache (
  id              BIGSERIAL   PRIMARY KEY,
  cert_id         BYTEA       NOT NULL,
  nonce           BYTEA       NOT NULL,
  envelope_hash   BYTEA       NOT NULL,
  payload_type    TEXT        NOT NULL,
  payload_hash    BYTEA       NOT NULL,
  created_at_ms   BIGINT      NOT NULL,
  signature       BYTEA       NOT NULL,
  cached_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(cert_id, nonce)
);

-- ── Indexes ───────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_audit_log_cache_cert ON audit_log_cache(cert_id);

-- ── View — the "foreign table" surface ───────────────────────────────

CREATE OR REPLACE VIEW signed_bundle_audit_sqlite AS
  SELECT id, cert_id, nonce, envelope_hash, payload_type, payload_hash,
         created_at_ms, signature, cached_at
  FROM audit_log_cache;

-- ── Refresh function ──────────────────────────────────────────────────
--
-- refresh_audit_log(entries JSONB) RETURNS INT
--
-- Accepts a JSONB array of audit entry objects (hex-encoded binary fields).
-- Inserts new rows; skips duplicates on (cert_id, nonce) conflict.
-- Returns the count of newly inserted rows.

CREATE OR REPLACE FUNCTION refresh_audit_log(entries JSONB)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
  entry    JSONB;
  inserted INT := 0;
  n        INT;
BEGIN
  FOR entry IN SELECT jsonb_array_elements(entries)
  LOOP
    INSERT INTO audit_log_cache (
      cert_id, nonce, envelope_hash, payload_type,
      payload_hash, created_at_ms, signature
    )
    VALUES (
      decode(entry->>'cert_id',       'hex'),
      decode(entry->>'nonce',         'hex'),
      decode(entry->>'envelope_hash', 'hex'),
      entry->>'payload_type',
      decode(entry->>'payload_hash',  'hex'),
      (entry->>'created_at_ms')::BIGINT,
      decode(entry->>'signature',     'hex')
    )
    ON CONFLICT (cert_id, nonce) DO NOTHING;

    GET DIAGNOSTICS n = ROW_COUNT;
    inserted := inserted + n;
  END LOOP;

  RETURN inserted;
END;
$$;

```
