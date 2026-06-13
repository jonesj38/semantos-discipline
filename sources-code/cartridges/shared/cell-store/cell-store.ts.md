---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/cell-store/cell-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.434838+00:00
---

# cartridges/shared/cell-store/cell-store.ts

```ts
#!/usr/bin/env bun
/**
 * cell-store.ts — Skyminer mesh cell persistence service
 *
 * Subscribes to the multicast relay's /cells/recent endpoint (polling every
 * 2 seconds) and persists each unique cell into a local SQLite database.
 * Designed to run on each Orange Pi node, giving every node a local cache of
 * the cells it has seen flow through the mesh — the "storage layer" of the
 * layer-collapse demo.
 *
 * On a Pi: bun cell-store.ts --relay http://laptop-ip:5199 --port 5197
 * Locally: bun cartridges/shared/cell-store/cell-store.ts
 *
 * HTTP :5197
 *   GET /cells              paginated cell list (newest first)
 *   GET /cells/:cellId      full cell record
 *   GET /cells/stats        summary: total, byTypePath, oldestTs, newestTs
 *   GET /cells/stream       SSE — pushes CanonicalCellHeader on each new cell
 *   GET /health             { ok, cellCount, relayUrl, nodeId }
 */

import { Database } from 'bun:sqlite';
import { createHash } from 'node:crypto';

// ── Config ────────────────────────────────────────────────────────────────────

const args    = process.argv.slice(2);
const flag    = (f: string) => { const i = args.indexOf(f); return i !== -1 ? args[i + 1] : undefined; };

const HTTP_PORT  = parseInt(flag('--port')   ?? process.env.CELL_STORE_PORT  ?? '5197', 10);
const RELAY_URL  = flag('--relay')           ?? process.env.CELL_STORE_RELAY ?? 'http://localhost:5199';
const DB_PATH    = flag('--db')              ?? process.env.CELL_STORE_DB    ?? './cell-store.sqlite';
const POLL_MS    = parseInt(flag('--poll-ms') ?? '2000', 10);

// Stable node ID: SHA-256(hostname + port)[0:8]
import { hostname } from 'node:os';
const NODE_ID = createHash('sha256')
  .update(`${hostname()}:${HTTP_PORT}`)
  .digest('hex').slice(0, 8);

// ── Database ──────────────────────────────────────────────────────────────────

const db = new Database(DB_PATH);

db.run(`CREATE TABLE IF NOT EXISTS cells (
  cell_id     TEXT PRIMARY KEY,
  type_path   TEXT NOT NULL,
  sender_fp   TEXT NOT NULL,
  seq         INTEGER NOT NULL DEFAULT 0,
  payload_len INTEGER NOT NULL DEFAULT 0,
  received_at INTEGER NOT NULL,
  payload     TEXT            -- hex-encoded bytes, may be NULL if header-only
)`);

db.run(`CREATE INDEX IF NOT EXISTS idx_cells_type  ON cells(type_path)`);
db.run(`CREATE INDEX IF NOT EXISTS idx_cells_ts    ON cells(received_at DESC)`);
db.run(`CREATE INDEX IF NOT EXISTS idx_cells_sender ON cells(sender_fp)`);

const stmtInsert = db.prepare(`
  INSERT OR IGNORE INTO cells(cell_id, type_path, sender_fp, seq, payload_len, received_at, payload)
  VALUES ($cellId, $typePath, $senderFp, $seq, $payloadLen, $receivedAt, $payload)
`);

const stmtList = db.prepare(`
  SELECT cell_id, type_path, sender_fp, seq, payload_len, received_at
  FROM cells ORDER BY received_at DESC LIMIT $limit OFFSET $offset
`);

const stmtListByType = db.prepare(`
  SELECT cell_id, type_path, sender_fp, seq, payload_len, received_at
  FROM cells WHERE type_path = $typePath
  ORDER BY received_at DESC LIMIT $limit OFFSET $offset
`);

const stmtCountByType = db.prepare(`
  SELECT COUNT(*) AS n FROM cells WHERE type_path = $typePath
`);

const stmtGet = db.prepare(`
  SELECT * FROM cells WHERE cell_id = $cellId
`);

const stmtStats = db.prepare(`
  SELECT
    COUNT(*)                AS total,
    COUNT(DISTINCT sender_fp) AS unique_senders,
    MIN(received_at)        AS oldest_ts,
    MAX(received_at)        AS newest_ts
  FROM cells
`);

const stmtByType = db.prepare(`
  SELECT type_path, COUNT(*) AS count FROM cells GROUP BY type_path ORDER BY count DESC
`);

const stmtRate60s = db.prepare(`
  SELECT COUNT(*) AS n FROM cells WHERE received_at > ($now - 60000)
