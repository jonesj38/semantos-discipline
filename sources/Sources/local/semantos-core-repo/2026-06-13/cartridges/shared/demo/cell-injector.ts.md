---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/demo/cell-injector.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.435727+00:00
---

# cartridges/shared/demo/cell-injector.ts

```ts
#!/usr/bin/env bun
/**
 * cell-injector.ts — MNCA Compute Layer demo for the Layer Collapse pipeline
 *
 * Runs the canonical MNCA rule (stepTile from protocol-types) in a tight loop,
 * encodes each tick as a CanonicalCellHeader, and publishes it through the
 * multicast relay (:5199). This closes the Compute → Network → Money → Storage
 * chain:
 *
 *   Mac (stepTile) → relay (:5199) → UDP multicast → cell-store (:5197)
 *                                  → CashLanes advance (:5198) → BSV anchor
 *
 * Usage:
 *   # With funded CashLanes channel (real payment per cell):
 *   bun cartridges/shared/demo/cell-injector.ts
 *
 *   # Demo mode — no channel needed (relay must have RELAY_ALLOW_LOCAL_INJECT=true):
 *   DEMO_MODE=true bun cartridges/shared/demo/cell-injector.ts
 *
 *   # Custom rate (default 10 ticks/sec):
 *   TICK_RATE=5 bun cartridges/shared/demo/cell-injector.ts
 *
 * Tile: 27×27 grid (haloRadius=3, interior=21×21). 729 bytes state + 16 header
 *        = 745 bytes active; zero-padded to canonical PAYLOAD_SIZE=768.
 * Type path: mnca.tile.tick
 * Sender fingerprint: SHA-256("mnca-injector")[0:8]
 */

import { createHash } from 'node:crypto';

// ── Canonical MNCA tile codec (from core/protocol-types) ──────────────────────
// Using the shared canonical codec ensures the injector produces 768-byte
// payloads that match PAYLOAD_SIZE exactly, consistent with the cell-engine
// WASM port and all other consumers.
import {
  type TileState,
  type MncaRuleParams,
  DEFAULT_MNCA_RULE,
  encodeTilePayload,
  stepTile,
} from '../../../core/protocol-types/src/mnca/tile';

// Re-export alias so the rest of the file reads naturally.
const DEFAULT_RULE: MncaRuleParams = DEFAULT_MNCA_RULE;

// ── Config ────────────────────────────────────────────────────────────────────

const RELAY_URL  = process.env.RELAY_URL   ?? 'http://localhost:5199';
const STORE_URL  = process.env.STORE_URL   ?? 'http://localhost:5197';
const TICK_RATE  = parseFloat(process.env.TICK_RATE ?? '10'); // ticks per second
const DEMO_MODE  = process.env.DEMO_MODE   === 'true';        // skip x402 check message
const TYPE_PATH  = 'mnca.tile.tick';
const SENDER_FP  = createHash('sha256').update('mnca-injector').digest('hex').slice(0, 8);

// ── Tile setup ────────────────────────────────────────────────────────────────

// 27×27 with haloRadius=3 → interior=21×21 = 441 owned cells.
// Payload: 16 header + 729 state = 745 bytes; canonical encodeTilePayload
// zero-pads to PAYLOAD_SIZE=768 bytes for wire-format compliance.
const W = 27, H = 27, HALO = 3;

function randomTile(): TileState {
  const cells = new Uint8Array(W * H);
  // Seed the interior with random live/dead cells (~40% alive)
  const margin = HALO;
  for (let y = margin; y < H - margin; y++)
    for (let x = margin; x < W - margin; x++)
      cells[y * W + x] = Math.random() < 0.40 ? 255 : 0;
  return { tileX: 0, tileY: 0, tick: 0n, width: W, height: H, haloRadius: HALO, flags: 0, cells };
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// Content-addressed cellId: SHA-256 of the encoded payload bytes.
// This matches the canonical CanonicalCellHeader.cellId semantics and ensures
// each unique tile state produces a unique cellId even across injector restarts
// (tick=0 after restart has different cell values due to random seed).
function cellId(payload: Uint8Array): string {
  return createHash('sha256').update(payload).digest('hex');
}

function renderAscii(tile: TileState): string {
  const SHADES = ' ░▒▓█';
  const lines: string[] = [];
  const R = tile.haloRadius;
  // Render only interior so the frame is clean
  for (let y = R; y < tile.height - R; y++) {
    let line = '';
    for (let x = R; x < tile.width - R; x++) {
      const v = tile.cells[y * tile.width + x]!;
      line += SHADES[Math.floor(v / 52)]!;
    }
    lines.push(line);
  }
  return lines.join('\n');
}

async function checkChannelState(): Promise<string> {
  try {
    const r = await fetch(`http://localhost:5198/channel/state`, { signal: AbortSignal.timeout(800) });
    if (!r.ok) return 'BRIDGE_ERROR';
    const j = await r.json() as { state: string };
    return j.state;
  } catch {
    return 'BRIDGE_OFFLINE';
  }
}

