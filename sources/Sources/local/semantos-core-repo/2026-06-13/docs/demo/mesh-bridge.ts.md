---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/demo/mesh-bridge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.746531+00:00
---

# docs/demo/mesh-bridge.ts

```ts
// mesh-bridge.ts — bridge the U.2 IPv6 multicast mesh to the browser.
//
// Joins the mesh multicast group, decodes MNCA tile broadcasts (cell_sync
// datagrams whose payload is a 768-byte tile), keeps the latest tile per
// (tileX,tileY), and serves them live to the webview over SSE. This is what
// makes docs/demo/mnca-grid.html show the REAL distributed mesh instead of a
// local simulation.
//
// HMAC is NOT verified here — this is a trusted-loopback demo bridge, not a
// consensus participant. (The mesh nodes verify each other; the bridge is a
// read-only observer.)
//
// Run:  bun docs/demo/mesh-bridge.ts
// Env:  MCAST_GROUP (ff15::5e:1)  MCAST_PORT (47100)  MCAST_IFACE (e.g. lo0)
//       BRIDGE_PORT (4400)
//       RELAY_PORT  — when set, ALSO bind a localhost UDP socket on this port
//                     to receive raw datagrams from mcast-relay.py (needed when
//                     Bun's addMembership doesn't join on the right IPv6 iface).
//
// Endpoints (CORS-open so the demo page on another port can read them):
//   GET /tiles   → JSON array of the current tiles
//   GET /events  → text/event-stream; one `data: {tile}` per broadcast

import dgram from 'node:dgram';

const GROUP = process.env.MCAST_GROUP ?? 'ff15::5e:1';
const MCAST_PORT = Number(process.env.MCAST_PORT ?? 47100);
const IFACE = process.env.MCAST_IFACE; // interface name/scope for IPv6 membership
const HTTP_PORT = Number(process.env.BRIDGE_PORT ?? 4400);
/** When set, bind a second UDP4 socket on localhost:RELAY_PORT to receive
 *  datagrams forwarded by mcast-relay.py (workaround for Bun IPv6 join). */
const RELAY_PORT = process.env.RELAY_PORT ? Number(process.env.RELAY_PORT) : null;

// udp_protocol framing (see runtime/semantos-brain/src/udp_protocol.zig)
const OFFSET_PAYLOAD = 49;
const HMAC_LEN = 32;
const TYPE_CELL_SYNC = 0x01;
const TILE_SIZE = 768;
const CELL_SIZE = 1024;
const CELL_HEADER_SIZE = 256; // matches mnca_cell.zig HEADER_SIZE
// tile header offsets within the payload (see core/protocol-types/src/mnca/tile.ts)
const OFF_TILE_X = 0, OFF_TILE_Y = 2, OFF_TICK = 4, OFF_WIDTH = 12, OFF_HEIGHT = 13, OFF_HALO = 14, OFF_STATE = 16;

// Cell header offsets (D-SRS-typed-cell; matches mnca_cell.zig + constants.ts).
const CELL_OFF_TYPE_HASH = 30; // 32 bytes: SHA-256("mnca.tile.tick")
const MNCA_TILE_TICK_TYPE_HASH = 'd2182b60a63e3646a75f9b4b2a1cd771d52e0ab913566a6dd84b78af7edbf519';

export interface DecodedTile {
  tileX: number; tileY: number; tick: number;
  width: number; height: number; halo: number;
  cells: number[]; // row-major, width*height, 0..255
  /** If the tile arrived in a 1024-byte typed cell, its typeHash hex. */
  typeHash?: string;
}

/** Decode a 768-byte tile payload into a JSON-friendly tile. */
export function decodeTile(p: Uint8Array, typeHash?: string): DecodedTile {
  const dv = new DataView(p.buffer, p.byteOffset, p.byteLength);
  const width = p[OFF_WIDTH]!;
  const height = p[OFF_HEIGHT]!;
  return {
    tileX: dv.getUint16(OFF_TILE_X, true),
    tileY: dv.getUint16(OFF_TILE_Y, true),
    tick: Number(dv.getBigUint64(OFF_TICK, true)),
    width, height,
    halo: p[OFF_HALO]!,
    cells: Array.from(p.subarray(OFF_STATE, OFF_STATE + width * height)),
    ...(typeHash ? { typeHash } : {}),
  };
}

/** Hex-encode a byte slice. */
function toHex(b: Uint8Array): string {
  return Array.from(b).map(x => x.toString(16).padStart(2, '0')).join('');
}

/** Extract a tile from a raw datagram, or null if it isn't a tile cell_sync.
 *
 * Handles two payload formats (D-SRS-typed-cell):
 *   payload.length === 768  → plain tile (legacy, backward-compat)
 *   payload.length === 1024 → typed cell (256-byte Semantos header + 768-byte tile)
 *     The bridge validates the typeHash = SHA-256("mnca.tile.tick") and strips
 *     the header before decoding — the SSE stream carries the typeHash field so
 *     the viz can show cell identity.
 */
export function tileFromDatagram(msg: Uint8Array): DecodedTile | null {
  if (msg.length < OFFSET_PAYLOAD + HMAC_LEN + TILE_SIZE) return null;
  if (msg[0] !== TYPE_CELL_SYNC) return null;
  const payload = msg.subarray(OFFSET_PAYLOAD, msg.length - HMAC_LEN);
  if (payload.length < TILE_SIZE) return null;

  try {
    // D-SRS-typed-cell: 1024-byte typed cell payload.
    if (payload.length >= CELL_SIZE) {
      const typeHash = toHex(payload.subarray(CELL_OFF_TYPE_HASH, CELL_OFF_TYPE_HASH + 32));
      // Only decode tiles whose typeHash matches mnca.tile.tick.
      if (typeHash === MNCA_TILE_TICK_TYPE_HASH) {
        const tilePart = payload.subarray(CELL_HEADER_SIZE, CELL_HEADER_SIZE + TILE_SIZE);
        if (tilePart[OFF_WIDTH]! > 0 && tilePart[OFF_HEIGHT]! > 0)
          return decodeTile(tilePart, typeHash);
      }
      // Unknown typed cell — ignore (don't fall through to 768-byte decode).
      return null;
    }
    // Legacy: plain 768-byte tile.
    return decodeTile(payload.subarray(0, TILE_SIZE));
  } catch {
    return null;
  }
}

// Only start the server/socket when run directly (not when imported by a test).
if (import.meta.main) {
  const tiles = new Map<string, DecodedTile>();
  const clients = new Set<(data: string) => void>();

  /** Process a raw datagram from any source (multicast socket or relay). */
  const onDatagram = (msg: Buffer): void => {
    const tile = tileFromDatagram(new Uint8Array(msg));
    if (!tile) return;
    tiles.set(`${tile.tileX},${tile.tileY}`, tile);
    const json = JSON.stringify(tile);
    for (const send of clients) send(json);
  };

  const sock = dgram.createSocket({ type: 'udp6', reuseAddr: true });
  sock.on('error', (e) => console.error('socket error:', e.message));
  sock.on('message', onDatagram);
  sock.bind(MCAST_PORT, () => {
    try {
      sock.addMembership(GROUP, IFACE);
      console.log(`mesh-bridge: joined ${GROUP}:${MCAST_PORT}${IFACE ? ` on ${IFACE}` : ''}`);
    } catch (e) {
      console.error(`addMembership failed (${(e as Error).message}) — set MCAST_IFACE (e.g. lo0)`);
    }
  });

  // Relay socket: receives raw datagrams forwarded by mcast-relay.py on
  // localhost. Used when Bun's IPv6 addMembership doesn't bind the right iface
  // (e.g. on macOS with a non-default interface like a USB-Ethernet adapter).
  if (RELAY_PORT) {
    const relay = dgram.createSocket({ type: 'udp4', reuseAddr: true });
    relay.on('error', (e) => console.error('relay socket error:', e.message));
    relay.on('message', onDatagram);
    relay.bind(RELAY_PORT, '127.0.0.1', () =>
      console.log(`mesh-bridge: relay socket on 127.0.0.1:${RELAY_PORT} (mcast-relay.py → bridge)`));
  }

  const cors = { 'Access-Control-Allow-Origin': '*' };
  Bun.serve({
    port: HTTP_PORT,
    fetch(req) {
      const url = new URL(req.url);
      if (url.pathname === '/tiles') {
        return Response.json([...tiles.values()], { headers: cors });
      }
      if (url.pathname === '/events') {
        let send!: (data: string) => void;
        const stream = new ReadableStream<Uint8Array>({
          start(controller) {
            const enc = new TextEncoder();
            send = (data) => { try { controller.enqueue(enc.encode(`data: ${data}\n\n`)); } catch { /* closed */ } };
            for (const t of tiles.values()) send(JSON.stringify(t)); // initial snapshot
            clients.add(send);
          },
          cancel() { clients.delete(send); },
        });
        return new Response(stream, {
          headers: { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive', ...cors },
        });
      }
      return new Response('mesh-bridge — GET /tiles or /events', { headers: cors });
    },
  });
  console.log(`mesh-bridge: HTTP on http://localhost:${HTTP_PORT}  (/tiles, /events)`);
}

```