`);

// ── SSE clients ───────────────────────────────────────────────────────────────

const sseClients = new Set<ReadableStreamController<Uint8Array>>();
const _sseEnc = new TextEncoder();
const _ssePing = _sseEnc.encode(': ping\n\n');

function broadcastCell(header: object) {
  const msg = _sseEnc.encode(`event: cell\ndata: ${JSON.stringify(header)}\n\n`);
  for (const ctrl of sseClients) {
    try { ctrl.enqueue(msg); } catch { sseClients.delete(ctrl); }
  }
}

// Keep-alive: send a comment ping every 25 seconds to prevent proxy/browser
// timeouts when the mesh is quiet (e.g., MNCA injector paused, channel settling).
setInterval(() => {
  for (const ctrl of sseClients) {
    try { ctrl.enqueue(_ssePing); } catch { sseClients.delete(ctrl); }
  }
}, 25_000);

// ── Relay ingestion — shared cell-processing logic ───────────────────────────

const lastSeenIds = new Set<string>();
let pollErrors = 0;
let lastPollTs = 0;
let sseConnected = false;  // true when relay SSE stream is live

interface CellHeader {
  cellId: string; typePath: string; senderFp: string;
  seq: number; payloadLen: number; ts?: number;
}

/** Persist a single cell + broadcast to downstream SSE clients. Deduplicates. */
function ingestCell(c: CellHeader, hexPayload: string | null) {
  if (lastSeenIds.has(c.cellId)) return;
  lastSeenIds.add(c.cellId);
  // Keep dedup set bounded (>2× relay ring size avoids re-insert on ring overlap)
  if (lastSeenIds.size > 300) {
    const iter = lastSeenIds.values();
    for (let i = 0; i < 50; i++) lastSeenIds.delete(iter.next().value);
  }

  stmtInsert.run({
    $cellId:     c.cellId,
    $typePath:   c.typePath,
    $senderFp:   c.senderFp,
    $seq:        c.seq,
    $payloadLen: c.payloadLen,
    $receivedAt: c.ts ?? Date.now(),
    $payload:    hexPayload,
  });

  broadcastCell({
    cellId:     c.cellId,
    typePath:   c.typePath,
    senderFp:   c.senderFp,
    seq:        c.seq,
    payloadLen: c.payloadLen,
    ts:         c.ts,
    nodeId:     NODE_ID,
    hasPayload: hexPayload !== null,
  });
}

// ── Primary feed: relay SSE (GET /cells/stream) ───────────────────────────────
// Subscribes to the relay's SSE push stream for near-zero-lag cell ingestion.
// Falls back to polling on disconnect/error; retries SSE after 5s.

async function connectRelaySSE(): Promise<void> {
  const url = `${RELAY_URL}/cells/stream`;
  try {
    // Timeout only the initial connection; once headers arrive, read indefinitely.
    // AbortSignal.timeout() on the full fetch would kill the stream body after the
    // deadline — wrong for a long-lived SSE connection.
    const connCtrl    = new AbortController();
    const connTimeout = setTimeout(() => connCtrl.abort(), 8000);
    let r: Response;
    try {
      r = await fetch(url, { headers: { Accept: 'text/event-stream' }, signal: connCtrl.signal });
    } finally {
      clearTimeout(connTimeout);
    }
    if (!r.ok || !r.body) throw new Error(`HTTP ${r.status}`);

    sseConnected = true;
    console.log(`[cell-store] SSE connected to relay ${url}`);

    const reader = r.body.getReader();
    const dec    = new TextDecoder();
    let buf = '';
    let eventType = 'message';
    let dataLines: string[] = [];

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      const parts = buf.split('\n');
      buf = parts.pop()!;  // hold incomplete last line

      for (const line of parts) {
        if (line.startsWith('event: ')) {
          eventType = line.slice(7).trim();
        } else if (line.startsWith('data: ')) {
          dataLines.push(line.slice(6));
        } else if (line === '' && dataLines.length > 0) {
          // Dispatch event
          if (eventType === 'cell') {
            try {
              const { header, payload } = JSON.parse(dataLines.join('\n')) as
                { header: CellHeader; payload: string | null };
              if (header?.cellId) ingestCell(header, payload ?? null);
            } catch { /* malformed event — skip */ }
          }
          eventType  = 'message';
          dataLines  = [];
        }
      }
    }
  } catch (e: any) {
    if (sseConnected) {
      console.warn(`[cell-store] SSE disconnected: ${e.message} — polling fallback active`);
    }
    sseConnected = false;
  }
  // Retry SSE after a back-off
  setTimeout(connectRelaySSE, 5000);
}

// ── Fallback: polling /cells/recent ──────────────────────────────────────────
// Active while SSE is not connected. Once SSE establishes, polls still run but
// serve only as a catch-up net (dedup prevents double-counting).

async function pollRelay() {
  try {
    const r = await fetch(`${RELAY_URL}/cells/recent`, { signal: AbortSignal.timeout(3000) });
    if (!r.ok) { pollErrors++; return; }

    // Support both ring formats:
    //   new: { header: CanonicalCellHeader, payload: string|null }
    //   old: flat CanonicalCellHeader (backward compat with old relay)
    const j = await r.json() as { cells: Array<
      | { header: CellHeader; payload: string | null }
      | CellHeader
    > };

    pollErrors = 0;
    lastPollTs = Date.now();

    for (const entry of j.cells ?? []) {
      const c          = 'header' in entry ? entry.header : entry;
      const hexPayload = 'header' in entry ? (entry.payload ?? null) : null;
      ingestCell(c, hexPayload);
    }
  } catch {
    pollErrors++;
  }
}

// Start both: SSE (primary) + polling (fallback / catch-up)
connectRelaySSE();
setInterval(pollRelay, POLL_MS);
pollRelay();

// ── CORS ──────────────────────────────────────────────────────────────────────

const CORS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

function json(data: unknown, status = 200) {
  return Response.json(data, { status, headers: CORS });
}

// ── HTTP server ───────────────────────────────────────────────────────────────

Bun.serve({
  port: HTTP_PORT,

  fetch(req) {
    const url = new URL(req.url);
    const { method, pathname } = { method: req.method, pathname: url.pathname };

    if (method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });

    // ── GET /health
    if (method === 'GET' && pathname === '/health') {
      const stats = db.prepare('SELECT COUNT(*) AS n FROM cells').get() as { n: number };
      return json({
        ok:           true,
        nodeId:       NODE_ID,
        cellCount:    stats.n,
        relayUrl:     RELAY_URL,
        sseConnected,
        pollErrors,
        lastPollTs,
      });
    }

    // ── GET /cells/stats
    if (method === 'GET' && pathname === '/cells/stats') {
      const s  = stmtStats.get() as { total: number; unique_senders: number; oldest_ts: number | null; newest_ts: number | null };
      const bt = stmtByType.all() as Array<{ type_path: string; count: number }>;
      const byTypePath: Record<string, number> = {};
      for (const r of bt) byTypePath[r.type_path] = r.count;
      const rate = stmtRate60s.get({ $now: Date.now() }) as { n: number };
      return json({ total: s.total, uniqueSenders: s.unique_senders, byTypePath, oldestTs: s.oldest_ts, newestTs: s.newest_ts, nodeId: NODE_ID, cellsPerMin: rate.n });
    }

    // ── GET /cells/stream (SSE)
    if (method === 'GET' && pathname === '/cells/stream') {
      let ctrl!: ReadableStreamController<Uint8Array>;
      const stream = new ReadableStream<Uint8Array>({
        start(c) {
          ctrl = c;
          sseClients.add(ctrl);
          // Send a hello event with current stats
          const stats = db.prepare('SELECT COUNT(*) AS n FROM cells').get() as { n: number };
          const hello = new TextEncoder().encode(
            `event: connected\ndata: ${JSON.stringify({ nodeId: NODE_ID, cellCount: stats.n })}\n\n`
          );
          ctrl.enqueue(hello);
        },
        cancel() { sseClients.delete(ctrl); },
      });
      return new Response(stream, {
        headers: {
          ...CORS,
          'Content-Type':  'text/event-stream',
          'Cache-Control': 'no-cache',
          'Connection':    'keep-alive',
        },
      });
    }

    // ── GET /cells/:cellId
    const cellMatch = pathname.match(/^\/cells\/([0-9a-f]{64})$/i);
    if (method === 'GET' && cellMatch) {
      const row = stmtGet.get({ $cellId: cellMatch[1] });
      if (!row) return json({ error: 'not found' }, 404);
      return json(row);
    }

    // ── GET /cells (paginated, optional ?type=<typePath> filter)
    if (method === 'GET' && pathname === '/cells') {
      const limit    = Math.min(100, parseInt(url.searchParams.get('limit')  ?? '20', 10));
      const offset   = parseInt(url.searchParams.get('offset') ?? '0', 10);
      const typePath = url.searchParams.get('type') ?? null;
      let rows: unknown[];
      let total: number;
      if (typePath) {
        rows  = stmtListByType.all({ $typePath: typePath, $limit: limit, $offset: offset });
        total = (stmtCountByType.get({ $typePath: typePath }) as { n: number }).n;
      } else {
        rows  = stmtList.all({ $limit: limit, $offset: offset });
        total = (db.prepare('SELECT COUNT(*) AS n FROM cells').get() as { n: number }).n;
      }
      return json({ cells: rows, total, limit, offset, typePath: typePath ?? undefined });
    }

    return new Response('not found', { status: 404, headers: CORS });
  },
});

console.log(`[cell-store] node=${NODE_ID}  HTTP :${HTTP_PORT}  db=${DB_PATH}`);
console.log(`[cell-store] relay=${RELAY_URL}  SSE primary + polling fallback every ${POLL_MS}ms`);

```