async function getCellCount(): Promise<number> {
  try {
    const r = await fetch(`${STORE_URL}/health`, { signal: AbortSignal.timeout(800) });
    if (!r.ok) return -1;
    const j = await r.json() as { cellCount: number };
    return j.cellCount;
  } catch { return -1; }
}

// ── Main loop ─────────────────────────────────────────────────────────────────

console.log(`\n╔════════════════════════════════════════════════════════════╗`);
console.log(`║  MNCA Cell Injector — Layer Collapse Compute Layer         ║`);
console.log(`║  Tile: ${W}×${H} (interior ${W - 2*HALO}×${H - 2*HALO}), halo=${HALO}, rule=DEFAULT  ║`);
console.log(`║  Type: ${TYPE_PATH}                    ║`);
console.log(`║  Sender: ${SENDER_FP}  Rate: ${TICK_RATE} ticks/sec          ║`);
console.log(`╚════════════════════════════════════════════════════════════╝\n`);

if (DEMO_MODE) {
  console.log(`  ⚡ DEMO_MODE=true — relay must have RELAY_ALLOW_LOCAL_INJECT=true`);
  console.log(`     Restart relay: RELAY_ALLOW_LOCAL_INJECT=true bun cartridges/shared/relay/multicast-relay.ts\n`);
}

// Check relay
try {
  const rh = await fetch(`${RELAY_URL}/health`, { signal: AbortSignal.timeout(2000) });
  if (!rh.ok) throw new Error(`HTTP ${rh.status}`);
  const h = await rh.json() as any;
  console.log(`  ✓ relay online  (publishCount=${h.publishCount ?? '?'})`);
} catch (e: any) {
  console.error(`  ✗ relay offline: ${e.message}`);
  console.error(`    Start: bun cartridges/shared/relay/multicast-relay.ts`);
  process.exit(1);
}

// Wait for FLOW_ACTIVE (unless DEMO_MODE)
if (!DEMO_MODE) {
  let channelState = await checkChannelState();
  if (channelState !== 'FLOW_ACTIVE') {
    console.log(`\n  ⚠ Channel state: ${channelState}`);
    console.log(`    Open http://localhost:5190/ixp-routing/verify/index.html`);
    console.log(`    → Fund Channel  → Start Flow`);
    console.log(`\n  Waiting for FLOW_ACTIVE (Ctrl+C to abort)…`);
    while (channelState !== 'FLOW_ACTIVE') {
      await new Promise(r => setTimeout(r, 2000));
      channelState = await checkChannelState();
      process.stdout.write(`\r  Channel: ${channelState.padEnd(20)}`);
    }
    console.log(`\n  ✓ Channel FLOW_ACTIVE — starting injection`);
  } else {
    console.log(`  ✓ channel FLOW_ACTIVE`);
  }
} else {
  const cs = await checkChannelState();
  console.log(`  ℹ channel: ${cs} (DEMO_MODE bypasses x402)`);
}

console.log(`  ✓ cell-store: ${await getCellCount()} cells stored\n`);

// ── Stagnation detector ───────────────────────────────────────────────────────
// Tracks the interior alive-cell count over the last STAG_WINDOW ticks.
// When all counts in the window are identical the tile has reached a fixed
// point (or period-1 oscillator).  Inject random noise to kick it alive.

const STAG_WINDOW    = 6;   // ticks to look back
const NOISE_DENSITY  = 0.20; // fraction of interior cells to flip alive on reseed
const NOISE_KILL     = 0.08; // fraction of alive interior cells to kill on reseed

