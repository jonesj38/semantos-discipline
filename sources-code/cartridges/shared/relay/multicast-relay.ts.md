---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/relay/multicast-relay.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.438355+00:00
---

# cartridges/shared/relay/multicast-relay.ts

```ts
#!/usr/bin/env bun
/**
 * multicast-relay.ts — bridges infra-demo dashboard verdicts onto the Skyminer mesh.
 *
 * WHAT THIS DOES
 * ──────────────
 * Listens on HTTP :5199 for POST /publish from the three browser dashboards
 * (dark-fiber, inference-gate, ixp-routing).  Each POST carries a policy
 * verdict + inputs + the operator's hat context.  The relay derives the
 * SRv6 type-hash multicast group for the event type, encodes a compact cell,
 * and sends it as a UDP multicast packet on the same LAN as the Skyminer Pis.
 *
 * Any Pi running cell-subscriber.py (or the same relay in subscribe mode)
 * will receive the event and print/act on it.
 *
 * IDENTITY (HATS + PLEXUS)
 * ─────────────────────────
 * Each cell carries a `hat` field (operator context, e.g. "ixp-ams-noc") and
 * a `hat_fp` field: SHA-256(hat_name)[0:4] as 8 hex chars.  This is the same
 * derivation the brain uses via HAT_SEED → identitySk.  Different hats produce
 * different anchor key families.
 *
 * Plexus credentials (cert_tier 0-3) are carried in the `plexus` field for
 * inference events — the relay passes them through without interpreting them.
 *
 * MULTICAST GROUPS (Phase 34A SRv6 formula)
 * ───────────────────────────────────────────
 * ff15:4c8d:4906:bcc5:5005::  dark.fiber.commit
 * ff15:4c8d:4906:65a8:c2d4::  dark.fiber.hold
 * ff15:f927:c97d:a01f:2dee::  inference.access.grant
 * ff15:f927:c97d:6acb:8af4::  inference.access.deny
 * ff15:ad28:ac72:53d0:9d47::  ixp.route.accept
 * ff15:ad28:ac72:c8f2:d98d::  ixp.route.reject
 *
 * What-prefix groups (hierarchical subscription, requires SSM-capable router):
 * ff15:4c8d:4906::  all dark.fiber.*
 * ff15:f927:c97d::  all inference.access.*
 * ff15:ad28:ac72::  all ixp.route.*
 *
 * USAGE
 * ─────
 * bun cartridges/shared/relay/multicast-relay.ts [--port 5199] [--udp-port 4242] [--iface eth0]
 *
 * Set RELAY_IFACE=<interface> if the Pi mesh is on a non-default interface
 * (e.g. end0 on Orange Pi Prime).
 */

import { createSocket } from 'node:dgram';
import { createHash } from 'node:crypto';

// ── Canonical cell header (layer-collapse demo wire format) ───────────────────
// A CanonicalCellHeader identifies a 1024-byte cell traversing the mesh.
// Consumers can subscribe by typePath to receive only the types they care about.
// The full payload (up to 1024 bytes hex) is broadcast on the multicast group;
// only the header is stored in the relay's recent-cells ring buffer.

export interface CanonicalCellHeader {
  cellId:      string;   // 64-hex SHA-256 of payload bytes (content-addressed)
  typeHash?:   string;   // 64-hex canonical (8|8|8|8) routing label — optional, computed if absent
  typePath:    string;   // e.g. "ixp.route.accept", "dark.fiber.commit"
  scopeHash?:  string;   // 64-hex SHA-256 of scope string e.g. "AU.QLD.site-123"
                         // Separates geo/org/jurisdiction from the universal type namespace.
                         // Relay can filter: typePath prefix AND scopeHash prefix → route.
                         // Leave undefined for globally-scoped cells.
  senderFp:    string;   // 8-hex hat fingerprint of originating node
  seq:         number;   // monotonic sequence number from sender
  payloadLen:  number;   // byte length of payload (0-1024)
  ts:          number;   // unix ms timestamp at relay ingress
}

// Ring buffer — last N cells seen at this relay (header + hex payload).
// Max payload per cell: 1536 hex chars (768 bytes canonical MNCA tile) → ring
// at 100 is ≈ 155 KB — well within RAM budget.  100 cells gives > 9s of
// headroom at 10 ticks/sec MNCA + 0.3/sec policy sim vs cell-store's 2s poll.
// With SSE push now wired in, cell-store no longer relies on the ring; the
// ring remains for /cells/recent (late-joiners + polling fallback).
interface RecentCell {
  header:  CanonicalCellHeader;
  payload: string | null;   // hex-encoded bytes, null for legacy cells
}
const recentCells: RecentCell[] = [];
const RECENT_MAX = 500; // increased from 100 — pipeline cells must survive SSE reconnect flood
let publishCount = 0;   // lifetime accepted publishes (resets on restart)

// ── SSE push — typed subscription ─────────────────────────────────────────────
// Each subscriber gets `event: cell\ndata: {header, payload}\n\n` immediately
// on publish, eliminating the poll-interval lag.
//
// Typed subscription: GET /cells/stream?typePath=inference.*
//   null filter  → receive ALL cells (default, backward-compat)
//   "inference.*"     → cells where typePath starts with "inference."
//   "network.intent.*"→ cells where typePath starts with "network.intent."
//   "ixp.route.accept"→ exact match
//
// Each relay subscriber only receives cells it's interested in — this is the
// load-bearing primitive for semantic multicast: handlers specialize by type,
// relays forward only to matching subscribers, economic selection follows.

// Map: controller → typePath filter (null = all)
const sseClients = new Map<ReadableStreamDefaultController<Uint8Array>, string | null>();
const enc = new TextEncoder();

// Returns true if typePath matches the subscription filter pattern.
// Patterns: "prefix.*" (wildcard), "prefix*" (bare wildcard), or exact string.
function matchesTypeFilter(typePath: string, filter: string): boolean {
  if (filter.endsWith('.*')) return typePath.startsWith(filter.slice(0, -1));   // "a.b.*" → prefix "a.b."
  if (filter.endsWith('*'))  return typePath.startsWith(filter.slice(0, -1));   // "a.b*"  → prefix "a.b"
  return typePath === filter;
}

function pushSSE(h: CanonicalCellHeader, payload: string | null) {
  if (sseClients.size === 0) return;
  const msg = enc.encode(`event: cell\ndata: ${JSON.stringify({ header: h, payload })}\n\n`);
  for (const [ctrl, filter] of sseClients) {
    if (filter !== null && !matchesTypeFilter(h.typePath, filter)) continue;
    try { ctrl.enqueue(msg); } catch { sseClients.delete(ctrl); }
  }
}

function recordCell(h: CanonicalCellHeader, payload: string | null = null) {
  // Ensure typeHash is present — compute from typePath if not supplied by publisher
  if (!h.typeHash) (h as any).typeHash = computeTypeHash(h.typePath);
  recentCells.unshift({ header: h, payload });
  if (recentCells.length > RECENT_MAX) recentCells.length = RECENT_MAX;
  publishCount++;
  // Track routing contract stats
  recordRouting(contractFor(h.typeHash!));
  pushSSE(h, payload);
}

// Keep-alive: send a comment ping every 25 seconds to prevent proxy/browser
// timeouts during quiet periods (e.g., bridge SETTLING phase with MND ~7s).
const PING_MSG = enc.encode(': ping\n\n');
setInterval(() => {
  for (const ctrl of sseClients) {
    try { ctrl.enqueue(PING_MSG); } catch { sseClients.delete(ctrl); }
  }
}, 25_000);

// ── Canonical typeHash (8|8|8|8) — 4 × sha256[0:8] segments ─────────────────
// Matches buildTestTypeHash in cartridges/wallet-headers/brain/test/cell-anchor.spec.ts
// and @semantos/protocol-types buildTypeHash.
//
// typePath "ixp.route.accept" → segments ["ixp","route","accept",""]
// bytes  0- 7:  sha256("ixp")[0:8]
// bytes  8-15:  sha256("route")[0:8]
// bytes 16-23:  sha256("accept")[0:8]
// bytes 24-31:  sha256("")[0:8]   ← empty qualifier

function typeHashSeg(s: string): Buffer {
  return createHash('sha256').update(s).digest().slice(0, 8);
}

function computeTypeHash(typePath: string): string {
  const parts     = typePath.split('.');
  const [s1='', s2='', s3='', s4=''] = [parts[0], parts[1], parts[2], parts[3]];
  return Buffer.concat([typeHashSeg(s1), typeHashSeg(s2), typeHashSeg(s3), typeHashSeg(s4)]).toString('hex');
}

// Tier prefix = first 8 bytes (16 hex chars) = sha256(tier)[0:8]
// One memcmp determines the payment contract for a cell.
function tierPrefix(typePath: string): string {
  return computeTypeHash(typePath).slice(0, 16);
}

// ── Payment contract table ────────────────────────────────────────────────────
// Maps typeHash tier prefix → sats/cell.  Higher sats = higher routing priority.
// Tier prefix computed once at startup (sha256(tierName)[0:8] as 16-hex chars).

interface PaymentContract {
  label:       string;
  tierPrefix:  string;   // 16-hex = sha256(tierName)[0:8]
  satsPerCell: number;
  priority:    number;   // 1 = highest
}

const PAYMENT_CONTRACTS: PaymentContract[] = [
  { label: 'inference', tierPrefix: tierPrefix('inference.x.x'), satsPerCell: 200, priority: 1 },
  { label: 'bsv',       tierPrefix: tierPrefix('bsv.x.x'),       satsPerCell: 150, priority: 2 },
  { label: 'ixp',       tierPrefix: tierPrefix('ixp.x.x'),       satsPerCell: 100, priority: 3 },
  { label: 'p2p',       tierPrefix: tierPrefix('p2p.x.x'),       satsPerCell:  75, priority: 4 },
  { label: 'compute',   tierPrefix: tierPrefix('compute.x.x'),   satsPerCell:  60, priority: 5 },
  { label: 'dark',      tierPrefix: tierPrefix('dark.x.x'),      satsPerCell:  50, priority: 6 },
  { label: 'ipv6',      tierPrefix: tierPrefix('ipv6.x.x'),      satsPerCell:  40, priority: 7 },
  { label: 'mnca',      tierPrefix: tierPrefix('mnca.x.x'),      satsPerCell:   5, priority: 8 },
];

function contractFor(typeHashHex: string): PaymentContract {
  const prefix = typeHashHex.slice(0, 16);
  return PAYMENT_CONTRACTS.find(c => c.tierPrefix === prefix)
    ?? { label: 'default', tierPrefix: prefix, satsPerCell: 10, priority: 9 };
}

// ── Routing stats ─────────────────────────────────────────────────────────────
// Tracks per-contract cell counts, sats routed, and a rolling 5-second rate.

interface ContractStat {
  hits:       number;
  satsRouted: number;
  // Rolling window: timestamps of last 500 cells for rate calculation
  recentTs:   number[];
}

const routingStats = new Map<string, ContractStat>();
let   totalCellsRouted = 0;
let   totalSatsRouted  = 0;

function recordRouting(contract: PaymentContract): void {
  totalCellsRouted++;
  totalSatsRouted += contract.satsPerCell;
  let s = routingStats.get(contract.label);
  if (!s) {
    s = { hits: 0, satsRouted: 0, recentTs: [] };
    routingStats.set(contract.label, s);
  }
  s.hits++;
  s.satsRouted += contract.satsPerCell;
  const now = Date.now();
  s.recentTs.push(now);
  // Keep only last 5 seconds of timestamps
  const cutoff = now - 5000;
  while (s.recentTs.length > 0 && s.recentTs[0]! < cutoff) s.recentTs.shift();
}

function routingStatsSnapshot() {
  const now = Date.now();
  const contracts = PAYMENT_CONTRACTS.map(c => {
    const s = routingStats.get(c.label);
    const rate5s = s ? s.recentTs.filter(t => t > now - 5000).length / 5 : 0;
    return {
      label:       c.label,
      tierPrefix:  c.tierPrefix,
      satsPerCell: c.satsPerCell,
      priority:    c.priority,
      hits:        s?.hits        ?? 0,
      satsRouted:  s?.satsRouted  ?? 0,
      rate5s:      Math.round(rate5s * 10) / 10,  // cells/sec (5s rolling)
    };
  });
  // Also include 'default' if it has hits
  const def = routingStats.get('default');
  if (def) {
    const rate5s = def.recentTs.filter(t => t > now - 5000).length / 5;
    contracts.push({ label: 'default', tierPrefix: '(unmatched)', satsPerCell: 10, priority: 9,
      hits: def.hits, satsRouted: def.satsRouted, rate5s: Math.round(rate5s * 10) / 10 });
  }
  return {
    contracts,
    totalCells:     totalCellsRouted,
    totalSats:      totalSatsRouted,
    publishCount,   // lifetime
    uniqueContracts: routingStats.size,
  };
}

// ── Config ────────────────────────────────────────────────────────────────────

const HTTP_PORT  = parseInt(process.env.RELAY_HTTP_PORT  ?? '5199', 10);
const UDP_PORT   = parseInt(process.env.RELAY_UDP_PORT   ?? '4242', 10);
const IFACE      = process.env.RELAY_IFACE ?? '';   // e.g. 'end0' for Pi LAN
const TTL        = parseInt(process.env.RELAY_TTL  ?? '4',    10); // site-local

// Demo mode: allow localhost /publish without a funded channel.
// Set RELAY_ALLOW_LOCAL_INJECT=true for testing + cell-injector demos.
const ALLOW_LOCAL_INJECT = process.env.RELAY_ALLOW_LOCAL_INJECT === 'true';

// ── SRv6 type-hash formula (matches core/protocol-types/src/mnca/srv6.ts) ────

function axisPrefix(prefix: string, value: string): string {
  const buf = createHash('sha256').update(`${prefix}.${value}`).digest();
  // Return 4 bytes as 8-char hex — rendered as two 4-char IPv6 groups
  return buf.slice(0, 4).toString('hex');
}

function deriveGroup(what: string, how: string, scope = 0x15): string {
  const w = axisPrefix('what', what); // 8 hex chars
  const h = axisPrefix('how',  how);
  const ZERO = '00000000';
  const sc = scope.toString(16).padStart(2, '0');
  // Format: ff<sc>:W[0:4]:W[4:8]H[0:4]:H[4:8]ZERO[0:4]:ZERO[4:8]:0000
  // Mirrors: ff${sc}:${group(w)}:${group(h)}:${group(i)}:0000
  const grp = (s: string) => `${s.slice(0,4)}:${s.slice(4)}`;
  return `ff${sc}:${grp(w)}:${grp(h)}:${ZERO.slice(0,4)}:${ZERO.slice(4)}:0000`;
}

// ── Pinned known-answer table (computed 2026-05-26 against scope=0x15) ────────

const KNOWN_GROUPS: Record<string, string> = {
  'dark.fiber.commit':       'ff15:4c8d:4906:bcc5:5005:0000:0000:0000',
  'dark.fiber.hold':         'ff15:4c8d:4906:65a8:c2d4:0000:0000:0000',
  'inference.access.grant':  'ff15:f927:c97d:a01f:2dee:0000:0000:0000',
  'inference.access.deny':   'ff15:f927:c97d:6acb:8af4:0000:0000:0000',
  'ixp.route.accept':        'ff15:ad28:ac72:53d0:9d47:0000:0000:0000',
  'ixp.route.reject':        'ff15:ad28:ac72:c8f2:d98d:0000:0000:0000',
};

function groupForType(typePath: string): string {
  if (KNOWN_GROUPS[typePath]) return KNOWN_GROUPS[typePath];
  // Dynamic derivation for unknown types
  const parts = typePath.split('.');
  const how   = parts.pop()!;
  const what  = parts.join('.');
  return deriveGroup(what, how);
}

// ── Hat fingerprint (truncated SHA-256 of hat name) ───────────────────────────

function hatFingerprint(hatName: string): string {
  return createHash('sha256').update(hatName).digest('hex').slice(0, 8);
}

// ── UDP multicast socket ──────────────────────────────────────────────────────

const udpSock = createSocket({ type: 'udp6', reuseAddr: true });

udpSock.on('error', (err) => {
  console.error('[relay] UDP error:', err.message);
});

await new Promise<void>((resolve, reject) => {
  udpSock.bind(0, () => resolve());
  udpSock.once('error', reject);
});

udpSock.setMulticastTTL(TTL);
if (IFACE) {
  try { udpSock.setMulticastInterface(IFACE); } catch {}
}

async function publishCell(typePath: string, payload: object): Promise<string> {
  const group = groupForType(typePath);
  const json  = JSON.stringify(payload);
  const buf   = Buffer.from(json, 'utf-8');
  await new Promise<void>((resolve, reject) => {
    udpSock.send(buf, UDP_PORT, group, (err) => {
      if (err) reject(err); else resolve();
    });
  });
  return group;
}

// ── HTTP server ───────────────────────────────────────────────────────────────

const CORS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

Bun.serve({
  port: HTTP_PORT,

  async fetch(req) {
    const url = new URL(req.url);

    // CORS preflight
    if (req.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS });
    }

    // ── GET /groups — return all known multicast groups + their type paths
    if (req.method === 'GET' && url.pathname === '/groups') {
      return Response.json({ groups: KNOWN_GROUPS }, { headers: CORS });
    }

    // ── GET /health
    if (req.method === 'GET' && url.pathname === '/health') {
      // Summarise typed subscribers: { "inference.*": 2, "ixp.*": 1, "(all)": 3 }
      const subsByFilter: Record<string, number> = {};
      for (const filter of sseClients.values()) {
        const key = filter ?? '(all)';
        subsByFilter[key] = (subsByFilter[key] ?? 0) + 1;
      }
      return Response.json({
        ok: true,
        udpPort: UDP_PORT,
        iface: IFACE || 'default',
        recentCellCount: recentCells.length,
        publishCount,
        sseClientCount: sseClients.size,
        sseSubscriptions: subsByFilter,
      }, { headers: CORS });
    }

    // ── GET /routing/stats — per-contract cell counts, sats routed, rolling rate
    if (req.method === 'GET' && url.pathname === '/routing/stats') {
      return Response.json(routingStatsSnapshot(), { headers: CORS });
    }

    // ── GET /routing/contracts — contract table (for dashboard initialisation)
    if (req.method === 'GET' && url.pathname === '/routing/contracts') {
      return Response.json({
        contracts: PAYMENT_CONTRACTS.map(c => ({
          label:       c.label,
          tierPrefix:  c.tierPrefix,
          satsPerCell: c.satsPerCell,
          priority:    c.priority,
          typeHashExample: computeTypeHash(`${c.label}.example.accept`),
        })),
      }, { headers: CORS });
    }

    // ── GET /cells/recent — last N cells seen at this relay
    // Each entry: { header: CanonicalCellHeader, payload: string|null }
    // Optional: ?typePath=inference.*  filter by type (same pattern as /cells/stream)
    // Optional: ?limit=N               max results (default 20, max 100)
    if (req.method === 'GET' && url.pathname === '/cells/recent') {
      const typeFilter = url.searchParams.get('typePath') ?? null;
      const limit = Math.min(parseInt(url.searchParams.get('limit') ?? '20', 10), RECENT_MAX);
      const filtered = typeFilter
        ? recentCells.filter(rc => matchesTypeFilter(rc.header.typePath, typeFilter))
        : recentCells;
      const cells = filtered.slice(0, limit);
      return Response.json({ cells, count: cells.length, filter: typeFilter }, { headers: CORS });
    }

    // ── GET /cells/stream — SSE push: typed real-time cell feed
    // Each `cell` event carries { header: CanonicalCellHeader, payload: string|null }.
    // Subscribers (e.g. cell-store.ts) should prefer this over polling /cells/recent.
    //
    // Optional query param: ?typePath=<filter>
    //   No param:                 receive ALL cells (backward-compat)
    //   ?typePath=inference.*     receive only inference.* cells
    //   ?typePath=network.intent.ixp.*  receive only IXP intent cells
    //   ?typePath=ixp.route.accept      exact match only
    //
    // On connect, immediately replays the last 20 matching cells from the ring
    // buffer so late-joining subscribers don't miss recent history.
    if (req.method === 'GET' && url.pathname === '/cells/stream') {
      const typeFilter = url.searchParams.get('typePath') ?? null;
      let controller!: ReadableStreamDefaultController<Uint8Array>;
      const stream = new ReadableStream<Uint8Array>({
        start(c) {
          controller = c;
          sseClients.set(c, typeFilter);
          // Confirm connection with filter info
          const filterMsg = typeFilter ? `typePath=${typeFilter}` : 'all types';
          c.enqueue(enc.encode(`: relay-stream-connected filter=${filterMsg}\n\n`));
          // Replay recent matching cells (late-joiner catch-up, newest first → reverse)
          const recent = recentCells
            .filter(rc => typeFilter === null || matchesTypeFilter(rc.header.typePath, typeFilter))
            .slice(0, 20)
            .reverse();  // oldest first for replay
          for (const rc of recent) {
            try {
              c.enqueue(enc.encode(`event: cell\ndata: ${JSON.stringify({ header: rc.header, payload: rc.payload })}\n\n`));
            } catch { break; }
          }
        },
        cancel() { sseClients.delete(controller); },
      });
      return new Response(stream, {
        headers: {
          ...CORS,
          'Content-Type':      'text/event-stream',
          'Cache-Control':     'no-cache',
          'X-Accel-Buffering': 'no',
          'Connection':        'keep-alive',
        },
      });
    }

    // ── POST /publish
    if (req.method === 'POST' && url.pathname === '/publish') {
      // x402 payment gate — check if a CashLanes channel is FLOW_ACTIVE
      let bridgeResponded = false;
      let channelActive = false;
      try {
        const cr = await fetch('http://localhost:5198/channel/state', { signal: AbortSignal.timeout(500) });
        if (cr.ok) {
          bridgeResponded = true;
          const cs = await cr.json() as any;
          channelActive = cs.state === 'FLOW_ACTIVE';
        }
      } catch { /* bridge offline — allow publish (graceful degradation) */ }

      // Allow publishes when RELAY_ALLOW_LOCAL_INJECT=true (demo mode — skips payment for entire mesh)
      const reqHost = url.hostname;
      const isLocal = reqHost === 'localhost' || reqHost === '127.0.0.1' || reqHost === '::1';
      const isMeshNode = /^192\.168\./.test(reqHost) || /^10\./.test(reqHost) || /^172\.(1[6-9]|2\d|3[01])\./.test(reqHost);
      if (ALLOW_LOCAL_INJECT && (isLocal || isMeshNode)) {
        // skip x402 check — demo/dev mode, all local mesh nodes allowed
      } else if (bridgeResponded && !channelActive) {
        return Response.json({
          error: 'payment_required',
          message: 'Fund and start a CashLanes payment channel to publish to the mesh',
          channelUrl: 'http://localhost:5198',
          hint: 'POST http://localhost:5198/channel/fund then /channel/start',
        }, { status: 402, headers: CORS });
      }

      let raw: Record<string, unknown>;
      try {
        raw = await req.json();
      } catch {
        return Response.json({ error: 'invalid JSON' }, { status: 400, headers: CORS });
      }

      // ── Detect body shape: canonical cell vs legacy verdict format ─────────
      //
      // Canonical:  { header: CanonicalCellHeader, payload?: string (hex) }
      // Legacy:     { typePath, verdict, inputs?, hat?, strategyHex?, plexus? }
      //
      // The relay normalises both to the same UDP broadcast format and records
      // a CanonicalCellHeader in the recent-cells ring buffer either way.

      let typePath: string;
      let cellPayload: object;         // what goes on the wire as UDP JSON
      let cellHeader: CanonicalCellHeader;

      if (raw.header && typeof (raw.header as any).cellId === 'string') {
        // ── Canonical cell path ───────────────────────────────────────────
        const h = raw.header as CanonicalCellHeader;
        if (!h.cellId || !h.typePath || !h.senderFp) {
          return Response.json({ error: 'header.cellId, typePath, senderFp required' }, { status: 400, headers: CORS });
        }
        typePath    = h.typePath;
        cellHeader  = { ...h, ts: Date.now() };
        cellPayload = {
          v:       2,           // canonical format version
          header:  cellHeader,
          payload: raw.payload ?? null,
        };
      } else {
        // ── Legacy verdict path (backward compat) ─────────────────────────
        const body = raw as {
          typePath?: string; verdict?: boolean;
          inputs?: Record<string, unknown>; strategy?: string;
          hat?: string; plexus?: unknown; strategyHex?: string;
        };
        if (!body.typePath || typeof body.verdict !== 'boolean') {
          return Response.json({ error: 'typePath + verdict required (legacy) or header.cellId (canonical)' }, { status: 400, headers: CORS });
        }
        typePath = body.typePath;
        const hat    = body.hat ?? 'demo-operator';
        const hat_fp = hatFingerprint(hat);
        const legacyPayload = JSON.stringify({ v: 1, type: typePath, verdict: body.verdict, inputs: body.inputs ?? {} });
        // Derive a deterministic cellId from the legacy payload content + ts
        const tsNow = Date.now();
        const cellId = createHash('sha256').update(legacyPayload + tsNow).digest('hex');
        cellHeader = {
          cellId,
          typePath,
          senderFp:   hat_fp,
          seq:        0,
          payloadLen: legacyPayload.length,
          ts:         tsNow,
        };
        cellPayload = {
          v:           1,
          type:        typePath,
          verdict:     body.verdict,
          inputs:      body.inputs ?? {},
          strategy:    body.strategy ?? '',
          strategyHex: body.strategyHex ?? '',
          hat,
          hat_fp,
          plexus:      body.plexus ?? null,
          ts:          tsNow,
          cellId,       // add cellId so subscribers can cross-reference
        };
      }

      // Record header + payload in ring buffer
      // For canonical cells the payload is a hex string (may be null for header-only).
      // For legacy cells the payload is null (backward compat).
      const ringPayload = (raw.header && raw.payload != null && typeof raw.payload === 'string')
        ? (raw.payload as string)
        : null;
      recordCell(cellHeader, ringPayload);

      let group: string;
      try {
        group = await publishCell(typePath, cellPayload);
      } catch (err: any) {
        return Response.json(
          { error: 'udp_send_failed', detail: err?.message },
          { status: 500, headers: CORS }
        );
      }

      const shortGroup = group.replace(':0000:0000:0000', '::');
      const contract   = contractFor(cellHeader.typeHash ?? computeTypeHash(typePath));
      console.log(
        `[relay] ${typePath.padEnd(32)} cell=${cellHeader.cellId.slice(0, 8)}… ` +
        `${contract.label.padEnd(10)} ${contract.satsPerCell}sat  → ${shortGroup}`
      );

      // Notify bridge of published packet (fire-and-forget; only when channel is active)
      if (channelActive) {
        fetch('http://localhost:5198/channel/advance', { method: 'POST' }).catch(() => {});
      }

      return Response.json({ ok: true, group, shortGroup, cellId: cellHeader.cellId }, { headers: CORS });
    }

    return new Response('not found', { status: 404, headers: CORS });
  },
});

console.log(`[relay] HTTP :${HTTP_PORT}  UDP multicast :${UDP_PORT}  TTL=${TTL}${IFACE ? `  iface=${IFACE}` : ''}`);
console.log('[relay] Known multicast groups:');
for (const [type, group] of Object.entries(KNOWN_GROUPS)) {
  console.log(`  ${type.padEnd(30)} ${group}`);
}
console.log('[relay] Ready — dashboards should POST to http://localhost:5199/publish');

```
