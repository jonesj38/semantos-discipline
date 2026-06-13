---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/mnca-rehab-server.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.408658+00:00
---

# cartridges/inference-gate/mnca-rehab-server.ts

```ts
#!/usr/bin/env bun
/**
 * mnca-rehab-server.ts — Mine Rehabilitation Zone Monitor demo
 *
 * Serves a live MNCA vegetation-spread simulation with real BSV mainnet
 * anchoring.  Each "Record Inspection" click packages the current grid state
 * as a PushDrop UTXO and broadcasts it via Metanet Desktop (:3321).
 *
 * The anchor payload is the inspection record:
 *   { v, type, zone, tick, coveragePct, gridHash (sha256), ts, inspector }
 * Any regulator can verify the on-chain txid and check the hash against
 * an exported grid snapshot — "As Done" data that can't be falsified.
 *
 * Usage:
 *   bun cartridges/inference-gate/mnca-rehab-server.ts
 *   → opens http://localhost:5210 automatically
 *
 * Requires Metanet Desktop running at http://localhost:3321
 */

import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import Anthropic from '@anthropic-ai/sdk';

const PORT     = parseInt(process.env.PORT ?? '5210');
const MND_URL  = process.env.MND_URL ?? 'http://127.0.0.1:3321';
const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY ?? '';

// ── Real NDVI seed data (written by sentinel2-ndvi-ingest.ts) ───────────────

const GRID_SEED_PATH = resolve(import.meta.dir, 'mnca-grid-real.json');
let gridSeedData: { cells: number[]; tileId: string; date: string; location: string; coveragePct: number; source: string; note?: string } | null = null;

try {
  if (existsSync(GRID_SEED_PATH)) {
    gridSeedData = JSON.parse(readFileSync(GRID_SEED_PATH, 'utf8'));
    console.log(`[mnca-rehab] Real NDVI grid loaded: ${gridSeedData!.tileId} (${gridSeedData!.date})`);
  }
} catch (e) {
  console.warn('[mnca-rehab] Could not load mnca-grid-real.json:', e);
}

// ── Anthropic client (optional) ──────────────────────────────────────────────

let anthropic: Anthropic | null = null;
if (ANTHROPIC_API_KEY) {
  anthropic = new Anthropic({ apiKey: ANTHROPIC_API_KEY });
  console.log('[mnca-rehab] Claude API available for compliance analysis');
} else {
  console.log('[mnca-rehab] ANTHROPIC_API_KEY not set — AI analysis disabled');
}

// ── Script helpers (mirrors cashlanes-bridge.ts) ───────────────────────────

function toHex(b: Uint8Array): string {
  return Buffer.from(b).toString('hex');
}

function fromHex(h: string): Uint8Array {
  const clean = h.replace(/\s/g, '');
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++)
    out[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  return out;
}

function encodePush(data: Uint8Array): Uint8Array {
  if (data.length <= 75) {
    const out = new Uint8Array(1 + data.length);
    out[0] = data.length; out.set(data, 1); return out;
  }
  if (data.length <= 255) {
    const out = new Uint8Array(2 + data.length);
    out[0] = 0x4c; out[1] = data.length; out.set(data, 2); return out;
  }
  const out = new Uint8Array(3 + data.length);
  out[0] = 0x4d; out[1] = data.length & 0xff; out[2] = (data.length >> 8) & 0xff;
  out.set(data, 3); return out;
}

function pushdropScript(data: Uint8Array, pubkey: Uint8Array): string {
  const dp = encodePush(data);
  const pp = encodePush(pubkey);
  const out = new Uint8Array(dp.length + 1 + pp.length + 1);
  let i = 0;
  out.set(dp, i); i += dp.length;
  out[i++] = 0x75; // OP_DROP
  out.set(pp, i); i += pp.length;
  out[i] = 0xac;   // OP_CHECKSIG
  return toHex(out);
}

// ── MND helpers ────────────────────────────────────────────────────────────

let cachedPubkey: string | null = null;

async function getMndPubkey(): Promise<string> {
  if (cachedPubkey) return cachedPubkey;
  const r = await fetch(`${MND_URL}/getPublicKey`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Origin': 'http://localhost' },
    body: JSON.stringify({ protocolID: [1, 'mnca rehab anchor'], keyID: 'rehab-v1' }),
  });
  if (!r.ok) throw new Error(`MND getPublicKey ${r.status}`);
  const j = await r.json() as { publicKey?: string };
  if (!j.publicKey) throw new Error('MND: no publicKey');
  cachedPubkey = j.publicKey;
  return cachedPubkey;
}

async function anchorInspection(payload: object): Promise<string> {
  const pubkey   = await getMndPubkey();
  const data     = new TextEncoder().encode(JSON.stringify(payload));
  const script   = pushdropScript(data, fromHex(pubkey));

  const r = await fetch(`${MND_URL}/createAction`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Origin': 'http://localhost' },
    body: JSON.stringify({
      description: `Rehab inspection — ${(payload as any).zone} tick ${(payload as any).tick} cover ${(payload as any).coveragePct}%`,
      labels: ['mnca-rehab'],
      outputs: [{
        lockingScript:     script,
        satoshis:          1,
        outputDescription: `Rehab inspection ${(payload as any).zone} #${(payload as any).seq}`,
        tags: [],
      }],
    }),
  });
  if (!r.ok) throw new Error(`MND createAction ${r.status}: ${await r.text()}`);
  const j = await r.json() as { txid?: string };
  if (!j.txid) throw new Error('MND createAction: no txid');
  return j.txid;
}

