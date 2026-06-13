---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/db/postgres/migrations/006_cert_dag_populator.sql
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.142385+00:00
---

# db/postgres/migrations/006_cert_dag_populator.sql

```sql
-- M5.9 — cert_dag populator from identity-certs log replay.
--
-- Provides an idempotent stored procedure that replays a JSONB array of
-- cert entries into cert_dag using ON CONFLICT DO NOTHING.  Can be called
-- repeatedly; only newly-unseen rows are counted.
--
-- Acceptance:
--   populate_cert_dag_from_jsonb(entries JSONB) → INT (newly inserted count)
--   cert_dag_summary view for reporting.
--
-- Idempotency: re-running this file against a database where M5.9 is already
-- applied is a no-op (CREATE OR REPLACE / DROP IF EXISTS ... CREATE).
--
-- JSONB entry schema (one element of the array):
--   cert_hash        TEXT  — hex-encoded bytes (no leading \x)
--   issuer_pub       TEXT  — hex-encoded bytes
--   subject_pub      TEXT  — hex-encoded bytes
--   cert_type        TEXT  — one of: identity, capability, delegation, revocation, session
--   cert_bytes       TEXT  — hex-encoded raw cert payload
--   issued_at        TEXT  — ISO-8601 timestamp
--   parent_cert_hash TEXT  — hex-encoded bytes, or null for root certs
--   metadata         JSONB — arbitrary metadata, or null

BEGIN;

-- ── populate_cert_dag_from_jsonb ──────────────────────────────────────
-- Accepts a JSONB array of cert log entries and bulk-upserts them into
-- cert_dag.  Returns the count of rows actually inserted (skips conflicts).
--
-- Each entry must supply at minimum: cert_hash, issuer_pub, subject_pub,
-- cert_type, cert_bytes, issued_at.  All other fields are optional.

CREATE OR REPLACE FUNCTION populate_cert_dag_from_jsonb(entries JSONB)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
  entry       JSONB;
  inserted    INT := 0;
  row_delta   INT;
BEGIN
  -- Validate that the input is a JSON array.
  IF jsonb_typeof(entries) <> 'array' THEN
    RAISE EXCEPTION 'populate_cert_dag_from_jsonb: expected a JSONB array, got %',
                    jsonb_typeof(entries);
  END IF;

  FOR entry IN SELECT jsonb_array_elements(entries)
  LOOP
    INSERT INTO cert_dag (
        cert_hash,
        parent_cert_hash,
        issuer_pub,
        subject_pub,
        cert_type,
        cert_bytes,
        issued_at,
        metadata
    )
    VALUES (
        -- cert_hash: required hex string
        decode(entry->>'cert_hash', 'hex'),

        -- parent_cert_hash: optional; NULL for root certs
        CASE
          WHEN entry->>'parent_cert_hash' IS NOT NULL
            THEN decode(entry->>'parent_cert_hash', 'hex')
          ELSE NULL
        END,

        -- issuer_pub: required hex string
        decode(entry->>'issuer_pub', 'hex'),

        -- subject_pub: required hex string
        decode(entry->>'subject_pub', 'hex'),

        -- cert_type: required; CHECK constraint enforces allowed values
        entry->>'cert_type',

        -- cert_bytes: required hex string (raw certificate payload)
        decode(entry->>'cert_bytes', 'hex'),

        -- issued_at: required ISO-8601
        (entry->>'issued_at')::TIMESTAMPTZ,

        -- metadata: optional JSONB blob
        CASE
          WHEN entry->'metadata' IS NOT NULL AND entry->>'metadata' <> 'null'
            THEN entry->'metadata'
          ELSE NULL
        END
    )
    ON CONFLICT (cert_hash) DO NOTHING;

    -- GET DIAGNOSTICS captures whether the INSERT succeeded.
    GET DIAGNOSTICS row_delta = ROW_COUNT;
    inserted := inserted + row_delta;
  END LOOP;

  RETURN inserted;
END;
$$;

-- ── cert_dag_summary ──────────────────────────────────────────────────
-- Reporting view: one row per cert_type with total, active (not revoked),
-- and expired counts, plus the timestamp of the most recent issuance.
-- "Revoked" is represented as metadata->>'revoked_at' IS NOT NULL since
-- the cert_dag table itself is append-only (K7 immutability invariant).

CREATE OR REPLACE VIEW cert_dag_summary AS
SELECT
    cert_type,
    COUNT(*)                                                      AS total,
    COUNT(*) FILTER (WHERE metadata->>'revoked_at' IS NULL)       AS active,
    COUNT(*) FILTER (WHERE
        issued_at < now()
        AND metadata->>'expires_at' IS NOT NULL
        AND (metadata->>'expires_at')::TIMESTAMPTZ < now()
    )                                                             AS expired,
    MAX(issued_at)                                                AS latest_issuance
FROM cert_dag
GROUP BY cert_type;

COMMIT;

```
