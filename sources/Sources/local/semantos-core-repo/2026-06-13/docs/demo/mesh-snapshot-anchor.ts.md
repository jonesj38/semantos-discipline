---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/demo/mesh-snapshot-anchor.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.747579+00:00
---

# docs/demo/mesh-snapshot-anchor.ts

```ts
#!/usr/bin/env bun
/**
 * mesh-snapshot-anchor.ts — periodic grid-snapshot anchor for the MNCA demo.
 *
 * Reads the current live tiles from mesh-bridge (:4400/tiles) every
 * ANCHOR_INTERVAL_MS, packs a 1024-byte grid-snapshot cell, and
 * BUILDS (but does NOT broadcast) a pushdrop anchor tx — exactly the
 * same pushdrop structure the proven mainnet anchor uses.
 *
 * BUILD + DRY-RUN ONLY:
 *   • A throwaway secp256k1 key is generated at startup (never stored).
 *   • The funding UTXO is synthetic (random txid); the tx can never be
 *     broadcast without a real funded UTXO.
 *   • No private keys are printed or committed.
 *   • The OPERATOR broadcasts via browser wallet (wallet.html anchor panel).
 *
 * Endpoints (CORS-open):
 *   GET /anchor-preview  — latest dry-run anchor result (txid, WoC URL, cell hex)
 *
 * Run:
 *   bun docs/demo/mesh-snapshot-anchor.ts
 *
 * Env:
 *   BRIDGE_URL      (http://localhost:4400)
 *   ANCHOR_PORT     (4401)
 *   ANCHOR_INTERVAL_MS  (30000)
 */

import * as secp from '@noble/secp256k1';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';
import { hmac } from '@noble/hashes/hmac';
import { randomBytes } from 'node:crypto';

// Wire secp's HMAC-SHA256 implementation
secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

// Imports from the PROVEN wallet primitives (same path as test-mnca-anchor.ts).
const WALLET_SRC = new URL(
  '../../cartridges/wallet-headers/brain/src',
  import.meta.url,
).pathname;

const { buildAnchorTx } = await import(`${WALLET_SRC}/mesh-bsv-sink.ts`);
const { encodeDer }     = await import(`${WALLET_SRC}/der.ts`);
const { hexFromBytes, reverseTxid } = await import(`${WALLET_SRC}/beef-codec.ts`);

// ── Config ─────────────────────────────────────────────────────────────────

const BRIDGE_BASE   = process.env.BRIDGE_URL  ?? 'http://localhost:4400';
const HTTP_PORT     = Number(process.env.ANCHOR_PORT ?? 4401);
const INTERVAL_MS   = Number(process.env.ANCHOR_INTERVAL_MS ?? 30_000);
const CELL_SIZE     = 1024;
const ANCHOR_SATS   = 1n;
const FEE_SATS      = 1200n;
const TYPE_HASH_OFF = 30;

// ── Snapshot cell format ───────────────────────────────────────────────────
// [0]     version = 1
// [1]     numTiles
// [2]     gridCols
// [3]     gridRows
// [4..7]  latestTick (uint32 LE)
// [8..15] unixTimeSec (uint64 LE)
// [16..29] reserved
// [30..61] typeHash = SHA-256("mnca.snapshot.grid")
// [62]    interiorW   (tile width - 2*halo)
// [63]    interiorH   (tile height - 2*halo)
// [64..]  tile interior cells packed sequentially by (tileY,tileX) coord order

const TYPE_HASH = nobleSha256(new TextEncoder().encode('mnca.snapshot.grid'));

interface BridgeTile {
  tileX: number; tileY: number; tick: number;
  width: number; height: number; halo: number;
  cells: number[];
}

function packSnapshotCell(tiles: BridgeTile[]): Uint8Array {
  if (tiles.length === 0) throw new Error('no tiles to pack');
  const maxTX = Math.max(...tiles.map(t => t.tileX));
  const maxTY = Math.max(...tiles.map(t => t.tileY));
  const cols  = maxTX + 1;
  const rows  = maxTY + 1;
  const t0 = tiles[0]!;
  const iW  = t0.width  - 2 * t0.halo;
  const iH  = t0.height - 2 * t0.halo;
  const latestTick = Math.max(...tiles.map(t => t.tick));
  const byCoord = new Map<string, BridgeTile>();
  for (const t of tiles) byCoord.set(`${t.tileX},${t.tileY}`, t);

  const cell = new Uint8Array(CELL_SIZE);
  const dv   = new DataView(cell.buffer);
  // Header
  cell[0] = 1;              // version
  cell[1] = tiles.length;
  cell[2] = cols;
  cell[3] = rows;
  dv.setUint32(4,  latestTick,         true);
  dv.setBigUint64(8, BigInt(Math.floor(Date.now() / 1000)), true);
  // typeHash
  cell.set(TYPE_HASH, TYPE_HASH_OFF);
  // Interior size
  cell[62] = iW;
  cell[63] = iH;
  // Cell data: scan tiles in row-major coord order
  let off = 64;
  for (let ty = 0; ty < rows; ty++) {
    for (let tx = 0; tx < cols; tx++) {
      const tile = byCoord.get(`${tx},${ty}`);
      if (!tile) continue;
      for (let y = tile.halo; y < tile.height - tile.halo; y++) {
        for (let x = tile.halo; x < tile.width - tile.halo; x++) {
          if (off >= CELL_SIZE) break;
          cell[off++] = tile.cells[y * tile.width + x] ?? 0;
        }
      }
    }
  }
  return cell;
}

// ── Throwaway demo key (not stored, not printed) ───────────────────────────

const demoSk  = secp.utils.randomPrivateKey();
const demoPk  = secp.getPublicKey(demoSk, true);

// Pushdrop lock: <cell> OP_DROP <ownerPk> OP_CHECKSIG
function pushdropLock(cell: Uint8Array, ownerPk: Uint8Array): Uint8Array {
  const out: number[] = [0x4d, cell.length & 0xff, (cell.length >> 8) & 0xff]; // PUSHDATA2
  for (const b of cell) out.push(b);
  out.push(0x75); // OP_DROP
  out.push(ownerPk.length);
  for (const b of ownerPk) out.push(b);
  out.push(0xac); // OP_CHECKSIG
  return new Uint8Array(out);
}

// ── Anchor preview state ───────────────────────────────────────────────────

interface AnchorPreview {
  ok: boolean;
  dryRun: true;
  builtAt: string;   // ISO timestamp
  numTiles: number;
  latestTick: number;
  txid: string;      // display hex (the tx that WOULD anchor the snapshot)
  wocUrl: string;    // https://whatsonchain.com/tx/<txid>
  cellHex: string;   // first 64 bytes (header + typeHash) as hex
  anchorSats: number;
  feeSats: number;
  message: string;
}

let latest: AnchorPreview | null = null;

async function buildSnapshotPreview(): Promise<void> {
  let tiles: BridgeTile[];
  try {
    const res = await fetch(`${BRIDGE_BASE}/tiles`, { signal: AbortSignal.timeout(3000) });
    if (!res.ok) { console.error(`anchor: bridge /tiles returned ${res.status}`); return; }
    tiles = await res.json() as BridgeTile[];
  } catch (e) { console.error('anchor: bridge unreachable —', (e as Error).message); return; }

  if (tiles.length === 0) { console.log('anchor: no tiles yet — skipping'); return; }

  // Pack snapshot cell
  let cell: Uint8Array;
  try { cell = packSnapshotCell(tiles); }
  catch (e) { console.error('anchor: packSnapshotCell failed —', (e as Error).message); return; }

  // Build anchor tx (DRY-RUN: synthetic funding UTXO — random txid, no funds)
  const lockingScript = pushdropLock(cell, demoPk);
  const fakeTxid = new Uint8Array(randomBytes(32));
  const funder = {
    pubkey: demoPk,
    signSighash: (sighash: Uint8Array): Uint8Array => {
      const sig = secp.sign(sighash, demoSk).normalizeS();
      return encodeDer(sig.r, sig.s);
    },
  };

  let anchorTx: { efTx: Uint8Array; rawTx: Uint8Array; txid: Uint8Array; changeSats: bigint };
  try {
    anchorTx = buildAnchorTx({
      anchor:  { lockingScript, satoshis: ANCHOR_SATS },
      funding: { txid: fakeTxid, vout: 0, value: ANCHOR_SATS + FEE_SATS },
      funder,
      feeSats: FEE_SATS,
    });
  } catch (e) { console.error('anchor: buildAnchorTx failed —', (e as Error).message); return; }

  const txidHex = hexFromBytes(reverseTxid(anchorTx.txid));
  const latestTick = Math.max(...tiles.map(t => t.tick));
  latest = {
    ok: true, dryRun: true,
    builtAt: new Date().toISOString(),
    numTiles: tiles.length,
    latestTick,
    txid: txidHex,
    wocUrl: `https://whatsonchain.com/tx/${txidHex}`,
    cellHex: hexFromBytes(cell.subarray(0, 64)),
    anchorSats: Number(ANCHOR_SATS),
    feeSats: Number(FEE_SATS),
    message:
      `DRY-RUN — snapshot built: ${tiles.length} tiles · tick ${latestTick} · ` +
      `anchor ${ANCHOR_SATS} sats · fee ${FEE_SATS} sats. ` +
      `Broadcast via browser wallet (wallet.html anchor panel) to make the WoC link live.`,
  };
  console.log(`anchor: snapshot built — ${tiles.length} tiles tick=${latestTick} txid=${txidHex.slice(0, 16)}…`);
}

