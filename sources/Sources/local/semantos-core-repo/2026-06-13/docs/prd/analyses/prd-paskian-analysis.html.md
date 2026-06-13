---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/analyses/prd-paskian-analysis.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.765350+00:00
---

# docs/prd/analyses/prd-paskian-analysis.html

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Semantos PRD Corpus Analysis — Paskian Topology</title>
<style>
:root {
  --bg: #0a0e17;
  --bg2: #111827;
  --bg3: #1f2937;
  --text: #e5e7eb;
  --text2: #9ca3af;
  --accent: #60a5fa;
  --green: #34d399;
  --amber: #fbbf24;
  --red: #f87171;
  --purple: #a78bfa;
  --cyan: #22d3ee;
  --pink: #f472b6;

  --forth: #34d399;
  --lisp: #60a5fa;
  --cli: #fbbf24;
  --conv: #f87171;
  --relevant-c: #34d399;
  --active-c: #60a5fa;
  --affine-c: #fbbf24;
  --oscillating-c: #f87171;
  --linear-c: #9ca3af;
}

* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;
  background: var(--bg);
  color: var(--text);
  overflow-x: hidden;
}

.header {
  padding: 32px 40px 24px;
  border-bottom: 1px solid var(--bg3);
  background: linear-gradient(135deg, var(--bg) 0%, #0f172a 100%);
}
.header h1 {
  font-size: 24px;
  font-weight: 600;
  letter-spacing: -0.5px;
  margin-bottom: 8px;
}
.header .subtitle {
  color: var(--text2);
  font-size: 13px;
  line-height: 1.6;
}
.stats-row {
  display: flex;
  gap: 24px;
  margin-top: 16px;
  flex-wrap: wrap;
}
.stat {
  background: var(--bg2);
  border: 1px solid var(--bg3);
  border-radius: 8px;
  padding: 12px 16px;
  min-width: 120px;
}
.stat .val { font-size: 20px; font-weight: 700; color: var(--accent); }
.stat .label { font-size: 11px; color: var(--text2); margin-top: 2px; }

nav {
  display: flex;
  gap: 4px;
  padding: 12px 40px;
  background: var(--bg2);
  border-bottom: 1px solid var(--bg3);
  overflow-x: auto;
}
nav button {
  background: transparent;
  border: 1px solid transparent;
  color: var(--text2);
  padding: 8px 16px;
  border-radius: 6px;
  cursor: pointer;
  font-family: inherit;
  font-size: 12px;
  white-space: nowrap;
  transition: all 0.15s;
}
nav button:hover { color: var(--text); background: var(--bg3); }
nav button.active {
  color: var(--accent);
  background: rgba(96, 165, 250, 0.1);
  border-color: rgba(96, 165, 250, 0.3);
}

.content { padding: 24px 40px 60px; }

.panel { display: none; }
.panel.active { display: block; }

.section-title {
  font-size: 16px;
  font-weight: 600;
  margin: 24px 0 12px;
  color: var(--text);
}
.section-desc {
  font-size: 12px;
  color: var(--text2);
  margin-bottom: 16px;
  line-height: 1.5;
  max-width: 800px;
}

/* Attractor Force Graph (canvas) */
#attractor-canvas {
  width: 100%;
  height: 500px;
  background: var(--bg2);
  border: 1px solid var(--bg3);
  border-radius: 8px;
  margin-bottom: 24px;
}

/* Grid layouts */
.card-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 12px;
  margin-bottom: 24px;
}
.card {
  background: var(--bg2);
  border: 1px solid var(--bg3);
  border-radius: 8px;
  padding: 16px;
  transition: border-color 0.15s;
}
.card:hover { border-color: var(--accent); }
.card .name { font-size: 14px; font-weight: 600; margin-bottom: 4px; }
.card .desc { font-size: 11px; color: var(--text2); margin-bottom: 8px; }
.card .metrics { display: flex; gap: 12px; flex-wrap: wrap; }
.card .metric { font-size: 11px; }
.card .metric .mv { font-weight: 600; }

/* Thread list */
.thread-list { margin-bottom: 24px; }
.thread {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 16px;
  background: var(--bg2);
  border: 1px solid var(--bg3);
  border-radius: 6px;
  margin-bottom: 6px;
  font-size: 13px;
}
.thread .concepts {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 8px;
}
.thread .concept-tag {
  background: rgba(96, 165, 250, 0.15);
  color: var(--accent);
  padding: 2px 8px;
  border-radius: 4px;
  font-size: 12px;
}
.thread .arrow { color: var(--text2); }
.thread .score { font-weight: 600; min-width: 60px; text-align: right; }

/* Lifecycle sparklines */
.sparkline-row {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 12px;
  border-bottom: 1px solid var(--bg3);
  font-size: 12px;
}
.sparkline-row .label { min-width: 160px; }
.sparkline-row .badges { display: flex; gap: 6px; min-width: 180px; }
.sparkline-row canvas { flex: 1; height: 28px; }
.badge {
  display: inline-block;
  padding: 1px 6px;
  border-radius: 3px;
  font-size: 10px;
  font-weight: 600;
}
.badge.RELEVANT { background: rgba(52, 211, 153, 0.2); color: var(--relevant-c); }
.badge.ACTIVE { background: rgba(96, 165, 250, 0.2); color: var(--active-c); }
.badge.AFFINE { background: rgba(251, 191, 36, 0.2); color: var(--affine-c); }
.badge.OSCILLATING { background: rgba(248, 113, 113, 0.2); color: var(--oscillating-c); }
.badge.LINEAR { background: rgba(156, 163, 175, 0.2); color: var(--linear-c); }
.badge.FORTH { background: rgba(52, 211, 153, 0.15); color: var(--forth); border: 1px solid rgba(52, 211, 153, 0.3); }
.badge.LISP { background: rgba(96, 165, 250, 0.15); color: var(--lisp); border: 1px solid rgba(96, 165, 250, 0.3); }
.badge.CLI { background: rgba(251, 191, 36, 0.15); color: var(--cli); border: 1px solid rgba(251, 191, 36, 0.3); }
.badge.CONVERSATION { background: rgba(248, 113, 113, 0.15); color: var(--conv); border: 1px solid rgba(248, 113, 113, 0.3); }

/* Gradient view */
.gradient-container {
  display: flex;
  gap: 16px;
  margin-bottom: 24px;
}
.gradient-col {
  flex: 1;
  min-width: 200px;
}
.gradient-header {
  padding: 10px 14px;
  border-radius: 8px 8px 0 0;
  font-size: 13px;
  font-weight: 700;
  text-align: center;
}
.gradient-header.FORTH { background: rgba(52, 211, 153, 0.2); color: var(--forth); }
.gradient-header.LISP { background: rgba(96, 165, 250, 0.2); color: var(--lisp); }
.gradient-header.CLI { background: rgba(251, 191, 36, 0.2); color: var(--cli); }
.gradient-header.CONVERSATION { background: rgba(248, 113, 113, 0.2); color: var(--conv); }
.gradient-body {
  background: var(--bg2);
  border: 1px solid var(--bg3);
  border-top: none;
  border-radius: 0 0 8px 8px;
  padding: 12px;
  max-height: 400px;
  overflow-y: auto;
}
.gradient-item {
  padding: 4px 0;
  font-size: 12px;
  display: flex;
  justify-content: space-between;
}
.gradient-item .cv { color: var(--text2); font-size: 11px; }

/* Similarity table */
table.sim-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
  margin-bottom: 24px;
}
table.sim-table th {
  text-align: left;
  padding: 8px 12px;
  background: var(--bg3);
  color: var(--text2);
  font-weight: 600;
}
table.sim-table td {
  padding: 8px 12px;
  border-bottom: 1px solid var(--bg3);
}
table.sim-table tr:hover { background: rgba(96, 165, 250, 0.05); }

/* Force graph */
.force-container {
  position: relative;
  width: 100%;
  height: 550px;
  background: var(--bg2);
  border: 1px solid var(--bg3);
  border-radius: 8px;
  overflow: hidden;
  margin-bottom: 24px;
}
.force-container canvas { width: 100%; height: 100%; }
.force-legend {
  position: absolute;
  top: 12px;
  right: 12px;
  background: rgba(10, 14, 23, 0.9);
  padding: 10px 14px;
  border-radius: 6px;
  font-size: 11px;
  line-height: 1.8;
}
.force-legend .dot {
  display: inline-block;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  margin-right: 6px;
}

/* Tooltip */
.tooltip {
  position: fixed;
  background: var(--bg3);
  border: 1px solid var(--accent);
  border-radius: 6px;
  padding: 10px 14px;
  font-size: 12px;
  max-width: 320px;
  pointer-events: none;
  z-index: 1000;
  display: none;
  line-height: 1.5;
}
</style>
</head>
<body>

<div class="header">
  <h1>Semantos PRD Corpus — Paskian Topology Analysis</h1>
  <div class="subtitle">
    Treating 200 PRDs as a Paskian conversation graph. Concepts are nodes, co-occurrence is edge weight,
    stability is convergence. Substructural types (LINEAR/RELEVANT/AFFINE) classify concept lifetimes.
    The compression gradient (Conversation → CLI → Lisp → Forth) maps where each concept has settled.
  </div>
  <div id="stats-row" class="stats-row"></div>
</div>

<nav id="nav"></nav>

<div class="content">
  <div id="panel-topology" class="panel active"></div>
  <div id="panel-attractors" class="panel"></div>
  <div id="panel-threads" class="panel"></div>
  <div id="panel-gradient" class="panel"></div>
  <div id="panel-lifecycles" class="panel"></div>
  <div id="panel-oscillating" class="panel"></div>
  <div id="panel-similarity" class="panel"></div>
</div>

<div class="tooltip" id="tooltip"></div>

