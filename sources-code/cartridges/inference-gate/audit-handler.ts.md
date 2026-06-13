---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/audit-handler.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.408959+00:00
---

# cartridges/inference-gate/audit-handler.ts

```ts
#!/usr/bin/env bun
/**
 * audit-handler.ts  (:5200)
 *
 * GDPR Article 30 — "Records of processing activities" for AI inference.
 *
 * Subscribes to inference.* cells via typed SSE from the relay.
 * Stores every inference.request.classify + inference.result.response in SQLite.
 *
 * GET /audit               — paginated list of inference events
 * GET /audit/:requestId    — full record for one inference event
 * GET /audit/stats         — totals, by-classification, breach count, txid count
 * GET /audit/stream        — SSE: live push of new audit entries
 * GET /health              — service health
 *
 * Pitch: "When regulators ask what governed access to record X —
 *         show them a Bitcoin transaction ID, not a log file."
 *
 * Usage:
 *   bun audit-handler.ts [--port 5200] [--relay http://localhost:5199]
 *
 * Env:
 *   RELAY_URL   override relay base URL
 *   AUDIT_PORT  override listen port
 *   DB_PATH     override SQLite path (default: ./audit.sqlite)
 */

import { Database } from "bun:sqlite";
import { createHash } from "crypto";

// ── Config ─────────────────────────────────────────────────────────────────

const PORT       = Number(process.env.AUDIT_PORT ?? "5200");
const RELAY_URL  = process.env.RELAY_URL ?? "http://localhost:5199";
const DB_PATH    = process.env.DB_PATH   ?? "./audit.sqlite";

// ── Schema ──────────────────────────────────────────────────────────────────

interface CanonicalCellHeader {
  cellId:     string;       // 64-hex SHA-256 of payload
  typePath:   string;       // e.g. "inference.request.classify"
  senderFp:   string;       // 8-hex hat fingerprint
  seq:        number;
  payloadLen: number;
  scopeHash?: string;       // geo/org routing
}

interface AuditRecord {
  id:             number;
  request_id:     string;    // cellId of the request cell
  result_id:      string | null;
  type_path:      string;
  sender_fp:      string;
  scope_hash:     string | null;
  seq:            number;
  // parsed fields from payload
  prompt:         string | null;
  result:         string | null;
  cert_tier:      string | null;
  data_class:     string | null;
  policy_hex:     string | null;
  bsv_txid:       string | null;
  model:          string | null;
  confidence:     number | null;
  // meta
  received_at:    number;    // unix ms
  is_breach:      number;    // 0/1 — policy denied or cert_tier insufficient
}

// ── Database ─────────────────────────────────────────────────────────────────

const db = new Database(DB_PATH, { create: true });

db.exec(`
  CREATE TABLE IF NOT EXISTS audit (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    request_id  TEXT NOT NULL,
    result_id   TEXT,
    type_path   TEXT NOT NULL,
    sender_fp   TEXT NOT NULL,
    scope_hash  TEXT,
    seq         INTEGER,
    prompt      TEXT,
    result      TEXT,
    cert_tier   TEXT,
    data_class  TEXT,
    policy_hex  TEXT,
    bsv_txid    TEXT,
    model       TEXT,
    confidence  REAL,
    received_at INTEGER NOT NULL,
    is_breach   INTEGER NOT NULL DEFAULT 0
  );
  CREATE INDEX IF NOT EXISTS idx_audit_request_id  ON audit(request_id);
  CREATE INDEX IF NOT EXISTS idx_audit_type_path   ON audit(type_path);
  CREATE INDEX IF NOT EXISTS idx_audit_received_at ON audit(received_at);
  CREATE INDEX IF NOT EXISTS idx_audit_is_breach   ON audit(is_breach);
  CREATE INDEX IF NOT EXISTS idx_audit_bsv_txid    ON audit(bsv_txid);
