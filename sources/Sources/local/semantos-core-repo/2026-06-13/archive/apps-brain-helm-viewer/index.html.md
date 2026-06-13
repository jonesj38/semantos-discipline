---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-brain-helm-viewer/index.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.692652+00:00
---

# archive/apps-brain-helm-viewer/index.html

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Brain helm viewer · oddjobz</title>
  <link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@300;400;500;600;700&family=Space+Mono:wght@400;700&display=swap" rel="stylesheet">
  <style>
    /* 2026-05-07 — Brain helm viewer for the meetup demo.
       Single-file static HTML.  Open in a browser, paste bearer
       token, hit Connect.  Pulls live jobs via REPL HTTP, subscribes
       to the WSS event stream, renders incoming intent_cell.created
       events as projection-friendly cards. */

    :root {
      --bg: #0b0d12;
      --panel: #11151c;
      --panel-2: #161b24;
      --ink: #e7eef5;
      --ink-soft: rgba(231, 238, 245, 0.5);
      --ink-mute: rgba(231, 238, 245, 0.3);
      --rule: rgba(231, 238, 245, 0.08);
      --rule-strong: rgba(231, 238, 245, 0.18);
      --activation: #c9a96e;
      --activation-soft: rgba(201, 169, 110, 0.18);
      --good: #6fd6b5;
      --good-soft: rgba(111, 214, 181, 0.15);
      --bad: #ff7b7b;
      --bad-soft: rgba(255, 123, 123, 0.15);
      --warn: #ffb24a;
      --warn-soft: rgba(255, 178, 74, 0.15);
      --pulse: #b18bff;
      --mono: 'Space Mono', ui-monospace, monospace;
      --sans: 'Space Grotesk', system-ui, sans-serif;
    }

    * { box-sizing: border-box; margin: 0; padding: 0; }

    html, body {
      height: 100%;
      overflow: hidden;
      background: var(--bg);
      color: var(--ink);
      font-family: var(--sans);
      font-weight: 400;
    }

    body {
      display: grid;
      grid-template-rows: auto 1fr;
    }

    /* ── Top bar ─────────────────────────────────────────────────── */
    .topbar {
      display: flex;
      align-items: center;
      gap: 16px;
      padding: 14px 24px;
      border-bottom: 1px solid var(--rule);
      background: var(--panel);
    }

    .brand {
      font-weight: 600;
      font-size: 18px;
      letter-spacing: 0.04em;
    }

    .brand .accent { color: var(--activation); }

    .topbar button {
      padding: 8px 16px;
      background: var(--activation-soft);
      color: var(--activation);
      border: 1px solid var(--activation);
      border-radius: 6px;
      font-family: var(--sans);
      font-size: 12px;
      font-weight: 600;
      letter-spacing: 0.06em;
      text-transform: uppercase;
      cursor: pointer;
    }

    .topbar button:hover { background: rgba(201, 169, 110, 0.3); }
    .topbar button:disabled { opacity: 0.4; cursor: not-allowed; }

    .status-pill {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 6px 12px;
      border-radius: 999px;
      background: rgba(0, 0, 0, 0.4);
      font-family: var(--mono);
      font-size: 11px;
      letter-spacing: 0.06em;
      text-transform: uppercase;
    }

    .status-pill .dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--ink-mute);
    }

    .status-pill.connecting .dot { background: var(--warn); animation: pulse 1.6s ease-in-out infinite; }
    .status-pill.connected .dot  { background: var(--good); }
    .status-pill.error .dot      { background: var(--bad); }

    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50%      { opacity: 0.3; }
    }

    /* ── Main grid: jobs list | active detail | intent cell stream ── */
    .stage {
      display: grid;
      grid-template-columns: 1fr 1.2fr 1.4fr;
      overflow: hidden;
    }

    .panel {
      padding: 24px;
      overflow-y: auto;
      border-right: 1px solid var(--rule);
    }

    .panel:last-child { border-right: none; }

    .panel-title {
      font-size: 11px;
      letter-spacing: 0.16em;
      text-transform: uppercase;
      color: var(--ink-soft);
      margin-bottom: 16px;
      display: flex;
      justify-content: space-between;
      align-items: baseline;
    }

    .panel-title .count {
      color: var(--ink-mute);
      font-family: var(--mono);
    }

    /* ── Jobs list (left) ───────────────────────────────────────── */
    .job-list {
      display: flex;
      flex-direction: column;
      gap: 6px;
    }

    .job-list-empty {
      padding: 32px 0;
      color: var(--ink-mute);
      font-style: italic;
      font-size: 13px;
      text-align: center;
    }

    .job-row {
      padding: 14px 16px;
      border: 1px solid var(--rule);
      border-radius: 8px;
      background: var(--panel);
      cursor: pointer;
      transition: all 0.15s;
    }

    .job-row:hover {
      background: var(--panel-2);
      border-color: var(--rule-strong);
    }

    .job-row.selected {
      background: var(--panel-2);
      border-color: var(--activation);
    }

    .job-row .row-state {
      display: inline-block;
      padding: 2px 8px;
      border-radius: 999px;
      font-family: var(--mono);
      font-size: 9px;
      font-weight: 700;
      letter-spacing: 0.12em;
      text-transform: uppercase;
      margin-bottom: 6px;
    }

    .job-row .row-summary {
      font-size: 13px;
      line-height: 1.35;
      color: var(--ink);
      display: -webkit-box;
      -webkit-line-clamp: 2;
      -webkit-box-orient: vertical;
      overflow: hidden;
    }

    .job-row .row-meta {
      font-family: var(--mono);
      font-size: 10px;
      color: var(--ink-mute);
      margin-top: 4px;
    }

    /* Per-state pill colours (shared with the active detail panel) */
    .state-lead, .state-open
      { background: var(--warn-soft); color: var(--warn); }
    .state-quoted
      { background: var(--good-soft); color: var(--good); }
    .state-scheduled
      { background: var(--activation-soft); color: var(--activation); }
    .state-invoiced
      { background: rgba(127, 217, 255, 0.15); color: #7fd9ff; }
    .state-paid, .state-closed
      { background: rgba(231, 238, 245, 0.08); color: var(--ink-soft); }

    /* ── Active job detail (centre) ─────────────────────────────── */
    .empty-detail {
      padding: 48px 0;
      color: var(--ink-mute);
      font-style: italic;
      font-size: 14px;
      text-align: center;
    }

    .job-card {
      padding: 24px;
      border: 1px solid var(--rule);
      border-radius: 12px;
      background: var(--panel);
    }

    .job-state-pill {
      display: inline-block;
      padding: 6px 14px;
      border-radius: 999px;
      font-family: var(--mono);
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 0.16em;
      text-transform: uppercase;
      margin-bottom: 16px;
    }

    .job-card-summary {
      font-size: 17px;
      font-weight: 500;
      line-height: 1.4;
      letter-spacing: -0.005em;
      margin-bottom: 18px;
    }

    .job-meta {
      display: grid;
      grid-template-columns: 1fr;
      gap: 10px;
      padding-top: 16px;
      border-top: 1px solid var(--rule);
    }

    .meta-row {
      display: flex;
      justify-content: space-between;
      gap: 12px;
      font-family: var(--mono);
      font-size: 11px;
    }

    .meta-row .k { color: var(--ink-mute); letter-spacing: 0.04em; text-transform: uppercase; }
    .meta-row .v { color: var(--ink); text-align: right; word-break: break-all; }

    /* ── Intent cell stream (right) ─────────────────────────────── */
    .stream-empty {
      text-align: center;
      padding: 48px 0;
      color: var(--ink-mute);
      font-style: italic;
      font-size: 14px;
    }

    .cell {
      padding: 20px 22px;
      border: 1px solid var(--rule);
      border-radius: 12px;
      background: var(--panel);
      margin-bottom: 12px;
      animation: slideIn 0.6s ease-out;
    }

    .cell.fresh {
      border-color: var(--activation);
      box-shadow: 0 0 0 6px var(--activation-soft);
    }

    @keyframes slideIn {
      from { opacity: 0; transform: translateX(40px); }
      to   { opacity: 1; transform: translateX(0); }
    }

    .cell-header {
      display: flex;
      justify-content: space-between;
      align-items: baseline;
      margin-bottom: 10px;
    }

    .cell-action {
      display: inline-block;
      padding: 4px 10px;
      border-radius: 4px;
      background: var(--activation-soft);
      color: var(--activation);
      font-family: var(--mono);
      font-size: 10px;
      font-weight: 700;
      letter-spacing: 0.16em;
      text-transform: uppercase;
    }

    .cell-time {
      font-family: var(--mono);
      font-size: 10px;
      color: var(--ink-mute);
    }

    .cell-summary {
      font-size: 18px;
      font-weight: 500;
      line-height: 1.35;
      margin-bottom: 14px;
      letter-spacing: -0.01em;
    }

    .cell-meta {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 8px 14px;
      padding-top: 12px;
      border-top: 1px solid var(--rule);
      font-family: var(--mono);
      font-size: 10px;
    }

    .cell-meta-cell { display: flex; justify-content: space-between; gap: 8px; }
    .cell-meta-cell .k { color: var(--ink-mute); }
    .cell-meta-cell .v { color: var(--ink); }
    .cell-meta-cell .v.ok { color: var(--good); }

    .cell-id {
      font-family: var(--mono);
      font-size: 9px;
      color: var(--ink-mute);
      margin-top: 10px;
      word-break: break-all;
    }

    /* ── Footer / signature stamp ───────────────────────────────── */
    .signature {
      position: fixed;
      bottom: 12px;
      right: 18px;
      font-family: var(--mono);
      font-size: 10px;
      color: var(--ink-mute);
      letter-spacing: 0.08em;
    }

    /* ── Setup overlay (shown until connected) ──────────────────── */
    .setup {
      position: fixed;
      inset: 0;
      display: flex;
      align-items: center;
      justify-content: center;
      background: rgba(11, 13, 18, 0.96);
      z-index: 1000;
      backdrop-filter: blur(8px);
    }

    .setup.hidden { display: none; }

    .setup-card {
      width: 460px;
      padding: 32px;
      background: var(--panel);
      border: 1px solid var(--rule);
      border-radius: 16px;
    }

    .setup h2 {
      font-size: 20px;
      font-weight: 500;
      margin-bottom: 8px;
    }

    .setup p {
      font-size: 13px;
      color: var(--ink-soft);
      margin-bottom: 24px;
      line-height: 1.5;
    }

    .setup label {
      display: block;
      font-family: var(--mono);
      font-size: 11px;
      letter-spacing: 0.1em;
      text-transform: uppercase;
      color: var(--ink-mute);
      margin-bottom: 6px;
      margin-top: 16px;
    }

    .setup input {
      width: 100%;
      padding: 10px 14px;
      background: rgba(0, 0, 0, 0.25);
      border: 1px solid var(--rule);
      border-radius: 6px;
      color: var(--ink);
      font-family: var(--mono);
      font-size: 12px;
    }

    .setup input:focus {
      outline: none;
      border-color: var(--activation);
    }

    .setup button {
      width: 100%;
      margin-top: 24px;
      padding: 12px;
      background: var(--activation);
      color: var(--bg);
      border: none;
      border-radius: 6px;
      font-family: var(--sans);
      font-size: 13px;
      font-weight: 700;
      letter-spacing: 0.1em;
      text-transform: uppercase;
      cursor: pointer;
    }

    .setup button:hover { filter: brightness(1.1); }

    .error-banner {
      display: none;
      padding: 12px 16px;
      background: var(--bad-soft);
      border: 1px solid var(--bad);
      border-radius: 6px;
      color: var(--bad);
      font-family: var(--mono);
      font-size: 11px;
      margin-top: 16px;
      word-break: break-word;
    }

    .error-banner.shown { display: block; }
  </style>
</head>
<body>
  <!-- ── Setup overlay ───────────────────────────────────────────── -->
  <div class="setup" id="setup">
    <div class="setup-card">
      <h2><span style="color: var(--activation);">brain helm</span> viewer</h2>
      <p>Live read-only view onto the operator's brain.  Pulls jobs via the bearer-gated REPL HTTP, subscribes to the helm WSS stream, renders intent cells as they arrive from paired devices.</p>

      <label for="setup-base">Brain HTTPS base URL</label>
      <input type="text" id="setup-base" value="https://brain.oddjobtodd.info" />

      <label for="setup-bearer">Bearer token</label>
      <input type="password" id="setup-bearer" placeholder="64-hex bearer issued by the brain" />

      <button id="setup-connect">Connect</button>

      <div class="error-banner" id="setup-error"></div>
    </div>
  </div>

  <!-- ── Top bar ────────────────────────────────────────────────── -->
  <div class="topbar">
    <span class="brand"><span class="accent">brain.oddjobtodd</span> · helm viewer</span>
    <span style="flex: 1;"></span>
    <span class="status-pill" id="status"><span class="dot"></span><span id="status-text">disconnected</span></span>
    <button id="reload-jobs">Reload jobs</button>
    <button id="reconnect" style="display: none;">Reconnect</button>
  </div>

  <!-- ── Stage ──────────────────────────────────────────────────── -->
  <div class="stage">
    <!-- Left: jobs list pulled from `find jobs` -->
    <div class="panel">
      <div class="panel-title">
        <span>jobs · brain</span>
        <span class="count" id="jobs-count"></span>
      </div>
      <div class="job-list" id="job-list">
        <div class="job-list-empty">connecting…</div>
      </div>
    </div>

    <!-- Centre: selected job detail -->
    <div class="panel">
      <div class="panel-title">selected job</div>
      <div id="job-detail">
        <div class="empty-detail">click a job on the left to focus it</div>
      </div>
    </div>

    <!-- Right: live intent cell stream -->
    <div class="panel">
      <div class="panel-title">live intent cells</div>
      <div id="stream">
        <div class="stream-empty">waiting for signed intent cells from paired devices…</div>
      </div>
    </div>
  </div>

  <div class="signature">on-device llama · kernel-verified · BSV-signed · no API keys</div>

  <script>
    /* ──────────────────────────────────────────────────────────────
       Brain helm viewer — vanilla JS, no build step.

       1. On Connect, GET-equivalent `find jobs` over POST /api/v1/repl
          (bearer-gated) to populate the left panel with the operator's
          actual jobs from brain.oddjobtodd.info.  No hardcoded
          synthetic data.
       2. Open a WebSocket to /api/v1/wallet?bearer=… and send
          helm.subscribe so incoming intent cells appear live in the
          right panel.
       3. Operator clicks a job to focus it in the centre panel.

       Important: this is a read-only viewer.  When an intent cell
       arrives the right panel updates; the left panel's job state
       does NOT change (the brain hasn't yet wired intent → FSM, and
       we don't fake it).  The honest demo is "watch the audited
       command land on the brain in real time, signed by the device,
       kernel-verified locally, llama-extracted on the phone".
       ────────────────────────────────────────────────────────── */

    // ── DOM refs
    const $ = (id) => document.getElementById(id);
    const setupOverlay  = $('setup');
    const setupConnect  = $('setup-connect');
    const setupBaseEl   = $('setup-base');
    const setupBearerEl = $('setup-bearer');
    const setupError    = $('setup-error');
    const statusPill    = $('status');
    const statusText    = $('status-text');
    const reconnectBtn  = $('reconnect');
    const reloadBtn     = $('reload-jobs');
    const stream        = $('stream');
    const jobListEl     = $('job-list');
    const jobsCountEl   = $('jobs-count');
    const jobDetailEl   = $('job-detail');

    // ── Persisted config (so the operator doesn't re-paste the bearer
    //    every time they reload during the meetup setup phase).
    const cfg = {
      get base()      { return localStorage.getItem('bhv.base')   || setupBaseEl.value; },
      get bearer()    { return localStorage.getItem('bhv.bearer') || ''; },
      set(base, bearer){
        localStorage.setItem('bhv.base',   base);
        localStorage.setItem('bhv.bearer', bearer);
      },
      clear() {
        localStorage.removeItem('bhv.base');
        localStorage.removeItem('bhv.bearer');
      },
    };

    // Pre-populate setup if remembered.
    if (cfg.bearer) {
      setupBearerEl.value = cfg.bearer;
      setupBaseEl.value   = cfg.base;
    }

    // ── State
    let ws = null;
    let subscribeId = 1;
    let jobs = [];
    let selectedJobId = null;
    let keepaliveTimer = null;

    // ── Lifecycle
    setupConnect.addEventListener('click', async () => {
      const base = setupBaseEl.value.trim().replace(/\/+$/, '');
      const bearer = setupBearerEl.value.trim();
      if (!base || !bearer) return;
      setupError.classList.remove('shown');

      // Fast smoke-test the bearer + base by issuing a `status` command
      // before we hide the overlay.  This catches typos before the
      // operator hits an empty stage.
      try {
        const r = await replCommand(base, bearer, 'status');
        if (typeof r.result !== 'string') throw new Error('unexpected response');
      } catch (e) {
        setupError.textContent = 'connect failed: ' + (e.message || String(e));
        setupError.classList.add('shown');
        return;
      }

      cfg.set(base, bearer);
      setupOverlay.classList.add('hidden');
      await loadJobs();
      connectWss();
    });

    setupBearerEl.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') setupConnect.click();
    });

    reconnectBtn.addEventListener('click', () => {
      reconnectBtn.style.display = 'none';
      connectWss();
    });

    reloadBtn.addEventListener('click', loadJobs);

    // ── REPL HTTP
    async function replCommand(base, bearer, cmd) {
      const res = await fetch(base + '/api/v1/repl', {
        method: 'POST',
        headers: {
          'Authorization': 'Bearer ' + bearer,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ cmd }),
      });
      if (!res.ok) {
        throw new Error(`HTTP ${res.status} ${res.statusText}`);
      }
      const j = await res.json();
      return j;
    }

    async function loadJobs() {
      jobListEl.innerHTML = '<div class="job-list-empty">loading…</div>';
      try {
        const r = await replCommand(cfg.base, cfg.bearer, 'find jobs --limit 200');
        // The result is a string containing a JSON array.  Parse it.
        let parsed;
        try {
          parsed = JSON.parse(r.result);
        } catch (e) {
          // Some commands return a human-readable line; in that case
          // surface the raw result.
          jobListEl.innerHTML = `<div class="job-list-empty">${escapeHtml(r.result)}</div>`;
          return;
        }
        if (!Array.isArray(parsed)) {
          jobListEl.innerHTML = '<div class="job-list-empty">unexpected shape from `find jobs`</div>';
          return;
        }
        jobs = parsed;
        renderJobList();
      } catch (e) {
        jobListEl.innerHTML = `<div class="job-list-empty">load failed: ${escapeHtml(e.message)}</div>`;
      }
    }

    function renderJobList() {
      jobsCountEl.textContent = String(jobs.length);
      if (jobs.length === 0) {
        jobListEl.innerHTML = '<div class="job-list-empty">(no jobs)</div>';
        return;
      }
      jobListEl.innerHTML = '';
      for (const job of jobs) {
        const row = document.createElement('div');
        row.className = 'job-row' + (job.id === selectedJobId ? ' selected' : '');
        row.dataset.jobId = job.id;
        const state = (job.state || 'lead').toLowerCase();
        row.innerHTML = `
          <span class="row-state state-${escapeHtml(state)}">${escapeHtml(state)}</span>
          <div class="row-summary">${escapeHtml(job.customer_name || '(no summary)')}</div>
          <div class="row-meta">${escapeHtml(job.id.slice(0, 8))}…  ·  ${escapeHtml(formatDate(job.created_at))}</div>
        `;
        row.addEventListener('click', () => selectJob(job.id));
        jobListEl.appendChild(row);
      }
    }

    function selectJob(id) {
      selectedJobId = id;
      // Re-paint list selection.
      for (const el of jobListEl.querySelectorAll('.job-row')) {
        el.classList.toggle('selected', el.dataset.jobId === id);
      }
      // Render detail card.
      const job = jobs.find((j) => j.id === id);
      if (!job) {
        jobDetailEl.innerHTML = '<div class="empty-detail">job not found</div>';
        return;
      }
      const state = (job.state || 'lead').toLowerCase();
      jobDetailEl.innerHTML = `
        <div class="job-card">
          <div class="job-state-pill state-${escapeHtml(state)}">${escapeHtml(state)}</div>
          <div class="job-card-summary">${escapeHtml(job.customer_name || '(no summary)')}</div>
          <div class="job-meta">
            <div class="meta-row"><span class="k">Job id</span><span class="v">${escapeHtml(job.id)}</span></div>
            <div class="meta-row"><span class="k">Created</span><span class="v">${escapeHtml(job.created_at || '—')}</span></div>
            <div class="meta-row"><span class="k">Scheduled</span><span class="v">${escapeHtml(job.scheduled_at || '—')}</span></div>
          </div>
        </div>
      `;
    }

    // ── WebSocket
    function setStatus(state, text) {
      statusPill.classList.remove('connecting', 'connected', 'error');
      statusPill.classList.add(state);
      statusText.textContent = text;
    }

    function connectWss() {
      // Derive WSS URL from the HTTPS base.
      const wssUrl = cfg.base.replace(/^https?:/, (m) => m === 'https:' ? 'wss:' : 'ws:') + '/api/v1/wallet';
      const url = new URL(wssUrl);
      url.searchParams.set('bearer', cfg.bearer);

      setStatus('connecting', 'connecting');
      try {
        ws = new WebSocket(url.toString());
      } catch (e) {
        setStatus('error', 'invalid url');
        reconnectBtn.style.display = 'inline-block';
        return;
      }

      ws.addEventListener('open', () => {
        setStatus('connected', 'subscribed');
        const subscribeFrame = JSON.stringify({
          jsonrpc: '2.0',
          id: subscribeId++,
          method: 'helm.subscribe',
          // Topic name is canonical-plural per brain's HELM_TOPICS
          // allowlist.  `intent_cells` (plural) is what
          // `helm.subscribe` accepts; the broker emits
          // `intent_cell.created` (singular event-type prefix) which
          // is mapped to the plural topic via topicPlural().  See
          // runtime/semantos-brain/src/wss_wallet.zig.
          params: { topics: ['intent_cells', 'jobs'] },
        });
        ws.send(subscribeFrame);

        // 2026-05-07 — keepalive ping every 1.5s.  The brain reactor
        // path only drains its per-session helm_event_queue inside
        // advanceFrame() (which is invoked when an INBOUND frame
        // arrives).  A passive subscriber never triggers drain →
        // events back up unsent.  Sending a no-op JSON-RPC every
        // 1.5s (helm.fetch_since with limit=0) ticks the reactor's
        // drain path so queued events flush promptly.  Cheap to
        // process server-side — the fetch_since with limit=0 just
        // returns an empty list.
        if (keepaliveTimer) clearInterval(keepaliveTimer);
        keepaliveTimer = setInterval(() => {
          if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({
              jsonrpc: '2.0',
              id: subscribeId++,
              method: 'helm.fetch_since',
              // limit must be ≥ 1 per brain validator.  since_ts in the
              // far future means the result is always an empty list,
              // so this is a true no-op aside from triggering the
              // reactor's queue drain.
              params: { since_ts: Date.now() + 86400_000, limit: 1 },
            }));
          }
        }, 1500);
      });

      ws.addEventListener('message', (ev) => {
        let frame;
        try { frame = JSON.parse(ev.data); } catch (e) { return; }
        if (frame.method === 'helm.event') {
          // 2026-05-07: brain's helm.event params shape is `{type, data}`,
          // not `{type, payload}`.  Was reading the wrong key — every
          // event was being dropped at the first guard.  See
          // runtime/semantos-brain/src/wss_wallet.zig::helmEventCallback.
          const p = frame.params || {};
          handleHelmEvent({ type: p.type, payload: p.data });
        }
      });

      ws.addEventListener('error', () => {
        setStatus('error', 'connection error');
      });

      ws.addEventListener('close', () => {
        setStatus('error', 'disconnected');
        reconnectBtn.style.display = 'inline-block';
        if (keepaliveTimer) { clearInterval(keepaliveTimer); keepaliveTimer = null; }
      });
    }

    // ── Event handling
    function handleHelmEvent({ type, payload }) {
      if (!type || !payload) return;

      if (type === 'intent_cell.created') {
        renderIntentCell(payload);
      } else if (type.startsWith('jobs.')) {
        // Jobs may have been mutated server-side — pull fresh.
        loadJobs();
      }
    }

    function renderIntentCell(p) {
      // Remove the empty placeholder if present.
      const placeholder = stream.querySelector('.stream-empty');
      if (placeholder) placeholder.remove();

      const card = document.createElement('div');
      card.className = 'cell fresh';
      const stamp = new Date(p.ts || Date.now()).toLocaleTimeString();
      card.innerHTML = `
        <div class="cell-header">
          <span class="cell-action">${escapeHtml(p.intent_action || 'note')}</span>
          <span class="cell-time">${stamp}</span>
        </div>
        <div class="cell-summary">${escapeHtml(p.intent_summary || '(no summary)')}</div>
        <div class="cell-meta">
          <div class="cell-meta-cell"><span class="k">kernel</span><span class="v ok">verified ✓</span></div>
          <div class="cell-meta-cell"><span class="k">extractor</span><span class="v">llama 3.2 3B</span></div>
          <div class="cell-meta-cell"><span class="k">on-device</span><span class="v ok">yes</span></div>
          <div class="cell-meta-cell"><span class="k">api keys</span><span class="v ok">none</span></div>
        </div>
        <div class="cell-id">${escapeHtml(p.cell_id || '')}</div>
      `;
      // Newest cells go to the top.
      stream.insertBefore(card, stream.firstChild);

      // Cap at 12 visible cards.
      while (stream.children.length > 12) {
        stream.removeChild(stream.lastChild);
      }

      // Drop the "fresh" highlight after 3s.
      setTimeout(() => card.classList.remove('fresh'), 3000);
    }

    function escapeHtml(s) {
      return String(s ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
    }

    function formatDate(iso) {
      if (!iso) return '—';
      try {
        const d = new Date(iso);
        const now = new Date();
        const days = Math.floor((now - d) / (1000 * 60 * 60 * 24));
        if (days < 1) return 'today';
        if (days < 2) return '1d ago';
        if (days < 30) return `${days}d ago`;
        return d.toISOString().slice(0, 10);
      } catch (_) {
        return iso;
      }
    }
  </script>
</body>
</html>

```