<script>
const DATA = {"corpus_stats": {"total_docs": 200, "substantial_docs": 200, "total_lines": 85067, "phase_range": "-5.0 \u2014 105.0", "doc_types": {"prd": 76, "prompt": 76, "errata": 21, "architecture": 12, "refactor": 2, "sweep": 2, "master": 7, "design": 4}}, "attractors": [{"concept": "cell", "description": "256-byte cell primitive", "score": 73.672}, {"concept": "linear", "description": "LINEAR substructural type", "score": 66.899}, {"concept": "identity", "description": "identity system", "score": 64.491}, {"concept": "linearity", "description": "linearity enforcement", "score": 62.022}, {"concept": "node", "description": "sovereign node", "score": 56.191}, {"concept": "semantic object", "description": "semantic object primitive", "score": 55.661}, {"concept": "relevant", "description": "RELEVANT substructural type", "score": 54.731}, {"concept": "extension", "description": "extension system", "score": 53.753}, {"concept": "ffi", "description": "foreign function interface", "score": 53.476}, {"concept": "flow", "description": "conversation flow", "score": 52.951}, {"concept": "patch", "description": "state patch", "score": 52.669}, {"concept": "kernel", "description": "kernel layer", "score": 48.756}, {"concept": "capability", "description": "capability token", "score": 46.848}, {"concept": "affine", "description": "AFFINE substructural type", "score": 40.867}, {"concept": "plexus", "description": "Plexus overlay network", "score": 40.051}, {"concept": "adapter", "description": "adapter interface pattern", "score": 39.97}, {"concept": "wasm", "description": "WebAssembly target", "score": 39.929}, {"concept": "evidence", "description": "evidence chain", "score": 33.079}, {"concept": "governance", "description": "governance system", "score": 31.553}, {"concept": "trades", "description": "trades vertical", "score": 30.949}], "stable_threads": [{"concept_a": "linear", "concept_b": "cell", "edge_weight": 0.976, "combined_stability": 0.999, "combined_span": 40, "paskian_score": 3.629, "description_a": "LINEAR substructural type", "description_b": "256-byte cell primitive"}, {"concept_a": "linear", "concept_b": "linearity", "edge_weight": 1.0, "combined_stability": 1.032, "combined_span": 39, "paskian_score": 3.573, "description_a": "LINEAR substructural type", "description_b": "linearity enforcement"}, {"concept_a": "linearity", "concept_b": "cell", "edge_weight": 0.89, "combined_stability": 1.01, "combined_span": 39, "paskian_score": 3.251, "description_a": "linearity enforcement", "description_b": "256-byte cell primitive"}, {"concept_a": "cell", "concept_b": "identity", "edge_weight": 0.866, "combined_stability": 0.993, "combined_span": 39, "paskian_score": 3.218, "description_a": "256-byte cell primitive", "description_b": "identity system"}, {"concept_a": "cell", "concept_b": "ffi", "edge_weight": 0.803, "combined_stability": 1.003, "combined_span": 37, "paskian_score": 2.913, "description_a": "256-byte cell primitive", "description_b": "foreign function interface"}, {"concept_a": "linear", "concept_b": "identity", "edge_weight": 0.795, "combined_stability": 1.016, "combined_span": 39, "paskian_score": 2.887, "description_a": "LINEAR substructural type", "description_b": "identity system"}, {"concept_a": "cell", "concept_b": "node", "edge_weight": 0.819, "combined_stability": 1.08, "combined_span": 41, "paskian_score": 2.835, "description_a": "256-byte cell primitive", "description_b": "sovereign node"}, {"concept_a": "cell", "concept_b": "kernel", "edge_weight": 0.898, "combined_stability": 1.152, "combined_span": 36, "paskian_score": 2.812, "description_a": "256-byte cell primitive", "description_b": "kernel layer"}, {"concept_a": "linear", "concept_b": "ffi", "edge_weight": 0.78, "combined_stability": 1.026, "combined_span": 37, "paskian_score": 2.764, "description_a": "LINEAR substructural type", "description_b": "foreign function interface"}, {"concept_a": "cell", "concept_b": "extension", "edge_weight": 0.756, "combined_stability": 1.047, "combined_span": 40, "paskian_score": 2.68, "description_a": "256-byte cell primitive", "description_b": "extension system"}, {"concept_a": "relevant", "concept_b": "cell", "edge_weight": 0.661, "combined_stability": 0.908, "combined_span": 36, "paskian_score": 2.63, "description_a": "RELEVANT substructural type", "description_b": "256-byte cell primitive"}, {"concept_a": "linear", "concept_b": "relevant", "edge_weight": 0.677, "combined_stability": 0.931, "combined_span": 36, "paskian_score": 2.626, "description_a": "LINEAR substructural type", "description_b": "RELEVANT substructural type"}, {"concept_a": "cell", "concept_b": "flow", "edge_weight": 0.803, "combined_stability": 1.132, "combined_span": 39, "paskian_score": 2.618, "description_a": "256-byte cell primitive", "description_b": "conversation flow"}, {"concept_a": "cell", "concept_b": "semantic object", "edge_weight": 0.598, "combined_stability": 0.806, "combined_span": 33, "paskian_score": 2.617, "description_a": "256-byte cell primitive", "description_b": "semantic object primitive"}, {"concept_a": "cell", "concept_b": "patch", "edge_weight": 0.764, "combined_stability": 1.042, "combined_span": 34, "paskian_score": 2.605, "description_a": "256-byte cell primitive", "description_b": "state patch"}, {"concept_a": "identity", "concept_b": "flow", "edge_weight": 0.811, "combined_stability": 1.148, "combined_span": 39, "paskian_score": 2.605, "description_a": "identity system", "description_b": "conversation flow"}, {"concept_a": "identity", "concept_b": "node", "edge_weight": 0.772, "combined_stability": 1.096, "combined_span": 39, "paskian_score": 2.596, "description_a": "identity system", "description_b": "sovereign node"}, {"concept_a": "linearity", "concept_b": "identity", "edge_weight": 0.717, "combined_stability": 1.026, "combined_span": 39, "paskian_score": 2.575, "description_a": "linearity enforcement", "description_b": "identity system"}, {"concept_a": "linear", "concept_b": "node", "edge_weight": 0.732, "combined_stability": 1.102, "combined_span": 40, "paskian_score": 2.467, "description_a": "LINEAR substructural type", "description_b": "sovereign node"}, {"concept_a": "relevant", "concept_b": "linearity", "edge_weight": 0.638, "combined_stability": 0.942, "combined_span": 36, "paskian_score": 2.446, "description_a": "RELEVANT substructural type", "description_b": "linearity enforcement"}, {"concept_a": "linearity", "concept_b": "ffi", "edge_weight": 0.693, "combined_stability": 1.036, "combined_span": 37, "paskian_score": 2.432, "description_a": "linearity enforcement", "description_b": "foreign function interface"}, {"concept_a": "linear", "concept_b": "semantic object", "edge_weight": 0.567, "combined_stability": 0.83, "combined_span": 33, "paskian_score": 2.41, "description_a": "LINEAR substructural type", "description_b": "semantic object primitive"}, {"concept_a": "linear", "concept_b": "extension", "edge_weight": 0.685, "combined_stability": 1.07, "combined_span": 40, "paskian_score": 2.376, "description_a": "LINEAR substructural type", "description_b": "extension system"}, {"concept_a": "cell", "concept_b": "wasm", "edge_weight": 0.756, "combined_stability": 1.149, "combined_span": 36, "paskian_score": 2.376, "description_a": "256-byte cell primitive", "description_b": "WebAssembly target"}, {"concept_a": "relevant", "concept_b": "ffi", "edge_weight": 0.614, "combined_stability": 0.935, "combined_span": 36, "paskian_score": 2.372, "description_a": "RELEVANT substructural type", "description_b": "foreign function interface"}, {"concept_a": "linear", "concept_b": "kernel", "edge_weight": 0.772, "combined_stability": 1.176, "combined_span": 36, "paskian_score": 2.37, "description_a": "LINEAR substructural type", "description_b": "kernel layer"}, {"concept_a": "linear", "concept_b": "patch", "edge_weight": 0.709, "combined_stability": 1.066, "combined_span": 34, "paskian_score": 2.365, "description_a": "LINEAR substructural type", "description_b": "state patch"}, {"concept_a": "identity", "concept_b": "ffi", "edge_weight": 0.661, "combined_stability": 1.02, "combined_span": 37, "paskian_score": 2.359, "description_a": "identity system", "description_b": "foreign function interface"}, {"concept_a": "cell", "concept_b": "capability", "edge_weight": 0.827, "combined_stability": 1.287, "combined_span": 38, "paskian_score": 2.353, "description_a": "256-byte cell primitive", "description_b": "capability token"}, {"concept_a": "identity", "concept_b": "patch", "edge_weight": 0.701, "combined_stability": 1.06, "combined_span": 34, "paskian_score": 2.352, "description_a": "identity system", "description_b": "state patch"}], "oscillating": [{"concept": "edge", "description": "graph edge / network edge", "stability_cv": 2.195, "trend": 1.295, "phase_span": 33}, {"concept": "coordinate", "description": "coordinate system", "stability_cv": 1.929, "trend": -0.793, "phase_span": 17}, {"concept": "transfer", "description": "ownership transfer", "stability_cv": 1.773, "trend": -0.239, "phase_span": 20}, {"concept": "recovery", "description": "recovery mechanism", "stability_cv": 1.647, "trend": 0.624, "phase_span": 17}, {"concept": "bca", "description": "Bitcoin-Certified Address", "stability_cv": 1.604, "trend": -0.58, "phase_span": 19}, {"concept": "reputation", "description": "reputation system", "stability_cv": 1.601, "trend": -0.893, "phase_span": 9}, {"concept": "capability", "description": "capability token", "stability_cv": 1.598, "trend": -0.01, "phase_span": 38}, {"concept": "intent", "description": "intent classification", "stability_cv": 1.549, "trend": -0.75, "phase_span": 26}, {"concept": "octave", "description": "octave memory hierarchy", "stability_cv": 1.527, "trend": -0.432, "phase_span": 5}, {"concept": "taxonomy", "description": "type taxonomy", "stability_cv": 1.514, "trend": -0.843, "phase_span": 29}, {"concept": "plexus", "description": "Plexus overlay network", "stability_cv": 1.511, "trend": -0.139, "phase_span": 35}, {"concept": "routing", "description": "network routing", "stability_cv": 1.459, "trend": 0.718, "phase_span": 21}, {"concept": "vertical", "description": "vertical domain (pre-rename)", "stability_cv": 1.446, "trend": -0.879, "phase_span": 12}, {"concept": "stake", "description": "staking mechanism", "stability_cv": 1.437, "trend": 0.667, "phase_span": 16}, {"concept": "adapter", "description": "adapter interface pattern", "stability_cv": 1.386, "trend": 0.364, "phase_span": 26}], "type_summary": {"ACTIVE": {"count": 44, "concepts": ["adapter", "affine", "anchor", "ballot", "bsv", "cell", "compression gradient", "constraint graph", "convergence", "dispute", "docker", "evidence", "extension", "flow runner", "forth", "four adapter", "gip", "governance", "grammar", "identity", "kernel", "linear", "linearity", "lisp", "ltree", "mesh", "multicast", "natural language", "node", "opcodes", "overlay", "paskian", "patch", "pruning", "relevant", "routing", "self-hosting", "semantic object", "spv", "srv6", "stake", "tick", "two-stack", "unrestricted"]}, "AFFINE": {"count": 28, "concepts": ["6lowpan", "anchor adapter", "axiom", "bca", "bootstrap", "cell packing", "certid", "classification", "coordinate", "depin", "facets", "ffi", "flow", "host function", "identity adapter", "intent", "isolation", "metering", "micropayment", "reputation", "semantic shell", "six-axis", "stability", "storage adapter", "taxonomy", "trades", "vertical", "wasm"]}, "RELEVANT": {"count": 4, "concepts": ["2pda", "network adapter", "selective disclosure", "stack machine"]}, "OSCILLATING": {"count": 6, "concepts": ["capability", "edge", "octave", "plexus", "recovery", "transfer"]}}, "gradient": {"CLI": {"count": 60, "concepts": [{"concept": "bootstrap", "description": "node bootstrap", "stability_cv": 0.809, "phase_span": 9}, {"concept": "compression gradient", "description": "compression gradient pipeline", "stability_cv": 0.816, "phase_span": 10}, {"concept": "semantic shell", "description": "semantic shell", "stability_cv": 0.839, "phase_span": 12}, {"concept": "relevant", "description": "RELEVANT substructural type", "stability_cv": 0.84, "phase_span": 36}, {"concept": "cell packing", "description": "cell serialisation", "stability_cv": 0.868, "phase_span": 21}, {"concept": "isolation", "description": "kernel isolation", "stability_cv": 0.891, "phase_span": 13}, {"concept": "natural language", "description": "NL input layer", "stability_cv": 0.923, "phase_span": 12}, {"concept": "axiom", "description": "axiom compilation", "stability_cv": 0.937, "phase_span": 13}, {"concept": "spv", "description": "simplified payment verification", "stability_cv": 0.946, "phase_span": 17}, {"concept": "evidence", "description": "evidence chain", "stability_cv": 0.949, "phase_span": 22}, {"concept": "certid", "description": "certificate identity", "stability_cv": 0.962, "phase_span": 17}, {"concept": "overlay", "description": "overlay network", "stability_cv": 0.975, "phase_span": 20}, {"concept": "cell", "description": "256-byte cell primitive", "stability_cv": 0.976, "phase_span": 45}, {"concept": "forth", "description": "Forth execution layer", "stability_cv": 0.978, "phase_span": 18}, {"concept": "governance", "description": "governance system", "stability_cv": 0.987, "phase_span": 22}, {"concept": "ballot", "description": "ballot mechanism", "stability_cv": 0.996, "phase_span": 14}, {"concept": "identity", "description": "identity system", "stability_cv": 1.01, "phase_span": 39}, {"concept": "linear", "description": "LINEAR substructural type", "stability_cv": 1.022, "phase_span": 40}, {"concept": "ltree", "description": "LTREE path structure", "stability_cv": 1.022, "phase_span": 7}, {"concept": "ffi", "description": "foreign function interface", "stability_cv": 1.03, "phase_span": 37}, {"concept": "linearity", "description": "linearity enforcement", "stability_cv": 1.043, "phase_span": 39}, {"concept": "lisp", "description": "Lisp axiom layer", "stability_cv": 1.049, "phase_span": 18}, {"concept": "affine", "description": "AFFINE substructural type", "stability_cv": 1.055, "phase_span": 32}, {"concept": "dispute", "description": "dispute resolution", "stability_cv": 1.064, "phase_span": 17}, {"concept": "host function", "description": "host function dispatch", "stability_cv": 1.07, "phase_span": 19}, {"concept": "trades", "description": "trades vertical", "stability_cv": 1.074, "phase_span": 27}, {"concept": "classification", "description": "classification system", "stability_cv": 1.079, "phase_span": 23}, {"concept": "tick", "description": "tick payment", "stability_cv": 1.085, "phase_span": 8}, {"concept": "opcodes", "description": "instruction set", "stability_cv": 1.088, "phase_span": 25}, {"concept": "patch", "description": "state patch", "stability_cv": 1.109, "phase_span": 34}, {"concept": "mesh", "description": "mesh network", "stability_cv": 1.113, "phase_span": 10}, {"concept": "extension", "description": "extension system", "stability_cv": 1.119, "phase_span": 40}, {"concept": "docker", "description": "Docker deployment", "stability_cv": 1.13, "phase_span": 10}, {"concept": "facets", "description": "identity facets", "stability_cv": 1.146, "phase_span": 18}, {"concept": "node", "description": "sovereign node", "stability_cv": 1.183, "phase_span": 41}, {"concept": "stability", "description": "stability metric", "stability_cv": 1.188, "phase_span": 6}, {"concept": "bsv", "description": "Bitcoin SV anchoring", "stability_cv": 1.215, "phase_span": 29}, {"concept": "metering", "description": "resource metering", "stability_cv": 1.261, "phase_span": 24}, {"concept": "multicast", "description": "multicast delivery", "stability_cv": 1.274, "phase_span": 11}, {"concept": "grammar", "description": "domain grammar", "stability_cv": 1.281, "phase_span": 15}, {"concept": "srv6", "description": "SRv6 segment routing", "stability_cv": 1.284, "phase_span": 3}, {"concept": "flow", "description": "conversation flow", "stability_cv": 1.287, "phase_span": 39}, {"concept": "wasm", "description": "WebAssembly target", "stability_cv": 1.322, "phase_span": 36}, {"concept": "kernel", "description": "kernel layer", "stability_cv": 1.329, "phase_span": 36}, {"concept": "anchor", "description": "blockchain anchoring", "stability_cv": 1.342, "phase_span": 25}, {"concept": "adapter", "description": "adapter interface pattern", "stability_cv": 1.386, "phase_span": 26}, {"concept": "stake", "description": "staking mechanism", "stability_cv": 1.437, "phase_span": 16}, {"concept": "vertical", "description": "vertical domain (pre-rename)", "stability_cv": 1.446, "phase_span": 12}, {"concept": "routing", "description": "network routing", "stability_cv": 1.459, "phase_span": 21}, {"concept": "plexus", "description": "Plexus overlay network", "stability_cv": 1.511, "phase_span": 35}, {"concept": "taxonomy", "description": "type taxonomy", "stability_cv": 1.514, "phase_span": 29}, {"concept": "octave", "description": "octave memory hierarchy", "stability_cv": 1.527, "phase_span": 5}, {"concept": "intent", "description": "intent classification", "stability_cv": 1.549, "phase_span": 26}, {"concept": "capability", "description": "capability token", "stability_cv": 1.598, "phase_span": 38}, {"concept": "reputation", "description": "reputation system", "stability_cv": 1.601, "phase_span": 9}, {"concept": "bca", "description": "Bitcoin-Certified Address", "stability_cv": 1.604, "phase_span": 19}, {"concept": "recovery", "description": "recovery mechanism", "stability_cv": 1.647, "phase_span": 17}, {"concept": "transfer", "description": "ownership transfer", "stability_cv": 1.773, "phase_span": 20}, {"concept": "coordinate", "description": "coordinate system", "stability_cv": 1.929, "phase_span": 17}, {"concept": "edge", "description": "graph edge / network edge", "stability_cv": 2.195, "phase_span": 33}]}, "LISP": {"count": 9, "concepts": [{"concept": "flow runner", "description": "FlowRunner execution", "stability_cv": 0.165, "phase_span": 3}, {"concept": "two-stack", "description": "dual-stack machine", "stability_cv": 0.291, "phase_span": 2}, {"concept": "six-axis", "description": "six-axis coordinate system", "stability_cv": 0.341, "phase_span": 4}, {"concept": "self-hosting", "description": "self-hosted deployment", "stability_cv": 0.462, "phase_span": 3}, {"concept": "unrestricted", "description": "UNRESTRICTED substructural type", "stability_cv": 0.581, "phase_span": 2}, {"concept": "semantic object", "description": "semantic object primitive", "stability_cv": 0.637, "phase_span": 33}, {"concept": "gip", "description": "identity model", "stability_cv": 0.672, "phase_span": 6}, {"concept": "four adapter", "description": "four-adapter architecture", "stability_cv": 0.717, "phase_span": 8}, {"concept": "micropayment", "description": "micropayment channel", "stability_cv": 0.766, "phase_span": 6}]}, "FORTH": {"count": 3, "concepts": [{"concept": "stack machine", "description": "stack-based execution", "stability_cv": 0.467, "phase_span": 6}, {"concept": "selective disclosure", "description": "privacy mechanism", "stability_cv": 0.484, "phase_span": 5}, {"concept": "2pda", "description": "dual-stack pushdown automaton", "stability_cv": 0.498, "phase_span": 8}]}, "CONVERSATION": {"count": 10, "concepts": [{"concept": "convergence", "description": "learning convergence", "stability_cv": 0.0, "phase_span": 1}, {"concept": "network adapter", "description": "NetworkAdapter boundary", "stability_cv": 0.326, "phase_span": 6}, {"concept": "identity adapter", "description": "IdentityAdapter boundary", "stability_cv": 0.443, "phase_span": 3}, {"concept": "anchor adapter", "description": "AnchorAdapter boundary", "stability_cv": 0.519, "phase_span": 5}, {"concept": "storage adapter", "description": "StorageAdapter boundary", "stability_cv": 0.546, "phase_span": 6}, {"concept": "paskian", "description": "Paskian learning", "stability_cv": 0.637, "phase_span": 7}, {"concept": "pruning", "description": "graph pruning", "stability_cv": 0.686, "phase_span": 3}, {"concept": "constraint graph", "description": "constraint propagation graph", "stability_cv": 0.812, "phase_span": 2}, {"concept": "6lowpan", "description": "6LoWPAN IoT protocol", "stability_cv": 1.207, "phase_span": 6}, {"concept": "depin", "description": "decentralised physical infrastructure", "stability_cv": 1.335, "phase_span": 6}]}}, "unexpected_sims": [{"doc_a": "SEMANTIC-SHELL-ARCHITECTURE.md", "doc_b": "SEMANTIC-SHELL-ARCHITECTURE.md", "similarity": 1.0, "phase_distance": 980.5, "phase_a": 18.5, "phase_b": 999}, {"doc_a": "PLATFORM-ARCHITECTURE.md", "doc_b": "PLATFORM-ARCHITECTURE.md", "similarity": 1.0, "phase_distance": 949, "phase_a": 50, "phase_b": 999}, {"doc_a": "PLEXUS-INTEGRATION-MAP.md", "doc_b": "PLEXUS-SEMANTOS-INTEGRATION.md", "similarity": 0.966, "phase_distance": 985.5, "phase_a": 13.5, "phase_b": 999}, {"doc_a": "IMPLEMENTATION-PLAN-POST-HELM-MERGE.md", "doc_b": "SHELL-ALIGNMENT-VS-ARCHITECTURE-VISION.md", "similarity": 0.663, "phase_distance": 961.5, "phase_a": 37.5, "phase_b": 999}, {"doc_a": "PHASE-15-PLEXUS-REAL-SDK.md", "doc_b": "PLEXUS-SEMANTOS-INTEGRATION.md", "similarity": 0.651, "phase_distance": 984.0, "phase_a": 15.0, "phase_b": 999}, {"doc_a": "PHASE-11-FORMAL-VERIFICATION.md", "doc_b": "PHASE-22-PROMPT.md", "similarity": 0.633, "phase_distance": 11.0, "phase_a": 11.0, "phase_b": 22.0}, {"doc_a": "PHASE-15-PROMPT.md", "doc_b": "PLEXUS-SEMANTOS-INTEGRATION.md", "similarity": 0.594, "phase_distance": 984.0, "phase_a": 15.0, "phase_b": 999}, {"doc_a": "PHASE-12-IMPLEMENTATION-BRIDGE.md", "doc_b": "FORMAL-VERIFICATION-STRATEGY.md", "similarity": 0.593, "phase_distance": 987.0, "phase_a": 12.0, "phase_b": 999}, {"doc_a": "PHASE-0-SCAFFOLDING.md", "doc_b": "SEMANTOS_ZIG_WASM_PRD.md", "similarity": 0.589, "phase_distance": 999.0, "phase_a": 0.0, "phase_b": 999}, {"doc_a": "SHOMEE-EXTRACTION-AUDIT-AND-ROADMAP.md", "doc_b": "PHASE-9-PROMPT.md", "similarity": 0.573, "phase_distance": 13.0, "phase_a": -4, "phase_b": 9.0}, {"doc_a": "PHASE-9-FULL-PROMPT.md", "doc_b": "WORKBENCH-TO-LOOM-RENAME.md", "similarity": 0.573, "phase_distance": 13.0, "phase_a": 9.0, "phase_b": 22}, {"doc_a": "PHASE-1-CELL-PACKING.md", "doc_b": "SEMANTOS_ZIG_WASM_PRD.md", "similarity": 0.564, "phase_distance": 998.0, "phase_a": 1.0, "phase_b": 999}, {"doc_a": "PHASE-11-FORMAL-VERIFICATION.md", "doc_b": "FORMAL-VERIFICATION-STRATEGY.md", "similarity": 0.559, "phase_distance": 988.0, "phase_a": 11.0, "phase_b": 999}, {"doc_a": "PHASE-14-PLEXUS-ADAPTER.md", "doc_b": "PLEXUS-SEMANTOS-INTEGRATION.md", "similarity": 0.558, "phase_distance": 985.0, "phase_a": 14.0, "phase_b": 999}, {"doc_a": "PHASE-26D-PROMPT.md", "doc_b": "PHASE-37-PROMPT.md", "similarity": 0.548, "phase_distance": 11.0, "phase_a": 26.04, "phase_b": 37.0}, {"doc_a": "SHOMEE-EXTRACTION-AUDIT-AND-ROADMAP.md", "doc_b": "PHASE-9.5-PROMPT.md", "similarity": 0.543, "phase_distance": 13.5, "phase_a": -4, "phase_b": 9.5}, {"doc_a": "PHASE-21-LISP-AXIOM-COMPILER.md", "doc_b": "SEMANTIC-SHELL-ARCHITECTURE.md", "similarity": 0.543, "phase_distance": 978.0, "phase_a": 21.0, "phase_b": 999}, {"doc_a": "PHASE-14-PLEXUS-ADAPTER.md", "doc_b": "PHASE-26B-PROMPT.md", "similarity": 0.535, "phase_distance": 12.0, "phase_a": 14.0, "phase_b": 26.02}, {"doc_a": "PHASE-4-PROMPT.md", "doc_b": "SEMANTOS_ZIG_WASM_PRD.md", "similarity": 0.526, "phase_distance": 995.0, "phase_a": 4.0, "phase_b": 999}, {"doc_a": "PHASE-H5-SWARM-DASHBOARD.md", "doc_b": "EXECUTION-ORDER.md", "similarity": 0.524, "phase_distance": 894, "phase_a": 105, "phase_b": 999}], "divergences": [{"filename": "README.md", "actual_refs": 98, "declared_deps": 0, "ratio": 98.0, "actual_ref_list": ["COMMERCIAL-CONTEXT.md", "SHOMEE-EXTRACTION-AUDIT-AND-ROADMAP.md", "PHASE-0-PROMPT.md", "PHASE-0-SCAFFOLDING.md", "PHASE-1-CELL-PACKING.md", "PHASE-1-PROMPT.md", "PHASE-2-BCA-DERIVATION.md", "PHASE-2-PROMPT.md", "PHASE-3-2PDA-CORE.md", "PHASE-3-ERRATA-FIX-PROMPT.md"], "declared_dep_list": []}, {"filename": "PHASE-R0-REPO-HYGIENE.md", "actual_refs": 12, "declared_deps": 0, "ratio": 12.0, "actual_ref_list": ["README.md", "PHASE-11-FORMAL-VERIFICATION.md", "PHASE-11-FULL-PROMPT.md", "PHASE-11.5-FULL-PROMPT.md", "PHASE-11.5-TLA-PROTOCOL.md", "PHASE-12-FULL-PROMPT.md", "PHASE-12-IMPLEMENTATION-BRIDGE.md", "SHOMEE-TO-SEMANTOS-MAPPING.md", "BRANCHING-AND-CI-POLICY.md", "FORMAL-VERIFICATION-STRATEGY.md"], "declared_dep_list": []}, {"filename": "PLEXUS-INTEGRATION-MAP.md", "actual_refs": 11, "declared_deps": 0, "ratio": 11.0, "actual_ref_list": ["PHASE-14-PLEXUS-ADAPTER.md", "PHASE-14-PROMPT.md", "PHASE-15-PLEXUS-REAL-SDK.md", "PHASE-15-PROMPT.md", "PHASE-16-PLEXUS-EDGES.md", "PHASE-16-PROMPT.md", "PHASE-17-PLEXUS-TRANSFER.md", "PHASE-17-PROMPT.md", "PHASE-18-METERING-CONTROL-PLANE.md", "PHASE-18-PROMPT.md"], "declared_dep_list": []}, {"filename": "PHASE-26E-PROMPT.md", "actual_refs": 9, "declared_deps": 0, "ratio": 9.0, "actual_ref_list": ["PHASE-26-KERNEL-ISOLATION-MASTER.md", "PHASE-26A-IDENTITY-EXTRACTION.md", "PHASE-26B-LOCAL-IDENTITY.md", "PHASE-26C-ANCHOR-ADAPTER.md", "PHASE-26D-NETWORK-ADAPTER.md", "PHASE-26E-NODE-BOOTSTRAP.md", "PLATFORM-ARCHITECTURE.md", "BRANCHING-AND-CI-POLICY.md", "PLATFORM-ARCHITECTURE.md"], "declared_dep_list": []}, {"filename": "PHASE-25.5-SWEEP-PROMPT.md", "actual_refs": 8, "declared_deps": 0, "ratio": 8.0, "actual_ref_list": ["PHASE-26-GAME-ENGINE-SDK.md", "PHASE-26-PROMPT.md", "PHASE-27-PROMPT.md", "PHASE-27-SIMPLE-GAMES.md", "PHASE-28-ISDA-CDM.md", "PHASE-28-PROMPT.md", "PHASE-29-PROMPT.md", "PHASE-29-SCADA.md"], "declared_dep_list": []}, {"filename": "PHASE-26H-EXTENSION-RENAME.md", "actual_refs": 8, "declared_deps": 1, "ratio": 8.0, "actual_ref_list": ["README.md", "PHASE-26-KERNEL-ISOLATION-MASTER.md", "PHASE-26F-PROMPT.md", "PHASE-26F-VERTICAL-LOADING.md", "PHASE-26G-NODE-PACKAGING.md", "PLATFORM-ARCHITECTURE.md", "BRANCHING-AND-CI-POLICY.md", "PLATFORM-ARCHITECTURE.md"], "declared_dep_list": ["26F"]}, {"filename": "PHASE-36F-PROMPT.md", "actual_refs": 8, "declared_deps": 0, "ratio": 8.0, "actual_ref_list": ["PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md", "PHASE-36A-EXTENSION-GRAMMAR-SCHEMA.md", "PHASE-36B-SEMANTIC-EXTRACTION-PIPELINE.md", "PHASE-36D-EXTENSION-GOVERNANCE-MODEL.md", "PHASE-36F-CONNECTOR-REFERENCE-IMPL.md", "PLATFORM-ARCHITECTURE.md", "SHOMEE-TO-SEMANTOS-MAPPING.md", "PLATFORM-ARCHITECTURE.md"], "declared_dep_list": []}, {"filename": "PHASE-38-VOICE-TO-EXECUTION.md", "actual_refs": 8, "declared_deps": 0, "ratio": 8.0, "actual_ref_list": ["PHASE-38A-PROMPT.md", "PHASE-38B-PROMPT.md", "PHASE-38C-PROMPT.md", "PHASE-38D-PROMPT.md", "PHASE-38E-PROMPT.md", "PHASE-38F-PROMPT.md", "PHASE-38G-PROMPT.md", "BRANCHING-AND-CI-POLICY.md"], "declared_dep_list": []}, {"filename": "PHASE-19.5-PROMPT.md", "actual_refs": 7, "declared_deps": 0, "ratio": 7.0, "actual_ref_list": ["PLEXUS-INTEGRATION-MAP.md", "SEMANTIC-SHELL-ARCHITECTURE.md", "PHASE-19-SEMANTIC-SHELL.md", "PHASE-19.5-ERRATA.md", "PHASE-19.5-SHELL-PLEXUS-AUTH.md", "SEMANTIC-SHELL-ARCHITECTURE.md", "BRANCHING-AND-CI-POLICY.md"], "declared_dep_list": []}, {"filename": "PHASE-26G-PROMPT.md", "actual_refs": 7, "declared_deps": 0, "ratio": 7.0, "actual_ref_list": ["PHASE-26-KERNEL-ISOLATION-MASTER.md", "PHASE-26E-NODE-BOOTSTRAP.md", "PHASE-26F-VERTICAL-LOADING.md", "PHASE-26G-NODE-PACKAGING.md", "PLATFORM-ARCHITECTURE.md", "BRANCHING-AND-CI-POLICY.md", "PLATFORM-ARCHITECTURE.md"], "declared_dep_list": []}, {"filename": "PHASE-26H-PROMPT.md", "actual_refs": 7, "declared_deps": 0, "ratio": 7.0, "actual_ref_list": ["README.md", "PHASE-26-KERNEL-ISOLATION-MASTER.md", "PHASE-26F-VERTICAL-LOADING.md", "PHASE-26H-EXTENSION-RENAME.md", "PLATFORM-ARCHITECTURE.md", "BRANCHING-AND-CI-POLICY.md", "PLATFORM-ARCHITECTURE.md"], "declared_dep_list": []}, {"filename": "PHASE-36C-PROMPT.md", "actual_refs": 7, "declared_deps": 0, "ratio": 7.0, "actual_ref_list": ["README.md", "PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md", "PHASE-36A-EXTENSION-GRAMMAR-SCHEMA.md", "PHASE-36B-SEMANTIC-EXTRACTION-PIPELINE.md", "PHASE-36C-ERRATA.md", "PHASE-36C-SCHEMA-INFERENCE-AGENT.md", "TAXONOMY-SEED-DESIGN.md"], "declared_dep_list": []}, {"filename": "PHASE-26D-PROMPT.md", "actual_refs": 6, "declared_deps": 0, "ratio": 6.0, "actual_ref_list": ["PHASE-26-KERNEL-ISOLATION-MASTER.md", "PHASE-26D-ERRATA.md", "PHASE-26D-NETWORK-ADAPTER.md", "PLATFORM-ARCHITECTURE.md", "BRANCHING-AND-CI-POLICY.md", "PLATFORM-ARCHITECTURE.md"], "declared_dep_list": []}, {"filename": "PHASE-30J-PROMPT.md", "actual_refs": 6, "declared_deps": 0, "ratio": 6.0, "actual_ref_list": ["PHASE-26E-NODE-BOOTSTRAP.md", "PHASE-26G-NODE-PACKAGING.md", "PHASE-30-FFI-MASTER.md", "PHASE-30J-DOCKER-MULTIARCH.md", "PHASE-30D-ANCHOR-FFI.md", "BRANCHING-AND-CI-POLICY.md"], "declared_dep_list": []}, {"filename": "PHASE-30A-PATCH-TX-CHAIN.md", "actual_refs": 6, "declared_deps": 1, "ratio": 6.0, "actual_ref_list": ["PHASE-30-FFI-MASTER.md", "PHASE-30A-C-ABI-HEADER.md", "PHASE-30B-ADAPTER-CALLBACKS.md", "PHASE-30C-CAPABILITY-FFI.md", "PHASE-30D-ANCHOR-FFI.md", "BRANCHING-AND-CI-POLICY.md"], "declared_dep_list": ["30A"]}], "lifecycles": {"linear": {"d": "LINEAR substructural type", "b": -5, "l": 999, "m": 2062, "s": 40, "t": -0.075, "cv": 1.022, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -5, "n": 14, "d": 7.42}, {"p": -4, "n": 46, "d": 6.93}, {"p": -3, "n": 4, "d": 2.23}, {"p": -1, "n": 1, "d": 0.64}, {"p": 0, "n": 18, "d": 5.29}, {"p": 1, "n": 10, "d": 3.31}, {"p": 2, "n": 4, "d": 2.53}, {"p": 3, "n": 9, "d": 1.46}, {"p": 4, "n": 217, "d": 38.62}, {"p": 5, "n": 16, "d": 2.37}, {"p": 6, "n": 74, "d": 10.03}, {"p": 7, "n": 18, "d": 2.85}, {"p": 8, "n": 9, "d": 2.07}, {"p": 9, "n": 10, "d": 1.45}, {"p": 10, "n": 39, "d": 9.74}, {"p": 11, "n": 78, "d": 16.28}, {"p": 12, "n": 89, "d": 10.64}, {"p": 13, "n": 11, "d": 2.73}, {"p": 14, "n": 8, "d": 1.11}, {"p": 17, "n": 18, "d": 4.42}, {"p": 18, "n": 54, "d": 6.21}, {"p": 20, "n": 13, "d": 3.28}, {"p": 21, "n": 34, "d": 7.91}, {"p": 22, "n": 9, "d": 3.26}, {"p": 26, "n": 110, "d": 3.22}, {"p": 27, "n": 52, "d": 8.19}, {"p": 28, "n": 44, "d": 7.11}, {"p": 29, "n": 65, "d": 7.52}, {"p": 30, "n": 221, "d": 6.97}, {"p": 32, "n": 53, "d": 10.34}, {"p": 33, "n": 70, "d": 12.94}, {"p": 34, "n": 46, "d": 4.0}, {"p": 35, "n": 59, "d": 13.25}, {"p": 36, "n": 74, "d": 2.2}, {"p": 37, "n": 1, "d": 0.38}, {"p": 38, "n": 25, "d": 4.6}, {"p": 50, "n": 3, "d": 1.01}, {"p": 102, "n": 33, "d": 6.68}, {"p": 103, "n": 15, "d": 3.5}, {"p": 999, "n": 388, "d": 5.91}]}, "relevant": {"d": "RELEVANT substructural type", "b": -5, "l": 999, "m": 660, "s": 36, "t": -0.089, "cv": 0.84, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -5, "n": 2, "d": 1.06}, {"p": -4, "n": 25, "d": 3.76}, {"p": -3, "n": 1, "d": 0.56}, {"p": 0, "n": 4, "d": 2.11}, {"p": 1, "n": 4, "d": 2.37}, {"p": 3, "n": 1, "d": 0.2}, {"p": 4, "n": 41, "d": 7.35}, {"p": 6, "n": 15, "d": 3.89}, {"p": 7, "n": 1, "d": 0.55}, {"p": 8, "n": 17, "d": 3.79}, {"p": 9, "n": 1, "d": 0.41}, {"p": 10, "n": 16, "d": 9.84}, {"p": 11, "n": 2, "d": 1.04}, {"p": 12, "n": 8, "d": 1.29}, {"p": 13, "n": 3, "d": 0.74}, {"p": 14, "n": 6, "d": 1.49}, {"p": 17, "n": 7, "d": 1.86}, {"p": 18, "n": 23, "d": 3.08}, {"p": 20, "n": 5, "d": 1.27}, {"p": 21, "n": 4, "d": 0.94}, {"p": 26, "n": 49, "d": 2.99}, {"p": 28, "n": 16, "d": 2.56}, {"p": 29, "n": 16, "d": 2.14}, {"p": 30, "n": 17, "d": 0.9}, {"p": 31, "n": 1, "d": 0.47}, {"p": 32, "n": 13, "d": 2.54}, {"p": 33, "n": 25, "d": 5.42}, {"p": 34, "n": 29, "d": 2.57}, {"p": 35, "n": 22, "d": 4.94}, {"p": 36, "n": 79, "d": 2.83}, {"p": 38, "n": 1, "d": 0.45}, {"p": 50, "n": 17, "d": 5.71}, {"p": 102, "n": 12, "d": 2.43}, {"p": 103, "n": 3, "d": 0.7}, {"p": 104, "n": 9, "d": 1.68}, {"p": 999, "n": 165, "d": 2.95}]}, "affine": {"d": "AFFINE substructural type", "b": -5, "l": 999, "m": 454, "s": 32, "t": -0.454, "cv": 1.055, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -5, "n": 1, "d": 0.53}, {"p": -4, "n": 19, "d": 2.86}, {"p": 0, "n": 4, "d": 2.11}, {"p": 1, "n": 4, "d": 2.37}, {"p": 4, "n": 43, "d": 7.65}, {"p": 6, "n": 4, "d": 0.96}, {"p": 7, "n": 4, "d": 1.01}, {"p": 8, "n": 8, "d": 1.79}, {"p": 9, "n": 3, "d": 1.22}, {"p": 10, "n": 18, "d": 11.07}, {"p": 11, "n": 2, "d": 1.04}, {"p": 12, "n": 4, "d": 0.82}, {"p": 13, "n": 3, "d": 0.74}, {"p": 18, "n": 11, "d": 3.97}, {"p": 20, "n": 6, "d": 1.53}, {"p": 21, "n": 5, "d": 1.16}, {"p": 26, "n": 17, "d": 1.45}, {"p": 27, "n": 9, "d": 1.41}, {"p": 28, "n": 7, "d": 1.12}, {"p": 29, "n": 13, "d": 1.51}, {"p": 30, "n": 12, "d": 0.84}, {"p": 31, "n": 1, "d": 0.47}, {"p": 32, "n": 8, "d": 1.56}, {"p": 33, "n": 3, "d": 0.55}, {"p": 34, "n": 6, "d": 0.76}, {"p": 35, "n": 8, "d": 1.8}, {"p": 36, "n": 85, "d": 2.88}, {"p": 38, "n": 1, "d": 1.04}, {"p": 50, "n": 12, "d": 4.03}, {"p": 102, "n": 6, "d": 1.21}, {"p": 103, "n": 3, "d": 0.7}, {"p": 999, "n": 124, "d": 2.7}]}, "unrestricted": {"d": "UNRESTRICTED substructural type", "b": 4, "l": 999, "m": 2, "s": 2, "t": 0, "cv": 0.581, "tb": "ACTIVE", "gp": "LISP", "tl": [{"p": 4, "n": 1, "d": 0.41}, {"p": 999, "n": 1, "d": 0.11}]}, "linearity": {"d": "linearity enforcement", "b": -5, "l": 999, "m": 1104, "s": 39, "t": -0.154, "cv": 1.043, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -5, "n": 6, "d": 3.18}, {"p": -4, "n": 33, "d": 4.97}, {"p": -3, "n": 2, "d": 1.12}, {"p": -1, "n": 1, "d": 0.64}, {"p": 0, "n": 12, "d": 3.71}, {"p": 1, "n": 5, "d": 1.83}, {"p": 2, "n": 2, "d": 1.27}, {"p": 3, "n": 6, "d": 0.88}, {"p": 4, "n": 121, "d": 21.98}, {"p": 5, "n": 7, "d": 0.95}, {"p": 6, "n": 45, "d": 6.22}, {"p": 7, "n": 8, "d": 1.84}, {"p": 8, "n": 7, "d": 1.62}, {"p": 9, "n": 8, "d": 1.18}, {"p": 10, "n": 29, "d": 6.7}, {"p": 11, "n": 58, "d": 12.14}, {"p": 12, "n": 58, "d": 6.68}, {"p": 13, "n": 7, "d": 1.74}, {"p": 14, "n": 4, "d": 0.61}, {"p": 17, "n": 2, "d": 0.84}, {"p": 18, "n": 28, "d": 3.03}, {"p": 20, "n": 11, "d": 2.78}, {"p": 21, "n": 23, "d": 5.34}, {"p": 22, "n": 8, "d": 2.9}, {"p": 26, "n": 67, "d": 2.08}, {"p": 27, "n": 22, "d": 3.47}, {"p": 28, "n": 20, "d": 3.23}, {"p": 29, "n": 18, "d": 1.94}, {"p": 30, "n": 76, "d": 3.85}, {"p": 32, "n": 22, "d": 4.29}, {"p": 33, "n": 41, "d": 7.28}, {"p": 34, "n": 22, "d": 1.87}, {"p": 35, "n": 30, "d": 6.74}, {"p": 36, "n": 60, "d": 1.82}, {"p": 37, "n": 1, "d": 0.38}, {"p": 38, "n": 14, "d": 2.66}, {"p": 102, "n": 12, "d": 2.43}, {"p": 103, "n": 12, "d": 2.8}, {"p": 999, "n": 196, "d": 3.16}]}, "cell": {"d": "256-byte cell primitive", "b": -5, "l": 999, "m": 4286, "s": 45, "t": -0.442, "cv": 0.976, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -5, "n": 21, "d": 11.13}, {"p": -4, "n": 28, "d": 4.22}, {"p": -3, "n": 9, "d": 5.02}, {"p": -1, "n": 116, "d": 27.24}, {"p": 0, "n": 38, "d": 12.72}, {"p": 1, "n": 134, "d": 44.72}, {"p": 2, "n": 37, "d": 11.56}, {"p": 3, "n": 68, "d": 8.25}, {"p": 4, "n": 156, "d": 27.4}, {"p": 5, "n": 69, "d": 10.8}, {"p": 6, "n": 401, "d": 40.97}, {"p": 7, "n": 246, "d": 39.4}, {"p": 8, "n": 12, "d": 2.78}, {"p": 9, "n": 17, "d": 2.72}, {"p": 10, "n": 13, "d": 3.11}, {"p": 11, "n": 77, "d": 15.67}, {"p": 12, "n": 55, "d": 8.41}, {"p": 13, "n": 1, "d": 0.49}, {"p": 14, "n": 15, "d": 2.22}, {"p": 18, "n": 30, "d": 5.38}, {"p": 19, "n": 18, "d": 3.81}, {"p": 20, "n": 12, "d": 3.04}, {"p": 21, "n": 81, "d": 18.87}, {"p": 22, "n": 4, "d": 1.45}, {"p": 23, "n": 1, "d": 0.33}, {"p": 26, "n": 432, "d": 9.62}, {"p": 27, "n": 174, "d": 27.34}, {"p": 28, "n": 158, "d": 25.41}, {"p": 29, "n": 219, "d": 24.29}, {"p": 30, "n": 443, "d": 8.21}, {"p": 31, "n": 17, "d": 4.4}, {"p": 32, "n": 81, "d": 15.8}, {"p": 33, "n": 78, "d": 15.94}, {"p": 34, "n": 162, "d": 14.07}, {"p": 35, "n": 22, "d": 4.94}, {"p": 36, "n": 53, "d": 1.57}, {"p": 37, "n": 3, "d": 1.15}, {"p": 38, "n": 5, "d": 1.23}, {"p": 50, "n": 5, "d": 1.68}, {"p": 101, "n": 27, "d": 6.27}, {"p": 102, "n": 29, "d": 5.87}, {"p": 103, "n": 173, "d": 40.35}, {"p": 104, "n": 69, "d": 12.84}, {"p": 105, "n": 40, "d": 7.35}, {"p": 999, "n": 437, "d": 7.23}]}, "cell packing": {"d": "cell serialisation", "b": -5, "l": 999, "m": 69, "s": 21, "t": -0.702, "cv": 0.868, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": -5, "n": 1, "d": 0.53}, {"p": -4, "n": 1, "d": 0.15}, {"p": -3, "n": 1, "d": 0.56}, {"p": 0, "n": 2, "d": 1.06}, {"p": 1, "n": 8, "d": 3.07}, {"p": 2, "n": 4, "d": 1.24}, {"p": 3, "n": 3, "d": 0.79}, {"p": 5, "n": 5, "d": 0.97}, {"p": 6, "n": 3, "d": 0.52}, {"p": 7, "n": 5, "d": 0.76}, {"p": 11, "n": 1, "d": 0.52}, {"p": 18, "n": 2, "d": 0.72}, {"p": 21, "n": 8, "d": 1.91}, {"p": 26, "n": 5, "d": 1.04}, {"p": 28, "n": 1, "d": 0.32}, {"p": 29, "n": 1, "d": 0.26}, {"p": 30, "n": 4, "d": 0.4}, {"p": 32, "n": 1, "d": 0.2}, {"p": 102, "n": 1, "d": 0.2}, {"p": 105, "n": 1, "d": 0.18}, {"p": 999, "n": 11, "d": 0.64}]}, "2pda": {"d": "dual-stack pushdown automaton", "b": -3, "l": 999, "m": 42, "s": 8, "t": 0.076, "cv": 0.498, "tb": "RELEVANT", "gp": "FORTH", "tl": [{"p": -3, "n": 1, "d": 0.56}, {"p": 0, "n": 2, "d": 1.06}, {"p": 3, "n": 5, "d": 0.66}, {"p": 4, "n": 1, "d": 0.31}, {"p": 5, "n": 1, "d": 0.19}, {"p": 6, "n": 3, "d": 0.78}, {"p": 26, "n": 1, "d": 0.51}, {"p": 999, "n": 28, "d": 1.23}]}, "two-stack": {"d": "dual-stack machine", "b": 3, "l": 999, "m": 2, "s": 2, "t": 0, "cv": 0.291, "tb": "ACTIVE", "gp": "LISP", "tl": [{"p": 3, "n": 1, "d": 0.2}, {"p": 999, "n": 1, "d": 0.11}]}, "opcodes": {"d": "instruction set", "b": -5, "l": 999, "m": 398, "s": 25, "t": -0.378, "cv": 1.088, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -5, "n": 2, "d": 1.06}, {"p": -4, "n": 1, "d": 0.15}, {"p": -3, "n": 3, "d": 1.67}, {"p": -1, "n": 3, "d": 1.05}, {"p": 0, "n": 4, "d": 1.59}, {"p": 1, "n": 1, "d": 0.94}, {"p": 2, "n": 2, "d": 0.61}, {"p": 3, "n": 50, "d": 5.73}, {"p": 4, "n": 39, "d": 6.94}, {"p": 5, "n": 8, "d": 1.32}, {"p": 6, "n": 10, "d": 2.23}, {"p": 7, "n": 1, "d": 0.55}, {"p": 11, "n": 34, "d": 9.07}, {"p": 12, "n": 13, "d": 4.88}, {"p": 18, "n": 1, "d": 0.36}, {"p": 26, "n": 108, "d": 6.02}, {"p": 27, "n": 10, "d": 1.58}, {"p": 28, "n": 8, "d": 1.28}, {"p": 29, "n": 11, "d": 1.71}, {"p": 30, "n": 11, "d": 0.91}, {"p": 32, "n": 2, "d": 0.39}, {"p": 33, "n": 1, "d": 0.56}, {"p": 38, "n": 4, "d": 1.06}, {"p": 102, "n": 1, "d": 0.2}, {"p": 999, "n": 70, "d": 1.86}]}, "forth": {"d": "Forth execution layer", "b": -4, "l": 999, "m": 299, "s": 18, "t": -0.328, "cv": 0.978, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -4, "n": 2, "d": 0.3}, {"p": -3, "n": 2, "d": 1.12}, {"p": 0, "n": 21, "d": 6.62}, {"p": 1, "n": 14, "d": 4.67}, {"p": 3, "n": 10, "d": 1.7}, {"p": 4, "n": 12, "d": 2.04}, {"p": 5, "n": 2, "d": 1.48}, {"p": 6, "n": 19, "d": 5.09}, {"p": 18, "n": 15, "d": 5.42}, {"p": 20, "n": 2, "d": 0.51}, {"p": 21, "n": 43, "d": 10.11}, {"p": 26, "n": 11, "d": 1.58}, {"p": 28, "n": 1, "d": 0.32}, {"p": 29, "n": 1, "d": 0.26}, {"p": 35, "n": 1, "d": 0.22}, {"p": 102, "n": 9, "d": 1.82}, {"p": 104, "n": 8, "d": 1.49}, {"p": 999, "n": 126, "d": 6.93}]}, "stack machine": {"d": "stack-based execution", "b": -3, "l": 999, "m": 11, "s": 6, "t": 0.547, "cv": 0.467, "tb": "RELEVANT", "gp": "FORTH", "tl": [{"p": -3, "n": 1, "d": 0.56}, {"p": 3, "n": 2, "d": 0.34}, {"p": 4, "n": 1, "d": 0.41}, {"p": 11, "n": 2, "d": 1.12}, {"p": 26, "n": 1, "d": 0.43}, {"p": 999, "n": 4, "d": 0.96}]}, "bca": {"d": "Bitcoin-Certified Address", "b": -5, "l": 999, "m": 527, "s": 19, "t": -0.58, "cv": 1.604, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": -5, "n": 8, "d": 4.24}, {"p": -3, "n": 2, "d": 1.12}, {"p": 0, "n": 10, "d": 3.71}, {"p": 1, "n": 4, "d": 1.53}, {"p": 2, "n": 105, "d": 31.5}, {"p": 3, "n": 17, "d": 2.69}, {"p": 4, "n": 7, "d": 1.22}, {"p": 5, "n": 5, "d": 0.97}, {"p": 6, "n": 14, "d": 3.11}, {"p": 7, "n": 26, "d": 4.19}, {"p": 8, "n": 1, "d": 0.43}, {"p": 26, "n": 94, "d": 4.07}, {"p": 29, "n": 19, "d": 3.16}, {"p": 32, "n": 1, "d": 0.2}, {"p": 34, "n": 115, "d": 9.81}, {"p": 37, "n": 1, "d": 0.38}, {"p": 101, "n": 24, "d": 5.57}, {"p": 104, "n": 1, "d": 0.19}, {"p": 999, "n": 73, "d": 2.65}]}, "certid": {"d": "certificate identity", "b": 12, "l": 999, "m": 717, "s": 17, "t": -0.91, "cv": 0.962, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": 12, "n": 9, "d": 5.21}, {"p": 14, "n": 193, "d": 15.05}, {"p": 15, "n": 59, "d": 12.92}, {"p": 16, "n": 48, "d": 12.47}, {"p": 17, "n": 62, "d": 13.86}, {"p": 18, "n": 46, "d": 5.95}, {"p": 20, "n": 29, "d": 6.76}, {"p": 26, "n": 148, "d": 7.67}, {"p": 30, "n": 6, "d": 1.06}, {"p": 31, "n": 13, "d": 3.55}, {"p": 32, "n": 1, "d": 0.2}, {"p": 34, "n": 7, "d": 0.61}, {"p": 36, "n": 3, "d": 0.31}, {"p": 37, "n": 3, "d": 1.15}, {"p": 38, "n": 14, "d": 1.64}, {"p": 102, "n": 1, "d": 0.2}, {"p": 999, "n": 75, "d": 2.04}]}, "gip": {"d": "identity model", "b": -3, "l": 999, "m": 45, "s": 6, "t": -0.191, "cv": 0.672, "tb": "ACTIVE", "gp": "LISP", "tl": [{"p": -3, "n": 4, "d": 2.23}, {"p": -1, "n": 1, "d": 0.73}, {"p": 9, "n": 18, "d": 3.96}, {"p": 10, "n": 3, "d": 1.09}, {"p": 14, "n": 2, "d": 0.5}, {"p": 999, "n": 17, "d": 1.91}]}, "identity": {"d": "identity system", "b": -5, "l": 999, "m": 1882, "s": 39, "t": -0.168, "cv": 1.01, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -5, "n": 5, "d": 2.65}, {"p": -4, "n": 45, "d": 6.78}, {"p": -3, "n": 13, "d": 7.25}, {"p": 1, "n": 5, "d": 1.65}, {"p": 2, "n": 4, "d": 2.53}, {"p": 4, "n": 11, "d": 1.84}, {"p": 8, "n": 65, "d": 14.74}, {"p": 9, "n": 40, "d": 6.37}, {"p": 10, "n": 18, "d": 3.81}, {"p": 11, "n": 12, "d": 3.36}, {"p": 12, "n": 6, "d": 1.04}, {"p": 13, "n": 3, "d": 1.47}, {"p": 14, "n": 159, "d": 16.26}, {"p": 15, "n": 37, "d": 8.17}, {"p": 16, "n": 40, "d": 10.07}, {"p": 17, "n": 78, "d": 19.47}, {"p": 18, "n": 31, "d": 3.68}, {"p": 19, "n": 21, "d": 4.45}, {"p": 20, "n": 117, "d": 17.75}, {"p": 21, "n": 9, "d": 2.1}, {"p": 22, "n": 4, "d": 1.12}, {"p": 23, "n": 1, "d": 0.33}, {"p": 26, "n": 528, "d": 13.47}, {"p": 27, "n": 2, "d": 0.31}, {"p": 28, "n": 18, "d": 2.9}, {"p": 29, "n": 25, "d": 3.25}, {"p": 30, "n": 134, "d": 4.4}, {"p": 31, "n": 37, "d": 10.01}, {"p": 32, "n": 11, "d": 2.15}, {"p": 33, "n": 35, "d": 6.32}, {"p": 34, "n": 18, "d": 1.57}, {"p": 35, "n": 6, "d": 1.35}, {"p": 36, "n": 44, "d": 1.59}, {"p": 37, "n": 66, "d": 20.51}, {"p": 38, "n": 12, "d": 2.67}, {"p": 50, "n": 5, "d": 1.68}, {"p": 101, "n": 6, "d": 1.39}, {"p": 103, "n": 1, "d": 0.23}, {"p": 999, "n": 210, "d": 4.17}]}, "selective disclosure": {"d": "privacy mechanism", "b": -3, "l": 999, "m": 12, "s": 5, "t": -0.079, "cv": 0.484, "tb": "RELEVANT", "gp": "FORTH", "tl": [{"p": -3, "n": 2, "d": 1.12}, {"p": 9, "n": 1, "d": 0.41}, {"p": 10, "n": 2, "d": 0.7}, {"p": 14, "n": 1, "d": 0.25}, {"p": 999, "n": 6, "d": 1.03}]}, "facets": {"d": "identity facets", "b": -4, "l": 999, "m": 109, "s": 18, "t": -0.632, "cv": 1.146, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": -4, "n": 12, "d": 1.81}, {"p": -3, "n": 1, "d": 0.56}, {"p": 8, "n": 27, "d": 6.1}, {"p": 9, "n": 5, "d": 1.17}, {"p": 14, "n": 4, "d": 0.72}, {"p": 16, "n": 3, "d": 0.8}, {"p": 17, "n": 1, "d": 0.58}, {"p": 19, "n": 1, "d": 0.42}, {"p": 20, "n": 4, "d": 2.46}, {"p": 26, "n": 1, "d": 0.46}, {"p": 27, "n": 1, "d": 0.32}, {"p": 28, "n": 7, "d": 1.13}, {"p": 29, "n": 9, "d": 1.17}, {"p": 32, "n": 3, "d": 0.59}, {"p": 34, "n": 2, "d": 0.52}, {"p": 36, "n": 13, "d": 0.78}, {"p": 50, "n": 1, "d": 0.34}, {"p": 999, "n": 14, "d": 0.71}]}, "taxonomy": {"d": "type taxonomy", "b": -4, "l": 999, "m": 988, "s": 29, "t": -0.843, "cv": 1.514, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": -4, "n": 64, "d": 9.64}, {"p": -3, "n": 11, "d": 6.14}, {"p": -1, "n": 4, "d": 4.29}, {"p": 0, "n": 1, "d": 0.53}, {"p": 1, "n": 1, "d": 0.59}, {"p": 8, "n": 3, "d": 0.67}, {"p": 9, "n": 16, "d": 2.44}, {"p": 10, "n": 46, "d": 26.85}, {"p": 13, "n": 136, "d": 33.6}, {"p": 14, "n": 10, "d": 1.13}, {"p": 18, "n": 7, "d": 2.53}, {"p": 20, "n": 8, "d": 2.01}, {"p": 22, "n": 44, "d": 8.35}, {"p": 23, "n": 59, "d": 19.52}, {"p": 24, "n": 4, "d": 8.91}, {"p": 26, "n": 136, "d": 6.12}, {"p": 28, "n": 16, "d": 2.59}, {"p": 29, "n": 9, "d": 1.17}, {"p": 32, "n": 6, "d": 1.17}, {"p": 34, "n": 9, "d": 1.14}, {"p": 35, "n": 2, "d": 0.45}, {"p": 36, "n": 255, "d": 6.5}, {"p": 37, "n": 2, "d": 0.77}, {"p": 50, "n": 5, "d": 1.68}, {"p": 101, "n": 1, "d": 0.23}, {"p": 102, "n": 4, "d": 0.81}, {"p": 104, "n": 1, "d": 0.19}, {"p": 105, "n": 1, "d": 0.18}, {"p": 999, "n": 127, "d": 2.54}]}, "intent": {"d": "intent classification", "b": -4, "l": 999, "m": 495, "s": 26, "t": -0.75, "cv": 1.549, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": -4, "n": 51, "d": 7.68}, {"p": -3, "n": 4, "d": 2.23}, {"p": -1, "n": 5, "d": 2.46}, {"p": 3, "n": 1, "d": 0.2}, {"p": 4, "n": 1, "d": 0.41}, {"p": 5, "n": 1, "d": 0.19}, {"p": 9, "n": 90, "d": 14.38}, {"p": 10, "n": 16, "d": 3.59}, {"p": 12, "n": 1, "d": 3.17}, {"p": 13, "n": 119, "d": 29.38}, {"p": 14, "n": 8, "d": 1.47}, {"p": 15, "n": 1, "d": 2.07}, {"p": 18, "n": 16, "d": 3.23}, {"p": 19, "n": 12, "d": 2.54}, {"p": 21, "n": 7, "d": 1.63}, {"p": 22, "n": 14, "d": 2.18}, {"p": 23, "n": 20, "d": 6.62}, {"p": 24, "n": 6, "d": 13.36}, {"p": 26, "n": 30, "d": 2.21}, {"p": 28, "n": 2, "d": 0.32}, {"p": 31, "n": 1, "d": 0.47}, {"p": 32, "n": 1, "d": 0.2}, {"p": 35, "n": 1, "d": 0.22}, {"p": 36, "n": 15, "d": 0.83}, {"p": 38, "n": 2, "d": 0.72}, {"p": 999, "n": 70, "d": 2.82}]}, "ltree": {"d": "LTREE path structure", "b": -4, "l": 999, "m": 17, "s": 7, "t": 0.376, "cv": 1.022, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -4, "n": 3, "d": 0.45}, {"p": -3, "n": 1, "d": 0.56}, {"p": 10, "n": 4, "d": 3.13}, {"p": 13, "n": 1, "d": 0.5}, {"p": 22, "n": 1, "d": 0.36}, {"p": 23, "n": 1, "d": 0.33}, {"p": 999, "n": 6, "d": 1.06}]}, "six-axis": {"d": "six-axis coordinate system", "b": -3, "l": 999, "m": 12, "s": 4, "t": -0.67, "cv": 0.341, "tb": "AFFINE", "gp": "LISP", "tl": [{"p": -3, "n": 2, "d": 1.12}, {"p": 9, "n": 2, "d": 0.81}, {"p": 34, "n": 7, "d": 0.88}, {"p": 999, "n": 1, "d": 0.37}]}, "coordinate": {"d": "coordinate system", "b": -4, "l": 999, "m": 146, "s": 17, "t": -0.793, "cv": 1.929, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": -4, "n": 11, "d": 1.66}, {"p": -3, "n": 3, "d": 1.67}, {"p": 9, "n": 3, "d": 1.22}, {"p": 10, "n": 22, "d": 14.51}, {"p": 12, "n": 1, "d": 1.99}, {"p": 14, "n": 1, "d": 0.25}, {"p": 18, "n": 1, "d": 0.34}, {"p": 19, "n": 2, "d": 0.42}, {"p": 26, "n": 3, "d": 0.38}, {"p": 27, "n": 2, "d": 0.31}, {"p": 28, "n": 4, "d": 0.64}, {"p": 29, "n": 4, "d": 1.04}, {"p": 32, "n": 1, "d": 0.2}, {"p": 34, "n": 4, "d": 0.5}, {"p": 36, "n": 50, "d": 1.54}, {"p": 102, "n": 1, "d": 0.2}, {"p": 999, "n": 33, "d": 1.91}]}, "classification": {"d": "classification system", "b": -4, "l": 999, "m": 196, "s": 23, "t": -0.659, "cv": 1.079, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": -4, "n": 34, "d": 5.12}, {"p": -3, "n": 1, "d": 0.56}, {"p": -1, "n": 3, "d": 3.22}, {"p": 4, "n": 8, "d": 1.38}, {"p": 7, "n": 1, "d": 0.37}, {"p": 9, "n": 44, "d": 7.0}, {"p": 10, "n": 12, "d": 4.49}, {"p": 11, "n": 5, "d": 1.49}, {"p": 12, "n": 1, "d": 0.63}, {"p": 13, "n": 31, "d": 7.67}, {"p": 14, "n": 1, "d": 0.48}, {"p": 18, "n": 1, "d": 0.36}, {"p": 19, "n": 1, "d": 0.42}, {"p": 21, "n": 2, "d": 0.47}, {"p": 22, "n": 3, "d": 1.09}, {"p": 23, "n": 9, "d": 2.98}, {"p": 24, "n": 1, "d": 2.23}, {"p": 26, "n": 2, "d": 1.12}, {"p": 28, "n": 2, "d": 0.32}, {"p": 35, "n": 1, "d": 0.22}, {"p": 36, "n": 1, "d": 1.93}, {"p": 102, "n": 1, "d": 0.2}, {"p": 999, "n": 31, "d": 1.51}]}, "compression gradient": {"d": "compression gradient pipeline", "b": -3, "l": 999, "m": 48, "s": 10, "t": -0.496, "cv": 0.816, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -3, "n": 2, "d": 1.12}, {"p": 18, "n": 2, "d": 0.72}, {"p": 21, "n": 6, "d": 1.44}, {"p": 26, "n": 10, "d": 2.52}, {"p": 27, "n": 2, "d": 0.31}, {"p": 28, "n": 2, "d": 0.32}, {"p": 29, "n": 1, "d": 0.26}, {"p": 30, "n": 1, "d": 0.31}, {"p": 32, "n": 2, "d": 0.39}, {"p": 999, "n": 20, "d": 0.95}]}, "natural language": {"d": "NL input layer", "b": -5, "l": 999, "m": 48, "s": 12, "t": 0.059, "cv": 0.923, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -5, "n": 6, "d": 3.18}, {"p": -4, "n": 2, "d": 0.3}, {"p": -3, "n": 1, "d": 0.56}, {"p": 9, "n": 1, "d": 0.41}, {"p": 18, "n": 6, "d": 2.17}, {"p": 19, "n": 1, "d": 0.42}, {"p": 21, "n": 9, "d": 2.1}, {"p": 23, "n": 2, "d": 0.66}, {"p": 26, "n": 1, "d": 0.43}, {"p": 27, "n": 1, "d": 0.32}, {"p": 31, "n": 4, "d": 3.38}, {"p": 999, "n": 14, "d": 0.58}]}, "lisp": {"d": "Lisp axiom layer", "b": -5, "l": 999, "m": 690, "s": 18, "t": 1.642, "cv": 1.049, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -5, "n": 6, "d": 3.18}, {"p": -4, "n": 1, "d": 0.15}, {"p": -3, "n": 4, "d": 2.23}, {"p": 18, "n": 28, "d": 10.11}, {"p": 19, "n": 8, "d": 1.69}, {"p": 20, "n": 3, "d": 0.76}, {"p": 21, "n": 74, "d": 17.42}, {"p": 26, "n": 131, "d": 7.13}, {"p": 27, "n": 34, "d": 5.33}, {"p": 28, "n": 30, "d": 4.8}, {"p": 29, "n": 35, "d": 4.92}, {"p": 30, "n": 4, "d": 1.25}, {"p": 32, "n": 19, "d": 3.71}, {"p": 38, "n": 6, "d": 2.71}, {"p": 102, "n": 62, "d": 12.55}, {"p": 104, "n": 130, "d": 24.2}, {"p": 105, "n": 4, "d": 0.74}, {"p": 999, "n": 111, "d": 3.98}]}, "axiom": {"d": "axiom compilation", "b": -5, "l": 999, "m": 120, "s": 13, "t": -0.705, "cv": 0.937, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": -5, "n": 3, "d": 1.59}, {"p": -3, "n": 2, "d": 1.12}, {"p": 11, "n": 29, "d": 6.36}, {"p": 12, "n": 5, "d": 1.22}, {"p": 18, "n": 10, "d": 3.61}, {"p": 19, "n": 6, "d": 1.27}, {"p": 20, "n": 2, "d": 0.51}, {"p": 21, "n": 10, "d": 2.35}, {"p": 22, "n": 16, "d": 5.79}, {"p": 26, "n": 1, "d": 0.43}, {"p": 102, "n": 2, "d": 0.4}, {"p": 104, "n": 1, "d": 0.19}, {"p": 999, "n": 33, "d": 2.01}]}, "semantic shell": {"d": "semantic shell", "b": -4, "l": 999, "m": 42, "s": 12, "t": -0.551, "cv": 0.839, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": -4, "n": 1, "d": 0.15}, {"p": -3, "n": 2, "d": 1.12}, {"p": 18, "n": 7, "d": 2.53}, {"p": 19, "n": 7, "d": 1.48}, {"p": 20, "n": 4, "d": 0.7}, {"p": 21, "n": 1, "d": 0.5}, {"p": 27, "n": 2, "d": 0.31}, {"p": 28, "n": 2, "d": 0.32}, {"p": 29, "n": 1, "d": 0.26}, {"p": 35, "n": 2, "d": 0.45}, {"p": 36, "n": 2, "d": 0.43}, {"p": 999, "n": 11, "d": 1.23}]}, "adapter": {"d": "adapter interface pattern", "b": -5, "l": 999, "m": 2820, "s": 26, "t": 0.364, "cv": 1.386, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -5, "n": 2, "d": 1.06}, {"p": -3, "n": 20, "d": 11.16}, {"p": 6, "n": 3, "d": 2.49}, {"p": 14, "n": 153, "d": 14.88}, {"p": 15, "n": 103, "d": 24.83}, {"p": 16, "n": 29, "d": 7.54}, {"p": 17, "n": 39, "d": 9.62}, {"p": 18, "n": 37, "d": 4.54}, {"p": 19, "n": 6, "d": 1.27}, {"p": 20, "n": 26, "d": 3.34}, {"p": 26, "n": 1169, "d": 31.62}, {"p": 29, "n": 35, "d": 4.17}, {"p": 30, "n": 362, "d": 8.73}, {"p": 31, "n": 10, "d": 2.67}, {"p": 33, "n": 86, "d": 13.61}, {"p": 34, "n": 58, "d": 5.12}, {"p": 35, "n": 18, "d": 4.04}, {"p": 36, "n": 177, "d": 5.06}, {"p": 37, "n": 197, "d": 65.26}, {"p": 38, "n": 10, "d": 2.4}, {"p": 50, "n": 2, "d": 0.67}, {"p": 101, "n": 120, "d": 27.87}, {"p": 103, "n": 14, "d": 3.27}, {"p": 104, "n": 5, "d": 0.93}, {"p": 105, "n": 2, "d": 0.37}, {"p": 999, "n": 137, "d": 3.06}]}, "storage adapter": {"d": "StorageAdapter boundary", "b": 26, "l": 37, "m": 37, "s": 6, "t": -0.577, "cv": 0.546, "tb": "AFFINE", "gp": "CONVERSATION", "tl": [{"p": 26, "n": 16, "d": 1.13}, {"p": 30, "n": 8, "d": 1.34}, {"p": 33, "n": 3, "d": 0.55}, {"p": 34, "n": 1, "d": 0.24}, {"p": 36, "n": 8, "d": 0.66}, {"p": 37, "n": 1, "d": 0.38}]}, "identity adapter": {"d": "IdentityAdapter boundary", "b": 26, "l": 34, "m": 20, "s": 3, "t": -0.646, "cv": 0.443, "tb": "AFFINE", "gp": "CONVERSATION", "tl": [{"p": 26, "n": 14, "d": 1.08}, {"p": 33, "n": 3, "d": 0.55}, {"p": 34, "n": 3, "d": 0.38}]}, "anchor adapter": {"d": "AnchorAdapter boundary", "b": 26, "l": 103, "m": 18, "s": 5, "t": -0.704, "cv": 0.519, "tb": "AFFINE", "gp": "CONVERSATION", "tl": [{"p": 26, "n": 9, "d": 0.79}, {"p": 33, "n": 5, "d": 0.82}, {"p": 34, "n": 2, "d": 0.25}, {"p": 37, "n": 1, "d": 0.38}, {"p": 103, "n": 1, "d": 0.23}]}, "network adapter": {"d": "NetworkAdapter boundary", "b": 26, "l": 999, "m": 20, "s": 6, "t": -0.469, "cv": 0.326, "tb": "RELEVANT", "gp": "CONVERSATION", "tl": [{"p": 26, "n": 9, "d": 0.62}, {"p": 30, "n": 2, "d": 0.86}, {"p": 33, "n": 4, "d": 0.68}, {"p": 34, "n": 3, "d": 0.38}, {"p": 37, "n": 1, "d": 0.38}, {"p": 999, "n": 1, "d": 0.4}]}, "four adapter": {"d": "four-adapter architecture", "b": -3, "l": 103, "m": 60, "s": 8, "t": -0.321, "cv": 0.717, "tb": "ACTIVE", "gp": "LISP", "tl": [{"p": -3, "n": 3, "d": 1.67}, {"p": 26, "n": 41, "d": 1.73}, {"p": 33, "n": 5, "d": 1.11}, {"p": 34, "n": 3, "d": 0.26}, {"p": 35, "n": 1, "d": 0.22}, {"p": 36, "n": 1, "d": 0.62}, {"p": 37, "n": 5, "d": 2.08}, {"p": 103, "n": 1, "d": 0.23}]}, "plexus": {"d": "Plexus overlay network", "b": -5, "l": 999, "m": 1875, "s": 35, "t": -0.139, "cv": 1.511, "tb": "OSCILLATING", "gp": "CLI", "tl": [{"p": -5, "n": 8, "d": 4.24}, {"p": -4, "n": 7, "d": 1.05}, {"p": -3, "n": 22, "d": 12.28}, {"p": 0, "n": 5, "d": 1.86}, {"p": 2, "n": 3, "d": 0.92}, {"p": 3, "n": 16, "d": 2.29}, {"p": 4, "n": 46, "d": 8.37}, {"p": 5, "n": 19, "d": 3.49}, {"p": 6, "n": 28, "d": 3.49}, {"p": 7, "n": 12, "d": 1.74}, {"p": 8, "n": 8, "d": 1.76}, {"p": 11, "n": 25, "d": 5.67}, {"p": 12, "n": 37, "d": 6.93}, {"p": 14, "n": 378, "d": 33.1}, {"p": 15, "n": 227, "d": 54.76}, {"p": 16, "n": 107, "d": 26.28}, {"p": 17, "n": 68, "d": 16.44}, {"p": 18, "n": 67, "d": 7.92}, {"p": 19, "n": 6, "d": 1.27}, {"p": 20, "n": 115, "d": 17.46}, {"p": 26, "n": 247, "d": 9.62}, {"p": 27, "n": 1, "d": 0.32}, {"p": 28, "n": 5, "d": 0.81}, {"p": 29, "n": 5, "d": 0.65}, {"p": 30, "n": 16, "d": 4.99}, {"p": 31, "n": 75, "d": 17.95}, {"p": 32, "n": 3, "d": 0.59}, {"p": 33, "n": 7, "d": 1.83}, {"p": 34, "n": 12, "d": 1.55}, {"p": 35, "n": 1, "d": 0.22}, {"p": 36, "n": 11, "d": 0.64}, {"p": 37, "n": 1, "d": 0.38}, {"p": 38, "n": 10, "d": 2.19}, {"p": 102, "n": 1, "d": 0.2}, {"p": 999, "n": 276, "d": 5.18}]}, "overlay": {"d": "overlay network", "b": -4, "l": 999, "m": 306, "s": 20, "t": 0.785, "cv": 0.975, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -4, "n": 7, "d": 1.05}, {"p": -3, "n": 1, "d": 0.56}, {"p": 8, "n": 1, "d": 0.43}, {"p": 10, "n": 5, "d": 2.69}, {"p": 13, "n": 2, "d": 0.49}, {"p": 20, "n": 2, "d": 0.51}, {"p": 26, "n": 155, "d": 6.72}, {"p": 30, "n": 16, "d": 3.39}, {"p": 31, "n": 7, "d": 3.32}, {"p": 33, "n": 1, "d": 0.56}, {"p": 34, "n": 8, "d": 2.08}, {"p": 35, "n": 2, "d": 0.45}, {"p": 36, "n": 9, "d": 1.11}, {"p": 37, "n": 20, "d": 6.64}, {"p": 50, "n": 8, "d": 2.69}, {"p": 101, "n": 1, "d": 0.23}, {"p": 103, "n": 4, "d": 0.93}, {"p": 104, "n": 3, "d": 0.56}, {"p": 105, "n": 7, "d": 1.29}, {"p": 999, "n": 47, "d": 4.55}]}, "edge": {"d": "graph edge / network edge", "b": -5, "l": 999, "m": 674, "s": 33, "t": 1.295, "cv": 2.195, "tb": "OSCILLATING", "gp": "CLI", "tl": [{"p": -5, "n": 1, "d": 0.53}, {"p": -4, "n": 1, "d": 0.15}, {"p": -3, "n": 4, "d": 2.23}, {"p": 1, "n": 1, "d": 0.59}, {"p": 3, "n": 4, "d": 0.68}, {"p": 4, "n": 5, "d": 0.87}, {"p": 6, "n": 2, "d": 0.71}, {"p": 7, "n": 1, "d": 0.62}, {"p": 8, "n": 2, "d": 0.45}, {"p": 10, "n": 3, "d": 1.36}, {"p": 11, "n": 1, "d": 0.52}, {"p": 12, "n": 4, "d": 1.67}, {"p": 14, "n": 67, "d": 4.96}, {"p": 15, "n": 11, "d": 3.29}, {"p": 16, "n": 111, "d": 28.04}, {"p": 17, "n": 151, "d": 35.04}, {"p": 18, "n": 39, "d": 5.16}, {"p": 19, "n": 1, "d": 0.42}, {"p": 21, "n": 1, "d": 0.5}, {"p": 22, "n": 1, "d": 0.36}, {"p": 23, "n": 1, "d": 0.33}, {"p": 26, "n": 28, "d": 2.36}, {"p": 27, "n": 1, "d": 0.32}, {"p": 29, "n": 59, "d": 6.25}, {"p": 30, "n": 5, "d": 0.58}, {"p": 32, "n": 4, "d": 0.78}, {"p": 33, "n": 2, "d": 0.42}, {"p": 34, "n": 45, "d": 4.2}, {"p": 36, "n": 17, "d": 0.83}, {"p": 38, "n": 3, "d": 0.77}, {"p": 50, "n": 5, "d": 1.68}, {"p": 105, "n": 15, "d": 2.76}, {"p": 999, "n": 78, "d": 1.42}]}, "capability": {"d": "capability token", "b": -5, "l": 999, "m": 1426, "s": 38, "t": -0.01, "cv": 1.598, "tb": "OSCILLATING", "gp": "CLI", "tl": [{"p": -5, "n": 10, "d": 5.3}, {"p": -4, "n": 7, "d": 1.05}, {"p": -3, "n": 8, "d": 4.46}, {"p": -1, "n": 1, "d": 0.73}, {"p": 0, "n": 9, "d": 2.91}, {"p": 1, "n": 1, "d": 0.59}, {"p": 4, "n": 40, "d": 6.69}, {"p": 5, "n": 57, "d": 10.73}, {"p": 6, "n": 15, "d": 2.02}, {"p": 7, "n": 13, "d": 3.04}, {"p": 8, "n": 23, "d": 5.17}, {"p": 9, "n": 6, "d": 0.95}, {"p": 10, "n": 1, "d": 1.32}, {"p": 11, "n": 2, "d": 0.54}, {"p": 12, "n": 4, "d": 1.58}, {"p": 13, "n": 2, "d": 0.49}, {"p": 14, "n": 45, "d": 4.0}, {"p": 15, "n": 12, "d": 4.35}, {"p": 16, "n": 204, "d": 51.28}, {"p": 17, "n": 17, "d": 4.05}, {"p": 18, "n": 30, "d": 3.54}, {"p": 19, "n": 24, "d": 5.08}, {"p": 20, "n": 84, "d": 11.64}, {"p": 21, "n": 35, "d": 8.07}, {"p": 26, "n": 150, "d": 4.26}, {"p": 28, "n": 43, "d": 6.92}, {"p": 29, "n": 88, "d": 10.65}, {"p": 30, "n": 120, "d": 5.87}, {"p": 31, "n": 21, "d": 4.74}, {"p": 32, "n": 13, "d": 2.54}, {"p": 34, "n": 7, "d": 1.82}, {"p": 35, "n": 2, "d": 0.45}, {"p": 36, "n": 41, "d": 1.53}, {"p": 37, "n": 7, "d": 2.69}, {"p": 38, "n": 76, "d": 7.68}, {"p": 50, "n": 2, "d": 0.67}, {"p": 102, "n": 1, "d": 0.2}, {"p": 999, "n": 205, "d": 4.36}]}, "transfer": {"d": "ownership transfer", "b": -3, "l": 999, "m": 399, "s": 20, "t": -0.239, "cv": 1.773, "tb": "OSCILLATING", "gp": "CLI", "tl": [{"p": -3, "n": 3, "d": 1.67}, {"p": 3, "n": 1, "d": 0.2}, {"p": 4, "n": 5, "d": 1.53}, {"p": 5, "n": 1, "d": 0.74}, {"p": 14, "n": 11, "d": 2.72}, {"p": 16, "n": 14, "d": 3.55}, {"p": 17, "n": 126, "d": 30.3}, {"p": 18, "n": 9, "d": 1.09}, {"p": 19, "n": 6, "d": 1.27}, {"p": 20, "n": 7, "d": 2.4}, {"p": 26, "n": 31, "d": 4.18}, {"p": 27, "n": 12, "d": 1.89}, {"p": 28, "n": 41, "d": 6.59}, {"p": 29, "n": 37, "d": 5.85}, {"p": 30, "n": 4, "d": 1.25}, {"p": 31, "n": 1, "d": 0.47}, {"p": 32, "n": 20, "d": 3.9}, {"p": 36, "n": 1, "d": 0.35}, {"p": 37, "n": 1, "d": 0.38}, {"p": 999, "n": 68, "d": 1.57}]}, "recovery": {"d": "recovery mechanism", "b": -5, "l": 999, "m": 427, "s": 17, "t": 0.624, "cv": 1.647, "tb": "OSCILLATING", "gp": "CLI", "tl": [{"p": -5, "n": 2, "d": 1.06}, {"p": -3, "n": 2, "d": 1.12}, {"p": -1, "n": 29, "d": 7.52}, {"p": 4, "n": 1, "d": 0.31}, {"p": 5, "n": 1, "d": 0.74}, {"p": 14, "n": 46, "d": 4.08}, {"p": 15, "n": 12, "d": 3.32}, {"p": 16, "n": 26, "d": 6.74}, {"p": 17, "n": 144, "d": 34.64}, {"p": 18, "n": 6, "d": 1.1}, {"p": 26, "n": 63, "d": 4.37}, {"p": 28, "n": 1, "d": 0.33}, {"p": 30, "n": 9, "d": 2.51}, {"p": 31, "n": 31, "d": 11.46}, {"p": 32, "n": 1, "d": 0.2}, {"p": 37, "n": 4, "d": 1.54}, {"p": 999, "n": 49, "d": 1.75}]}, "bsv": {"d": "Bitcoin SV anchoring", "b": -5, "l": 999, "m": 952, "s": 29, "t": 0.015, "cv": 1.215, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -5, "n": 3, "d": 1.59}, {"p": -4, "n": 2, "d": 0.3}, {"p": -3, "n": 5, "d": 2.79}, {"p": 1, "n": 1, "d": 0.59}, {"p": 2, "n": 14, "d": 4.3}, {"p": 3, "n": 29, "d": 3.61}, {"p": 5, "n": 152, "d": 17.75}, {"p": 6, "n": 35, "d": 6.47}, {"p": 7, "n": 28, "d": 4.08}, {"p": 8, "n": 3, "d": 1.29}, {"p": 12, "n": 8, "d": 1.31}, {"p": 14, "n": 1, "d": 0.25}, {"p": 15, "n": 2, "d": 4.15}, {"p": 26, "n": 218, "d": 6.88}, {"p": 30, "n": 49, "d": 2.82}, {"p": 31, "n": 66, "d": 15.75}, {"p": 32, "n": 1, "d": 0.2}, {"p": 33, "n": 13, "d": 3.52}, {"p": 34, "n": 11, "d": 1.5}, {"p": 35, "n": 8, "d": 1.8}, {"p": 36, "n": 3, "d": 1.11}, {"p": 37, "n": 54, "d": 20.44}, {"p": 38, "n": 4, "d": 1.81}, {"p": 50, "n": 4, "d": 1.34}, {"p": 101, "n": 3, "d": 0.7}, {"p": 102, "n": 1, "d": 0.2}, {"p": 103, "n": 37, "d": 8.63}, {"p": 105, "n": 30, "d": 5.51}, {"p": 999, "n": 167, "d": 2.39}]}, "anchor": {"d": "blockchain anchoring", "b": -5, "l": 999, "m": 1399, "s": 25, "t": 4.955, "cv": 1.342, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -5, "n": 3, "d": 1.59}, {"p": -3, "n": 7, "d": 3.91}, {"p": 1, "n": 1, "d": 0.59}, {"p": 5, "n": 4, "d": 1.21}, {"p": 6, "n": 8, "d": 1.75}, {"p": 7, "n": 1, "d": 0.37}, {"p": 12, "n": 8, "d": 1.85}, {"p": 13, "n": 1, "d": 0.5}, {"p": 14, "n": 2, "d": 0.5}, {"p": 18, "n": 1, "d": 0.36}, {"p": 20, "n": 1, "d": 0.5}, {"p": 26, "n": 571, "d": 18.19}, {"p": 30, "n": 302, "d": 8.89}, {"p": 31, "n": 4, "d": 1.19}, {"p": 32, "n": 16, "d": 3.12}, {"p": 33, "n": 64, "d": 12.43}, {"p": 34, "n": 47, "d": 4.07}, {"p": 35, "n": 16, "d": 3.59}, {"p": 36, "n": 4, "d": 3.98}, {"p": 37, "n": 85, "d": 24.73}, {"p": 101, "n": 7, "d": 1.63}, {"p": 102, "n": 10, "d": 2.02}, {"p": 103, "n": 105, "d": 24.49}, {"p": 105, "n": 40, "d": 7.35}, {"p": 999, "n": 91, "d": 2.28}]}, "spv": {"d": "simplified payment verification", "b": -5, "l": 999, "m": 194, "s": 17, "t": -0.208, "cv": 0.946, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -5, "n": 7, "d": 3.71}, {"p": -3, "n": 2, "d": 1.12}, {"p": 1, "n": 1, "d": 0.59}, {"p": 4, "n": 1, "d": 0.31}, {"p": 5, "n": 42, "d": 6.54}, {"p": 6, "n": 8, "d": 1.72}, {"p": 7, "n": 32, "d": 5.17}, {"p": 12, "n": 1, "d": 0.39}, {"p": 14, "n": 3, "d": 0.74}, {"p": 15, "n": 2, "d": 1.34}, {"p": 18, "n": 6, "d": 1.2}, {"p": 20, "n": 3, "d": 0.76}, {"p": 26, "n": 16, "d": 1.41}, {"p": 30, "n": 36, "d": 4.82}, {"p": 37, "n": 1, "d": 0.38}, {"p": 104, "n": 12, "d": 2.23}, {"p": 999, "n": 21, "d": 0.86}]}, "micropayment": {"d": "micropayment channel", "b": -5, "l": 999, "m": 31, "s": 6, "t": -0.576, "cv": 0.766, "tb": "AFFINE", "gp": "LISP", "tl": [{"p": -5, "n": 3, "d": 1.59}, {"p": 3, "n": 3, "d": 0.59}, {"p": 31, "n": 10, "d": 3.11}, {"p": 33, "n": 2, "d": 1.13}, {"p": 34, "n": 4, "d": 0.53}, {"p": 999, "n": 9, "d": 0.39}]}, "tick": {"d": "tick payment", "b": 4, "l": 999, "m": 207, "s": 8, "t": 0.972, "cv": 1.085, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": 4, "n": 1, "d": 0.31}, {"p": 6, "n": 1, "d": 0.36}, {"p": 12, "n": 13, "d": 3.21}, {"p": 26, "n": 51, "d": 11.4}, {"p": 33, "n": 72, "d": 11.88}, {"p": 34, "n": 62, "d": 5.38}, {"p": 102, "n": 6, "d": 1.21}, {"p": 999, "n": 1, "d": 0.11}]}, "metering": {"d": "resource metering", "b": -5, "l": 999, "m": 314, "s": 24, "t": -0.555, "cv": 1.261, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": -5, "n": 2, "d": 1.06}, {"p": -3, "n": 2, "d": 1.12}, {"p": -1, "n": 24, "d": 5.73}, {"p": 1, "n": 1, "d": 0.94}, {"p": 4, "n": 6, "d": 1.84}, {"p": 6, "n": 1, "d": 0.36}, {"p": 8, "n": 3, "d": 0.67}, {"p": 12, "n": 20, "d": 4.51}, {"p": 14, "n": 8, "d": 1.98}, {"p": 17, "n": 2, "d": 0.5}, {"p": 18, "n": 61, "d": 7.98}, {"p": 26, "n": 89, "d": 10.04}, {"p": 27, "n": 1, "d": 0.32}, {"p": 28, "n": 8, "d": 1.28}, {"p": 29, "n": 8, "d": 1.04}, {"p": 30, "n": 2, "d": 0.62}, {"p": 32, "n": 4, "d": 0.78}, {"p": 33, "n": 10, "d": 1.64}, {"p": 34, "n": 5, "d": 1.22}, {"p": 35, "n": 1, "d": 0.22}, {"p": 36, "n": 21, "d": 1.29}, {"p": 38, "n": 2, "d": 0.9}, {"p": 103, "n": 1, "d": 0.23}, {"p": 999, "n": 32, "d": 0.93}]}, "governance": {"d": "governance system", "b": -4, "l": 999, "m": 784, "s": 22, "t": -0.237, "cv": 0.987, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -4, "n": 52, "d": 7.83}, {"p": -3, "n": 7, "d": 3.91}, {"p": -1, "n": 6, "d": 6.44}, {"p": 10, "n": 60, "d": 10.8}, {"p": 13, "n": 5, "d": 1.23}, {"p": 14, "n": 36, "d": 2.77}, {"p": 16, "n": 3, "d": 0.72}, {"p": 18, "n": 17, "d": 1.86}, {"p": 19, "n": 15, "d": 3.18}, {"p": 20, "n": 4, "d": 1.03}, {"p": 22, "n": 3, "d": 0.94}, {"p": 23, "n": 6, "d": 1.99}, {"p": 26, "n": 8, "d": 0.41}, {"p": 28, "n": 12, "d": 1.92}, {"p": 29, "n": 4, "d": 0.52}, {"p": 32, "n": 2, "d": 0.39}, {"p": 36, "n": 302, "d": 11.05}, {"p": 37, "n": 8, "d": 3.77}, {"p": 38, "n": 20, "d": 4.54}, {"p": 101, "n": 1, "d": 0.23}, {"p": 102, "n": 1, "d": 0.2}, {"p": 999, "n": 212, "d": 5.54}]}, "ballot": {"d": "ballot mechanism", "b": -4, "l": 999, "m": 280, "s": 14, "t": -0.18, "cv": 0.996, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -4, "n": 20, "d": 3.01}, {"p": -3, "n": 1, "d": 0.56}, {"p": 10, "n": 22, "d": 5.41}, {"p": 13, "n": 1, "d": 0.49}, {"p": 14, "n": 9, "d": 1.23}, {"p": 18, "n": 54, "d": 5.74}, {"p": 20, "n": 7, "d": 1.79}, {"p": 23, "n": 2, "d": 0.66}, {"p": 26, "n": 1, "d": 0.38}, {"p": 28, "n": 9, "d": 1.43}, {"p": 29, "n": 1, "d": 0.26}, {"p": 32, "n": 1, "d": 0.2}, {"p": 36, "n": 114, "d": 5.81}, {"p": 999, "n": 38, "d": 1.51}]}, "dispute": {"d": "dispute resolution", "b": -4, "l": 999, "m": 468, "s": 17, "t": -0.282, "cv": 1.064, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -4, "n": 30, "d": 4.52}, {"p": -3, "n": 2, "d": 1.12}, {"p": 10, "n": 43, "d": 7.63}, {"p": 12, "n": 4, "d": 2.31}, {"p": 13, "n": 1, "d": 0.49}, {"p": 14, "n": 3, "d": 0.49}, {"p": 18, "n": 124, "d": 12.99}, {"p": 19, "n": 13, "d": 2.75}, {"p": 20, "n": 9, "d": 1.27}, {"p": 22, "n": 4, "d": 1.45}, {"p": 26, "n": 20, "d": 2.98}, {"p": 28, "n": 14, "d": 2.23}, {"p": 29, "n": 1, "d": 0.26}, {"p": 32, "n": 14, "d": 2.73}, {"p": 36, "n": 140, "d": 6.87}, {"p": 50, "n": 1, "d": 0.34}, {"p": 999, "n": 45, "d": 1.34}]}, "reputation": {"d": "reputation system", "b": -4, "l": 999, "m": 92, "s": 9, "t": -0.893, "cv": 1.601, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": -4, "n": 28, "d": 4.22}, {"p": -3, "n": 4, "d": 2.23}, {"p": 10, "n": 28, "d": 15.38}, {"p": 13, "n": 1, "d": 0.49}, {"p": 14, "n": 8, "d": 0.74}, {"p": 18, "n": 1, "d": 0.36}, {"p": 20, "n": 1, "d": 0.5}, {"p": 36, "n": 4, "d": 0.58}, {"p": 999, "n": 17, "d": 1.25}]}, "stake": {"d": "staking mechanism", "b": -4, "l": 999, "m": 223, "s": 16, "t": 0.667, "cv": 1.437, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -4, "n": 27, "d": 4.07}, {"p": -3, "n": 1, "d": 0.56}, {"p": 9, "n": 1, "d": 0.41}, {"p": 10, "n": 22, "d": 4.11}, {"p": 13, "n": 1, "d": 0.49}, {"p": 14, "n": 11, "d": 1.48}, {"p": 16, "n": 7, "d": 1.81}, {"p": 18, "n": 5, "d": 0.59}, {"p": 19, "n": 4, "d": 0.85}, {"p": 20, "n": 7, "d": 2.4}, {"p": 22, "n": 2, "d": 0.72}, {"p": 28, "n": 1, "d": 0.32}, {"p": 29, "n": 3, "d": 0.39}, {"p": 36, "n": 1, "d": 0.34}, {"p": 101, "n": 55, "d": 12.77}, {"p": 999, "n": 75, "d": 2.24}]}, "extension": {"d": "extension system", "b": -5, "l": 999, "m": 2128, "s": 40, "t": 0.953, "cv": 1.119, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -5, "n": 14, "d": 7.42}, {"p": -4, "n": 74, "d": 11.14}, {"p": -3, "n": 10, "d": 5.58}, {"p": -1, "n": 1, "d": 0.73}, {"p": 0, "n": 1, "d": 0.53}, {"p": 1, "n": 15, "d": 4.61}, {"p": 2, "n": 4, "d": 1.21}, {"p": 3, "n": 2, "d": 0.34}, {"p": 4, "n": 2, "d": 0.61}, {"p": 5, "n": 6, "d": 1.16}, {"p": 6, "n": 2, "d": 0.6}, {"p": 7, "n": 4, "d": 1.48}, {"p": 8, "n": 40, "d": 9.03}, {"p": 9, "n": 62, "d": 10.04}, {"p": 10, "n": 38, "d": 7.92}, {"p": 13, "n": 90, "d": 22.27}, {"p": 14, "n": 24, "d": 2.83}, {"p": 16, "n": 1, "d": 0.43}, {"p": 17, "n": 5, "d": 2.11}, {"p": 18, "n": 11, "d": 1.33}, {"p": 19, "n": 36, "d": 7.63}, {"p": 20, "n": 12, "d": 1.7}, {"p": 21, "n": 22, "d": 5.24}, {"p": 22, "n": 13, "d": 4.71}, {"p": 23, "n": 7, "d": 2.32}, {"p": 26, "n": 288, "d": 9.38}, {"p": 28, "n": 3, "d": 0.48}, {"p": 29, "n": 2, "d": 0.52}, {"p": 30, "n": 15, "d": 1.29}, {"p": 31, "n": 19, "d": 5.99}, {"p": 32, "n": 18, "d": 3.51}, {"p": 33, "n": 5, "d": 2.82}, {"p": 34, "n": 14, "d": 3.64}, {"p": 35, "n": 19, "d": 4.27}, {"p": 36, "n": 800, "d": 18.58}, {"p": 37, "n": 91, "d": 26.44}, {"p": 38, "n": 27, "d": 3.82}, {"p": 102, "n": 48, "d": 9.71}, {"p": 105, "n": 2, "d": 0.37}, {"p": 999, "n": 281, "d": 5.86}]}, "vertical": {"d": "vertical domain (pre-rename)", "b": -3, "l": 999, "m": 1025, "s": 12, "t": -0.879, "cv": 1.446, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": -3, "n": 6, "d": 3.35}, {"p": 18, "n": 2, "d": 2.11}, {"p": 26, "n": 808, "d": 25.22}, {"p": 30, "n": 25, "d": 1.47}, {"p": 33, "n": 17, "d": 3.17}, {"p": 34, "n": 65, "d": 5.65}, {"p": 36, "n": 7, "d": 0.48}, {"p": 50, "n": 38, "d": 12.76}, {"p": 101, "n": 1, "d": 0.23}, {"p": 102, "n": 1, "d": 0.2}, {"p": 105, "n": 1, "d": 0.18}, {"p": 999, "n": 54, "d": 3.28}]}, "trades": {"d": "trades vertical", "b": -5, "l": 999, "m": 392, "s": 27, "t": -0.54, "cv": 1.074, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": -5, "n": 2, "d": 1.06}, {"p": -4, "n": 8, "d": 1.2}, {"p": -3, "n": 2, "d": 1.12}, {"p": 6, "n": 1, "d": 0.83}, {"p": 8, "n": 18, "d": 4.12}, {"p": 9, "n": 19, "d": 2.96}, {"p": 10, "n": 9, "d": 1.88}, {"p": 13, "n": 54, "d": 13.36}, {"p": 14, "n": 7, "d": 1.21}, {"p": 15, "n": 2, "d": 1.22}, {"p": 16, "n": 6, "d": 1.6}, {"p": 18, "n": 18, "d": 6.5}, {"p": 19, "n": 27, "d": 5.72}, {"p": 20, "n": 9, "d": 1.6}, {"p": 21, "n": 6, "d": 1.41}, {"p": 22, "n": 11, "d": 3.98}, {"p": 23, "n": 3, "d": 0.99}, {"p": 26, "n": 85, "d": 2.74}, {"p": 28, "n": 5, "d": 0.8}, {"p": 30, "n": 2, "d": 0.42}, {"p": 31, "n": 2, "d": 0.95}, {"p": 32, "n": 1, "d": 0.2}, {"p": 34, "n": 10, "d": 1.28}, {"p": 36, "n": 11, "d": 0.62}, {"p": 38, "n": 2, "d": 2.09}, {"p": 50, "n": 9, "d": 3.02}, {"p": 999, "n": 63, "d": 3.38}]}, "grammar": {"d": "domain grammar", "b": -3, "l": 999, "m": 1427, "s": 15, "t": 4.266, "cv": 1.281, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -3, "n": 1, "d": 0.56}, {"p": 18, "n": 3, "d": 1.08}, {"p": 19, "n": 13, "d": 2.75}, {"p": 20, "n": 2, "d": 1.23}, {"p": 26, "n": 19, "d": 2.0}, {"p": 30, "n": 14, "d": 4.37}, {"p": 32, "n": 11, "d": 2.15}, {"p": 33, "n": 59, "d": 9.4}, {"p": 34, "n": 54, "d": 4.64}, {"p": 35, "n": 10, "d": 2.25}, {"p": 36, "n": 1087, "d": 25.24}, {"p": 38, "n": 5, "d": 2.26}, {"p": 102, "n": 41, "d": 8.3}, {"p": 105, "n": 5, "d": 0.92}, {"p": 999, "n": 103, "d": 3.42}]}, "srv6": {"d": "SRv6 segment routing", "b": -4, "l": 999, "m": 201, "s": 3, "t": 5.03, "cv": 1.284, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -4, "n": 1, "d": 0.15}, {"p": 34, "n": 191, "d": 16.03}, {"p": 999, "n": 9, "d": 0.91}]}, "mesh": {"d": "mesh network", "b": -4, "l": 999, "m": 137, "s": 10, "t": 2.223, "cv": 1.113, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -4, "n": 3, "d": 0.45}, {"p": 3, "n": 2, "d": 0.39}, {"p": 26, "n": 2, "d": 0.44}, {"p": 33, "n": 24, "d": 6.18}, {"p": 34, "n": 78, "d": 7.02}, {"p": 101, "n": 6, "d": 1.39}, {"p": 103, "n": 5, "d": 1.17}, {"p": 104, "n": 2, "d": 0.37}, {"p": 105, "n": 5, "d": 0.92}, {"p": 999, "n": 10, "d": 2.84}]}, "multicast": {"d": "multicast delivery", "b": -4, "l": 999, "m": 334, "s": 11, "t": -0.323, "cv": 1.274, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -4, "n": 6, "d": 0.9}, {"p": 26, "n": 22, "d": 4.44}, {"p": 33, "n": 4, "d": 2.26}, {"p": 34, "n": 149, "d": 12.64}, {"p": 37, "n": 1, "d": 0.38}, {"p": 50, "n": 4, "d": 1.34}, {"p": 101, "n": 84, "d": 19.51}, {"p": 103, "n": 13, "d": 3.03}, {"p": 104, "n": 6, "d": 1.12}, {"p": 105, "n": 7, "d": 1.29}, {"p": 999, "n": 38, "d": 2.74}]}, "6lowpan": {"d": "6LoWPAN IoT protocol", "b": 33, "l": 999, "m": 19, "s": 6, "t": -0.807, "cv": 1.207, "tb": "AFFINE", "gp": "CONVERSATION", "tl": [{"p": 33, "n": 11, "d": 2.36}, {"p": 34, "n": 4, "d": 0.5}, {"p": 101, "n": 1, "d": 0.23}, {"p": 102, "n": 1, "d": 0.2}, {"p": 103, "n": 1, "d": 0.23}, {"p": 999, "n": 1, "d": 0.32}]}, "depin": {"d": "decentralised physical infrastructure", "b": 33, "l": 999, "m": 310, "s": 6, "t": -0.937, "cv": 1.335, "tb": "AFFINE", "gp": "CONVERSATION", "tl": [{"p": 33, "n": 195, "d": 32.38}, {"p": 34, "n": 42, "d": 3.51}, {"p": 35, "n": 1, "d": 0.22}, {"p": 102, "n": 66, "d": 13.35}, {"p": 103, "n": 4, "d": 0.93}, {"p": 999, "n": 2, "d": 1.35}]}, "routing": {"d": "network routing", "b": -4, "l": 999, "m": 173, "s": 21, "t": 0.718, "cv": 1.459, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -4, "n": 16, "d": 2.41}, {"p": -3, "n": 1, "d": 0.56}, {"p": 3, "n": 2, "d": 0.34}, {"p": 6, "n": 2, "d": 0.73}, {"p": 9, "n": 5, "d": 0.82}, {"p": 10, "n": 1, "d": 0.78}, {"p": 18, "n": 4, "d": 1.44}, {"p": 19, "n": 5, "d": 1.06}, {"p": 20, "n": 5, "d": 0.71}, {"p": 21, "n": 1, "d": 0.5}, {"p": 23, "n": 1, "d": 0.33}, {"p": 26, "n": 2, "d": 0.39}, {"p": 30, "n": 1, "d": 0.4}, {"p": 31, "n": 1, "d": 0.47}, {"p": 32, "n": 1, "d": 0.2}, {"p": 33, "n": 4, "d": 0.68}, {"p": 34, "n": 88, "d": 7.95}, {"p": 35, "n": 5, "d": 1.12}, {"p": 36, "n": 3, "d": 0.78}, {"p": 50, "n": 1, "d": 0.34}, {"p": 999, "n": 24, "d": 1.09}]}, "paskian": {"d": "Paskian learning", "b": 22, "l": 999, "m": 194, "s": 7, "t": 0.938, "cv": 0.637, "tb": "ACTIVE", "gp": "CONVERSATION", "tl": [{"p": 22, "n": 1, "d": 1.15}, {"p": 33, "n": 22, "d": 3.4}, {"p": 34, "n": 89, "d": 8.16}, {"p": 35, "n": 2, "d": 0.45}, {"p": 38, "n": 18, "d": 4.09}, {"p": 103, "n": 22, "d": 5.13}, {"p": 999, "n": 40, "d": 3.67}]}, "constraint graph": {"d": "constraint propagation graph", "b": 34, "l": 999, "m": 12, "s": 2, "t": 0, "cv": 0.812, "tb": "ACTIVE", "gp": "CONVERSATION", "tl": [{"p": 34, "n": 10, "d": 2.82}, {"p": 999, "n": 2, "d": 0.29}]}, "convergence": {"d": "learning convergence", "b": 34, "l": 34, "m": 15, "s": 1, "t": 0, "cv": 0.0, "tb": "ACTIVE", "gp": "CONVERSATION", "tl": [{"p": 34, "n": 15, "d": 4.24}]}, "stability": {"d": "stability metric", "b": -1, "l": 999, "m": 33, "s": 6, "t": -0.852, "cv": 1.188, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": -1, "n": 1, "d": 0.73}, {"p": 34, "n": 21, "d": 5.93}, {"p": 36, "n": 7, "d": 0.72}, {"p": 37, "n": 1, "d": 1.5}, {"p": 105, "n": 1, "d": 0.18}, {"p": 999, "n": 2, "d": 0.8}]}, "pruning": {"d": "graph pruning", "b": 30, "l": 999, "m": 13, "s": 3, "t": 4.338, "cv": 0.686, "tb": "ACTIVE", "gp": "CONVERSATION", "tl": [{"p": 30, "n": 1, "d": 0.45}, {"p": 34, "n": 6, "d": 0.84}, {"p": 999, "n": 6, "d": 2.4}]}, "kernel": {"d": "kernel layer", "b": -5, "l": 999, "m": 1263, "s": 36, "t": -0.284, "cv": 1.329, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -5, "n": 16, "d": 8.48}, {"p": -4, "n": 23, "d": 3.46}, {"p": -3, "n": 11, "d": 6.14}, {"p": -1, "n": 7, "d": 1.99}, {"p": 0, "n": 6, "d": 2.12}, {"p": 1, "n": 2, "d": 1.88}, {"p": 2, "n": 5, "d": 1.56}, {"p": 3, "n": 74, "d": 7.68}, {"p": 4, "n": 25, "d": 4.14}, {"p": 5, "n": 48, "d": 6.57}, {"p": 6, "n": 61, "d": 12.76}, {"p": 7, "n": 68, "d": 11.25}, {"p": 9, "n": 5, "d": 0.82}, {"p": 10, "n": 4, "d": 1.02}, {"p": 11, "n": 7, "d": 1.86}, {"p": 12, "n": 25, "d": 3.46}, {"p": 13, "n": 1, "d": 0.49}, {"p": 14, "n": 1, "d": 0.48}, {"p": 18, "n": 4, "d": 1.44}, {"p": 22, "n": 1, "d": 0.36}, {"p": 26, "n": 124, "d": 3.06}, {"p": 27, "n": 1, "d": 0.32}, {"p": 28, "n": 4, "d": 0.64}, {"p": 29, "n": 7, "d": 0.98}, {"p": 30, "n": 383, "d": 8.03}, {"p": 31, "n": 6, "d": 2.84}, {"p": 32, "n": 14, "d": 2.73}, {"p": 33, "n": 10, "d": 1.49}, {"p": 34, "n": 9, "d": 1.12}, {"p": 36, "n": 16, "d": 0.77}, {"p": 37, "n": 87, "d": 25.67}, {"p": 50, "n": 4, "d": 1.34}, {"p": 101, "n": 1, "d": 0.23}, {"p": 103, "n": 1, "d": 0.23}, {"p": 104, "n": 5, "d": 0.93}, {"p": 999, "n": 197, "d": 3.29}]}, "wasm": {"d": "WebAssembly target", "b": -5, "l": 999, "m": 1142, "s": 36, "t": -0.668, "cv": 1.322, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": -5, "n": 6, "d": 3.18}, {"p": -4, "n": 9, "d": 1.36}, {"p": -3, "n": 6, "d": 3.35}, {"p": -1, "n": 11, "d": 2.93}, {"p": 0, "n": 34, "d": 14.35}, {"p": 1, "n": 11, "d": 4.3}, {"p": 2, "n": 50, "d": 15.31}, {"p": 3, "n": 78, "d": 9.19}, {"p": 4, "n": 23, "d": 3.93}, {"p": 5, "n": 83, "d": 11.61}, {"p": 6, "n": 111, "d": 11.94}, {"p": 7, "n": 114, "d": 17.51}, {"p": 9, "n": 5, "d": 0.82}, {"p": 10, "n": 4, "d": 1.4}, {"p": 11, "n": 1, "d": 0.52}, {"p": 12, "n": 38, "d": 8.05}, {"p": 13, "n": 3, "d": 0.74}, {"p": 14, "n": 3, "d": 1.35}, {"p": 18, "n": 3, "d": 1.08}, {"p": 21, "n": 2, "d": 1.0}, {"p": 22, "n": 3, "d": 1.09}, {"p": 26, "n": 144, "d": 3.86}, {"p": 27, "n": 2, "d": 0.31}, {"p": 28, "n": 3, "d": 0.49}, {"p": 29, "n": 7, "d": 1.74}, {"p": 30, "n": 213, "d": 22.24}, {"p": 31, "n": 1, "d": 0.47}, {"p": 32, "n": 1, "d": 0.2}, {"p": 33, "n": 8, "d": 1.37}, {"p": 34, "n": 5, "d": 0.62}, {"p": 35, "n": 1, "d": 0.22}, {"p": 36, "n": 5, "d": 0.58}, {"p": 37, "n": 1, "d": 0.38}, {"p": 38, "n": 3, "d": 1.17}, {"p": 104, "n": 3, "d": 0.56}, {"p": 999, "n": 147, "d": 3.33}]}, "ffi": {"d": "foreign function interface", "b": -5, "l": 999, "m": 1021, "s": 37, "t": -0.556, "cv": 1.03, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": -5, "n": 1, "d": 0.53}, {"p": -4, "n": 20, "d": 3.01}, {"p": -3, "n": 13, "d": 7.25}, {"p": 0, "n": 4, "d": 2.11}, {"p": 1, "n": 4, "d": 2.37}, {"p": 4, "n": 43, "d": 7.65}, {"p": 5, "n": 1, "d": 0.19}, {"p": 6, "n": 12, "d": 1.62}, {"p": 7, "n": 28, "d": 4.9}, {"p": 8, "n": 8, "d": 1.79}, {"p": 9, "n": 4, "d": 1.62}, {"p": 10, "n": 19, "d": 11.69}, {"p": 11, "n": 3, "d": 0.8}, {"p": 12, "n": 7, "d": 1.84}, {"p": 13, "n": 3, "d": 0.74}, {"p": 14, "n": 1, "d": 1.74}, {"p": 18, "n": 11, "d": 3.97}, {"p": 20, "n": 6, "d": 1.53}, {"p": 21, "n": 5, "d": 1.16}, {"p": 22, "n": 1, "d": 0.36}, {"p": 26, "n": 32, "d": 1.72}, {"p": 27, "n": 10, "d": 1.57}, {"p": 28, "n": 7, "d": 1.12}, {"p": 29, "n": 22, "d": 2.66}, {"p": 30, "n": 462, "d": 10.15}, {"p": 31, "n": 1, "d": 0.47}, {"p": 32, "n": 10, "d": 1.95}, {"p": 33, "n": 3, "d": 0.55}, {"p": 34, "n": 18, "d": 1.62}, {"p": 35, "n": 11, "d": 2.47}, {"p": 36, "n": 87, "d": 2.93}, {"p": 38, "n": 3, "d": 0.79}, {"p": 50, "n": 12, "d": 4.03}, {"p": 101, "n": 1, "d": 0.23}, {"p": 102, "n": 6, "d": 1.21}, {"p": 103, "n": 4, "d": 0.93}, {"p": 999, "n": 138, "d": 2.68}]}, "host function": {"d": "host function dispatch", "b": -1, "l": 999, "m": 303, "s": 19, "t": -0.662, "cv": 1.07, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": -1, "n": 1, "d": 0.73}, {"p": 1, "n": 1, "d": 0.59}, {"p": 2, "n": 7, "d": 2.11}, {"p": 3, "n": 6, "d": 0.82}, {"p": 4, "n": 2, "d": 0.36}, {"p": 5, "n": 27, "d": 5.63}, {"p": 6, "n": 26, "d": 2.7}, {"p": 7, "n": 8, "d": 1.25}, {"p": 12, "n": 1, "d": 3.17}, {"p": 26, "n": 151, "d": 8.37}, {"p": 27, "n": 12, "d": 1.88}, {"p": 28, "n": 14, "d": 2.25}, {"p": 29, "n": 15, "d": 2.43}, {"p": 30, "n": 2, "d": 0.87}, {"p": 32, "n": 2, "d": 0.39}, {"p": 34, "n": 1, "d": 0.24}, {"p": 36, "n": 1, "d": 0.37}, {"p": 104, "n": 1, "d": 0.19}, {"p": 999, "n": 25, "d": 1.41}]}, "isolation": {"d": "kernel isolation", "b": -3, "l": 999, "m": 76, "s": 13, "t": -0.65, "cv": 0.891, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": -3, "n": 6, "d": 3.35}, {"p": 11, "n": 4, "d": 1.06}, {"p": 12, "n": 3, "d": 0.85}, {"p": 15, "n": 7, "d": 1.96}, {"p": 16, "n": 1, "d": 0.43}, {"p": 26, "n": 26, "d": 0.93}, {"p": 30, "n": 2, "d": 0.26}, {"p": 31, "n": 1, "d": 0.47}, {"p": 36, "n": 1, "d": 0.24}, {"p": 38, "n": 1, "d": 0.95}, {"p": 50, "n": 2, "d": 0.67}, {"p": 103, "n": 1, "d": 0.23}, {"p": 999, "n": 21, "d": 0.67}]}, "semantic object": {"d": "semantic object primitive", "b": -4, "l": 999, "m": 297, "s": 33, "t": -0.17, "cv": 0.637, "tb": "ACTIVE", "gp": "LISP", "tl": [{"p": -4, "n": 8, "d": 1.2}, {"p": -3, "n": 3, "d": 1.67}, {"p": -1, "n": 1, "d": 0.73}, {"p": 1, "n": 2, "d": 1.18}, {"p": 2, "n": 2, "d": 1.16}, {"p": 4, "n": 3, "d": 1.22}, {"p": 6, "n": 8, "d": 1.44}, {"p": 7, "n": 2, "d": 0.46}, {"p": 8, "n": 12, "d": 2.72}, {"p": 9, "n": 2, "d": 0.81}, {"p": 10, "n": 8, "d": 2.01}, {"p": 13, "n": 4, "d": 0.99}, {"p": 14, "n": 15, "d": 1.31}, {"p": 15, "n": 1, "d": 0.54}, {"p": 16, "n": 1, "d": 0.43}, {"p": 17, "n": 4, "d": 1.08}, {"p": 18, "n": 14, "d": 1.64}, {"p": 19, "n": 2, "d": 0.42}, {"p": 20, "n": 5, "d": 1.27}, {"p": 22, "n": 1, "d": 0.36}, {"p": 23, "n": 1, "d": 0.33}, {"p": 26, "n": 19, "d": 0.81}, {"p": 27, "n": 8, "d": 1.25}, {"p": 28, "n": 11, "d": 1.77}, {"p": 29, "n": 3, "d": 0.39}, {"p": 30, "n": 6, "d": 0.6}, {"p": 33, "n": 1, "d": 0.27}, {"p": 34, "n": 2, "d": 0.25}, {"p": 35, "n": 4, "d": 0.9}, {"p": 36, "n": 53, "d": 1.54}, {"p": 50, "n": 10, "d": 3.36}, {"p": 102, "n": 2, "d": 0.4}, {"p": 999, "n": 79, "d": 1.38}]}, "flow": {"d": "conversation flow", "b": -4, "l": 999, "m": 1301, "s": 39, "t": -0.772, "cv": 1.287, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": -4, "n": 110, "d": 16.56}, {"p": -3, "n": 6, "d": 3.35}, {"p": 3, "n": 36, "d": 4.43}, {"p": 4, "n": 1, "d": 0.41}, {"p": 6, "n": 4, "d": 0.8}, {"p": 7, "n": 3, "d": 1.86}, {"p": 8, "n": 3, "d": 0.67}, {"p": 9, "n": 156, "d": 25.34}, {"p": 10, "n": 76, "d": 13.4}, {"p": 11, "n": 12, "d": 2.73}, {"p": 12, "n": 9, "d": 1.48}, {"p": 13, "n": 62, "d": 15.3}, {"p": 14, "n": 46, "d": 4.0}, {"p": 15, "n": 7, "d": 1.82}, {"p": 16, "n": 14, "d": 3.62}, {"p": 17, "n": 29, "d": 7.12}, {"p": 18, "n": 107, "d": 11.36}, {"p": 19, "n": 64, "d": 13.56}, {"p": 20, "n": 17, "d": 2.89}, {"p": 21, "n": 27, "d": 6.34}, {"p": 22, "n": 1, "d": 1.15}, {"p": 23, "n": 6, "d": 1.99}, {"p": 26, "n": 94, "d": 2.48}, {"p": 27, "n": 2, "d": 0.31}, {"p": 28, "n": 16, "d": 2.55}, {"p": 29, "n": 8, "d": 1.04}, {"p": 30, "n": 131, "d": 5.14}, {"p": 31, "n": 21, "d": 4.41}, {"p": 32, "n": 1, "d": 0.2}, {"p": 33, "n": 1, "d": 0.27}, {"p": 34, "n": 4, "d": 1.13}, {"p": 36, "n": 42, "d": 1.37}, {"p": 37, "n": 4, "d": 1.33}, {"p": 38, "n": 7, "d": 1.08}, {"p": 50, "n": 4, "d": 1.34}, {"p": 101, "n": 2, "d": 0.46}, {"p": 103, "n": 1, "d": 0.23}, {"p": 105, "n": 2, "d": 0.37}, {"p": 999, "n": 165, "d": 3.29}]}, "flow runner": {"d": "FlowRunner execution", "b": 9, "l": 26, "m": 7, "s": 3, "t": 0.509, "cv": 0.165, "tb": "ACTIVE", "gp": "LISP", "tl": [{"p": 9, "n": 2, "d": 0.48}, {"p": 10, "n": 1, "d": 0.62}, {"p": 26, "n": 4, "d": 0.73}]}, "evidence": {"d": "evidence chain", "b": -4, "l": 999, "m": 530, "s": 22, "t": -0.421, "cv": 0.949, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -4, "n": 15, "d": 2.26}, {"p": -3, "n": 1, "d": 0.56}, {"p": 6, "n": 6, "d": 1.33}, {"p": 8, "n": 9, "d": 2.09}, {"p": 9, "n": 1, "d": 0.56}, {"p": 10, "n": 24, "d": 4.99}, {"p": 12, "n": 50, "d": 7.83}, {"p": 13, "n": 2, "d": 1.0}, {"p": 14, "n": 11, "d": 1.36}, {"p": 17, "n": 37, "d": 9.05}, {"p": 18, "n": 56, "d": 5.62}, {"p": 19, "n": 11, "d": 2.33}, {"p": 20, "n": 8, "d": 2.04}, {"p": 26, "n": 6, "d": 0.8}, {"p": 28, "n": 6, "d": 1.9}, {"p": 29, "n": 7, "d": 0.92}, {"p": 30, "n": 1, "d": 0.21}, {"p": 32, "n": 1, "d": 0.2}, {"p": 36, "n": 171, "d": 4.65}, {"p": 38, "n": 13, "d": 2.54}, {"p": 102, "n": 4, "d": 0.81}, {"p": 999, "n": 90, "d": 2.05}]}, "patch": {"d": "state patch", "b": -5, "l": 999, "m": 1177, "s": 34, "t": 0.557, "cv": 1.109, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -5, "n": 2, "d": 1.06}, {"p": -4, "n": 29, "d": 4.37}, {"p": -3, "n": 2, "d": 1.12}, {"p": 3, "n": 22, "d": 2.39}, {"p": 4, "n": 5, "d": 0.82}, {"p": 5, "n": 6, "d": 1.16}, {"p": 6, "n": 4, "d": 0.64}, {"p": 8, "n": 34, "d": 7.83}, {"p": 9, "n": 26, "d": 4.04}, {"p": 10, "n": 47, "d": 14.66}, {"p": 11, "n": 1, "d": 0.52}, {"p": 13, "n": 1, "d": 0.49}, {"p": 14, "n": 9, "d": 2.23}, {"p": 16, "n": 4, "d": 1.01}, {"p": 17, "n": 36, "d": 8.68}, {"p": 18, "n": 73, "d": 7.78}, {"p": 19, "n": 19, "d": 4.02}, {"p": 20, "n": 40, "d": 5.11}, {"p": 26, "n": 78, "d": 2.03}, {"p": 27, "n": 2, "d": 0.62}, {"p": 28, "n": 8, "d": 1.28}, {"p": 29, "n": 7, "d": 0.91}, {"p": 30, "n": 68, "d": 1.71}, {"p": 31, "n": 6, "d": 1.61}, {"p": 32, "n": 1, "d": 0.2}, {"p": 33, "n": 1, "d": 0.27}, {"p": 34, "n": 59, "d": 7.53}, {"p": 35, "n": 64, "d": 14.38}, {"p": 36, "n": 126, "d": 3.85}, {"p": 37, "n": 3, "d": 1.15}, {"p": 38, "n": 85, "d": 8.33}, {"p": 50, "n": 51, "d": 17.12}, {"p": 104, "n": 3, "d": 0.56}, {"p": 999, "n": 255, "d": 5.11}]}, "octave": {"d": "octave memory hierarchy", "b": -3, "l": 27, "m": 251, "s": 5, "t": -0.432, "cv": 1.527, "tb": "OSCILLATING", "gp": "CLI", "tl": [{"p": -3, "n": 3, "d": 1.67}, {"p": 6, "n": 215, "d": 37.22}, {"p": 7, "n": 27, "d": 5.71}, {"p": 26, "n": 3, "d": 0.64}, {"p": 27, "n": 3, "d": 0.95}]}, "docker": {"d": "Docker deployment", "b": -3, "l": 999, "m": 388, "s": 10, "t": 0.166, "cv": 1.13, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -3, "n": 5, "d": 2.79}, {"p": 22, "n": 1, "d": 1.06}, {"p": 26, "n": 100, "d": 4.42}, {"p": 30, "n": 140, "d": 15.37}, {"p": 37, "n": 1, "d": 0.38}, {"p": 101, "n": 90, "d": 20.9}, {"p": 103, "n": 17, "d": 3.97}, {"p": 104, "n": 4, "d": 0.74}, {"p": 105, "n": 6, "d": 1.1}, {"p": 999, "n": 24, "d": 7.79}]}, "node": {"d": "sovereign node", "b": -5, "l": 999, "m": 1923, "s": 41, "t": 0.268, "cv": 1.183, "tb": "ACTIVE", "gp": "CLI", "tl": [{"p": -5, "n": 21, "d": 11.13}, {"p": -4, "n": 25, "d": 3.76}, {"p": -3, "n": 15, "d": 8.37}, {"p": -1, "n": 8, "d": 2.02}, {"p": 2, "n": 1, "d": 0.58}, {"p": 3, "n": 1, "d": 0.2}, {"p": 5, "n": 2, "d": 0.47}, {"p": 6, "n": 4, "d": 0.74}, {"p": 7, "n": 3, "d": 1.11}, {"p": 9, "n": 11, "d": 1.89}, {"p": 10, "n": 24, "d": 15.29}, {"p": 12, "n": 11, "d": 3.89}, {"p": 13, "n": 20, "d": 4.93}, {"p": 14, "n": 27, "d": 4.04}, {"p": 15, "n": 10, "d": 2.4}, {"p": 16, "n": 2, "d": 0.51}, {"p": 17, "n": 30, "d": 7.26}, {"p": 18, "n": 1, "d": 0.36}, {"p": 19, "n": 4, "d": 0.85}, {"p": 20, "n": 5, "d": 1.27}, {"p": 22, "n": 15, "d": 3.36}, {"p": 23, "n": 50, "d": 16.55}, {"p": 24, "n": 4, "d": 8.91}, {"p": 26, "n": 907, "d": 16.12}, {"p": 27, "n": 2, "d": 0.31}, {"p": 28, "n": 1, "d": 0.33}, {"p": 29, "n": 4, "d": 1.04}, {"p": 30, "n": 180, "d": 7.18}, {"p": 31, "n": 113, "d": 25.59}, {"p": 33, "n": 11, "d": 2.95}, {"p": 34, "n": 51, "d": 4.58}, {"p": 35, "n": 15, "d": 3.37}, {"p": 36, "n": 56, "d": 1.8}, {"p": 37, "n": 24, "d": 5.18}, {"p": 38, "n": 5, "d": 0.81}, {"p": 50, "n": 1, "d": 0.34}, {"p": 101, "n": 56, "d": 13.01}, {"p": 102, "n": 1, "d": 0.2}, {"p": 103, "n": 8, "d": 1.87}, {"p": 105, "n": 37, "d": 6.8}, {"p": 999, "n": 157, "d": 2.47}]}, "bootstrap": {"d": "node bootstrap", "b": -5, "l": 999, "m": 64, "s": 9, "t": -0.517, "cv": 0.809, "tb": "AFFINE", "gp": "CLI", "tl": [{"p": -5, "n": 2, "d": 1.06}, {"p": -3, "n": 3, "d": 1.67}, {"p": 14, "n": 1, "d": 0.24}, {"p": 26, "n": 36, "d": 1.19}, {"p": 30, "n": 14, "d": 2.7}, {"p": 34, "n": 1, "d": 0.24}, {"p": 36, "n": 3, "d": 0.5}, {"p": 101, "n": 2, "d": 0.46}, {"p": 999, "n": 2, "d": 0.47}]}, "self-hosting": {"d": "self-hosted deployment", "b": -5, "l": 999, "m": 7, "s": 3, "t": 0.51, "cv": 0.462, "tb": "ACTIVE", "gp": "LISP", "tl": [{"p": -5, "n": 1, "d": 0.53}, {"p": 22, "n": 4, "d": 1.59}, {"p": 999, "n": 2, "d": 0.8}]}}};

// ─── Navigation ───────────────────────────────────────────────────────────
const tabs = [
  { id: 'topology', label: 'Force Graph' },
  { id: 'attractors', label: 'Attractors' },
  { id: 'threads', label: 'Stable Threads' },
  { id: 'gradient', label: 'Compression Gradient' },
  { id: 'lifecycles', label: 'Lifecycles' },
  { id: 'oscillating', label: 'Oscillating' },
  { id: 'similarity', label: 'Unexpected Similarities' },
];

const nav = document.getElementById('nav');
tabs.forEach(tab => {
  const btn = document.createElement('button');
  btn.textContent = tab.label;
  btn.dataset.panel = tab.id;
  if (tab.id === 'topology') btn.classList.add('active');
  btn.onclick = () => {
    document.querySelectorAll('nav button').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
    btn.classList.add('active');
    document.getElementById('panel-' + tab.id).classList.add('active');
  };
  nav.appendChild(btn);
});

// ─── Stats ────────────────────────────────────────────────────────────────
const statsRow = document.getElementById('stats-row');
const stats = DATA.corpus_stats;
[
  { val: stats.total_docs, label: 'Documents' },
  { val: stats.total_lines.toLocaleString(), label: 'Total Lines' },
  { val: Object.keys(DATA.lifecycles).length, label: 'Tracked Concepts' },
  { val: DATA.stable_threads.length, label: 'Stable Threads' },
  { val: DATA.attractors.length, label: 'Attractors' },
].forEach(s => {
  const d = document.createElement('div');
  d.className = 'stat';
  d.innerHTML = `<div class="val">${s.val}</div><div class="label">${s.label}</div>`;
  statsRow.appendChild(d);
});

// ─── Color helpers ────────────────────────────────────────────────────────
const typeColors = {
  RELEVANT: '#34d399', ACTIVE: '#60a5fa', AFFINE: '#fbbf24',
  OSCILLATING: '#f87171', LINEAR: '#9ca3af',
};
const gradientColors = {
  FORTH: '#34d399', LISP: '#60a5fa', CLI: '#fbbf24', CONVERSATION: '#f87171',
};

// ─── Panel: Force Graph (Topology) ────────────────────────────────────────
function buildTopologyPanel() {
  const panel = document.getElementById('panel-topology');
  panel.innerHTML = `
    <div class="section-title">Concept Topology — Force-Directed Graph</div>
    <div class="section-desc">
      Node size = attractor score. Node color = substructural type behavior.
      Edges = Paskian stable threads (co-occurrence × stability × span).
      Thicker/brighter edges = stronger architectural coupling.
    </div>
    <div class="force-container">
      <canvas id="force-canvas"></canvas>
      <div class="force-legend">
        <div><span class="dot" style="background:#34d399"></span> RELEVANT (stable, persistent)</div>
        <div><span class="dot" style="background:#60a5fa"></span> ACTIVE (still evolving)</div>
        <div><span class="dot" style="background:#fbbf24"></span> AFFINE (declining)</div>
        <div><span class="dot" style="background:#f87171"></span> OSCILLATING (unstable)</div>
        <div style="margin-top:6px; color:#9ca3af">Edge brightness = Paskian score</div>
      </div>
    </div>
  `;

  const canvas = document.getElementById('force-canvas');
  const container = canvas.parentElement;
  const dpr = window.devicePixelRatio || 1;
  canvas.width = container.clientWidth * dpr;
  canvas.height = container.clientHeight * dpr;
  canvas.style.width = container.clientWidth + 'px';
  canvas.style.height = container.clientHeight + 'px';
  const ctx = canvas.getContext('2d');
  ctx.scale(dpr, dpr);
  const W = container.clientWidth;
  const H = container.clientHeight;

  // Build nodes from attractors + lifecycles
  const nodeMap = {};
  DATA.attractors.forEach(a => {
    const lc = DATA.lifecycles[a.concept];
    if (!lc) return;
    nodeMap[a.concept] = {
      id: a.concept,
      label: a.concept,
      score: a.score,
      r: Math.max(8, Math.sqrt(a.score) * 2.5),
      color: typeColors[lc.tb] || '#9ca3af',
      type: lc.tb,
      gradient: lc.gp,
      x: W/2 + (Math.random() - 0.5) * W * 0.6,
      y: H/2 + (Math.random() - 0.5) * H * 0.6,
      vx: 0, vy: 0,
    };
  });

  // Add nodes for thread endpoints not in attractors
  DATA.stable_threads.forEach(t => {
    [t.concept_a, t.concept_b].forEach(c => {
      if (!nodeMap[c]) {
        const lc = DATA.lifecycles[c];
        if (!lc) return;
        nodeMap[c] = {
          id: c, label: c, score: 5,
          r: 6, color: typeColors[lc.tb] || '#9ca3af',
          type: lc.tb, gradient: lc.gp,
          x: W/2 + (Math.random() - 0.5) * W * 0.6,
          y: H/2 + (Math.random() - 0.5) * H * 0.6,
          vx: 0, vy: 0,
        };
      }
    });
  });

  const nodes = Object.values(nodeMap);
  const edges = DATA.stable_threads.filter(t => nodeMap[t.concept_a] && nodeMap[t.concept_b])
    .map(t => ({
      source: nodeMap[t.concept_a],
      target: nodeMap[t.concept_b],
      weight: t.paskian_score,
    }));

  // Simple force simulation
  const maxWeight = Math.max(...edges.map(e => e.weight), 1);

  function simulate() {
    // Repulsion
    for (let i = 0; i < nodes.length; i++) {
      for (let j = i + 1; j < nodes.length; j++) {
        let dx = nodes[j].x - nodes[i].x;
        let dy = nodes[j].y - nodes[i].y;
        let d = Math.sqrt(dx*dx + dy*dy) || 1;
        let force = 800 / (d * d);
        let fx = dx / d * force;
        let fy = dy / d * force;
        nodes[i].vx -= fx; nodes[i].vy -= fy;
        nodes[j].vx += fx; nodes[j].vy += fy;
      }
    }

    // Attraction (edges)
    edges.forEach(e => {
      let dx = e.target.x - e.source.x;
      let dy = e.target.y - e.source.y;
      let d = Math.sqrt(dx*dx + dy*dy) || 1;
      let force = (d - 80) * 0.005 * (e.weight / maxWeight);
      let fx = dx / d * force;
      let fy = dy / d * force;
      e.source.vx += fx; e.source.vy += fy;
      e.target.vx -= fx; e.target.vy -= fy;
    });

    // Center gravity
    nodes.forEach(n => {
      n.vx += (W/2 - n.x) * 0.001;
      n.vy += (H/2 - n.y) * 0.001;
    });

    // Update positions
    nodes.forEach(n => {
      n.vx *= 0.85;
      n.vy *= 0.85;
      n.x += n.vx;
      n.y += n.vy;
      n.x = Math.max(n.r, Math.min(W - n.r, n.x));
      n.y = Math.max(n.r, Math.min(H - n.r, n.y));
    });
  }

  function draw() {
    ctx.clearRect(0, 0, W, H);

    // Edges
    edges.forEach(e => {
      const alpha = 0.15 + 0.6 * (e.weight / maxWeight);
      const width = 0.5 + 2.5 * (e.weight / maxWeight);
      ctx.beginPath();
      ctx.moveTo(e.source.x, e.source.y);
      ctx.lineTo(e.target.x, e.target.y);
      ctx.strokeStyle = `rgba(96, 165, 250, ${alpha})`;
      ctx.lineWidth = width;
      ctx.stroke();
    });

    // Nodes
    nodes.forEach(n => {
      // Glow
      ctx.beginPath();
      ctx.arc(n.x, n.y, n.r + 4, 0, Math.PI * 2);
      ctx.fillStyle = n.color + '22';
      ctx.fill();

      // Circle
      ctx.beginPath();
      ctx.arc(n.x, n.y, n.r, 0, Math.PI * 2);
      ctx.fillStyle = n.color + 'cc';
      ctx.fill();
      ctx.strokeStyle = n.color;
      ctx.lineWidth = 1.5;
      ctx.stroke();

      // Label
      ctx.fillStyle = '#e5e7eb';
      ctx.font = `${Math.max(9, n.r * 0.8)}px 'SF Mono', monospace`;
      ctx.textAlign = 'center';
      ctx.fillText(n.label, n.x, n.y + n.r + 14);
    });
  }

  let frame = 0;
  function tick() {
    simulate();
    draw();
    frame++;
    if (frame < 300) requestAnimationFrame(tick);
  }
  tick();

  // Tooltip on hover
  canvas.addEventListener('mousemove', (e) => {
    const rect = canvas.getBoundingClientRect();
    const mx = e.clientX - rect.left;
    const my = e.clientY - rect.top;
    const tooltip = document.getElementById('tooltip');
    let hit = null;
    for (const n of nodes) {
      const dx = mx - n.x, dy = my - n.y;
      if (dx*dx + dy*dy < (n.r + 4) * (n.r + 4)) { hit = n; break; }
    }
    if (hit) {
      const lc = DATA.lifecycles[hit.id];
      tooltip.style.display = 'block';
      tooltip.style.left = (e.clientX + 12) + 'px';
      tooltip.style.top = (e.clientY + 12) + 'px';
      tooltip.innerHTML = `
        <strong>${hit.label}</strong><br>
        ${lc ? lc.d : ''}<br><br>
        Type: <span style="color:${hit.color}">${hit.type}</span><br>
        Gradient: ${hit.gradient}<br>
        Attractor score: ${hit.score.toFixed(1)}<br>
        ${lc ? `Mentions: ${lc.m} | Span: ${lc.s} phases | CV: ${lc.cv.toFixed(2)}` : ''}
      `;
    } else {
      tooltip.style.display = 'none';
    }
  });
}

// ─── Panel: Attractors ────────────────────────────────────────────────────
function buildAttractorsPanel() {
  const panel = document.getElementById('panel-attractors');
  let html = `
    <div class="section-title">Architectural Attractors</div>
    <div class="section-desc">
      Concepts with the highest weighted degree in the Paskian stable thread graph.
      These are the load-bearing architectural ideas — the ones that pull everything else toward them.
      Score = sum of Paskian stability scores across all stable threads involving this concept.
    </div>
    <div class="card-grid">
  `;

  DATA.attractors.forEach((a, i) => {
    const lc = DATA.lifecycles[a.concept] || {};
    const barW = Math.round(a.score / DATA.attractors[0].score * 100);
    html += `
      <div class="card">
        <div class="name">${i+1}. ${a.concept}</div>
        <div class="desc">${a.description}</div>
        <div style="height:4px;background:var(--bg3);border-radius:2px;margin:8px 0">
          <div style="height:4px;width:${barW}%;background:${typeColors[lc.tb] || '#60a5fa'};border-radius:2px"></div>
        </div>
        <div class="metrics">
          <div class="metric">Score: <span class="mv">${a.score.toFixed(1)}</span></div>
          <div class="metric">Type: <span class="mv badge ${lc.tb}">${lc.tb}</span></div>
          <div class="metric">Gradient: <span class="mv badge ${lc.gp}">${lc.gp}</span></div>
          <div class="metric">Mentions: <span class="mv">${lc.m || '?'}</span></div>
          <div class="metric">Span: <span class="mv">${lc.s || '?'}</span> phases</div>
        </div>
      </div>
    `;
  });

  html += '</div>';
  panel.innerHTML = html;
}

// ─── Panel: Stable Threads ────────────────────────────────────────────────
function buildThreadsPanel() {
  const panel = document.getElementById('panel-threads');
  let html = `
    <div class="section-title">Paskian Stable Threads</div>
    <div class="section-desc">
      Concept pairs whose co-occurrence is strong, whose individual density is stable (low CV),
      and whose joint appearance spans many phases. These are the architectural invariants —
      the concept pairs that the system cannot decouple without breaking something fundamental.
      Score = edge_weight × (1/CV) × log(span).
    </div>
    <div class="thread-list">
  `;

  const maxScore = DATA.stable_threads[0]?.paskian_score || 1;
  DATA.stable_threads.forEach((t, i) => {
    const barW = Math.round(t.paskian_score / maxScore * 100);
    html += `
      <div class="thread">
        <div style="min-width:24px;color:var(--text2);font-size:11px">${i+1}</div>
        <div class="concepts">
          <span class="concept-tag">${t.concept_a}</span>
          <span class="arrow">↔</span>
          <span class="concept-tag">${t.concept_b}</span>
        </div>
        <div style="flex:1;max-width:200px;height:3px;background:var(--bg3);border-radius:2px">
          <div style="height:3px;width:${barW}%;background:var(--accent);border-radius:2px"></div>
        </div>
        <div class="score" style="color:var(--accent)">${t.paskian_score.toFixed(3)}</div>
        <div style="color:var(--text2);font-size:11px;min-width:100px">
          w=${t.edge_weight} cv=${t.combined_stability} s=${t.combined_span}
        </div>
      </div>
    `;
  });

  html += '</div>';
  panel.innerHTML = html;
}

// ─── Panel: Compression Gradient ──────────────────────────────────────────
function buildGradientPanel() {
  const panel = document.getElementById('panel-gradient');
  const levels = ['FORTH', 'LISP', 'CLI', 'CONVERSATION'];
  const levelDescs = {
    FORTH: 'Foundational, stable, executable. These concepts have achieved maximum compression — they are architectural axioms.',
    LISP: 'Committed, compositional. Stable enough to build on, but still being composed into higher structures.',
    CLI: 'Committed but still being refined. The concept is established but its boundaries are still moving.',
    CONVERSATION: 'Exploratory, recent. Still discovering what this concept means in the system.',
  };

  let html = `
    <div class="section-title">Compression Gradient Position</div>
    <div class="section-desc">
      Where each concept sits on the Semantos compression gradient.
      Conversation → CLI → Lisp → Forth mirrors discovery → commitment → composition → execution.
      Position is determined by: birth phase (earlier = deeper), stability (lower CV = deeper), and span.
    </div>
    <div class="gradient-container">
  `;

  levels.forEach(level => {
    const group = DATA.gradient[level];
    if (!group) return;
    html += `
      <div class="gradient-col">
        <div class="gradient-header ${level}">${level} (${group.count})</div>
        <div class="gradient-body">
          <div style="font-size:11px;color:var(--text2);margin-bottom:8px">${levelDescs[level]}</div>
    `;
    group.concepts.forEach(c => {
      html += `<div class="gradient-item"><span>${c.concept}</span><span class="cv">CV: ${c.stability_cv.toFixed(2)}</span></div>`;
    });
    html += '</div></div>';
  });

  html += '</div>';
  panel.innerHTML = html;
}

// ─── Panel: Lifecycles ────────────────────────────────────────────────────
function buildLifecyclesPanel() {
  const panel = document.getElementById('panel-lifecycles');
  let html = `
    <div class="section-title">Concept Lifecycles</div>
    <div class="section-desc">
      Each concept's mention density over time (by phase). The sparkline shows how the concept
      waxes and wanes through the PRD history. Type behavior and gradient position are inferred
      from the lifecycle shape.
    </div>
    <div style="background:var(--bg2);border:1px solid var(--bg3);border-radius:8px;overflow:hidden">
      <div class="sparkline-row" style="background:var(--bg3)">
        <div class="label" style="font-weight:600">Concept</div>
        <div class="badges" style="font-weight:600">Type / Gradient</div>
        <div style="flex:1;font-weight:600;font-size:11px">Density over Phases →</div>
        <div style="min-width:60px;font-weight:600;font-size:11px;text-align:right">Mentions</div>
      </div>
  `;

  // Sort by attractor score (total mentions × span)
  const sorted = Object.entries(DATA.lifecycles)
    .sort((a, b) => b[1].m * b[1].s - a[1].m * a[1].s)
    .slice(0, 40);

  sorted.forEach(([concept, lc], idx) => {
    html += `
      <div class="sparkline-row">
        <div class="label">${concept}</div>
        <div class="badges">
          <span class="badge ${lc.tb}">${lc.tb}</span>
          <span class="badge ${lc.gp}">${lc.gp}</span>
        </div>
        <canvas id="spark-${idx}" height="28"></canvas>
        <div style="min-width:60px;text-align:right;font-size:12px;font-weight:600">${lc.m.toLocaleString()}</div>
      </div>
    `;
  });

  html += '</div>';
  panel.innerHTML = html;

  // Draw sparklines
  sorted.forEach(([concept, lc], idx) => {
    const canvas = document.getElementById('spark-' + idx);
    if (!canvas || !lc.tl.length) return;
    const dpr = window.devicePixelRatio || 1;
    const w = canvas.clientWidth;
    const h = 28;
    canvas.width = w * dpr;
    canvas.height = h * dpr;
    const ctx = canvas.getContext('2d');
    ctx.scale(dpr, dpr);

    const maxD = Math.max(...lc.tl.map(t => t.d), 1);
    const color = typeColors[lc.tb] || '#60a5fa';

    ctx.beginPath();
    ctx.moveTo(0, h);
    lc.tl.forEach((t, i) => {
      const x = (i / Math.max(lc.tl.length - 1, 1)) * w;
      const y = h - (t.d / maxD) * (h - 4);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.strokeStyle = color;
    ctx.lineWidth = 1.5;
    ctx.stroke();

    // Fill under
    ctx.lineTo(w, h);
    ctx.lineTo(0, h);
    ctx.closePath();
    ctx.fillStyle = color + '18';
    ctx.fill();
  });
}

// ─── Panel: Oscillating ──────────────────────────────────────────────────
function buildOscillatingPanel() {
  const panel = document.getElementById('panel-oscillating');
  let html = `
    <div class="section-title">Oscillating Concepts</div>
    <div class="section-desc">
      Concepts with high coefficient of variation (CV > 1.0) that appear across 3+ phases.
      These are architecturally unstable — their role keeps shifting. They may indicate
      unresolved design tension, concepts being refactored, or ideas that haven't found
      their final form. In Paskian terms, these are edges that haven't converged.
    </div>
    <div class="card-grid">
  `;

  DATA.oscillating.forEach(o => {
    const lc = DATA.lifecycles[o.concept] || {};
    const trendArrow = o.trend > 0.3 ? '↑' : o.trend < -0.3 ? '↓' : '→';
    const trendColor = o.trend > 0.3 ? 'var(--green)' : o.trend < -0.3 ? 'var(--red)' : 'var(--amber)';
    html += `
      <div class="card" style="border-left: 3px solid var(--red)">
        <div class="name">${o.concept}</div>
        <div class="desc">${o.description}</div>
        <div class="metrics">
          <div class="metric">CV: <span class="mv" style="color:var(--red)">${o.stability_cv.toFixed(2)}</span></div>
          <div class="metric">Trend: <span class="mv" style="color:${trendColor}">${trendArrow} ${o.trend.toFixed(2)}</span></div>
          <div class="metric">Span: <span class="mv">${o.phase_span}</span> phases</div>
        </div>
      </div>
    `;
  });

  html += '</div>';
  panel.innerHTML = html;
}

// ─── Panel: Unexpected Similarities ───────────────────────────────────────
function buildSimilarityPanel() {
  const panel = document.getElementById('panel-similarity');
  let html = `
    <div class="section-title">Unexpected Document Similarities</div>
    <div class="section-desc">
      Document pairs with high TF-IDF cosine similarity but large phase distance (>10 phases apart).
      These reveal conceptual dependencies that aren't captured in the declared dependency graph —
      places where distant parts of the system are semantically coupled. Potential architectural debt
      or unacknowledged design influence.
    </div>
    <table class="sim-table">
      <tr><th>Document A</th><th>Document B</th><th>Similarity</th><th>Phase Gap</th></tr>
  `;

  // Filter out self-similarities
  DATA.unexpected_sims
    .filter(u => u.doc_a !== u.doc_b)
    .forEach(u => {
      const simColor = u.similarity > 0.5 ? 'var(--red)' : u.similarity > 0.3 ? 'var(--amber)' : 'var(--text)';
      html += `
        <tr>
          <td>${u.doc_a}</td>
          <td>${u.doc_b}</td>
          <td style="color:${simColor};font-weight:600">${u.similarity.toFixed(3)}</td>
          <td>${u.phase_distance.toFixed(0)} phases</td>
        </tr>
      `;
    });

  html += `</table>

    <div class="section-title">Dependency Divergences</div>
    <div class="section-desc">
      Documents where the ratio of actual cross-references to declared prerequisites is high.
      A high ratio means the document references many other docs it doesn't formally depend on —
      implicit coupling that the dependency graph doesn't capture.
    </div>
    <table class="sim-table">
      <tr><th>Document</th><th>Actual Refs</th><th>Declared Deps</th><th>Ratio</th></tr>
  `;

  DATA.divergences.forEach(d => {
    const color = d.ratio > 5 ? 'var(--red)' : d.ratio > 2 ? 'var(--amber)' : 'var(--text)';
    html += `
      <tr>
        <td>${d.filename}</td>
        <td>${d.actual_refs}</td>
        <td>${d.declared_deps}</td>
        <td style="color:${color};font-weight:600">${d.ratio.toFixed(1)}x</td>
      </tr>
    `;
  });

  html += '</table>';
  panel.innerHTML = html;
}

// ─── Build all panels ─────────────────────────────────────────────────────
buildTopologyPanel();
buildAttractorsPanel();
buildThreadsPanel();
buildGradientPanel();
buildLifecyclesPanel();
buildOscillatingPanel();
buildSimilarityPanel();
</script>
</body>
</html>
```