`);

const insertStmt = db.prepare(`
  INSERT OR REPLACE INTO audit
    (request_id, result_id, type_path, sender_fp, scope_hash, seq,
     prompt, result, cert_tier, data_class, policy_hex, bsv_txid, model, confidence,
     received_at, is_breach)
  VALUES
    ($request_id, $result_id, $type_path, $sender_fp, $scope_hash, $seq,
     $prompt, $result, $cert_tier, $data_class, $policy_hex, $bsv_txid, $model, $confidence,
     $received_at, $is_breach)
`);

function upsertRecord(r: Omit<AuditRecord, "id">) {
  insertStmt.run({
    $request_id: r.request_id,
    $result_id:  r.result_id,
    $type_path:  r.type_path,
    $sender_fp:  r.sender_fp,
    $scope_hash: r.scope_hash,
    $seq:        r.seq,
    $prompt:     r.prompt,
    $result:     r.result,
    $cert_tier:  r.cert_tier,
    $data_class: r.data_class,
    $policy_hex: r.policy_hex,
    $bsv_txid:   r.bsv_txid,
    $model:      r.model,
    $confidence: r.confidence,
    $received_at:r.received_at,
    $is_breach:  r.is_breach,
  });
}

// ── SSE broadcast to audit stream subscribers ─────────────────────────────

type SSEController = ReadableStreamDefaultController<Uint8Array>;
const auditSseClients = new Set<SSEController>();
const enc = new TextEncoder();

function pushAuditEvent(record: object) {
  if (auditSseClients.size === 0) return;
  const msg = enc.encode(`event: audit\ndata: ${JSON.stringify(record)}\n\n`);
  for (const ctrl of auditSseClients) {
    try { ctrl.enqueue(msg); } catch { auditSseClients.delete(ctrl); }
  }
}

// ── Cell parsing helpers ───────────────────────────────────────────────────

function parsePayload(hex: string | null): Record<string, unknown> {
  if (!hex) return {};
  try {
    const json = Buffer.from(hex, "hex").toString("utf8");
    return JSON.parse(json);
  } catch {
    return {};
  }
}

function isBreach(typePath: string, payload: Record<string, unknown>): boolean {
  // A "breach" is any event where access was denied or tier was insufficient
  if (typePath.includes("deny") || typePath.includes("reject")) return true;
  if (payload.verdict === "deny") return true;
  if (payload.policyDenied === true) return true;
  if (payload.certTier === "NONE" && typePath.includes("request")) return true;
  return false;
}

function cellToRecord(header: CanonicalCellHeader, payloadHex: string | null): Omit<AuditRecord, "id"> {
  const p = parsePayload(payloadHex);
  return {
    request_id:  (p.requestId as string) ?? header.cellId,
    result_id:   typePath(header) === "result" ? header.cellId : null,
    type_path:   header.typePath,
    sender_fp:   header.senderFp,
    scope_hash:  header.scopeHash ?? null,
    seq:         header.seq,
    prompt:      (p.prompt as string) ?? (p.description as string) ?? null,
    result:      (p.result as string) ?? (p.verdict as string) ?? (p.classification as string) ?? null,
    cert_tier:   (p.certTier as string) ?? null,
    data_class:  (p.dataClass as string) ?? null,
    policy_hex:  (p.policyHex as string) ?? null,
    bsv_txid:    (p.bsvTxid as string) ?? (p.txid as string) ?? null,
    model:       (p.model as string) ?? null,
    confidence:  typeof p.confidence === "number" ? p.confidence : null,
    received_at: Date.now(),
    is_breach:   isBreach(header.typePath, p) ? 1 : 0,
  };
}

function typePath(header: CanonicalCellHeader): string {
  const parts = header.typePath.split(".");
  return parts[parts.length - 1] ?? "";
}

// ── Relay SSE subscription ─────────────────────────────────────────────────

let relayConnected = false;
let relayEventCount = 0;
let reconnectMs = 1000;

async function subscribeRelay() {
  const url = `${RELAY_URL}/cells/stream?typePath=inference.*`;
  console.log(`[audit] Connecting to relay SSE: ${url}`);

  try {
    const resp = await fetch(url, {
      headers: { Accept: "text/event-stream" },
    });

    if (!resp.ok || !resp.body) {
      throw new Error(`relay SSE ${resp.status}`);
    }

    relayConnected = true;
    reconnectMs = 1000; // reset backoff on success
    console.log("[audit] ✓ Relay SSE connected (inference.*)");

    const reader = resp.body.getReader();
    const tdec = new TextDecoder();
    let buf = "";

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += tdec.decode(value, { stream: true });

      const lines = buf.split("\n");
      buf = lines.pop() ?? "";

      let eventType = "";
      let dataLine  = "";
      for (const line of lines) {
        if (line.startsWith("event: ")) eventType = line.slice(7).trim();
        if (line.startsWith("data: "))  dataLine  = line.slice(6).trim();
        if (line === "" && dataLine) {
          if (eventType === "cell" || !eventType) {
            try {
              const ev = JSON.parse(dataLine) as { header: CanonicalCellHeader; payload: string | null };
              const rec = cellToRecord(ev.header, ev.payload ?? null);
              upsertRecord(rec);
              relayEventCount++;
              pushAuditEvent({ ...rec, id: relayEventCount });
            } catch { /* skip malformed */ }
          }
          eventType = "";
          dataLine  = "";
        }
      }
    }
  } catch (err) {
    relayConnected = false;
    console.warn(`[audit] Relay SSE error: ${err}. Reconnecting in ${reconnectMs}ms…`);
  }

  // Reconnect with capped backoff
  setTimeout(() => subscribeRelay(), reconnectMs);
  reconnectMs = Math.min(reconnectMs * 2, 30_000);
}

// ── HTTP handler ───────────────────────────────────────────────────────────

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  });
}

function cors(method = "GET"): Response {
  return new Response(null, {
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": method + ", OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    },
  });
}

const server = Bun.serve({
  port: PORT,

  fetch(req: Request) {
    const url = new URL(req.url);
    const path = url.pathname;

    if (req.method === "OPTIONS") return cors();

    // ── GET /health ──────────────────────────────────────────────────────
    if (path === "/health" && req.method === "GET") {
      const stats = db.query("SELECT COUNT(*) as total, SUM(is_breach) as breaches FROM audit").get() as any;
      return json({
        service:      "audit-handler",
        port:         PORT,
        relay:        RELAY_URL,
        relayConnected,
        relayEventCount,
        auditSseSubscriptions: auditSseClients.size,
        db:           DB_PATH,
        totalRecords: stats?.total ?? 0,
        totalBreaches: stats?.breaches ?? 0,
      });
    }

    // ── GET /audit/stats ──────────────────────────────────────────────────
    if (path === "/audit/stats" && req.method === "GET") {
      const total     = (db.query("SELECT COUNT(*) as c FROM audit").get() as any)?.c ?? 0;
      const breaches  = (db.query("SELECT COUNT(*) as c FROM audit WHERE is_breach=1").get() as any)?.c ?? 0;
      const withTxid  = (db.query("SELECT COUNT(*) as c FROM audit WHERE bsv_txid IS NOT NULL").get() as any)?.c ?? 0;
      const byType    = db.query("SELECT type_path, COUNT(*) as count FROM audit GROUP BY type_path ORDER BY count DESC").all() as any[];
      const byCert    = db.query("SELECT cert_tier, COUNT(*) as count FROM audit WHERE cert_tier IS NOT NULL GROUP BY cert_tier ORDER BY count DESC").all() as any[];
      const oldest    = (db.query("SELECT MIN(received_at) as ts FROM audit").get() as any)?.ts ?? null;
      const newest    = (db.query("SELECT MAX(received_at) as ts FROM audit").get() as any)?.ts ?? null;

      // Cells per minute (last 5 min)
      const fiveMinAgo = Date.now() - 5 * 60_000;
      const recentCount = (db.query("SELECT COUNT(*) as c FROM audit WHERE received_at > ?").get(fiveMinAgo) as any)?.c ?? 0;
      const cellsPerMin = Math.round(recentCount / 5);

      return json({
        total,
        breaches,
        withBsvTxid: withTxid,
        cellsPerMin,
        byTypePath: Object.fromEntries(byType.map((r: any) => [r.type_path, r.count])),
        byCertTier: Object.fromEntries(byCert.map((r: any) => [r.cert_tier ?? "null", r.count])),
        oldestTs: oldest,
        newestTs: newest,
      });
    }

    // ── GET /audit/stream — SSE ───────────────────────────────────────────
    if (path === "/audit/stream" && req.method === "GET") {
      let ctrl: SSEController;
      const stream = new ReadableStream<Uint8Array>({
        start(controller) {
          ctrl = controller;
          auditSseClients.add(ctrl);
          // Send last 10 records on connect
          const recent = db.query("SELECT * FROM audit ORDER BY received_at DESC LIMIT 10").all() as AuditRecord[];
          for (const r of recent.reverse()) {
            try { ctrl.enqueue(enc.encode(`event: audit\ndata: ${JSON.stringify(r)}\n\n`)); } catch {}
          }
          // Keepalive ping every 20s
          const ping = setInterval(() => {
            try { ctrl.enqueue(enc.encode(": ping\n\n")); } catch { clearInterval(ping); }
          }, 20_000);
        },
        cancel() { auditSseClients.delete(ctrl); },
      });
      return new Response(stream, {
        headers: {
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache",
          "Connection": "keep-alive",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }

    // ── GET /audit/:requestId ─────────────────────────────────────────────
    const singleMatch = path.match(/^\/audit\/([a-zA-Z0-9_-]{1,128})$/);
    if (singleMatch && req.method === "GET") {
      const requestId = singleMatch[1];
      const row = db.query("SELECT * FROM audit WHERE request_id = ? ORDER BY received_at ASC").all(requestId) as AuditRecord[];
      if (row.length === 0) return json({ error: "not found" }, 404);
      // Return all rows with that request_id (request + result cells)
      return json({ requestId, records: row });
    }

    // ── GET /audit ────────────────────────────────────────────────────────
    if (path === "/audit" && req.method === "GET") {
      const limit  = Math.min(Number(url.searchParams.get("limit")  ?? "50"), 200);
      const offset = Number(url.searchParams.get("offset") ?? "0");
      const certTier  = url.searchParams.get("certTier");
      const dataClass = url.searchParams.get("dataClass");
      const typePath  = url.searchParams.get("typePath");
      const breach    = url.searchParams.get("breach");
      const withTxid  = url.searchParams.get("withTxid");

      let where = "1=1";
      const params: unknown[] = [];
      if (certTier)  { where += " AND cert_tier = ?";  params.push(certTier); }
      if (dataClass) { where += " AND data_class = ?"; params.push(dataClass); }
      if (typePath)  { where += " AND type_path LIKE ?"; params.push(typePath.replace("*", "%")); }
      if (breach === "1") { where += " AND is_breach = 1"; }
      if (withTxid === "1") { where += " AND bsv_txid IS NOT NULL"; }

      const total = (db.query(`SELECT COUNT(*) as c FROM audit WHERE ${where}`).get(...params) as any)?.c ?? 0;
      const rows  = db.query(
        `SELECT * FROM audit WHERE ${where} ORDER BY received_at DESC LIMIT ? OFFSET ?`
      ).all(...params, limit, offset) as AuditRecord[];

      return json({ total, limit, offset, records: rows });
    }

    // ── 404 ───────────────────────────────────────────────────────────────
    return json({ error: "not found" }, 404);
  },
});

console.log(`
╔══════════════════════════════════════════════════════════╗
║   audit-handler  :${PORT}                               ║
║   GDPR Article 30 — AI Inference Audit Log              ║
╠══════════════════════════════════════════════════════════╣
║   GET /audit              paginated inference events     ║
║   GET /audit/:requestId   single event + result pair     ║
║   GET /audit/stats        totals, by-type, by-tier       ║
║   GET /audit/stream       SSE live push of new entries   ║
║   GET /health             service health                 ║
╠══════════════════════════════════════════════════════════╣
║   Relay: ${RELAY_URL.padEnd(46)} ║
║   DB:    ${DB_PATH.padEnd(46)} ║
╚══════════════════════════════════════════════════════════╝
`);

// Start relay subscription
subscribeRelay();

```
