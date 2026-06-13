#!/usr/bin/env bash
set -euo pipefail
export QMD_OPENAI=1
export QMD_SQLITE_BUSY_TIMEOUT_MS=10000
export SHAD_LLM_PROVIDER=edwin-gateway
export SHAD_EDWIN_GATEWAY_BASE_URL=http://127.0.0.1:18789/v1
export SHAD_EDWIN_GATEWAY_API_KEY=not-needed
export SHAD_ORCHESTRATOR_MODEL=gpt-5.5
export SHAD_WORKER_MODEL=gpt-5.5
export SHAD_LEAF_MODEL=gpt-5.5
shad run "$(cat '/home/jake/.edwinpai/disciplines/semantos/runs/20260613-120324-code-first/goal.txt')" \
  --strategy discipline-report \
  --sources '/home/jake/.edwinpai/disciplines/semantos/sources-code' \
  --collection sources-code \
  --profile deep \
  --provider edwin-gateway \
  -O gpt-5.5 -W gpt-5.5 -L gpt-5.5 \
  --max-nodes 160 \
  --max-time 10800 \
  --output '/home/jake/.edwinpai/disciplines/semantos/runs/20260613-120324-code-first/final.report.md'
