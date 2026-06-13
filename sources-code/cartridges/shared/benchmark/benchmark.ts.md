---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/benchmark/benchmark.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.439369+00:00
---

# cartridges/shared/benchmark/benchmark.ts

```ts
#!/usr/bin/env bun
/**
 * benchmark.ts — Skyminer mesh + policy + CashLanes throughput harness
 *
 * Measures the real performance ceiling of each layer in the layer-collapse
 * demo stack, without mocking anything.
 *
 * Sweep 1 — Gossip throughput
 *   Sends synthetic cell publish events to the multicast relay (:5199) at
 *   increasing rates (10 → 100 → 500 → 1000 req/s) and measures latency
 *   distribution and error rate.  Relay must be running; if not, this sweep
 *   is skipped and reported as "relay offline".
 *
 * Sweep 2 — Policy evaluation rate
 *   Runs the Rúnar-compiled Bitcoin Script predicates (route_accept and
 *   tier_prefix_product) inline using the same script interpreter the
 *   backtest uses.  No HTTP — pure in-process throughput.  Reports how many
 *   policy evaluations per second a single JS thread can sustain.
 *
 * Sweep 3 — CashLanes advance rate
 *   If the bridge (:5198) is running and channel is FLOW_ACTIVE, fires
 *   POST /channel/advance in a tight loop and measures advances/sec and
 *   the wall-clock latency until auto-settlement fires (if it fires).
 *   If the bridge is offline or the channel is not FLOW_ACTIVE, reports
 *   that and skips.
 *
 * Usage:
 *   bun cartridges/shared/benchmark/benchmark.ts
 *   bun cartridges/shared/benchmark/benchmark.ts --relay http://localhost:5199 --bridge http://localhost:5198
 *   bun cartridges/shared/benchmark/benchmark.ts --sweep policy      (policy only)
 *   bun cartridges/shared/benchmark/benchmark.ts --sweep gossip      (gossip only)
 *   bun cartridges/shared/benchmark/benchmark.ts --sweep cashlanes   (CashLanes only)
 */

// ── Config ────────────────────────────────────────────────────────────────────

const args   = process.argv.slice(2);
const flag   = (f: string) => { const i = args.indexOf(f); return i !== -1 ? args[i + 1] : undefined; };
const has    = (f: string) => args.includes(f);

const RELAY_URL  = flag('--relay')  ?? 'http://localhost:5199';
const BRIDGE_URL = flag('--bridge') ?? 'http://localhost:5198';
const SWEEP      = flag('--sweep');          // 'gossip' | 'policy' | 'cashlanes' | undefined (all)

const GOSSIP_RATES   = [10, 50, 100, 500, 1000]; // req/s
const GOSSIP_SECS    = 3;                          // seconds per rate step
const POLICY_SECS    = 5;                          // seconds for policy eval burst
const CASHLANES_N    = 60;                         // advances to fire

// ── Colours ───────────────────────────────────────────────────────────────────

const C = {
  reset:  '\x1b[0m',
  bold:   '\x1b[1m',
  dim:    '\x1b[2m',
  green:  '\x1b[32m',
  yellow: '\x1b[33m',
  red:    '\x1b[31m',
  cyan:   '\x1b[36m',
  white:  '\x1b[37m',
};

function hl(s: string | number) { return `${C.cyan}${s}${C.reset}`; }
function ok(s: string | number) { return `${C.green}${s}${C.reset}`; }
function warn(s: string | number) { return `${C.yellow}${s}${C.reset}`; }
function err(s: string | number) { return `${C.red}${s}${C.reset}`; }

// ── Timing helpers ────────────────────────────────────────────────────────────

function now() { return performance.now(); }

interface LatencyStats {
  count:  number;
  errors: number;
  p50:    number;
  p99:    number;
  maxMs:  number;
  rps:    number;
}

function percentile(sorted: number[], p: number): number {
  if (sorted.length === 0) return 0;
  const idx = Math.floor((p / 100) * (sorted.length - 1));
  return sorted[Math.min(idx, sorted.length - 1)]!;
}

function statsFrom(samples: number[], durationMs: number, errors: number): LatencyStats {
  const sorted = [...samples].sort((a, b) => a - b);
  return {
    count:  samples.length,
    errors,
    p50:    +percentile(sorted, 50).toFixed(2),
    p99:    +percentile(sorted, 99).toFixed(2),
    maxMs:  +(sorted.at(-1) ?? 0).toFixed(2),
    rps:    +((samples.length / durationMs) * 1000).toFixed(1),
  };
}

// ── Script interpreter (inline — same logic as ixp-routing/scripts) ───────────
// Avoids cross-directory relative import issues when run from any cwd.

type ScriptStack = bigint[];

function readCScriptNum(buf: Uint8Array): bigint {
  if (buf.length === 0) return 0n;
  let val = 0n;
  for (let i = 0; i < buf.length; i++) {
    val |= BigInt(buf[i]!) << BigInt(8 * i);
  }
  const negative = (buf[buf.length - 1]! & 0x80) !== 0;
  if (negative) {
    const mask = (1n << BigInt(8 * buf.length - 1)) - 1n;
    val = -(val & mask);
  }
  return val;
}

function encodeScriptNum(n: bigint): Uint8Array {
  if (n === 0n) return new Uint8Array(0);
  const neg = n < 0n;
  let abs = neg ? -n : n;
  const bytes: number[] = [];
  while (abs > 0n) { bytes.push(Number(abs & 0xffn)); abs >>= 8n; }
  if (bytes[bytes.length - 1]! & 0x80) bytes.push(neg ? 0x80 : 0x00);
  else if (neg) bytes[bytes.length - 1]! |= 0x80;
  return new Uint8Array(bytes);
}

function pushSmallInt(n: number): Uint8Array {
  const encoded = encodeScriptNum(BigInt(n));
  const out = new Uint8Array(1 + encoded.length);
  out[0] = encoded.length; // push <len>
  out.set(encoded, 1);
  return out;
}

function concat(...arrs: Uint8Array[]): Uint8Array {
  const total = arrs.reduce((s, a) => s + a.length, 0);
  const out = new Uint8Array(total);
  let off = 0;
  for (const a of arrs) { out.set(a, off); off += a.length; }
  return out;
}

function hexToBytes(hex: string): Uint8Array {
  const h = hex.trim();
  const out = new Uint8Array(h.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(h.slice(i * 2, i * 2 + 2), 16);
  return out;
}

function execute(script: Uint8Array): { ok: boolean; opcount: number } {
  const stack: ScriptStack = [];
  let pc = 0, opcount = 0;

  while (pc < script.length) {
    const op = script[pc++]!;
    opcount++;

    if (op >= 0x01 && op <= 0x4b) {
      const n = op;
      if (pc + n > script.length) return { ok: false, opcount };
      stack.push(readCScriptNum(script.subarray(pc, pc + n)));
      pc += n;
    } else if (op === 0x00) {
      stack.push(0n);
    } else if (op === 0x51) {
      stack.push(1n);
    } else if (op === 0x69) { // OP_VERIFY
      const v = stack.pop();
      if (v === undefined || v === 0n) return { ok: false, opcount };
    } else if (op === 0x75) { // OP_DROP
      if (stack.length < 1) return { ok: false, opcount };
      stack.pop();
    } else if (op === 0x76) { // OP_DUP
      if (stack.length < 1) return { ok: false, opcount };
      stack.push(stack[stack.length - 1]!);
    } else if (op === 0x77) { // OP_NIP
      if (stack.length < 2) return { ok: false, opcount };
      stack.splice(stack.length - 2, 1);
    } else if (op === 0x78) { // OP_OVER
      if (stack.length < 2) return { ok: false, opcount };
      stack.push(stack[stack.length - 2]!);
    } else if (op === 0x7c) { // OP_SWAP
      if (stack.length < 2) return { ok: false, opcount };
      const a = stack[stack.length - 1]!, b = stack[stack.length - 2]!;
      stack[stack.length - 1] = b; stack[stack.length - 2] = a;
    } else if (op === 0x87) { // OP_EQUAL
      if (stack.length < 2) return { ok: false, opcount };
      const a = stack.pop()!, b = stack.pop()!;
      stack.push(a === b ? 1n : 0n);
    } else if (op === 0x8b) { // OP_1ADD
      if (stack.length < 1) return { ok: false, opcount };
      stack.push(stack.pop()! + 1n);
    } else if (op === 0x95) { // OP_MUL
      if (stack.length < 2) return { ok: false, opcount };
      stack.push(stack.pop()! * stack.pop()!);
    } else if (op === 0x9a) { // OP_BOOLAND
      if (stack.length < 2) return { ok: false, opcount };
      const a = stack.pop()!, b = stack.pop()!;
      stack.push((a !== 0n && b !== 0n) ? 1n : 0n);
    } else if (op === 0x9c) { // OP_NUMEQUAL
      if (stack.length < 2) return { ok: false, opcount };
      stack.push(stack.pop()! === stack.pop()! ? 1n : 0n);
    } else if (op === 0xa0) { // OP_GREATERTHAN
      if (stack.length < 2) return { ok: false, opcount };
      const top = stack.pop()!, second = stack.pop()!;
      stack.push(second > top ? 1n : 0n);
    } else if (op === 0xa1) { // OP_LESSTHANOREQUAL
      if (stack.length < 2) return { ok: false, opcount };
      const top = stack.pop()!, second = stack.pop()!;
      stack.push(second <= top ? 1n : 0n);
    } else if (op === 0xa2) { // OP_GREATERTHANOREQUAL
      if (stack.length < 2) return { ok: false, opcount };
      const top = stack.pop()!, second = stack.pop()!;
      stack.push(second >= top ? 1n : 0n);
    } else if (op === 0x6d) { // OP_2DROP
      if (stack.length < 2) return { ok: false, opcount };
      stack.pop(); stack.pop();
    } else {
      return { ok: false, opcount };
    }
  }

  const top = stack[stack.length - 1];
  return { ok: top !== undefined && top !== 0n, opcount };
}

function evaluatePredicate(predicateHex: Uint8Array, tier: number, prefixLen: number) {
  return execute(concat(pushSmallInt(tier), pushSmallInt(prefixLen), predicateHex));
}

// ── Strategy bytes ─────────────────────────────────────────────────────────────

const ROUTE_ACCEPT        = hexToBytes('760110a269750101a2950120a2');
const TIER_PREFIX_PRODUCT = hexToBytes('950120a2');

// ── Synthetic BGP events ───────────────────────────────────────────────────────

function mulberry32(seed: number) {
  let s = seed;
  return () => {
    s |= 0; s += 0x6d2b79f5 | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = t + Math.imul(t ^ (t >>> 7), 61 | t) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rng = mulberry32(1337);

function syntheticBgpEvent(): { tier: number; prefixLen: number } {
  const t = rng();
  const tier = t < 0.15 ? 3 : t < 0.5 ? 2 : t < 0.9 ? 1 : 0;
  const prefixLen = 16 + Math.floor(rng() * 16);
  return { tier, prefixLen };
}

// ── Table rendering ───────────────────────────────────────────────────────────

type Row = {
  layer: string;
  target: string;
  achieved: string;
  p50: string;
  p99: string;
  bottleneck: string;
};

function printTable(rows: Row[]) {
  const cols: (keyof Row)[] = ['layer', 'target', 'achieved', 'p50', 'p99', 'bottleneck'];
  const headers: Record<keyof Row, string> = {
    layer: 'Layer', target: 'Target rate', achieved: 'Achieved',
    p50: 'p50 ms', p99: 'p99 ms', bottleneck: 'Bottleneck',
  };
  const widths = cols.map(c => Math.max(headers[c].length, ...rows.map(r => r[c].length)));

  const line = widths.map(w => '─'.repeat(w + 2)).join('┼');
  const header = cols.map((c, i) => ` ${headers[c].padEnd(widths[i]!)} `).join('│');
  console.log(`\n┌${line.replaceAll('┼', '┬')}┐`);
  console.log(`│${header}│`);
  console.log(`├${line}┤`);
  for (const r of rows) {
    const row = cols.map((c, i) => ` ${r[c].padEnd(widths[i]!)} `).join('│');
    console.log(`│${row}│`);
  }
  console.log(`└${line.replaceAll('┼', '┴')}┘`);
}

// ── Sweep 1: Gossip throughput ────────────────────────────────────────────────

async function sweepGossip(): Promise<Row[]> {
  console.log(`\n${C.bold}═══ Sweep 1: Gossip throughput → ${RELAY_URL} ═══${C.reset}`);

  // Check relay is up
  try {
    const h = await fetch(`${RELAY_URL}/health`, { signal: AbortSignal.timeout(1500) });
    if (!h.ok) throw new Error(`HTTP ${h.status}`);
    console.log(ok('  ✓ relay online'));
  } catch (e: any) {
    console.log(warn(`  ⚠ relay offline (${e.message}) — skipping gossip sweep`));
    return [{
      layer: 'Gossip', target: 'N/A', achieved: 'SKIPPED',
      p50: '—', p99: '—', bottleneck: 'relay offline',
    }];
  }

  const rows: Row[] = [];
  let saturated = false;

  for (const targetRps of GOSSIP_RATES) {
    if (saturated) break;
    const intervalMs = 1000 / targetRps;
    const totalMs    = GOSSIP_SECS * 1000;
    const latencies: number[] = [];
    let errors = 0;
    let gated402 = 0;
    const start = now();

    process.stdout.write(`  ${hl(targetRps)} req/s for ${GOSSIP_SECS}s … `);

    const sends: Promise<void>[] = [];
    let sent = 0;
    const deadline = start + totalMs;

    // Fire requests at target rate using precise interval scheduling
    while (now() < deadline) {
      const t0 = now();
      sends.push(
        fetch(`${RELAY_URL}/publish`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            typePath: 'ixp.route.accept',
            verdict: true,
            inputs: { asnTier: 1, prefixLen: 24 },
            strategyHex: '760110a269750101a2950120a2',
          }),
          signal: AbortSignal.timeout(2000),
        }).then(async r => {
          const ms = now() - t0;
          if (r.ok) {
            latencies.push(ms);
          } else if (r.status === 402) {
            latencies.push(ms);
            gated402++;
          } else {
            errors++;
          }
        }).catch(() => { errors++; }),
      );
      sent++;

      // Throttle to target rate
      const elapsed = now() - start;
      const expected = sent * intervalMs;
      const drift = expected - elapsed;
      if (drift > 0.5) await new Promise(r => setTimeout(r, drift));
    }

    await Promise.all(sends);
    const durationMs = now() - start;
    const stats = statsFrom(latencies, durationMs, errors);
    const pctErr  = errors > 0 ? `${((errors / sent) * 100).toFixed(0)}% err` : 'no errors';
    const gatedStr = gated402 === sent ? 'all gated (x402 — fund channel to accept)' :
                     gated402 > 0     ? `${gated402} gated (x402)` : '';
    const status = gatedStr || pctErr;

    console.log(`${ok(stats.rps + ' rps')} p50=${hl(stats.p50 + 'ms')} p99=${hl(stats.p99 + 'ms')} ${status}`);

    // Saturation heuristic: p99 > 500ms or >5% error rate
    if (stats.p99 > 500 || errors / sent > 0.05) {
      saturated = true;
      console.log(warn(`  ↳ saturating at ~${stats.rps} rps (p99 spike / errors)`));
    }

    rows.push({
      layer:     `Gossip ${targetRps}rps`,
      target:    `${targetRps} req/s`,
      achieved:  `${stats.rps} rps`,
      p50:       `${stats.p50}`,
      p99:       `${stats.p99}`,
      bottleneck: saturated ? 'relay CPU / UDP backpressure' : gated402 === sent ? 'x402 gated' : 'none yet',
    });
  }

  return rows;
}

// ── Sweep 2: Policy evaluation rate ──────────────────────────────────────────

async function sweepPolicy(): Promise<Row[]> {
  console.log(`\n${C.bold}═══ Sweep 2: Policy evaluation rate (in-process) ═══${C.reset}`);

  const strategies: Array<{ name: string; bytes: Uint8Array }> = [
    { name: 'route_accept (13B)',        bytes: ROUTE_ACCEPT },
    { name: 'tier_prefix_product (4B)',  bytes: TIER_PREFIX_PRODUCT },
  ];

  const rows: Row[] = [];

  for (const { name, bytes } of strategies) {
    process.stdout.write(`  ${hl(name)} … `);
    let count = 0;
    const start = now();
    const deadline = start + POLICY_SECS * 1000;

    while (now() < deadline) {
      // Burst 1000 evaluations before checking time (avoids now() call overhead)
      for (let i = 0; i < 1000; i++) {
        const { tier, prefixLen } = syntheticBgpEvent();
        evaluatePredicate(bytes, tier, prefixLen);
        count++;
      }
    }

    const elapsed = now() - start;
    const eventsPerSec = Math.round((count / elapsed) * 1000);
    console.log(`${ok(eventsPerSec.toLocaleString() + '/sec')} (${count.toLocaleString()} evals in ${(elapsed / 1000).toFixed(1)}s)`);

    rows.push({
      layer:      `Policy: ${name}`,
      target:     'max throughput',
      achieved:   `${eventsPerSec.toLocaleString()}/sec`,
      p50:        `${+(1_000_000 / eventsPerSec).toFixed(3)}µs`,
      p99:        '~same',
      bottleneck: 'JS thread (single-core)',
    });
  }

  return rows;
}

// ── Sweep 3: CashLanes advance rate ──────────────────────────────────────────

async function sweepCashLanes(): Promise<Row[]> {
  console.log(`\n${C.bold}═══ Sweep 3: CashLanes advance rate → ${BRIDGE_URL} ═══${C.reset}`);

  // Check bridge + channel state
  let state: string;
  try {
    const r = await fetch(`${BRIDGE_URL}/channel/state`, { signal: AbortSignal.timeout(1500) });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const j = await r.json() as { state: string };
    state = j.state;
  } catch (e: any) {
    console.log(warn(`  ⚠ bridge offline (${e.message}) — skipping CashLanes sweep`));
    return [{ layer: 'CashLanes', target: 'N/A', achieved: 'SKIPPED', p50: '—', p99: '—', bottleneck: 'bridge offline' }];
  }

  if (state !== 'FLOW_ACTIVE') {
    console.log(warn(`  ⚠ channel state is ${state} (need FLOW_ACTIVE) — skipping`));
    console.log(warn(`    Fund and start the channel via the IXP dashboard first.`));
    return [{ layer: 'CashLanes', target: 'N/A', achieved: 'SKIPPED', p50: '—', p99: '—', bottleneck: `channel ${state}` }];
  }

  console.log(ok(`  ✓ bridge online, channel FLOW_ACTIVE`));
  console.log(`  Firing ${CASHLANES_N} sequential advances…`);

  const latencies: number[] = [];
  let errors = 0;
  let settlementFiredMs: number | null = null;
  const sweepStart = now();

  // Open SSE to detect when a settlement fires.
  // Bun has no global EventSource — use fetch + ReadableStream line parser.
  const settlementPromise = (async (): Promise<number> => {
    const ctrl = new AbortController();
    setTimeout(() => ctrl.abort(), 60_000);
    try {
      const r = await fetch(`${BRIDGE_URL}/channel/events`, {
        headers: { Accept: 'text/event-stream' },
        signal: ctrl.signal,
      });
      if (!r.ok || !r.body) return -1;
      const reader = r.body.getReader();
      const dec = new TextDecoder();
      let buf = '';
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buf += dec.decode(value, { stream: true });
        const lines = buf.split('\n');
        buf = lines.pop()!;
        for (const line of lines) {
          if (line.startsWith('event: settlement')) {
            ctrl.abort();
            return now() - sweepStart;
          }
        }
      }
    } catch { /* timeout or abort */ }
    return -1;
  })();

  // Fire N advances sequentially (measures per-advance round-trip, not parallel)
  for (let i = 0; i < CASHLANES_N; i++) {
    const t0 = now();
    try {
      const r = await fetch(`${BRIDGE_URL}/channel/advance`, {
        method: 'POST',
        signal: AbortSignal.timeout(3000),
      });
      const ms = now() - t0;
      if (r.ok) latencies.push(ms);
      else errors++;
    } catch { errors++; }

    if (i % 10 === 9) process.stdout.write('.');
  }
  console.log();

  const advanceDurationMs = now() - sweepStart;
  const stats = statsFrom(latencies, advanceDurationMs, errors);

  console.log(`  ${ok(stats.rps + ' advances/sec')} p50=${hl(stats.p50 + 'ms')} p99=${hl(stats.p99 + 'ms')}`);

  // Wait up to 30s for settlement SSE event (timeout is baked into settlementPromise)
  process.stdout.write('  Waiting for auto-settlement to fire… ');
  settlementFiredMs = await settlementPromise;

  if (settlementFiredMs > 0) {
    console.log(ok(`settlement fired at ${settlementFiredMs.toFixed(0)}ms from sweep start`));
  } else {
    console.log(warn(`no settlement in 30s (may need more advances to hit auto-settle threshold)`));
  }

  return [{
    layer:      'CashLanes advance',
    target:     `${CASHLANES_N} advances`,
    achieved:   `${stats.rps} advances/sec`,
    p50:        `${stats.p50}`,
    p99:        `${stats.p99}`,
    bottleneck: stats.p99 > 100 ? 'bridge HTTP round-trip' : 'none',
  }, {
    layer:      'CashLanes settle',
    target:     'auto on threshold',
    achieved:   settlementFiredMs > 0 ? `${settlementFiredMs.toFixed(0)}ms wall` : 'not triggered',
    p50:        '—',
    p99:        '—',
    bottleneck: 'Metanet Desktop createAction (2× BSV tx)',
  }];
}

// ── Sweep 4: Headless wallet construction throughput ──────────────────────────
//
// Measures how fast the headless wallet can locally:
//   a) Derive P2PKH address (hash160 + base58check) — once
//   b) Compute BIP143 sighash — per tx
//   c) Sign (secp256k1 ECDSA, low-S, DER encode) — per tx
//   d) Build EF transaction (serialize) — per tx
//
// Does NOT require live UTXOs or ARC access (dry run with synthetic UTXO).
// The ARC broadcast latency (~50-100ms) is the real-world ceiling; local
// construction is the floor — this sweep measures just the floor.

async function sweepHeadlessWallet(): Promise<Row[]> {
  console.log(`\n${C.bold}${C.cyan}──── Sweep 4: Headless Wallet Construction ─────────────────${C.reset}`);

  const { sha256 } = await import('@noble/hashes/sha2');
  const { ripemd160 } = await import('@noble/hashes/ripemd160');
  const { hmac } = await import('@noble/hashes/hmac');
  const secp = await import('@noble/secp256k1');

  // Wire secp HMAC-SHA256 sync backend (safe to call multiple times).
  secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]) =>
    hmac(sha256, key, secp.etc.concatBytes(...msgs));

  function hash256(b: Uint8Array) { return sha256(sha256(b)); }
  function hash160(b: Uint8Array) { return ripemd160(sha256(b)); }
  function le4(n: number) { const b=new Uint8Array(4); new DataView(b.buffer).setUint32(0,n>>>0,true); return b; }
  function le8(n: bigint) { const b=new Uint8Array(8); new DataView(b.buffer).setBigUint64(0,n,true); return b; }
  function varInt(n: number) { return n<0xfd?new Uint8Array([n]):new Uint8Array([0xfd,n&0xff,(n>>8)&0xff]); }
  function cat(parts: Uint8Array[]) {
    const t=parts.reduce((s,p)=>s+p.length,0); const out=new Uint8Array(t); let off=0;
    for(const p of parts){out.set(p,off);off+=p.length;} return out;
  }
  function buildP2pkhLock(h160: Uint8Array) {
    const s=new Uint8Array(25); s[0]=0x76;s[1]=0xa9;s[2]=0x14;s.set(h160,3);s[23]=0x88;s[24]=0xac;return s;
  }
  function encodePush(d: Uint8Array) {
    return d.length<=75?new Uint8Array([d.length,...d]):new Uint8Array([0x4c,d.length,...d]);
  }
  function pushdrop(data: Uint8Array, pk: Uint8Array) {
    const d=encodePush(data),p=encodePush(pk); const out=new Uint8Array(d.length+1+p.length+1); let i=0;
    out.set(d,i);i+=d.length;out[i++]=0x75;out.set(p,i);i+=p.length;out[i]=0xac;return out;
  }
  function derEncode(r: bigint, s: bigint) {
    function tp(n: bigint) {
      const b=new Uint8Array(32); let x=n;
      for(let i=31;i>=0;i--){b[i]=Number(x&0xffn);x>>=8n;}
      let st=0; while(st<b.length-1&&b[st]===0)st++;
      const t=b.subarray(st);
      if((t[0]!&0x80)!==0){const p=new Uint8Array(t.length+1);p.set(t,1);return p;} return t;
    }
    const rB=tp(r),sB=tp(s); const total=2+rB.length+2+sB.length;
    const out=new Uint8Array(2+total);
    out[0]=0x30;out[1]=total;out[2]=0x02;out[3]=rB.length;out.set(rB,4);
    const sOff=4+rB.length;out[sOff]=0x02;out[sOff+1]=sB.length;out.set(sB,sOff+2);return out;
  }

  // Throwaway key + synthetic UTXO.
  const sk   = sha256(new TextEncoder().encode('benchmark-headless-wallet-sweep4'));
  const pk   = secp.getPublicKey(sk, true);
  const lock = buildP2pkhLock(hash160(pk));
  const txid = new Uint8Array(32).fill(0xab);
  const val  = 50_000n;
  const data = new TextEncoder().encode('{"ch":"ixp-bench","mb":5,"sats":50,"seq":99,"role":"consumer"}');
  const EF_MARKER = new Uint8Array([0x00,0x00,0x00,0x00,0x00,0xef]);

  const N = 10_000;
  const SIGHASH_ALL_FORKID = 0x41;

  // ── Sighash computation
  const sighashTimes: number[] = [];
  for (let i = 0; i < N; i++) {
    const t0 = performance.now();
    const anchorScript = pushdrop(data, pk);
    const changeSats = val - 1n - 1200n;
    const outs = [{script:anchorScript,sats:1n},{script:lock,sats:changeSats}];
    const hashPrevouts = hash256(cat([txid,le4(0)]));
    const hashSeq      = hash256(le4(0xffffffff));
    const hashOuts     = hash256(cat(outs.map(o=>cat([le8(o.sats),varInt(o.script.length),o.script]))));
    const preimage = cat([le4(1),hashPrevouts,hashSeq,txid,le4(0),varInt(lock.length),lock,le8(val),le4(0xffffffff),hashOuts,le4(0),le4(SIGHASH_ALL_FORKID)]);
    hash256(preimage); // compute sighash
    sighashTimes.push(performance.now() - t0);
  }
  const shP50 = percentile(sighashTimes, 50);
  const shP99 = percentile(sighashTimes, 99);
  const shRate = Math.round(N / (sighashTimes.reduce((a,b)=>a+b,0)/1000));
  console.log(`  ${ok(shRate + '/sec')} sighash compute      p50=${hl(shP50.toFixed(3)+'ms')} p99=${hl(shP99.toFixed(3)+'ms')}`);

  // ── Sign (secp256k1 ECDSA)
  const signTimes: number[] = [];
  const sighash = hash256(new Uint8Array(32).fill(0xcc)); // fixed hash for repeatability
  for (let i = 0; i < N; i++) {
    const t0 = performance.now();
    const sig = secp.sign(sighash, sk).normalizeS();
    derEncode(sig.r, sig.s);
    signTimes.push(performance.now() - t0);
  }
  const sgP50 = percentile(signTimes, 50);
  const sgP99 = percentile(signTimes, 99);
  const sgRate = Math.round(N / (signTimes.reduce((a,b)=>a+b,0)/1000));
  console.log(`  ${ok(sgRate + '/sec')} ECDSA sign + DER     p50=${hl(sgP50.toFixed(3)+'ms')} p99=${hl(sgP99.toFixed(3)+'ms')}`);

  // ── Full EF tx construction (sighash + sign + serialize)
  const fullTimes: number[] = [];
  for (let i = 0; i < N; i++) {
    const t0 = performance.now();
    // Sighash
    const anchorScript = pushdrop(data, pk);
    const changeSats = val - 1n - 1200n;
    const outs = [{script:anchorScript,sats:1n},{script:lock,sats:changeSats}];
    const hp = hash256(cat([txid,le4(0)]));
    const hs = hash256(le4(0xffffffff));
    const ho = hash256(cat(outs.map(o=>cat([le8(o.sats),varInt(o.script.length),o.script]))));
    const pre = cat([le4(1),hp,hs,txid,le4(0),varInt(lock.length),lock,le8(val),le4(0xffffffff),ho,le4(0),le4(SIGHASH_ALL_FORKID)]);
    const sh = hash256(pre);
    // Sign
    const sig = secp.sign(sh, sk).normalizeS();
    const der = derEncode(sig.r, sig.s);
    // Build unlock script
    const sigLen = der.length + 1;
    const sigPush = new Uint8Array(1+sigLen); sigPush[0]=sigLen; sigPush.set(der,1); sigPush[sigLen]=SIGHASH_ALL_FORKID;
    const pkPush = new Uint8Array(1+pk.length); pkPush[0]=pk.length; pkPush.set(pk,1);
    const unlock = cat([sigPush,pkPush]);
    // Build EF tx
    const serializedOutputs = cat(outs.map(o=>cat([le8(o.sats),varInt(o.script.length),o.script])));
    const efInput = cat([txid,le4(0),varInt(unlock.length),unlock,le4(0xffffffff),le8(val),varInt(lock.length),lock]);
    cat([le4(1),EF_MARKER,varInt(1),efInput,varInt(2),serializedOutputs,le4(0)]);
    fullTimes.push(performance.now() - t0);
  }
  const fullP50 = percentile(fullTimes, 50);
  const fullP99 = percentile(fullTimes, 99);
  const fullRate = Math.round(N / (fullTimes.reduce((a,b)=>a+b,0)/1000));
  console.log(`  ${ok(fullRate + '/sec')} full EF tx build     p50=${hl(fullP50.toFixed(3)+'ms')} p99=${hl(fullP99.toFixed(3)+'ms')}`);
  console.log(`  ${C.dim}(+ ~50-100ms ARC broadcast, not measured here — dry run only)${C.reset}`);

  return [
    {
      layer:      'Headless wallet sighash',
      target:     `${N} iterations`,
      achieved:   `${shRate}/sec`,
      p50:        shP50.toFixed(3),
      p99:        shP99.toFixed(3),
      bottleneck: 'none — pure hash ops',
    },
    {
      layer:      'Headless wallet ECDSA sign+DER',
      target:     `${N} iterations`,
      achieved:   `${sgRate}/sec`,
      p50:        sgP50.toFixed(3),
      p99:        sgP99.toFixed(3),
      bottleneck: 'ECDSA scalar mult (secp256k1)',
    },
    {
      layer:      'Headless wallet full EF tx build',
      target:     `${N} iterations`,
      achieved:   `${fullRate}/sec`,
      p50:        fullP50.toFixed(3),
      p99:        fullP99.toFixed(3),
      bottleneck: 'ECDSA sign dominates; ARC ~50-100ms/tx',
    },
  ];
}

// ── Main ──────────────────────────────────────────────────────────────────────

console.log(`${C.bold}${C.white}
╔═══════════════════════════════════════════════════════════════╗
║  Skyminer Layer-Collapse Benchmark                            ║
║  Three sweeps: gossip · policy · CashLanes                    ║
╚═══════════════════════════════════════════════════════════════╝${C.reset}`);
console.log(`${C.dim}  Relay:  ${RELAY_URL}`);
console.log(`  Bridge: ${BRIDGE_URL}${C.reset}`);

const allRows: Row[] = [];

if (!SWEEP || SWEEP === 'gossip')    allRows.push(...await sweepGossip());
if (!SWEEP || SWEEP === 'policy')    allRows.push(...await sweepPolicy());
if (!SWEEP || SWEEP === 'cashlanes') allRows.push(...await sweepCashLanes());
if (!SWEEP || SWEEP === 'wallet')    allRows.push(...await sweepHeadlessWallet());

console.log(`\n${C.bold}${C.white}═══ Results ═══${C.reset}`);
printTable(allRows);

console.log(`
${C.dim}Run each sweep independently:
  bun cartridges/shared/benchmark/benchmark.ts --sweep policy
  bun cartridges/shared/benchmark/benchmark.ts --sweep gossip
  bun cartridges/shared/benchmark/benchmark.ts --sweep cashlanes
  bun cartridges/shared/benchmark/benchmark.ts --sweep wallet${C.reset}
`);

```