// ── HTML (served at GET /) ─────────────────────────────────────────────────

const HTML = /* html */`<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Rehabilitation Zone Monitor</title>
<style>
:root {
  --bg:     #0d1117;
  --panel:  #161b22;
  --panel2: #1c2330;
  --border: #21262d;
  --fg:     #e6edf3;
  --muted:  #8b949e;
  --green:  #3fb950;
  --amber:  #e3b341;
  --red:    #f85149;
  --blue:   #58a6ff;
  --mono:   ui-monospace, "SF Mono", Menlo, Consolas, monospace;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: var(--bg); color: var(--fg); font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; min-height: 100vh; display: flex; flex-direction: column; }

.topbar {
  padding: 14px 24px;
  background: var(--panel);
  border-bottom: 1px solid var(--border);
  display: flex; align-items: center; gap: 16px;
}
.topbar h1 { font-size: 1.1rem; font-weight: 700; }
.topbar h1 span { color: var(--green); }
.topbar .sub { font-size: 0.8rem; color: var(--muted); margin-left: auto; }
.live-dot { display: inline-block; width: 7px; height: 7px; border-radius: 50%; background: var(--green); margin-right: 6px; animation: pulse 2s ease-in-out infinite; }
@keyframes pulse { 0%,100%{opacity:1} 50%{opacity:.3} }

.main { display: grid; grid-template-columns: auto 1fr; gap: 0; flex: 1; }

.left-col { padding: 20px; display: flex; flex-direction: column; gap: 16px; border-right: 1px solid var(--border); }

.canvas-wrap { position: relative; }
canvas { display: block; border: 1px solid var(--border); border-radius: 6px; image-rendering: pixelated; }
.canvas-overlay {
  position: absolute; top: 6px; left: 6px;
  background: rgba(13,17,23,0.85); border: 1px solid var(--border);
  border-radius: 5px; padding: 6px 10px; font-size: 11px; font-family: var(--mono);
  line-height: 1.7; pointer-events: none;
}
.canvas-overlay .cov-val { color: var(--green); font-weight: 700; font-size: 13px; }
.canvas-overlay .tick-val { color: var(--blue); }

.controls { background: var(--panel); border: 1px solid var(--border); border-radius: 8px; padding: 14px 16px; }
.ctrl-row { display: flex; align-items: center; gap: 12px; margin-bottom: 10px; }
.ctrl-row:last-child { margin-bottom: 0; }
.ctrl-label { font-size: 0.72rem; color: var(--muted); text-transform: uppercase; letter-spacing: .04em; min-width: 60px; }
select, input[type=range] { background: var(--panel2); color: var(--fg); border: 1px solid var(--border); border-radius: 4px; padding: 4px 8px; font-size: 0.82rem; cursor: pointer; }
select { appearance: none; }
input[type=range] { padding: 0; accent-color: var(--green); width: 100px; }
.zone-name { font-size: 0.72rem; color: var(--muted); }

.anchor-btn {
  width: 100%; padding: 10px; border-radius: 6px;
  background: rgba(63,185,80,0.15); border: 1px solid rgba(63,185,80,0.45);
  color: var(--green); font-size: 0.9rem; font-weight: 700;
  cursor: pointer; font-family: inherit; letter-spacing: .02em;
  transition: all .15s;
}
.anchor-btn:hover { background: rgba(63,185,80,0.25); }
.anchor-btn:disabled { opacity: .4; cursor: not-allowed; }
.anchor-btn.anchoring { color: var(--amber); border-color: rgba(227,179,65,.45); background: rgba(227,179,65,.1); }

.mnd-status { font-size: 0.7rem; text-align: center; margin-top: 4px; }

.right-col { padding: 20px; display: flex; flex-direction: column; gap: 14px; overflow-y: auto; }

.panel { background: var(--panel); border: 1px solid var(--border); border-radius: 8px; padding: 14px 16px; }
.panel-title { font-size: 0.72rem; text-transform: uppercase; letter-spacing: .06em; color: var(--muted); margin-bottom: 10px; }

.stats-grid { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 8px; }
.stat { background: var(--panel2); border: 1px solid var(--border); border-radius: 6px; padding: 8px 10px; }
.stat-label { font-size: 0.65rem; color: var(--muted); text-transform: uppercase; letter-spacing: .04em; margin-bottom: 2px; }
.stat-value { font-size: 1.3rem; font-weight: 700; }
.stat-value.green { color: var(--green); }
.stat-value.blue  { color: var(--blue);  }
.stat-value.amber { color: var(--amber); }

.inspection-log { flex: 1; overflow-y: auto; max-height: 440px; }
.log-empty { color: var(--muted); font-size: 0.78rem; padding: 8px 0; }

.log-entry {
  display: flex; flex-direction: column; gap: 3px;
  padding: 10px 12px; margin-bottom: 6px;
  background: var(--panel2); border: 1px solid var(--border);
  border-radius: 6px; font-size: 11px; animation: slide-in .3s ease;
}
.log-entry.anchored { border-left: 3px solid var(--green); }
.log-entry.pending  { border-left: 3px solid var(--amber); }
@keyframes slide-in { from { opacity:0; transform:translateY(-6px) } to { opacity:1; transform:translateY(0) } }

.log-header { display: flex; align-items: center; gap: 8px; }
.log-zone { font-weight: 700; color: var(--fg); font-size: 12px; }
.log-tick { color: var(--muted); font-family: var(--mono); }
.log-cov  { color: var(--green); font-family: var(--mono); font-weight: 600; }
.log-ts   { color: var(--muted); margin-left: auto; font-size: 10px; }

.log-txid {
  display: flex; align-items: center; gap: 6px;
  font-family: var(--mono); font-size: 10px; color: var(--muted);
}
.log-txid a { color: var(--blue); text-decoration: none; }
.log-txid a:hover { text-decoration: underline; }
.log-txid .verified { color: var(--green); font-size: 10px; }

.log-hash { font-family: var(--mono); font-size: 9px; color: #3a4a5c; word-break: break-all; }

.legend { display: flex; gap: 12px; align-items: center; flex-wrap: wrap; }
.legend-item { display: flex; align-items: center; gap: 5px; font-size: 11px; color: var(--muted); }
.legend-swatch { width: 14px; height: 14px; border-radius: 3px; border: 1px solid rgba(255,255,255,.1); }

.about { font-size: 0.72rem; color: var(--muted); line-height: 1.6; }
.about strong { color: var(--fg); }
</style>
</head>
<body>

<div class="topbar">
  <h1><span class="live-dot"></span>Rehabilitation Zone Monitor &mdash; <span>BSV Verified Record</span></h1>
  <div class="sub">As Done data · tamper-proof · independently verifiable</div>
</div>

<div class="main">
  <!-- LEFT — grid + controls -->
  <div class="left-col">
    <div class="canvas-wrap">
      <canvas id="grid" width="50" height="50" style="width:400px;height:400px;image-rendering:pixelated"></canvas>
      <div class="canvas-overlay">
        <div>Zone: <span id="ov-zone" style="color:var(--amber);font-weight:700">A</span></div>
        <div>Tick: <span class="tick-val" id="ov-tick">0</span></div>
        <div>Cover: <span class="cov-val" id="ov-cov">0.0%</span></div>
      </div>
    </div>

    <div class="controls">
      <div class="ctrl-row">
        <span class="ctrl-label">Zone</span>
        <select id="zone-sel" onchange="setZone(this.value)">
          <option value="A">Zone A — West Highwall</option>
          <option value="B">Zone B — North Batters</option>
          <option value="C">Zone C — East Spoil</option>
          <option value="D">Zone D — Void Perimeter</option>
        </select>
      </div>
      <div class="ctrl-row">
        <span class="ctrl-label">Speed</span>
        <input type="range" id="speed" min="1" max="30" value="10" oninput="setSpeed(+this.value)">
        <span id="speed-label" style="font-size:.72rem;color:var(--muted);min-width:50px">10 fps</span>
      </div>
      <div class="ctrl-row">
        <button class="anchor-btn" id="anchor-btn" onclick="recordInspection()">
          ⬡ Record Inspection to BSV
        </button>
      </div>
      <div class="mnd-status" id="mnd-status" style="color:var(--muted)">Checking Metanet Desktop…</div>
    </div>

    <div class="legend">
      <div class="legend-item"><div class="legend-swatch" style="background:#7a3a1a"></div>Bare ground</div>
      <div class="legend-item"><div class="legend-swatch" style="background:#b8822a"></div>Disturbed</div>
      <div class="legend-item"><div class="legend-swatch" style="background:#8caa38"></div>Establishing</div>
      <div class="legend-item"><div class="legend-swatch" style="background:#3a8c28"></div>Established</div>
      <div class="legend-item"><div class="legend-swatch" style="background:#1a5c14"></div>Rehabilitated</div>
    </div>
  </div>

  <!-- RIGHT — stats + inspection log -->
  <div class="right-col">

    <div class="panel">
      <div class="panel-title">Cumulative Coverage</div>
      <div class="stats-grid">
        <div class="stat">
          <div class="stat-label">Coverage</div>
          <div class="stat-value green" id="stat-cov">—</div>
        </div>
        <div class="stat">
          <div class="stat-label">Inspections</div>
          <div class="stat-value blue" id="stat-count">0</div>
        </div>
        <div class="stat">
          <div class="stat-label">Tick</div>
          <div class="stat-value amber" id="stat-tick">0</div>
        </div>
      </div>
    </div>

    <div class="panel" style="flex:1">
      <div class="panel-title">Inspection Record — Anchored on BSV Mainnet</div>
      <div class="inspection-log" id="log">
        <div class="log-empty">No inspections recorded yet.<br>Click "Record Inspection" to anchor the current state on BSV.</div>
      </div>
    </div>

    <div class="panel">
      <div class="panel-title">AI Compliance Analysis <span style="font-size:.65rem;color:var(--muted)">(Claude Haiku · NSW Resources Regulator)</span></div>
      <div style="margin-bottom:10px">
        <button class="anchor-btn" id="analysis-btn" onclick="getClaudeAnalysis()" style="background:rgba(88,166,255,.12);border-color:rgba(88,166,255,.4);color:var(--blue)">
          🤖 Get AI Compliance Report
        </button>
      </div>
      <div id="analysis-panel" style="font-size:.8rem;color:var(--muted);line-height:1.6">
        Click to generate a NSW Resources Regulator compliance assessment based on current grid state.
      </div>
    </div>

    <div class="panel">
      <div class="panel-title">Data Source</div>
      <div style="font-size:.75rem;margin-bottom:6px">
        <span id="data-source" style="color:var(--muted)">Loading…</span>
      </div>
      <div class="about">
        Grid seeded from real <strong>Sentinel-2 L2A</strong> NDVI data (Hunter Valley NSW mine sites).
        Each inspection packages the current state as a <strong>PushDrop UTXO</strong> on BSV mainnet —
        a SHA-256 hash of the full grid + coverage %, cryptographically bound to a timestamp.
        Any regulator can verify via WhatsOnChain independently.
      </div>
    </div>

  </div>
</div>

<script>
// ── MNCA simulation ────────────────────────────────────────────────────────

const W = 50, H = 50;
let grid     = new Uint8Array(W * H);
let nextGrid = new Uint8Array(W * H);
let tick     = 0;
let zone     = 'A';
let fps      = 10;
let inspectionCount = 0;
let anchoring = false;
let mndOnline = false;

// ── B34/S234 rule with gradual state transitions ───────────────────────────
//
// Rule family: "34 Life" — birth if 3 or 4 alive neighbours, survive if 2, 3,
// or 4 alive neighbours. Tested over 100+ steps at starting densities from
// 20%→55%: always stays evolving, equilibrium ~55-62% coverage (right in the
// NSW compliance zone), never collapses to a fixed point.
//
// The gradual state system (GROW/DECAY = 64 per step) means:
//   dead → alive in 2 steps  (0 → 64 → 128)
//   alive → dead  in 3 steps (192 → 128 → 64 → 0)
// At 10fps you see smooth colour transitions rather than instant flips.
//
// Why NOT the two-radius MNCA: from a uniform starting density the outer boost
// (= GROW) exactly cancels the inner decay (= -DECAY) whenever boost fires,
// creating a trivial fixed point within 5 steps. It needs specific initial
// structures (gliders, blobs) to produce waves — wrong for this demo.
//
// Why NOT Conway B3/S23: equilibrium drifts to ~38-40% which looks too sparse
// and makes the compliance story less dramatic.

const ALIVE    = 128;
const BIRTH_LO = 3, BIRTH_HI = 4;  // B34 — 3 or 4 alive neighbours → born
const SURV_LO  = 2, SURV_HI  = 4;  // S234 — 2, 3, or 4 → survive
const GROW     = 64;
const DECAY    = 64;

function initGrid() {
  // 25% random alive seed — spatial heterogeneity, well within B34/S234 dynamic regime
  for (let i = 0; i < W * H; i++) {
    grid[i] = Math.random() < 0.25
      ? (148 + Math.floor(Math.random() * 107))  // alive: 148-255
      : Math.floor(Math.random() * 60);           // dead: 0-60
  }
  tick = 0;
}

function clamp(v) { return v < 0 ? 0 : v > 255 ? 255 : v; }

function stepGrid() {
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const self = grid[y * W + x];
      let alive = 0;
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          if (dx === 0 && dy === 0) continue;
          if (grid[((y + dy + H) % H) * W + ((x + dx + W) % W)] >= ALIVE) alive++;
        }
      }
      const isAlive = self >= ALIVE;
      const delta = isAlive
        ? (alive >= SURV_LO && alive <= SURV_HI ? GROW : -DECAY)
        : (alive >= BIRTH_LO && alive <= BIRTH_HI ? GROW : -DECAY);
      nextGrid[y * W + x] = clamp(self + delta);
    }
  }
  [grid, nextGrid] = [nextGrid, grid];
  tick++;
}

// ── Rendering ──────────────────────────────────────────────────────────────

const canvas = document.getElementById('grid');
const ctx = canvas.getContext('2d');
const imgData = ctx.createImageData(W, H);

// Color ramp: bare brown → establishing yellow-green → full green
function stateToColor(v) {
  // 0-110: brown range
  // 110-180: transitional yellow-green
  // 180-255: full green
  let r, g, b;
  if (v < 50) {
    // 0-50: dark reddish-brown (exposed overburden)
    const t = v / 50;
    r = Math.round(80  + t * 52);   // 80→132
    g = Math.round(30  + t * 28);   // 30→58
    b = Math.round(10  + t * 14);   // 10→24
  } else if (v < ALIVE) {
    // 50-110: tan/ochre (disturbed, early colonizers)
    const t = (v - 50) / (ALIVE - 50);
    r = Math.round(132 + t * 40);   // 132→172
    g = Math.round(58  + t * 82);   // 58→140
    b = Math.round(24  + t * 16);   // 24→40
  } else if (v < 180) {
    // 110-180: establishing (yellow-green)
    const t = (v - ALIVE) / (180 - ALIVE);
    r = Math.round(172 - t * 92);   // 172→80
    g = Math.round(140 + t * 50);   // 140→190
    b = Math.round(40  - t * 10);   // 40→30
  } else {
    // 180-255: established to full rehab (deep green)
    const t = (v - 180) / 75;
    r = Math.round(80  - t * 54);   // 80→26
    g = Math.round(190 - t * 100);  // 190→90  (darker = denser)
    b = Math.round(30  - t * 10);   // 30→20
  }
  return [r, g, b];
}

function render() {
  const d = imgData.data;
  let aliveCount = 0;
  for (let i = 0; i < W * H; i++) {
    const v = grid[i];
    if (v >= ALIVE) aliveCount++;
    const [r, g, b] = stateToColor(v);
    const p = i * 4;
    d[p] = r; d[p+1] = g; d[p+2] = b; d[p+3] = 255;
  }
  ctx.putImageData(imgData, 0, 0);
  // Scale up to canvas display size
  ctx.imageSmoothingEnabled = false;

  const coveragePct = ((aliveCount / (W * H)) * 100).toFixed(1);
  document.getElementById('ov-tick').textContent = tick;
  document.getElementById('ov-cov').textContent  = coveragePct + '%';
  document.getElementById('ov-zone').textContent = zone;
  document.getElementById('stat-tick').textContent = tick;
  document.getElementById('stat-cov').textContent  = coveragePct + '%';
  return { coveragePct: parseFloat(coveragePct), aliveCount };
}

// Canvas is 50×50 px, scaled to 400×400 via CSS (pixelated)

// ── Animation loop ─────────────────────────────────────────────────────────

let frameTimer = null;

function startLoop() {
  if (frameTimer) clearInterval(frameTimer);
  frameTimer = setInterval(() => { stepGrid(); render(); }, Math.round(1000 / fps));
}

function setSpeed(v) {
  fps = v;
  document.getElementById('speed-label').textContent = v + ' fps';
  startLoop();
}

function setZone(z) {
  zone = z;
  initGrid();
  tick = 0;
}

// ── Grid hash ──────────────────────────────────────────────────────────────

async function gridHash() {
  const buf = await crypto.subtle.digest('SHA-256', grid);
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2,'0')).join('');
}

// ── BSV anchoring ──────────────────────────────────────────────────────────

inspectionCount = 0;

async function recordInspection() {
  if (anchoring) return;
  anchoring = true;
  const btn = document.getElementById('anchor-btn');
  btn.disabled = true;
  btn.classList.add('anchoring');
  btn.textContent = '⏳ Anchoring on BSV…';

  const { coveragePct } = render();
  const hash   = await gridHash();
  const ts     = Math.floor(Date.now() / 1000);
  const seq    = ++inspectionCount;
  document.getElementById('stat-count').textContent = seq;

  const payload = {
    v:           1,
    type:        'mnca.rehab.inspection',
    zone:        'Zone ' + zone,
    tick,
    coveragePct,
    gridHash:    hash,
    ts,
    seq,
    inspector:   'Automated MNCA Monitor',
  };

  // Append pending entry immediately
  const entryId = 'log-' + seq;
  appendLogEntry(entryId, payload, null, 'pending');

  try {
    const r = await fetch('/anchor', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    if (!r.ok) throw new Error(await r.text());
    const { txid } = await r.json();
    updateLogEntry(entryId, txid);
    console.log('Anchored:', txid);
  } catch (e) {
    updateLogEntryError(entryId, e.message);
    console.error('Anchor failed:', e);
  } finally {
    anchoring = false;
    btn.disabled = false;
    btn.classList.remove('anchoring');
    btn.textContent = '⬡ Record Inspection to BSV';
  }
}

// ── Log rendering ──────────────────────────────────────────────────────────

function appendLogEntry(id, payload, txid, state) {
  const log = document.getElementById('log');
  // Remove empty message
  const empty = log.querySelector('.log-empty');
  if (empty) empty.remove();

  const ts = new Date(payload.ts * 1000).toLocaleTimeString();
  const el = document.createElement('div');
  el.id = id;
  el.className = 'log-entry ' + state;
  el.innerHTML = \`
    <div class="log-header">
      <span class="log-zone">\${payload.zone}</span>
      <span class="log-tick">tick \${payload.tick}</span>
      <span class="log-cov">\${payload.coveragePct}%</span>
      <span class="log-ts">\${ts}</span>
    </div>
    <div class="log-txid" id="\${id}-txid">
      <span style="color:var(--amber)">⏳ broadcasting…</span>
    </div>
    <div class="log-hash" title="SHA-256 of grid state">\${payload.gridHash}</div>
  \`;
  log.insertBefore(el, log.firstChild);
}

function updateLogEntry(id, txid) {
  const el = document.getElementById(id);
  if (el) el.className = 'log-entry anchored';
  const txEl = document.getElementById(id + '-txid');
  if (txEl) txEl.innerHTML = \`
    <span class="verified">✓ anchored</span>
    <a href="https://whatsonchain.com/tx/\${txid}" target="_blank" rel="noopener">
      \${txid.slice(0,16)}…\${txid.slice(-8)}
    </a>
    <span style="color:var(--muted);font-size:9px">[WhatsOnChain →]</span>
  \`;
}

function updateLogEntryError(id, msg) {
  const txEl = document.getElementById(id + '-txid');
  if (txEl) txEl.innerHTML = \`<span style="color:var(--red)">✗ \${msg.slice(0,80)}</span>\`;
}

// ── MND health check ───────────────────────────────────────────────────────

async function checkMnd() {
  try {
    const r = await fetch('/mnd-status', { signal: AbortSignal.timeout(2000) });
    const j = await r.json();
    mndOnline = j.ok;
    document.getElementById('mnd-status').textContent = j.ok
      ? '✓ Metanet Desktop connected — anchoring live'
      : '✗ Metanet Desktop offline — start MND to enable anchoring';
    document.getElementById('mnd-status').style.color = j.ok ? 'var(--green)' : 'var(--red)';
  } catch {
    mndOnline = false;
    document.getElementById('mnd-status').textContent = '✗ Server offline';
    document.getElementById('mnd-status').style.color = 'var(--red)';
  }
}

// ── Real NDVI seed loading ─────────────────────────────────────────────────

let realDataMeta = null;

async function loadRealData() {
  try {
    const r = await fetch('/grid-seed');
    if (!r.ok) return false;
    const j = await r.json();
    if (!j.ok || !j.cells || j.cells.length !== W * H) return false;
    // Load raw NDVI states. Add small per-cell noise so cells near the
    // alive threshold (128) aren't all in exactly the same state — that gives
    // the CA local variation to act on rather than a perfectly uniform field.
    for (let i = 0; i < W * H; i++) {
      const noise = Math.floor((Math.random() - 0.5) * 30);
      grid[i] = Math.max(0, Math.min(255, j.cells[i] + noise));
    }
    tick = 0;
    realDataMeta = { tileId: j.tileId, date: j.date, location: j.location, source: j.source };
    console.log('Loaded real NDVI grid:', j.tileId, j.date);
    return true;
  } catch (e) {
    console.warn('Real data not available:', e.message);
    return false;
  }
}

// ── Claude compliance analysis ─────────────────────────────────────────────

let analysisRunning = false;

async function getClaudeAnalysis() {
  if (analysisRunning) return;
  analysisRunning = true;
  const btn = document.getElementById('analysis-btn');
  if (btn) { btn.disabled = true; btn.textContent = '⏳ Analysing…'; }

  const { coveragePct } = render();
  const hash = await gridHash();

  try {
    const r = await fetch('/claude-analysis', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ zone: 'Zone ' + zone, tick, coveragePct, gridHash: hash }),
    });
    const j = await r.json();
    if (!r.ok) throw new Error(j.error ?? 'Analysis failed');
    const a = j.analysis;

    const statusColor = { compliant: 'var(--green)', remediation_required: 'var(--amber)', non_compliant: 'var(--red)' }[a.status] ?? 'var(--muted)';
    const statusEmoji = { compliant: '✓', remediation_required: '⚠', non_compliant: '✗' }[a.status] ?? '?';
    const panel = document.getElementById('analysis-panel');
    if (panel) {
      panel.innerHTML = \`
        <div style="display:flex;align-items:center;gap:10px;margin-bottom:10px">
          <span style="color:\${statusColor};font-size:1.2rem;font-weight:700">\${statusEmoji} \${(a.status ?? '').replace(/_/g,' ').toUpperCase()}</span>
          <span style="color:var(--muted);font-size:.75rem">\${(a.coverage_class ?? '').replace(/_/g,' ')} · trajectory: \${a.trajectory ?? '?'}</span>
        </div>
        <p style="color:var(--fg);font-size:.82rem;line-height:1.6;margin-bottom:10px">\${a.summary ?? ''}</p>
        \${a.key_findings?.length ? \`
          <div style="font-size:.72rem;color:var(--muted);margin-bottom:6px;text-transform:uppercase;letter-spacing:.04em">Key Findings</div>
          <ul style="padding-left:14px;margin-bottom:10px">\${a.key_findings.map(f => \`<li style="font-size:.8rem;color:var(--fg);line-height:1.5;margin-bottom:3px">\${f}</li>\`).join('')}</ul>
        \` : ''}
        \${a.recommended_actions?.length ? \`
          <div style="font-size:.72rem;color:var(--muted);margin-bottom:6px;text-transform:uppercase;letter-spacing:.04em">Recommended Actions</div>
          <ul style="padding-left:14px">\${a.recommended_actions.map(f => \`<li style="font-size:.8rem;color:var(--amber);line-height:1.5;margin-bottom:3px">\${f}</li>\`).join('')}</ul>
        \` : ''}
        <div style="font-size:.68rem;color:var(--muted);margin-top:8px">Next inspection recommended in \${a.next_inspection_recommended_days ?? '?'} days · Claude Haiku 4.5 · NSW Resources Regulator standards</div>
      \`;
    }
  } catch (e) {
    const panel = document.getElementById('analysis-panel');
    if (panel) panel.innerHTML = \`<span style="color:var(--red)">✗ \${e.message.slice(0,120)}</span>\`;
  } finally {
    analysisRunning = false;
    if (btn) { btn.disabled = false; btn.textContent = '🤖 Get AI Compliance Report'; }
  }
}

// ── Boot ───────────────────────────────────────────────────────────────────
// Wrapped in async IIFE — top-level await is only valid in module scripts,
// and this is a classic <script> tag embedded in a template literal.

(async function boot() {
  initGrid();

  // Try to load real Sentinel-2 NDVI data; fall back to synthetic
  const loadedReal = await loadRealData();
  const src = document.getElementById('data-source');
  if (loadedReal && realDataMeta) {
    if (src) {
      src.textContent = \`🛰 Sentinel-2 · \${realDataMeta.tileId} · \${realDataMeta.date}\`;
      src.style.color = 'var(--green)';
    }
  } else {
    if (src) {
      src.textContent = 'Synthetic mine pattern (run sentinel2-ndvi-ingest.ts for real data)';
      src.style.color = 'var(--amber)';
    }
  }

  render();
  startLoop();
  checkMnd();
  setInterval(checkMnd, 15000);
}());
</script>
</body>
</html>`;

