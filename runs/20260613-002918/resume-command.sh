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
export DEFAULT_MAX_WALL_TIME=10800
shad resume 988d6ecf-01e3-4119-87a9-15f2857c9bcc \
  --profile deep \
  --max-nodes 240 \
  --max-time 10800 \
  -O gpt-5.5 \
  -W gpt-5.5 \
  -L gpt-5.5
