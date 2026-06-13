---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/deploy/semantos-orphan-streams.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.541612+00:00
---

# tools/deploy/semantos-orphan-streams.sh

```sh
#!/usr/bin/env bash
# W7.13 — Nightly NATS orphan stream purge.
#
# Queries Postgres for all active operators (status IN active/suspended/exiting),
# builds the comma-separated op_pkh list, and hands it to `brain orphan-streams
# --delete`.  Any stream in the op_<pkh16> namespace not tied to a known active
# operator is deleted.
#
# This script is invoked by the semantos-orphan-streams.timer systemd unit.
# It must run on the same host as the brain process (same NATS instance).
#
# Environment / defaults:
#   BRAIN_BIN      path to the brain binary          default: /usr/local/bin/brain
#   BRAIN_DB_URL   libpq connection string            default: host=localhost dbname=semantos user=semantos_admin
#   NATS_HOST      NATS server host                   default: 127.0.0.1
#   NATS_PORT      NATS server port                   default: 4222

set -euo pipefail

BRAIN_BIN="${BRAIN_BIN:-/usr/local/bin/brain}"
BRAIN_DB_URL="${BRAIN_DB_URL:-host=localhost dbname=semantos user=semantos_admin}"
NATS_HOST="${NATS_HOST:-127.0.0.1}"
NATS_PORT="${NATS_PORT:-4222}"

# Query Postgres for all non-exited operator op_pkh values.
# op_pkh is stored as a 16-char lowercase hex TEXT in the operators table.
KNOWN_PKHS=$(psql "${BRAIN_DB_URL}" --no-align --tuples-only \
  -c "SELECT op_pkh FROM operators WHERE status IN ('active', 'suspended', 'exiting');" \
  | tr '\n' ',' | sed 's/,$//')

if [[ -z "${KNOWN_PKHS}" ]]; then
  KNOWN_PKHS=""
fi

echo "[orphan-streams] known operators: $(echo "${KNOWN_PKHS}" | tr ',' '\n' | grep -c . || echo 0)"

exec "${BRAIN_BIN}" orphan-streams \
  --known-pkh-list "${KNOWN_PKHS}" \
  --nats-host "${NATS_HOST}" \
  --nats-port "${NATS_PORT}" \
  --delete

```
