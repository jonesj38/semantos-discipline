---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/benchmark/check-pis.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.438698+00:00
---

# cartridges/shared/benchmark/check-pis.ts

```ts
#!/usr/bin/env bun
/**
 * check-pis.ts — Skyminer Pi fleet health check
 *
 * Scans the 192.168.0.x subnet (or TARGETS env list) for SSH-reachable
 * Orange Pi Primes.  For each reachable Pi, collects:
 *
 *   - hostname / uptime / free memory
 *   - systemd service status: cell-store, inference-handler, whisper-cpp
 *   - HTTP health: cell-store (:5197), inference-handler (:5196)
 *   - Cell counts from cell-store stats (if running)
 *
 * Prints a clean mesh health table + a per-Pi service detail block.
 *
 * USAGE
 * ─────
 *   bun cartridges/shared/benchmark/check-pis.ts
 *   TARGETS="192.168.0.3 192.168.0.5" bun check-pis.ts
 *   PI_SUBNET=10.0.0 bun check-pis.ts        # scan 10.0.0.2-20
 *   SSH_USER=pi bun check-pis.ts
 *   bun check-pis.ts --json                   # machine-readable JSON output
 *
 * REQUIREMENTS
 * ────────────
 *   SSH key auth to todriguez@ must be configured (ssh-add ~/.ssh/id_rsa)
 *   Pis should be running Armbian with bun installed
 */

import { createHash } from 'node:crypto';

// ── Config ────────────────────────────────────────────────────────────────────

const SSH_USER    = process.env.SSH_USER    ?? 'todriguez';
const PI_SUBNET   = process.env.PI_SUBNET   ?? '192.168.0';
const CONCURRENCY = parseInt(process.env.CONCURRENCY ?? '8', 10);
const SSH_TIMEOUT = parseInt(process.env.SSH_TIMEOUT ?? '5', 10);  // seconds
const JSON_OUT    = process.argv.includes('--json');

const SSH_OPTS = [
  '-o', `ConnectTimeout=${SSH_TIMEOUT}`,
  '-o', 'BatchMode=yes',
  '-o', 'StrictHostKeyChecking=no',
  '-o', 'LogLevel=ERROR',
];

// Target IPs: explicit list or scan range
const TARGETS: string[] = process.env.TARGETS
  ? process.env.TARGETS.trim().split(/\s+/)
  : Array.from({ length: 19 }, (_, i) => `${PI_SUBNET}.${i + 2}`);

// ── Types ─────────────────────────────────────────────────────────────────────

interface ServiceStatus {
  name: string;
  active: boolean;
  status: string;  // 'active' | 'inactive' | 'failed' | 'unknown'
}

interface HttpStatus {
  url: string;
  ok: boolean;
  latencyMs: number;
  body?: unknown;
}

interface PiResult {
  ip:           string;
  reachable:    boolean;
  hostname:     string;
  uptime:       string;
  memFreeMB:    number;
  memTotalMB:   number;
  bunVersion:   string;
  services:     ServiceStatus[];
  http:         HttpStatus[];
  cellCount:    number;
  cellTypes:    Record<string, number>;
  errorMsg?:    string;
  probedMs:     number;
}

// ── SSH helper ────────────────────────────────────────────────────────────────

async function ssh(ip: string, cmd: string, timeoutMs = 8000): Promise<{ out: string; ok: boolean }> {
  try {
    const proc = Bun.spawn(
      ['ssh', ...SSH_OPTS, `${SSH_USER}@${ip}`, cmd],
      { stdout: 'pipe', stderr: 'pipe' },
    );

    const timer = setTimeout(() => { try { proc.kill(); } catch {} }, timeoutMs);
    const [exitCode, stdout, stderr] = await Promise.all([
      proc.exited,
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
    ]);
    clearTimeout(timer);

    return { out: stdout.trim(), ok: exitCode === 0 };
  } catch {
    return { out: '', ok: false };
  }
}

// ── HTTP health check (via the laptop, not the Pi — works when on same LAN) ──

async function httpCheck(url: string, timeoutMs = 3000): Promise<HttpStatus> {
  const t0 = Date.now();
  try {
    const r = await fetch(url, { signal: AbortSignal.timeout(timeoutMs) });
    const body = r.headers.get('content-type')?.includes('json') ? await r.json() : undefined;
    return { url, ok: r.ok, latencyMs: Date.now() - t0, body };
  } catch {
    return { url, ok: false, latencyMs: Date.now() - t0 };
  }
}

// ── Probe one Pi ──────────────────────────────────────────────────────────────

async function probePi(ip: string): Promise<PiResult> {
  const t0 = Date.now();

  // Quick reachability check
  const reach = await ssh(ip, 'echo ok', 4000);
  if (!reach.ok) {
    return {
      ip, reachable: false,
      hostname: '', uptime: '', memFreeMB: 0, memTotalMB: 0, bunVersion: '',
      services: [], http: [], cellCount: 0, cellTypes: {},
      probedMs: Date.now() - t0,
    };
  }

  // Parallel: hostname, uptime, memory, bun version, service statuses
  const [hostnameR, uptimeR, memR, bunR, servicesR] = await Promise.all([
    ssh(ip, 'hostname -s'),
    ssh(ip, 'uptime -p 2>/dev/null || uptime'),
    ssh(ip, "free -m | awk 'NR==2{print $2\" \"$4}'"),
    ssh(ip, 'bun --version 2>/dev/null || echo none'),
    ssh(ip, [
      'cell_store=$(systemctl is-active cell-store 2>/dev/null || echo unknown)',
      'inf_handler=$(systemctl is-active inference-handler 2>/dev/null || echo unknown)',
      'whisper=$(systemctl is-active whisper-cpp 2>/dev/null || echo unknown)',
      'echo "cell-store=$cell_store inference-handler=$inf_handler whisper-cpp=$whisper"',
    ].join('; ')),
  ]);

  // Parse memory
  const [memTotalS, memFreeS] = (memR.out || '0 0').split(' ');
  const memTotalMB = parseInt(memTotalS, 10) || 0;
  const memFreeMB  = parseInt(memFreeS,  10) || 0;

  // Parse services
  const services: ServiceStatus[] = [];
  const svcLine = servicesR.out;
  for (const pair of svcLine.split(' ')) {
    const [name, status] = pair.split('=');
    if (name && status) {
      services.push({ name, active: status === 'active', status });
    }
  }

  // HTTP health checks (from laptop → Pi — works on same LAN)
  const http = await Promise.all([
    httpCheck(`http://${ip}:5197/health`),
    httpCheck(`http://${ip}:5196/health`),
    httpCheck(`http://${ip}:8080/health`),
  ]);

  // Cell stats from cell-store if it's up
  let cellCount = 0;
  let cellTypes: Record<string, number> = {};
  const statsCheck = await httpCheck(`http://${ip}:5197/cells/stats`);
  if (statsCheck.ok && statsCheck.body) {
    const body = statsCheck.body as { total?: number; byTypePath?: Record<string, number> };
    cellCount  = body.total ?? 0;
    cellTypes  = body.byTypePath ?? {};
  }

  return {
    ip,
    reachable: true,
    hostname:    hostnameR.out || ip,
    uptime:      uptimeR.out.replace(/^up\s+/, '').split(',').slice(0, 2).join(',').trim(),
    memFreeMB,
    memTotalMB,
    bunVersion:  bunR.out === 'none' ? '' : bunR.out,
    services,
    http,
    cellCount,
    cellTypes,
    probedMs: Date.now() - t0,
  };
}