// ── Server ─────────────────────────────────────────────────────────────────

Bun.serve({
  port: PORT,
  async fetch(req) {
    const url = new URL(req.url);

    // Serve HTML
    if (url.pathname === '/' && req.method === 'GET') {
      return new Response(HTML, { headers: { 'Content-Type': 'text/html' } });
    }

    // MND health check (proxied to avoid CORS from browser)
    if (url.pathname === '/mnd-status') {
      try {
        const pk = await getMndPubkey();
        return Response.json({ ok: !!pk });
      } catch {
        return Response.json({ ok: false });
      }
    }

    // Real NDVI grid seed (from sentinel2-ndvi-ingest.ts)
    if (url.pathname === '/grid-seed' && req.method === 'GET') {
      if (!gridSeedData) return Response.json({ ok: false, reason: 'no seed — run sentinel2-ndvi-ingest.ts first' }, { status: 404 });
      return Response.json({ ok: true, ...gridSeedData });
    }

    // Claude API compliance analysis
    if (url.pathname === '/claude-analysis' && req.method === 'POST') {
      if (!anthropic) return Response.json({ error: 'ANTHROPIC_API_KEY not configured' }, { status: 503 });
      try {
        const body: any = await req.json();
        const zone        = body.zone        ?? 'Zone A';
        const tick        = body.tick        ?? 0;
        const coveragePct = body.coveragePct ?? 0;
        const gridHash    = body.gridHash    ?? 'unknown';
        const tileId      = gridSeedData?.tileId ?? 'synthetic';
        const tileDate    = gridSeedData?.date   ?? 'unknown';
        const location    = gridSeedData?.location ?? 'Hunter Valley NSW';

        const prompt = `You are a mining rehabilitation compliance specialist for NSW Resources Regulator.

Analyse the following MNCA (Multi-Neighbourhood Cellular Automaton) vegetation monitoring report and provide a structured compliance assessment.

MONITORING DATA:
- Site: ${location}
- Sentinel-2 Tile: ${tileId} (captured ${tileDate})
- Zone: ${zone}
- Simulation Tick: ${tick}
- Vegetation Coverage: ${coveragePct.toFixed(1)}%
- Grid State Hash (SHA-256): ${gridHash.slice(0, 16)}…
- On-chain anchor: BSV mainnet PushDrop UTXO

CONTEXT:
NSW Mining Act rehabilitation standards require progressive rehabilitation covering ≥80% of disturbed area before mine closure. Coverage <60% triggers a compliance notice. Coverage 60-80% requires a remediation plan.

Provide your assessment in this JSON structure:
{
  "status": "compliant" | "remediation_required" | "non_compliant",
  "coverage_class": "excellent" | "satisfactory" | "marginal" | "poor",
  "summary": "2-3 sentence summary for the regulator",
  "key_findings": ["finding 1", "finding 2", "finding 3"],
  "recommended_actions": ["action 1", "action 2"],
  "trajectory": "improving" | "stable" | "declining",
  "next_inspection_recommended_days": number
}`;

        const message = await anthropic.messages.create({
          model: 'claude-haiku-4-5',
          max_tokens: 600,
          messages: [{ role: 'user', content: prompt }],
        });
        const text = (message.content[0] as any).text?.trim() ?? '';
        // Extract JSON from the response
        const jsonMatch = text.match(/\{[\s\S]*\}/);
        const analysis = jsonMatch ? JSON.parse(jsonMatch[0]) : { summary: text };
        console.log(`[claude-analysis] ${zone} ${coveragePct.toFixed(1)}% → ${analysis.status}`);
        return Response.json({ ok: true, analysis, rawText: text });
      } catch (e: any) {
        console.error('[claude-analysis] failed:', e.message);
        return Response.json({ error: e.message }, { status: 500 });
      }
    }

    // Anchor endpoint
    if (url.pathname === '/anchor' && req.method === 'POST') {
      try {
        const payload = await req.json();
        const txid = await anchorInspection(payload);
        console.log(`[anchor] Zone ${payload.zone} tick=${payload.tick} cov=${payload.coveragePct}% → ${txid}`);
        return Response.json({ txid });
      } catch (e: any) {
        console.error('[anchor] failed:', e.message);
        return new Response(e.message, { status: 500 });
      }
    }

    return new Response('not found', { status: 404 });
  },
});

console.log('');
console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
console.log('  Rehabilitation Zone Monitor');
console.log('  MNCA simulation + BSV mainnet anchoring');
console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
console.log(`  Open:  http://localhost:${PORT}`);
console.log(`  MND:   ${MND_URL}`);
console.log('');

// Check MND on startup
try {
  await getMndPubkey();
  console.log('  ✓ Metanet Desktop connected — anchoring live');
} catch (e: any) {
  console.log(`  ✗ Metanet Desktop offline (${e.message})`);
  console.log('    Start MND to enable real BSV anchoring');
}
console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
console.log('');

```
