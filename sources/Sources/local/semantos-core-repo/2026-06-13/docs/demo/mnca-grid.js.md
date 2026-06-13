---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/demo/mnca-grid.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.748120+00:00
---

# docs/demo/mnca-grid.js

```js
// core/protocol-types/src/constants.ts
var PAYLOAD_SIZE = 768;

// core/protocol-types/src/mnca/tile.ts
var TILE_HEADER_SIZE = 16;
var TILE_MAX_CELLS = PAYLOAD_SIZE - TILE_HEADER_SIZE;
var OFF_TILE_X = 0;
var OFF_TILE_Y = 2;
var OFF_TICK = 4;
var OFF_WIDTH = 12;
var OFF_HEIGHT = 13;
var OFF_HALO = 14;
var OFF_FLAGS = 15;
var OFF_STATE = 16;
function encodeTilePayload(tile) {
  const { width, height, cells } = tile;
  if (width < 1 || width > 255 || height < 1 || height > 255) {
    throw new Error(`encodeTilePayload: width/height must be 1..255 (got ${width}×${height})`);
  }
  if (cells.length !== width * height) {
    throw new Error(`encodeTilePayload: cells length ${cells.length} != ${width}×${height}`);
  }
  if (TILE_HEADER_SIZE + cells.length > PAYLOAD_SIZE) {
    throw new Error(`encodeTilePayload: ${width}×${height} = ${cells.length} cells + ${TILE_HEADER_SIZE} header exceeds payload (${PAYLOAD_SIZE})`);
  }
  if (tile.haloRadius < 0 || tile.haloRadius > 127) {
    throw new Error(`encodeTilePayload: haloRadius out of range (${tile.haloRadius})`);
  }
  if (2 * tile.haloRadius >= Math.min(width, height)) {
    throw new Error(`encodeTilePayload: haloRadius ${tile.haloRadius} leaves no interior in ${width}×${height}`);
  }
  const payload = new Uint8Array(PAYLOAD_SIZE);
  const dv = new DataView(payload.buffer);
  dv.setUint16(OFF_TILE_X, tile.tileX & 65535, true);
  dv.setUint16(OFF_TILE_Y, tile.tileY & 65535, true);
  dv.setBigUint64(OFF_TICK, tile.tick, true);
  payload[OFF_WIDTH] = width;
  payload[OFF_HEIGHT] = height;
  payload[OFF_HALO] = tile.haloRadius & 255;
  payload[OFF_FLAGS] = tile.flags & 255;
  payload.set(cells, OFF_STATE);
  return payload;
}
function decodeTilePayload(payload) {
  if (payload.length < TILE_HEADER_SIZE) {
    throw new Error(`decodeTilePayload: payload too short (${payload.length})`);
  }
  const dv = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
  const width = payload[OFF_WIDTH];
  const height = payload[OFF_HEIGHT];
  const n = width * height;
  if (TILE_HEADER_SIZE + n > payload.length) {
    throw new Error(`decodeTilePayload: ${width}×${height} cells exceed payload (${payload.length})`);
  }
  return {
    tileX: dv.getUint16(OFF_TILE_X, true),
    tileY: dv.getUint16(OFF_TILE_Y, true),
    tick: dv.getBigUint64(OFF_TICK, true),
    width,
    height,
    haloRadius: payload[OFF_HALO],
    flags: payload[OFF_FLAGS],
    cells: payload.slice(OFF_STATE, OFF_STATE + n)
  };
}
var DEFAULT_MNCA_RULE = {
  aliveThreshold: 128,
  innerRadius: 1,
  outerRadius: 3,
  birthLo: 3,
  birthHi: 3,
  surviveLo: 2,
  surviveHi: 3,
  growStep: 64,
  decayStep: 64,
  outerBoost: 12
};
function clampU8(v) {
  return v < 0 ? 0 : v > 255 ? 255 : v;
}
function neighbourhoodAliveCount(cells, width, x, y, radius, aliveThreshold) {
  let count = 0;
  for (let dy = -radius;dy <= radius; dy++) {
    for (let dx = -radius;dx <= radius; dx++) {
      if (dx === 0 && dy === 0)
        continue;
      const v = cells[(y + dy) * width + (x + dx)];
      if (v >= aliveThreshold)
        count++;
    }
  }
  return count;
}
function stepTile(tile, params = DEFAULT_MNCA_RULE) {
  const { width, height, haloRadius: R, cells } = tile;
  const next = cells.slice();
  const innerR = params.innerRadius;
  const outerR = params.outerRadius;
  const margin = Math.max(R, innerR, outerR);
  for (let y = margin;y < height - margin; y++) {
    for (let x = margin;x < width - margin; x++) {
      const self = cells[y * width + x];
      const innerAlive = neighbourhoodAliveCount(cells, width, x, y, innerR, params.aliveThreshold);
      const outerAlive = neighbourhoodAliveCount(cells, width, x, y, outerR, params.aliveThreshold);
      const isAlive = self >= params.aliveThreshold;
      let delta;
      if (isAlive) {
        delta = innerAlive >= params.surviveLo && innerAlive <= params.surviveHi ? params.growStep : -params.decayStep;
      } else {
        delta = innerAlive >= params.birthLo && innerAlive <= params.birthHi ? params.growStep : -params.decayStep;
      }
      if (outerAlive >= params.outerBoost)
        delta += params.growStep;
      next[y * width + x] = clampU8(self + delta);
    }
  }
  return {
    ...tile,
    tick: tile.tick + 1n,
    cells: next
  };
}

// core/protocol-types/src/mnca/grid-viz.ts
var W = 27;
var H = 27;
var R = DEFAULT_MNCA_RULE.outerRadius;
var INTERIOR = W - 2 * R;
var ALIVE = DEFAULT_MNCA_RULE.aliveThreshold;
var CELL_PX = 16;
function freshTile(seedDensity = 0.35) {
  const cells = new Uint8Array(W * H);
  for (let y = R;y < H - R; y++) {
    for (let x = R;x < W - R; x++) {
      cells[y * W + x] = Math.random() < seedDensity ? 255 : 0;
    }
  }
  return { tileX: 0, tileY: 0, tick: 0n, width: W, height: H, haloRadius: R, flags: 0, cells };
}
function wrapHalo(cells) {
  const map = (i) => {
    let j = i;
    while (j < R)
      j += INTERIOR;
    while (j >= R + INTERIOR)
      j -= INTERIOR;
    return j;
  };
  const src = cells.slice();
  for (let y = 0;y < H; y++) {
    for (let x = 0;x < W; x++) {
      const inInterior = x >= R && x < W - R && y >= R && y < H - R;
      if (inInterior)
        continue;
      cells[y * W + x] = src[map(y) * W + map(x)];
    }
  }
}
function colorFor(v) {
  if (v >= ALIVE) {
    const t = Math.min(255, v);
    return `rgb(${40 + (t - ALIVE) * 0.4 | 0}, ${120 + (t - ALIVE) | 0}, ${140})`;
  }
  const g = v / ALIVE * 40 | 0;
  return `rgb(${g}, ${g + 6}, ${g + 12})`;
}
function mount(canvas, tickEl) {
  canvas.width = INTERIOR * CELL_PX;
  canvas.height = INTERIOR * CELL_PX;
  const ctx = canvas.getContext("2d");
  let tile = freshTile();
  let timer = null;
  const render = () => {
    const t = decodeTilePayload(encodeTilePayload(tile));
    ctx.fillStyle = "#0a0a0a";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    for (let y = R;y < H - R; y++) {
      for (let x = R;x < W - R; x++) {
        ctx.fillStyle = colorFor(t.cells[y * W + x]);
        ctx.fillRect((x - R) * CELL_PX, (y - R) * CELL_PX, CELL_PX - 1, CELL_PX - 1);
      }
    }
    tickEl.textContent = `tick ${t.tick}  ·  ${INTERIOR}×${INTERIOR} interior  ·  rule: LtL(b${DEFAULT_MNCA_RULE.birthLo} s${DEFAULT_MNCA_RULE.surviveLo}-${DEFAULT_MNCA_RULE.surviveHi}) + outer r${DEFAULT_MNCA_RULE.outerRadius}`;
  };
  const advance = () => {
    wrapHalo(tile.cells);
    tile = stepTile(tile);
    render();
  };
  render();
  return {
    play() {
      if (!timer)
        timer = setInterval(advance, 120);
    },
    pause() {
      if (timer) {
        clearInterval(timer);
        timer = null;
      }
    },
    reseed() {
      tile = freshTile();
      render();
    },
    step() {
      advance();
    },
    isPlaying() {
      return timer !== null;
    }
  };
}
var BRIDGE_URL = "http://localhost:4400/events";
var BRIDGE_TIMEOUT_MS = 2500;
function renderMeshFrame(ctx, canvas, tiles, tickEl, statusEl) {
  if (tiles.size === 0)
    return;
  let maxTX = 0, maxTY = 0, iW = 12, iH = 12;
  for (const t of tiles.values()) {
    if (t.tileX > maxTX)
      maxTX = t.tileX;
    if (t.tileY > maxTY)
      maxTY = t.tileY;
    iW = t.width - 2 * t.halo;
    iH = t.height - 2 * t.halo;
  }
  const cols = maxTX + 1, rows = maxTY + 1;
  const newW = cols * iW * CELL_PX, newH = rows * iH * CELL_PX;
  if (canvas.width !== newW || canvas.height !== newH) {
    canvas.width = newW;
    canvas.height = newH;
  }
  ctx.fillStyle = "#0a0a0a";
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  let latestTick = 0;
  for (const tile of tiles.values()) {
    const { tileX, tileY, halo, width, height, cells, tick } = tile;
    if (tick > latestTick)
      latestTick = tick;
    const baseX = tileX * iW * CELL_PX, baseY = tileY * iH * CELL_PX;
    for (let y = halo;y < height - halo; y++) {
      for (let x = halo;x < width - halo; x++) {
        ctx.fillStyle = colorFor(cells[y * width + x] ?? 0);
        ctx.fillRect(baseX + (x - halo) * CELL_PX, baseY + (y - halo) * CELL_PX, CELL_PX - 1, CELL_PX - 1);
      }
    }
  }
  tickEl.textContent = `tick ${latestTick}  ·  ${cols}×${rows} tiles  ·  ${iW}×${iH} interior/tile  ·  LIVE MESH`;
  if (statusEl) {
    statusEl.textContent = `● live mesh · ${tiles.size} tile${tiles.size !== 1 ? "s" : ""}`;
    statusEl.style.color = "#2ec4b6";
  }
}
if (typeof document !== "undefined") {
  const onReady = () => {
    const canvas = document.getElementById("grid");
    const tickEl = document.getElementById("tick");
    if (!canvas || !tickEl)
      return;
    const statusEl = document.getElementById("bridge-status");
    const ctx = canvas.getContext("2d");
    const tiles = new Map;
    let localCtl = null;
    let meshTimer = null;
    const startLocalSim = () => {
      if (localCtl || meshTimer)
        return;
      localCtl = mount(canvas, tickEl);
      localCtl.play();
      if (statusEl) {
        statusEl.textContent = "○ local sim";
        statusEl.style.color = "#6b7a82";
      }
    };
    const switchToMesh = () => {
      if (meshTimer)
        return;
      if (localCtl) {
        localCtl.pause();
        localCtl = null;
      }
      meshTimer = setInterval(() => renderMeshFrame(ctx, canvas, tiles, tickEl, statusEl), 100);
      if (statusEl) {
        statusEl.textContent = "● live mesh · 1 tile";
        statusEl.style.color = "#2ec4b6";
      }
    };
    let es = null;
    const tryBridge = () => {
      if (meshTimer)
        return;
      if (es) {
        es.close();
        es = null;
      }
      if (statusEl && !localCtl) {
        statusEl.textContent = "checking bridge…";
        statusEl.style.color = "#6b7a82";
      }
      es = new EventSource(BRIDGE_URL);
      const fallbackTimer = setTimeout(() => {
        if (!meshTimer)
          startLocalSim();
      }, BRIDGE_TIMEOUT_MS);
      es.onmessage = (ev) => {
        clearTimeout(fallbackTimer);
        let tile;
        try {
          tile = JSON.parse(ev.data);
        } catch {
          return;
        }
        tiles.set(`${tile.tileX},${tile.tileY}`, tile);
        if (!meshTimer)
          switchToMesh();
      };
      es.onerror = () => {
        clearTimeout(fallbackTimer);
        if (!meshTimer)
          startLocalSim();
        setTimeout(tryBridge, 1e4);
      };
    };
    if (typeof EventSource !== "undefined") {
      tryBridge();
    } else {
      startLocalSim();
    }
    document.getElementById("play")?.addEventListener("click", () => {
      if (localCtl)
        localCtl.isPlaying() ? localCtl.pause() : localCtl.play();
    });
    document.getElementById("step")?.addEventListener("click", () => localCtl?.step());
    document.getElementById("reseed")?.addEventListener("click", () => localCtl?.reseed());
  };
  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", onReady);
  else
    onReady();
}
export {
  mount
};

```