// ── Semaphore for concurrency control ─────────────────────────────────────────

async function withConcurrency<T>(
  items: string[],
  limit: number,
  fn: (item: string) => Promise<T>,
): Promise<T[]> {
  const results: T[] = new Array(items.length);
  let idx = 0;

  async function worker() {
    while (idx < items.length) {
      const i = idx++;
      results[i] = await fn(items[i]);
    }
  }

  await Promise.all(Array.from({ length: limit }, () => worker()));
  return results;
}

// ── Table rendering ───────────────────────────────────────────────────────────

const C = {
  reset:  '\x1b[0m',
  bold:   '\x1b[1m',
  dim:    '\x1b[2m',
  green:  '\x1b[32m',
  yellow: '\x1b[33m',
  red:    '\x1b[31m',
  cyan:   '\x1b[36m',
  white:  '\x1b[97m',
};

function statusDot(active: boolean, status: string): string {
  if (status === 'unknown') return `${C.dim}·${C.reset}`;
  if (active)               return `${C.green}●${C.reset}`;
  if (status === 'failed')  return `${C.red}✗${C.reset}`;
  return `${C.yellow}○${C.reset}`;
}

function memBar(freeMB: number, totalMB: number): string {
  if (!totalMB) return '  n/a  ';
  const used = totalMB - freeMB;
  const pct  = Math.round((used / totalMB) * 100);
  const bar  = Math.round(pct / 10);
  const filled = '█'.repeat(bar) + '░'.repeat(10 - bar);
  const color = pct > 80 ? C.red : pct > 60 ? C.yellow : C.green;
  return `${color}${filled}${C.reset} ${pct}%`;
}

