---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/demo/cell-journey.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.745468+00:00
---

# docs/demo/cell-journey.js

```js
// core/protocol-types/src/constants.ts
var CELL_SIZE = 1024;
var HEADER_SIZE = 256;
var PAYLOAD_SIZE = 768;
var HeaderOffsets = {
  cellCount: 86,
  cellCountSize: 4,
  domainPayloadRoot: 224,
  domainPayloadRootSize: 32,
  flags: 24,
  flagsSize: 4,
  linearity: 16,
  linearitySize: 4,
  magic: 0,
  magicSize: 16,
  ownerId: 62,
  ownerIdSize: 16,
  parentHash: 96,
  parentHashSize: 32,
  payloadTotal: 90,
  payloadTotalSize: 4,
  prevStateHash: 128,
  prevStateHashSize: 32,
  refCount: 28,
  refCountSize: 2,
  timestamp: 78,
  timestampSize: 8,
  typeHash: 30,
  typeHashSize: 32,
  version: 20,
  versionSize: 4
};

// core/protocol-types/src/cell-routing.ts
var RoutingRegionOffsets = {
  routingMode: 94,
  routingModeSize: 1,
  priority: 95,
  prioritySize: 1,
  routingVersion: 160,
  routingVersionSize: 4,
  routingFlags: 164,
  routingFlagsSize: 4,
  segmentsLeft: 168,
  segmentsLeftSize: 4,
  hopCountBudget: 172,
  hopCountBudgetSize: 4,
  flowLabel: 176,
  flowLabelSize: 8,
  nextHopBca: 184,
  nextHopBcaSize: 16,
  finalDestBca: 200,
  finalDestBcaSize: 16,
  routingChecksum: 216,
  routingChecksumSize: 4,
  routingReserved: 220,
  routingReservedSize: 4
};
var ROUTING_REGION_END = 224;
var ROUTING_CHECKSUM_COVERAGE_START = 160;
var ROUTING_CHECKSUM_COVERAGE_END = 216;
var RoutingMode = {
  UNROUTED: 0,
  SOURCE_ROUTED: 1,
  ANYCAST: 2,
  MULTICAST_PRUNED: 3
};
var RoutingFlag = {
  PRIORITY: 1 << 0,
  ANCHOR_ON_ARRIVAL: 1 << 1,
  BATCHABLE: 1 << 2,
  USES_PUSHDROP_PAYMENT: 1 << 3,
  PATH_MERKLE_OVERLOAD: 1 << 4,
  PATH_IN_PAYLOAD: 1 << 5
};
function readRoutingRegion(buf) {
  if (buf.length < ROUTING_REGION_END) {
    throw new Error(`Buffer too small for routing region: ${buf.length} bytes, need ${ROUTING_REGION_END}`);
  }
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  return {
    routingMode: buf[RoutingRegionOffsets.routingMode],
    priority: buf[RoutingRegionOffsets.priority],
    routingVersion: dv.getUint32(RoutingRegionOffsets.routingVersion, true),
    routingFlags: dv.getUint32(RoutingRegionOffsets.routingFlags, true),
    segmentsLeft: dv.getUint32(RoutingRegionOffsets.segmentsLeft, true),
    hopCountBudget: dv.getUint32(RoutingRegionOffsets.hopCountBudget, true),
    flowLabel: dv.getBigUint64(RoutingRegionOffsets.flowLabel, true),
    nextHopBca: buf.slice(RoutingRegionOffsets.nextHopBca, RoutingRegionOffsets.nextHopBca + RoutingRegionOffsets.nextHopBcaSize),
    finalDestBca: buf.slice(RoutingRegionOffsets.finalDestBca, RoutingRegionOffsets.finalDestBca + RoutingRegionOffsets.finalDestBcaSize),
    routingChecksum: dv.getUint32(RoutingRegionOffsets.routingChecksum, true)
  };
}
function writeRoutingRegion(buf, region) {
  if (buf.length < ROUTING_REGION_END) {
    throw new Error(`Buffer too small for routing region: ${buf.length} bytes, need ${ROUTING_REGION_END}`);
  }
  if (region.nextHopBca.length !== 16) {
    throw new Error(`nextHopBca must be 16 bytes, got ${region.nextHopBca.length}`);
  }
  if (region.finalDestBca.length !== 16) {
    throw new Error(`finalDestBca must be 16 bytes, got ${region.finalDestBca.length}`);
  }
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  buf[RoutingRegionOffsets.routingMode] = region.routingMode & 255;
  buf[RoutingRegionOffsets.priority] = region.priority & 255;
  dv.setUint32(RoutingRegionOffsets.routingVersion, region.routingVersion >>> 0, true);
  dv.setUint32(RoutingRegionOffsets.routingFlags, region.routingFlags >>> 0, true);
  dv.setUint32(RoutingRegionOffsets.segmentsLeft, region.segmentsLeft >>> 0, true);
  dv.setUint32(RoutingRegionOffsets.hopCountBudget, region.hopCountBudget >>> 0, true);
  dv.setBigUint64(RoutingRegionOffsets.flowLabel, region.flowLabel, true);
  buf.set(region.nextHopBca, RoutingRegionOffsets.nextHopBca);
  buf.set(region.finalDestBca, RoutingRegionOffsets.finalDestBca);
  dv.setUint32(RoutingRegionOffsets.routingChecksum, region.routingChecksum >>> 0, true);
}
var crc32Table = null;
function crc32TableInit() {
  if (crc32Table)
    return crc32Table;
  const t = new Uint32Array(256);
  for (let i = 0;i < 256; i++) {
    let c = i;
    for (let k = 0;k < 8; k++) {
      c = c & 1 ? 3988292384 ^ c >>> 1 : c >>> 1;
    }
    t[i] = c >>> 0;
  }
  crc32Table = t;
  return t;
}
function crc32(bytes) {
  const t = crc32TableInit();
  let c = 4294967295;
  for (let i = 0;i < bytes.length; i++) {
    c = t[(c ^ bytes[i]) & 255] ^ c >>> 8;
  }
  return (c ^ 4294967295) >>> 0;
}
function computeRoutingChecksum(buf) {
  return crc32(buf.subarray(ROUTING_CHECKSUM_COVERAGE_START, ROUTING_CHECKSUM_COVERAGE_END));
}
function setRoutingChecksum(buf) {
  const c = computeRoutingChecksum(buf);
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  dv.setUint32(RoutingRegionOffsets.routingChecksum, c >>> 0, true);
  return c;
}
function verifyRoutingChecksum(buf) {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  const stored = dv.getUint32(RoutingRegionOffsets.routingChecksum, true);
  const computed = computeRoutingChecksum(buf);
  return stored === computed;
}

// core/protocol-types/src/cell-pushdrop.ts
var OP_DROP = 117;
var OP_CHECKSIG = 172;
var OP_PUSHDATA1 = 76;
var OP_PUSHDATA2 = 77;
var OP_PUSHDATA4 = 78;
var COMPRESSED_PUBKEY_SIZE = 33;
var UNCOMPRESSED_PUBKEY_SIZE = 65;
function pushPrefix(dataLen) {
  if (dataLen < 0)
    throw new Error(`pushPrefix: negative length ${dataLen}`);
  if (dataLen <= 75) {
    return new Uint8Array([dataLen]);
  }
  if (dataLen <= 255) {
    return new Uint8Array([OP_PUSHDATA1, dataLen]);
  }
  if (dataLen <= 65535) {
    return new Uint8Array([OP_PUSHDATA2, dataLen & 255, dataLen >>> 8 & 255]);
  }
  return new Uint8Array([
    OP_PUSHDATA4,
    dataLen & 255,
    dataLen >>> 8 & 255,
    dataLen >>> 16 & 255,
    dataLen >>> 24 & 255
  ]);
}
function buildPushdropLockingScript(cellBytes, pubkey) {
  if (cellBytes.length === 0) {
    throw new Error(`buildPushdropLockingScript: cell must be non-empty`);
  }
  if (cellBytes.length > 65535) {
    throw new Error(`buildPushdropLockingScript: cell ${cellBytes.length} bytes exceeds PUSHDATA2 max (65535)`);
  }
  if (pubkey.length !== COMPRESSED_PUBKEY_SIZE && pubkey.length !== UNCOMPRESSED_PUBKEY_SIZE) {
    throw new Error(`buildPushdropLockingScript: pubkey must be ${COMPRESSED_PUBKEY_SIZE} or ${UNCOMPRESSED_PUBKEY_SIZE} bytes (got ${pubkey.length})`);
  }
  const cellPrefix = pushPrefix(cellBytes.length);
  const pubkeyPrefix = pushPrefix(pubkey.length);
  const total = cellPrefix.length + cellBytes.length + 1 + pubkeyPrefix.length + pubkey.length + 1;
  const out = new Uint8Array(total);
  let off = 0;
  out.set(cellPrefix, off);
  off += cellPrefix.length;
  out.set(cellBytes, off);
  off += cellBytes.length;
  out[off++] = OP_DROP;
  out.set(pubkeyPrefix, off);
  off += pubkeyPrefix.length;
  out.set(pubkey, off);
  off += pubkey.length;
  out[off++] = OP_CHECKSIG;
  return out;
}
var CANONICAL_CELL_PUSHDROP_SCRIPT_SIZE = 3 + 1024 + 1 + 1 + 33 + 1;

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

// core/protocol-types/src/mnca/cell-types.ts
var MncaCellTypeName = {
  SNAPSHOT: "mnca.snapshot",
  PERTURB: "mnca.perturb",
  TILE_INJECTION: "mnca.tile.injection",
  TILE_TICK: "mnca.tile.tick"
};
var MNCA_CELL_TYPE_NAMES = Object.freeze(Object.values(MncaCellTypeName));
var MncaTransformEdges = Object.freeze([
  [MncaCellTypeName.PERTURB, MncaCellTypeName.TILE_INJECTION],
  [MncaCellTypeName.TILE_INJECTION, MncaCellTypeName.TILE_TICK],
  [MncaCellTypeName.TILE_TICK, MncaCellTypeName.SNAPSHOT],
  [MncaCellTypeName.TILE_TICK, MncaCellTypeName.PERTURB]
]);
async function computeMncaTypeHash(name) {
  const data = new TextEncoder().encode(name);
  const digest = await globalThis.crypto.subtle.digest("SHA-256", data);
  return new Uint8Array(digest);
}

// core/protocol-types/src/mnca/cell-journey.ts
var ANCHOR_TXID = "a5277713454f17d746283f41158f39b26ac14debd11f7a719f866f872e23383c";
function hex(b) {
  let s = "";
  for (const x of b)
    s += x.toString(16).padStart(2, "0");
  return s;
}
function short(h, n = 10) {
  return h.length <= 2 * n ? h : `${h.slice(0, n)}…${h.slice(-n)}`;
}
async function buildCell() {
  const W = 27, H = 27, R = 3;
  const cells = new Uint8Array(W * H);
  for (let y = R;y < H - R; y++)
    for (let x = R;x < W - R; x++)
      cells[y * W + x] = Math.random() < 0.35 ? 255 : 0;
  let tile = { tileX: 3, tileY: 5, tick: 0n, width: W, height: H, haloRadius: R, flags: 0, cells };
  for (let i = 0;i < 6; i++)
    tile = stepTile(tile);
  const cell = new Uint8Array(CELL_SIZE);
  cell.set(await computeMncaTypeHash(MncaCellTypeName.SNAPSHOT), HeaderOffsets.typeHash);
  const ownerBca = new Uint8Array(16);
  for (let i = 0;i < 16; i++)
    ownerBca[i] = i * 17 + 3 & 255;
  cell.set(ownerBca, HeaderOffsets.ownerId);
  cell.set(encodeTilePayload(tile), HEADER_SIZE);
  const nextHop = new Uint8Array(16);
  nextHop.set([46, 196, 182]);
  const finalDest = new Uint8Array(16);
  finalDest.set([222, 173, 190, 239]);
  writeRoutingRegion(cell, {
    routingMode: RoutingMode.SOURCE_ROUTED,
    priority: 7,
    routingVersion: 1,
    routingFlags: RoutingFlag.PATH_IN_PAYLOAD | RoutingFlag.USES_PUSHDROP_PAYMENT,
    segmentsLeft: 2,
    hopCountBudget: 8,
    flowLabel: 0x5e_5e_0000_0001n,
    nextHopBca: nextHop,
    finalDestBca: finalDest,
    routingChecksum: 0
  });
  setRoutingChecksum(cell);
  return { cell, tile };
}
async function sha256Hex(b) {
  return hex(new Uint8Array(await crypto.subtle.digest("SHA-256", b)));
}
var ALIVE = 128;
function renderTile(canvas, tile) {
  const { width: W, height: H, haloRadius: R, cells } = tile;
  const I = W - 2 * R, px = 6;
  canvas.width = I * px;
  canvas.height = I * px;
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = "#0a0a0a";
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  for (let y = R;y < H - R; y++)
    for (let x = R;x < W - R; x++) {
      const v = cells[y * W + x];
      ctx.fillStyle = v >= ALIVE ? `rgb(46,${150 + (v - ALIVE) | 0 % 100},182)` : `rgb(${v / ALIVE * 30 | 0},${v / ALIVE * 34 | 0},${v / ALIVE * 40 | 0})`;
      ctx.fillRect((x - R) * px, (y - R) * px, px - 1, px - 1);
    }
}
function panel(layer, title, rows, canvas) {
  const d = document.createElement("div");
  d.className = "layer";
  const h = document.createElement("div");
  h.className = "lhead";
  h.innerHTML = `<span class="lnum">${layer}</span> ${title}`;
  d.appendChild(h);
  if (canvas)
    d.appendChild(canvas);
  for (const [k, v] of rows) {
    const r = document.createElement("div");
    r.className = "lrow";
    r.innerHTML = `<span class="k">${k}</span><span class="v">${v}</span>`;
    d.appendChild(r);
  }
  return d;
}
async function render(root) {
  const { cell, tile } = await buildCell();
  const addr = await sha256Hex(cell);
  const region = readRoutingRegion(cell);
  const typeHash = hex(cell.slice(HeaderOffsets.typeHash, HeaderOffsets.typeHash + 32));
  const ownerBca = hex(cell.slice(HeaderOffsets.ownerId, HeaderOffsets.ownerId + 16));
  const ownerPk = new Uint8Array(33);
  ownerPk[0] = 2;
  for (let i = 1;i < 33; i++)
    ownerPk[i] = i * 7 & 255;
  const pushdrop = buildPushdropLockingScript(cell, ownerPk);
  const addrBadge = `<span class="addr" title="SHA-256 of the 1024 cell bytes — identical in every layer">sha256 ${short(addr)}</span>`;
  const head = document.createElement("div");
  head.className = "cellhead";
  head.innerHTML = `<h1>One cell · six layers</h1>
    <p class="sub">A single 1024-byte canonical cell, never re-encoded. The same ${addrBadge} threads through every layer below — that identity is the layer-collapse thesis.</p>`;
  root.appendChild(head);
  const grid = document.createElement("div");
  grid.className = "layers";
  const tileCanvas = document.createElement("canvas");
  renderTile(tileCanvas, decodeTilePayload(cell.subarray(HEADER_SIZE)));
  grid.appendChild(panel("L1", "Storage", [
    ["size", `${CELL_SIZE} bytes`],
    ["content-addr", addrBadge],
    ["as", "NVS row (C6) · LMDB row (Pi) · file (Mac) · pushdrop data (BSV)"]
  ]));
  grid.appendChild(panel("L2", "Memory", [
    ["live bytes", `same ${CELL_SIZE} in SRAM / RAM`],
    ["content-addr", addrBadge],
    ["note", "cell-engine reads/writes these bytes in place — no parse boundary"]
  ]));
  grid.appendChild(panel("L3", "Network transport", [
    ["mode", region.routingMode === RoutingMode.SOURCE_ROUTED ? "source-routed" : String(region.routingMode)],
    ["next-hop BCA", short(hex(region.nextHopBca), 6)],
    ["final-dest BCA", short(hex(region.finalDestBca), 6)],
    ["segments-left", String(region.segmentsLeft)],
    ["flow-label", "0x" + region.flowLabel.toString(16)],
    ["CRC-32", verifyRoutingChecksum(cell) ? "✓ intact" : "✗"]
  ]));
  grid.appendChild(panel("L4", "Compute", [
    ["tile", `${tile.width - 2 * tile.haloRadius}×${tile.height - 2 * tile.haloRadius} · tick ${tile.tick}`],
    ["kernel", "stepTile (integer MNCA rule) — same on C6 / Pi / Mac"]
  ], tileCanvas));
  grid.appendChild(panel("L5", "Identity", [
    ["type-hash @30", short(typeHash, 8)],
    ["type", "mnca.snapshot"],
    ["owner BCA @62", short(ownerBca, 6)],
    ["note", "secp256k1 + BCA derivation (Ducroux) — same keys every tier"]
  ]));
  grid.appendChild(panel("L6", "Money", [
    ["pushdrop", `${pushdrop.length} B: <cell> OP_DROP <pk> OP_CHECKSIG`],
    ["on mainnet", `<a href="https://whatsonchain.com/tx/${ANCHOR_TXID}">${short(ANCHOR_TXID)}</a>`],
    ["note", "1-sat spendable UTXO · owner = recoverable BRC-42 leaf"]
  ]));
  root.appendChild(grid);
}
if (typeof document !== "undefined") {
  const go = () => {
    const root = document.getElementById("root");
    if (root)
      render(root);
  };
  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", go);
  else
    go();
}
export {
  render
};

```
