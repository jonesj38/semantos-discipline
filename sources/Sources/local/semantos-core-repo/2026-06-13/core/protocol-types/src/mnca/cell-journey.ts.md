---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/mnca/cell-journey.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.897766+00:00
---

# core/protocol-types/src/mnca/cell-journey.ts

```ts
/**
 * cell-journey.ts — the singularity demo's hero view (L1-I / L5-I / L6-I).
 *
 * One canonical 1024-byte cell, rendered across all six system layers —
 * storage, memory, network, compute, identity, money — every panel derived
 * from the SAME bytes. A content hash (SHA-256 of the cell) threads through
 * every panel header, making the layer-collapse thesis visible: the cell is
 * never decoded into a different representation; it IS the thing at each layer.
 *
 * Uses the canonical codecs (cell-routing, tile, cell-pushdrop, cell-types) so
 * what's shown is the real wire format, not a mock. Bundle with:
 *   bun build core/protocol-types/src/mnca/cell-journey.ts \
 *     --target=browser --outfile docs/demo/cell-journey.js
 */

import { HeaderOffsets, CELL_SIZE, HEADER_SIZE } from '../constants';
import {
  RoutingMode,
  RoutingFlag,
  writeRoutingRegion,
  readRoutingRegion,
  setRoutingChecksum,
  verifyRoutingChecksum,
} from '../cell-routing';
import { buildPushdropLockingScript } from '../cell-pushdrop';
import { encodeTilePayload, decodeTilePayload, stepTile, type TileState } from './tile';
import { MncaCellTypeName, MNCA_TRIPLES } from './cell-types';
import { buildTypeHash } from '../type-hash';

const ANCHOR_TXID = 'a5277713454f17d746283f41158f39b26ac14debd11f7a719f866f872e23383c';

function hex(b: Uint8Array): string {
  let s = '';
  for (const x of b) s += x.toString(16).padStart(2, '0');
  return s;
}
function short(h: string, n = 10): string {
  return h.length <= 2 * n ? h : `${h.slice(0, n)}…${h.slice(-n)}`;
}

/** Build a computed snapshot cell: seed a tile, advance it, wrap as a routed
 *  mnca.snapshot cell with an owner BCA + a 2-hop source route.
 *  (No longer async — buildTypeHash is sync; the legacy async signature
 *  was driven by computeMncaTypeHash's use of Web Crypto subtle.digest.) */
function buildCell(): { cell: Uint8Array; tile: TileState } {
  const W = 27, H = 27, R = 3;
  const cells = new Uint8Array(W * H);
  for (let y = R; y < H - R; y++)
    for (let x = R; x < W - R; x++) cells[y * W + x] = Math.random() < 0.35 ? 255 : 0;
  let tile: TileState = { tileX: 3, tileY: 5, tick: 0n, width: W, height: H, haloRadius: R, flags: 0, cells };
  for (let i = 0; i < 6; i++) tile = stepTile(tile); // compute a few generations

  const cell = new Uint8Array(CELL_SIZE);
  // L5 identity: typeHash (offset 30) + a 16-byte owner BCA (offset 62).
  const snapshotTriple = MNCA_TRIPLES[MncaCellTypeName.SNAPSHOT];
  cell.set(
    buildTypeHash(snapshotTriple[0], snapshotTriple[1], snapshotTriple[2], snapshotTriple[3]),
    HeaderOffsets.typeHash,
  );
  const ownerBca = new Uint8Array(16);
  for (let i = 0; i < 16; i++) ownerBca[i] = (i * 17 + 3) & 0xff;
  cell.set(ownerBca, HeaderOffsets.ownerId);
  // L4 compute: the tile state IS the payload.
  cell.set(encodeTilePayload(tile), HEADER_SIZE);
  // L3 network: a 2-hop source route.
  const nextHop = new Uint8Array(16); nextHop.set([0x2e, 0xc4, 0xb6]);
  const finalDest = new Uint8Array(16); finalDest.set([0xde, 0xad, 0xbe, 0xef]);
  writeRoutingRegion(cell, {
    routingMode: RoutingMode.SOURCE_ROUTED, priority: 7, routingVersion: 1,
    routingFlags: RoutingFlag.PATH_IN_PAYLOAD | RoutingFlag.USES_PUSHDROP_PAYMENT,
    segmentsLeft: 2, hopCountBudget: 8, flowLabel: 0x5e_5e_0000_0001n,
    nextHopBca: nextHop, finalDestBca: finalDest, routingChecksum: 0,
  });
  setRoutingChecksum(cell);
  return { cell, tile };
}

async function sha256Hex(b: Uint8Array): Promise<string> {
  return hex(new Uint8Array(await crypto.subtle.digest('SHA-256', b)));
}

const ALIVE = 128;
function renderTile(canvas: HTMLCanvasElement, tile: TileState): void {
  const { width: W, height: H, haloRadius: R, cells } = tile;
  const I = W - 2 * R, px = 6;
  canvas.width = I * px; canvas.height = I * px;
  const ctx = canvas.getContext('2d')!;
  ctx.fillStyle = '#0a0a0a'; ctx.fillRect(0, 0, canvas.width, canvas.height);
  for (let y = R; y < H - R; y++)
    for (let x = R; x < W - R; x++) {
      const v = cells[y * W + x]!;
      ctx.fillStyle = v >= ALIVE ? `rgb(46,${150 + (v - ALIVE) | 0 % 100},182)` : `rgb(${(v / ALIVE * 30) | 0},${(v / ALIVE * 34) | 0},${(v / ALIVE * 40) | 0})`;
      ctx.fillRect((x - R) * px, (y - R) * px, px - 1, px - 1);
    }
}

function panel(layer: string, title: string, rows: Array<[string, string]>, canvas?: HTMLCanvasElement): HTMLElement {
  const d = document.createElement('div'); d.className = 'layer';
  const h = document.createElement('div'); h.className = 'lhead';
  h.innerHTML = `<span class="lnum">${layer}</span> ${title}`;
  d.appendChild(h);
  if (canvas) d.appendChild(canvas);
  for (const [k, v] of rows) {
    const r = document.createElement('div'); r.className = 'lrow';
    r.innerHTML = `<span class="k">${k}</span><span class="v">${v}</span>`;
    d.appendChild(r);
  }
  return d;
}

export async function render(root: HTMLElement): Promise<void> {
  const { cell, tile } = buildCell();
  const addr = await sha256Hex(cell);
  const region = readRoutingRegion(cell);
  const typeHash = hex(cell.slice(HeaderOffsets.typeHash, HeaderOffsets.typeHash + 32));
  const ownerBca = hex(cell.slice(HeaderOffsets.ownerId, HeaderOffsets.ownerId + 16));
  const ownerPk = new Uint8Array(33); ownerPk[0] = 0x02;
  for (let i = 1; i < 33; i++) ownerPk[i] = (i * 7) & 0xff;
  const pushdrop = buildPushdropLockingScript(cell, ownerPk);

  // The through-line: the same content hash in every panel.
  const addrBadge = `<span class="addr" title="SHA-256 of the 1024 cell bytes — identical in every layer">sha256 ${short(addr)}</span>`;
  const head = document.createElement('div'); head.className = 'cellhead';
  head.innerHTML = `<h1>One cell · six layers</h1>
    <p class="sub">A single 1024-byte canonical cell, never re-encoded. The same ${addrBadge} threads through every layer below — that identity is the layer-collapse thesis.</p>`;
  root.appendChild(head);

  const grid = document.createElement('div'); grid.className = 'layers';
  const tileCanvas = document.createElement('canvas');
  renderTile(tileCanvas, decodeTilePayload(cell.subarray(HEADER_SIZE)));

  grid.appendChild(panel('L1', 'Storage', [
    ['size', `${CELL_SIZE} bytes`],
    ['content-addr', addrBadge],
    ['as', 'NVS row (C6) · LMDB row (Pi) · file (Mac) · pushdrop data (BSV)'],
  ]));
  grid.appendChild(panel('L2', 'Memory', [
    ['live bytes', `same ${CELL_SIZE} in SRAM / RAM`],
    ['content-addr', addrBadge],
    ['note', 'cell-engine reads/writes these bytes in place — no parse boundary'],
  ]));
  grid.appendChild(panel('L3', 'Network transport', [
    ['mode', region.routingMode === RoutingMode.SOURCE_ROUTED ? 'source-routed' : String(region.routingMode)],
    ['next-hop BCA', short(hex(region.nextHopBca), 6)],
    ['final-dest BCA', short(hex(region.finalDestBca), 6)],
    ['segments-left', String(region.segmentsLeft)],
    ['flow-label', '0x' + region.flowLabel.toString(16)],
    ['CRC-32', verifyRoutingChecksum(cell) ? '✓ intact' : '✗'],
  ]));
  grid.appendChild(panel('L4', 'Compute', [
    ['tile', `${tile.width - 2 * tile.haloRadius}×${tile.height - 2 * tile.haloRadius} · tick ${tile.tick}`],
    ['kernel', 'stepTile (integer MNCA rule) — same on C6 / Pi / Mac'],
  ], tileCanvas));
  grid.appendChild(panel('L5', 'Identity', [
    ['type-hash @30', short(typeHash, 8)],
    ['type', 'mnca.snapshot'],
    ['owner BCA @62', short(ownerBca, 6)],
    ['note', 'secp256k1 + BCA derivation (Ducroux) — same keys every tier'],
  ]));
  grid.appendChild(panel('L6', 'Money', [
    ['pushdrop', `${pushdrop.length} B: <cell> OP_DROP <pk> OP_CHECKSIG`],
    ['on mainnet', `<a href="https://whatsonchain.com/tx/${ANCHOR_TXID}">${short(ANCHOR_TXID)}</a>`],
    ['note', '1-sat spendable UTXO · owner = recoverable BRC-42 leaf'],
  ]));
  root.appendChild(grid);
}

if (typeof document !== 'undefined') {
  const go = () => {
    const root = document.getElementById('root');
    if (root) void render(root);
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', go);
  else go();
}

```