const aliveCounts: number[] = [];
let   reseedCount = 0;

function countAliveInterior(tile: TileState): number {
  const { width, haloRadius: R, cells } = tile;
  let n = 0;
  for (let y = R; y < tile.height - R; y++)
    for (let x = R; x < tile.width - R; x++)
      if (cells[y * width + x]! >= DEFAULT_RULE.aliveThreshold) n++;
  return n;
}

function injectNoise(tile: TileState): TileState {
  const next = tile.cells.slice();
  const { width, haloRadius: R } = tile;
  const cells = next;
  for (let y = R; y < tile.height - R; y++) {
    for (let x = R; x < tile.width - R; x++) {
      const idx = y * width + x;
      const alive = cells[idx]! >= DEFAULT_RULE.aliveThreshold;
      if (!alive && Math.random() < NOISE_DENSITY) cells[idx] = 255;
      if ( alive && Math.random() < NOISE_KILL)    cells[idx] = 0;
    }
  }
  reseedCount++;
  return { ...tile, cells: next };
}

// Main tick loop
let tile        = randomTile();
let tickCount   = 0;
let errorCount  = 0;
let lastPrint   = Date.now();
let printTick   = 0;
const intervalMs = 1000 / TICK_RATE;

console.log(`Starting MNCA injection at ${TICK_RATE} ticks/sec…  (Ctrl+C to stop)\n`);

async function injectTick(t: TileState): Promise<void> {
  const payload = encodeTilePayload(t);
  const id      = cellId(payload);  // content-addressed: SHA-256(payload bytes)
  const header  = {
    cellId:     id,
    typePath:   TYPE_PATH,
    senderFp:   SENDER_FP,
    seq:        Number(t.tick),
    payloadLen: payload.length,
  };

  const r = await fetch(`${RELAY_URL}/publish`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify({ header, payload: Buffer.from(payload).toString('hex') }),
    signal:  AbortSignal.timeout(1500),
  });

  if (!r.ok && r.status !== 402) {
    throw new Error(`HTTP ${r.status}`);
  }
}

const timer = setInterval(async () => {
  const t0 = Date.now();

  try {
    await injectTick(tile);
  } catch (e: any) {
    errorCount++;
    if (errorCount % 20 === 1) console.error(`\n  ✗ inject error: ${e.message}`);
  }

  tile = stepTile(tile);
  tickCount++;

  // Stagnation check — reseed if fixed point detected
  const alive = countAliveInterior(tile);
  aliveCounts.push(alive);
  if (aliveCounts.length > STAG_WINDOW) aliveCounts.shift();
  const stagnant = aliveCounts.length === STAG_WINDOW &&
    aliveCounts.every(c => c === aliveCounts[0]);
  if (stagnant || alive === 0) {
    tile = injectNoise(tile);
    aliveCounts.length = 0;  // reset window after reseed
  }

  // Print a frame every second
  const now = Date.now();
  if (now - lastPrint >= 1000) {
    const rate     = ((tickCount - printTick) / ((now - lastPrint) / 1000)).toFixed(1);
    const cells    = await getCellCount().catch(() => -1);
    const ascii    = renderAscii(tile);
    const interior = `${W - 2*HALO}×${H - 2*HALO}`;

    // Clear previous frame (21 lines of interior + status)
    if (tickCount > TICK_RATE) process.stdout.write('\x1B[' + (H - 2*HALO + 4) + 'A');

    const seedTag = reseedCount > 0 ? `  reseeds=${reseedCount}` : '';
    console.log(`── tick ${tile.tick}  rate=${rate}/s  alive=${alive}  cell-store=${cells}  errors=${errorCount}${seedTag} ──`);
    console.log(ascii);
    console.log(`   ${TYPE_PATH}  sender=${SENDER_FP}  interior=${interior}`);
    console.log('');

    lastPrint = now;
    printTick = tickCount;
  }
}, intervalMs);

// Graceful shutdown
process.on('SIGINT', () => {
  clearInterval(timer);
  console.log(`\n\nStopped. Total ticks: ${tickCount}  errors: ${errorCount}`);
  process.exit(0);
});

```
