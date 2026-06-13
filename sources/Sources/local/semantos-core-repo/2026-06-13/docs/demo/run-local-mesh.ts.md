---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/demo/run-local-mesh.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.749430+00:00
---

# docs/demo/run-local-mesh.ts

```ts
#!/usr/bin/env bun
/**
 * run-local-mesh.ts — local MNCA mesh harness for the demo.
 *
 * Spins up N mesh-node processes on IPv6 loopback multicast, plus
 * mesh-bridge (→ SSE on :4400) and the demo HTTP server (:4321), so the
 * distributed MNCA renders live in the browser without the physical Pis.
 *
 * Prerequisites:
 *   1. mesh-node compiled: `cd runtime/semantos-brain && zig build mesh-node`
 *   2. bun installed (for mesh-bridge.ts + serve.ts)
 *
 * Usage:
 *   bun docs/demo/run-local-mesh.ts [--count 4] [--tile-ms 500] [--iface lo0]
 *
 * Then open http://localhost:4321/mnca-grid.html
 *
 * SAFETY: no real transactions; no mainnet contact; no private keys.
 */

import { mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { MNCA_TILE_TICK_GROUP } from '../../core/protocol-types/src/mnca/srv6';

// ── paths ──────────────────────────────────────────────────────────────────

const SCRIPT_DIR   = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT    = join(SCRIPT_DIR, '..', '..');
const MESH_NODE_BIN = join(REPO_ROOT, 'runtime', 'semantos-brain', 'zig-out', 'bin', 'mesh-node');
const CONFIG_DIR   = '/tmp/mnca-mesh-local';

// ── arg parsing ────────────────────────────────────────────────────────────

type Args = { count: number; tileMs: number; iface: string };
function parseArgs(argv: string[]): Args {
  const out: Args = { count: 4, tileMs: 500, iface: 'lo0' };
  for (let i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case '--count':   out.count  = Number(argv[++i]); break;
      case '--tile-ms': out.tileMs = Number(argv[++i]); break;
      case '--iface':   out.iface  = argv[++i] ?? 'lo0'; break;
    }
  }
  return out;
}

const args = parseArgs(process.argv.slice(2));
const { count: N, tileMs, iface } = args;

// ── inline config generation (mirrors gen-identities.ts, no extra dep) ────

function randHex(bytes: number): string {
  return randomBytes(bytes).toString('hex');
}

// D-SRS-sns-multicast-wire: multicast group is now type-derived, not hand-assigned.
// SHA-256("what.mnca.tile")[0:4] : SHA-256("how.tick")[0:4] : zeros (no INST)
// = ff15:4ed1:aabd:873d:e970:0000:0000:0000
// Previously ff15::5e:1 (hand-assigned "SE"mantos suffix, now superseded).
const MCAST_GROUP = MNCA_TILE_TICK_GROUP;
const MCAST_PORT  = 47100;

interface NodeConfig {
  self:      { label: string; cellId: string; broadcastSecret: string };
  multicast: { group: string; port: number; hops: number; loopback: boolean };
  peers:     { label: string; cellId: string; broadcastSecret: string }[];
  meta:      { generatedAt: string; schema: string; meshSize: number };
}

function generateConfigs(n: number): NodeConfig[] {
  const nodes = Array.from({ length: n }, (_, i) => ({
    index: i + 1,
    label: `local-${String(i + 1).padStart(2, '0')}`,
    cellId: randHex(32),
    broadcastSecret: randHex(32),
  }));
  const generatedAt = new Date().toISOString();
  return nodes.map((me) => ({
    self: { label: me.label, cellId: me.cellId, broadcastSecret: me.broadcastSecret },
    multicast: { group: MCAST_GROUP, port: MCAST_PORT, hops: 1, loopback: true },
    peers: nodes
      .filter((o) => o.cellId !== me.cellId)
      .map((o) => ({ label: o.label, cellId: o.cellId, broadcastSecret: o.broadcastSecret })),
    meta: { generatedAt, schema: 'u2-mesh-identity/v2', meshSize: n },
  }));
}

// ── tile grid layout: map node index → (tileX, tileY) ────────────────────

function tileCoord(i: number, cols: number): [number, number] {
  return [i % cols, Math.floor(i / cols)];
}

// ── pre-flight checks ─────────────────────────────────────────────────────

if (!existsSync(MESH_NODE_BIN)) {
  console.error(`\n  ✗ mesh-node not found at ${MESH_NODE_BIN}`);
  console.error(`    Build it first:\n      cd runtime/semantos-brain && zig build mesh-node\n`);
  process.exit(1);
}

// ── generate + write configs ──────────────────────────────────────────────

mkdirSync(CONFIG_DIR, { recursive: true });
const configs = generateConfigs(N);
const configPaths: string[] = [];
for (const cfg of configs) {
  const p = join(CONFIG_DIR, `${cfg.self.label}.json`);
  writeFileSync(p, JSON.stringify(cfg, null, 2) + '\n');
  configPaths.push(p);
}
console.log(`Generated ${N} node configs in ${CONFIG_DIR}`);
console.log(`  SNS multicast group (mnca.tile.tick): ${MCAST_GROUP}`);

// ── spawn helpers ─────────────────────────────────────────────────────────

const children: ReturnType<typeof Bun.spawn>[] = [];
let shutdownInProgress = false;

function spawnChild(
  cmd: string[],
  env: Record<string, string> = {},
  label: string,
): ReturnType<typeof Bun.spawn> {
  const proc = Bun.spawn(cmd, {
    env: { ...process.env, ...env },
    stdout: 'inherit',
    stderr: 'inherit',
  });
  children.push(proc);
  console.log(`  [${label}] pid ${proc.pid}  ${cmd.join(' ')}`);
  return proc;
}

function shutdown(): void {
  if (shutdownInProgress) return;
  shutdownInProgress = true;
  console.log('\nShutting down mesh…');
  for (const p of children) {
    try { p.kill(); } catch { /* already dead */ }
  }
  process.exit(0);
}

process.on('SIGINT',  shutdown);
process.on('SIGTERM', shutdown);

// ── launch mesh-node instances ────────────────────────────────────────────

const cols = Math.ceil(Math.sqrt(N));
console.log(`\nStarting ${N} mesh-node (${cols}×${Math.ceil(N / cols)} grid, --tile-ms ${tileMs}, --iface ${iface}):`);
for (let i = 0; i < N; i++) {
  const [tx, ty] = tileCoord(i, cols);
  spawnChild(
    [MESH_NODE_BIN,
      '--config',   configPaths[i]!,
      '--tile-ms',  String(tileMs),
      '--tile-x',   String(tx),
      '--tile-y',   String(ty),
      '--iface',    iface,
    ],
    {},
    configs[i]!.self.label,
  );
}

// ── launch mesh-bridge ────────────────────────────────────────────────────

console.log('\nStarting mesh-bridge (SSE → :4400):');
spawnChild(
  ['bun', join(SCRIPT_DIR, 'mesh-bridge.ts')],
  { MCAST_GROUP, MCAST_PORT: String(MCAST_PORT), MCAST_IFACE: iface, BRIDGE_PORT: '4400' },
  'mesh-bridge',
);

// ── launch demo HTTP server ───────────────────────────────────────────────

console.log('\nStarting demo server (:4321):');
spawnChild(
  ['bun', join(SCRIPT_DIR, 'serve.ts')],
  { DEMO_PORT: '4321' },
  'demo-server',
);

// ── launch snapshot anchor service (dry-run) ─────────────────────────────

console.log('\nStarting snapshot anchor service (:4401, dry-run):');
spawnChild(
  ['bun', join(SCRIPT_DIR, 'mesh-snapshot-anchor.ts')],
  { BRIDGE_URL: 'http://localhost:4400', ANCHOR_PORT: '4401', ANCHOR_INTERVAL_MS: '30000' },
  'anchor',
);

// ── launch data-cell source (D-SRS-mnca-cell-source) ─────────────────────
// Runs the MNCA rule on mesh-derived data seeds (tick freshness, peer
// density, SNS group bits) and serves the result on :4402/events.
// This is an optional overlay — the bridge (:4400) is the primary source.

console.log('\nStarting data-cell source (:4402, data-derived MNCA):');
spawnChild(
  ['bun', join(SCRIPT_DIR, 'mesh-data-cell-source.ts')],
  { BRIDGE_URL: 'http://localhost:4400', DATA_PORT: '4402', POLL_MS: '2000', PRE_STEPS: '3' },
  'data-source',
);

// ── launch type-path fuzzer (D-SRS-typepath-fuzzer) ──────────────────────
// Coverage-guided semantic type-path fuzzer.  Explores *.fuzz.* type paths,
// derives SNS multicast groups, fingerprints the MNCA state, and emits novel
// discoveries on :4403/events.  SAFETY: all paths are *.fuzz.* scoped.

console.log('\nStarting type-path fuzzer (:4403, *.fuzz.* namespace only):');
spawnChild(
  ['bun', join(SCRIPT_DIR, 'mesh-typepath-fuzzer.ts')],
  { DATA_URL: 'http://localhost:4402', FUZZER_PORT: '4403', ROUND_MS: '800' },
  'fuzzer',
);

// ── wait for bridge, verify tiles flow, then print ready message ──────────

async function waitForTiles(timeoutMs = 8000): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await Bun.sleep(500);
    try {
      const res  = await fetch('http://localhost:4400/tiles', { signal: AbortSignal.timeout(1000) });
      if (!res.ok) continue;
      const tiles = await res.json() as unknown[];
      if (tiles.length > 0) return true;
    } catch { /* bridge not up yet */ }
  }
  return false;
}

console.log('\nWaiting for tiles to flow…');
const ok = await waitForTiles();
if (ok) {
  const res = await fetch('http://localhost:4400/tiles');
  const tiles = await res.json() as Array<{ tileX: number; tileY: number; tick: number }>;
  console.log(`\n  ✓ Tiles flowing — ${tiles.length} tile(s) in bridge:`);
  for (const t of tiles) console.log(`      (${t.tileX},${t.tileY}) tick=${t.tick}`);
  console.log(`\n  ✓ Bridge SSE:      http://localhost:4400/events  (raw mesh)`);
  console.log(`  ✓ Data-cell SSE:   http://localhost:4402/events  (data-derived MNCA)`);
  console.log(`  ✓ Fuzzer corpus:   http://localhost:4403/stats    (type-path coverage)`);
  console.log(`  ✓ Fuzzer events:   http://localhost:4403/events   (novel *.fuzz.* paths)`);
  console.log(`  ✓ Anchor preview:  http://localhost:4401/anchor-preview  (dry-run)`);
  console.log(`  ✓ Demo page:       http://localhost:4321/mnca-grid.html`);
  console.log('  Press Ctrl+C to stop all processes.\n');
} else {
  console.warn('\n  ✗ No tiles after 8 s — check mesh-node output above.');
  console.warn('    Bridge may need MCAST_IFACE set. Try --iface en0 (physical NIC).\n');
  console.log('  Demo server still running at http://localhost:4321/mnca-grid.html');
  console.log('  (will fall back to local sim)\n');
}

// Keep the process alive until killed.
await new Promise<void>(() => { /* wait for SIGINT */ });

```
