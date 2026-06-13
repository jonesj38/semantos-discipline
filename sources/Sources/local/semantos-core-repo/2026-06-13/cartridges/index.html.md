---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/index.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.337765+00:00
---

# cartridges/index.html

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Layer Collapse Demo — Command Centre</title>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  :root {
    --bg: #0d1117; --surface: #161b22; --border: #30363d;
    --text: #e6edf3; --muted: #8b949e; --live: #3fb950; --warn: #d29922; --err: #f85149;
    --inference: #f78166; --bsv: #ff8c00; --ixp: #58a6ff; --p2p: #bc8cff;
    --compute: #79c0ff; --dark: #56d364; --ipv6: #e3b341; --mnca: #8b949e;
  }
  body { background: var(--bg); color: var(--text); font-family: 'SF Mono', 'Fira Code', monospace;
         font-size: 13px; line-height: 1.5; min-height: 100vh; }

  header { padding: 20px 28px 12px; border-bottom: 1px solid var(--border);
           display: flex; justify-content: space-between; align-items: baseline; }
  header h1 { font-size: 18px; font-weight: 600; letter-spacing: .02em; }
  header p  { color: var(--muted); font-size: 11px; }
  #status-row { display: flex; gap: 10px; font-size: 11px; }
  .pill { padding: 2px 8px; border-radius: 10px; border: 1px solid var(--border);
          background: var(--surface); color: var(--muted); white-space: nowrap; }
  .pill-live { border-color: var(--live); color: var(--live); }
  .pill-warn { border-color: var(--warn); color: var(--warn); }
  .pill-err  { border-color: var(--err);  color: var(--err);  }

  /* ── Hero stats ─────────────────────────────────────────── */
  .hero { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px;
          padding: 20px 28px; border-bottom: 1px solid var(--border); }
  .stat { background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 14px 16px; }
  .stat-label { font-size: 10px; color: var(--muted); text-transform: uppercase; letter-spacing: .08em; margin-bottom: 4px; }
  .stat-value { font-size: 26px; font-weight: 700; letter-spacing: -.02em; }
  .stat-sub   { font-size: 10px; color: var(--muted); margin-top: 2px; }

  /* ── Main grid ─────────────────────────────────────────── */
  .main { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; padding: 20px 28px; }
  .panel { background: var(--surface); border: 1px solid var(--border); border-radius: 8px; overflow: hidden; }
  .panel-head { padding: 10px 14px; border-bottom: 1px solid var(--border);
                display: flex; justify-content: space-between; align-items: center; }
  .panel-title { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: .08em; color: var(--muted); }
  .panel-body  { padding: 12px 14px; }

  /* ── Routing table ─────────────────────────────────────── */
  .rtable { width: 100%; border-collapse: collapse; font-size: 11px; }
  .rtable th { color: var(--muted); font-weight: 500; text-align: right; padding: 3px 6px;
               border-bottom: 1px solid var(--border); }
  .rtable th:first-child { text-align: left; }
  .rtable td { text-align: right; padding: 4px 6px; border-bottom: 1px solid #1c2128; }
  .rtable td:first-child { text-align: left; font-family: monospace; }
  .tier-dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%; margin-right: 5px; }
  .bar-cell { width: 80px; }
  .bar-bg { background: #1c2128; border-radius: 2px; height: 6px; overflow: hidden; }
  .bar-fill { height: 6px; border-radius: 2px; transition: width .5s; }

  /* ── Settlement log ─────────────────────────────────────── */
  #settle-log { max-height: 210px; overflow-y: auto; }
  .settle-row { display: grid; grid-template-columns: 40px 60px 1fr 1fr;
                gap: 6px; padding: 4px 0; border-bottom: 1px solid #1c2128; font-size: 11px; align-items: center; }
  .settle-row:last-child { border-bottom: none; }
  .settle-num { color: var(--muted); }
  .settle-mb  { color: var(--text); }
  .settle-txid a { color: var(--ixp); text-decoration: none; font-family: monospace; font-size: 10px; }
  .settle-txid a:hover { text-decoration: underline; }

  /* ── Layer cards ────────────────────────────────────────── */
  .layers { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px;
            padding: 0 28px 20px; }
  .layer-card { background: var(--surface); border: 1px solid var(--border);
                border-radius: 8px; padding: 14px; cursor: pointer; transition: border-color .2s; }
  .layer-card:hover { border-color: #58a6ff55; }
  .layer-card a { text-decoration: none; color: inherit; display: block; }
  .lc-name  { font-size: 13px; font-weight: 600; margin-bottom: 4px; }
  .lc-sub   { font-size: 10px; color: var(--muted); margin-bottom: 10px; }
  .lc-stat  { font-size: 20px; font-weight: 700; }
  .lc-label { font-size: 10px; color: var(--muted); }
  .lc-link  { font-size: 10px; color: var(--ixp); margin-top: 8px; }

  /* ── Fuzzer section ─────────────────────────────────────── */
  .fuzzer-box { background: #0d1117; border: 1px solid var(--border);
                border-radius: 6px; padding: 10px 14px; font-size: 11px;
                margin: 0 28px 20px; }
  .fuzzer-box code { color: var(--ipv6); }
  .fuzzer-box p { color: var(--muted); margin-top: 4px; }

  /* ── Footer ─────────────────────────────────────────────── */
  footer { border-top: 1px solid var(--border); padding: 10px 28px;
           display: flex; gap: 16px; font-size: 10px; color: var(--muted); }
  footer a { color: var(--ixp); text-decoration: none; }
</style>
</head>
<body>

<header>
  <div>
    <h1>Layer Collapse Demo — Command Centre</h1>
    <p>Compute · Network · Storage · Money — unified in a 1,024-byte cell</p>
  </div>
  <div id="status-row">
    <span id="st-relay"  class="pill">○ Relay</span>
    <span id="st-bridge" class="pill">○ Bridge</span>
    <span id="st-store"  class="pill">○ Cell Store</span>
  </div>
</header>

<!-- ── Hero stats ──────────────────────────────────────────────────────── -->
<div class="hero">
  <div class="stat">
    <div class="stat-label">Cells Routed</div>
    <div class="stat-value" id="h-cells">—</div>
    <div class="stat-sub" id="h-rate">—</div>
  </div>
  <div class="stat">
    <div class="stat-label">Sats Routed (simulated)</div>
    <div class="stat-value" id="h-sats">—</div>
    <div class="stat-sub" id="h-sats-sub">across all tiers</div>
  </div>
  <div class="stat">
    <div class="stat-label">BSV Settlements</div>
    <div class="stat-value" id="h-settle">—</div>
    <div class="stat-sub" id="h-settle-sub">real txns on mainnet</div>
  </div>
  <div class="stat">
    <div class="stat-label">Type Paths Seen</div>
    <div class="stat-value" id="h-paths">—</div>
    <div class="stat-sub">of 4,096 (8×8×8×8)</div>
  </div>
</div>

<!-- ── Main grid: routing + settlements ───────────────────────────────── -->
<div class="main">

  <!-- Routing table -->
  <div class="panel">
    <div class="panel-head">
      <span class="panel-title">TypeHash Routing — Payment Priority</span>
      <span id="rt-total" style="font-size:10px;color:var(--muted)">loading…</span>
    </div>
    <div class="panel-body">
      <table class="rtable">
        <thead>
          <tr>
            <th>Tier</th>
            <th>Hits</th>
            <th>Sats/cell</th>
            <th>Sats routed</th>
            <th>5s rate</th>
            <th class="bar-cell">Share</th>
          </tr>
        </thead>
        <tbody id="rt-body"></tbody>
      </table>
    </div>
  </div>

  <!-- Settlement log -->
  <div class="panel">
    <div class="panel-head">
      <span class="panel-title">BSV Settlement Log (MND · PushDrop Anchors)</span>
      <span id="settle-count" style="font-size:10px;color:var(--muted)">loading…</span>
    </div>
    <div class="panel-body" id="settle-log">
      <div style="color:var(--muted);font-size:11px;text-align:center;padding:20px">
        No settlements yet — fund the channel
      </div>
    </div>
  </div>

</div>

<!-- ── Layer cards ─────────────────────────────────────────────────────── -->
<div class="layers">
  <div class="layer-card">
    <a href="ixp-routing/verify/index.html">
      <div class="lc-name" style="color:var(--ixp)">⬡ IXP Routing Layer</div>
      <div class="lc-sub">BGP policy · threshold_commit · Rúnar-governed</div>
      <div class="lc-stat" id="lc-ixp-cells">—</div>
      <div class="lc-label">ixp.* cells routed</div>
      <div class="lc-link">→ Open dashboard</div>
    </a>
  </div>
  <div class="layer-card">
    <a href="dark-fiber/verify/index.html">
      <div class="lc-name" style="color:var(--dark)">⬡ Dark Fiber Layer</div>
      <div class="lc-sub">Wavelength spot market · SCADA actuate · EU Networks</div>
      <div class="lc-stat" id="lc-dark-cells">—</div>
      <div class="lc-label">dark.* cells routed</div>
      <div class="lc-link">→ Open dashboard</div>
    </a>
  </div>
  <div class="layer-card">
    <a href="inference-gate/verify/index.html">
      <div class="lc-name" style="color:var(--inference)">⬡ Inference Gate Layer</div>
      <div class="lc-sub">Policy-gated AI compute · GDPR Article 30 · cert-bound</div>
      <div class="lc-stat" id="lc-inf-cells">—</div>
      <div class="lc-label">inference.* cells routed</div>
      <div class="lc-link">→ Open dashboard</div>
    </a>
  </div>
</div>

<!-- ── Type-fuzzer box ─────────────────────────────────────────────────── -->
<div class="fuzzer-box">
  <strong>TypeHash Fuzzer</strong> — stress all 4,096 type paths and watch the routing table live:<br>
  <code>bun cartridges/shared/demo/type-fuzzer.ts</code> &nbsp;·&nbsp;
  <code>FUZZ_RATE=500 FUZZ_SECS=10 bun cartridges/shared/demo/type-fuzzer.ts</code>
  <p>Each cell carries a canonical 32-byte typeHash = sha256(tier)[0:8] ‖ sha256(domain)[0:8] ‖ sha256(verb)[0:8] ‖ sha256(qualifier)[0:8].
     One memcmp on bytes 0–7 selects the payment contract tier. Click any cell row in a dashboard to inspect byte anatomy.</p>
</div>

<footer>
  <span>Layer Collapse Demo · feat/infra-demos</span>
  <a href="ixp-routing/verify/index.html">IXP Routing</a>
  <a href="dark-fiber/verify/index.html">Dark Fiber</a>
  <a href="inference-gate/verify/index.html">Inference Gate</a>
  <span id="footer-ts" style="margin-left:auto"></span>
</footer>

<script>
const RELAY_URL      = 'http://localhost:5199';
const BRIDGE_URL     = 'http://localhost:5198';
const CELL_STORE_URL = 'http://localhost:5197';

const TIER_COLOURS = {
  inference: '#f78166', bsv: '#ff8c00', ixp: '#58a6ff', p2p: '#bc8cff',
  compute: '#79c0ff', dark: '#56d364', ipv6: '#e3b341', mnca: '#8b949e', default: '#6e7681',
};

// ── Helpers ────────────────────────────────────────────────────────────────

function $(id) { return document.getElementById(id); }
function fmt(n) { return n >= 1e6 ? (n/1e6).toFixed(2)+'M' : n >= 1e3 ? (n/1e3).toFixed(1)+'k' : String(n); }
function pill(id, live, text) {
  const el = $(id);
  if (!el) return;
  el.textContent = live ? `● ${text}` : `○ ${text} offline`;
  el.className = 'pill ' + (live ? 'pill-live' : 'pill-err');
}

// ── Relay + routing stats ──────────────────────────────────────────────────

let prevCells = 0, prevTs = Date.now();
let seenTypePaths = new Set();

async function fetchRelayStats() {
  try {
    const r = await fetch(`${RELAY_URL}/routing/stats`, { signal: AbortSignal.timeout(1500) });
    if (!r.ok) throw new Error();
    pill('st-relay', true, 'Relay');
    const d = await r.json();
    const total = d.totalCells || 0;
    const sats  = d.totalSats  || 0;
    const now   = Date.now();
    const rate  = Math.round((total - prevCells) / ((now - prevTs) / 1000));
    prevCells = total; prevTs = now;

    $('h-cells').textContent = fmt(total);
    $('h-rate').textContent  = `${rate}/s  ·  ${d.uniqueContracts || 0} tiers active`;
    $('h-sats').textContent  = fmt(sats);
    $('rt-total').textContent = `${total.toLocaleString()} cells total`;

    // Routing table
    const contracts = (d.contracts || []).sort((a, b) => b.hits - a.hits);
    const tbody = $('rt-body');
    tbody.innerHTML = '';
    for (const c of contracts) {
      if (!c.hits) continue;
      const pct = total ? (c.hits / total * 100) : 0;
      const col = TIER_COLOURS[c.label] ?? TIER_COLOURS.default;
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><span class="tier-dot" style="background:${col}"></span>${c.label}</td>
        <td>${c.hits.toLocaleString()}</td>
        <td style="color:${col}">${c.satsPerCell}</td>
        <td>${c.satsRouted.toLocaleString()}</td>
        <td>${c.rate5s}/s</td>
        <td class="bar-cell">
          <div class="bar-bg"><div class="bar-fill" style="width:${Math.min(100,pct)}%;background:${col}"></div></div>
          <span style="color:var(--muted);font-size:10px">${pct.toFixed(1)}%</span>
        </td>`;
      tbody.appendChild(tr);
    }

    // Layer cell counts from byTypePath in cell-store
    fetchLayerCounts();
  } catch {
    pill('st-relay', false, 'Relay');
  }
}

// ── Cell store stats ───────────────────────────────────────────────────────

async function fetchCellStats() {
  try {
    const r = await fetch(`${CELL_STORE_URL}/cells/stats`, { signal: AbortSignal.timeout(1500) });
    if (!r.ok) throw new Error();
    pill('st-store', true, 'Cell Store');
    const d = await r.json();
    $('h-rate').textContent += `  ·  ${d.cellsPerMin}/min stored`;
    $('h-paths').textContent = Object.keys(d.byTypePath || {}).length;
  } catch {
    pill('st-store', false, 'Cell Store');
  }
}

async function fetchLayerCounts() {
  try {
    const r = await fetch(`${CELL_STORE_URL}/cells/stats`, { signal: AbortSignal.timeout(1500) });
    if (!r.ok) return;
    const d = await r.json();
    const by = d.byTypePath || {};
    let ixp = 0, dark = 0, inf = 0;
    for (const [tp, n] of Object.entries(by)) {
      if (tp.startsWith('ixp.'))       ixp += n;
      else if (tp.startsWith('dark.')) dark += n;
      else if (tp.startsWith('inference.')) inf += n;
    }
    $('lc-ixp-cells').textContent  = fmt(ixp);
    $('lc-dark-cells').textContent = fmt(dark);
    $('lc-inf-cells').textContent  = fmt(inf);
    $('h-paths').textContent = Object.keys(by).length;
  } catch {}
}

// ── Bridge + settlements ───────────────────────────────────────────────────

async function fetchBridgeStats() {
  try {
    const r = await fetch(`${BRIDGE_URL}/channel/state`, { signal: AbortSignal.timeout(1500) });
    if (!r.ok) throw new Error();
    pill('st-bridge', true, 'Bridge');
    const d = await r.json();
    const setts = d.settlements || [];
    $('h-settle').textContent = setts.length;
    $('h-settle-sub').textContent = `state: ${d.state}  seq: ${d.sequence}`;
    $('settle-count').textContent = `${setts.length} settlements`;

    const log = $('settle-log');
    if (!setts.length) return;
    log.innerHTML = '';
    for (const s of [...setts].reverse().slice(0, 20)) {
      const row = document.createElement('div');
      row.className = 'settle-row';
      const ts = s.ts ? new Date(s.ts).toLocaleTimeString() : '';
      row.innerHTML = `
        <span class="settle-num">#${s.seq}</span>
        <span class="settle-mb">${s.unitsMB}MB</span>
        <span class="settle-txid">${s.consumerTxid
          ? `<a href="https://whatsonchain.com/tx/${s.consumerTxid}" target="_blank" title="consumer">${s.consumerTxid.slice(0,16)}…</a>`
          : '<span style="color:var(--muted)">pending</span>'}</span>
        <span class="settle-txid">${s.anchorTxid
          ? `<a href="https://whatsonchain.com/tx/${s.anchorTxid}" target="_blank" title="anchor">⚓ ${s.anchorTxid.slice(0,16)}…</a>`
          : `<span style="color:var(--muted)">${ts}</span>`}</span>`;
      log.appendChild(row);
    }
  } catch {
    pill('st-bridge', false, 'Bridge');
  }
}

// ── Polling ────────────────────────────────────────────────────────────────

async function tick() {
  await Promise.all([fetchRelayStats(), fetchCellStats(), fetchBridgeStats()]);
  $('footer-ts').textContent = new Date().toLocaleTimeString();
}

tick();
setInterval(tick, 4000);
</script>
</body>
</html>

```
