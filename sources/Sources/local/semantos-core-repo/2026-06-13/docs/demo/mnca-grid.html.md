---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/demo/mnca-grid.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.745993+00:00
---

# docs/demo/mnca-grid.html

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>MNCA grid — singularity demo</title>
<style>
  :root { color-scheme: dark; }
  body {
    margin: 0; background: #0a0a0a; color: #d8e0e4;
    font: 14px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace;
    display: flex; flex-direction: column; align-items: center; gap: 16px; padding: 24px;
  }
  h1 { font-size: 16px; font-weight: 600; margin: 0; letter-spacing: 0.02em; }
  .sub { color: #6b7a82; max-width: 540px; text-align: center; }
  .sub a { color: #2ec4b6; }
  canvas { border: 1px solid #1c2428; border-radius: 4px; image-rendering: pixelated; }
  #tick { color: #2ec4b6; font-size: 13px; }
  #bridge-status { font-size: 12px; color: #6b7a82; }
  .controls { display: flex; gap: 8px; }
  button {
    background: #14201f; color: #2ec4b6; border: 1px solid #2ec4b6;
    border-radius: 4px; padding: 6px 14px; font: inherit; cursor: pointer;
  }
  button:hover { background: #1c2c2a; }
  #anchor-panel {
    border: 1px solid #1c2428; border-radius: 4px; padding: 12px 16px;
    max-width: 540px; width: 100%; font-size: 12px; color: #6b7a82;
  }
  #anchor-panel h2 { font-size: 12px; margin: 0 0 6px; color: #9aacb4; font-weight: 600; }
  #anchor-panel a  { color: #2ec4b6; }
  #anchor-panel .anchor-row { display: flex; gap: 8px; align-items: baseline; flex-wrap: wrap; }
</style>
</head>
<body>
  <h1>MNCA grid — the compute layer, live</h1>
  <p class="sub">
    Distributed MNCA running across the Pi mesh — each node owns a tile, steps it,
    and multicasts the result via IPv6. The browser subscribes live via SSE
    (<code>mesh-bridge.ts</code>). Falls back to a local simulation if the bridge is
    unreachable. First cell on mainnet:
    <a href="https://whatsonchain.com/tx/a5277713454f17d746283f41158f39b26ac14debd11f7a719f866f872e23383c">a5277713…b2a78c</a>.
  </p>
  <div id="tick">tick 0</div>
  <div id="bridge-status">checking bridge…</div>
  <canvas id="grid"></canvas>
  <div class="controls">
    <button id="play">play / pause</button>
    <button id="step">step</button>
    <button id="reseed">reseed</button>
  </div>

  <!-- On-chain snapshot anchor panel (dry-run preview from mesh-snapshot-anchor.ts) -->
  <div id="anchor-panel">
    <h2>BSV snapshot anchor (dry-run)</h2>
    <div id="anchor-content" class="anchor-row">checking anchor service…</div>
  </div>

  <script type="module" src="./mnca-grid.js"></script>

  <!-- Anchor preview polling (separate from grid render loop) -->
  <script type="module">
    const ANCHOR_URL = 'http://localhost:4401/anchor-preview';
    const el = document.getElementById('anchor-content');
    if (!el) throw new Error('no anchor-content');

    async function pollAnchor() {
      try {
        const res = await fetch(ANCHOR_URL, { signal: AbortSignal.timeout(2000) });
        const d = await res.json();
        if (!d.ok) {
          el.textContent = d.message ?? 'anchor service not running';
          return;
        }
        const short = d.txid ? `${d.txid.slice(0,8)}…${d.txid.slice(-6)}` : '';
        el.innerHTML =
          `<span style="color:#2ec4b6">● DRY-RUN</span> &nbsp;` +
          `tick&nbsp;${d.latestTick} &nbsp;·&nbsp; ${d.numTiles}&nbsp;tile${d.numTiles!==1?'s':''} &nbsp;·&nbsp; ` +
          `built&nbsp;${new Date(d.builtAt).toLocaleTimeString()} &nbsp;·&nbsp; ` +
          (d.txid ? `<a href="${d.wocUrl}" target="_blank" title="${d.txid}">${short}</a> (WoC — live after broadcast)` : '') +
          ` &nbsp;<span style="color:#6b7a82">— operator broadcasts via wallet.html</span>`;
      } catch {
        el.textContent = 'anchor service unreachable (start mesh-snapshot-anchor.ts)';
      }
    }

    pollAnchor();
    setInterval(pollAnchor, 10_000);
  </script>
</body>
</html>

```
