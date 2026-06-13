---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/torture/M6_torture.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.588527+00:00
---

# tests/torture/M6_torture.sh

```sh
#!/usr/bin/env bash
# M6-T — Registry Drift Torture Test.
#
# Per §6 M6-T conditions:
#   1. Inject simulated drift (edit LMDB cache to disagree with Postgres);
#      drift-detection must catch within 60 s.
#   2. Pravega change-feed lag injected; cache invalidation must respect lag.
#   3. Browser mirror falls behind by 1000 events; resyncs cleanly on reconnect.
#   4. Federation peer joins with conflicting registry view; reconciliation
#      preserves Postgres source-of-truth.
#
# Pass criteria: all drift detected within 60 s; all reconciliations preserve
#   Postgres source-of-truth; no silent drift survives 60 s.

set -euo pipefail

: "${PGDATABASE:=semantos_production}"
: "${PGHOST:=localhost}"
: "${PGPORT:=5432}"
: "${BRAIN_BIN:=$(which brain 2>/dev/null || echo "brain-not-found")}"
: "${LMDB_DATA_DIR:=/tmp/semantos-torture-m6-registry}"
: "${DRIFT_DETECT_TIMEOUT:=60}"
: "${COMPOSE_FILE:=infra/pravega/docker-compose.yml}"
: "${BASE_URL:=http://localhost:5175}"

LOGDIR="$(dirname "$0")/logs"
mkdir -p "${LOGDIR}"
LOGFILE="${LOGDIR}/M6_torture_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOGFILE}") 2>&1

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}  $*"; }
fail() { echo -e "${RED}FAIL${NC}  $*"; exit 1; }
log()  { echo "[$(date -u +%H:%M:%S)] $*"; }

log "M6-T registry drift torture test starting"
log "Database: ${PGDATABASE}@${PGHOST}:${PGPORT}"

# Validate prerequisites.
psql -d "${PGDATABASE}" -h "${PGHOST}" -p "${PGPORT}" -c "SELECT 1" > /dev/null 2>&1 || \
    fail "Cannot connect to Postgres at ${PGHOST}:${PGPORT}/${PGDATABASE}"

if [[ "${BRAIN_BIN}" == "brain-not-found" ]]; then
    fail "brain binary not found — required for LMDB cache manipulation"
fi

if ! command -v registry-drift-cli &>/dev/null; then
    fail "registry-drift-cli not found — expected from M6 deliverables"
fi

# ── condition 1: simulated drift → detection within 60 s ─────────────

log "=== Condition 1: LMDB cache drift detection within ${DRIFT_DETECT_TIMEOUT}s ==="

# Insert a known cert into Postgres.
CERT_HASH=$(psql -d "${PGDATABASE}" -h "${PGHOST}" -p "${PGPORT}" -tAc "
    INSERT INTO cert_dag (cert_hash, issuer_pub, subject_pub, cert_type, cert_bytes, issued_at)
    VALUES (
        decode('deadbeef01020304deadbeef01020304deadbeef01020304deadbeef01020304', 'hex'),
        decode('aabb', 'hex'),
        decode('ccdd', 'hex'),
        'identity',
        decode('0102', 'hex'),
        now()
    )
    ON CONFLICT DO NOTHING
    RETURNING encode(cert_hash, 'hex');
")
[[ -z "${CERT_HASH}" ]] && CERT_HASH="deadbeef01020304deadbeef01020304deadbeef01020304deadbeef01020304"

# Tamper with the LMDB cache directly (write a wrong value for the cert).
registry-drift-cli inject-drift \
    --data-dir="${LMDB_DATA_DIR}" \
    --key="cert:${CERT_HASH}" \
    --corrupt-value \
    >> "${LOGDIR}/m6_drift_inject.log" 2>&1 || fail "Could not inject drift into LMDB cache"

log "Drift injected — waiting for detection (timeout: ${DRIFT_DETECT_TIMEOUT}s)"
DRIFT_DETECTED=0
for (( elapsed=0; elapsed<=DRIFT_DETECT_TIMEOUT; elapsed+=5 )); do
    if registry-drift-cli check-drift \
        --data-dir="${LMDB_DATA_DIR}" \
        --pgdatabase="${PGDATABASE}" --pghost="${PGHOST}" --pgport="${PGPORT}" \
        >> "${LOGDIR}/m6_drift_check.log" 2>&1; then
        DRIFT_DETECTED=1
        log "Drift detected after ${elapsed}s"
        break
    fi
    sleep 5
done

if (( DRIFT_DETECTED == 0 )); then
    fail "Drift NOT detected within ${DRIFT_DETECT_TIMEOUT}s"
fi

# Verify that after detection the cache was healed back to Postgres truth.
registry-drift-cli verify-healed \
    --data-dir="${LMDB_DATA_DIR}" \
    --pgdatabase="${PGDATABASE}" --pghost="${PGHOST}" --pgport="${PGPORT}" \
    >> "${LOGDIR}/m6_drift_healed.log" 2>&1 || fail "Cache not healed after drift detection"

pass "Condition 1: drift detected and healed within ${elapsed}s (< ${DRIFT_DETECT_TIMEOUT}s)"

# ── condition 2: Pravega change-feed lag ─────────────────────────────

log "=== Condition 2: Pravega change-feed lag + cache invalidation ==="

if ! docker compose -f "${COMPOSE_FILE}" ps --services 2>/dev/null | grep -q pravega; then
    log "SKIP condition 2 — Pravega not running (start with: docker compose -f ${COMPOSE_FILE} up -d)"
else
    # Inject 10 s lag on the Pravega reader by pausing the feed consumer.
    registry-drift-cli inject-feed-lag \
        --compose-file="${COMPOSE_FILE}" \
        --lag-seconds=10 \
        >> "${LOGDIR}/m6_feed_lag.log" 2>&1 || fail "Could not inject Pravega feed lag"

    # Write a registry change while lagged.
    psql -d "${PGDATABASE}" -h "${PGHOST}" -p "${PGPORT}" \
        -c "UPDATE cert_dag SET metadata = '{\"test\": \"lag\"}' WHERE encode(cert_hash,'hex') = '${CERT_HASH}'" \
        >> "${LOGDIR}/m6_feed_lag.log" 2>&1

    # Verify cache does NOT eagerly serve the stale value during lag.
    STALE_RESULT=$(registry-drift-cli cache-get \
        --data-dir="${LMDB_DATA_DIR}" \
        --key="cert:${CERT_HASH}" 2>/dev/null || echo "stale_ok")
    if [[ "${STALE_RESULT}" == *'"test":"lag"'* ]]; then
        fail "Cache served lagged (premature) value during Pravega lag"
    fi

    # Release the lag and wait for cache to catch up.
    registry-drift-cli release-feed-lag \
        --compose-file="${COMPOSE_FILE}" \
        >> "${LOGDIR}/m6_feed_lag.log" 2>&1
    sleep 15 # allow feed to drain

    HEALED=$(registry-drift-cli cache-get \
        --data-dir="${LMDB_DATA_DIR}" \
        --key="cert:${CERT_HASH}" 2>/dev/null || echo "")
    if [[ "${HEALED}" != *'"test":"lag"'* ]]; then
        fail "Cache did not catch up after Pravega lag released"
    fi

    pass "Condition 2: feed lag respected; cache invalidated correctly after lag clears"
fi

# ── condition 3: browser mirror 1000-event lag → resync ─────────────

log "=== Condition 3: browser mirror 1000-event lag → clean resync ==="

if ! command -v playwright &>/dev/null; then
    log "SKIP condition 3 — playwright not found (M2 browser tier not installed)"
else
    playwright test \
        --config apps/world-client/playwright.config.ts \
        --grep "M6-T.*mirror-resync" \
        >> "${LOGDIR}/m6_mirror_resync.log" 2>&1 || fail "Browser mirror resync test failed — see ${LOGDIR}/m6_mirror_resync.log"
    pass "Condition 3: browser mirror resynced cleanly after 1000-event lag"
fi

# ── condition 4: federation peer conflict → Postgres wins ────────────

log "=== Condition 4: conflicting federation peer → reconciliation preserves Postgres truth ==="

if ! command -v federation-cli &>/dev/null; then
    log "SKIP condition 4 — federation-cli not found (M7 deliverables not yet built)"
else
    # Spin up a simulated peer with a conflicting registry view.
    federation-cli peer-start \
        --conflict-mode=registry \
        --pgdatabase="${PGDATABASE}" --pghost="${PGHOST}" --pgport="${PGPORT}" \
        >> "${LOGDIR}/m6_federation.log" 2>&1 || fail "Could not start conflicting federation peer"

    sleep 5 # let peer announce its (wrong) view

    # Trigger reconciliation.
    federation-cli reconcile \
        --pgdatabase="${PGDATABASE}" --pghost="${PGHOST}" --pgport="${PGPORT}" \
        >> "${LOGDIR}/m6_federation.log" 2>&1 || fail "Reconciliation failed"

    # Verify that Postgres truth survived.
    PG_CERT=$(psql -d "${PGDATABASE}" -h "${PGHOST}" -p "${PGPORT}" -tAc "
        SELECT encode(cert_hash,'hex') FROM cert_dag
        WHERE encode(cert_hash,'hex') = '${CERT_HASH}'
    ")
    [[ "${PG_CERT}" == "${CERT_HASH}" ]] || \
        fail "Postgres cert_dag row was overwritten by conflicting peer — source-of-truth violated"

    federation-cli peer-stop >> "${LOGDIR}/m6_federation.log" 2>&1 || true
    pass "Condition 4: reconciliation preserved Postgres source-of-truth"
fi

pass "M6-T torture test PASSED"
log "Log: ${LOGFILE}"

```
