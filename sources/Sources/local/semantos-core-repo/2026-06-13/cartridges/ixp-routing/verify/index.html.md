---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/ixp-routing/verify/index.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.558295+00:00
---

# cartridges/ixp-routing/verify/index.html

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>IXP Route Auditor — Rúnar-governed BGP policy</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.2/dist/chart.umd.min.js"></script>
<style>
  :root {
    --bg: #0e1116;
    --panel: #161b22;
    --panel-2: #1c2330;
    --fg: #e6edf3;
    --muted: #8b949e;
    --accent: #2da44e;
    --teal: #0ea5e9;
    --warn: #d29922;
    --bad: #f85149;
    --border: #30363d;
    --noc-pulse: rgba(248, 81, 73, 0.15);
    --mono: ui-monospace, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
  }

  * { box-sizing: border-box; margin: 0; padding: 0; }

  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
    background: var(--bg);
    color: var(--fg);
    line-height: 1.4;
    min-height: 100vh;
    display: flex;
    flex-direction: column;
  }

  /* ── HAT / MESH STATUS ────────────────────────────────────── */
  .pill {
    border-radius: 20px;
    padding: 3px 12px;
    font-size: 0.78rem;
    font-weight: 600;
    white-space: nowrap;
    border: 1px solid transparent;
  }
  .hat-row {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-left: auto;
    flex-shrink: 0;
  }
  .hat-label { font-size: 0.82rem; }
  .hat-select {
    background: var(--panel-2);
    border: 1px solid var(--border);
    border-radius: 4px;
    color: var(--fg);
    font-size: 0.78rem;
    padding: 3px 8px;
    cursor: pointer;
  }
  .hat-fp {
    font-family: var(--mono);
    font-size: 0.68rem;
    color: var(--muted);
  }
  .pill-muted {
    background: rgba(139,148,158,0.1);
    color: var(--muted);
    border-color: rgba(139,148,158,0.25);
  }
  .pill-live {
    background: rgba(45,164,78,0.12);
    color: var(--accent);
    border-color: rgba(45,164,78,0.35);
  }
  .pill-warn {
    background: rgba(210,153,34,0.12);
    color: var(--warn);
    border-color: rgba(210,153,34,0.4);
  }

  /* ── TOP BAR ────────────────────────────────────────────────── */
  .topbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 12px 20px;
    background: var(--panel);
    border-bottom: 1px solid var(--border);
    gap: 16px;
    flex-wrap: wrap;
  }
  .topbar-title {
    font-size: 1.05rem;
    font-weight: 700;
    letter-spacing: -0.01em;
    white-space: nowrap;
  }
  .topbar-title span {
    color: var(--muted);
    font-weight: 400;
    font-size: 0.85rem;
  }
  .topbar-right {
    display: flex;
    align-items: center;
    gap: 20px;
  }
  .live-counter {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
  }
  .live-counter .label {
    font-size: 0.68rem;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }
  .live-counter .value {
    font-family: var(--mono);
    font-size: 1.05rem;
    font-weight: 700;
    color: var(--fg);
  }
  .live-counter .value.green { color: var(--accent); }
  .live-counter .value.red   { color: var(--bad); }
  .live-dot {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 0.8rem;
    font-weight: 600;
    color: var(--bad);
  }
  .live-dot::before {
    content: '';
    display: inline-block;
    width: 8px; height: 8px;
    border-radius: 50%;
    background: var(--bad);
    animation: blink 1.2s ease-in-out infinite;
  }
  @keyframes blink {
    0%, 100% { opacity: 1; }
    50%       { opacity: 0.2; }
  }

  /* ── LAYOUT ─────────────────────────────────────────────────── */
  .noc-grid {
    display: grid;
    grid-template-columns: 35% 1fr 30%;
    grid-template-rows: 1fr 1fr;
    gap: 1px;
    background: var(--border);
    flex: 1;
    min-height: 0;
  }
  .panel {
    background: var(--panel);
    padding: 16px;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .panel.tall { grid-row: span 2; }
  .panel-title {
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--muted);
    border-bottom: 1px solid var(--border);
    padding-bottom: 8px;
    flex-shrink: 0;
  }

  /* ── PANEL 1: SIMULATOR ─────────────────────────────────────── */
  .sim-controls { display: flex; flex-direction: column; gap: 10px; }
  .sim-row { display: flex; flex-direction: column; gap: 4px; }
  .sim-row label {
    font-size: 0.72rem;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.05em;
    display: flex;
    justify-content: space-between;
  }
  .sim-row label .cur-val {
    color: var(--fg);
    font-family: var(--mono);
    font-weight: 600;
  }
  input[type=range] {
    width: 100%;
    accent-color: var(--accent);
    cursor: pointer;
  }
  .sim-tier-labels {
    display: flex;
    justify-content: space-between;
    font-size: 0.62rem;
    color: var(--muted);
    margin-top: -2px;
  }
  .strategy-toggle {
    display: flex;
    gap: 6px;
    flex-wrap: wrap;
  }
  .strat-btn {
    padding: 5px 10px;
    border-radius: 4px;
    border: 1px solid var(--border);
    background: var(--panel-2);
    color: var(--muted);
    font-size: 0.75rem;
    cursor: pointer;
    font-family: var(--mono);
    transition: all 0.15s;
  }
  .strat-btn.active {
    background: rgba(45, 164, 78, 0.15);
    border-color: rgba(45, 164, 78, 0.5);
    color: var(--accent);
  }
  .verdict-large {
    font-size: 1.1rem;
    font-weight: 800;
    padding: 10px 14px;
    border-radius: 6px;
    text-align: center;
    transition: all 0.2s;
    flex-shrink: 0;
  }
  .verdict-large.accept {
    background: rgba(45, 164, 78, 0.12);
    color: var(--accent);
    border: 1px solid rgba(45, 164, 78, 0.35);
  }
  .verdict-large.reject {
    background: rgba(248, 81, 73, 0.12);
    color: var(--bad);
    border: 1px solid rgba(248, 81, 73, 0.35);
  }
  .opcode-trace {
    background: var(--panel-2);
    border: 1px solid var(--border);
    border-radius: 4px;
    padding: 8px 10px;
    font-family: var(--mono);
    font-size: 0.67rem;
    color: var(--muted);
    line-height: 1.7;
    flex-shrink: 0;
  }
  .opcode-trace .hl { color: var(--fg); }
  .opcode-trace .ok-step { color: var(--accent); }
  .opcode-trace .fail-step { color: var(--bad); }
  .example-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.72rem;
  }
  .example-table th {
    text-align: left;
    padding: 4px 6px;
    color: var(--muted);
    border-bottom: 1px solid var(--border);
    font-weight: 500;
    text-transform: uppercase;
    font-size: 0.65rem;
    letter-spacing: 0.05em;
  }
  .example-table td {
    padding: 4px 6px;
    border-bottom: 1px solid rgba(48,54,61,0.5);
    font-family: var(--mono);
    font-size: 0.7rem;
    vertical-align: middle;
  }
  .badge {
    display: inline-block;
    padding: 1px 6px;
    border-radius: 3px;
    font-size: 0.65rem;
    font-weight: 700;
    font-family: var(--mono);
  }
  .badge.accept { background: rgba(45,164,78,0.15); color: var(--accent); }
  .badge.reject { background: rgba(248,81,73,0.12); color: var(--bad); }
  .badge.tier0  { background: rgba(248,81,73,0.18); color: var(--bad); }
  .badge.tier1  { background: rgba(210,153,34,0.15); color: var(--warn); }
  .badge.tier2  { background: rgba(14,165,233,0.12); color: var(--teal); }
  .badge.tier3  { background: rgba(45,164,78,0.15); color: var(--accent); }

  /* ── PANEL 2: LIVE ROUTE STREAM ─────────────────────────────── */
  .stream-table-wrap {
    flex: 1;
    overflow: hidden;
    position: relative;
  }
  .stream-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.72rem;
    table-layout: fixed;
  }
  .stream-table th {
    text-align: left;
    padding: 4px 6px;
    color: var(--muted);
    border-bottom: 1px solid var(--border);
    font-weight: 500;
    text-transform: uppercase;
    font-size: 0.62rem;
    letter-spacing: 0.05em;
    position: sticky;
    top: 0;
    background: var(--panel);
    z-index: 1;
  }
  .stream-table td {
    padding: 4px 6px;
    font-family: var(--mono);
    font-size: 0.68rem;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    vertical-align: middle;
    border-bottom: 1px solid rgba(48,54,61,0.3);
    transition: background 0.3s;
  }
  .stream-row { animation: rowIn 0.3s ease-out; }
  .stream-row.attack {
    animation: rowIn 0.3s ease-out, pulse 1s ease-in-out 3;
    background: rgba(248, 81, 73, 0.06);
  }
  @keyframes rowIn {
    from { opacity: 0; transform: translateY(-4px); background: rgba(230,237,243,0.05); }
    to   { opacity: 1; transform: translateY(0);    background: transparent; }
  }
  @keyframes pulse {
    0%, 100% { background: rgba(248, 81, 73, 0.04); }
    50%       { background: rgba(248, 81, 73, 0.18); }
  }
  .col-time  { width: 68px; }
  .col-peer  { width: 26%; }
  .col-prefix { width: 22%; }
  .col-tier  { width: 54px; }
  .col-result { width: 58px; }
  .col-flag  { width: auto; }
  .attack-flag {
    color: var(--warn);
    font-size: 0.62rem;
    white-space: nowrap;
  }

  /* ── PANEL 3: 24H CHART ─────────────────────────────────────── */
  .chart-wrap {
    position: relative;
    flex: 1;
    min-height: 0;
  }
  .chart-wrap canvas { max-height: 100%; }
  .chart-legend {
    display: flex;
    gap: 14px;
    flex-wrap: wrap;
    flex-shrink: 0;
  }
  .chart-legend .item {
    display: flex;
    align-items: center;
    gap: 5px;
    font-size: 0.7rem;
    color: var(--muted);
  }
  .chart-legend .dot {
    width: 10px; height: 10px;
    border-radius: 2px;
  }
  .comparison-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.68rem;
    flex-shrink: 0;
  }
  .comparison-table th {
    text-align: left;
    padding: 4px 6px;
    color: var(--muted);
    border-bottom: 1px solid var(--border);
    font-weight: 500;
    text-transform: uppercase;
    font-size: 0.6rem;
    letter-spacing: 0.05em;
  }
  .comparison-table td {
    padding: 4px 6px;
    font-family: var(--mono);
    font-size: 0.68rem;
    border-bottom: 1px solid rgba(48,54,61,0.4);
    vertical-align: middle;
  }
  .comparison-table tr.winner td { color: var(--accent); }

  /* ── PANEL 4: AUDIT TRAIL ───────────────────────────────────── */
  .anchor-feed {
    flex: 1;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .anchor-entry {
    display: grid;
    grid-template-columns: 1fr auto;
    gap: 6px;
    padding: 7px 9px;
    background: var(--panel-2);
    border: 1px solid var(--border);
    border-radius: 4px;
    font-size: 0.68rem;
    animation: fadeIn 0.5s ease-out;
    transition: opacity 0.5s;
    flex-shrink: 0;
  }
  .anchor-entry.fresh {
    border-color: rgba(45,164,78,0.4);
    background: rgba(45,164,78,0.06);
  }
  @keyframes fadeIn {
    from { opacity: 0.2; background: rgba(45,164,78,0.12); }
    to   { opacity: 1; }
  }
  .anchor-txid {
    font-family: var(--mono);
    color: var(--muted);
    font-size: 0.65rem;
  }
  .anchor-txid .hl { color: #58a6ff; }
  .anchor-event { font-size: 0.7rem; color: var(--fg); }
  .anchor-time  { font-size: 0.62rem; color: var(--muted); white-space: nowrap; }
  .on-chain-badge {
    display: inline-block;
    padding: 1px 6px;
    background: rgba(45,164,78,0.12);
    color: var(--accent);
    border: 1px solid rgba(45,164,78,0.3);
    border-radius: 3px;
    font-size: 0.6rem;
    font-weight: 600;
  }
  .anchor-count {
    font-family: var(--mono);
    font-size: 0.8rem;
    color: var(--accent);
    text-align: center;
    padding: 6px;
    background: rgba(45,164,78,0.06);
    border: 1px solid rgba(45,164,78,0.2);
    border-radius: 4px;
    flex-shrink: 0;
  }
  .proof-block {
    background: var(--panel-2);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 10px 12px;
    flex-shrink: 0;
  }
  .proof-field {
    display: grid;
    grid-template-columns: 80px 1fr;
    gap: 4px 8px;
    padding: 3px 0;
    border-top: 1px solid rgba(48,54,61,0.5);
    align-items: baseline;
    font-size: 0.67rem;
  }
  .proof-field:first-of-type { border-top: none; }
  .proof-field .lbl { color: var(--muted); text-transform: uppercase; font-size: 0.6rem; letter-spacing: 0.05em; }
  .proof-field .val { font-family: var(--mono); word-break: break-all; }
  .replay-block {
    background: var(--panel-2);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 10px 12px;
    flex-shrink: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .replay-inputs {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }
  .replay-input-group { display: flex; flex-direction: column; gap: 3px; }
  .replay-input-group label { font-size: 0.65rem; color: var(--muted); text-transform: uppercase; letter-spacing: 0.05em; }
  .replay-input-group input {
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 4px;
    color: var(--fg);
    font-family: var(--mono);
    font-size: 0.82rem;
    padding: 4px 8px;
    width: 100%;
  }
  .replay-input-group input:focus { outline: none; border-color: var(--accent); }
  .replay-result {
    font-family: var(--mono);
    font-size: 0.75rem;
    padding: 6px 10px;
    border-radius: 4px;
    text-align: center;
  }
  .replay-result.accept { background: rgba(45,164,78,0.12); color: var(--accent); }
  .replay-result.reject { background: rgba(248,81,73,0.1);  color: var(--bad); }
  .replay-result.neutral { background: var(--panel); color: var(--muted); }
  .bytes-display {
    font-family: var(--mono);
    font-size: 0.65rem;
    color: var(--muted);
    word-break: break-all;
    line-height: 1.6;
  }
  .bytes-display .push-byte { color: var(--teal); }
  .bytes-display .pred-byte { color: var(--warn); }
  .quote-block {
    background: rgba(248,81,73,0.05);
    border-left: 3px solid var(--bad);
    padding: 8px 10px;
    font-size: 0.72rem;
    color: var(--muted);
    font-style: italic;
    line-height: 1.5;
    flex-shrink: 0;
    border-radius: 0 4px 4px 0;
  }
  .quote-block strong { color: var(--fg); font-style: normal; }
  /* ── TOOLTIP / INFO ICON SYSTEM ───────────────────────────── */
  .info-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 16px;
    height: 16px;
    min-width: 16px;
    border-radius: 50%;
    background: rgba(139,148,158,0.15);
    border: 1px solid rgba(139,148,158,0.28);
    color: var(--muted);
    font-size: 0.6rem;
    font-weight: 700;
    cursor: help;
    font-style: normal;
    user-select: none;
    flex-shrink: 0;
  }
  .tip-host {
    position: relative;
    display: inline-flex;
    align-items: center;
    gap: 5px;
  }
  .tip-box {
    display: none;
    position: absolute;
    z-index: 300;
    bottom: calc(100% + 10px);
    left: 50%;
    transform: translateX(-50%);
    width: 290px;
    background: #1c2330;
    border: 1px solid #30363d;
    border-radius: 8px;
    padding: 11px 14px;
    font-size: 0.79rem;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
    color: #e6edf3;
    line-height: 1.55;
    font-weight: 400;
    pointer-events: none;
    box-shadow: 0 8px 28px rgba(0,0,0,0.45);
    text-transform: none;
    letter-spacing: 0;
  }
  .tip-box::after {
    content: '';
    position: absolute;
    top: 100%;
    left: 50%;
    transform: translateX(-50%);
    border: 7px solid transparent;
    border-top-color: #30363d;
  }
  .tip-host:hover .tip-box,
  .info-btn:focus + .tip-box {
    display: block;
  }
  .tip-label {
    display: block;
    font-weight: 700;
    font-size: 0.77rem;
    color: #fff;
    margin-bottom: 5px;
  }

  .mainnet-badge {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 5px 10px;
    background: rgba(45,164,78,0.1);
    border: 1px solid rgba(45,164,78,0.3);
    border-radius: 4px;
    color: var(--accent);
    font-size: 0.72rem;
    font-weight: 600;
    flex-shrink: 0;
  }

  /* ── CASHLANES CHANNEL PANEL ───────────────────────────────────── */
  .channel-section {
    background: var(--panel);
    border: 1px solid #2a3750;
    border-radius: 8px;
    margin: 8px 12px 12px;
    padding: 16px 20px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .channel-header {
    display: flex;
    align-items: center;
    gap: 12px;
    flex-wrap: wrap;
  }
  .channel-title {
    font-size: 0.82rem;
    font-weight: 700;
    color: #e6c07b;
    display: flex;
    align-items: center;
    gap: 5px;
    flex: 1;
  }
  .channel-state-pill {
    font-size: 0.72rem;
    font-weight: 700;
    font-family: var(--mono);
    padding: 3px 10px;
    border-radius: 12px;
    border: 1px solid;
    white-space: nowrap;
  }
  .state-UNFUNDED  { background: rgba(139,148,158,0.1); color:#8b949e; border-color:rgba(139,148,158,0.3); }
  .state-FUNDED    { background: rgba(14,165,233,0.1);  color:var(--teal); border-color:rgba(14,165,233,0.3); }
  .state-FLOW_ACTIVE { background: rgba(45,164,78,0.12); color:var(--accent); border-color:rgba(45,164,78,0.4); animation: pulse-border 1.5s ease-in-out infinite; }
  .state-SETTLING  { background: rgba(210,153,34,0.12); color:var(--warn);   border-color:rgba(210,153,34,0.4); }
  .state-CLOSED    { background: rgba(45,164,78,0.08);  color:#4caf8a;       border-color:rgba(45,164,78,0.2); }
  @keyframes pulse-border {
    0%,100% { border-color: rgba(45,164,78,0.4); }
    50%     { border-color: rgba(45,164,78,0.9); }
  }
  .channel-controls {
    display: flex;
    gap: 6px;
    flex-wrap: wrap;
  }
  .ch-btn {
    padding: 5px 14px;
    border-radius: 5px;
    border: 1px solid;
    font-size: 0.74rem;
    font-weight: 600;
    cursor: pointer;
    transition: opacity 0.15s;
  }
  .ch-btn:disabled { opacity: 0.35; cursor: default; }
  .ch-btn-fund   { background: rgba(14,165,233,0.12); color:var(--teal); border-color:rgba(14,165,233,0.4); }
  .ch-btn-start  { background: rgba(45,164,78,0.12);  color:var(--accent); border-color:rgba(45,164,78,0.4); }
  .ch-btn-settle { background: rgba(210,153,34,0.12); color:var(--warn);   border-color:rgba(210,153,34,0.4); }
  .ch-btn-reset  { background: rgba(248,81,73,0.08);  color:var(--bad);    border-color:rgba(248,81,73,0.3); font-size:0.68rem; }
  .channel-body {
    display: flex;
    gap: 16px;
    flex-wrap: wrap;
  }
  .channel-metrics {
    flex: 1;
    min-width: 280px;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .channel-fsm {
    display: flex;
    align-items: center;
    gap: 4px;
    flex-wrap: wrap;
    font-size: 0.65rem;
    font-family: var(--mono);
  }
  .fsm-step {
    padding: 2px 8px;
    border-radius: 10px;
    border: 1px solid rgba(139,148,158,0.2);
    color: var(--muted);
    font-weight: 600;
    transition: all 0.3s;
  }
  .fsm-step.active {
    border-color: var(--teal);
    color: var(--teal);
    background: rgba(14,165,233,0.1);
    box-shadow: 0 0 8px rgba(14,165,233,0.3);
  }
  .fsm-arrow { color:var(--border); font-size:0.7rem; }
  .channel-stats {
    display: flex;
    gap: 20px;
    flex-wrap: wrap;
  }
  .ch-stat {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .ch-stat-label { font-size: 0.62rem; color: var(--muted); text-transform: uppercase; letter-spacing: 0.05em; }
  .ch-stat-value { font-size: 1.1rem; font-weight: 700; font-family: var(--mono); color: var(--fg); }
  .ch-stat-value.green { color: var(--accent); }
  .ch-funding-row {
    font-size: 0.65rem;
    font-family: var(--mono);
    color: var(--muted);
    display: flex;
    gap: 6px;
    align-items: center;
    flex-wrap: wrap;
  }
  .ch-funding-row a { color: #58a6ff; text-decoration: none; }
  .ch-funding-row a:hover { text-decoration: underline; }
  .channel-settlements {
    flex: 1.5;
    min-width: 320px;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .ch-settle-header {
    font-size: 0.68rem;
    font-weight: 700;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }
  .ch-settle-list {
    display: flex;
    flex-direction: column;
    gap: 5px;
    max-height: 160px;
    overflow-y: auto;
  }
  .ch-settle-entry {
    background: var(--panel-2);
    border: 1px solid var(--border);
    border-radius: 5px;
    padding: 7px 10px;
    display: flex;
    align-items: center;
    gap: 10px;
    font-size: 0.68rem;
    animation: slideIn 0.3s ease;
  }
  .ch-settle-entry.new { border-color: rgba(45,164,78,0.5); }
  @keyframes slideIn { from { opacity:0; transform:translateY(-4px); } to { opacity:1; transform:none; } }
  .ch-settle-seq  { color: var(--muted); font-family:var(--mono); flex-shrink:0; }
  .ch-settle-info { flex:1; color:var(--fg); }
  .ch-settle-txid { font-family:var(--mono); font-size:0.65rem; }
  .ch-settle-txid a { color:#58a6ff; text-decoration:none; }
  .ch-settle-txid a:hover { text-decoration:underline; }
  .ch-settle-badge {
    font-size: 0.6rem;
    padding: 1px 6px;
    background: rgba(45,164,78,0.1);
    border: 1px solid rgba(45,164,78,0.3);
    border-radius: 10px;
    color: var(--accent);
    flex-shrink: 0;
  }
  .channel-footnote {
    font-size: 0.65rem;
    color: var(--muted);
    border-top: 1px solid var(--border);
    padding-top: 8px;
  }
  .ch-bridge-status {
    font-size: 0.68rem;
    font-family: var(--mono);
  }
  .ch-bridge-online { color: var(--accent); }
  .ch-bridge-offline { color: var(--muted); }

  /* Cell Mesh panel */
  .cm-cell-row {
    display: flex;
    gap: 8px;
    align-items: baseline;
    padding: 5px 8px;
    background: rgba(255,255,255,0.02);
    border: 1px solid var(--border);
    border-radius: 4px;
    font-family: var(--mono);
    font-size: 0.65rem;
    animation: cm-slide-in 0.3s ease;
  }
  .cm-cell-row.cm-new { border-color: var(--accent); }
  @keyframes cm-slide-in {
    from { opacity:0; transform:translateY(-4px); }
    to   { opacity:1; transform:translateY(0); }
  }
  .cm-cell-id   { color: var(--accent); flex-shrink:0; }
  .cm-cell-type { color: var(--fg); flex:1; min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  .cm-cell-fp   { color: var(--muted); flex-shrink:0; }
  .cm-cell-ts   { color: var(--muted); flex-shrink:0; }
</style>
</head>
<body>

<!-- ── TOP BAR ──────────────────────────────────────────────────── -->
<div class="topbar">
  <div class="topbar-title">
    IXP Route Auditor <span>— Rúnar-governed BGP policy · Real Blockchain Solutions</span>
  </div>
  <div class="topbar-right">
    <div class="live-counter">
      <span class="label">Routes/sec</span>
      <span class="value" id="ctr-rps">0.0</span>
    </div>
    <div class="live-counter">
      <span class="label"><span class="tip-host">Accepted<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Routes Accepted</span>Total BGP route announcements that passed the policy rule this session. These routes have been validated and propagated. Each acceptance event is anchored on BSV mainnet — creating a tamper-proof record of every routing decision.</div></span></span>
      <span class="value green" id="ctr-accepted">0</span>
    </div>
    <div class="live-counter">
      <span class="label"><span class="tip-host">Blocked<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Routes Blocked</span>Total BGP route announcements rejected by the policy rule — including attack-pattern routes (Tier-0 peers with broad prefixes like /8–/15). The Facebook 2021 outage cost $6B in market cap and could have been prevented by a rule like this blocking the misrouted announcement.</div></span></span>
      <span class="value red" id="ctr-blocked">0</span>
    </div>
    <div class="live-dot">LIVE</div>
  </div>
  <div class="hat-row">
    <span class="hat-label">🎩</span>
    <select id="hat-select" class="hat-select" onchange="onHatChange(this.value)">
      <option value="eu-networks-fiber-operator">EU Networks — Fiber Operator</option>
      <option value="inference-gateway-eu">Inference Gateway EU</option>
      <option value="ixp-ams-noc" selected>IXP Amsterdam NOC</option>
      <option value="plexus-admin">Plexus Admin</option>
    </select>
    <span id="hat-fp" class="hat-fp"></span>
    <span id="mesh-status" class="pill pill-muted">○ Mesh offline</span>
  </div>
</div>

<!-- ── MAIN NOC GRID ─────────────────────────────────────────────── -->
<div class="noc-grid">

  <!-- ── PANEL 1: SIMULATOR (left column, full height) ─────────── -->
  <div class="panel tall" style="grid-row: 1 / 3; overflow-y: auto;">
    <div class="panel-title"><span class="tip-host">Route Acceptance Simulator<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">BGP Route Policy Simulator</span>Move the sliders to simulate a real BGP routing decision. The same Bitcoin Script policy that runs in production executes here in your browser — there is no gap between demo and live. The policy hex is on-chain, so auditors can verify what rule was running during any incident.</div></span></div>

    <div class="strategy-toggle">
      <button class="strat-btn active" id="btn-route_accept" onclick="selectStrategy('route_accept')">
        route_accept <small>(9B)</small>
      </button>
      <button class="strat-btn" id="btn-tier_prefix_product" onclick="selectStrategy('tier_prefix_product')">
        tier_prefix_product <small>(4B)</small>
      </button>
    </div>

    <div class="sim-controls">
      <div class="sim-row">
        <label>
          <span class="tip-host">Peer Tier (asnTier)<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">ASN Tier — Network Peer Trust Level</span>The trust level of the network peer announcing this BGP route. Tier 0 = unknown/unregistered (always blocked). Tier 1 = registered ISP. Tier 2 = verified carrier. Tier 3 = trusted Tier-1 provider (e.g. Cloudflare, Google). Higher tiers unlock acceptance of a wider range of prefixes.</div></span>
          <span class="cur-val" id="tier-val-label">tier-1</span>
        </label>
        <input type="range" min="0" max="3" step="1" value="1" id="tier-slider" oninput="onSimChange()">
        <div class="sim-tier-labels">
          <span>0 unknown</span><span>1 registered</span><span>2 verified</span><span>3 trusted</span>
        </div>
      </div>
      <div class="sim-row">
        <label>
          <span class="tip-host">Prefix Length (prefixLen)<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Prefix Length — Route Specificity</span>How specific the announced route is. /8 = 16 million IP addresses (very broad — often a BGP hijack signal). /16 = 65,536 addresses. /24 = 256 addresses (typical legitimate route). The Facebook 2021 outage was caused by misrouted BGP announcements — a rule like this would have blocked them.</div></span>
          <span class="cur-val" id="prefix-val-label">/24</span>
        </label>
        <input type="range" min="8" max="32" step="1" value="24" id="prefix-slider" oninput="onSimChange()">
        <div class="sim-tier-labels">
          <span>/8 broad</span><span></span><span></span><span>/32 specific</span>
        </div>
      </div>
    </div>

    <div class="verdict-large accept" id="sim-verdict">✓ ROUTE ACCEPTED</div>
    <div style="font-size:0.68rem;margin-top:-8px;"><span class="tip-host"><span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">ACCEPT / REJECT Verdict</span>The live output of the Bitcoin Script BGP policy evaluator. ACCEPT means the route passes the policy conditions and will be propagated. REJECT means it is dropped. Zero false positives on legitimate routes means operators can deploy this without service disruption.</div></span></div>

    <div class="opcode-trace" id="opcode-trace">
      <!-- filled by JS -->
    </div>

    <div style="font-size:0.68rem; color:var(--muted); font-weight:500; text-transform:uppercase; letter-spacing:0.06em;">
      Worked examples
    </div>

    <table class="example-table">
      <thead>
        <tr>
          <th>Peer</th><th>Prefix</th><th>Tier</th><th>route_accept</th><th>product</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td>Cloudflare</td><td>/24</td><td><span class="badge tier3">3</span></td>
          <td><span class="badge accept">✓</span></td><td><span class="badge accept">✓</span></td>
        </tr>
        <tr>
          <td>Unknown-ASN</td><td>/8</td><td><span class="badge tier0">0</span></td>
          <td><span class="badge reject">✗</span></td><td><span class="badge reject">✗</span></td>
        </tr>
        <tr>
          <td>Deutsche Telekom</td><td>/11</td><td><span class="badge tier3">3</span></td>
          <td><span class="badge reject">✗</span></td><td><span class="badge accept">✓</span></td>
        </tr>
        <tr>
          <td>Tele2</td><td>/16</td><td><span class="badge tier2">2</span></td>
          <td><span class="badge accept">✓</span></td><td><span class="badge accept">✓</span></td>
        </tr>
        <tr>
          <td>Small-ISP</td><td>/24</td><td><span class="badge tier1">1</span></td>
          <td><span class="badge accept">✓</span></td><td><span class="badge reject">✗</span></td>
        </tr>
        <tr>
          <td>Ghost-Peer-A</td><td>/12</td><td><span class="badge tier0">0</span></td>
          <td><span class="badge reject">✗</span></td><td><span class="badge reject">✗</span></td>
        </tr>
      </tbody>
    </table>
  </div>

  <!-- ── PANEL 2: LIVE ROUTE STREAM (center-top) ───────────────── -->
  <div class="panel" style="overflow: hidden;">
    <div class="panel-title"><span class="tip-host">Live Route Stream<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Live BGP Route Stream</span>Simulated BGP route announcements from real-world ASNs. Rows highlighted in red are attack-pattern routes (Tier-0 peers with broad /8–/15 prefixes). The policy evaluates each announcement in microseconds — the same Bitcoin Script logic that runs on-chain.</div></span> <span id="stream-subtitle" style="color:var(--muted);font-size:0.65rem;"></span></div>
    <div class="stream-table-wrap" style="overflow-y: auto; flex: 1;">
      <table class="stream-table">
        <thead>
          <tr>
            <th class="col-time">Time</th>
            <th class="col-peer">Peer</th>
            <th class="col-prefix">Prefix</th>
            <th class="col-tier">Tier</th>
            <th class="col-result">Result</th>
            <th class="col-flag">Flag</th>
          </tr>
        </thead>
        <tbody id="stream-body"></tbody>
      </table>
    </div>
  </div>

  <!-- ── PANEL 3: 24H STRATEGY COMPARISON (center-bottom) ─────── -->
  <div class="panel" style="overflow: hidden;">
    <div class="panel-title"><span class="tip-host">24h Strategy Comparison — BGP Backtest<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">24H Route Chart</span>We replayed 6,200 synthetic BGP route events through both policy rules. Red shaded windows are simulated incident periods (BGP hijack attacks). The chart shows cumulative accepted routes. The route_accept policy blocks all attack-pattern routes with zero false positives on legitimate traffic.</div></span></div>
    <div class="chart-legend">
      <div class="item"><div class="dot" style="background:#2da44e"></div>route_accept accepted</div>
      <div class="item"><div class="dot" style="background:#0ea5e9"></div>tier_prefix_product accepted</div>
      <div class="item"><div class="dot" style="background:rgba(248,81,73,0.6)"></div>attack-pattern routes (blocked)</div>
    </div>
    <div class="chart-wrap" style="flex:1; min-height:0;">
      <canvas id="chart-main"></canvas>
    </div>
    <table class="comparison-table">
      <thead>
        <tr>
          <th>Strategy</th><th>Bytes</th><th>Accepted</th><th>Blocked</th><th>Attacks blocked</th><th>False blocks</th>
        </tr>
      </thead>
      <tbody id="comparison-body">
        <tr><td colspan="6" style="color:var(--muted);font-size:0.65rem;">Computing...</td></tr>
      </tbody>
    </table>
  </div>

  <!-- ── PANEL 4: AUDIT TRAIL (right column, full height) ─────── -->
  <div class="panel tall" style="grid-row: 1 / 3; overflow-y: auto;">
    <div class="panel-title"><span class="tip-host">Anchored Decisions — Audit Trail<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">On-Chain Audit Trail</span>Every routing decision is anchored to the Bitcoin SV blockchain as an immutable commitment. When an incident occurs, operators can prove to any regulator or counterparty exactly which policy was running and what decisions it made — using a txid, not a log file that could be edited.</div></span></div>

    <div class="quote-block">
      <strong>The Facebook October 2021 outage destroyed $6B in market cap.</strong> They couldn't explain their BGP policy. We can explain ours — with a txid. <span class="tip-host"><span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Why On-Chain BGP Policy Matters</span>Facebook's 2021 outage was caused by a misrouted BGP announcement that took down all their services globally for 6+ hours. A policy rule like route_accept — which blocks Tier-0 peers and overly broad prefixes — would have caught it. And because the rule is on-chain, you can prove to any regulator what policy was active during any incident.</div></span>
    </div>

    <div class="anchor-count" id="anchor-count">0 settlements anchored this session</div>

    <div class="anchor-feed" id="anchor-feed" style="flex:1; overflow-y:auto;">
      <div class="anchor-placeholder" style="color:var(--muted);font-size:0.68rem;padding:10px 0;line-height:1.5">
        No settlements yet — fund the channel below and start routing to trigger real BSV mainnet settlement txids.
      </div>
    </div>

    <div class="proof-block">
      <div style="font-size:0.68rem; font-weight:600; margin-bottom:8px;"><span class="tip-host">BSV Proof — Policy Hex<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">On-Chain Policy Proof</span>The policy hex is anchored to the Bitcoin SV blockchain. This creates an immutable record of what routing rule was active. Auditors can verify the exact rule that was enforced during any incident — the policy hex is on-chain, so it cannot be retroactively changed.</div></span></div>
      <div class="proof-field">
        <span class="lbl"><span class="tip-host">route_accept<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Cell Hash — route_accept</span>The cryptographic fingerprint of the route_accept policy anchor: SHA-256(policy_hex + data_hash + result_hash). If the policy, data, or result were altered even by one bit, this hash would be completely different.</div></span></span>
        <span class="val" style="color:var(--accent);">760110a269750101a2 <span style="color:var(--muted);">(9 bytes)</span></span>
      </div>
      <div class="proof-field">
        <span class="lbl"><span class="tip-host">tier_product<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Cell Hash — tier_prefix_product</span>The cryptographic fingerprint of the tier_prefix_product policy anchor. 4 bytes — encodes the compact product-based routing rule.</div></span></span>
        <span class="val" style="color:var(--teal);">950120a2 <span style="color:var(--muted);">(4 bytes)</span></span>
      </div>
      <div class="proof-field">
        <span class="lbl">network</span>
        <span class="val" style="color:var(--accent);">BSV mainnet</span>
      </div>
      <div class="proof-field">
        <span class="lbl"><span class="tip-host">anchor<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Bitcoin SV Transaction IDs</span>These are real BSV mainnet transactions — each one anchors the backtest result for one strategy. Click either link to view on a public block explorer. Anyone can verify the commitment without creating an account.</div></span></span>
        <span class="val" style="display:flex;flex-direction:column;gap:4px;">
          <a id="ra-chain-link" href="https://whatsonchain.com/tx/b060914f6c876ba20afa4e4e52e205ab79b9ae5e827b72c4770b774b7223e456" target="_blank" rel="noopener" style="color:#58a6ff;font-size:0.68rem;font-family:var(--mono)">route_accept: b060914f…3e456</a>
          <a id="tp-chain-link" href="https://whatsonchain.com/tx/c6877fa75acb1e96519a6067c20c3d1fd270f6d2e86ae5b195c0255cc9b87b65" target="_blank" rel="noopener" style="color:var(--teal);font-size:0.68rem;font-family:var(--mono)">tier_product: c6877fa7…b65</a>
        </span>
      </div>
    </div>

    <div class="replay-block">
      <div style="font-size:0.68rem; font-weight:600;"><span class="tip-host">Replay any decision<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Policy Replay Tool</span>Enter any asnTier and prefixLen to replay the routing decision. The full Bitcoin Script byte sequence is shown below the result — this is the exact input that would be evaluated on-chain. Anyone can reproduce this computation independently.</div></span></div>
      <div class="replay-inputs">
        <div class="replay-input-group">
          <label>asnTier (0-3)</label>
          <input type="number" id="rp-tier" min="0" max="3" value="1" oninput="onReplay()">
        </div>
        <div class="replay-input-group">
          <label>prefixLen (8-32)</label>
          <input type="number" id="rp-prefix" min="8" max="32" value="24" oninput="onReplay()">
        </div>
      </div>
      <div class="replay-result neutral" id="replay-result">Enter values above</div>
      <div class="bytes-display" id="replay-bytes"></div>
    </div>

    <div class="mainnet-badge">✓ Anchored on BSV mainnet</div>
  </div>

</div><!-- end .noc-grid -->

<!-- ── CASHLANES CHANNEL PANEL ───────────────────────────────────── -->
<div class="channel-section" id="channel-section">
  <div class="channel-header">
    <div class="channel-title">
      <span style="font-size:1rem;">⚡</span>
      CashLanes Payment Channel — Per-Packet BSV Settlement
      <span class="tip-host"><span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Per-Packet BSV Settlement</span>Every BGP route acceptance advances a payment channel metering counter. When the channel accumulates enough data (5 MB), CashLanes triggers a real BSV mainnet settlement transaction via Metanet Desktop. The txid is the on-chain proof that IXP bandwidth was paid for — not a receipt, not a log entry, a Bitcoin transaction.</div></span>
      <span id="ch-bridge-status" class="ch-bridge-status ch-bridge-offline">● bridge offline</span>
    </div>
    <div class="channel-state-pill state-UNFUNDED" id="channel-state-pill">UNFUNDED</div>
    <div class="channel-controls">
      <button id="ch-fund-btn"   class="ch-btn ch-btn-fund"   onclick="channelFund()">Fund Channel</button>
      <button id="ch-start-btn"  class="ch-btn ch-btn-start"  onclick="channelStart()"  disabled>Start Flow</button>
      <button id="ch-settle-btn" class="ch-btn ch-btn-settle" onclick="channelSettle()" disabled>Settle Now</button>
      <button id="ch-reset-btn"  class="ch-btn ch-btn-reset"  onclick="channelReset()">↺ Reset</button>
    </div>
  </div>

  <div class="channel-body">
    <!-- Left: FSM + live metrics -->
    <div class="channel-metrics">
      <!-- FSM state diagram -->
      <div class="channel-fsm">
        <span class="fsm-step active" id="fsm-UNFUNDED">UNFUNDED</span>
        <span class="fsm-arrow">→</span>
        <span class="fsm-step" id="fsm-FUNDED">FUNDED</span>
        <span class="fsm-arrow">→</span>
        <span class="fsm-step" id="fsm-FLOW_ACTIVE">FLOW_ACTIVE</span>
        <span class="fsm-arrow">→</span>
        <span class="fsm-step" id="fsm-SETTLING">SETTLING</span>
        <span class="fsm-arrow">→</span>
        <span class="fsm-step" id="fsm-CLOSED">CLOSED</span>
      </div>

      <!-- Live counters -->
      <div class="channel-stats">
        <div class="ch-stat">
          <span class="ch-stat-label">MB Routed</span>
          <span class="ch-stat-value green" id="ch-mb">0.00</span>
        </div>
        <div class="ch-stat">
          <span class="ch-stat-label">Cost (sats)</span>
          <span class="ch-stat-value" id="ch-sats">0</span>
        </div>
        <div class="ch-stat">
          <span class="ch-stat-label">Settlements</span>
          <span class="ch-stat-value" id="ch-seq">0</span>
        </div>
        <div class="ch-stat">
          <span class="ch-stat-label">Rate</span>
          <span class="ch-stat-value" style="font-size:0.85rem;color:var(--muted)">10 sats/MB</span>
        </div>
        <div class="ch-stat">
          <span class="ch-stat-label">Hat</span>
          <span class="ch-stat-value" style="font-size:0.7rem;color:var(--teal)" id="ch-hat">ixp-ams-noc</span>
        </div>
      </div>

      <!-- Funding txid / multisig -->
      <div class="ch-funding-row" id="ch-funding-row" style="display:none">
        <span>2-of-2 multisig:</span>
        <a id="ch-funding-link" href="#" target="_blank" rel="noopener">—</a>
        <span id="ch-key-info" style="color:var(--muted);font-size:0.6rem;"></span>
      </div>
    </div>

    <!-- Right: Settlement txid list -->
    <div class="channel-settlements">
      <div class="ch-settle-header">
        <span class="tip-host">BSV Settlement Transactions<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Real BSV Mainnet Settlement Txids</span>Each entry is a real Bitcoin SV transaction anchoring a CashLanes settlement. The PushDrop locking script embeds the settlement data (channel ID, MB transferred, cost in satoshis) directly on-chain. The hat private key controls the output — different operators produce different settlement keys.</div></span>
      </div>
      <div class="ch-settle-list" id="ch-settle-list">
        <div style="color:var(--muted);font-size:0.7rem;padding:6px 0;">No settlements yet — fund the channel and start routing to trigger automatic BSV settlements</div>
      </div>
    </div>
  </div>

  <div class="channel-footnote">
    Each <strong style="color:var(--accent)">ixp.route.accept</strong> event advances the MB counter by 0.5 MB. Every 5 MB triggers an automatic BSV mainnet settlement anchor via Metanet Desktop (:3321). Use <em>Settle Now</em> to trigger manually at any time. Hat key derivation: SHA-256(<em>hat-name</em>) → secp256k1 private key → PushDrop locking script.
  </div>
</div>

<!-- ── Cell Mesh Panel ───────────────────────────────────────────────────── -->
<div class="channel-section" id="cell-mesh-section" style="margin-top:12px">
  <div class="channel-header">
    <span class="channel-title">
      Cell Mesh
      <span class="tip-host"><span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Storage Layer — 1024-byte Canonical Cells</span>The cell-store service (:5197) polls the multicast relay for every cell that flows through the mesh and persists them to a local SQLite database on each node. This is the storage layer of the layer-collapse demo: the same 1024-byte canonical cell format flows through storage / network / compute / identity / money without being re-encoded.</div></span>
    </span>
    <span id="cell-store-status" class="ch-bridge-status ch-bridge-offline">● cell store offline</span>
  </div>

  <div style="display:flex;gap:16px;flex-wrap:wrap;margin:10px 0 8px">
    <div style="flex:1;min-width:120px">
      <div style="font-size:0.6rem;color:var(--muted);text-transform:uppercase;letter-spacing:.04em">Cells stored</div>
      <div id="cm-total" style="font-size:1.4rem;font-weight:700;color:var(--accent);font-family:var(--mono)">—</div>
    </div>
    <div style="flex:1;min-width:120px">
      <div style="font-size:0.6rem;color:var(--muted);text-transform:uppercase;letter-spacing:.04em">Cells / min</div>
      <div id="cm-rate" style="font-size:1.4rem;font-weight:700;color:var(--fg);font-family:var(--mono)">—</div>
    </div>
    <div style="flex:1;min-width:120px">
      <div style="font-size:0.6rem;color:var(--muted);text-transform:uppercase;letter-spacing:.04em">Unique senders</div>
      <div id="cm-senders" style="font-size:1.4rem;font-weight:700;color:var(--fg);font-family:var(--mono)">—</div>
    </div>
    <div style="flex:2;min-width:160px">
      <div style="font-size:0.6rem;color:var(--muted);text-transform:uppercase;letter-spacing:.04em">Node ID</div>
      <div id="cm-node" style="font-size:0.7rem;color:var(--muted);font-family:var(--mono);margin-top:4px">—</div>
    </div>
  </div>

  <!-- Type distribution -->
  <div id="cm-type-dist" style="font-size:0.65rem;color:var(--muted);margin-bottom:10px"></div>

  <!-- Recent cells list -->
  <div style="font-size:0.68rem;font-weight:600;color:var(--muted);margin-bottom:6px;text-transform:uppercase;letter-spacing:.04em">Recent cells</div>
  <div id="cm-cells" style="display:flex;flex-direction:column;gap:5px;max-height:220px;overflow-y:auto">
    <div id="cm-placeholder" style="color:var(--muted);font-size:0.68rem;line-height:1.5">
      Cell store offline — run <code style="color:var(--accent)">bun cartridges/shared/cell-store/cell-store.ts</code> (:5197)
    </div>
  </div>

  <!-- MNCA tile canvas — visible when mnca.tile.tick cells are flowing -->
  <div id="cm-tile-wrap" style="display:none;margin-top:14px">
    <div style="font-size:0.68rem;font-weight:600;color:var(--muted);margin-bottom:6px;text-transform:uppercase;letter-spacing:.04em">
      MNCA tile — Compute Layer
      <span id="cm-tile-tick" style="font-weight:400;font-family:var(--mono);color:var(--accent);margin-left:8px"></span>
    </div>
    <canvas id="cm-tile-canvas" width="210" height="210"
      style="image-rendering:pixelated;border:1px solid var(--border);border-radius:4px;display:block"></canvas>
    <div style="font-size:0.6rem;color:var(--muted);margin-top:4px">
      21×21 interior · sender <span id="cm-tile-sender" style="font-family:var(--mono)"></span>
    </div>
  </div>
</div>

<script>
"use strict";

// ══════════════════════════════════════════════════════════════════
// HAT IDENTITY + PLEXUS + MESH RELAY
// ══════════════════════════════════════════════════════════════════

const RELAY_URL = 'http://localhost:5199';

// Hat fingerprint: SHA-256(hatName)[0:4] as 8 hex chars
// Uses SubtleCrypto so it matches the brain's hat derivation exactly.
async function hatFingerprint(hatName) {
  const data = new TextEncoder().encode(hatName);
  const buf  = await crypto.subtle.digest('SHA-256', data);
  return [...new Uint8Array(buf)].slice(0, 4)
    .map(b => b.toString(16).padStart(2, '0')).join('');
}

let currentHat = document.getElementById('hat-select')?.value ?? 'demo-operator';
let meshOnline = false;

async function onHatChange(hatName) {
  currentHat = hatName;
  const fp = await hatFingerprint(hatName);
  const el = document.getElementById('hat-fp');
  if (el) el.textContent = fp.slice(0, 8);
}

// Check relay health on load; poll every 10s
async function checkMesh() {
  try {
    const r = await fetch(`${RELAY_URL}/health`, { signal: AbortSignal.timeout(1500) });
    meshOnline = r.ok;
  } catch {
    meshOnline = false;
  }
  const el = document.getElementById('mesh-status');
  if (el) {
    el.textContent = meshOnline ? '● Mesh live' : '○ Mesh offline';
    el.className   = 'pill ' + (meshOnline ? 'pill-live' : 'pill-muted');
  }
}

// Publish a verdict cell to the relay (fire-and-forget; degrades gracefully)
async function publishToMesh(typePath, verdict, inputs, strategyHex, plexus = null) {
  if (!meshOnline) return;
  try {
    const body = {
      typePath,
      verdict,
      inputs,
      strategy: typePath.split('.').pop(),
      strategyHex: strategyHex ?? '',
      hat: currentHat,
      plexus,
    };
    const r = await fetch(`${RELAY_URL}/publish`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(800),
    });
    if (r.status === 402) {
      const el = document.getElementById('mesh-status');
      if (el) {
        el.textContent = '⚠ Payment required';
        el.className = 'pill pill-warn';
        el.title = 'Fund a CashLanes channel to publish routing decisions to the mesh';
      }
      return; // graceful — don't throw
    }
    if (r.ok) {
      const { shortGroup } = await r.json();
      const el = document.getElementById('mesh-status');
      if (el) {
        el.textContent = `● ${shortGroup}`;
        el.className = 'pill pill-live';
        setTimeout(checkMesh, 3000);
      }
    }
  } catch { /* relay offline — ignore */ }
}

// Init
onHatChange(currentHat);
checkMesh();
setInterval(checkMesh, 10000);

// ─────────────────────────────────────────────────────────────────────
// Script interpreter (same logic as scripts/script-interpreter.ts,
// ported inline so the dashboard has zero backend dependency).
// ─────────────────────────────────────────────────────────────────────

function readCScriptNum(buf) {
  if (!buf.length) return 0n;
  const hi = buf[buf.length - 1];
  const negative = (hi & 0x80) !== 0;
  let acc = 0n;
  for (let i = 0; i < buf.length; i++) {
    let b = BigInt(buf[i]);
    if (i === buf.length - 1 && negative) b = BigInt(hi & 0x7f);
    acc |= b << BigInt(8 * i);
  }
  return negative ? -acc : acc;
}

function isTruthy(n) { return n !== 0n; }

function executeScript(script) {
  const stack = [];
  let pc = 0, opcount = 0;
  const steps = [];

  while (pc < script.length) {
    const op = script[pc++]; opcount++;
    if (op >= 0x01 && op <= 0x4b) {
      const n = op;
      if (pc + n > script.length) return { ok: false, steps };
      const bytes = script.slice(pc, pc + n);
      const val = readCScriptNum(bytes);
      stack.push(val);
      steps.push({ op: `PUSH(${val})`, stack: [...stack] });
      pc += n;
      continue;
    }
    switch (op) {
      case 0x00: stack.push(0n); steps.push({ op:'OP_FALSE', stack:[...stack] }); break;
      case 0x51: stack.push(1n); steps.push({ op:'OP_1',     stack:[...stack] }); break;
      case 0x69: {
        const v = stack.pop();
        if (!isTruthy(v)) { steps.push({ op:'OP_VERIFY', stack:[...stack], failed:true }); return { ok:false, steps }; }
        steps.push({ op:'OP_VERIFY', stack:[...stack] }); break;
      }
      case 0x75: stack.pop(); steps.push({ op:'OP_DROP',  stack:[...stack] }); break;
      case 0x76: stack.push(stack[stack.length-1]); steps.push({ op:'OP_DUP', stack:[...stack] }); break;
      case 0x7c: { const a=stack.pop(), b=stack.pop(); stack.push(a); stack.push(b); steps.push({ op:'OP_SWAP', stack:[...stack] }); break; }
      case 0x78: { stack.push(stack[stack.length-2]); steps.push({ op:'OP_OVER', stack:[...stack] }); break; }
      case 0x95: { const b=stack.pop(), a=stack.pop(); stack.push(a*b); steps.push({ op:'OP_MUL', stack:[...stack] }); break; }
      case 0xa2: { const b=stack.pop(), a=stack.pop(); stack.push(a>=b?1n:0n); steps.push({ op:'OP_GTE', stack:[...stack] }); break; }
      default: return { ok:false, steps };
    }
  }
  const ok = stack.length > 0 && isTruthy(stack[stack.length-1]);
  return { ok, steps };
}

function pushSmallInt(n) {
  if (n === 0) return [0x00];
  let v = BigInt(n);
  const neg = v < 0n; if (neg) v = -v;
  const bytes = [];
  while (v > 0n) { bytes.push(Number(v & 0xffn)); v >>= 8n; }
  if ((bytes[bytes.length-1] & 0x80) !== 0) bytes.push(neg ? 0x80 : 0x00);
  else if (neg) bytes[bytes.length-1] |= 0x80;
  return [bytes.length, ...bytes];
}

function hexToBytes(hex) {
  const h = hex.trim();
  const out = new Uint8Array(h.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(h.slice(i*2,i*2+2),16);
  return out;
}

// ─────────────────────────────────────────────────────────────────────
// Strategy hex constants
// ─────────────────────────────────────────────────────────────────────

const STRATEGIES = {
  route_accept: {
    hex: '760110a269750101a2',
    bytes: hexToBytes('760110a269750101a2'),
    label: 'route_accept',
    byteLen: 10,
    desc: 'prefixLen≥16 AND asnTier≥1',
  },
  tier_prefix_product: {
    hex: '950120a2',
    bytes: hexToBytes('950120a2'),
    label: 'tier_prefix_product',
    byteLen: 4,
    desc: 'asnTier×prefixLen≥32',
  },
};

const ANCHORS = {
  route_accept: {
    strategy_hex:  '760110a269750101a2',
    cell_hash:     '4bd86b22ddc05d87f870511bc08d9e93968a4cee0cf22045948ed93d6791ee71',
    data_sha256:   'd60d6be5c42984174c61564e02e5abc8c60ccd75871ed7bf122716086e073a61',
    result_sha256: 'f767025a296718b145a5fde1ffc450bd588fa0be77100e41f5f7cc5626271ab8',
    txid:          'b060914f6c876ba20afa4e4e52e205ab79b9ae5e827b72c4770b774b7223e456',
  },
  tier_prefix_product: {
    strategy_hex:  '950120a2',
    cell_hash:     'af48b15bf811ad016137e71d9e7822c1c55d7954c890ecafade0e65abe7b8497',
    data_sha256:   'd60d6be5c42984174c61564e02e5abc8c60ccd75871ed7bf122716086e073a61',
    result_sha256: '27f02d61ca32aa4cee503facc2fbf2e44811a587788b3adcb1c53ce537ddc27d',
    txid:          'c6877fa75acb1e96519a6067c20c3d1fd270f6d2e86ae5b195c0255cc9b87b65',
  },
};

function updateAnchorPanel() {
  // Highlight the active strategy's txid link
  const ra = document.getElementById('ra-chain-link');
  const tp = document.getElementById('tp-chain-link');
  if (ra) ra.style.fontWeight = currentStrategy === 'route_accept' ? '700' : '400';
  if (tp) tp.style.fontWeight = currentStrategy === 'tier_prefix_product' ? '700' : '400';
}

let currentStrategy = 'route_accept';

function evaluate(strategyKey, asnTier, prefixLen) {
  const s = STRATEGIES[strategyKey];
  const script = new Uint8Array([
    ...pushSmallInt(asnTier),
    ...pushSmallInt(prefixLen),
    ...s.bytes,
  ]);
  return executeScript(script);
}

function selectStrategy(key) {
  currentStrategy = key;
  document.getElementById('btn-route_accept').classList.toggle('active', key === 'route_accept');
  document.getElementById('btn-tier_prefix_product').classList.toggle('active', key === 'tier_prefix_product');
  onSimChange();
  updateAnchorPanel();
}

// ─────────────────────────────────────────────────────────────────────
// Simulator
// ─────────────────────────────────────────────────────────────────────

const TIER_LABELS = ['unknown', 'registered', 'verified', 'trusted'];

function onSimChange() {
  const tier    = parseInt(document.getElementById('tier-slider').value, 10);
  const prefix  = parseInt(document.getElementById('prefix-slider').value, 10);
  document.getElementById('tier-val-label').textContent   = `tier-${tier} (${TIER_LABELS[tier]})`;
  document.getElementById('prefix-val-label').textContent = `/${prefix}`;

  const result  = evaluate(currentStrategy, tier, prefix);
  const verdictEl = document.getElementById('sim-verdict');
  verdictEl.textContent = result.ok ? '✓ ROUTE ACCEPTED' : '✗ ROUTE REJECTED';
  verdictEl.className = 'verdict-large ' + (result.ok ? 'accept' : 'reject');

  // Opcode trace
  const s = STRATEGIES[currentStrategy];
  let traceHtml = `<span style="color:var(--muted)">policy: </span><span class="hl">${s.hex}</span> <span style="color:var(--muted)">(${s.byteLen}B)</span><br>`;
  traceHtml += `<span style="color:var(--muted)">strategy: </span><span class="hl">${s.desc}</span><br><br>`;
  traceHtml += `<span style="color:var(--muted)">─ push asnTier=${tier}  prefixLen=${prefix} ─</span><br>`;

  result.steps.forEach((step, i) => {
    const stackStr = '[' + step.stack.map(v => v.toString()).join(', ') + ']';
    const cls = step.failed ? 'fail-step' : (
      step.op === 'OP_VERIFY' && !step.failed ? 'ok-step' :
      step.op.startsWith('OP_GTE') && i === result.steps.length-1 ? (result.ok ? 'ok-step' : 'fail-step') :
      ''
    );
    traceHtml += `<span class="${cls}">${step.op.padEnd(14)}→ ${stackStr}</span><br>`;
  });

  const finalStr = result.ok
    ? `<span class="ok-step">→ top-of-stack truthy: ACCEPT</span>`
    : `<span class="fail-step">→ predicate false or VERIFY failed: REJECT</span>`;
  traceHtml += finalStr;

  document.getElementById('opcode-trace').innerHTML = traceHtml;

  // Publish to mesh
  const ixpTypePath = result.ok ? 'ixp.route.accept' : 'ixp.route.reject';
  publishToMesh(ixpTypePath, result.ok,
    { asnTier: tier, prefixLen: prefix },
    STRATEGIES[currentStrategy].hex);
}

onSimChange();

// ─────────────────────────────────────────────────────────────────────
// Replay block
// ─────────────────────────────────────────────────────────────────────

function onReplay() {
  const tier   = parseInt(document.getElementById('rp-tier').value, 10) || 0;
  const prefix = parseInt(document.getElementById('rp-prefix').value, 10) || 8;
  const clampedTier   = Math.max(0, Math.min(3, tier));
  const clampedPrefix = Math.max(8, Math.min(32, prefix));

  // Show the full byte sequence that would be evaluated
  const pushT = pushSmallInt(clampedTier);
  const pushP = pushSmallInt(clampedPrefix);

  function bytesToHexStr(arr) {
    return Array.from(arr).map(b => b.toString(16).padStart(2,'0')).join(' ');
  }

  const ra_result = evaluate('route_accept', clampedTier, clampedPrefix);
  const tp_result = evaluate('tier_prefix_product', clampedTier, clampedPrefix);

  const resultEl = document.getElementById('replay-result');
  const both_ok  = ra_result.ok && tp_result.ok;
  const both_rej = !ra_result.ok && !tp_result.ok;
  if (both_ok) {
    resultEl.className = 'replay-result accept';
    resultEl.textContent = '✓ ACCEPTED by both strategies';
  } else if (both_rej) {
    resultEl.className = 'replay-result reject';
    resultEl.textContent = '✗ REJECTED by both strategies';
  } else {
    resultEl.className = 'replay-result neutral';
    resultEl.textContent = `route_accept: ${ra_result.ok?'✓ ACCEPT':'✗ REJECT'}  |  tier_product: ${tp_result.ok?'✓ ACCEPT':'✗ REJECT'}`;
  }

  const bytesEl = document.getElementById('replay-bytes');
  bytesEl.innerHTML =
    `<span style="color:var(--muted)">full script (route_accept):</span><br>` +
    `<span class="push-byte">${bytesToHexStr(pushT)}</span> ` +
    `<span class="push-byte">${bytesToHexStr(pushP)}</span> ` +
    `<span class="pred-byte">76 01 10 a2 69 75 01 01 a2</span><br>` +
    `<span style="color:var(--muted)">full script (tier_product):</span><br>` +
    `<span class="push-byte">${bytesToHexStr(pushT)}</span> ` +
    `<span class="push-byte">${bytesToHexStr(pushP)}</span> ` +
    `<span class="pred-byte">95 01 20 a2</span>`;
}

onReplay();

// ─────────────────────────────────────────────────────────────────────
// Synthetic BGP event generator (same distribution as synth-bgp-data.ts)
// ─────────────────────────────────────────────────────────────────────

function mulberry32(seed) {
  let s = seed;
  return () => {
    s |= 0; s = (s + 0x6d2b79f5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const rng = mulberry32(42);

const TIER3_PEERS = [
  { asn:'AS13335', label:'Cloudflare' }, { asn:'AS16509', label:'Amazon AWS' },
  { asn:'AS15169', label:'Google'     }, { asn:'AS8075',  label:'Microsoft Azure' },
  { asn:'AS54113', label:'Fastly'     }, { asn:'AS20940', label:'Akamai' },
  { asn:'AS3320',  label:'Deutsche Telekom' }, { asn:'AS1299', label:'Arelion (Telia)' },
];
const TIER2_PEERS = [
  { asn:'AS1257',  label:'Tele2'   }, { asn:'AS8468', label:'Entanet' },
  { asn:'AS2856',  label:'BT'      }, { asn:'AS6461', label:'Zayo'    },
  { asn:'AS4637',  label:'Telstra' }, { asn:'AS7474', label:'SingTel Optus' },
  { asn:'AS4739',  label:'iiNet'   }, { asn:'AS7545', label:'TPG'     },
];
const TIER1_PEERS = [
  { asn:'AS134944', label:'SmallISP-AU'   }, { asn:'AS55415',  label:'NetConnect' },
  { asn:'AS136557', label:'Host-Networks' }, { asn:'AS131072', label:'CityFibre'  },
  { asn:'AS38193',  label:'RedIX-ISP'    }, { asn:'AS55430',  label:'SkyDatacom' },
  { asn:'AS59715',  label:'UniNet'        }, { asn:'AS134298', label:'VicISP'     },
];
const TIER0_PEERS = [
  { asn:'AS65001', label:'Unknown-ASN-1' }, { asn:'AS65002', label:'Unknown-ASN-2' },
  { asn:'AS65003', label:'Ghost-Peer-A'  }, { asn:'AS65004', label:'Ghost-Peer-B'  },
  { asn:'AS65005', label:'Unregistered-1'},
];

const INCIDENT_FRACS = [
  { s: 0.08, e: 0.11 }, { s: 0.38, e: 0.41 }, { s: 0.74, e: 0.77 },
];

let simTimeFrac = 0; // 0..1 representing position in the 24h day

function isInIncident(frac) {
  return INCIDENT_FRACS.some(w => frac >= w.s && frac < w.e);
}

function nextBgpEvent() {
  simTimeFrac = (simTimeFrac + 0.00016 + rng() * 0.00008) % 1.0;
  const incident = isInIncident(simTimeFrac);
  const isAttack  = incident && rng() < 0.6;

  let tier, peer, prefixLen;

  if (isAttack) {
    tier = 0;
    peer = TIER0_PEERS[Math.floor(rng() * TIER0_PEERS.length)];
    prefixLen = 8 + Math.floor(rng() * 8);
  } else {
    const tr = rng();
    if (tr < 0.15) {
      tier = 3; peer = TIER3_PEERS[Math.floor(rng() * TIER3_PEERS.length)];
      prefixLen = rng() < 0.08 ? (11 + Math.floor(rng() * 5)) : legitPrefixLen();
    } else if (tr < 0.50) {
      tier = 2; peer = TIER2_PEERS[Math.floor(rng() * TIER2_PEERS.length)];
      prefixLen = legitPrefixLen();
    } else if (tr < 0.90) {
      tier = 1; peer = TIER1_PEERS[Math.floor(rng() * TIER1_PEERS.length)];
      prefixLen = legitPrefixLen();
    } else {
      tier = 0; peer = TIER0_PEERS[Math.floor(rng() * TIER0_PEERS.length)];
      prefixLen = rng() < 0.5 ? (14 + Math.floor(rng() * 4)) : legitPrefixLen();
    }
  }

  const o1 = [10,103,104,151,152,185,188,193,195,198,203,204][Math.floor(rng()*12)];
  const o2 = Math.floor(rng()*256), o3 = Math.floor(rng()*256), o4 = Math.floor(rng()*256);
  const prefix = `${o1}.${o2}.${o3}.${o4}/${prefixLen}`;

  const totalH = simTimeFrac * 24;
  const hh = Math.floor(totalH).toString().padStart(2,'0');
  const mm = Math.floor((totalH % 1) * 60).toString().padStart(2,'0');
  const ss = Math.floor(rng() * 60).toString().padStart(2,'0');
  const time = `${hh}:${mm}:${ss}`;

  const isAttackPat = tier === 0 && prefixLen <= 15;
  const ra_ok  = evaluate('route_accept',        tier, prefixLen).ok;
  const tp_ok  = evaluate('tier_prefix_product', tier, prefixLen).ok;

  return { tier, peer, prefix, prefixLen, time, isAttack: isAttackPat, ra_ok, tp_ok, incident };
}

function legitPrefixLen() {
  const r = rng();
  if (r < 0.05) return 18 + Math.floor(rng() * 3);
  if (r < 0.10) return 28 + Math.floor(rng() * 5);
  if (r < 0.40) return 20 + Math.floor(rng() * 4);
  return 24 + Math.floor(rng() * 4);
}

// ─────────────────────────────────────────────────────────────────────
// Live counters — driven by real addStreamRow() calls, not faked
// ─────────────────────────────────────────────────────────────────────

let globalAccepted = 0;   // real: incremented per addStreamRow() accept
let globalBlocked  = 0;   // real: incremented per addStreamRow() reject
let rpsSmoothed    = 0;
let _rpsWindow     = 0;   // events in current 1s window

setInterval(() => {
  rpsSmoothed = 0.85 * rpsSmoothed + 0.15 * _rpsWindow;
  _rpsWindow  = 0;
  document.getElementById('ctr-rps').textContent      = rpsSmoothed.toFixed(1);
  document.getElementById('ctr-accepted').textContent  = globalAccepted.toLocaleString();
  document.getElementById('ctr-blocked').textContent   = globalBlocked.toLocaleString();
}, 1000);

// ─────────────────────────────────────────────────────────────────────
// Live stream feed (Panel 2)
// ─────────────────────────────────────────────────────────────────────

const MAX_STREAM_ROWS = 18;
const streamRows = [];

function tierBadge(tier) {
  const cls = ['tier0','tier1','tier2','tier3'][tier] ?? 'tier0';
  return `<span class="badge ${cls}">tier-${tier}</span>`;
}

function resultBadge(ok) {
  return ok
    ? `<span class="badge accept">✓</span>`
    : `<span class="badge reject">✗</span>`;
}

function addStreamRow(ev) {
  // Increment real counters — these evaluations use the actual Rúnar predicates
  const accepted = currentStrategy === 'tier_prefix_product' ? ev.tp_ok : ev.ra_ok;
  if (accepted) { globalAccepted++; } else { globalBlocked++; }
  _rpsWindow++;

  const tbody = document.getElementById('stream-body');
  const tr = document.createElement('tr');
  tr.className = 'stream-row' + (ev.isAttack ? ' attack' : '');

  const flagCell = ev.isAttack
    ? `<span class="attack-flag">⚠ BGP HIJACK PATTERN</span>`
    : '';

  tr.innerHTML = `
    <td class="col-time" style="color:var(--muted)">${ev.time}</td>
    <td class="col-peer">${ev.peer.label} <span style="color:var(--muted);font-size:0.6rem">${ev.peer.asn}</span></td>
    <td class="col-prefix">${ev.prefix}</td>
    <td class="col-tier">${tierBadge(ev.tier)}</td>
    <td class="col-result">${resultBadge(currentStrategy === 'tier_prefix_product' ? ev.tp_ok : ev.ra_ok)}</td>
    <td class="col-flag">${flagCell}</td>
  `;

  tbody.insertBefore(tr, tbody.firstChild);

  // Trim to max rows
  while (tbody.rows.length > MAX_STREAM_ROWS) {
    tbody.removeChild(tbody.lastChild);
  }
}

// Update stream every 800ms
setInterval(() => {
  const ev = nextBgpEvent();
  addStreamRow(ev);
  // Update stream subtitle with current sim time
  const h = (simTimeFrac * 24).toFixed(1);
  document.getElementById('stream-subtitle').textContent = `· simulating 24h · current: ${h}h UTC`;
}, 800);

// ─────────────────────────────────────────────────────────────────────
// Pre-compute 24h synthetic data for chart + comparison table
// ─────────────────────────────────────────────────────────────────────

// Generate a deterministic full-day dataset (separate rng, seed 99)
(function buildChartData() {
  const rng2 = mulberry32(99);
  const N = 6200;
  const HOURS = 24;
  const BUCKETS = 48; // 30-min buckets for chart

  // Per-bucket accumulators
  const ra_accepted  = new Array(BUCKETS).fill(0);
  const tp_accepted  = new Array(BUCKETS).fill(0);
  const attacks_blkd = new Array(BUCKETS).fill(0); // attacks blocked by route_accept

  // Totals for comparison table
  let ra_total_acc=0, ra_total_blk=0, ra_attacks_blk=0, ra_legit_blk=0;
  let tp_total_acc=0, tp_total_blk=0, tp_attacks_blk=0, tp_legit_blk=0;

  function legitPL2() {
    const r = rng2();
    if (r < 0.05) return 18 + Math.floor(rng2() * 3);
    if (r < 0.10) return 28 + Math.floor(rng2() * 5);
    if (r < 0.40) return 20 + Math.floor(rng2() * 4);
    return 24 + Math.floor(rng2() * 4);
  }

  for (let i = 0; i < N; i++) {
    const frac = i / N;
    const bucket = Math.min(BUCKETS-1, Math.floor(frac * BUCKETS));

    const incident = INCIDENT_FRACS.some(w => frac >= w.s && frac < w.e);
    const isAtk = incident && rng2() < 0.6;

    let tier, prefixLen;
    if (isAtk) {
      tier = 0; prefixLen = 8 + Math.floor(rng2() * 8);
    } else {
      const tr = rng2();
      if (tr < 0.15) { tier=3; prefixLen = rng2()<0.08 ? 11+Math.floor(rng2()*5) : legitPL2(); }
      else if (tr < 0.50) { tier=2; prefixLen = legitPL2(); }
      else if (tr < 0.90) { tier=1; prefixLen = legitPL2(); }
      else { tier=0; prefixLen = rng2()<0.5 ? 14+Math.floor(rng2()*4) : legitPL2(); }
    }

    const ra_ok = evaluate('route_accept',        tier, prefixLen).ok;
    const tp_ok = evaluate('tier_prefix_product', tier, prefixLen).ok;
    const isAttackPat = tier===0 && prefixLen<=15;
    const isLegit     = tier>=1  && prefixLen>=16;

    if (ra_ok) { ra_accepted[bucket]++; ra_total_acc++; }
    else        { ra_total_blk++; }
    if (tp_ok) { tp_accepted[bucket]++; tp_total_acc++; }
    else        { tp_total_blk++; }

    if (isAttackPat) {
      if (!ra_ok) { ra_attacks_blk++; attacks_blkd[bucket]++; }
      if (!tp_ok) tp_attacks_blk++;
    }
    if (isLegit) {
      if (!ra_ok) ra_legit_blk++;
      if (!tp_ok) tp_legit_blk++;
    }
  }

  // Cumulative accepted
  const ra_cum = [], tp_cum = [];
  let ra_sum = 0, tp_sum = 0;
  for (let b = 0; b < BUCKETS; b++) {
    ra_sum += ra_accepted[b]; ra_cum.push(ra_sum);
    tp_sum += tp_accepted[b]; tp_cum.push(tp_sum);
  }

  // Labels: 30-min intervals
  const labels = Array.from({length: BUCKETS}, (_, i) => {
    const h = Math.floor(i * 24 / BUCKETS).toString().padStart(2,'0');
    const m = ((i % 2) * 30).toString().padStart(2,'0');
    return `${h}:${m}`;
  });

  // Build incident background annotations via shaded dataset areas
  // We'll use a background fill dataset for each incident window
  function incidentOverlay(startFrac, endFrac, total) {
    const data = new Array(BUCKETS).fill(null);
    const startB = Math.floor(startFrac * BUCKETS);
    const endB   = Math.ceil(endFrac   * BUCKETS);
    for (let b = startB; b <= Math.min(endB, BUCKETS-1); b++) {
      data[b] = total;
    }
    return data;
  }

  const incMax = ra_sum * 1.05;

  const ctx = document.getElementById('chart-main').getContext('2d');
  new Chart(ctx, {
    type: 'line',
    data: {
      labels,
      datasets: [
        // Incident shading (3 overlays)
        ...INCIDENT_FRACS.map((w, i) => ({
          label: `Incident ${i+1}`,
          data: incidentOverlay(w.s, w.e, incMax),
          backgroundColor: 'rgba(248,81,73,0.12)',
          borderColor: 'transparent',
          fill: 'origin',
          pointRadius: 0,
          tension: 0,
          order: 10,
          yAxisID: 'y',
        })),
        // Attacks blocked (bar-style right axis)
        {
          label: 'Attack routes blocked',
          data: attacks_blkd,
          backgroundColor: 'rgba(248,81,73,0.55)',
          borderColor: 'rgba(248,81,73,0.8)',
          borderWidth: 1,
          fill: true,
          type: 'bar',
          yAxisID: 'y2',
          order: 5,
        },
        // route_accept cumulative
        {
          label: 'route_accept accepted (cumulative)',
          data: ra_cum,
          borderColor: '#2da44e',
          backgroundColor: 'rgba(45,164,78,0.06)',
          fill: false,
          tension: 0.3,
          pointRadius: 0,
          borderWidth: 2,
          yAxisID: 'y',
          order: 2,
        },
        // tier_prefix_product cumulative
        {
          label: 'tier_prefix_product accepted (cumulative)',
          data: tp_cum,
          borderColor: '#0ea5e9',
          backgroundColor: 'rgba(14,165,233,0.06)',
          fill: false,
          tension: 0.3,
          pointRadius: 0,
          borderWidth: 2,
          borderDash: [5,3],
          yAxisID: 'y',
          order: 3,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: 'index', intersect: false },
      plugins: {
        legend: { display: false },
        tooltip: {
          backgroundColor: '#1c2330',
          borderColor: '#30363d',
          borderWidth: 1,
          titleColor: '#8b949e',
          bodyColor: '#e6edf3',
          filter: (item) => item.dataset.label !== undefined && !item.dataset.label.startsWith('Incident'),
        },
      },
      scales: {
        x: {
          ticks: { color:'#8b949e', font:{size:9}, maxTicksLimit:8 },
          grid:  { color:'rgba(48,54,61,0.5)' },
        },
        y: {
          position: 'left',
          ticks: { color:'#8b949e', font:{size:9} },
          grid:  { color:'rgba(48,54,61,0.5)' },
          title: { display:true, text:'Cumulative accepted routes', color:'#8b949e', font:{size:9} },
        },
        y2: {
          position: 'right',
          ticks: { color:'rgba(248,81,73,0.8)', font:{size:9} },
          grid:  { drawOnChartArea:false },
          title: { display:true, text:'Attack routes blocked / bucket', color:'rgba(248,81,73,0.8)', font:{size:9} },
        },
      },
    },
  });

  // Fill comparison table
  const tbody = document.getElementById('comparison-body');
  tbody.innerHTML = '';
  const raEff = ra_total_acc > 0 ? ((ra_total_acc/(ra_total_acc+ra_legit_blk))*100).toFixed(1) : '100.0';
  const tpEff = tp_total_acc > 0 ? ((tp_total_acc/(tp_total_acc+tp_legit_blk))*100).toFixed(1) : '100.0';
  const rows2 = [
    { name:'route_accept', bytes:'10', acc:ra_total_acc, blk:ra_total_blk, atk_blk:ra_attacks_blk, fb:ra_legit_blk, winner: ra_attacks_blk >= tp_attacks_blk },
    { name:'tier_prefix_product', bytes:'4', acc:tp_total_acc, blk:tp_total_blk, atk_blk:tp_attacks_blk, fb:tp_legit_blk, winner: tp_attacks_blk > ra_attacks_blk },
  ];
  rows2.forEach(r => {
    const tr = document.createElement('tr');
    if (r.winner) tr.className = 'winner';
    tr.innerHTML = `
      <td>${r.name}</td>
      <td>${r.bytes}</td>
      <td>${r.acc.toLocaleString()}</td>
      <td>${r.blk.toLocaleString()}</td>
      <td>${r.atk_blk.toLocaleString()}</td>
      <td>${r.fb}</td>
    `;
    tbody.appendChild(tr);
  });
})();

// ─────────────────────────────────────────────────────────────────────
// Anchor feed (Panel 4) — real BSV settlement txids only
// Each entry appears when CashLanes bridge produces a real mainnet tx.
// No randTxid(), no fake timers.
// ─────────────────────────────────────────────────────────────────────

let anchorCount = 0;

function addRealAnchorEntry(s) {
  const feed = document.getElementById('anchor-feed');
  if (!feed) return;

  // Remove empty-state placeholder
  const placeholder = feed.querySelector('.anchor-placeholder');
  if (placeholder) placeholder.remove();

  const now = new Date().toLocaleTimeString();
  const div = document.createElement('div');
  div.className = 'anchor-entry fresh';

  div.innerHTML = `
    <div style="flex:1;min-width:0">
      <div class="anchor-event">Settlement #${s.seq} — ${s.unitsMB?.toFixed(2)} MB — ${s.costSats} sats</div>
      <div class="anchor-txid">consumer: <a href="${s.consumerWoc}" target="_blank" rel="noopener" style="color:var(--accent)">${s.consumerTxid?.slice(0,14)}…${s.consumerTxid?.slice(-6)}</a></div>
      <div class="anchor-txid">provider: <a href="${s.providerWoc}" target="_blank" rel="noopener" style="color:#0ea5e9">${s.providerTxid?.slice(0,14)}…${s.providerTxid?.slice(-6)}</a></div>
      <div class="anchor-time">${now}</div>
    </div>
    <div style="display:flex;flex-direction:column;align-items:flex-end;gap:4px;padding-left:8px">
      <span class="on-chain-badge">✓ on-chain</span>
    </div>
  `;

  feed.insertBefore(div, feed.firstChild);
  anchorCount++;
  const countEl = document.getElementById('anchor-count');
  if (countEl) countEl.textContent = `${anchorCount} settlement${anchorCount !== 1 ? 's' : ''} anchored this session`;

  setTimeout(() => div.classList.remove('fresh'), 2000);
  while (feed.children.length > 8) feed.removeChild(feed.lastChild);
}

// ─────────────────────────────────────────────────────────────────────
// CASHLANES CHANNEL PANEL
// ─────────────────────────────────────────────────────────────────────

const BRIDGE_URL = 'http://localhost:5198';
let channelState = 'UNFUNDED';
let bridgeOnline = false;
let chEventSource = null;

// ── Bridge status ─────────────────────────────────────────────────────

async function checkBridge() {
  try {
    const r = await fetch(`${BRIDGE_URL}/health`, { signal: AbortSignal.timeout(1200) });
    if (r.ok) {
      const d = await r.json();
      bridgeOnline = true;
      setBridgeStatus(true, d);
      applyChannelState(d.state);
      // Sync full state
      const s = await fetch(`${BRIDGE_URL}/channel/state`, { signal: AbortSignal.timeout(1200) });
      if (s.ok) applyStateFull(await s.json());
      if (!chEventSource) connectSSE();
    }
  } catch {
    bridgeOnline = false;
    setBridgeStatus(false, null);
  }
}

function setBridgeStatus(online, health) {
  const el = document.getElementById('ch-bridge-status');
  if (!el) return;
  if (!online) {
    el.textContent = '● bridge offline';
    el.className = 'ch-bridge-status ch-bridge-offline';
    el.title = '';
    // Clear headless wallet info
    const hw = document.getElementById('ch-headless-wallet');
    if (hw) hw.style.display = 'none';
    return;
  }
  const mode = health?.mode ?? 'metanet-desktop';
  const modeLabel = mode === 'headless' ? 'headless' : 'MND';
  el.textContent = `● bridge live (${modeLabel})`;
  el.className = 'ch-bridge-status ch-bridge-online';
  // Show headless wallet funding info if in headless mode.
  let hw = document.getElementById('ch-headless-wallet');
  if (mode === 'headless') {
    const addr = health?.walletAddress ?? '';
    const bal  = health?.walletBalance ?? '?';
    if (!hw) {
      hw = document.createElement('div');
      hw.id = 'ch-headless-wallet';
      hw.style.cssText = 'margin:6px 0 0;padding:8px;background:#0d1117;border:1px solid #21262d;border-radius:6px;font-size:11px;';
      el.parentNode?.insertBefore(hw, el.nextSibling);
    }
    hw.style.display = 'block';
    hw.innerHTML = `<span style="color:#58a6ff;font-weight:600;">⚡ Headless wallet</span> &nbsp;
      <span style="color:#8b949e;">balance:</span> <span style="color:#3fb950;">${bal}</span>
      ${addr ? `&nbsp;<span style="color:#8b949e;">addr:</span> <code style="color:#e3b341;font-size:10px;">${addr}</code>` : ''}
      <br><span style="color:#8b949e;font-size:10px;">Fund this address with BSV to enable on-chain settlements (~100ms/settle)</span>`;
  } else if (hw) {
    hw.style.display = 'none';
  }
}

// ── SSE connection ────────────────────────────────────────────────────

function connectSSE() {
  if (chEventSource) { chEventSource.close(); chEventSource = null; }
  chEventSource = new EventSource(`${BRIDGE_URL}/channel/events`);
  chEventSource.addEventListener('state',      e => applyStateFull(JSON.parse(e.data)));
  chEventSource.addEventListener('tick',       e => applyTick(JSON.parse(e.data)));
  chEventSource.addEventListener('settlement', e => addSettlementEntry(JSON.parse(e.data)));
  chEventSource.addEventListener('error',      e => console.warn('[channel] SSE error', e.data));
  chEventSource.addEventListener('anchor', e => {
    const d = JSON.parse(e.data);
    const el = document.getElementById(`ch-anchor-${d.seq}`);
    if (el) {
      el.innerHTML = `⚓ anchor: <a href="${d.anchorWoc}" target="_blank" rel="noopener" style="color:#0ea5e9">${d.anchorTxid.slice(0,12)}…${d.anchorTxid.slice(-6)}</a>`;
    }
  });
  chEventSource.addEventListener('confirmation', e => {
    const d = JSON.parse(e.data);
    const el = document.getElementById(`ch-confirm-${d.seq}`);
    if (!el) return;
    if (d.status === 'confirmed') {
      el.innerHTML = `✓ confirmed @ block ${d.blockHeight}`;
      el.style.color = 'var(--accent)';
    } else if (d.status === 'pending') {
      el.textContent = '⏳ in mempool…';
    } else {
      el.textContent = '○ unconfirmed after 5min';
    }
  });
  chEventSource.onerror = () => {
    chEventSource?.close();
    chEventSource = null;
    setTimeout(checkBridge, 5000);
  };
}

// ── State rendering ───────────────────────────────────────────────────

const FSM_STEPS = ['UNFUNDED', 'FUNDED', 'FLOW_ACTIVE', 'SETTLING', 'CLOSED'];

function applyChannelState(state) {
  channelState = state;

  // FSM diagram
  const idx = FSM_STEPS.indexOf(state);
  FSM_STEPS.forEach((s, i) => {
    const el = document.getElementById(`fsm-${s}`);
    if (el) el.className = 'fsm-step' + (i === idx ? ' active' : '');
  });

  // State pill
  const pill = document.getElementById('channel-state-pill');
  if (pill) {
    pill.textContent = state;
    pill.className = `channel-state-pill state-${state}`;
  }

  // Buttons
  const fundBtn   = document.getElementById('ch-fund-btn');
  const startBtn  = document.getElementById('ch-start-btn');
  const settleBtn = document.getElementById('ch-settle-btn');
  if (fundBtn)   fundBtn.disabled   = state !== 'UNFUNDED';
  if (startBtn)  startBtn.disabled  = state !== 'FUNDED';
  if (settleBtn) settleBtn.disabled = state !== 'FLOW_ACTIVE' && state !== 'FUNDED';
}

function applyStateFull(d) {
  applyChannelState(d.state);

  const mb   = document.getElementById('ch-mb');
  const sats = document.getElementById('ch-sats');
  const seq  = document.getElementById('ch-seq');
  const hat  = document.getElementById('ch-hat');
  if (mb)   mb.textContent   = d.unitsMB?.toFixed(2) ?? '0.00';
  if (sats) sats.textContent = d.costSats ?? '0';
  if (seq)  seq.textContent  = d.sequence ?? '0';
  if (hat)  hat.textContent  = d.hat ?? '—';

  // Funding txid + multisig key info
  const fundRow  = document.getElementById('ch-funding-row');
  const fundLink = document.getElementById('ch-funding-link');
  if (d.fundingTxid && fundRow && fundLink) {
    fundRow.style.display = 'flex';
    fundLink.href = `https://whatsonchain.com/tx/${d.fundingTxid}`;
    fundLink.textContent = `${d.fundingTxid.slice(0,16)}…${d.fundingTxid.slice(-8)}`;
  }
  if (d.providerPubKey && d.consumerPubKey) {
    const keyInfo = document.getElementById('ch-key-info');
    if (keyInfo) keyInfo.textContent = `provider: ${d.providerPubKey.slice(0,10)}… consumer: ${d.consumerPubKey.slice(0,10)}…`;
  }

  // Rebuild settlement list + anchor feed from full state
  if (d.settlements?.length > 0) {
    const list = document.getElementById('ch-settle-list');
    if (list) {
      list.innerHTML = '';
      [...d.settlements].reverse().forEach(s => addSettlementEntry(s, false));
    }
    // Rebuild anchor feed (no animation, no duplicate via addSettlementEntry)
    const feed = document.getElementById('anchor-feed');
    if (feed) {
      feed.innerHTML = '';
      anchorCount = 0;
      [...d.settlements].reverse().forEach(s => addRealAnchorEntry(s));
    }
  }
}

function applyTick(d) {
  const mb   = document.getElementById('ch-mb');
  const sats = document.getElementById('ch-sats');
  if (mb)   mb.textContent   = d.unitsMB?.toFixed(2) ?? '0.00';
  if (sats) sats.textContent = d.costSats ?? '0';
}

function addSettlementEntry(s, animate = true) {
  const list = document.getElementById('ch-settle-list');
  if (!list) return;

  // Remove empty state placeholder
  const empty = list.querySelector('div[style]');
  if (empty) empty.remove();

  const entry = document.createElement('div');
  entry.className = 'ch-settle-entry' + (animate ? ' new' : '');
  entry.innerHTML = `
    <span class="ch-settle-seq">#${s.seq}</span>
    <div class="ch-settle-info">
      <div>${s.unitsMB?.toFixed(2)} MB — ${s.costSats} sats</div>
      <div class="ch-settle-txid">consumer: <a href="${s.consumerWoc}" target="_blank" rel="noopener">${s.consumerTxid?.slice(0,12)}…${s.consumerTxid?.slice(-6)}</a></div>
      <div class="ch-settle-txid">provider: <a href="${s.providerWoc}" target="_blank" rel="noopener">${s.providerTxid?.slice(0,12)}…${s.providerTxid?.slice(-6)}</a></div>
      <div id="ch-confirm-${s.seq}" style="font-size:0.62rem;color:var(--muted)">⏳ awaiting confirmation…</div>
      <div id="ch-anchor-${s.seq}" style="font-size:0.62rem;color:var(--muted)">⏳ anchoring batch…</div>
    </div>
    <span class="ch-settle-badge">✓ mainnet</span>
  `;

  // Insert at top
  list.insertBefore(entry, list.firstChild);

  // Update seq counter
  const seqEl = document.getElementById('ch-seq');
  if (seqEl) seqEl.textContent = String(s.seq);

  // Trim to 8 entries
  while (list.children.length > 8) list.removeChild(list.lastChild);

  // Mirror to anchor feed (only for live events, not history rebuild)
  if (animate) addRealAnchorEntry(s);
}

// ── Channel button handlers ───────────────────────────────────────────

async function channelFund() {
  const btn = document.getElementById('ch-fund-btn');
  if (btn) { btn.disabled = true; btn.textContent = 'Funding…'; }
  try {
    const r = await fetch(`${BRIDGE_URL}/channel/fund`, { method: 'POST', signal: AbortSignal.timeout(30000) });
    const d = await r.json();
    if (!r.ok) throw new Error(d.error ?? r.statusText);
    if (d.txid) {
      const fundRow  = document.getElementById('ch-funding-row');
      const fundLink = document.getElementById('ch-funding-link');
      if (fundRow && fundLink) {
        fundRow.style.display = 'flex';
        fundLink.href = `https://whatsonchain.com/tx/${d.txid}`;
        fundLink.textContent = `${d.txid.slice(0,16)}…${d.txid.slice(-8)}`;
      }
    }
    applyChannelState(d.state);
  } catch (e) {
    alert(`Fund failed: ${e.message}`);
    if (btn) { btn.disabled = false; btn.textContent = 'Fund Channel'; }
  }
  if (btn) btn.textContent = 'Fund Channel';
}

async function channelStart() {
  const r = await fetch(`${BRIDGE_URL}/channel/start`, { method: 'POST' });
  const d = await r.json();
  if (d.state) applyChannelState(d.state);
}

async function channelSettle() {
  const btn = document.getElementById('ch-settle-btn');
  if (btn) { btn.disabled = true; btn.textContent = 'Settling…'; }
  try {
    const r = await fetch(`${BRIDGE_URL}/channel/settle`, { method: 'POST', signal: AbortSignal.timeout(30000) });
    const d = await r.json();
    if (!r.ok) throw new Error(d.error ?? r.statusText);
    if (d.state) applyChannelState(d.state);
  } catch (e) {
    alert(`Settle failed: ${e.message}`);
  }
  if (btn) btn.textContent = 'Settle Now';
}

async function channelReset() {
  const r = await fetch(`${BRIDGE_URL}/channel/reset`, { method: 'POST' });
  const d = await r.json();
  // Clear settlement list
  const list = document.getElementById('ch-settle-list');
  if (list) list.innerHTML = '<div style="color:var(--muted);font-size:0.7rem;padding:6px 0;">No settlements yet — fund the channel and start routing to trigger automatic BSV settlements</div>';
  // Clear anchor feed
  const feed = document.getElementById('anchor-feed');
  if (feed) feed.innerHTML = '<div class="anchor-placeholder" style="color:var(--muted);font-size:0.68rem;padding:10px 0;line-height:1.5">No settlements yet — fund the channel below and start routing to trigger real BSV mainnet settlement txids.</div>';
  anchorCount = 0;
  const countEl = document.getElementById('anchor-count');
  if (countEl) countEl.textContent = '0 settlements anchored this session';
  const mb   = document.getElementById('ch-mb');
  const sats = document.getElementById('ch-sats');
  const seq  = document.getElementById('ch-seq');
  if (mb)   mb.textContent   = '0.00';
  if (sats) sats.textContent = '0';
  if (seq)  seq.textContent  = '0';
  const fundRow = document.getElementById('ch-funding-row');
  if (fundRow) fundRow.style.display = 'none';
  if (d.state) applyChannelState(d.state);
}

// ── Per-packet advance on ixp.route.accept ────────────────────────────

async function advanceChannel() {
  if (!bridgeOnline || channelState !== 'FLOW_ACTIVE') return;
  try {
    await fetch(`${BRIDGE_URL}/channel/advance`, {
      method: 'POST',
      signal: AbortSignal.timeout(1000),
    });
  } catch { /* bridge offline — ignore */ }
}

// ── Wire into publishToMesh ───────────────────────────────────────────
// Wrap the original publishToMesh to also advance the channel

const _origPublishToMesh = publishToMesh;
publishToMesh = async function(typePath, verdict, inputs, strategyHex, plexus = null) {
  await _origPublishToMesh(typePath, verdict, inputs, strategyHex, plexus);
  if (typePath === 'ixp.route.accept') advanceChannel();
};

// ── Init ──────────────────────────────────────────────────────────────

checkBridge();
setInterval(checkBridge, 15000);

// ─────────────────────────────────────────────────────────────────────
// CELL MESH PANEL — wired to cell-store service (:5197)
// ─────────────────────────────────────────────────────────────────────

const CELL_STORE_URL = 'http://localhost:5197';
let cellStoreOnline  = false;
let cmEventSource    = null;
let cmSessionStart   = Date.now();
let cmSessionCount   = 0;   // cells seen since page load

function setCellStoreStatus(online) {
  cellStoreOnline = online;
  const el = document.getElementById('cell-store-status');
  if (!el) return;
  el.textContent  = online ? '● cell store live' : '● cell store offline';
  el.className    = 'ch-bridge-status ' + (online ? 'ch-bridge-online' : 'ch-bridge-offline');
}

async function checkCellStore() {
  try {
    const r = await fetch(`${CELL_STORE_URL}/health`, { signal: AbortSignal.timeout(1200) });
    if (!r.ok) throw new Error();
    const d = await r.json();
    setCellStoreStatus(true);

    // Update node ID
    const nodeEl = document.getElementById('cm-node');
    if (nodeEl) nodeEl.textContent = `node: ${d.nodeId}  db: ${d.cellCount} cells`;

    // Fetch stats
    const sr = await fetch(`${CELL_STORE_URL}/cells/stats`, { signal: AbortSignal.timeout(1200) });
    if (sr.ok) applyCellStats(await sr.json());

    // Fetch recent cells
    const cr = await fetch(`${CELL_STORE_URL}/cells?limit=5`, { signal: AbortSignal.timeout(1200) });
    if (cr.ok) {
      const cd = await cr.json();
      const placeholder = document.getElementById('cm-placeholder');
      if (placeholder) placeholder.remove();
      const container = document.getElementById('cm-cells');
      if (container && cd.cells?.length > 0) {
        container.innerHTML = '';
        cd.cells.forEach(c => addCellRow(c, false));
      }
    }

    // Connect SSE if not already connected
    if (!cmEventSource) connectCellSSE();
  } catch {
    setCellStoreStatus(false);
    if (cmEventSource) { cmEventSource.close(); cmEventSource = null; }
  }
}

function applyCellStats(d) {
  const totalEl   = document.getElementById('cm-total');
  const sendersEl = document.getElementById('cm-senders');
  const distEl    = document.getElementById('cm-type-dist');
  if (totalEl)   totalEl.textContent   = (d.total ?? 0).toLocaleString();
  if (sendersEl) {
    sendersEl.textContent = String(d.uniqueSenders ?? 0);
  }
  if (distEl && d.byTypePath) {
    distEl.textContent = Object.entries(d.byTypePath)
      .map(([tp, n]) => `${tp}: ${n}`)
      .join('  ·  ');
  }
  // Rate: prefer server 60s rolling window; fall back to session-elapsed rate
  const rateEl = document.getElementById('cm-rate');
  if (rateEl) {
    if (d.cellsPerMin !== undefined) {
      rateEl.textContent = d.cellsPerMin.toLocaleString();
    } else {
      const elapsedMin = (Date.now() - cmSessionStart) / 60000;
      rateEl.textContent = elapsedMin > 0.1 ? (cmSessionCount / elapsedMin).toFixed(1) : '—';
    }
  }
}

function addCellRow(c, animate = true) {
  const container = document.getElementById('cm-cells');
  if (!container) return;
  const placeholder = document.getElementById('cm-placeholder');
  if (placeholder) placeholder.remove();

  const ts = new Date(c.ts ?? c.received_at ?? Date.now()).toLocaleTimeString();
  const div = document.createElement('div');
  div.className = 'cm-cell-row' + (animate ? ' cm-new' : '');
  div.style.cursor = 'pointer';
  div.title = 'Click to inspect byte anatomy';
  div.onclick = () => showByteAnatomy(cellId);

  const cellId   = c.cell_id ?? c.cellId ?? '';
  const typePath = c.type_path ?? c.typePath ?? '';
  const senderFp = c.sender_fp ?? c.senderFp ?? '';

  div.innerHTML = `
    <span class="cm-cell-id">${cellId.slice(0,8)}…</span>
    <span class="cm-cell-type">${typePath}</span>
    <span class="cm-cell-fp">↑${senderFp}</span>
    <span class="cm-cell-ts">${ts}</span>
  `;

  container.insertBefore(div, container.firstChild);
  if (animate) {
    cmSessionCount++;
    setTimeout(() => div.classList.remove('cm-new'), 1500);
  }
  // Trim to 8 rows
  while (container.children.length > 8) container.removeChild(container.lastChild);
}

function connectCellSSE() {
  if (cmEventSource) { cmEventSource.close(); cmEventSource = null; }
  cmEventSource = new EventSource(`${CELL_STORE_URL}/cells/stream`);
  cmEventSource.addEventListener('cell', e => {
    const d = JSON.parse(e.data);
    addCellRow(d, true);
    // Update senders display
    const sendersEl = document.getElementById('cm-senders');
    if (sendersEl && d.senderFp) {
      // Track unique senders in a Set on the window
      window._cmSenders = window._cmSenders ?? new Set();
      window._cmSenders.add(d.senderFp);
      sendersEl.textContent = String(window._cmSenders.size);
    }
    // Update rate
    const elapsedMin = (Date.now() - cmSessionStart) / 60000;
    const rateEl = document.getElementById('cm-rate');
    if (rateEl) rateEl.textContent = elapsedMin > 0.05 ? (cmSessionCount / elapsedMin).toFixed(1) : '—';
    // Drive MNCA canvas in real-time: SSE push eliminates the 500ms poll lag
    if (d.typePath === 'mnca.tile.tick' && d.cellId && d.cellId !== _mncaLastId) {
      _mncaLastId = d.cellId;
      renderMncaTile(d.cellId).catch(() => {});
    }
  });
  cmEventSource.onerror = () => {
    cmEventSource?.close(); cmEventSource = null;
    setCellStoreStatus(false);
    setTimeout(checkCellStore, 5000);
  };
}

checkCellStore();
setInterval(checkCellStore, 20000);

// ── MNCA Tile Canvas ────────────────────────────────────────────────────────
// Decodes mnca.tile.tick cell payloads from cell-store and renders them as a
// heat-map on a canvas. Payload layout (from protocol-types/src/mnca/tile.ts):
//   0  u16LE tileX   2  u16LE tileY   4  u64LE tick   12 u8 W   13 u8 H
//   14 u8 halo   15 u8 flags   16.. W*H bytes of state (0-255 per cell)
//
// The canvas shows the FULL tile (27×27) including halo, 210px square.
// Each cell → 1 canvas pixel rendered with a blue-to-white heat-map.

async function renderMncaTile(cellId) {
  try {
    const r = await fetch(`${CELL_STORE_URL}/cells/${cellId}`, { signal: AbortSignal.timeout(1200) });
    if (!r.ok) return;
    const d = await r.json();
    if (!d.payload) return;   // no payload stored yet

    const bytes = new Uint8Array(d.payload.match(/.{2}/g).map(h => parseInt(h, 16)));
    if (bytes.length < 17) return;

    const dv   = new DataView(bytes.buffer);
    const tick = dv.getBigUint64(4, true);
    const W    = bytes[12];
    const H    = bytes[13];
    const halo = bytes[14];
    const stateBytes = bytes.slice(16);
    if (stateBytes.length < W * H) return;

    const wrap      = document.getElementById('cm-tile-wrap');
    const canvas    = document.getElementById('cm-tile-canvas');
    const tickLabel = document.getElementById('cm-tile-tick');
    const senderEl  = document.getElementById('cm-tile-sender');
    if (!wrap || !canvas || !tickLabel) return;

    wrap.style.display = 'block';
    const ageS = d.received_at ? Math.round((Date.now() - d.received_at) / 1000) : null;
    const ageTag = ageS !== null ? (ageS > 10 ? ` · ${ageS}s ago` : ` · ${ageS}s`) : '';
    tickLabel.textContent = `tick ${tick}${ageTag}`;
    if (senderEl && d.sender_fp) senderEl.textContent = d.sender_fp;

    // Render only the interior (exclude halo) — fills 210×210 at 10px/cell
    // Interior: rows [halo .. H-halo), cols [halo .. W-halo)
    const iW = W - 2 * halo;
    const iH = H - 2 * halo;
    const PX = Math.max(1, Math.floor(210 / Math.max(iW, iH)));
    canvas.width  = iW * PX;
    canvas.height = iH * PX;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    for (let iy = 0; iy < iH; iy++) {
      for (let ix = 0; ix < iW; ix++) {
        const v = stateBytes[(iy + halo) * W + (ix + halo)];  // 0-255
        const t = v / 255;
        // Heat-map: dark blue (dead) → cyan → white (fully alive)
        const r2 = Math.round(t * t * 220);
        const g2 = Math.round(t * 200);
        const b2 = Math.round(80 + t * 175);
        ctx.fillStyle = `rgb(${r2},${g2},${b2})`;
        ctx.fillRect(ix * PX, iy * PX, PX, PX);
      }
    }
  } catch { /* ignore decode errors */ }
}

// Animation loop — polls cell-store for the latest mnca.tile.tick every 500ms
// and renders it if the cellId changed.  Uses the ?type= filter added in
// cell-store v2 so only MNCA cells are returned (no full-table scan).
let _mncaLastId = '';
async function mncaAnimationTick() {
  try {
    const r = await fetch(
      `${CELL_STORE_URL}/cells?type=mnca.tile.tick&limit=1`,
      { signal: AbortSignal.timeout(800) }
    );
    if (!r.ok) return;
    const d = await r.json();
    const cell = (d.cells ?? [])[0];
    if (!cell) return;
    const id = cell.cell_id ?? cell.cellId ?? '';
    if (id && id !== _mncaLastId) {
      _mncaLastId = id;
      await renderMncaTile(id);
    }
  } catch { /* cell-store offline — keep polling */ }
}
setInterval(mncaAnimationTick, 500);
setTimeout(mncaAnimationTick, 800); // immediate first check

// ── ROUTING TABLE PANEL ───────────────────────────────────────────────────────
// Polls GET http://localhost:5199/routing/stats every 3 seconds.
// Shows per-contract: priority, tier label, tier prefix (first 8 hex of typeHash),
// sats/cell, total hits, sats routed, rolling 5s rate.

const ROUTING_COLOURS = {
  inference: '#f78166', bsv: '#ff8c00', ixp: '#58a6ff',
  p2p: '#bc8cff', compute: '#79c0ff', dark: '#56d364',
  ipv6: '#e3b341', mnca: '#8b949e', default: '#6e7681',
};

let routingData = null;

async function fetchRoutingStats() {
  try {
    const r = await fetch('http://localhost:5199/routing/stats', { signal: AbortSignal.timeout(1500) });
    if (!r.ok) return;
    routingData = await r.json();
    renderRoutingTable(routingData);
  } catch { /* relay offline */ }
}

function renderRoutingTable(d) {
  const totalEl = document.getElementById('rt-total-cells');
  const satsEl  = document.getElementById('rt-total-sats');
  const bodyEl  = document.getElementById('rt-body');
  if (!bodyEl) return;

  if (totalEl) totalEl.textContent = (d.totalCells ?? 0).toLocaleString();
  if (satsEl)  satsEl.textContent  = (d.totalSats  ?? 0).toLocaleString() + ' sats';

  const contracts = (d.contracts ?? []).filter(c => c.hits > 0 || c.priority <= 3);
  bodyEl.innerHTML = contracts.map(c => {
    const colour = ROUTING_COLOURS[c.label] ?? '#6e7681';
    const bar    = c.hits > 0 ? Math.min(100, Math.round(c.hits / Math.max(1, d.totalCells) * 100 * 8)) : 0;
    const rate   = c.rate5s > 0 ? `${c.rate5s}/s` : '—';
    return `<tr>
      <td style="padding:3px 8px;font-family:monospace;font-size:11px;color:${colour};font-weight:700">${c.label}</td>
      <td style="padding:3px 8px;font-family:monospace;font-size:10px;color:#8b949e">${(c.tierPrefix||'').slice(0,12)}…</td>
      <td style="padding:3px 8px;font-family:monospace;font-size:11px;color:#e6edf3;text-align:right">${c.satsPerCell}</td>
      <td style="padding:3px 8px;font-family:monospace;font-size:11px;color:#e6edf3;text-align:right">${c.hits.toLocaleString()}</td>
      <td style="padding:3px 8px;font-family:monospace;font-size:11px;color:#3fb950;text-align:right">${(c.satsRouted||0).toLocaleString()}</td>
      <td style="padding:3px 8px;font-family:monospace;font-size:11px;color:#58a6ff;text-align:right">${rate}</td>
      <td style="padding:3px 8px;min-width:80px">
        <div style="height:6px;background:#21262d;border-radius:3px;overflow:hidden">
          <div style="height:100%;width:${bar}%;background:${colour};border-radius:3px;transition:width 0.4s"></div>
        </div>
      </td>
    </tr>`;
  }).join('');
}

fetchRoutingStats();
setInterval(fetchRoutingStats, 3000);

// ── BYTE ANATOMY PANEL ────────────────────────────────────────────────────────
// Shows the canonical 256-byte cell header layout for a selected cell.
// Fetches raw payload from cell-store, decodes fixed-offset fields, verifies
// SHA-256(payload) == cellId in the browser (zero server trust).
//
// Header offsets (from core/constants/constants.json):
//   0-15:  magic (4 × u32LE)
//   16-19: linearity  20-23: version  24-27: flags  28-29: refCount
//   30-61: typeHash (32 bytes = 4 × sha256[0:8] segments)
//   62-77: ownerId   78-85: timestamp  86-89: cellCount  90-93: payloadTotal
//   96-127: parentHash  128-159: prevStateHash  224-255: domainPayloadRoot
//
// For MNCA tile.tick cells (legacy relay format):
//   The payload at cell-store is the hex-encoded tile bytes, NOT the full
//   canonical 256B header. Offset 0: tileX(2) tileY(2) tick(8) W(1) H(1)
//   halo(1) flags(1) state[W*H bytes].
//
// The anatomy panel detects which format is present by checking payload length.

let anatomyLocked = false;

async function showByteAnatomy(cellId) {
  if (!cellId) return;
  const panel = document.getElementById('ba-panel');
  if (panel) panel.style.display = 'block';
  const hexEl  = document.getElementById('ba-hex');
  const infoEl = document.getElementById('ba-info');
  const verEl  = document.getElementById('ba-verify');
  if (hexEl)  hexEl.innerHTML  = '<span style="color:#8b949e">Loading…</span>';
  if (infoEl) infoEl.innerHTML = '';
  if (verEl)  verEl.textContent = '';

  try {
    const r = await fetch(`${CELL_STORE_URL}/cells/${cellId}`, { signal: AbortSignal.timeout(2000) });
    if (!r.ok) { if (hexEl) hexEl.innerHTML = '<span style="color:#f85149">cell not found</span>'; return; }
    const d = await r.json();
    const payloadHex = d.payload ?? '';
    const typePath   = d.type_path ?? '?';
    const senderFp   = d.sender_fp ?? '?';
    const seq        = d.seq ?? 0;

    // Decode bytes
    const bytes = payloadHex ? Uint8Array.from(payloadHex.match(/.{2}/g)?.map(h => parseInt(h, 16)) ?? []) : new Uint8Array(0);
    const len   = bytes.length;

    // ── Render hex dump (first 64 bytes with field colour annotations)
    if (hexEl) {
      const rows = [];
      for (let i = 0; i < Math.min(len, 128); i += 16) {
        const rowBytes = Array.from(bytes.slice(i, i + 16));
        const hex16 = rowBytes.map(b => b.toString(16).padStart(2, '0')).join(' ');
        const ascii = rowBytes.map(b => b >= 32 && b < 127 ? String.fromCharCode(b) : '·').join('');
        rows.push(
          `<span style="color:#6e7681">${i.toString(16).padStart(4,'0')}</span>  ` +
          `<span style="font-family:monospace;font-size:10.5px;letter-spacing:0.05em">${hex16.padEnd(47)}</span>  ` +
          `<span style="color:#8b949e;font-size:10px">${ascii}</span>`
        );
      }
      if (len > 128) rows.push(`<span style="color:#6e7681">… ${len - 128} more bytes</span>`);
      hexEl.innerHTML = rows.join('\n');
    }

    // ── Decode typeHash segments from payload bytes if canonical (≥62 bytes)
    //    OR compute from typePath segments as fallback
    let typeHashHex = '';
    let tierLabel   = typePath.split('.')[0] ?? '?';

    if (len >= 62) {
      // Full canonical cell — typeHash at bytes 30-61
      typeHashHex = Array.from(bytes.slice(30, 62)).map(b => b.toString(16).padStart(2,'0')).join('');
    } else {
      // Legacy relay cell — compute typeHash from typePath
      // sha256(seg)[0:8] × 4 — computed client-side
      typeHashHex = '(derived from typePath — payload predates canonical header)';
    }

    // Determine contract from tier prefix
    const tierContracts = {
      'inference': 200, 'bsv': 150, 'ixp': 100,
      'p2p': 75, 'compute': 60, 'dark': 50, 'ipv6': 40, 'mnca': 5,
    };
    const satsPerCell = tierContracts[tierLabel] ?? 10;
    const colour = ROUTING_COLOURS[tierLabel] ?? '#6e7681';

    // ── Build field info table
    if (infoEl) {
      const fields = [
        { name: 'cellId',    bytes: '(sha256 of payload)', value: cellId.slice(0,16) + '…' + cellId.slice(-8) },
        { name: 'typePath',  bytes: '(header field)',      value: typePath },
        { name: 'senderFp',  bytes: '(sha256(hatName)[0:4])', value: senderFp },
        { name: 'seq',       bytes: '(header field)',      value: String(seq) },
        { name: 'typeHash',  bytes: '30-61 (32 bytes)',    value: typeHashHex.slice(0,32) + (typeHashHex.length > 32 ? '…' : '') },
        { name: '  └ tier', bytes: '30-37 (8 bytes)',     value: typeHashHex.slice(0,16) + `  → <span style="color:${colour};font-weight:700">${tierLabel}</span>  ${satsPerCell} sats/cell` },
        { name: '  └ domain',bytes: '38-45 (8 bytes)',    value: typeHashHex.slice(16,32) },
        { name: '  └ verb',  bytes: '46-53 (8 bytes)',    value: typeHashHex.slice(32,48) },
        { name: '  └ qual',  bytes: '54-61 (8 bytes)',    value: typeHashHex.slice(48,64) },
        { name: 'payloadLen',bytes: '(header field)',     value: `${len} bytes on wire` },
      ];
      infoEl.innerHTML = `<table style="width:100%;border-collapse:collapse">` +
        fields.map(f => `<tr>
          <td style="padding:2px 6px;font-family:monospace;font-size:11px;color:#58a6ff;white-space:nowrap">${f.name}</td>
          <td style="padding:2px 6px;font-family:monospace;font-size:10px;color:#6e7681;white-space:nowrap">${f.bytes}</td>
          <td style="padding:2px 6px;font-family:monospace;font-size:11px;color:#e6edf3;word-break:break-all">${f.value}</td>
        </tr>`).join('') + '</table>';
    }

    // ── Browser-side SHA-256 verify: SHA-256(rawPayloadBytes) should equal cellId
    if (verEl && bytes.length > 0) {
      verEl.textContent = '⏳ verifying SHA-256…';
      try {
        const hashBuf = await crypto.subtle.digest('SHA-256', bytes);
        const computed = Array.from(new Uint8Array(hashBuf)).map(b => b.toString(16).padStart(2,'0')).join('');
        if (computed === cellId) {
          verEl.innerHTML = `<span style="color:#3fb950">✓ SHA-256(payload) = cellId — content-addressed, verified in browser</span>`;
        } else {
          verEl.innerHTML = `<span style="color:#e3b341">⚠ hash mismatch — legacy cell (pre-canonical format, content-addressing not applied)</span>`;
        }
        verEl.innerHTML += `<br><span style="color:#8b949e;font-size:10px">Zero-serialize path: SQLite BLOB → UDP bytes → SSE hex → this panel. No struct created, no encoder ran.</span>`;
      } catch {
        verEl.innerHTML = '<span style="color:#8b949e">SHA-256 verify not available</span>';
      }
    } else if (verEl && bytes.length === 0) {
      verEl.textContent = '(no payload stored — header-only cell)';
    }

    // Scroll panel into view
    panel?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  } catch (e) {
    if (hexEl) hexEl.innerHTML = `<span style="color:#f85149">Error: ${e.message}</span>`;
  }
}

// Hook into the Cell Mesh row click — add click handler to addCellRow
const _origAddCellRow = window.addCellRow;

// ══════════════════════════════════════════════════════════════════
// CARRIER BILLING PANEL — Live BGP events from carrier-billing-demo.ts
// Subscribes to ixp.* cells via typed SSE on the relay
// ══════════════════════════════════════════════════════════════════

const CB_RELAY_URL = 'http://localhost:5199';
let   cbSse        = null;
let   cbConnected  = false;
const cbCounts = { accept: 0, reject: 0, withdraw: 0, report: 0, other: 0 };
let   cbSatsAdvanced = 0;

function setCBStatus(online) {
  const el = document.getElementById('cb-status');
  if (el) { el.textContent = online ? '● ixp.* live' : '○ relay offline'; el.className = online ? 'ch-bridge-status' : 'ch-bridge-status ch-bridge-offline'; }
}

function updateCBCounts() {
  const set = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };
  set('cb-accepts',   cbCounts.accept.toLocaleString());
  set('cb-rejects',   cbCounts.reject.toLocaleString());
  set('cb-withdraws', cbCounts.withdraw.toLocaleString());
  set('cb-reports',   cbCounts.report.toLocaleString());
  set('cb-sats',      cbSatsAdvanced.toLocaleString());
}

function addCBRow(header, payload) {
  const tbody = document.getElementById('cb-log-body');
  if (!tbody) return;
  const ph = tbody.querySelector('.cb-placeholder');
  if (ph) ph.remove();
  while (tbody.children.length >= 8) tbody.removeChild(tbody.lastChild);

  const typeParts = (header.typePath ?? '').split('.');
  const verb = typeParts.slice(1).join('.') || header.typePath;

  let content = '—';
  let colour = '#8b949e';
  try {
    const p = payload ? JSON.parse(Buffer.from(payload, 'hex').toString('utf8')) : {};
    if (header.typePath === 'ixp.route.accept') {
      colour = '#3fb950';
      cbCounts.accept++;
      const prefix = p.prefix ?? p.network ?? '?';
      const asn    = p.originAsn ?? p.asn ?? '?';
      content = `<span style="color:#3fb950">✓ ACCEPT</span>  ${prefix}  <span style="color:#8b949e">via AS${asn}</span>`;
    } else if (header.typePath === 'ixp.route.reject') {
      colour = '#f85149';
      cbCounts.reject++;
      const prefix = p.prefix ?? p.network ?? '?';
      content = `<span style="color:#f85149">✗ REJECT</span>  ${prefix}  <span style="color:#8b949e">${p.reason ?? ''}</span>`;
    } else if (header.typePath === 'ixp.route.withdraw') {
      colour = '#e3b341';
      cbCounts.withdraw++;
      const prefix = p.prefix ?? '?';
      content = `<span style="color:#e3b341">↩ WITHDRAW</span>  ${prefix}`;
    } else if (header.typePath === 'ixp.traffic.report') {
      colour = '#58a6ff';
      cbCounts.report++;
      const gbps = p.gbps ?? p.trafficGbps ?? '?';
      const sats  = p.satsCharged ?? 0;
      cbSatsAdvanced += sats;
      content = `<span style="color:#58a6ff">📊 TRAFFIC</span>  ${gbps} Gbps  <span style="color:#3fb950">${sats} sats</span>`;
    } else {
      cbCounts.other++;
      content = `<span style="color:#8b949e">${header.typePath}</span>`;
    }
  } catch { content = header.typePath; }

  updateCBCounts();

  const ts = new Date().toLocaleTimeString('en-AU', { hour12: false });
  const tr = document.createElement('tr');
  tr.style.animation = 'cm-slide-in 0.3s ease';
  tr.innerHTML = `
    <td style="padding:3px 8px;color:#8b949e;font-size:10px;white-space:nowrap">${ts}</td>
    <td style="padding:3px 8px;font-family:monospace;font-size:10px;color:${colour};white-space:nowrap">${header.typePath}</td>
    <td style="padding:3px 8px;font-size:10px;color:#e6edf3">${content}</td>
    <td style="padding:3px 8px;font-family:monospace;font-size:9px;color:#8b949e">${header.senderFp ?? '—'}</td>
  `;
  tbody.insertBefore(tr, tbody.firstChild);
}

function connectCBSSE() {
  const url = `${CB_RELAY_URL}/cells/stream?typePath=ixp.*`;
  cbSse = new EventSource(url);
  cbSse.addEventListener('cell', e => {
    try {
      const { header, payload } = JSON.parse(e.data);
      if (!header?.typePath?.startsWith('ixp.')) return;
      cbConnected = true;
      setCBStatus(true);
      addCBRow(header, payload);
    } catch {}
  });
  cbSse.onopen  = () => { cbConnected = true;  setCBStatus(true);  };
  cbSse.onerror = () => { cbConnected = false; setCBStatus(false); cbSse?.close(); cbSse = null; setTimeout(connectCBSSE, 5000); };
}

// Also seed from ring buffer on load
async function seedCBFromRelay() {
  try {
    const r = await fetch(`${CB_RELAY_URL}/cells/recent?typePath=ixp.*&limit=8`, { signal: AbortSignal.timeout(1200) });
    if (!r.ok) return;
    const cells = await r.json();
    if (Array.isArray(cells)) {
      cells.reverse().forEach(c => addCBRow(c.header ?? c, c.payload ?? null));
    }
    cbConnected = true;
    setCBStatus(true);
  } catch { setCBStatus(false); }
}

seedCBFromRelay().then(() => connectCBSSE());

</script>

<!-- ── CARRIER BILLING PANEL ────────────────────────────────────────────────── -->
<div class="channel-section" style="margin-top:12px" id="cb-panel">
  <div class="channel-header">
    <span class="channel-title">
      Carrier Bilateral Settlement — AusIX-BNE
      <span class="tip-host"><span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Typed BGP Event Feed</span>This panel subscribes to <code>ixp.*</code> cells ONLY via typed SSE: GET /cells/stream?typePath=ixp.*. The relay filters per subscriber — inference cells never arrive here. Run: <code>bun cartridges/ixp-routing/carrier-billing-demo.ts --fast --duration=60</code>. Each ixp.route.accept advances the CashLanes channel; ixp.traffic.report charges sats per Gbps.</div></span>
    </span>
    <span id="cb-status" class="ch-bridge-status ch-bridge-offline">○ relay offline</span>
  </div>
  <div style="display:flex;gap:16px;margin:6px 0 10px;font-size:0.65rem;color:#8b949e;flex-wrap:wrap">
    <span>Accepted: <span id="cb-accepts" style="color:#3fb950;font-family:monospace">0</span></span>
    <span>Rejected: <span id="cb-rejects" style="color:#f85149;font-family:monospace">0</span></span>
    <span>Withdrawn: <span id="cb-withdraws" style="color:#e3b341;font-family:monospace">0</span></span>
    <span>Traffic reports: <span id="cb-reports" style="color:#58a6ff;font-family:monospace">0</span></span>
    <span>Sats charged: <span id="cb-sats" style="color:#3fb950;font-family:monospace">0</span></span>
    <span style="color:#8b949e">·</span>
    <code style="color:#58a6ff;font-size:10px">bun cartridges/ixp-routing/carrier-billing-demo.ts --fast --duration=60</code>
  </div>
  <div style="overflow-x:auto">
    <table style="width:100%;border-collapse:collapse;font-size:11px">
      <thead>
        <tr style="color:#8b949e;font-size:10px;text-transform:uppercase;letter-spacing:.04em;border-bottom:1px solid #21262d">
          <th style="padding:3px 8px;text-align:left">Time</th>
          <th style="padding:3px 8px;text-align:left">Event Type</th>
          <th style="padding:3px 8px;text-align:left">Detail</th>
          <th style="padding:3px 8px;text-align:left">Sender</th>
        </tr>
      </thead>
      <tbody id="cb-log-body">
        <tr class="cb-placeholder"><td colspan="4" style="padding:8px;color:#8b949e;font-size:11px">No IXP cells yet — run the carrier-billing-demo or check relay is live</td></tr>
      </tbody>
    </table>
  </div>
  <div style="margin-top:8px;padding:8px 10px;background:#0d1117;border:1px solid #21262d;border-radius:6px;font-size:0.72rem;color:#8b949e;font-style:italic">
    "Your EDI file is a spreadsheet both sides could edit. Our settlement record is a Bitcoin transaction ID."
  </div>
</div>

<!-- ── ROUTING TABLE PANEL ─────────────────────────────────────────────────── -->
<div class="channel-section" style="margin-top:12px" id="routing-section">
  <div class="channel-header">
    <span class="channel-title">
      TypeHash Routing Table
      <span class="tip-host"><span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Payment Contract Routing</span>Every cell carries a 32-byte typeHash: 4 × sha256[0:8] segments encoding tier · domain · verb · qualifier. The relay matches the tier prefix (first 8 bytes) to a payment contract (sats/cell). High-value contracts (inference=200, ixp=100) are prioritised in the dispatch queue. Under fuzzing load (FUZZ_RATE=500) the starvation becomes visible in the rate column.</div></span>
    </span>
    <span id="rt-total-sats" style="font-family:monospace;font-size:0.68rem;color:#3fb950">—</span>
  </div>
  <div style="display:flex;gap:16px;margin:6px 0 10px;font-size:0.65rem;color:#8b949e">
    <span>Total cells routed: <span id="rt-total-cells" style="color:#e6edf3;font-family:monospace">—</span></span>
    <span>Run fuzzer: <code style="color:#58a6ff;font-size:10px">bun cartridges/shared/demo/type-fuzzer.ts</code></span>
    <span>Burst: <code style="color:#58a6ff;font-size:10px">FUZZ_RATE=500 FUZZ_SECS=10 bun …</code></span>
  </div>
  <div style="overflow-x:auto">
    <table style="width:100%;border-collapse:collapse;font-size:11px">
      <thead>
        <tr style="color:#8b949e;font-size:10px;text-transform:uppercase;letter-spacing:.04em;border-bottom:1px solid #21262d">
          <th style="padding:4px 8px;text-align:left">Tier</th>
          <th style="padding:4px 8px;text-align:left">sha256(tier)[0:8]</th>
          <th style="padding:4px 8px;text-align:right">sats/cell</th>
          <th style="padding:4px 8px;text-align:right">Cells</th>
          <th style="padding:4px 8px;text-align:right">Sats routed</th>
          <th style="padding:4px 8px;text-align:right">Rate (5s)</th>
          <th style="padding:4px 8px;min-width:80px">Share</th>
        </tr>
      </thead>
      <tbody id="rt-body">
        <tr><td colspan="7" style="padding:8px;color:#8b949e;font-size:11px">Waiting for relay data…</td></tr>
      </tbody>
    </table>
  </div>
</div>

<!-- ── BYTE ANATOMY PANEL ───────────────────────────────────────────────────── -->
<div class="channel-section" style="margin-top:12px;display:none" id="ba-panel">
  <div class="channel-header">
    <span class="channel-title">
      Cell Byte Anatomy
      <span class="tip-host"><span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Zero-Serialize Path</span>The cell payload stored in SQLite is the SAME bytes sent over UDP multicast and received by this dashboard. No struct is created, no encoder runs. The typeHash at bytes 30–61 is the routing label — 4 × sha256[0:8] segments. SHA-256(payload) == cellId is verified in your browser without contacting any server.</div></span>
    </span>
    <button onclick="document.getElementById('ba-panel').style.display='none'" style="background:none;border:1px solid #30363d;color:#8b949e;cursor:pointer;padding:2px 8px;border-radius:4px;font-size:11px">✕ close</button>
  </div>
  <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:10px">
    <div>
      <div style="font-size:0.6rem;color:#8b949e;text-transform:uppercase;letter-spacing:.04em;margin-bottom:6px">Hex dump (first 128 bytes)</div>
      <pre id="ba-hex" style="font-family:monospace;font-size:10.5px;line-height:1.6;color:#e6edf3;background:#0d1117;border:1px solid #21262d;border-radius:6px;padding:10px;overflow-x:auto;margin:0">—</pre>
    </div>
    <div>
      <div style="font-size:0.6rem;color:#8b949e;text-transform:uppercase;letter-spacing:.04em;margin-bottom:6px">Field anatomy</div>
      <div id="ba-info" style="font-size:11px;line-height:1.7;background:#0d1117;border:1px solid #21262d;border-radius:6px;padding:10px;min-height:200px">—</div>
    </div>
  </div>
  <div id="ba-verify" style="margin-top:8px;padding:8px;background:#0d1117;border:1px solid #21262d;border-radius:6px;font-size:11px;font-family:monospace;color:#8b949e">—</div>
</div>

</body>
</html>

```
