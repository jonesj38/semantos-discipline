---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/worker-registry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.409820+00:00
---

# cartridges/inference-gate/worker-registry.ts

```ts
#!/usr/bin/env bun
/**
 * worker-registry.ts  (:5201)
 *
 * Central registry for distributed inference workers across the Skyminer mesh.
 * Workers POST /workers/register on start, heartbeat every 5s, DELETE on shutdown.
 * Coordinator queries /workers/available?typePath=inference.safety.* to find
 * workers that can handle a given cell type.
 *
 * Usage:
 *   bun worker-registry.ts [--port 5201]
 *
 * Env:
 *   REGISTRY_PORT   override listen port (default 5201)
 *   WORKER_TTL_MS   time before a worker is considered stale (default 30000)
 *   HEARTBEAT_MISS  missed heartbeats before marking inactive (default 3)
 */

const PORT         = Number(process.env.REGISTRY_PORT ?? '5201');
const WORKER_TTL   = Number(process.env.WORKER_TTL_MS ?? '30000');   // 30s
const HEARTBEAT_MS = 5000;   // expected heartbeat interval
const MAX_MISS     = Number(process.env.HEARTBEAT_MISS ?? '3');

// ── Types ─────────────────────────────────────────────────────────────────────

interface WorkerRecord {
  workerId:     string;
  nodeIp:       string;
  typePaths:    string[];    // e.g. ["inference.safety.*", "inference.ppe.*"]
  model:        string;      // e.g. "llama-1b", "whisper-small", "mock"
  loadPct:      number;      // 0-100
  cellsHandled: number;
  satsEarned:   number;
  registeredAt: number;
  lastSeen:     number;
  active:       boolean;
  missedBeats:  number;
}

// ── State ─────────────────────────────────────────────────────────────────────

const workers = new Map<string, WorkerRecord>();
let registrationCount = 0;
let totalDeregistrations = 0;

// ── Helpers ───────────────────────────────────────────────────────────────────

function matchesTypeFilter(typePath: string, filter: string): boolean {
  if (filter.endsWith('.*')) return typePath.startsWith(filter.slice(0, -1));
  if (filter.endsWith('*'))  return typePath.startsWith(filter.slice(0, -1));
  return typePath === filter;
}

function workerMatchesType(worker: WorkerRecord, typePath: string): boolean {
  return worker.typePaths.some(f => matchesTypeFilter(typePath, f));
}

function activeWorkers(): WorkerRecord[] {
  return [...workers.values()].filter(w => w.active);
}

function generateWorkerId(): string {
  return crypto.randomUUID().replace(/-/g, '').slice(0, 16);
}

// ── Staleness checker — runs every heartbeat interval ─────────────────────────

setInterval(() => {
  const now = Date.now();
  for (const [id, w] of workers) {
    if (!w.active) continue;
    const elapsed = now - w.lastSeen;
    if (elapsed > HEARTBEAT_MS * 1.5) {
      w.missedBeats = Math.floor(elapsed / HEARTBEAT_MS);
      if (w.missedBeats >= MAX_MISS) {
        w.active = false;
        console.log(`[registry] Worker ${id} (${w.nodeIp} ${w.model}) marked inactive — ${w.missedBeats} missed heartbeats`);
      }
    }
  }
  // Evict records older than 5 minutes and inactive
  for (const [id, w] of workers) {
    if (!w.active && now - w.lastSeen > 300_000) {
      workers.delete(id);
    }
  }
}, HEARTBEAT_MS);

// ── HTTP helpers ──────────────────────────────────────────────────────────────

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
  });
}

// ── Server ────────────────────────────────────────────────────────────────────

const server = Bun.serve({
  port: PORT,

  fetch(req: Request) {
    const url    = new URL(req.url);
    const path   = url.pathname;
    const method = req.method;

    if (method === 'OPTIONS') {
      return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type' } });
    }

    // ── POST /workers/register ───────────────────────────────────────────────
    if (path === '/workers/register' && method === 'POST') {
      return req.json().then((body: any) => {
        const workerId = body.workerId ?? generateWorkerId();
        const record: WorkerRecord = {
          workerId,
          nodeIp:       body.nodeIp     ?? '127.0.0.1',
          typePaths:    Array.isArray(body.typePaths) ? body.typePaths : [body.typePaths ?? 'inference.*'],
          model:        body.model      ?? 'mock',
          loadPct:      body.loadPct    ?? 0,
          cellsHandled: body.cellsHandled ?? 0,
          satsEarned:   body.satsEarned ?? 0,
          registeredAt: Date.now(),
          lastSeen:     Date.now(),
          active:       true,
          missedBeats:  0,
        };
        workers.set(workerId, record);
        registrationCount++;
        console.log(`[registry] +worker ${workerId} @ ${record.nodeIp} — model:${record.model} types:[${record.typePaths.join(',')}]`);
        return json({ workerId, registered: true });
      });
    }

    // ── POST /workers/heartbeat/:workerId ────────────────────────────────────
    const hbMatch = path.match(/^\/workers\/heartbeat\/([a-zA-Z0-9_-]{8,36})$/);
    if (hbMatch && method === 'POST') {
      const workerId = hbMatch[1];
      const worker = workers.get(workerId);
      if (!worker) return json({ error: 'not found' }, 404);
      return req.json().then((body: any) => {
        worker.lastSeen     = Date.now();
        worker.loadPct      = body.loadPct      ?? worker.loadPct;
        worker.cellsHandled = body.cellsHandled ?? worker.cellsHandled;
        worker.satsEarned   = body.satsEarned   ?? worker.satsEarned;
        worker.active       = true;
        worker.missedBeats  = 0;
        return json({ ok: true, workerId });
      });
    }

    // ── DELETE /workers/:workerId ────────────────────────────────────────────
    const delMatch = path.match(/^\/workers\/([a-zA-Z0-9_-]{8,36})$/);
    if (delMatch && method === 'DELETE') {
      const workerId = delMatch[1];
      const existed = workers.has(workerId);
      if (existed) {
        const w = workers.get(workerId)!;
        w.active = false;
        totalDeregistrations++;
        console.log(`[registry] -worker ${workerId} @ ${w.nodeIp} deregistered (${w.cellsHandled} cells, ${w.satsEarned} sats)`);
      }
      return json({ ok: existed, workerId });
    }

    // ── GET /workers/available?typePath=inference.safety.* ───────────────────
    if (path === '/workers/available' && method === 'GET') {
      const typePath  = url.searchParams.get('typePath') ?? '';
      const maxLoad   = Number(url.searchParams.get('maxLoad') ?? '80');
      const available = activeWorkers().filter(w =>
        (!typePath || workerMatchesType(w, typePath)) && w.loadPct < maxLoad
      );
      // Sort by loadPct ascending (least loaded first)
      available.sort((a, b) => a.loadPct - b.loadPct);
      return json({ typePath, available, count: available.length });
    }

    // ── GET /workers ─────────────────────────────────────────────────────────
    if (path === '/workers' && method === 'GET') {
      const includeInactive = url.searchParams.get('inactive') === '1';
      const list = includeInactive ? [...workers.values()] : activeWorkers();
      return json({
        total: workers.size,
        active: activeWorkers().length,
        workers: list,
      });
    }

    // ── GET /health ──────────────────────────────────────────────────────────
    if (path === '/health' && method === 'GET') {
      const active = activeWorkers();
      const byModel: Record<string, number> = {};
      const byType:  Record<string, number> = {};
      for (const w of active) {
        byModel[w.model] = (byModel[w.model] ?? 0) + 1;
        for (const t of w.typePaths) byType[t] = (byType[t] ?? 0) + 1;
      }
      return json({
        service: 'worker-registry',
        port: PORT,
        totalWorkers: workers.size,
        activeWorkers: active.length,
        registrationCount,
        totalDeregistrations,
        avgLoadPct: active.length ? Math.round(active.reduce((s, w) => s + w.loadPct, 0) / active.length) : 0,
        totalCellsHandled: [...workers.values()].reduce((s, w) => s + w.cellsHandled, 0),
        totalSatsEarned:   [...workers.values()].reduce((s, w) => s + w.satsEarned, 0),
        byModel,
        byTypePath: byType,
      });
    }

    return json({ error: 'not found' }, 404);
  },
});

console.log(`
╔══════════════════════════════════════════════════════════╗
║   worker-registry  :${PORT}                             ║
║   Distributed Inference Worker Registry                 ║
╠══════════════════════════════════════════════════════════╣
║   POST /workers/register        announce capabilities   ║
║   POST /workers/heartbeat/:id   update load + stats     ║
║   GET  /workers                 list active workers     ║
║   GET  /workers/available       query by typePath       ║
║   DELETE /workers/:id           deregister              ║
║   GET  /health                  registry health         ║
╠══════════════════════════════════════════════════════════╣
║   TTL: ${WORKER_TTL}ms · Max missed beats: ${MAX_MISS}                  ║
╚══════════════════════════════════════════════════════════╝
`);

```
