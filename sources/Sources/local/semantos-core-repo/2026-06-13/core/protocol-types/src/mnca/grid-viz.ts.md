---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/mnca/grid-viz.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.899769+00:00
---

# core/protocol-types/src/mnca/grid-viz.ts

```ts
/**
 * grid-viz.ts — browser visualizer for the MNCA reference rule (L4-I).
 *
 * Two render modes, chosen automatically at startup:
 *
 *  LIVE MESH  — connects to docs/demo/mesh-bridge.ts running on
 *               BRIDGE_URL (localhost:4400/events) and renders the
 *               real distributed MNCA tiles from the Pi mesh (or local
 *               mesh harness) as a composite N×M grid, one tile per node.
 *
 *  LOCAL SIM  — fallback when the bridge is unreachable. Runs the same
 *               stepTile kernel locally in the browser on a single tile.
 *
 * No build-time deps beyond the tile codec; bundle with:
 *   bun build core/protocol-types/src/mnca/grid-viz.ts \
 *     --target=browser --outfile docs/demo/mnca-grid.js
 */

import {
  encodeTilePayload,
  decodeTilePayload,
  stepTile,
  DEFAULT_MNCA_RULE,
  type TileState,
} from './tile';

const W = 27;
const H = 27;
const R = DEFAULT_MNCA_RULE.outerRadius; // halo width must cover the largest neighbourhood
const INTERIOR = W - 2 * R; // cells that actually evolve
const ALIVE = DEFAULT_MNCA_RULE.aliveThreshold;
const CELL_PX = 16;

function freshTile(seedDensity = 0.35): TileState {
  const cells = new Uint8Array(W * H);
  // Seed the interior with random alive cells; halo filled by wrap each frame.
  for (let y = R; y < H - R; y++) {
    for (let x = R; x < W - R; x++) {
      cells[y * W + x] = Math.random() < seedDensity ? 255 : 0;
    }
  }
  return { tileX: 0, tileY: 0, tick: 0n, width: W, height: H, haloRadius: R, flags: 0, cells };
}

/** Torus-wrap the R-wide halo from the opposite interior edges (stands in for
 *  neighbour gossip). Period = INTERIOR, so the grid is seamless. */
function wrapHalo(cells: Uint8Array): void {
  const map = (i: number): number => {
    // Map any index into the interior range [R, R+INTERIOR) toroidally.
    let j = i;
    while (j < R) j += INTERIOR;
    while (j >= R + INTERIOR) j -= INTERIOR;
    return j;
  };
  const src = cells.slice();
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const inInterior = x >= R && x < W - R && y >= R && y < H - R;
      if (inInterior) continue;
      cells[y * W + x] = src[map(y) * W + map(x)]!;
    }
  }
}

function colorFor(v: number): string {
  if (v >= ALIVE) {
    // alive → warm (teal→green by intensity)
    const t = Math.min(255, v);
    return `rgb(${40 + (t - ALIVE) * 0.4 | 0}, ${120 + (t - ALIVE) | 0}, ${140})`;
  }
  // sub-threshold → dark, brighter as it approaches the threshold
  const g = (v / ALIVE) * 40 | 0;
  return `rgb(${g}, ${g + 6}, ${g + 12})`;
}

export function mount(canvas: HTMLCanvasElement, tickEl: HTMLElement): {
  play(): void; pause(): void; reseed(): void; step(): void; isPlaying(): boolean;
} {
  canvas.width = INTERIOR * CELL_PX;
  canvas.height = INTERIOR * CELL_PX;
  const ctx = canvas.getContext('2d')!;

  let tile = freshTile();
  let timer: ReturnType<typeof setInterval> | null = null;

  const render = (): void => {
    // Round-trip through the canonical payload codec each frame to prove the
    // viz state IS a real cell payload, not a parallel representation.
    const t = decodeTilePayload(encodeTilePayload(tile));
    ctx.fillStyle = '#0a0a0a';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    for (let y = R; y < H - R; y++) {
      for (let x = R; x < W - R; x++) {
        ctx.fillStyle = colorFor(t.cells[y * W + x]!);
        ctx.fillRect((x - R) * CELL_PX, (y - R) * CELL_PX, CELL_PX - 1, CELL_PX - 1);
      }
    }
    tickEl.textContent = `tick ${t.tick}  ·  ${INTERIOR}×${INTERIOR} interior  ·  rule: LtL(b${DEFAULT_MNCA_RULE.birthLo} s${DEFAULT_MNCA_RULE.surviveLo}-${DEFAULT_MNCA_RULE.surviveHi}) + outer r${DEFAULT_MNCA_RULE.outerRadius}`;
  };

  const advance = (): void => {
    wrapHalo(tile.cells);     // neighbour gossip (torus) refreshes the halo
    tile = stepTile(tile);    // the canonical MNCA kernel — same as on-chain
    render();
  };

  render();
  return {
    play() { if (!timer) timer = setInterval(advance, 120); },
    pause() { if (timer) { clearInterval(timer); timer = null; } },
    reseed() { tile = freshTile(); render(); },
    step() { advance(); },
    isPlaying() { return timer !== null; },
  };
}

// ── Bridge SSE support (slice 3) ─────────────────────────────────────────────

const BRIDGE_URL = 'http://localhost:4400/events';
/** Millis to wait for the first SSE tile before falling back to local sim. */
const BRIDGE_TIMEOUT_MS = 2500;

/** Shape of tiles arriving over the bridge SSE.
 *  tick is a plain JSON number (BigInt serialised as number by JSON.stringify);
 *  cells is a plain number[] (not Uint8Array). */
interface BridgeTile {
  tileX: number; tileY: number; tick: number;
  width: number; height: number; halo: number;
  cells: number[];
}

/** Render all bridge tiles onto the canvas as a composite grid. */
function renderMeshFrame(
  ctx: CanvasRenderingContext2D,
  canvas: HTMLCanvasElement,
  tiles: Map<string, BridgeTile>,
  tickEl: HTMLElement,
  statusEl: HTMLElement | null,
): void {
  if (tiles.size === 0) return;
  // Determine bounds and interior size from received tiles.
  let maxTX = 0, maxTY = 0, iW = 12, iH = 12;
  for (const t of tiles.values()) {
    if (t.tileX > maxTX) maxTX = t.tileX;
    if (t.tileY > maxTY) maxTY = t.tileY;
    iW = t.width  - 2 * t.halo;
    iH = t.height - 2 * t.halo;
  }
  const cols = maxTX + 1, rows = maxTY + 1;
  const newW = cols * iW * CELL_PX, newH = rows * iH * CELL_PX;
  if (canvas.width !== newW || canvas.height !== newH) {
    canvas.width = newW; canvas.height = newH;
  }
  ctx.fillStyle = '#0a0a0a';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  let latestTick = 0;
  for (const tile of tiles.values()) {
    const { tileX, tileY, halo, width, height, cells, tick } = tile;
    if (tick > latestTick) latestTick = tick;
    const baseX = tileX * iW * CELL_PX, baseY = tileY * iH * CELL_PX;
    for (let y = halo; y < height - halo; y++) {
      for (let x = halo; x < width - halo; x++) {
        ctx.fillStyle = colorFor(cells[y * width + x] ?? 0);
        ctx.fillRect(
          baseX + (x - halo) * CELL_PX, baseY + (y - halo) * CELL_PX,
          CELL_PX - 1, CELL_PX - 1,
        );
      }
    }
  }
  tickEl.textContent =
    `tick ${latestTick}  ·  ${cols}×${rows} tiles  ·  ${iW}×${iH} interior/tile  ·  LIVE MESH`;
  if (statusEl) {
    statusEl.textContent = `● live mesh · ${tiles.size} tile${tiles.size !== 1 ? 's' : ''}`;
    statusEl.style.color = '#2ec4b6';
  }
}

// ── Auto-mount when loaded in the demo page ───────────────────────────────────
if (typeof document !== 'undefined') {
  const onReady = (): void => {
    const canvas  = document.getElementById('grid') as HTMLCanvasElement | null;
    const tickEl  = document.getElementById('tick');
    if (!canvas || !tickEl) return;
    const statusEl = document.getElementById('bridge-status');
    const ctx = canvas.getContext('2d')!;

    const tiles = new Map<string, BridgeTile>();
    let localCtl: ReturnType<typeof mount> | null = null;
    let meshTimer: ReturnType<typeof setInterval> | null = null;

    // ── local sim fallback ──
    const startLocalSim = (): void => {
      if (localCtl || meshTimer) return; // already running something
      localCtl = mount(canvas, tickEl);
      localCtl.play();
      if (statusEl) { statusEl.textContent = '○ local sim'; statusEl.style.color = '#6b7a82'; }
    };

    // ── switch to live mesh rendering ──
    const switchToMesh = (): void => {
      if (meshTimer) return; // already in mesh mode
      if (localCtl) { localCtl.pause(); localCtl = null; }
      meshTimer = setInterval(
        () => renderMeshFrame(ctx, canvas, tiles, tickEl, statusEl), 100);
      if (statusEl) { statusEl.textContent = '● live mesh · 1 tile'; statusEl.style.color = '#2ec4b6'; }
    };

    // ── try bridge; fallback after timeout; retry from local sim ──
    let es: EventSource | null = null;

    const tryBridge = (): void => {
      if (meshTimer) return; // already in mesh mode — nothing to do
      if (es) { es.close(); es = null; }
      if (statusEl && !localCtl) { statusEl.textContent = 'checking bridge…'; statusEl.style.color = '#6b7a82'; }

      es = new EventSource(BRIDGE_URL);
      const fallbackTimer = setTimeout((): void => {
        if (!meshTimer) startLocalSim();
      }, BRIDGE_TIMEOUT_MS);

      es.onmessage = (ev: MessageEvent): void => {
        clearTimeout(fallbackTimer);
        let tile: BridgeTile;
        try { tile = JSON.parse(ev.data as string) as BridgeTile; } catch { return; }
        tiles.set(`${tile.tileX},${tile.tileY}`, tile);
        if (!meshTimer) switchToMesh();
      };

      es.onerror = (): void => {
        clearTimeout(fallbackTimer);
        if (!meshTimer) startLocalSim();
        // Retry the bridge every 10 s while in local sim mode.
        // This means opening run-real-mesh.ts after the page loads still works.
        setTimeout(tryBridge, 10_000);
      };
    };

    if (typeof EventSource !== 'undefined') {
      tryBridge();
    } else {
      startLocalSim();
    }

    // Button bindings operate on local sim; hidden/inactive in mesh mode.
    document.getElementById('play')?.addEventListener('click', () => {
      if (localCtl) (localCtl.isPlaying() ? localCtl.pause() : localCtl.play());
    });
    document.getElementById('step')?.addEventListener('click',   () => localCtl?.step());
    document.getElementById('reseed')?.addEventListener('click', () => localCtl?.reseed());
  };

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', onReady);
  else onReady();
}

```
