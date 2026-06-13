#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "usage: $0 <stage-id> <output-path> <prompt-file> <run-root>" >&2
  exit 2
fi

STAGE_ID="$1"
OUTPUT="$2"
PROMPT_FILE="$3"
RUN_ROOT="$4"
BASE="/home/jake/.edwinpai/disciplines/semantos"
mkdir -p "$RUN_ROOT/logs" "$RUN_ROOT/prompts"
cp "$PROMPT_FILE" "$RUN_ROOT/prompts/${STAGE_ID}.md"
LOG="$RUN_ROOT/logs/${STAGE_ID}.log"
RESUME_LOG="$RUN_ROOT/logs/${STAGE_ID}.resume.log"

export QMD_OPENAI=1
export QMD_SQLITE_BUSY_TIMEOUT_MS=10000
export SHAD_LLM_PROVIDER=edwin-gateway
export SHAD_EDWIN_GATEWAY_BASE_URL=http://127.0.0.1:18789/v1
export SHAD_EDWIN_GATEWAY_API_KEY=not-needed
export SHAD_ORCHESTRATOR_MODEL=gpt-5.5
export SHAD_WORKER_MODEL=gpt-5.5
export SHAD_LEAF_MODEL=gpt-5.5
export DEFAULT_MAX_WALL_TIME=14400

echo "[$(date -Is)] START $STAGE_ID" | tee -a "$RUN_ROOT/pipeline.log"
set +e
shad run "$(cat "$PROMPT_FILE")" \
  --strategy analysis \
  --sources "$BASE/sources-code" \
  --collection sources-code \
  --profile deep \
  --provider edwin-gateway \
  -O gpt-5.5 -W gpt-5.5 -L gpt-5.5 \
  --max-nodes 160 \
  --max-time 10800 \
  --output "$OUTPUT" \
  > "$LOG" 2>&1
code=$?
set -e

if grep -q "Status: complete" "$LOG" && [[ -s "$OUTPUT" ]] && ! grep -qx "No result" "$OUTPUT"; then
  echo "[$(date -Is)] DONE $STAGE_ID -> $OUTPUT" | tee -a "$RUN_ROOT/pipeline.log"
  exit 0
fi

if grep -q "Status: partial" "$LOG"; then
  RUN_ID=$(grep -E "^Run ID:" "$LOG" | tail -1 | awk '{print $3}')
  if [[ -n "${RUN_ID:-}" ]]; then
    echo "[$(date -Is)] RESUME $STAGE_ID run=$RUN_ID" | tee -a "$RUN_ROOT/pipeline.log"
    set +e
    shad resume "$RUN_ID" --profile deep --max-nodes 240 --max-time 14400 -O gpt-5.5 -W gpt-5.5 -L gpt-5.5 > "$RESUME_LOG" 2>&1
    rcode=$?
    set -e
    if grep -q "Status: complete" "$RESUME_LOG" && [[ -s "$OUTPUT" ]] && ! grep -qx "No result" "$OUTPUT"; then
      echo "[$(date -Is)] DONE_AFTER_RESUME $STAGE_ID -> $OUTPUT" | tee -a "$RUN_ROOT/pipeline.log"
      exit 0
    fi
    echo "[$(date -Is)] PARTIAL_AFTER_RESUME $STAGE_ID code=$rcode -> $OUTPUT" | tee -a "$RUN_ROOT/pipeline.log"
    exit 1
  fi
fi

echo "[$(date -Is)] FAILED $STAGE_ID code=$code -> $OUTPUT" | tee -a "$RUN_ROOT/pipeline.log"
exit "$code"
