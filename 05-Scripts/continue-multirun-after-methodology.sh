#!/usr/bin/env bash
set -euo pipefail

BASE="/home/jake/.edwinpai/disciplines/semantos"
RUN_ROOT="${1:-$BASE/07-Out-Reports/multirun-$(date +%Y%m%d-%H%M%S)-continued}"
mkdir -p "$RUN_ROOT/prompts" "$RUN_ROOT/logs" "$RUN_ROOT/outputs"

export QMD_OPENAI=1
export QMD_SQLITE_BUSY_TIMEOUT_MS=10000
export SHAD_LLM_PROVIDER=edwin-gateway
export SHAD_EDWIN_GATEWAY_BASE_URL=http://127.0.0.1:18789/v1
export SHAD_EDWIN_GATEWAY_API_KEY=not-needed
export SHAD_ORCHESTRATOR_MODEL=gpt-5.5
export SHAD_WORKER_MODEL=gpt-5.5
export SHAD_LEAF_MODEL=gpt-5.5

run_stage() {
  local id="$1"
  local output="$2"
  local prompt_file="$RUN_ROOT/prompts/${id}.md"
  local log_file="$RUN_ROOT/logs/${id}.log"
  shift 2
  cat > "$prompt_file"
  echo "[$(date -Is)] START $id" | tee -a "$RUN_ROOT/pipeline.log"
  if shad run "$(cat "$prompt_file")" \
    --strategy analysis \
    --sources "$BASE/sources-code" \
    --collection sources-code \
    --profile balanced \
    --provider edwin-gateway \
    -O gpt-5.5 -W gpt-5.5 -L gpt-5.5 \
    --max-nodes 45 \
    --max-time 3600 \
    --output "$output" \
    > "$log_file" 2>&1; then
    echo "[$(date -Is)] DONE $id -> $output" | tee -a "$RUN_ROOT/pipeline.log"
  else
    code=$?
    echo "[$(date -Is)] PARTIAL_OR_FAILED $id code=$code -> $output" | tee -a "$RUN_ROOT/pipeline.log"
    # Continue pipeline; later quality gate will mark missing/weak artifacts.
  fi
}

run_stage architecture "$BASE/03-Analysis/architecture.md" <<'PROMPT'
Using the Semantos methodology in 01-Methodology/evidence-rules.md, analyze repository architecture from actual semantos-core source snapshots. Primary evidence: runtime/, core/, packages/, apps/, cartridges/, configs/, db/, scripts/, tools/, package manifests. Docs are secondary only.

Produce a concise but source-grounded artifact with: subsystem map, active vs legacy/experimental caveats, concrete source paths/symbols, and a Mermaid architecture diagram.
PROMPT

run_stage runtime "$BASE/03-Analysis/runtime-concepts.md" <<'PROMPT'
Using the Semantos methodology, analyze runtime concepts and execution/data flow from source. Primary evidence: runtime/, core/cell*, cartridges/, db/, configs/, scripts, tests. Docs are secondary only.

Produce: runtime entrypoints/services, execution/cell/data-flow model as represented in code, concrete paths/symbols, Mermaid data/control-flow diagram, and future-agent cautions.
PROMPT

run_stage protocols_security "$BASE/03-Analysis/protocols-security.md" <<'PROMPT'
Using the Semantos methodology, analyze protocols, identity, security, capabilities, networking, and authorization from source. Primary evidence: implementation files, tests, configs, protocol packages, runtime services. Docs are secondary only.

Produce: protocol/security surfaces present in code, trust/capability/key/network boundaries, concrete paths/symbols/tests/configs, Mermaid trust-boundary/protocol-flow diagram, and unsupported claims to avoid.
PROMPT

run_stage storage_data "$BASE/03-Analysis/storage-data-model.md" <<'PROMPT'
Using the Semantos methodology, analyze storage and data model from source. Primary evidence: db/, core/, runtime/, packages/, schemas/config, tests, migrations/scripts if present. Docs are secondary only.

