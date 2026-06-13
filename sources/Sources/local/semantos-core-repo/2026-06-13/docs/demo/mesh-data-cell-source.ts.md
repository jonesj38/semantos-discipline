---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/demo/mesh-data-cell-source.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.746262+00:00
---

# docs/demo/mesh-data-cell-source.ts

```ts
#!/usr/bin/env bun
/**
 * mesh-data-cell-source.ts — D-SRS-mnca-cell-source
 *
 * Replaces the random MNCA tile seed with mesh-derived signal data.
 * This turns the demo from a decorative tile animation into a filter
 * over real mesh state: "data becomes the program."
 *
 * Data mapping (6-axis SNS taxonomy → MNCA cell density):
 *
 *   WHAT density  ← SNS group bits (ff15:WHAT[0:2]:WHAT[2:4]:...)
 *                   Each tile type projects into 32 bits of address space;
 *                   those bits seed spatial structure in the tile rows.
 *
 *   WHO density   ← peer count  (distinct tile sources seen by the bridge)
 *                   More peers → denser initial state (busier mesh).
 *
 *   WHERE coherence ← tile coordinate (tileX, tileY) — spatial gradient
 *                     Adjacent tiles share similar initial density → smooth
 *                     halo exchanges, coherent large-scale patterns.
 *
 *   WHEN validity ← tick freshness  (tick * decay_rate)
 *                   Old tiles have low density; their interior cells die
 *                   under the MNCA decay rule before the next step.
 *                   Recent tiles stay alive — the MNCA acts as a temporal
 *                   low-pass filter ("ageing cells die").
 *
 *   HOW (implicit) ← variance across peer ticks — mesh divergence signal.
 *                   High variance → high outer-neighbourhood activity.
 *
 * Mechanicsm:
 *   1. Poll the bridge's GET /tiles every POLL_MS.
 *   2. For each tile, compute a data-derived seed matching the tile's
 *      actual dimensions (same width/height/halo as the mesh tile).
 *   3. Run DEFAULT_MNCA_RULE for PRE_STEPS generations on the seed.
 *   4. Serve the resulting tiles as SSE events on DATA_PORT (:4402).
 *
 * The browser viz (mnca-grid.html) connects to DATA_PORT/events as a
 * data-layer overlay. When the data source is unreachable the viz falls
 * back to the primary bridge (:4400/events).
 *
 * Run:   bun docs/demo/mesh-data-cell-source.ts
 * Env:   BRIDGE_URL  (http://localhost:4400)  bridge to read tiles from
 *        DATA_PORT   (4402)                   port to serve data SSE on
 *        POLL_MS     (2000)                   polling interval
 *        PRE_STEPS   (3)                      MNCA steps applied to seed
 *        DECAY_RATE  (4)                      tick→density multiplier
 *        PEER_SCALE  (20)                     peer_count→density multiplier
 *
 * SAFETY: read-only observer; no transactions; no private keys.
 */

import { createHash } from 'node:crypto';
import { stepTile, DEFAULT_MNCA_RULE, type TileState } from '../../core/protocol-types/src/mnca/tile';
import { MNCA_TILE_TICK_GROUP } from '../../core/protocol-types/src/mnca/srv6';

// ── config ────────────────────────────────────────────────────────────────────

const BRIDGE_URL  = process.env.BRIDGE_URL  ?? 'http://localhost:4400';
const DATA_PORT   = Number(process.env.DATA_PORT   ?? 4402);
const POLL_MS     = Number(process.env.POLL_MS     ?? 2000);
const PRE_STEPS   = Number(process.env.PRE_STEPS   ?? 3);
const DECAY_RATE  = Number(process.env.DECAY_RATE  ?? 4);
const PEER_SCALE  = Number(process.env.PEER_SCALE  ?? 20);

// Extract the first 4 bytes of the SNS WHAT group for the MNCA tile type.
// Used as a stable spatial seed base so the WHAT axis is physically visible.
const SNS_WHAT_BYTES = (() => {
  // MNCA_TILE_TICK_GROUP = "ff15:4ed1:aabd:873d:e970:0000:0000:0000"
  // Groups 1+2 are the WHAT prefix: 4ed1 aabd
  const parts = MNCA_TILE_TICK_GROUP.split(':');
  const bytes = [
    parseInt(parts[1]!.slice(0, 2), 16),
    parseInt(parts[1]!.slice(2, 4), 16),
    parseInt(parts[2]!.slice(0, 2), 16),
    parseInt(parts[2]!.slice(2, 4), 16),
  ];
  return bytes;
})();

// ── seed computation ──────────────────────────────────────────────────────────

/**
 * Compute a data-derived initial tile state from mesh metrics.
 *
 * The seed density encodes:
 *   - WHEN validity  : tick freshness → alive if recent, dead if stale
 *   - WHO density    : peer count → overall mesh busyness
 *   - WHERE gradient : tileX, tileY → spatial variation
 *   - WHAT bits      : SNS group address bytes → type-system signal
 *
 * Target density ~0.30-0.40 alive cells (works well with DEFAULT_MNCA_RULE
 * birth=3/survive=2-3). Fresh, busy tiles lean toward 0.40; stale sparse
 * tiles lean toward 0.20 so the MNCA decays them naturally.
 */
export function computeDataSeed(
  tileX: number,
  tileY: number,
  tick: number,
  peerCount: number,
  width: number,
  height: number,
  haloRadius: number,
): Uint8Array {
  const cells = new Uint8Array(width * height);
  const ALIVE  = 200;  // value used for alive cells (> aliveThreshold=128)
  const DEAD   = 0;

  // Normalised signals ∈ [0,1]
  const tickFresh  = Math.min(1.0, tick  * DECAY_RATE / 255);  // fresh = 1, stale = 0
  const peerDens   = Math.min(1.0, peerCount * PEER_SCALE / 255);
  const whatSignal = (SNS_WHAT_BYTES[tileX & 3]! ^ SNS_WHAT_BYTES[tileY & 3]!) / 255;

  // Target density: fresh+busy → 0.42, stale+sparse → 0.18
  const targetDensity = 0.18 + 0.12 * tickFresh + 0.08 * peerDens + 0.04 * whatSignal;

  // Per-cell deterministic threshold based on (tileX, tileY, row, col).
  // SHA-256 first byte gives a uniform [0,255] pseudo-random per (x,y,r,c).
  for (let row = 0; row < height; row++) {
    for (let col = 0; col < width; col++) {
      const idx = row * width + col;

      // Halo ring: leave as zero (refreshed by gossip, not part of data seed).
      const isHalo =
        row < haloRadius || row >= height - haloRadius ||
        col < haloRadius || col >= width  - haloRadius;
      if (isHalo) {
        cells[idx] = DEAD;
        continue;
      }

      // Interior: data-derived threshold
      // A fast per-cell hash: XOR of positional bytes — cheap, no crypto.
      const h = sha8(tileX, tileY, row, col);
      const threshold = Math.round(targetDensity * 255);
      cells[idx] = (h & 0xFF) < threshold ? ALIVE : DEAD;
    }
  }

  return cells;
}

/** Fast 8-bit hash of (tileX, tileY, row, col) for cell-level pseudo-randomness. */
function sha8(tileX: number, tileY: number, row: number, col: number): number {
  // Compute a stable digest for the 4 coordinates.
  // Murmur-inspired integer mix — no crypto overhead.
  let h = (tileX * 2654435769 + tileY * 2246822519 + row * 1597334677 + col * 3266489909) >>> 0;
  h ^= h >>> 16;
  h = Math.imul(h, 0x45d9f3b) >>> 0;
  h ^= h >>> 16;
  return h & 0xFF;
}

/**
 * Build a complete data-derived TileState for (tileX, tileY, tick, peerCount),
 * matching the dimensions of the actual tile from the bridge.
 */
export function buildDataTile(
  tileX: number,
  tileY: number,
  tick: number,
  peerCount: number,
  width: number,
  height: number,
  haloRadius: number,
): TileState {
  const cells = computeDataSeed(tileX, tileY, tick, peerCount, width, height, haloRadius);
  // TileState.tick is u64 (bigint) per the tile codec spec.
  return { tileX, tileY, tick: BigInt(tick), width, height, haloRadius, flags: 0, cells };
}

/**
 * Run N generations of the MNCA rule on a data-seeded tile.
 * The rule acts as a temporal filter: recent/busy cells grow,
 * stale/sparse cells decay and die ("ageing cells die").
 */
export function stepDataTile(tile: TileState, steps: number = PRE_STEPS): TileState {
  let t = tile;
  for (let i = 0; i < steps; i++) {
    t = stepTile(t, DEFAULT_MNCA_RULE);
  }
  return t;
}

/** Convert a TileState to the JSON shape the SSE bridge uses. */
export function tileToSSEPayload(tile: TileState): object {
  return {
    tileX:  tile.tileX,
    tileY:  tile.tileY,
    tick:   Number(tile.tick),
    width:  tile.width,
    height: tile.height,
    halo:   tile.haloRadius,
    cells:  Array.from(tile.cells),
    source: 'data',  // distinguishes data-derived from raw mesh tiles
  };
}

// ── bridge tile type (matches mesh-bridge.ts DecodedTile) ─────────────────────

interface BridgeTile {
  tileX: number; tileY: number; tick: number;
  width: number; height: number; halo: number;
  cells: number[];
}

// ── main server ───────────────────────────────────────────────────────────────

if (import.meta.main) {
  const clients = new Set<(data: string) => void>();
  let lastTiles: BridgeTile[] = [];
  let pollCount = 0;

  async function poll(): Promise<void> {
    try {
      const res = await fetch(`${BRIDGE_URL}/tiles`, { signal: AbortSignal.timeout(2000) });
      if (!res.ok) return;
      const tiles = await res.json() as BridgeTile[];
      if (tiles.length === 0) return;

      lastTiles = tiles;
      pollCount++;

      const peerCount = tiles.length;

      for (const raw of tiles) {
        const width  = raw.width;
        const height = raw.height;
        const halo   = raw.halo;

        // Build the data-seeded tile from mesh metrics.
        const seed = buildDataTile(
          raw.tileX, raw.tileY, raw.tick, peerCount,
          width, height, halo,
        );

        // Apply MNCA rule for PRE_STEPS generations.
        const stepped = stepDataTile(seed, PRE_STEPS);
        const payload = tileToSSEPayload(stepped);
        const json    = JSON.stringify(payload);

        for (const send of clients) send(json);
      }

      if (pollCount % 10 === 1) {
        console.log(
          `data-source: poll=${pollCount} tiles=${peerCount} ` +
          `clients=${clients.size} steps=${PRE_STEPS}`,
        );
      }
    } catch {
      // Bridge not yet up or temporary error — retry on next poll.
    }
  }

  // Start polling loop.
  poll();
  setInterval(poll, POLL_MS);

  const cors = { 'Access-Control-Allow-Origin': '*' };

  Bun.serve({
    port: DATA_PORT,
    fetch(req) {
      const url = new URL(req.url);

      // GET /tiles — current data-derived tile snapshot (JSON).
      if (url.pathname === '/tiles') {
        if (lastTiles.length === 0) {
          return Response.json([], { headers: cors });
        }
        const peerCount = lastTiles.length;
        const out = lastTiles.map((raw) => {
          const seed   = buildDataTile(raw.tileX, raw.tileY, raw.tick, peerCount, raw.width, raw.height, raw.halo);
          const stepped = stepDataTile(seed, PRE_STEPS);
          return tileToSSEPayload(stepped);
        });
        return Response.json(out, { headers: cors });
      }

      // GET /events — SSE stream of data-derived tile events.
      if (url.pathname === '/events') {
        let send!: (data: string) => void;
        const stream = new ReadableStream<Uint8Array>({
          start(controller) {
            const enc = new TextEncoder();
            send = (data) => {
              try { controller.enqueue(enc.encode(`data: ${data}\n\n`)); }
              catch { /* closed */ }
            };
            // Initial snapshot — send current computed tiles immediately.
            if (lastTiles.length > 0) {
              const peerCount = lastTiles.length;
              for (const raw of lastTiles) {
                const seed    = buildDataTile(raw.tileX, raw.tileY, raw.tick, peerCount, raw.width, raw.height, raw.halo);
                const stepped = stepDataTile(seed, PRE_STEPS);
                send(JSON.stringify(tileToSSEPayload(stepped)));
              }
            }
            clients.add(send);
          },
          cancel() { clients.delete(send); },
        });
        return new Response(stream, {
          headers: {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection':    'keep-alive',
            ...cors,
          },
        });
      }

      return new Response(
        'mesh-data-cell-source — GET /tiles or /events\n' +
        'data: MNCA tiles seeded from bridge mesh metrics (D-SRS-mnca-cell-source)',
        { headers: cors },
      );
    },
  });

  console.log(`mesh-data-cell-source: polling ${BRIDGE_URL}/tiles every ${POLL_MS}ms`);
  console.log(`mesh-data-cell-source: SSE on http://localhost:${DATA_PORT}/events`);
  console.log(`  PRE_STEPS=${PRE_STEPS} DECAY_RATE=${DECAY_RATE} PEER_SCALE=${PEER_SCALE}`);
  console.log(`  SNS WHAT bytes: [${SNS_WHAT_BYTES.map(b => b.toString(16).padStart(2,'0')).join(',')}]`);
}

```
