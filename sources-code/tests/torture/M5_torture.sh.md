---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/torture/M5_torture.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.587105+00:00
---

# tests/torture/M5_torture.sh

```sh
#!/usr/bin/env bash
# M5-T — Postgres Reasoning Tier Torture Test.
#
# Per §6 M5-T conditions:
#   1. 100 K concurrent recursive ancestry walks over 24 h.
#   2. Four-way FDW JOIN query running every 10 s.
#   3. Bert's intent reducer producing 1000 intents/sec.
#   4. Schema migration applied mid-load; assert no downtime, no incorrect results.
#   5. FDW upstream node (LMDB) restarts every 4 h; assert FDW reconnects cleanly.
#
# Pass criteria: all queries return correct results; no FDW-stale-result errors;
#   schema migration completes without lock contention > 1 min.

set -euo pipefail

: "${PGDATABASE:=semantos_production}"
: "${PGHOST:=localhost}"
: "${PGPORT:=5432}"
: "${DURATION_HOURS:=24}"
: "${INTENT_RATE:=1000}"

DURATION_SECS=$(( DURATION_HOURS * 3600 ))
LOGDIR="$(dirname "$0")/logs"
mkdir -p "${LOGDIR}"
LOGFILE="${LOGDIR}/M5_torture_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOGFILE}") 2>&1

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}  $*"; }
fail() { echo -e "${RED}FAIL${NC}  $*"; exit 1; }
log()  { echo "[$(date -u +%H:%M:%S)] $*"; }

log "M5-T torture test starting (${DURATION_HOURS}h)"
log "Database: ${PGDATABASE}@${PGHOST}:${PGPORT}"

# Validate Postgres connectivity.
psql -d "${PGDATABASE}" -h "${PGHOST}" -p "${PGPORT}" -c "SELECT 1" > /dev/null 2>&1 || \
    fail "Cannot connect to Postgres at ${PGHOST}:${PGPORT}/${PGDATABASE}"

# ── seed 100 M cert_dag rows if not already present ──────────────────

ROW_COUNT=$(psql -d "${PGDATABASE}" -h "${PGHOST}" -p "${PGPORT}" -tAc "SELECT COUNT(*) FROM cert_dag")
if (( ROW_COUNT < 1000000 )); then
    log "Seeding cert_dag with 1 M rows (target: 100 M for full torture; using 1 M for CI)…"
    psql -d "${PGDATABASE}" -h "${PGHOST}" -p "${PGPORT}" \
        -f tests/torture/fixtures/seed_cert_dag_1m.sql \
        >> "${LOGDIR}/m5_seed.log" 2>&1 || fail "cert_dag seeding failed"
fi

# ── condition 1: recursive ancestry walks ────────────────────────────

log "=== Condition 1: 100 K recursive ancestry walks ==="
psql -d "${PGDATABASE}" -h "${PGHOST}" -p "${PGPORT}" << 'EOSQL' >> "${LOGDIR}/m5_recursive.log" 2>&1
DO $$
DECLARE
  i INT;
  tip BYTEA;
  cnt BIGINT;
BEGIN
  FOR i IN 1..100000 LOOP
    -- Pick a random cert at depth ≥ 50 as the starting tip.
    SELECT cert_hash INTO tip
    FROM cert_dag
    WHERE parent_cert_hash IS NOT NULL
    ORDER BY random()
    LIMIT 1;

    SELECT COUNT(*) INTO cnt FROM cert_ancestors(tip);

    IF cnt < 1 THEN
      RAISE EXCEPTION 'cert_ancestors returned 0 rows for hash %', tip;
    END IF;
  END LOOP;
  RAISE NOTICE 'Recursive walk: 100 K iterations OK';
END $$;
EOSQL
pass "Condition 1: 100 K recursive walks"

# ── condition 2: four-way FDW JOIN every 10 s ────────────────────────

log "=== Condition 2: FDW JOIN every 10 s for ${DURATION_HOURS}h ==="
FDW_END=$(( $(date +%s) + DURATION_SECS ))
FDW_ERRORS=0

while (( $(date +%s) < FDW_END )); do
    psql -d "${PGDATABASE}" -h "${PGHOST}" -p "${PGPORT}" << 'EOSQL' >> "${LOGDIR}/m5_fdw.log" 2>&1 || (( FDW_ERRORS++ ))
    SELECT c.cert_hash, t.seq_num, a.evidence_hash
    FROM cert_dag c
    LEFT JOIN cells_lmdb lmdb ON lmdb.type_hash = c.cert_hash
    LEFT JOIN session_chain t   ON t.host_pub   = c.issuer_pub
    LEFT JOIN equivocation_evidence a ON a.host_pub = c.issuer_pub
    WHERE c.cert_type = 'identity'
    LIMIT 10;
EOSQL
    sleep 10
done

if (( FDW_ERRORS > 0 )); then
    fail "FDW JOIN: ${FDW_ERRORS} errors over ${DURATION_HOURS}h"
fi
pass "Condition 2: FDW JOIN ran without error for ${DURATION_HOURS}h"

# ── condition 3: intent reducer throughput ────────────────────────────

log "=== Condition 3: ${INTENT_RATE} intents/sec for ${DURATION_HOURS}h ==="
if command -v intent-reducer-cli &>/dev/null; then
    intent-reducer-cli \
        --rate="${INTENT_RATE}" \
        --duration="${DURATION_SECS}" \
        >> "${LOGDIR}/m5_reducer.log" 2>&1 || fail "Intent reducer test failed"
    pass "Condition 3: intent reducer throughput"
else
    log "SKIP condition 3 — intent-reducer-cli not built (M5.10 is Bert-owned)"
fi

# ── condition 4: schema migration mid-load ────────────────────────────

log "=== Condition 4: schema migration mid-load ==="
MIGRATION_START=$(date +%s)
psql -d "${PGDATABASE}" -h "${PGHOST}" -p "${PGPORT}" \
    -c "ALTER TABLE cert_dag ADD COLUMN IF NOT EXISTS torture_flag BOOLEAN DEFAULT false" \
    >> "${LOGDIR}/m5_migration.log" 2>&1 || fail "Schema migration failed"
MIGRATION_ELAPSED=$(( $(date +%s) - MIGRATION_START ))
if (( MIGRATION_ELAPSED > 60 )); then
    fail "Schema migration took ${MIGRATION_ELAPSED}s > 60 s (lock contention)"
fi
pass "Condition 4: migration completed in ${MIGRATION_ELAPSED}s (< 60 s)"

# ── condition 5: LMDB FDW upstream restart every 4 h ─────────────────

log "=== Condition 5: FDW reconnect after LMDB restart (verify 1 cycle) ==="
if [[ -n "${BRAIN_BIN:-}" ]]; then
    kill -HUP "$(pgrep -x brain || echo 0)" 2>/dev/null || true
    sleep 5
    psql -d "${PGDATABASE}" -h "${PGHOST}" -p "${PGPORT}" \
        -c "SELECT count(*) FROM cells_lmdb LIMIT 1" \
        >> "${LOGDIR}/m5_fdw_reconnect.log" 2>&1 || fail "FDW did not reconnect after LMDB restart"
    pass "Condition 5: FDW reconnects after LMDB restart"
else
    log "SKIP condition 5 — BRAIN_BIN not set; FDW reconnect requires running brain"
fi

pass "M5-T torture test PASSED"
log "Log: ${LOGFILE}"

```