Produce: storage backends/data structures represented, persistence/event flow, concrete file paths/symbols/configs/tests, Mermaid storage/event diagram, and doc-vs-implementation mismatch risks.
PROMPT

run_stage formal_methods "$BASE/03-Analysis/formal-methods.md" <<'PROMPT'
Using the Semantos methodology, analyze formal methods, proofs, invariants, tests, fuzzing, and verification assets from source. Primary evidence: proofs/, tests/, fuzz assets, package scripts, CI/config. Docs are secondary only.

Produce: Lean/TLA+/fuzz/test inventory, invariant-to-file/test mapping where supportable, what is mechanized/tested vs only documented, traceability table/diagram, and caveats against overclaiming verification.
PROMPT

run_stage developer_workflows "$BASE/03-Analysis/developer-workflows.md" <<'PROMPT'
Using the Semantos methodology, analyze developer workflows from source. Primary evidence: package.json/pnpm/mise/nvm/tsconfig/docker/systemd/scripts/CI/tests. Docs are secondary only.

Produce: build/test/dev/deploy commands supported by manifests/scripts, workspace/package structure, local/deployment workflow notes, concrete paths/commands, and future-agent pitfalls.
PROMPT

run_stage pitfalls "$BASE/03-Analysis/pitfalls-checklists.md" <<'PROMPT'
Using the Semantos methodology and prior focused artifacts if available, build operational and implementation pitfalls/checklists from source evidence. Primary evidence: code, tests, configs, scripts, proofs. Docs are secondary only.

Produce: checklists for runtime/core/protocol/storage/proof-sensitive changes, likely footguns from code layout/config/scripts/tests, caveats, and a short future-agent checklist.
PROMPT

run_stage routing "$BASE/03-Analysis/routing-hints.md" <<'PROMPT'
Using Semantos focused artifacts and methodology, create routing hints for future agents.

Produce: useWhen/avoidWhen guidance, which artifact to consult for which task, when to fall back to raw sources-code, when docs are acceptable vs when code/proofs/tests/config are required, and concise YAML snippets for discipline.yaml.
PROMPT

run_stage verification "$BASE/01-Methodology/quality-gate.md" <<'PROMPT'
Verify the Semantos discipline artifacts on disk. Check required files under 01-Methodology, 02-Source-Map, and 03-Analysis. Evaluate whether claims are source-grounded in code/proofs/tests/config/runtime, not docs-dominant.

Output PASS/PARTIAL/FAIL with explicit missing/weak artifacts and remediation. Do not claim files exist unless they actually exist.
PROMPT

run_stage final_synthesis "$BASE/00-Final-Reports/semantos-discipline-report.md" <<'PROMPT'
Synthesize the final Semantos discipline report from the methodology and focused analysis artifacts. Use raw sources-code only to clarify evidence. Do not make unsupported new claims.

Output: executive summary, architecture/runtime/security/storage/formal/developer/pitfall synthesis, source authority caveats, future-agent operating guidance, and references to artifact files/key source paths.
PROMPT

python3 - <<'PY'
import json, hashlib
from pathlib import Path
base=Path('/home/jake/.edwinpai/disciplines/semantos')
paths=[]
for root in ['00-Final-Reports','01-Methodology','02-Source-Map','03-Analysis','04-Data','05-Scripts','06-Visualizations','07-Out-Reports']:
    for p in (base/root).rglob('*'):
        if p.is_file():
            data=p.read_bytes()
            paths.append({'path':str(p.relative_to(base)),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
(base/'04-Data/artifact-manifest.json').write_text(json.dumps({'discipline':'semantos','artifacts':paths},indent=2))
PY

echo "[$(date -Is)] COMPLETE $RUN_ROOT" | tee -a "$RUN_ROOT/pipeline.log"
