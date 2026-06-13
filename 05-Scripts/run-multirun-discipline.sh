#!/usr/bin/env bash
set -euo pipefail

BASE="/home/jake/.edwinpai/disciplines/semantos"
RUN_ROOT="$BASE/07-Out-Reports/multirun-$(date +%Y%m%d-%H%M%S)"
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
  shad run "$(cat "$prompt_file")" \
    --strategy analysis \
    --sources "$BASE/sources-code" \
    --collection sources-code \
    --profile deep \
    --provider edwin-gateway \
    -O gpt-5.5 -W gpt-5.5 -L gpt-5.5 \
    --max-nodes 90 \
    --max-time 5400 \
    --output "$output" \
    > "$log_file" 2>&1
  echo "[$(date -Is)] DONE $id -> $output" | tee -a "$RUN_ROOT/pipeline.log"
}

# Methodology first: source authority and exact questions for the rest of the build.
run_stage methodology "$BASE/01-Methodology/evidence-rules.md" <<'PROMPT'
Build the Semantos discipline methodology from the semantos-core source snapshots.

Output must define:
1. source authority rules for this discipline;
2. what code/proof/test/config/runtime evidence must be preferred over docs/plans;
3. major analysis questions for subsequent focused runs;
4. verification checks that should reject docs-dominant or unsupported claims;
5. citation requirements using concrete paths/symbols/files.

Use actual source paths from the corpus. Do not write final architecture conclusions here; write the methodology and analysis plan.
PROMPT

run_stage architecture "$BASE/03-Analysis/architecture.md" <<'PROMPT'
Analyze Semantos repository architecture from actual semantos-core source snapshots.

Primary evidence: runtime/, core/, packages/, apps/, cartridges/, configs/, db/, scripts/, tools/, package manifests. Docs are secondary only.

Output requirements:
- major repo subsystems and their responsibilities;
- concrete source paths and symbols/modules for each subsystem;
- Mermaid architecture diagram;
- what appears active vs legacy/experimental based on source layout and manifests;
- uncertainties/caveats.
PROMPT

run_stage runtime "$BASE/03-Analysis/runtime-concepts.md" <<'PROMPT'
Analyze Semantos runtime concepts and execution/data flow from source.

Primary evidence: runtime/, core/cell*, cartridges/, db/, configs/, scripts, tests. Docs are secondary only.

Output requirements:
- runtime entrypoints and services;
- cell/execution model as implemented or represented in code;
- data/control flow diagram in Mermaid;
- concrete file paths and symbols;
- what future agents need to know before changing runtime behavior.
PROMPT

run_stage protocols_security "$BASE/03-Analysis/protocols-security.md" <<'PROMPT'
Analyze Semantos protocols, identity, security, capabilities, networking, and authorization from source.

Primary evidence: code, tests, configs, protocol packages, cartridges, runtime services. Docs are secondary only.

Output requirements:
- protocol/security surfaces actually present in code;
- auth/capability/key/certificate/network boundaries;
- Mermaid trust-boundary or protocol-flow diagram;
- concrete paths/symbols/tests/configs;
- risks, caveats, and unsupported claims to avoid.
PROMPT

run_stage storage_data "$BASE/03-Analysis/storage-data-model.md" <<'PROMPT'
Analyze Semantos storage and data model from actual source.

Primary evidence: db/, core/, runtime/, packages/, schemas/config, tests, migrations/scripts if present. Docs are secondary only.

Output requirements:
- storage backends and data structures actually represented;
- data model / persistence flow;
- Mermaid storage/event flow diagram;
- concrete file paths/symbols/configs/tests;
- mismatch risks between docs/plans and implementation.
PROMPT

run_stage formal_methods "$BASE/03-Analysis/formal-methods.md" <<'PROMPT'
Analyze Semantos formal methods, proofs, invariants, tests, fuzzing, and verification assets from source.

Primary evidence: proofs/, tests/, fuzz assets, package scripts, CI/config. Docs are secondary only.

Output requirements:
- inventory of Lean/TLA+/fuzz/test assets;
- invariant-to-file/test mapping where supportable;
- what is actually mechanized/tested vs only documented;
- Mermaid traceability diagram/table;
- caveats against overclaiming verification.
PROMPT

run_stage developer_workflows "$BASE/03-Analysis/developer-workflows.md" <<'PROMPT'
Analyze Semantos developer workflows from source.

Primary evidence: package.json/pnpm/mise/nvm/tsconfig/docker/systemd/scripts/CI/tests. Docs are secondary only.

Output requirements:
- build/test/dev/deploy commands that appear supported by manifests/scripts;
- workspace/package structure;
- local and deployment workflow notes;
- concrete paths/commands;
- pitfalls for future agents.
PROMPT

run_stage pitfalls "$BASE/03-Analysis/pitfalls-checklists.md" <<'PROMPT'
Build Semantos operational and implementation pitfalls/checklists from source evidence.

Primary evidence: code, tests, configs, scripts, proofs. Docs are secondary only.

Output requirements:
- checklist for changing runtime/core/protocol/storage/proof-sensitive behavior;
- likely footguns found from code layout/config/scripts/tests;
- source-grounded caveats and uncertainties;
- short future-agent checklist.
PROMPT

run_stage routing "$BASE/03-Analysis/routing-hints.md" <<'PROMPT'
Create Semantos discipline routing hints for future agents.

Use the completed source-grounded analyses and the source corpus. Output:
- useWhen and avoidWhen guidance;
- which artifact to consult for which task;
- when to fall back to raw sources-code collection;
- when docs are acceptable vs when code/proofs/tests/config are required;
- concise YAML snippets suitable for discipline.yaml.
PROMPT

run_stage verification "$BASE/01-Methodology/quality-gate.md" <<'PROMPT'
Verify the Semantos discipline artifacts produced so far.

Inputs to consider: 01-Methodology/evidence-rules.md and 03-Analysis/*.md plus raw sources-code. Check:
- required artifacts exist and are nontrivial;
- claims are source-grounded in code/proofs/tests/config/runtime, not docs-dominant;
- diagrams/tables are present where useful;
- unsupported claims are caveated;
- major topics are covered.

Output a PASS/PARTIAL/FAIL verdict with explicit missing items and remediation. Do not claim files exist unless they actually exist in the artifact paths.
PROMPT

run_stage final_synthesis "$BASE/00-Final-Reports/semantos-discipline-report.md" <<'PROMPT'
Synthesize the final Semantos discipline report from the verified multi-run artifacts.

Use artifacts from 01-Methodology and 03-Analysis as inputs, and raw sources-code only to clarify evidence. Do not make new unsupported claims.

Output:
- executive summary;
- architecture/runtime/security/storage/formal/developer/pitfall synthesis;
- key diagrams or links to diagrams in prior artifacts;
- source authority caveats;
- future-agent operating guidance;
- references to artifact files and key source paths.
PROMPT

# Deterministic manifest after all stages.
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
