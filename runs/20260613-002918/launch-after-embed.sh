#!/usr/bin/env bash
set -euo pipefail
DISC="/home/jake/.edwinpai/disciplines/semantos"
RUN_DIR="/home/jake/.edwinpai/disciplines/semantos/runs/20260613-002918"
EMBED_PID="2875206"
EMBED_LOG="/home/jake/.edwinpai/disciplines/semantos/state/qmd-embed-20260613-002939.log"
WATCH_LOG="$RUN_DIR/launch-after-embed.log"
RLM_LOG="$RUN_DIR/rlm.log"
RLM_PID_FILE="$RUN_DIR/rlm.pid"
{
  echo "[$(date -Iseconds)] Waiting for QMD embed pid $EMBED_PID"
  while kill -0 "$EMBED_PID" 2>/dev/null; do
    sleep 30
  done
  echo "[$(date -Iseconds)] QMD embed process exited"
  echo "--- embed log tail ---"
  tail -120 "$EMBED_LOG" || true
  if ! grep -Eq "✓ Done!|All content hashes already have embeddings|No non-empty documents" "$EMBED_LOG"; then
    echo "[$(date -Iseconds)] WARNING: embed log did not contain a clear success marker; attempting retrieval smoke anyway"
  fi
  echo "[$(date -Iseconds)] Running QMD retrieval smoke"
  QMD_OPENAI=1 QMD_SQLITE_BUSY_TIMEOUT_MS=10000 qmd search "Semantos SemanticTypes Linearity vault" -c semantos-discipline --json > "$RUN_DIR/qmd-smoke.json"
  python3 - <<'PY'
import json, pathlib, sys
p = pathlib.Path('/home/jake/.edwinpai/disciplines/semantos/runs/20260613-002918/qmd-smoke.json')
data = json.loads(p.read_text() or '[]')
print(f'qmd smoke results: {len(data)}')
if not data:
    sys.exit(1)
PY
  echo "[$(date -Iseconds)] Starting Shad RLM"
  (
    cd "$DISC"
    "$RUN_DIR/run-command.sh"
  ) > "$RLM_LOG" 2>&1 &
  rlm_pid=$!
  echo "$rlm_pid" > "$RLM_PID_FILE"
  echo "[$(date -Iseconds)] Shad RLM started pid=$rlm_pid log=$RLM_LOG"
} >> "$WATCH_LOG" 2>&1