// ── HTTP server ────────────────────────────────────────────────────────────

const cors = { 'Access-Control-Allow-Origin': '*' };

Bun.serve({
  port: HTTP_PORT,
  fetch(req) {
    const url = new URL(req.url);
    if (url.pathname === '/anchor-preview') {
      if (!latest) {
        return Response.json({ ok: false, message: 'no preview built yet — bridge may not be running' }, { headers: cors });
      }
      return Response.json(latest, { headers: cors });
    }
    return new Response('mesh-snapshot-anchor — GET /anchor-preview', { headers: cors });
  },
});
console.log(`mesh-snapshot-anchor: HTTP on http://localhost:${HTTP_PORT}  (/anchor-preview)`);
console.log(`  BRIDGE: ${BRIDGE_BASE}  INTERVAL: ${INTERVAL_MS}ms  (dry-run, no broadcast)`);

// ── Periodic snapshot loop ─────────────────────────────────────────────────
// Wait 5 s for the bridge to populate before the first build, then retry
// every 5 s until we get tiles, then switch to the configured interval.

async function runLoop(): Promise<void> {
  // Initial wait — bridge needs a moment to join multicast + receive first tiles.
  await Bun.sleep(5000);
  await buildSnapshotPreview();
  if (!latest) {
    // Retry every 5 s until first successful build.
    const id = setInterval(async () => {
      await buildSnapshotPreview();
      if (latest) clearInterval(id);
    }, 5000);
    // Give it up to 60 s total, then switch to normal cadence regardless.
    await Bun.sleep(60_000);
    clearInterval(id);
  }
  // Normal cadence.
  setInterval(buildSnapshotPreview, INTERVAL_MS);
}

runLoop();

// Keep alive
await new Promise<void>(() => { /* wait for SIGINT */ });

```
