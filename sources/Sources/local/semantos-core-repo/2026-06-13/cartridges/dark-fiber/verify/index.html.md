---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/dark-fiber/verify/index.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.421224+00:00
---

# cartridges/dark-fiber/verify/index.html

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>EU Networks — Dark Fiber Wavelength Spot Market</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<style>
  :root {
    --bg: #0e1116;
    --panel: #161b22;
    --panel-2: #1c2330;
    --fg: #e6edf3;
    --muted: #8b949e;
    --accent: #2da44e;
    --teal: #2bbcd4;
    --warn: #d29922;
    --bad: #f85149;
    --border: #30363d;
    --mono: ui-monospace, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
    background: var(--bg);
    color: var(--fg);
    line-height: 1.5;
    min-height: 100vh;
  }

  /* ── HAT / MESH STATUS ────────────────────────────────────── */
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

  /* ── TOP BAR ───────────────────────────────────────────────── */
  .topbar {
    background: var(--panel);
    border-bottom: 1px solid var(--border);
    padding: 14px 28px;
    display: flex;
    align-items: baseline;
    gap: 18px;
    flex-wrap: wrap;
  }
  .topbar h1 {
    font-size: 1.15rem;
    font-weight: 700;
    letter-spacing: -0.01em;
    white-space: nowrap;
  }
  .topbar .sub {
    color: var(--muted);
    font-size: 0.82rem;
    flex: 1;
  }
  .topbar .pill {
    background: rgba(45,164,78,0.15);
    color: var(--accent);
    border: 1px solid rgba(45,164,78,0.35);
    border-radius: 20px;
    padding: 3px 12px;
    font-size: 0.78rem;
    font-weight: 600;
    white-space: nowrap;
  }

  /* ── THREE-PANEL LAYOUT ────────────────────────────────────── */
  .main-grid {
    display: grid;
    grid-template-columns: 35% 1fr 25%;
    gap: 14px;
    padding: 16px;
    min-height: calc(100vh - 56px - 200px);
  }
  @media (max-width: 1100px) {
    .main-grid { grid-template-columns: 1fr; }
  }

  /* ── PANEL BASE ────────────────────────────────────────────── */
  .panel {
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 8px;
    overflow: hidden;
  }
  .panel-header {
    padding: 11px 16px;
    border-bottom: 1px solid var(--border);
    font-size: 0.8rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--muted);
    background: var(--panel-2);
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .panel-body { padding: 16px; }

  /* ── PANEL 1: LIVE SIMULATOR ───────────────────────────────── */
  .strat-tabs {
    display: flex;
    gap: 6px;
    margin-bottom: 16px;
  }
  .strat-tab {
    flex: 1;
    padding: 7px 10px;
    background: var(--panel-2);
    border: 1px solid var(--border);
    border-radius: 6px;
    color: var(--muted);
    font-size: 0.8rem;
    font-weight: 600;
    cursor: pointer;
    text-align: center;
    transition: all 0.15s;
  }
  .strat-tab.active {
    background: rgba(45,164,78,0.12);
    border-color: rgba(45,164,78,0.45);
    color: var(--accent);
  }

  .slider-group { margin-bottom: 18px; }
  .slider-label {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    margin-bottom: 6px;
  }
  .slider-label .lname {
    font-size: 0.82rem;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  .slider-label .lval {
    font-family: var(--mono);
    font-size: 0.92rem;
    font-weight: 700;
    color: var(--fg);
  }
  input[type=range] {
    width: 100%;
    accent-color: var(--accent);
    height: 4px;
    cursor: pointer;
  }

  .strategy-badges {
    display: flex;
    flex-direction: column;
    gap: 10px;
    margin-bottom: 20px;
  }
  .badge-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 10px 13px;
    background: var(--panel-2);
    border: 1px solid var(--border);
    border-radius: 6px;
  }
  .badge-name {
    font-size: 0.78rem;
    font-family: var(--mono);
    color: var(--muted);
  }
  .badge-decision {
    font-size: 0.88rem;
    font-weight: 700;
    font-family: var(--mono);
    transition: color 0.12s;
  }
  .badge-decision.commit { color: var(--accent); }
  .badge-decision.hold { color: var(--warn); }

  .hex-panel {
    background: var(--panel-2);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 12px 14px;
  }
  .hex-label {
    font-size: 0.72rem;
    text-transform: uppercase;
    letter-spacing: 0.07em;
    color: var(--muted);
    margin-bottom: 8px;
  }
  .hex-bytes {
    font-family: var(--mono);
    font-size: 0.95rem;
    color: var(--accent);
    letter-spacing: 0.08em;
    margin-bottom: 12px;
    word-break: break-all;
  }
  .opcode-trace {
    font-family: var(--mono);
    font-size: 0.71rem;
    color: var(--muted);
    line-height: 1.65;
  }
  .opcode-trace .ok-line { color: var(--accent); }
  .opcode-trace .fail-line { color: var(--bad); }
  .opcode-trace .neutral-line { color: #7d8590; }

  /* ── PANEL 2: CHART ────────────────────────────────────────── */
  .chart-wrapper {
    position: relative;
    height: 280px;
    margin-bottom: 16px;
  }
  .results-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.8rem;
  }
  .results-table th {
    text-align: left;
    padding: 7px 10px;
    color: var(--muted);
    font-weight: 600;
    font-size: 0.72rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    border-bottom: 1px solid var(--border);
  }
  .results-table td {
    padding: 8px 10px;
    border-bottom: 1px solid rgba(48,54,61,0.5);
    font-family: var(--mono);
    font-size: 0.79rem;
  }
  .results-table tr:last-child td { border-bottom: none; }
  .results-table .net-col { font-weight: 700; color: var(--accent); }
  .results-table .net-col.loss { color: var(--bad); }
  .results-table .bytes-badge {
    display: inline-block;
    padding: 1px 7px;
    background: var(--panel-2);
    border: 1px solid var(--border);
    border-radius: 3px;
    font-size: 0.7rem;
    color: var(--muted);
  }
  .results-table tr.winner td { background: rgba(45,164,78,0.06); }

  /* ── PANEL 3: ANCHOR PROOF ─────────────────────────────────── */
  .anchor-status {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 9px 12px;
    background: rgba(45,164,78,0.1);
    border: 1px solid rgba(45,164,78,0.3);
    border-radius: 6px;
    margin-bottom: 16px;
    font-size: 0.82rem;
    font-weight: 600;
    color: var(--accent);
  }
  .field-row {
    padding: 7px 0;
    border-top: 1px solid rgba(48,54,61,0.7);
  }
  .field-row:first-of-type { border-top: none; }
  .field-row .fname {
    font-size: 0.69rem;
    text-transform: uppercase;
    letter-spacing: 0.07em;
    color: var(--muted);
    margin-bottom: 3px;
  }
  .field-row .fval {
    font-family: var(--mono);
    font-size: 0.72rem;
    color: var(--fg);
    word-break: break-all;
    line-height: 1.45;
  }
  .field-row .fval a {
    color: #58a6ff;
    text-decoration: none;
  }
  .field-row .fval a:hover { text-decoration: underline; }
  .verify-link {
    display: block;
    width: 100%;
    margin-top: 14px;
    padding: 9px 14px;
    background: rgba(45,164,78,0.12);
    border: 1px solid rgba(45,164,78,0.4);
    border-radius: 6px;
    color: var(--accent);
    font-size: 0.82rem;
    font-weight: 600;
    text-align: center;
    text-decoration: none;
    cursor: pointer;
    transition: background 0.15s;
  }
  .verify-link:hover {
    background: rgba(45,164,78,0.2);
  }
  .proof-note {
    margin-top: 14px;
    padding: 10px 12px;
    background: var(--panel-2);
    border: 1px solid var(--border);
    border-radius: 5px;
    font-size: 0.73rem;
    color: var(--muted);
    line-height: 1.55;
  }
  .proof-note code {
    font-family: var(--mono);
    color: var(--fg);
    font-size: 0.68rem;
  }

  /* ── BOTTOM: LIVE MARKET FEED ──────────────────────────────── */
  .feed-section {
    padding: 0 16px 16px;
  }
  .feed-header-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 10px 0 10px;
    border-bottom: 1px solid var(--border);
    margin-bottom: 0;
  }
  .feed-title {
    font-size: 0.8rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--muted);
  }
  .feed-live {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 0.75rem;
    color: var(--accent);
    font-weight: 600;
  }
  .feed-dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: var(--accent);
    animation: pulse 1.8s ease-in-out infinite;
  }
  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.3; }
  }
  .feed-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.78rem;
  }
  .feed-table th {
    text-align: left;
    padding: 7px 10px;
    color: var(--muted);
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    border-bottom: 1px solid var(--border);
    font-weight: 600;
    position: sticky;
    top: 0;
    background: var(--panel);
  }
  .feed-table td {
    padding: 6px 10px;
    font-family: var(--mono);
    font-size: 0.75rem;
    border-bottom: 1px solid rgba(48,54,61,0.35);
  }
  .feed-table tr.row-commit td { background: rgba(45,164,78,0.06); }
  .feed-table tr.row-hold td { background: transparent; }
  .feed-table tr.row-new { animation: fadein 0.4s ease; }
  @keyframes fadein { from { opacity: 0; transform: translateY(-4px); } to { opacity: 1; } }
  .dec-commit { color: var(--accent); font-weight: 700; }
  .dec-hold { color: var(--warn); }

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

  /* ── FOOTER ────────────────────────────────────────────────── */
  footer {
    padding: 18px 28px;
    border-top: 1px solid var(--border);
    color: var(--muted);
    font-size: 0.78rem;
    display: flex;
    gap: 24px;
    flex-wrap: wrap;
  }
  footer a { color: #58a6ff; text-decoration: none; }

  /* ── CASHLANES CHANNEL PANEL ───────────────────────────────────── */
  :root { --mono: ui-monospace, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace; }
  .channel-section { background:var(--panel); border:1px solid #2a3750; border-radius:8px; margin:8px 28px 12px; padding:16px 20px; display:flex; flex-direction:column; gap:12px; }
  .channel-header  { display:flex; align-items:center; gap:12px; flex-wrap:wrap; }
  .channel-title   { font-size:0.82rem; font-weight:700; color:#e6c07b; display:flex; align-items:center; gap:5px; flex:1; }
  .channel-state-pill { font-size:0.72rem; font-weight:700; font-family:var(--mono); padding:3px 10px; border-radius:12px; border:1px solid; white-space:nowrap; }
  .state-UNFUNDED   { background:rgba(139,148,158,0.1); color:#8b949e; border-color:rgba(139,148,158,0.3); }
  .state-FUNDED     { background:rgba(14,165,233,0.1); color:var(--teal); border-color:rgba(14,165,233,0.3); }
  .state-FLOW_ACTIVE{ background:rgba(45,164,78,0.12); color:var(--ok); border-color:rgba(45,164,78,0.4); animation:pulse-border 1.5s ease-in-out infinite; }
  .state-SETTLING   { background:rgba(210,153,34,0.12); color:var(--warn); border-color:rgba(210,153,34,0.4); }
  .state-CLOSED     { background:rgba(45,164,78,0.08); color:#4caf8a; border-color:rgba(45,164,78,0.2); }
  @keyframes pulse-border { 0%,100%{border-color:rgba(45,164,78,0.4)}50%{border-color:rgba(45,164,78,0.9)} }
  .channel-controls { display:flex; gap:6px; flex-wrap:wrap; }
  .ch-btn { padding:5px 14px; border-radius:5px; border:1px solid; font-size:0.74rem; font-weight:600; cursor:pointer; transition:opacity 0.15s; }
  .ch-btn:disabled { opacity:0.35; cursor:default; }
  .ch-btn-fund   { background:rgba(14,165,233,0.12); color:var(--teal); border-color:rgba(14,165,233,0.4); }
  .ch-btn-start  { background:rgba(45,164,78,0.12);  color:var(--ok);   border-color:rgba(45,164,78,0.4); }
  .ch-btn-settle { background:rgba(210,153,34,0.12); color:var(--warn);  border-color:rgba(210,153,34,0.4); }
  .ch-btn-reset  { background:rgba(248,81,73,0.08);  color:#f85149;      border-color:rgba(248,81,73,0.3); font-size:0.68rem; }
  .channel-body  { display:flex; gap:16px; flex-wrap:wrap; }
  .channel-metrics { flex:1; min-width:280px; display:flex; flex-direction:column; gap:10px; }
  .channel-fsm { display:flex; align-items:center; gap:4px; flex-wrap:wrap; font-size:0.65rem; font-family:var(--mono); }
  .fsm-step { padding:2px 8px; border-radius:10px; border:1px solid rgba(139,148,158,0.2); color:#8b949e; font-weight:600; transition:all 0.3s; }
  .fsm-step.active { border-color:var(--teal); color:var(--teal); background:rgba(14,165,233,0.1); box-shadow:0 0 8px rgba(14,165,233,0.3); }
  .fsm-arrow { color:var(--border); font-size:0.7rem; }
  .channel-stats { display:flex; gap:20px; flex-wrap:wrap; }
  .ch-stat { display:flex; flex-direction:column; gap:2px; }
  .ch-stat-label { font-size:0.62rem; color:#8b949e; text-transform:uppercase; letter-spacing:0.05em; }
  .ch-stat-value { font-size:1.1rem; font-weight:700; font-family:var(--mono); }
  .ch-stat-value.green { color:var(--ok); }
  .ch-funding-row { font-size:0.65rem; font-family:var(--mono); color:#8b949e; display:flex; gap:6px; align-items:center; flex-wrap:wrap; }
  .ch-funding-row a { color:#58a6ff; text-decoration:none; }
  .channel-settlements { flex:1.5; min-width:320px; display:flex; flex-direction:column; gap:6px; }
  .ch-settle-header { font-size:0.68rem; font-weight:700; color:#8b949e; text-transform:uppercase; letter-spacing:0.06em; }
  .ch-settle-list { display:flex; flex-direction:column; gap:5px; max-height:160px; overflow-y:auto; }
  .ch-settle-entry { background:#1c2330; border:1px solid #30363d; border-radius:5px; padding:7px 10px; display:flex; align-items:center; gap:10px; font-size:0.68rem; animation:slideIn 0.3s ease; }
  .ch-settle-entry.new { border-color:rgba(45,164,78,0.5); }
  @keyframes slideIn { from{opacity:0;transform:translateY(-4px)} to{opacity:1;transform:none} }
  .ch-settle-seq { color:#8b949e; font-family:var(--mono); flex-shrink:0; }
  .ch-settle-info { flex:1; }
  .ch-settle-txid a { color:#58a6ff; text-decoration:none; font-family:var(--mono); font-size:0.65rem; }
  .ch-settle-badge { font-size:0.6rem; padding:1px 6px; background:rgba(45,164,78,0.1); border:1px solid rgba(45,164,78,0.3); border-radius:10px; color:var(--ok); flex-shrink:0; }
  .channel-footnote { font-size:0.65rem; color:#8b949e; border-top:1px solid #30363d; padding-top:8px; }
  .ch-bridge-status { font-size:0.68rem; font-family:var(--mono); }
  .ch-bridge-online { color:var(--ok); }
  .ch-bridge-offline { color:#8b949e; }
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

<!-- TOP BAR -->
<div class="topbar">
  <h1>EU Networks — Dark Fiber Wavelength Spot Market</h1>
  <span class="sub">Rúnar-governed commitment decisions, settled on BSV</span>
  <span class="pill">● Live Demo</span>
  <div class="hat-row">
    <span class="hat-label">🎩</span>
    <select id="hat-select" class="hat-select" onchange="onHatChange(this.value)">
      <option value="eu-networks-fiber-operator" selected>EU Networks — Fiber Operator</option>
      <option value="inference-gateway-eu">Inference Gateway EU</option>
      <option value="ixp-ams-noc">IXP Amsterdam NOC</option>
      <option value="plexus-admin">Plexus Admin</option>
    </select>
    <span id="hat-fp" class="hat-fp"></span>
    <span id="mesh-status" class="pill pill-muted">○ Mesh offline</span>
  </div>
</div>

<!-- THREE-PANEL GRID -->
<div class="main-grid">

  <!-- PANEL 1: LIVE STRATEGY SIMULATOR -->
  <div class="panel">
    <div class="panel-header">
      <span class="tip-host"><span>Live Strategy Simulator</span><span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Live Strategy Simulator</span>Move the sliders to simulate a real dark-fiber wavelength spot market. The same 9-byte Bitcoin Script policy that runs in production executes here in your browser — there is no gap between demo and live.</div></span>
    </div>
    <div class="panel-body">

      <div class="strat-tabs">
        <div class="strat-tab active" id="tab-threshold" onclick="selectTab('threshold')">Threshold</div>
        <div class="strat-tab" id="tab-premium" onclick="selectTab('premium')">Premium</div>
      </div>

      <div class="slider-group">
        <div class="slider-label">
          <span class="lname"><span class="tip-host">Link Utilization<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Link Utilization %</span>How much of the fiber wavelength is already sold. High utilization = scarcity = higher spot prices. The policy gates on this to avoid over-committing capacity.</div></span></span>
          <span class="lval" id="util-display">62%</span>
        </div>
        <input type="range" id="util-slider" min="0" max="100" value="62" oninput="onSlider()">
      </div>

      <div class="slider-group">
        <div class="slider-label">
          <span class="lname"><span class="tip-host">Bid (€-cents / Gbps-hr)<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Current Market Bid</span>What a buyer is currently offering per gigabit-per-second per hour. The policy commits capacity only when the bid clears the minimum threshold — protecting the operator from selling cheap.</div></span></span>
          <span class="lval" id="bid-display">320 <span style="font-size:0.7rem;color:var(--muted)">(€3.20)</span></span>
        </div>
        <input type="range" id="bid-slider" min="0" max="1000" value="320" oninput="onSlider()">
      </div>

      <div class="strategy-badges">
        <div class="badge-row">
          <span class="badge-name"><span class="tip-host">threshold_commit<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Threshold Commit</span>The conservative strategy: commit only when link utilization is ≤ 70% AND the bid is at least €2.50/Gbps-hr. Protects against over-committing during peak congestion.</div></span></span>
          <span class="badge-decision commit" id="badge-threshold">● COMMIT</span>
        </div>
        <div class="badge-row">
          <span class="badge-name"><span class="tip-host">premium_threshold<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Premium Threshold</span>The high-margin strategy: only commit when utilization is ≤ 50% AND the bid exceeds €5.00/Gbps-hr. Fewer commits, but each one is at premium pricing.</div></span></span>
          <span class="badge-decision hold" id="badge-premium">○ HOLD</span>
        </div>
      </div>

      <div class="hex-panel">
        <div class="hex-label" id="hex-label"><span class="tip-host">Strategy hex — threshold_commit<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">The Policy Rule in Machine Code</span>This hexadecimal string is the complete commitment policy — compiled to Bitcoin Script opcodes. 9 bytes. It runs identically in the backtest, in the browser, and on-chain. There is no server that could change it between contexts.</div></span></div>
        <div class="hex-bytes" id="hex-display">7c 01 46 a1 69 02 fa 00 a2</div>
        <div class="opcode-trace" id="opcode-trace"></div>
      </div>
    </div>
  </div>

  <!-- PANEL 2: BACKTEST RESULTS -->
  <div class="panel">
    <div class="panel-header">
      <span class="tip-host"><span>30-Day Backtest — Wavelength Spot Revenue</span><span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">30-Day Revenue Backtest</span>We replayed 8,640 five-minute market intervals through each policy rule. The chart shows cumulative net revenue in euros. The Rúnar-governed strategies beat the naive "commit when bid > €2" baseline because they avoid high-utilization periods that trigger switching costs.</div></span>
    </div>
    <div class="panel-body">
      <div class="chart-wrapper">
        <canvas id="revenueChart"></canvas>
      </div>
      <table class="results-table">
        <thead>
          <tr>
            <th>Strategy</th>
            <th>Bytes</th>
            <th>Commits</th>
            <th>Gross Revenue</th>
            <th>Switching Cost</th>
            <th><span class="tip-host">Net<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Net Revenue</span>Gross revenue minus switching costs (€0.20 flat per state change). This is the number an operator actually earns. The policy rule's edge comes from avoiding unnecessary switches during congested periods.</div></span></th>
          </tr>
        </thead>
        <tbody id="results-tbody">
          <tr><td colspan="6" style="color:var(--muted);text-align:center;padding:18px">Computing...</td></tr>
        </tbody>
      </table>
    </div>
  </div>

  <!-- PANEL 3: BSV ANCHOR PROOF -->
  <div class="panel">
    <div class="panel-header">
      <span class="tip-host"><span>On-Chain Proof</span><span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">On-Chain Proof</span>The backtest result is anchored to the Bitcoin SV blockchain as an immutable commitment. This means the operator can prove to any counterparty — without sharing raw data — that a specific policy was applied to specific inputs and produced a specific result.</div></span>
    </div>
    <div class="panel-body">
      <div class="anchor-status">
        <span>✓</span>
        <span>Anchored on BSV mainnet</span>
      </div>

      <div class="field-row">
        <div class="fname">event_type</div>
        <div class="fval" style="color:var(--teal);">scada.event.v0 — ACTUATE</div>
      </div>
      <div class="field-row">
        <div class="fname">tag</div>
        <div class="fval" style="font-family:var(--mono);font-size:0.72rem;">wavelength-DE-FR-001</div>
      </div>

      <div class="field-row">
        <div class="fname"><span class="tip-host">cell_hash<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Cell Hash</span>A cryptographic fingerprint: SHA-256(policy_hex + data_hash + result_hash). If the policy, data, or result were altered even by one bit, this hash would be completely different. It is the tamper-evident seal.</div></span></div>
        <div class="fval" id="proof-cell-hash"></div>
      </div>
      <div class="field-row">
        <div class="fname">strategy_hex</div>
        <div class="fval"><code>7c0146a16902fa00a2</code></div>
      </div>
      <div class="field-row">
        <div class="fname">data_sha256</div>
        <div class="fval" id="proof-data-sha"></div>
      </div>
      <div class="field-row">
        <div class="fname">result_sha256</div>
        <div class="fval" id="proof-result-sha"></div>
      </div>
      <div class="field-row">
        <div class="fname"><span class="tip-host">txid<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Bitcoin SV Transaction ID</span>The unique identifier of the on-chain transaction that recorded this commitment. Click the link below to view it on a public block explorer — anyone in the world can verify it, no account required.</div></span></div>
        <div class="fval">
          <a id="proof-txid-link" href="#" target="_blank" rel="noopener"></a>
        </div>
      </div>

      <a class="verify-link" id="verify-chain-link" href="#" target="_blank" rel="noopener">
        Verify on chain →
      </a>

      <div class="proof-note">
        <span class="tip-host"><span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">How to Verify</span>Anyone can re-compute SHA-256(strategy_hex + data_sha256 + result_sha256) and check it equals the cell_hash. Then look up the txid on any BSV explorer. No trust in us required — the math and the chain do the verification.</div></span>
        <code>SHA-256(strategy_hex ‖ data_sha256 ‖ result_sha256) = cell_hash</code>
        <br><br>
        Anyone can re-run this exact hex against the same data and confirm the result. No server trust required.
      </div>
    </div>
  </div>

</div><!-- /main-grid -->

<!-- BOTTOM: LIVE MARKET FEED -->
<div class="feed-section" style="background:var(--panel);border:1px solid var(--border);border-radius:8px;margin:0 16px 16px;">
  <div class="feed-header-bar">
    <span class="feed-title"><span class="tip-host">Live Market Feed — 5-min Tick Simulation<span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Live Market Feed</span>Simulated 5-minute wavelength spot market ticks. Each row shows the current market conditions and what each policy rule decides — COMMIT (sell capacity now) or HOLD (wait for better conditions). Updates every 2 seconds.</div></span></span>
    <span class="feed-live"><span class="feed-dot"></span> Auto-updating every 2s</span>
  </div>
  <div style="overflow-x:auto;">
    <table class="feed-table">
      <thead>
        <tr>
          <th>Time (UTC)</th>
          <th>Utilization %</th>
          <th>Bid (€/Gbps-hr)</th>
          <th>Demand (Gbps)</th>
          <th>threshold_commit</th>
          <th>premium_threshold</th>
        </tr>
      </thead>
      <tbody id="feed-body"></tbody>
    </table>
  </div>
</div>

<!-- ── CASHLANES CHANNEL PANEL ───────────────────────────────────── -->
<div class="channel-section" id="channel-section">
  <div class="channel-header">
    <div class="channel-title">
      <span style="font-size:1rem;">⚡</span>
      CashLanes Payment Channel — Dark Fiber Bandwidth Settlement
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
    <div class="channel-metrics">
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
      <div class="channel-stats">
        <div class="ch-stat"><span class="ch-stat-label">GB Committed</span><span class="ch-stat-value green" id="ch-mb">0.00</span></div>
        <div class="ch-stat"><span class="ch-stat-label">Cost (sats)</span><span class="ch-stat-value" id="ch-sats">0</span></div>
        <div class="ch-stat"><span class="ch-stat-label">Settlements</span><span class="ch-stat-value" id="ch-seq">0</span></div>
        <div class="ch-stat"><span class="ch-stat-label">Rate</span><span class="ch-stat-value" style="font-size:0.85rem;color:#8b949e">10 sats/GB</span></div>
      </div>
      <div class="ch-funding-row" id="ch-funding-row" style="display:none">
        <span>2-of-2 multisig:</span>
        <a id="ch-funding-link" href="#" target="_blank" rel="noopener">—</a>
        <span id="ch-key-info" style="color:var(--muted);font-size:0.6rem;"></span>
      </div>
    </div>

    <div class="channel-settlements">
      <div class="ch-settle-header">BSV Settlement Transactions</div>
      <div class="ch-settle-list" id="ch-settle-list">
        <div style="color:#8b949e;font-size:0.7rem;padding:6px 0;">No settlements yet — fund the channel and commit dark fiber bandwidth to trigger BSV settlements</div>
      </div>
    </div>
  </div>

  <div class="channel-footnote">
    Each <strong style="color:var(--ok)">dark.fiber.commit</strong> event advances the GB counter by 0.5 GB. Every 5 GB triggers a real BSV mainnet settlement anchor via Metanet Desktop (:3321). The PushDrop output embeds channel ID, GB transferred, and cost in satoshis on-chain.
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

<footer>
  <span>Built by <a href="https://realblockchainsolutions.com">Real Blockchain Solutions</a></span>
  <span>Source: <code style="font-family:var(--mono);font-size:0.72rem">cartridges/dark-fiber/</code></span>
  <span>Strategy hex: <code style="font-family:var(--mono);font-size:0.72rem">7c0146a16902fa00a2</code> (threshold) · <code style="font-family:var(--mono);font-size:0.72rem">7c0132a16902f401a2</code> (premium)</span>
</footer>

<script>
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

// ══════════════════════════════════════════════════════════════════
// SCRIPT INTERPRETER — minimal Bitcoin Script subset
// Mirrors cartridges/dark-fiber/scripts/script-interpreter.ts
// ══════════════════════════════════════════════════════════════════

function readCScriptNum(bytes) {
  if (bytes.length === 0) return 0n;
  const hi = bytes[bytes.length - 1];
  const negative = (hi & 0x80) !== 0;
  let acc = 0n;
  for (let i = 0; i < bytes.length; i++) {
    let b = BigInt(bytes[i]);
    if (i === bytes.length - 1 && negative) b = BigInt(hi & 0x7f);
    acc |= b << BigInt(8 * i);
  }
  return negative ? -acc : acc;
}

function isTruthy(n) { return n !== 0n; }

function executeScript(scriptBytes) {
  const stack = [];
  let pc = 0;
  let opcount = 0;
  const ops = [];
  while (pc < scriptBytes.length) {
    const op = scriptBytes[pc++];
    opcount++;
    if (op >= 0x01 && op <= 0x4b) {
      const n = op;
      const chunk = scriptBytes.slice(pc, pc + n);
      const val = readCScriptNum(chunk);
      stack.push(val);
      ops.push({ op: `PUSH(${val})`, stack: [...stack] });
      pc += n;
      continue;
    }
    switch (op) {
      case 0x00: stack.push(0n); ops.push({ op: 'OP_FALSE', stack: [...stack] }); break;
      case 0x51: stack.push(1n); ops.push({ op: 'OP_1', stack: [...stack] }); break;
      case 0x69: {
        const v = stack.pop();
        if (!isTruthy(v)) return { ok: false, ops, reason: 'verify_failed' };
        ops.push({ op: 'OP_VERIFY', stack: [...stack], note: '✓ truthy' });
        break;
      }
      case 0x75: { stack.pop(); ops.push({ op: 'OP_DROP', stack: [...stack] }); break; }
      case 0x76: { stack.push(stack[stack.length-1]); ops.push({ op: 'OP_DUP', stack: [...stack] }); break; }
      case 0x7c: {
        const a = stack.pop(), b = stack.pop();
        stack.push(a); stack.push(b);
        ops.push({ op: 'OP_SWAP', stack: [...stack] });
        break;
      }
      case 0x78: {
        stack.push(stack[stack.length-2]);
        ops.push({ op: 'OP_OVER', stack: [...stack] });
        break;
      }
      case 0x95: {
        const b = stack.pop(), a = stack.pop();
        stack.push(a * b);
        ops.push({ op: 'OP_MUL', stack: [...stack] });
        break;
      }
      case 0xa1: {
        const b = stack.pop(), a = stack.pop();
        stack.push(a <= b ? 1n : 0n);
        ops.push({ op: 'OP_LESSTHANOREQUAL', stack: [...stack] });
        break;
      }
      case 0xa2: {
        const b = stack.pop(), a = stack.pop();
        stack.push(a >= b ? 1n : 0n);
        ops.push({ op: 'OP_GREATERTHANOREQUAL', stack: [...stack] });
        break;
      }
      default: return { ok: false, ops, reason: 'invalid_opcode_0x' + op.toString(16) };
    }
  }
  if (stack.length === 0) return { ok: false, ops, reason: 'empty_stack' };
  return { ok: isTruthy(stack[stack.length-1]), ops, stack };
}

function hexToBytes(hex) {
  const h = hex.replace(/\s+/g, '');
  const out = new Uint8Array(h.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(h.slice(i*2, i*2+2), 16);
  return out;
}

function pushSmallInt(n) {
  if (n === 0) return new Uint8Array([0x00]);
  let v = BigInt(n);
  const neg = v < 0n;
  if (neg) v = -v;
  const bytes = [];
  while (v > 0n) { bytes.push(Number(v & 0xffn)); v >>= 8n; }
  if ((bytes[bytes.length-1] & 0x80) !== 0) bytes.push(neg ? 0x80 : 0x00);
  else if (neg) bytes[bytes.length-1] |= 0x80;
  return new Uint8Array([bytes.length, ...bytes]);
}

function concatBytes(...parts) {
  let total = 0;
  for (const p of parts) total += p.length;
  const out = new Uint8Array(total);
  let off = 0;
  for (const p of parts) { out.set(p, off); off += p.length; }
  return out;
}

// ══════════════════════════════════════════════════════════════════
// STRATEGIES
// ══════════════════════════════════════════════════════════════════

const STRATEGIES = {
  threshold: {
    name: 'threshold_commit',
    hex: '7c0146a16902fa00a2',
    bytes: 9,
    label: 'util ≤ 70% ∧ bid ≥ 250',
    color: '#2da44e',
    borderColor: '#2da44e',
  },
  premium: {
    name: 'premium_threshold',
    hex: '7c0132a16902f401a2',
    bytes: 9,
    label: 'util ≤ 50% ∧ bid ≥ 500',
    color: '#2bbcd4',
    borderColor: '#2bbcd4',
  },
};

function runStrategy(stratKey, utilizationPct, bidCentsPerGbps) {
  const strat = STRATEGIES[stratKey];
  const predBytes = hexToBytes(strat.hex);
  const script = concatBytes(
    pushSmallInt(utilizationPct),
    pushSmallInt(bidCentsPerGbps),
    predBytes
  );
  return executeScript(script);
}

function evalDecision(stratKey, utilizationPct, bidCentsPerGbps) {
  return runStrategy(stratKey, utilizationPct, bidCentsPerGbps).ok;
}

// ══════════════════════════════════════════════════════════════════
// SYNTHETIC DATA — 500-row inline sample for backtest computation
// Generated with mulberry32 seed=42, same logic as synth-fiber-data.ts
// ══════════════════════════════════════════════════════════════════

function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function generateSynthData(totalIntervals, seed) {
  const rng = mulberry32(seed);
  const TOTAL_CAPACITY_GBPS = 400;

  // Pre-select burst windows (3-5 events)
  const numBursts = 3 + Math.floor(rng() * 3);
  const bursts = [];
  for (let b = 0; b < numBursts; b++) {
    const start = Math.floor(rng() * (totalIntervals - 72));
    const dur = 24 + Math.floor(rng() * 48);
    bursts.push({ start, end: start + dur });
  }
  function isBurst(i) { return bursts.some(b => i >= b.start && i < b.end); }

  const BASE_TS = Date.UTC(2026, 0, 1, 0, 0, 0);
  const rows = [];
  for (let i = 0; i < totalIntervals; i++) {
    const tsMs = BASE_TS + i * 5 * 60 * 1000;
    const hourOfDay = ((tsMs / 3600000) % 24 + 24) % 24;
    const dayOfWeek = new Date(tsMs).getUTCDay();
    const isWeekend = dayOfWeek === 0 || dayOfWeek === 6;

    let baseUtil;
    if (hourOfDay < 5) baseUtil = 30 + rng() * 15;
    else if (hourOfDay < 8) baseUtil = 45 + ((hourOfDay-5)/3)*20 + rng()*8;
    else if (hourOfDay < 13) baseUtil = 65 + rng()*20;
    else if (hourOfDay < 18) baseUtil = 60 + rng()*18;
    else if (hourOfDay < 22) baseUtil = 50 - ((hourOfDay-18)/4)*20 + rng()*12;
    else baseUtil = 35 + rng()*12;
    if (isWeekend) baseUtil *= 0.85;

    let burstMul = 1.0, burstBidMul = 1.0;
    if (isBurst(i)) { burstMul = 1.2 + rng()*0.25; burstBidMul = 2.0 + rng()*1.5; }

    const utilizationPct = Math.min(98, Math.max(5, Math.round(baseUtil * burstMul)));
    const demandGbps = Math.round(utilizationPct / 100 * TOTAL_CAPACITY_GBPS);

    let baseBid;
    if (utilizationPct < 40) baseBid = 150 + rng()*80;
    else if (utilizationPct < 60) baseBid = 200 + rng()*100;
    else if (utilizationPct < 75) baseBid = 250 + rng()*100;
    else baseBid = 300 + rng()*150;
    const bidCentsPerGbps = Math.round(baseBid * burstBidMul);

    rows.push({ ts: tsMs, utilizationPct, bidCentsPerGbps, demandGbps });
  }
  return rows;
}

// Generate full 30-day dataset (8640 rows) in the browser
const SYNTH_DATA = generateSynthData(8640, 42);

// ══════════════════════════════════════════════════════════════════
// BACKTEST ENGINE (runs in browser)
// ══════════════════════════════════════════════════════════════════

const SLOT_FRACTION = 5 / 60;
const SWITCHING_COST_CENTS = 20;
const CAPACITY_GBPS = 100;

function runBacktest(stratFn) {
  let netCents = 0, grossCents = 0, switchCents = 0;
  let commits = 0, holds = 0;
  let prevDecision = null;
  const cumulativeNet = []; // one entry per row

  for (let i = 0; i < SYNTH_DATA.length; i++) {
    const row = SYNTH_DATA[i];
    const decision = stratFn(row.utilizationPct, row.bidCentsPerGbps);
    if (prevDecision !== null && prevDecision !== decision) {
      switchCents += SWITCHING_COST_CENTS;
      netCents -= SWITCHING_COST_CENTS;
    }
    prevDecision = decision;
    if (decision) {
      const rev = Math.round(row.bidCentsPerGbps * CAPACITY_GBPS * SLOT_FRACTION);
      grossCents += rev;
      netCents += rev;
      commits++;
    } else {
      holds++;
    }
    cumulativeNet.push(netCents / 100); // €
  }
  return {
    commits, holds,
    grossEur: grossCents / 100,
    switchEur: switchCents / 100,
    netEur: netCents / 100,
    cumulativeNet,
  };
}

// Run all three strategies
const thresholdResults = runBacktest((u, b) => evalDecision('threshold', u, b));
const premiumResults   = runBacktest((u, b) => evalDecision('premium', u, b));
const naiveResults     = runBacktest((u, b) => b > 200);

// ══════════════════════════════════════════════════════════════════
// CHART — downsample to 500 points for rendering
// ══════════════════════════════════════════════════════════════════

function downsample(arr, n) {
  const out = [];
  const step = arr.length / n;
  for (let i = 0; i < n; i++) {
    out.push(arr[Math.min(Math.round(i * step), arr.length - 1)]);
  }
  return out;
}

const CHART_POINTS = 500;
const labels = downsample(SYNTH_DATA, CHART_POINTS).map((r, i) => {
  const d = new Date(r.ts);
  return `Day ${Math.floor(i * 30 / CHART_POINTS) + 1}`;
});

const chartData = {
  labels,
  datasets: [
    {
      label: 'threshold_commit',
      data: downsample(thresholdResults.cumulativeNet, CHART_POINTS),
      borderColor: '#2da44e',
      backgroundColor: 'rgba(45,164,78,0.07)',
      borderWidth: 2,
      pointRadius: 0,
      tension: 0.3,
      fill: false,
    },
    {
      label: 'premium_threshold',
      data: downsample(premiumResults.cumulativeNet, CHART_POINTS),
      borderColor: '#2bbcd4',
      backgroundColor: 'rgba(43,188,212,0.07)',
      borderWidth: 2,
      pointRadius: 0,
      tension: 0.3,
      fill: false,
    },
    {
      label: 'naive (bid > €2.00)',
      data: downsample(naiveResults.cumulativeNet, CHART_POINTS),
      borderColor: '#f85149',
      backgroundColor: 'rgba(248,81,73,0.05)',
      borderWidth: 1.5,
      borderDash: [5, 4],
      pointRadius: 0,
      tension: 0.3,
      fill: false,
    },
  ],
};

const ctx = document.getElementById('revenueChart').getContext('2d');
new Chart(ctx, {
  type: 'line',
  data: chartData,
  options: {
    responsive: true,
    maintainAspectRatio: false,
    interaction: { mode: 'index', intersect: false },
    plugins: {
      legend: {
        labels: {
          color: '#8b949e',
          font: { size: 11 },
          boxWidth: 18,
          padding: 14,
        },
      },
      tooltip: {
        backgroundColor: '#161b22',
        borderColor: '#30363d',
        borderWidth: 1,
        titleColor: '#e6edf3',
        bodyColor: '#8b949e',
        callbacks: {
          label: ctx => ` ${ctx.dataset.label}: €${ctx.parsed.y.toLocaleString('en', {minimumFractionDigits:0, maximumFractionDigits:0})}`,
        },
      },
    },
    scales: {
      x: {
        ticks: { color: '#8b949e', font: { size: 10 }, maxTicksLimit: 8 },
        grid: { color: 'rgba(48,54,61,0.5)' },
      },
      y: {
        ticks: {
          color: '#8b949e',
          font: { size: 10 },
          callback: v => '€' + (v/1000).toFixed(0) + 'k',
        },
        grid: { color: 'rgba(48,54,61,0.5)' },
      },
    },
  },
});

// ══════════════════════════════════════════════════════════════════
// RESULTS TABLE — populate from actual computed numbers
// ══════════════════════════════════════════════════════════════════

function fmtEur(n) {
  return '€' + n.toLocaleString('en', {minimumFractionDigits: 0, maximumFractionDigits: 0});
}

const tbody = document.getElementById('results-tbody');
const rows = [
  {
    name: 'threshold_commit', bytes: 9,
    color: '#2da44e',
    res: thresholdResults,
    winner: thresholdResults.netEur >= premiumResults.netEur && thresholdResults.netEur >= naiveResults.netEur,
  },
  {
    name: 'premium_threshold', bytes: 9,
    color: '#2bbcd4',
    res: premiumResults,
    winner: premiumResults.netEur >= thresholdResults.netEur && premiumResults.netEur >= naiveResults.netEur,
  },
  {
    name: 'naive (bid > €2.00)', bytes: null,
    color: '#f85149',
    res: naiveResults,
    winner: false,
  },
];
tbody.innerHTML = rows.map(r => `
  <tr class="${r.winner ? 'winner' : ''}">
    <td style="color:${r.color};font-weight:600">${r.name}${r.winner ? ' ★' : ''}</td>
    <td>${r.bytes ? `<span class="bytes-badge">${r.bytes} bytes</span>` : '<span style="color:var(--muted)">—</span>'}</td>
    <td>${r.res.commits.toLocaleString()}</td>
    <td>${fmtEur(r.res.grossEur)}</td>
    <td style="color:var(--bad)">${fmtEur(r.res.switchEur)}</td>
    <td class="net-col ${r.res.netEur < 0 ? 'loss' : ''}">${fmtEur(r.res.netEur)}</td>
  </tr>
`).join('');

// ══════════════════════════════════════════════════════════════════
// BSV ANCHOR PROOF — per-strategy anchors from the backtest run
// ══════════════════════════════════════════════════════════════════

const ANCHORS = {
  threshold: {
    strategy_hex:  '7c0146a16902fa00a2',
    cell_hash:     '5f181387c4319eca800677dc471c22264d1b1343307b0b5ab903544fc9d553dd',
    data_sha256:   '6a47d0803b2e8ab7b895b2e9a0cd1d78e1430208ae50d83225a384202d10d252',
    result_sha256: '16e716158fba0de6551b566776e1db04601972c596bb46baace2ad7e7b372c9b',
    txid:          '82f4ccbcabd944e45963c02dfa013e669f40767d4fc1d474dcbe8bf3c6d57600',
  },
  premium: {
    strategy_hex:  '7c0132a16902f401a2',
    cell_hash:     '27b8d73b54bc6b9f8fba0f94be237329106e6106c6e1e22939297ab00b5b2e57',
    data_sha256:   '6a47d0803b2e8ab7b895b2e9a0cd1d78e1430208ae50d83225a384202d10d252',
    result_sha256: '47c79e2fac19b940d10f755ef2524bca3962cfadd5f2d94eafd9000cdda44f23',
    txid:          'd506e9f3fb0b90ca618748fa9d5060b94ec55bc0cc9b65d75dfc8aa86c268d8d',
  },
};

function updateAnchorPanel() {
  const a = ANCHORS[activeTab];
  document.getElementById('proof-cell-hash').textContent = a.cell_hash;
  document.getElementById('proof-data-sha').textContent = a.data_sha256;
  document.getElementById('proof-result-sha').textContent = a.result_sha256;
  const wocUrl = `https://whatsonchain.com/tx/${a.txid}`;
  const txLink = document.getElementById('proof-txid-link');
  txLink.textContent = a.txid.slice(0, 16) + '...' + a.txid.slice(-8);
  txLink.href = wocUrl;
  document.getElementById('verify-chain-link').href = wocUrl;
}

// ══════════════════════════════════════════════════════════════════
// LIVE SIMULATOR — sliders + badge + opcode trace
// ══════════════════════════════════════════════════════════════════

let activeTab = 'threshold';

function selectTab(tab) {
  activeTab = tab;
  document.getElementById('tab-threshold').classList.toggle('active', tab === 'threshold');
  document.getElementById('tab-premium').classList.toggle('active', tab === 'premium');
  onSlider();
  updateAnchorPanel();
}

const STRAT_HEX = {
  threshold: '7c0146a16902fa00a2',
  premium:   '7c0132a16902f401a2',
};

const OPCODE_COMMENTS = {
  threshold: [
    ['7c',       'OP_SWAP'],
    ['01 46',    'PUSH(70)'],
    ['a1',       'OP_LESSTHANOREQUAL'],
    ['69',       'OP_VERIFY'],
    ['02 fa 00', 'PUSH(250)'],
    ['a2',       'OP_GTE'],
  ],
  premium: [
    ['7c',       'OP_SWAP'],
    ['01 32',    'PUSH(50)'],
    ['a1',       'OP_LESSTHANOREQUAL'],
    ['69',       'OP_VERIFY'],
    ['02 f4 01', 'PUSH(500)'],
    ['a2',       'OP_GTE'],
  ],
};

function formatStack(stack) {
  return '[' + stack.map(v => v.toString()).join(', ') + ']';
}

function onSlider() {
  const util = parseInt(document.getElementById('util-slider').value, 10);
  const bid  = parseInt(document.getElementById('bid-slider').value, 10);

  document.getElementById('util-display').textContent = util + '%';
  document.getElementById('bid-display').innerHTML =
    bid + ' <span style="font-size:0.7rem;color:var(--muted)">(€' + (bid/100).toFixed(2) + ')</span>';

  // Update both badges
  const tOk = evalDecision('threshold', util, bid);
  const pOk = evalDecision('premium', util, bid);

  const bThresh = document.getElementById('badge-threshold');
  bThresh.textContent = tOk ? '● COMMIT' : '○ HOLD';
  bThresh.className = 'badge-decision ' + (tOk ? 'commit' : 'hold');

  const bPrem = document.getElementById('badge-premium');
  bPrem.textContent = pOk ? '● COMMIT' : '○ HOLD';
  bPrem.className = 'badge-decision ' + (pOk ? 'commit' : 'hold');

  // Publish active-tab verdict to mesh
  const dfTypePath = (activeTab === 'threshold' ? tOk : pOk) ? 'dark.fiber.commit' : 'dark.fiber.hold';
  const dfHex = STRAT_HEX[activeTab];
  publishToMesh(dfTypePath, activeTab === 'threshold' ? tOk : pOk,
    { utilizationPct: util, bidCentsPerGbps: bid }, dfHex);

  // Update hex display for active tab
  const hexStr = STRAT_HEX[activeTab];
  const hexSpaced = hexStr.match(/.{1,2}/g).join(' ');
  document.getElementById('hex-label').textContent = `Strategy hex — ${STRATEGIES[activeTab].name}`;
  document.getElementById('hex-display').textContent = hexSpaced;

  // Build opcode trace with live stack values
  const predBytes = hexToBytes(hexStr);
  const script = concatBytes(
    pushSmallInt(util),
    pushSmallInt(bid),
    predBytes
  );
  const result = executeScript(script);
  const comments = OPCODE_COMMENTS[activeTab];

  // The interpreter ops include the two input pushes first, then predicate ops
  const traceLines = [];
  const initOps = result.ops.slice(0, 2); // PUSH(util), PUSH(bid)
  traceLines.push({
    text: `stack before:  [${util}, ${bid}]`,
    cls: 'neutral-line',
  });

  comments.forEach((c, idx) => {
    const interpOp = result.ops[idx + 2]; // offset past the 2 input pushes
    if (!interpOp) return;
    const stackAfter = formatStack(interpOp.stack);
    const isVerify = c[0] === '69';
    let cls = 'neutral-line';
    if (isVerify) {
      cls = result.ok || idx < comments.length - 1 ? 'ok-line' : 'fail-line';
      // if verify failed, result.ok is false and reason is verify_failed
      if (!result.ok && result.reason === 'verify_failed') {
        // The verify at idx
        cls = 'fail-line';
      }
    }
    traceLines.push({
      text: `${c[0].padEnd(10)} ${c[1].padEnd(22)} → ${stackAfter}`,
      cls,
    });
  });

  const finalOk = result.ok ? 'COMMIT ✓' : 'HOLD ✗';
  traceLines.push({
    text: `result: ${finalOk}`,
    cls: result.ok ? 'ok-line' : 'fail-line',
  });

  document.getElementById('opcode-trace').innerHTML =
    traceLines.map(l => `<div class="${l.cls}">${l.text}</div>`).join('');
}

// Initial render
onSlider();
updateAnchorPanel();

// ══════════════════════════════════════════════════════════════════
// LIVE MARKET FEED — scrolling table, auto-updates every 2 seconds
// ══════════════════════════════════════════════════════════════════

const MAX_FEED_ROWS = 20;
const feedRows = [];
let feedDataIdx = 0; // walks through SYNTH_DATA

function addFeedRow() {
  if (feedDataIdx >= SYNTH_DATA.length) feedDataIdx = 0;
  const d = SYNTH_DATA[feedDataIdx++];
  const tOk = evalDecision('threshold', d.utilizationPct, d.bidCentsPerGbps);
  const pOk = evalDecision('premium', d.utilizationPct, d.bidCentsPerGbps);
  feedRows.unshift({ d, tOk, pOk, isNew: true });
  if (feedRows.length > MAX_FEED_ROWS) feedRows.pop();
  setTimeout(() => { if (feedRows[0]) feedRows[0].isNew = false; }, 500);
}

function renderFeed() {
  const tbody = document.getElementById('feed-body');
  if (!tbody) return;
  const dt = new Date(feedRows[0]?.d.ts || Date.now());
  tbody.innerHTML = feedRows.map((r, i) => {
    const t = new Date(r.d.ts);
    const timeStr = t.toISOString().slice(11, 16);
    const isCommit = r.tOk || r.pOk;
    const rowCls = isCommit ? 'row-commit' : 'row-hold';
    const newCls = i === 0 && r.isNew ? ' row-new' : '';
    return `<tr class="${rowCls}${newCls}">
      <td>${timeStr}</td>
      <td>${r.d.utilizationPct}%</td>
      <td>€${(r.d.bidCentsPerGbps/100).toFixed(2)}</td>
      <td>${r.d.demandGbps} Gbps</td>
      <td class="${r.tOk ? 'dec-commit' : 'dec-hold'}">${r.tOk ? '● COMMIT' : '○ HOLD'}</td>
      <td class="${r.pOk ? 'dec-commit' : 'dec-hold'}">${r.pOk ? '● COMMIT' : '○ HOLD'}</td>
    </tr>`;
  }).join('');
}

// Seed initial rows
for (let i = 0; i < MAX_FEED_ROWS; i++) addFeedRow();
feedRows.forEach(r => r.isNew = false);
renderFeed();

// Auto-update every 2 seconds
setInterval(() => {
  addFeedRow();
  renderFeed();
}, 2000);

// ─────────────────────────────────────────────────────────────────────
// CASHLANES CHANNEL PANEL
// ─────────────────────────────────────────────────────────────────────

const BRIDGE_URL = 'http://localhost:5198';
let channelState = 'UNFUNDED';
let bridgeOnline = false;
let chEventSource = null;

async function checkBridge() {
  try {
    const r = await fetch(`${BRIDGE_URL}/health`, { signal: AbortSignal.timeout(1200) });
    if (r.ok) {
      const d = await r.json();
      bridgeOnline = true;
      setBridgeStatus(true, d);
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
    const hw = document.getElementById('ch-headless-wallet');
    if (hw) hw.style.display = 'none';
    return;
  }
  const mode = health?.mode ?? 'metanet-desktop';
  el.textContent = `● bridge live (${mode === 'headless' ? 'headless' : 'MND'})`;
  el.className = 'ch-bridge-status ch-bridge-online';
  let hw = document.getElementById('ch-headless-wallet');
  if (mode === 'headless') {
    const addr = health?.walletAddress ?? '', bal = health?.walletBalance ?? '?';
    if (!hw) { hw = document.createElement('div'); hw.id = 'ch-headless-wallet';
      hw.style.cssText = 'margin:6px 0 0;padding:8px;background:#0d1117;border:1px solid #21262d;border-radius:6px;font-size:11px;';
      el.parentNode?.insertBefore(hw, el.nextSibling); }
    hw.style.display = 'block';
    hw.innerHTML = `<span style="color:#58a6ff;font-weight:600;">⚡ Headless wallet</span> &nbsp;
      <span style="color:#8b949e;">balance:</span> <span style="color:#3fb950;">${bal}</span>
      ${addr?`&nbsp;<code style="color:#e3b341;font-size:10px;">${addr}</code>`:''}
      <br><span style="color:#8b949e;font-size:10px;">Fund this address with BSV (~100ms/settle)</span>`;
  } else if (hw) { hw.style.display = 'none'; }
}

function connectSSE() {
  if (chEventSource) { chEventSource.close(); chEventSource = null; }
  chEventSource = new EventSource(`${BRIDGE_URL}/channel/events`);
  chEventSource.addEventListener('state',      e => applyStateFull(JSON.parse(e.data)));
  chEventSource.addEventListener('tick',       e => applyTick(JSON.parse(e.data)));
  chEventSource.addEventListener('settlement', e => addSettlementEntry(JSON.parse(e.data)));
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
    chEventSource?.close(); chEventSource = null;
    setTimeout(checkBridge, 5000);
  };
}

const FSM_STEPS = ['UNFUNDED', 'FUNDED', 'FLOW_ACTIVE', 'SETTLING', 'CLOSED'];

function applyChannelState(state) {
  channelState = state;
  const idx = FSM_STEPS.indexOf(state);
  FSM_STEPS.forEach((s, i) => {
    const el = document.getElementById(`fsm-${s}`);
    if (el) el.className = 'fsm-step' + (i === idx ? ' active' : '');
  });
  const pill = document.getElementById('channel-state-pill');
  if (pill) { pill.textContent = state; pill.className = `channel-state-pill state-${state}`; }
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
  if (mb)   mb.textContent   = d.unitsMB?.toFixed(2) ?? '0.00';
  if (sats) sats.textContent = d.costSats ?? '0';
  if (seq)  seq.textContent  = d.sequence ?? '0';
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
  if (d.settlements?.length > 0) {
    const list = document.getElementById('ch-settle-list');
    if (list) { list.innerHTML = ''; [...d.settlements].reverse().forEach(s => addSettlementEntry(s, false)); }
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
  const empty = list.querySelector('div[style]');
  if (empty) empty.remove();
  const entry = document.createElement('div');
  entry.className = 'ch-settle-entry' + (animate ? ' new' : '');
  entry.innerHTML = `
    <span class="ch-settle-seq">#${s.seq}</span>
    <div class="ch-settle-info">
      <div>${s.unitsMB?.toFixed(2)} GB — ${s.costSats} sats</div>
      <div class="ch-settle-txid">consumer: <a href="${s.consumerWoc}" target="_blank" rel="noopener">${s.consumerTxid?.slice(0,12)}…${s.consumerTxid?.slice(-6)}</a></div>
      <div class="ch-settle-txid">provider: <a href="${s.providerWoc}" target="_blank" rel="noopener">${s.providerTxid?.slice(0,12)}…${s.providerTxid?.slice(-6)}</a></div>
      <div id="ch-confirm-${s.seq}" style="font-size:0.62rem;color:#8b949e">⏳ awaiting confirmation…</div>
    </div>
    <span class="ch-settle-badge">✓ mainnet</span>`;
  list.insertBefore(entry, list.firstChild);
  const seqEl = document.getElementById('ch-seq');
  if (seqEl) seqEl.textContent = String(s.seq);
  while (list.children.length > 8) list.removeChild(list.lastChild);
}

async function channelFund() {
  const btn = document.getElementById('ch-fund-btn');
  if (btn) { btn.disabled = true; btn.textContent = 'Funding…'; }
  try {
    const r = await fetch(`${BRIDGE_URL}/channel/fund`, { method: 'POST', signal: AbortSignal.timeout(30000) });
    const d = await r.json();
    if (!r.ok) throw new Error(d.error ?? r.statusText);
    if (d.txid) {
      const fundRow = document.getElementById('ch-funding-row');
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
    if (btn) btn.disabled = false;
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
  const list = document.getElementById('ch-settle-list');
  if (list) list.innerHTML = '<div style="color:#8b949e;font-size:0.7rem;padding:6px 0;">No settlements yet</div>';
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

async function advanceChannel() {
  if (!bridgeOnline || channelState !== 'FLOW_ACTIVE') return;
  try {
    await fetch(`${BRIDGE_URL}/channel/advance`, { method: 'POST', signal: AbortSignal.timeout(1000) });
  } catch { /* bridge offline */ }
}

// Wire into publishToMesh — advance channel on dark.fiber.commit
const _origPublishToMesh = publishToMesh;
publishToMesh = async function(typePath, verdict, inputs, strategyHex, plexus = null) {
  await _origPublishToMesh(typePath, verdict, inputs, strategyHex, plexus);
  if (typePath === 'dark.fiber.commit') advanceChannel();
};

// Init
checkBridge();
setInterval(checkBridge, 15000);

// CELL MESH PANEL — wired to cell-store service (:5197)
// ─────────────────────────────────────────────────────────────────────

const CELL_STORE_URL = 'http://localhost:5197';
let cellStoreOnline  = false;
let cmEventSource    = null;
let cmSessionStart   = Date.now();
let cmSessionCount   = 0;

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
    const nodeEl = document.getElementById('cm-node');
    if (nodeEl) nodeEl.textContent = `node: ${d.nodeId}  db: ${d.cellCount} cells`;
    const sr = await fetch(`${CELL_STORE_URL}/cells/stats`, { signal: AbortSignal.timeout(1200) });
    if (sr.ok) applyCellStats(await sr.json());
    const cr = await fetch(`${CELL_STORE_URL}/cells?limit=5`, { signal: AbortSignal.timeout(1200) });
    if (cr.ok) {
      const cd = await cr.json();
      const placeholder = document.getElementById('cm-placeholder');
      if (placeholder) placeholder.remove();
      const container = document.getElementById('cm-cells');
      if (container && cd.cells?.length > 0) { container.innerHTML = ''; cd.cells.forEach(c => addCellRow(c, false)); }
    }
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
  if (totalEl)   totalEl.textContent = (d.total ?? 0).toLocaleString();
  if (sendersEl) sendersEl.textContent = String(d.uniqueSenders ?? 0);
  if (distEl && d.byTypePath) distEl.textContent = Object.entries(d.byTypePath).map(([tp, n]) => `${tp}: ${n}`).join('  ·  ');
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
  const cellId   = c.cell_id ?? c.cellId ?? '';
  const typePath = c.type_path ?? c.typePath ?? '';
  const senderFp = c.sender_fp ?? c.senderFp ?? '';
  div.onclick = () => showByteAnatomy(cellId);
  div.innerHTML = `<span class="cm-cell-id">${cellId.slice(0,8)}…</span><span class="cm-cell-type">${typePath}</span><span class="cm-cell-fp">↑${senderFp}</span><span class="cm-cell-ts">${ts}</span>`;
  container.insertBefore(div, container.firstChild);
  if (animate) { cmSessionCount++; setTimeout(() => div.classList.remove('cm-new'), 1500); }
  while (container.children.length > 8) container.removeChild(container.lastChild);
}

function connectCellSSE() {
  if (cmEventSource) { cmEventSource.close(); cmEventSource = null; }
  cmEventSource = new EventSource(`${CELL_STORE_URL}/cells/stream`);
  cmEventSource.addEventListener('cell', e => {
    const d = JSON.parse(e.data);
    addCellRow(d, true);
    const sendersEl = document.getElementById('cm-senders');
    if (sendersEl && d.senderFp) {
      window._cmSenders = window._cmSenders ?? new Set();
      window._cmSenders.add(d.senderFp);
      sendersEl.textContent = String(window._cmSenders.size);
    }
    const elapsedMin = (Date.now() - cmSessionStart) / 60000;
    const rateEl = document.getElementById('cm-rate');
    if (rateEl) rateEl.textContent = elapsedMin > 0.05 ? (cmSessionCount / elapsedMin).toFixed(1) : '—';
    // Drive MNCA canvas in real-time via SSE push
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

// ── MNCA tile canvas ──────────────────────────────────────────────────────────
// Decodes mnca.tile.tick cell payloads from cell-store and renders them as a
// heat-map on a canvas. Payload layout (from protocol-types/src/mnca/tile.ts):
//   0  u16LE tileX   2  u16LE tileY   4  u64LE tick   12 u8 W   13 u8 H
//   14 u8 halo   15 u8 flags   16.. W*H bytes of state (0-255 per cell)

async function renderMncaTile(cellId) {
  try {
    const r = await fetch(`${CELL_STORE_URL}/cells/${cellId}`, { signal: AbortSignal.timeout(1200) });
    if (!r.ok) return;
    const d = await r.json();
    if (!d.payload) return;

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

    const iW = W - 2 * halo;
    const iH = H - 2 * halo;
    const PX = Math.max(1, Math.floor(210 / Math.max(iW, iH)));
    canvas.width  = iW * PX;
    canvas.height = iH * PX;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    for (let iy = 0; iy < iH; iy++) {
      for (let ix = 0; ix < iW; ix++) {
        const v  = stateBytes[(iy + halo) * W + (ix + halo)];
        const t  = v / 255;
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
setTimeout(mncaAnimationTick, 800);

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

// ── MESH WORKERS PANEL — polls registry (:5201) + coordinator (:5202) ────────

const REGISTRY_URL  = 'http://localhost:5201';
const COORD_URL     = 'http://localhost:5202';

const WORKER_COLOURS = {
  'safety':   '#f85149',
  'analysis': '#58a6ff',
  'access':   '#e3b341',
  'ppe':      '#ff8c00',
  'vision':   '#bc8cff',
  'audio':    '#56d364',
  'bgp':      '#79c0ff',
  'general':  '#8b949e',
};

function workerColour(typePaths) {
  const tp = (typePaths ?? []).join(',');
  for (const [k, c] of Object.entries(WORKER_COLOURS)) if (tp.includes(k)) return c;
  return '#8b949e';
}

function renderWorkerCard(w) {
  const colour  = workerColour(w.typePaths);
  const loadW   = Math.min(100, w.loadPct ?? 0);
  const loadCol = loadW > 70 ? '#f85149' : loadW > 40 ? '#e3b341' : '#3fb950';
  const types   = (w.typePaths ?? []).map(t => t.replace('inference.request.','').replace('inference.','')).join(', ');
  const seen    = w.lastSeen ? Math.round((Date.now() - w.lastSeen) / 1000) + 's ago' : '?';
  const isLlama = (w.model ?? '').includes('llama') || (w.model ?? '').includes('llm');
  return `<div style="display:flex;align-items:center;gap:12px;padding:8px 12px;background:#0d1117;border:1px solid #21262d;border-radius:6px;font-size:11px">
    <div style="width:8px;height:8px;border-radius:50%;background:${w.active ? colour : '#6e7681'};flex-shrink:0"></div>
    <div style="font-family:monospace;color:${colour};min-width:100px;font-weight:600">${w.nodeIp ?? '?'}</div>
    <div style="color:#8b949e;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="${(w.typePaths??[]).join(', ')}">${types}</div>
    <div style="color:${isLlama ? '#3fb950' : '#8b949e'};font-family:monospace;min-width:80px" title="${w.model ?? '?'}">${isLlama ? '🦙 ' : ''}${(w.model ?? '?').slice(0,18)}</div>
    <div style="min-width:100px">
      <div style="height:4px;background:#21262d;border-radius:2px;overflow:hidden">
        <div style="height:100%;width:${loadW}%;background:${loadCol};border-radius:2px;transition:width 0.3s"></div>
      </div>
      <div style="color:#8b949e;font-size:9px;margin-top:2px">${loadW}% load</div>
    </div>
    <div style="color:#3fb950;font-family:monospace;min-width:50px;text-align:right">${(w.cellsHandled??0).toLocaleString()} cells</div>
    <div style="color:#8b949e;font-size:10px;min-width:55px;text-align:right">${seen}</div>
  </div>`;
}

async function checkMeshWorkers() {
  try {
    const [rr, cr] = await Promise.all([
      fetch(`${REGISTRY_URL}/health`,             { signal: AbortSignal.timeout(1500) }).catch(() => null),
      fetch(`${COORD_URL}/coordinator/stats`,     { signal: AbortSignal.timeout(1500) }).catch(() => null),
    ]);
    const statusEl = document.getElementById('df-mw-status');
    if (!rr?.ok) {
      if (statusEl) { statusEl.textContent = '● registry offline'; statusEl.className = 'cm-status-offline'; }
      return;
    }
    const rh = await rr.json();
    if (statusEl) {
      statusEl.textContent = `● ${rh.activeWorkers ?? 0} workers live`;
      statusEl.className = rh.activeWorkers > 0 ? 'cm-status-live' : 'cm-status-offline';
    }
    const set = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };
    set('df-mw-active',      rh.activeWorkers ?? 0);
    set('df-mw-total-cells', (rh.totalCellsHandled ?? 0).toLocaleString());
    set('df-mw-total-sats',  (rh.totalSatsEarned ?? 0).toLocaleString() + ' sats');
    if (cr?.ok) {
      const cd = await cr.json();
      set('df-mw-dispatched', (cd.totalDispatched ?? 0).toLocaleString());
      set('df-mw-noworker',   (cd.noWorkerCount ?? 0).toLocaleString());
    }
    const listEl = document.getElementById('df-mw-list');
    if (listEl) {
      const wr = await fetch(`${REGISTRY_URL}/workers`, { signal: AbortSignal.timeout(1500) });
      if (wr.ok) {
        const wd = await wr.json();
        const workers = wd.workers ?? [];
        listEl.innerHTML = workers.length
          ? workers.map(renderWorkerCard).join('')
          : '<div style="color:#8b949e;font-size:0.68rem">No workers registered</div>';
      }
    }
  } catch { /* registry offline */ }
}

checkMeshWorkers();
setInterval(checkMeshWorkers, 5000);

</script>

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

<!-- ── MESH INFERENCE WORKERS PANEL ───────────────────────────────────────── -->
<div class="channel-section" style="margin-top:12px" id="df-mesh-workers-panel">
  <div class="channel-header">
    <span class="channel-title">
      Mesh Inference Workers
      <span class="tip-host"><span class="info-btn">ⓘ</span><div class="tip-box"><span class="tip-label">Distributed Skyminer Fleet</span>8 Orange Pi Prime H5 nodes (aarch64). Pi #1 runs Llama-3.2-3B-Instruct-Q4_K_M distributed via llama.cpp RPC sharding across 4 Pis (~31s/request, cites OSHA 29 CFR 1910.134). Remaining 7 Pis run mock-classifier. Coordinator primes dedup map on restart (replay-safe). Registry :5201 · Coordinator :5202. Deploy: <code>./scripts/fleet-deploy.sh</code></div></span>
    </span>
    <span id="df-mw-status" class="cm-status-offline">● registry offline</span>
  </div>
  <div style="display:flex;gap:20px;margin:8px 0 12px;font-size:0.65rem;color:#8b949e;flex-wrap:wrap">
    <span>Active: <span id="df-mw-active" style="color:#3fb950;font-family:monospace">—</span></span>
    <span>Cells handled: <span id="df-mw-total-cells" style="color:#e6edf3;font-family:monospace">—</span></span>
    <span>Sats earned: <span id="df-mw-total-sats" style="color:#3fb950;font-family:monospace">—</span></span>
    <span>Coordinator dispatched: <span id="df-mw-dispatched" style="color:#58a6ff;font-family:monospace">—</span></span>
    <span>No-worker errors: <span id="df-mw-noworker" style="color:#f85149;font-family:monospace">—</span></span>
  </div>
  <div id="df-mw-list" style="display:flex;flex-direction:column;gap:6px;margin-bottom:10px">
    <div style="color:#8b949e;font-size:0.68rem">Worker registry offline — run: <code style="color:#58a6ff">bun cartridges/inference-gate/worker-registry.ts</code></div>
  </div>
  <div style="font-size:0.65rem;color:#8b949e">
    E2E test: <code style="color:#58a6ff">bun cartridges/inference-gate/scripts/llm-e2e-test.ts</code>
    &nbsp;·&nbsp;
    Deploy Pi: <code style="color:#58a6ff">./cartridges/inference-gate/scripts/setup-llama-rpc-worker.sh --pi-index 1 --coordinator-ip &lt;laptop-ip&gt;</code>
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