function svcSymbols(services: ServiceStatus[]): string {
  const map: Record<string, string> = {
    'cell-store':         'CS',
    'inference-handler':  'IH',
    'whisper-cpp':        'WH',
  };
  return services.map(s => {
    const label = map[s.name] ?? s.name.slice(0, 2).toUpperCase();
    return s.active
      ? `${C.green}${label}${C.reset}`
      : s.status === 'unknown'
        ? `${C.dim}${label}${C.reset}`
        : `${C.red}${label}${C.reset}`;
  }).join(' ');
}

function renderTable(results: PiResult[]): void {
  const up   = results.filter(r => r.reachable);
  const down  = results.filter(r => !r.reachable);

  console.log(`\n${C.bold}${C.cyan}  Skyminer Mesh — Pi Fleet Health${C.reset}  ${new Date().toLocaleTimeString()}`);
  console.log(`  ${up.length} reachable  ${down.length} offline  of ${results.length} probed\n`);

  if (up.length === 0) {
    console.log(`${C.yellow}  No Pis reachable. Check SSH keys and LAN connectivity.${C.reset}\n`);
    return;
  }

  // Header
  const H = (s: string) => `${C.bold}${s}${C.reset}`;
  console.log(
    `  ${H('IP')}              ${H('Host')}         ${H('Uptime')}              ${H('RAM')}               ${H('Services')}      ${H('Cells')}   ${H('ms')}`,
  );
  console.log('  ' + '─'.repeat(100));

  for (const r of up) {
    const ip       = r.ip.padEnd(16);
    const host     = r.hostname.slice(0, 12).padEnd(12);
    const uptime   = r.uptime.slice(0, 20).padEnd(20);
    const mem      = memBar(r.memFreeMB, r.memTotalMB).padEnd(30);
    const svcs     = svcSymbols(r.services).padEnd(28);
    const cells    = String(r.cellCount).padStart(5);
    const ms       = String(r.probedMs).padStart(5) + 'ms';
    console.log(`  ${ip}  ${host}  ${uptime}  ${mem}  ${svcs}  ${cells}   ${ms}`);
  }

  if (down.length > 0) {
    console.log('  ' + '─'.repeat(100));
    console.log(`  ${C.dim}offline: ${down.map(r => r.ip).join('  ')}${C.reset}`);
  }

  // Service legend
  console.log(`\n  ${C.dim}CS=cell-store(:5197)  IH=inference-handler(:5196)  WH=whisper-cpp(:8080)${C.reset}`);
  console.log(`  ${C.green}●${C.reset}=active  ${C.yellow}○${C.reset}=inactive  ${C.red}✗${C.reset}=failed  ${C.dim}·${C.reset}=unknown\n`);

  // Per-Pi detail for any with issues or interesting stats
  for (const r of up) {
    const hasIssue = r.services.some(s => !s.active && s.status !== 'unknown');
    const hasCells = r.cellCount > 0;
    if (!hasIssue && !hasCells && !r.bunVersion) continue;

    console.log(`  ${C.bold}${r.hostname}${C.reset} (${r.ip})`);
    if (r.bunVersion) console.log(`    bun ${r.bunVersion}`);

    for (const s of r.services) {
      const dot = statusDot(s.active, s.status);
      console.log(`    ${dot} ${s.name.padEnd(22)} ${s.status}`);
    }

    if (hasCells) {
      console.log(`    ${C.cyan}${r.cellCount} cells stored${C.reset}`);
      for (const [typePath, count] of Object.entries(r.cellTypes).slice(0, 5)) {
        console.log(`      ${C.dim}${typePath.padEnd(32)}${C.reset}  ${count}`);
      }
    }

    // HTTP health
    for (const h of r.http) {
      const port = h.url.match(/:(\d+)\//)?.[1];
      if (port) {
        const symbol = h.ok ? `${C.green}✓${C.reset}` : `${C.red}✗${C.reset}`;
        console.log(`    ${symbol} :${port}  ${h.latencyMs}ms`);
      }
    }
    console.log('');
  }
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  if (!JSON_OUT) {
    console.log(`\n  ${C.dim}Probing ${TARGETS.length} IPs on ${PI_SUBNET}.x (up to ${CONCURRENCY} parallel)…${C.reset}`);
  }

  const results = await withConcurrency(TARGETS, CONCURRENCY, probePi);

  if (JSON_OUT) {
    console.log(JSON.stringify(results, null, 2));
    return;
  }

  renderTable(results);

  const up = results.filter(r => r.reachable);
  const totalCells = up.reduce((s, r) => s + r.cellCount, 0);
  const allServices = up.flatMap(r => r.services);
  const activeCount = allServices.filter(s => s.active).length;
  const totalSvcChecks = allServices.length;

  console.log(`  Mesh summary: ${up.length} nodes  ${totalCells} total cells stored  ${activeCount}/${totalSvcChecks} services active\n`);
}

main().catch(e => { console.error(e); process.exit(1); });

```
