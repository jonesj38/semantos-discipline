---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/poker-dashboard.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.314950+00:00
---

# scripts/poker-dashboard.html

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Semantos Poker Arena — Live Casino</title>
<style>
  :root {
    --bg: #0a0e14;
    --card-bg: #131920;
    --felt: #0d4a2e;
    --felt-border: #1a6b42;
    --gold: #f0b429;
    --green: #00e676;
    --red: #ff5252;
    --blue: #40c4ff;
    --white: #e8eaed;
    --dim: #5f6b7a;
    --tx-flash: #f0b429;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: var(--bg);
    color: var(--white);
    font-family: 'SF Mono', 'Fira Code', 'JetBrains Mono', monospace;
    overflow-x: hidden;
  }

  /* ── Header ── */
  .header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 16px 24px;
    border-bottom: 1px solid #1e2630;
    background: linear-gradient(180deg, #111820 0%, var(--bg) 100%);
  }
  .header h1 {
    font-size: 20px;
    font-weight: 600;
    background: linear-gradient(90deg, var(--gold), #ff9100);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    letter-spacing: 1px;
  }
  .header .subtitle { color: var(--dim); font-size: 12px; margin-top: 2px; }

  /* ── Stats Bar ── */
  .stats-bar {
    display: flex;
    gap: 32px;
    padding: 12px 24px;
    border-bottom: 1px solid #1e2630;
    background: #0d1117;
    flex-wrap: wrap;
  }
  .stat {
    display: flex;
    flex-direction: column;
    align-items: center;
  }
  .stat-value {
    font-size: 28px;
    font-weight: 700;
    color: var(--green);
    line-height: 1;
  }
  .stat-value.gold { color: var(--gold); }
  .stat-value.blue { color: var(--blue); }
  .stat-value.red { color: var(--red); }
  .stat-label {
    font-size: 10px;
    color: var(--dim);
    text-transform: uppercase;
    letter-spacing: 1px;
    margin-top: 4px;
  }
  .target-badge {
    display: inline-block;
    padding: 4px 12px;
    border-radius: 12px;
    font-size: 13px;
    font-weight: 600;
    margin-left: auto;
    align-self: center;
  }
  .target-badge.pass { background: #00e67622; color: var(--green); border: 1px solid var(--green); }
  .target-badge.miss { background: #ff525222; color: var(--red); border: 1px solid var(--red); }

  /* ── Tables Grid ── */
  .tables-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
    gap: 12px;
    padding: 16px 24px;
  }

  /* ── Single Table ── */
  .table-card {
    background: var(--card-bg);
    border-radius: 12px;
    overflow: hidden;
    border: 1px solid #1e2630;
    transition: border-color 0.3s;
  }
  .table-card.active { border-color: var(--felt-border); }
  .table-card.finished { opacity: 0.6; }

  .table-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 8px 12px;
    background: #0d1117;
    font-size: 12px;
  }
  .table-id { color: var(--gold); font-weight: 600; }
  .table-hand { color: var(--dim); }

  .felt {
    background: radial-gradient(ellipse at center, #0f5e38 0%, var(--felt) 60%, #093d24 100%);
    border: 2px solid var(--felt-border);
    border-radius: 50%;
    margin: 10px 12px;
    padding: 12px 8px;
    min-height: 100px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    position: relative;
  }

  .pot {
    background: #00000066;
    border-radius: 8px;
    padding: 2px 10px;
    font-size: 13px;
    color: var(--gold);
    font-weight: 600;
    margin-bottom: 6px;
  }

  .community-cards {
    display: flex;
    gap: 4px;
    margin-bottom: 4px;
  }
  .card {
    width: 30px;
    height: 42px;
    background: white;
    border-radius: 4px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 11px;
    font-weight: 700;
    color: #1a1a1a;
    box-shadow: 0 2px 4px #00000066;
    transition: transform 0.2s;
  }
  .card.heart, .card.diamond { color: #d32f2f; }
  .card.club, .card.spade { color: #1a1a1a; }
  .card.facedown {
    background: linear-gradient(135deg, #1565c0, #0d47a1);
    color: white;
    font-size: 14px;
  }
  .card.dealing {
    animation: dealIn 0.3s ease-out;
  }
  @keyframes dealIn {
    from { transform: translateY(-30px) scale(0.5); opacity: 0; }
    to { transform: translateY(0) scale(1); opacity: 1; }
  }

  .players-row {
    display: flex;
    justify-content: space-between;
    padding: 6px 12px;
  }
  .player {
    display: flex;
    flex-direction: column;
    align-items: center;
    font-size: 11px;
  }
  .player-name {
    font-weight: 600;
    margin-bottom: 2px;
  }
  .player-name.shark { color: var(--red); }
  .player-name.turtle { color: var(--blue); }
  .player-chips { color: var(--dim); font-size: 10px; }
  .player-cards {
    display: flex;
    gap: 2px;
    margin-top: 3px;
  }
  .player-cards .card {
    width: 22px;
    height: 30px;
    font-size: 8px;
  }

  /* ── Action Flash ── */
  .action-bar {
    padding: 4px 12px;
    font-size: 11px;
    color: var(--dim);
    min-height: 22px;
    display: flex;
    align-items: center;
    gap: 6px;
    border-top: 1px solid #1e2630;
  }
  .action-bar .action-text {
    color: var(--white);
    font-weight: 500;
  }
  .action-bar .action-text.fold { color: var(--red); }
  .action-bar .action-text.raise, .action-bar .action-text.bet { color: var(--gold); }
  .action-bar .action-text.call, .action-bar .action-text.check { color: var(--green); }
  .action-bar .action-text.all-in { color: #ff9100; font-weight: 700; }

  /* ── TX Feed ── */
  .tx-bar {
    padding: 3px 12px;
    font-size: 10px;
    color: var(--dim);
    border-top: 1px solid #1a1f26;
    display: flex;
    align-items: center;
    gap: 4px;
    min-height: 20px;
  }
  .tx-bar a {
    color: var(--gold);
    text-decoration: none;
    font-family: inherit;
  }
  .tx-bar a:hover { text-decoration: underline; }
  .tx-flash {
    animation: txPulse 0.6s ease-out;
  }
  @keyframes txPulse {
    0% { background: #f0b42933; }
    100% { background: transparent; }
  }
  .tx-badge {
    display: inline-block;
    padding: 1px 5px;
    border-radius: 3px;
    font-size: 9px;
    font-weight: 600;
  }
  .tx-badge.celltoken { background: #00e67622; color: var(--green); }
  .tx-badge.opreturn { background: #40c4ff22; color: var(--blue); }
  .tx-badge.kernel { background: #b388ff22; color: #b388ff; font-weight: 700; }
  .tx-badge.channel-open { background: #69f0ae22; color: #69f0ae; font-weight: 700; }
  .tx-badge.settlement { background: #ffd74022; color: #ffd740; font-weight: 700; }

  /* ── Winner overlay ── */
  .winner-overlay {
    position: absolute;
    inset: 0;
    background: #000000aa;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 50%;
    animation: winFade 0.5s ease-in;
  }
  .winner-overlay span {
    font-size: 14px;
    font-weight: 700;
    color: var(--gold);
    text-shadow: 0 0 10px var(--gold);
  }
  @keyframes winFade {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  /* ── TX Ticker (bottom) ── */
  .tx-ticker {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    background: #0d1117ee;
    border-top: 1px solid #1e2630;
    padding: 6px 24px;
    display: flex;
    gap: 16px;
    overflow: hidden;
    font-size: 11px;
    backdrop-filter: blur(8px);
  }
  .tx-ticker-item {
    white-space: nowrap;
    animation: tickerSlide 0.3s ease-out;
    color: var(--dim);
  }
  .tx-ticker-item a { color: var(--gold); text-decoration: none; }
  @keyframes tickerSlide {
    from { transform: translateX(100px); opacity: 0; }
    to { transform: translateX(0); opacity: 1; }
  }

  /* ── Phase indicator ── */
  .phase-badge {
    display: inline-block;
    padding: 1px 6px;
    border-radius: 4px;
    font-size: 9px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }
  .phase-badge.preflop { background: #ffffff22; color: #aaa; }
  .phase-badge.flop { background: #40c4ff22; color: var(--blue); }
  .phase-badge.turn { background: #f0b42922; color: var(--gold); }
  .phase-badge.river { background: #ff525222; color: var(--red); }
  .phase-badge.complete { background: #00e67622; color: var(--green); }

  /* ── Hypervisor / Red-Team Console ── */
  .hypervisor {
    display: none; /* hidden until first channel event arrives */
    border-top: 1px solid #1e2630;
    border-bottom: 1px solid #1e2630;
    background: linear-gradient(180deg, #14090b 0%, #0a0e14 100%);
    padding: 10px 24px 12px;
  }
  .hypervisor.active {
    display: block;
    animation: hyperFadeIn 0.4s ease-out;
  }
  .hypervisor.alarm {
    border-top: 1px solid var(--red);
    border-bottom: 1px solid var(--red);
    animation: hyperAlarmPulse 1.2s ease-out;
  }
  @keyframes hyperFadeIn {
    from { opacity: 0; transform: translateY(-8px); }
    to { opacity: 1; transform: translateY(0); }
  }
  @keyframes hyperAlarmPulse {
    0%, 100% { box-shadow: none; }
    50% { box-shadow: inset 0 0 24px #ff525266; }
  }
  .hypervisor-header {
    display: flex;
    align-items: center;
    gap: 12px;
    margin-bottom: 10px;
  }
  .hypervisor-title {
    font-size: 12px;
    font-weight: 700;
    letter-spacing: 2px;
    color: var(--red);
    text-transform: uppercase;
  }
  .hypervisor-title::before {
    content: '■';
    color: var(--red);
    margin-right: 6px;
    animation: blink 1.2s infinite;
  }
  @keyframes blink {
    0%, 49% { opacity: 1; }
    50%, 100% { opacity: 0.3; }
  }
  .hypervisor-subtitle {
    font-size: 10px;
    color: var(--dim);
    text-transform: uppercase;
    letter-spacing: 1px;
  }
  .hypervisor-stats {
    display: flex;
    gap: 20px;
    margin-left: auto;
    font-size: 11px;
  }
  .hypervisor-stat {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
  }
  .hypervisor-stat-value {
    font-size: 16px;
    font-weight: 700;
    line-height: 1;
  }
  .hypervisor-stat-value.red { color: var(--red); }
  .hypervisor-stat-value.gold { color: var(--gold); }
  .hypervisor-stat-value.purple { color: #b388ff; }
  .hypervisor-stat-label {
    font-size: 9px;
    color: var(--dim);
    text-transform: uppercase;
    letter-spacing: 1px;
    margin-top: 2px;
  }
  .hypervisor-body {
    display: grid;
    grid-template-columns: minmax(0, 1.4fr) minmax(0, 1fr);
    gap: 12px;
  }
  .hypervisor-section {
    background: #0a0d11;
    border: 1px solid #1e2630;
    border-radius: 8px;
    overflow: hidden;
    min-height: 70px;
  }
  .hypervisor-section-head {
    padding: 6px 10px;
    background: #0d1117;
    border-bottom: 1px solid #1a1f26;
    font-size: 10px;
    color: var(--dim);
    text-transform: uppercase;
    letter-spacing: 1px;
    font-weight: 600;
  }
  .hypervisor-section-head .count-badge {
    display: inline-block;
    background: #ff525222;
    color: var(--red);
    padding: 1px 6px;
    border-radius: 8px;
    font-weight: 700;
    margin-left: 6px;
  }
  .hypervisor-section-head .count-badge.yellow {
    background: #f0b42922;
    color: var(--gold);
  }
  .violation-feed {
    max-height: 180px;
    overflow-y: auto;
    padding: 4px 0;
  }
  .violation-row {
    display: grid;
    grid-template-columns: 64px 1fr auto;
    gap: 8px;
    padding: 6px 10px;
    border-bottom: 1px solid #12161c;
    font-size: 11px;
    line-height: 1.4;
    animation: rowFlash 0.8s ease-out;
  }
  @keyframes rowFlash {
    0% { background: #ff525244; }
    100% { background: transparent; }
  }
  .violation-row:last-child { border-bottom: none; }
  .violation-row .v-time {
    color: var(--dim);
    font-size: 10px;
  }
  .violation-row .v-body {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .violation-row .v-offender {
    color: var(--red);
    font-weight: 700;
  }
  .violation-row .v-ktheorem {
    display: inline-block;
    background: #b388ff22;
    color: #b388ff;
    padding: 0 5px;
    border-radius: 3px;
    font-size: 9px;
    font-weight: 700;
    margin: 0 4px;
  }
  .violation-row .v-reason {
    color: #aaa;
    font-size: 10px;
    display: block;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .violation-row .v-link {
    font-size: 10px;
  }
  .violation-row .v-link a {
    color: var(--gold);
    text-decoration: none;
  }
  .violation-row .v-link a:hover { text-decoration: underline; }
  .watchlist-table {
    max-height: 180px;
    overflow-y: auto;
  }
  .watchlist-row {
    display: grid;
    grid-template-columns: 1fr auto auto;
    gap: 8px;
    padding: 6px 10px;
    border-bottom: 1px solid #12161c;
    font-size: 11px;
    align-items: center;
  }
  .watchlist-row:last-child { border-bottom: none; }
  .watchlist-row.updated {
    animation: watchlistFlash 0.8s ease-out;
  }
  @keyframes watchlistFlash {
    0% { background: #f0b42944; }
    100% { background: transparent; }
  }
  .watchlist-row .w-name {
    color: var(--red);
    font-weight: 700;
  }
  .watchlist-row .w-id {
    color: var(--dim);
    font-size: 9px;
    font-family: inherit;
  }
  .watchlist-row .w-hits {
    display: inline-block;
    padding: 2px 8px;
    border-radius: 10px;
    background: #ff525222;
    color: var(--red);
    font-weight: 700;
    font-size: 11px;
    min-width: 32px;
    text-align: center;
  }
  .watchlist-row .w-cell {
    font-size: 10px;
    color: var(--dim);
  }
  .watchlist-row .w-cell a {
    color: var(--gold);
    text-decoration: none;
  }
  .watchlist-row .w-cell a:hover { text-decoration: underline; }
  .hypervisor-empty {
    padding: 14px;
    font-size: 11px;
    color: var(--dim);
    text-align: center;
    font-style: italic;
  }

  /* ── Connecting overlay ── */
  .connecting {
    position: fixed;
    inset: 0;
    background: var(--bg);
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    z-index: 100;
    transition: opacity 0.5s;
  }
  .connecting.hidden { opacity: 0; pointer-events: none; }
  .connecting h2 { color: var(--gold); margin-bottom: 8px; }
  .connecting p { color: var(--dim); font-size: 13px; }
  .pulse-dot {
    width: 12px; height: 12px;
    background: var(--gold);
    border-radius: 50%;
    margin-bottom: 16px;
    animation: pulse 1.5s infinite;
  }
  @keyframes pulse {
    0%, 100% { transform: scale(1); opacity: 1; }
    50% { transform: scale(1.5); opacity: 0.5; }
  }
</style>
</head>
<body>
  <div class="connecting" id="connecting">
    <div class="pulse-dot"></div>
    <h2>Connecting to Arena...</h2>
    <p>Start the arena: <code>bun run scripts/poker-arena.ts</code></p>
  </div>

  <div class="header">
    <div>
      <h1>SEMANTOS POKER ARENA</h1>
      <div class="subtitle">Open Run Agentic Pay — BSV Hackathon</div>
    </div>
    <div style="text-align:right">
      <div class="subtitle">Claude Haiku Agents × BSV Mainnet</div>
      <div class="subtitle" id="elapsed"></div>
    </div>
  </div>

  <div class="stats-bar" id="statsBar">
    <div class="stat">
      <div class="stat-value gold" id="totalTx">0</div>
      <div class="stat-label">On-Chain TXs</div>
    </div>
    <div class="stat">
      <div class="stat-value" id="txRate">0.0</div>
      <div class="stat-label">TX/sec</div>
    </div>
    <div class="stat">
      <div class="stat-value blue" id="proj24h">0.00</div>
      <div class="stat-label">24h Projected (M)</div>
    </div>
    <div class="stat">
      <div class="stat-value gold" id="matchesActive">0</div>
      <div class="stat-label">Matches Active</div>
    </div>
    <div class="stat">
      <div class="stat-value" id="matchesDone">0/0</div>
      <div class="stat-label">Completed</div>
    </div>
    <div class="stat">
      <div class="stat-value red" id="errorCount">0</div>
      <div class="stat-label">Errors</div>
    </div>
    <div class="stat">
      <div class="stat-value" id="kernelCount" style="color:#b388ff">0</div>
      <div class="stat-label">2PDA Validated</div>
    </div>
    <div class="stat">
      <div class="stat-value" id="channelCount" style="color:#69f0ae">0</div>
      <div class="stat-label">Channels</div>
    </div>
    <div class="stat">
      <div class="stat-value gold" id="satsTransferred">0</div>
      <div class="stat-label">Sats Moved</div>
    </div>
    <div id="targetBadge" class="target-badge miss">TARGET: 1.5M — WARMING UP</div>
  </div>

  <!-- ── Hypervisor / Red-Team Console ── -->
  <!-- Hidden by default. Reveals when the first channel event arrives and
       flashes red whenever the 2PDA kernel catches a violation. -->
  <div class="hypervisor" id="hypervisor">
    <div class="hypervisor-header">
      <div>
        <div class="hypervisor-title">RED-TEAM HYPERVISOR CONSOLE</div>
        <div class="hypervisor-subtitle">2PDA Kernel — Adversarial Event Stream</div>
      </div>
      <div class="hypervisor-stats">
        <div class="hypervisor-stat">
          <div class="hypervisor-stat-value red" id="hvViolationsCaught">0</div>
          <div class="hypervisor-stat-label">Violations Caught</div>
        </div>
        <div class="hypervisor-stat">
          <div class="hypervisor-stat-value gold" id="hvCellsAnchored">0</div>
          <div class="hypervisor-stat-label">Cells Anchored</div>
        </div>
        <div class="hypervisor-stat">
          <div class="hypervisor-stat-value purple" id="hvOffendersTracked">0</div>
          <div class="hypervisor-stat-label">Offenders</div>
        </div>
        <div class="hypervisor-stat">
          <div class="hypervisor-stat-value gold" id="hvWatchlistHits">0</div>
          <div class="hypervisor-stat-label">Watchlist Hits</div>
        </div>
      </div>
    </div>
    <div class="hypervisor-body">
      <div class="hypervisor-section">
        <div class="hypervisor-section-head">
          Kernel Violations
          <span class="count-badge" id="hvViolationBadge">0</span>
        </div>
        <div class="violation-feed" id="hvViolationFeed">
          <div class="hypervisor-empty" id="hvViolationEmpty">
            Awaiting adversarial events — kernel is clean.
          </div>
        </div>
      </div>
      <div class="hypervisor-section">
        <div class="hypervisor-section-head">
          Offender Watchlist
          <span class="count-badge yellow" id="hvWatchlistBadge">0</span>
        </div>
        <div class="watchlist-table" id="hvWatchlistTable">
          <div class="hypervisor-empty" id="hvWatchlistEmpty">
            No offenders on the watchlist.
          </div>
        </div>
      </div>
    </div>
  </div>

  <div class="tables-grid" id="tablesGrid"></div>

  <div class="tx-ticker" id="txTicker"></div>

<script>
// ── State ──
const tables = {};   // matchId → table state
let startTime = null;

// ── Hypervisor state ──
// Tracks kernel violations + per-offender watchlist for the red-team console.
const hypervisor = {
  revealed: false,
  violationsCaught: 0,
  cellsAnchored: 0,
  watchlistHits: 0,
  violations: [], // newest first; capped at MAX_VIOLATIONS
  offenders: {},  // offenderIdHex → { name, hitCount, cellVersion, cellTxid, lastTs }
};
const MAX_VIOLATIONS_DISPLAYED = 20;

function revealHypervisor() {
  if (hypervisor.revealed) return;
  hypervisor.revealed = true;
  document.getElementById('hypervisor').classList.add('active');
}

function flashHypervisorAlarm() {
  const el = document.getElementById('hypervisor');
  el.classList.remove('alarm');
  // Re-trigger the CSS animation by forcing a reflow.
  void el.offsetWidth;
  el.classList.add('alarm');
}

function formatTimeHms(ts) {
  const d = new Date(ts);
  const h = String(d.getHours()).padStart(2, '0');
  const m = String(d.getMinutes()).padStart(2, '0');
  const s = String(d.getSeconds()).padStart(2, '0');
  return `${h}:${m}:${s}`;
}

function escapeHtml(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function renderHypervisorStats() {
  document.getElementById('hvViolationsCaught').textContent = hypervisor.violationsCaught;
  document.getElementById('hvCellsAnchored').textContent = hypervisor.cellsAnchored;
  const offCount = Object.keys(hypervisor.offenders).length;
  document.getElementById('hvOffendersTracked').textContent = offCount;
  document.getElementById('hvWatchlistHits').textContent = hypervisor.watchlistHits;
  document.getElementById('hvViolationBadge').textContent = hypervisor.violations.length;
  document.getElementById('hvWatchlistBadge').textContent = offCount;
}

function renderViolationFeed() {
  const feed = document.getElementById('hvViolationFeed');
  const empty = document.getElementById('hvViolationEmpty');
  if (hypervisor.violations.length === 0) {
    empty.style.display = 'block';
    return;
  }
  empty.style.display = 'none';
  feed.innerHTML = hypervisor.violations.slice(0, MAX_VIOLATIONS_DISPLAYED).map(v => {
    const tx = v.txid
      ? `<a href="https://whatsonchain.com/tx/${v.txid}" target="_blank">${v.txid.slice(0, 10)}…</a>`
      : '<span style="color:#444">no anchor</span>';
    return `
      <div class="violation-row">
        <div class="v-time">${escapeHtml(formatTimeHms(v.ts))}</div>
        <div class="v-body">
          <span class="v-offender">${escapeHtml(v.offenderName)}</span>
          <span class="v-ktheorem">${escapeHtml(v.kTheorem)}</span>
          <span style="color:#555;font-size:10px">v${v.fromVersion}→v${v.attemptedVersion}</span>
          <div class="v-reason">${escapeHtml(v.kernelReason)}</div>
        </div>
        <div class="v-link">${tx}</div>
      </div>
    `;
  }).join('');
}

function renderWatchlistTable() {
  const tbl = document.getElementById('hvWatchlistTable');
  const empty = document.getElementById('hvWatchlistEmpty');
  const entries = Object.values(hypervisor.offenders).sort((a, b) => b.hitCount - a.hitCount);
  if (entries.length === 0) {
    empty.style.display = 'block';
    return;
  }
  empty.style.display = 'none';
  tbl.innerHTML = entries.map(o => {
    const txShort = o.cellTxid ? o.cellTxid.slice(0, 10) + '…' : '—';
    const txLink = o.cellTxid
      ? `<a href="https://whatsonchain.com/tx/${o.cellTxid}" target="_blank">${txShort}</a>`
      : '<span style="color:#444">—</span>';
    const rowClass = o._flashed ? 'watchlist-row updated' : 'watchlist-row';
    return `
      <div class="${rowClass}">
        <div>
          <div class="w-name">${escapeHtml(o.name)}</div>
          <div class="w-id">id: ${escapeHtml(o.offenderIdHex.slice(0, 16))}…</div>
        </div>
        <div class="w-hits" title="Watchlist hit count">${o.hitCount}</div>
        <div class="w-cell">v${o.cellVersion} · ${txLink}</div>
      </div>
    `;
  }).join('');
  // Clear the flash marker after rendering so the next update can re-flash.
  for (const o of entries) delete o._flashed;
}

function handleHypervisorEvent(event) {
  const type = event.type; // 'channel:channel-violation' etc
  const data = event.data || {};
  const ts = event.ts || Date.now();

  // Any channel event reveals the panel — it surfaces the moment the first
  // channel opens so users immediately know what it's for.
  revealHypervisor();

  switch (type) {
    case 'channel:channel-violation': {
      hypervisor.violationsCaught++;
      if (data.anchorKind === 'violation-cell' || data.anchorKind === 'op-return') {
        hypervisor.cellsAnchored++;
      }
      hypervisor.violations.unshift({
        ts,
        offenderName: data.offenderName || '?',
        offenderIdHex: data.offenderIdHex || '',
        kernelReason: data.kernelReason || '',
        kTheorem: data.kTheorem || 'kernel',
        tamperMode: data.tamperMode || null,
        fromVersion: data.fromVersion ?? '?',
        attemptedVersion: data.attemptedVersion ?? '?',
        txid: event.data?.txid || data.txid || null,
        anchorKind: data.anchorKind || 'none',
      });
      if (hypervisor.violations.length > MAX_VIOLATIONS_DISPLAYED * 2) {
        hypervisor.violations.length = MAX_VIOLATIONS_DISPLAYED;
      }
      flashHypervisorAlarm();
      renderViolationFeed();
      renderHypervisorStats();
      break;
    }
    case 'channel:watchlist-hit': {
      hypervisor.watchlistHits++;
      const idHex = data.offenderIdHex || '';
      const existing = hypervisor.offenders[idHex] || {};
      hypervisor.offenders[idHex] = {
        name: data.offenderName || existing.name || '?',
        offenderIdHex: idHex,
        hitCount: data.hitCount ?? (existing.hitCount || 0),
        cellVersion: data.cellVersion ?? (existing.cellVersion || 0),
        cellTxid: event.data?.txid || data.txid || existing.cellTxid || null,
        firstSeen: existing.firstSeen || ts,
        lastTs: ts,
        _flashed: true,
      };
      renderWatchlistTable();
      renderHypervisorStats();
      break;
    }
    case 'channel:channel-open':
    case 'channel:channel-tick':
    case 'channel:channel-settle':
      // Reveal the panel on first channel activity but don't log these to
      // the violation feed — they're routine lifecycle events, not red-team
      // material. The stats strip still updates via the main stats tick.
      break;
    default:
      break;
  }
}

// ── Card rendering ──
const SUIT_SYMBOLS = { h: '♥', d: '♦', c: '♣', s: '♠' };
const SUIT_CLASSES = { h: 'heart', d: 'diamond', c: 'club', s: 'spade' };

function parseCard(label) {
  if (!label || label.length < 2) return { rank: '?', suit: '?', cls: '' };
  const suit = label.slice(-1).toLowerCase();
  const rank = label.slice(0, -1);
  return { rank, suit: SUIT_SYMBOLS[suit] || suit, cls: SUIT_CLASSES[suit] || '' };
}

function renderCard(label, facedown) {
  if (facedown) return '<div class="card facedown dealing">?</div>';
  const c = parseCard(label);
  return `<div class="card ${c.cls} dealing">${c.rank}${c.suit}</div>`;
}

// ── Table HTML ──
function getOrCreateTable(matchId) {
  if (tables[matchId]) return tables[matchId];
  tables[matchId] = {
    el: null,
    hand: 0,
    phase: 'preflop',
    pot: 0,
    community: [],
    players: [
      { name: `Shark-${matchId}`, chips: 5000, cards: [] },
      { name: `Turtle-${matchId}`, chips: 5000, cards: [] },
    ],
    lastAction: '',
    lastTx: null,
    finished: false,
    winner: null,
  };
  const card = document.createElement('div');
  card.className = 'table-card active';
  card.id = `table-${matchId}`;
  card.innerHTML = buildTableHTML(matchId);
  document.getElementById('tablesGrid').appendChild(card);
  tables[matchId].el = card;
  return tables[matchId];
}

function buildTableHTML(matchId) {
  const t = tables[matchId];
  const communityHTML = t.community.map(c => renderCard(c)).join('');
  // Pad with facedown cards to 5
  const remaining = 5 - t.community.length;
  const padHTML = t.phase !== 'complete'
    ? Array(remaining).fill('<div class="card facedown" style="opacity:0.3">?</div>').join('')
    : '';

  const p0cards = t.players[0].cards.length
    ? t.players[0].cards.map(c => renderCard(c)).join('')
    : '<div class="card facedown" style="width:22px;height:30px;font-size:8px">?</div><div class="card facedown" style="width:22px;height:30px;font-size:8px">?</div>';
  const p1cards = t.players[1].cards.length
    ? t.players[1].cards.map(c => renderCard(c)).join('')
    : '<div class="card facedown" style="width:22px;height:30px;font-size:8px">?</div><div class="card facedown" style="width:22px;height:30px;font-size:8px">?</div>';

  const phaseClass = t.phase || 'preflop';
  const kernelBadge = t.lastTx && t.lastTx.kernelValidated ? ' <span class="tx-badge kernel">2PDA ✓</span>' : '';
  const txHTML = t.lastTx
    ? `<span class="tx-badge ${t.lastTx.kind}">${t.lastTx.kind}</span>${kernelBadge} <a href="https://whatsonchain.com/tx/${t.lastTx.txid}" target="_blank">${t.lastTx.txid.slice(0,12)}...</a>`
    : '<span style="color:#333">waiting...</span>';

  const winnerHTML = t.winner
    ? `<div class="winner-overlay"><span>${t.winner} WINS</span></div>`
    : '';

  return `
    <div class="table-header">
      <span class="table-id">TABLE ${matchId}</span>
      <span class="table-hand">Hand #${t.hand} <span class="phase-badge ${phaseClass}">${t.phase}</span></span>
    </div>
    <div class="felt">
      <div class="pot">POT: ${t.pot}</div>
      <div class="community-cards">${communityHTML}${padHTML}</div>
      ${winnerHTML}
    </div>
    <div class="players-row">
      <div class="player">
        <div class="player-name shark">${t.players[0].name}</div>
        <div class="player-chips">${t.players[0].chips} chips</div>
        <div class="player-cards">${p0cards}</div>
      </div>
      <div class="player">
        <div class="player-name turtle">${t.players[1].name}</div>
        <div class="player-chips">${t.players[1].chips} chips</div>
        <div class="player-cards">${p1cards}</div>
      </div>
    </div>
    <div class="action-bar">${t.lastAction || '<span style="color:#333">waiting for action...</span>'}</div>
    <div class="tx-bar tx-flash">${txHTML}</div>
  `;
}

function updateTable(matchId) {
  const t = tables[matchId];
  if (!t || !t.el) return;
  t.el.innerHTML = buildTableHTML(matchId);
  t.el.className = `table-card ${t.finished ? 'finished' : 'active'}`;
}

// ── TX Ticker ──
const MAX_TICKER = 30;
function addToTicker(matchId, txid, kind, kernelValidated) {
  const ticker = document.getElementById('txTicker');
  const item = document.createElement('div');
  item.className = 'tx-ticker-item';
  const kernelBadge = kernelValidated ? ' <span class="tx-badge kernel">2PDA</span>' : '';
  item.innerHTML = `T${matchId} <a href="https://whatsonchain.com/tx/${txid}" target="_blank">${txid.slice(0,10)}</a>${kernelBadge}`;
  ticker.insertBefore(item, ticker.firstChild);
  while (ticker.children.length > MAX_TICKER) {
    ticker.removeChild(ticker.lastChild);
  }
}

// ── Stats Update ──
function updateStats(s) {
  if (!s) return;
  if (!startTime) startTime = Date.now();
  document.getElementById('totalTx').textContent = (s.totalBroadcast || 0).toLocaleString();
  document.getElementById('txRate').textContent = (s.txPerSec || 0).toFixed(1);
  document.getElementById('proj24h').textContent = (s.projected24h || 0).toFixed(2);
  document.getElementById('errorCount').textContent = s.errors || 0;

  if (s.completedMatches !== undefined) {
    document.getElementById('matchesDone').textContent = `${s.completedMatches}/${s.totalMatches || 0}`;
    document.getElementById('matchesActive').textContent = (s.totalMatches || 0) - (s.completedMatches || 0);
  }

  const badge = document.getElementById('targetBadge');
  const proj = s.projected24h || 0;
  if (proj >= 1.5) {
    badge.className = 'target-badge pass';
    badge.textContent = `TARGET: 1.5M ✓ PASS (${proj.toFixed(2)}M)`;
  } else if (s.totalBroadcast > 50) {
    badge.className = 'target-badge miss';
    badge.textContent = `TARGET: 1.5M — ${proj.toFixed(2)}M projected`;
  }

  if (s.elapsed) {
    document.getElementById('elapsed').textContent = `${s.elapsed}s elapsed`;
  }

  // Kernel validation stats
  if (s.kernelValidations !== undefined) {
    document.getElementById('kernelCount').textContent = s.kernelValidations;
  }

  // Channel stats
  if (s.channelsOpen !== undefined) {
    const settled = s.channelsSettled || 0;
    document.getElementById('channelCount').textContent = `${settled}/${s.channelsOpen}`;
  }
  if (s.channelSatsTransferred !== undefined) {
    document.getElementById('satsTransferred').textContent = s.channelSatsTransferred.toLocaleString();
  }
}

// ── WebSocket ──
function connect() {
  const ws = new WebSocket(`ws://${location.host}/ws`);

  ws.onopen = () => {
    document.getElementById('connecting').classList.add('hidden');
  };

  ws.onclose = () => {
    document.getElementById('connecting').classList.remove('hidden');
    setTimeout(connect, 2000);
  };

  ws.onmessage = (msg) => {
    let event;
    try { event = JSON.parse(msg.data); } catch { return; }

    // Hypervisor / red-team channel events
    if (event.gameId === '__hypervisor__') {
      handleHypervisorEvent(event);
      return;
    }

    // Global stats tick
    if (event.gameId === '__arena__' && event.engineStats) {
      updateStats(event.engineStats);
      return;
    }

    // Per-game events
    if (event.engineStats) updateStats(event.engineStats);
    const mid = event.matchId;
    if (mid === undefined || mid === null) return;

    const t = getOrCreateTable(mid);

    switch (event.type) {
      case 'hand-start':
        t.hand = event.handNumber;
        t.phase = 'preflop';
        t.pot = 0;
        t.community = [];
        t.lastAction = '';
        t.lastTx = null;
        t.winner = null;
        if (event.data.players) {
          event.data.players.forEach((p, i) => {
            if (t.players[i]) {
              t.players[i].name = p.name;
              t.players[i].chips = p.chips;
              t.players[i].cards = [];
            }
          });
        }
        updateTable(mid);
        break;

      case 'deal':
        if (event.data.players) {
          event.data.players.forEach((p, i) => {
            if (t.players[i]) t.players[i].cards = p.cards || [];
          });
        }
        updateTable(mid);
        break;

      case 'phase':
        t.phase = event.data.phase;
        t.community = event.data.communityCards || [];
        t.pot = event.data.pot || t.pot;
        updateTable(mid);
        break;

      case 'action': {
        const act = event.data.action;
        const player = event.data.player;
        const amt = event.data.amount;
        const reason = event.data.reasoning;
        const cls = act.replace(' ', '-');
        const amtStr = amt ? ` ${amt}` : '';
        t.lastAction = `<strong>${player}</strong> <span class="action-text ${cls}">${act}${amtStr}</span> <span style="color:#555;font-size:10px">${(reason || '').slice(0, 50)}</span>`;
        t.pot = event.data.pot || t.pot;
        // Update chips
        if (event.data.player && event.data.chips !== undefined) {
          const pi = t.players.findIndex(p => p.name === event.data.player);
          if (pi >= 0) t.players[pi].chips = event.data.chips;
        }
        updateTable(mid);
        break;
      }

      case 'tx': {
        const kind = event.data.kind || 'tx';
        t.lastTx = { txid: event.data.txid, kind, kernelValidated: event.data.kernelValidated || false };
        addToTicker(mid, event.data.txid, kind, event.data.kernelValidated);
        updateTable(mid);
        break;
      }

      case 'hand-end':
        t.winner = null; // brief flash, don't persist overlay
        if (event.data.players) {
          event.data.players.forEach((p, i) => {
            if (t.players[i]) {
              t.players[i].chips = p.chips;
              if (p.cards) t.players[i].cards = p.cards;
            }
          });
        }
        // Flash winner briefly
        t.winner = event.data.winner;
        updateTable(mid);
        setTimeout(() => { t.winner = null; updateTable(mid); }, 1500);
        break;

      case 'game-over':
        t.finished = true;
        t.winner = event.data.winner + ' WINS MATCH';
        updateTable(mid);
        break;
    }
  };
}

connect();
</script>
</body>
</html>

```
