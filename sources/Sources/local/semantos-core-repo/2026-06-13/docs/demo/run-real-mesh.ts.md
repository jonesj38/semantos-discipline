---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/demo/run-real-mesh.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.747841+00:00
---

# docs/demo/run-real-mesh.ts

```ts
#!/usr/bin/env bun
/**
 * run-real-mesh.ts — connect the browser viz to the REAL Pi mesh.
 *
 * The Pi nodes must already be running `mesh-node --tile-ms 500`
 * (deployed via `tools/u2-mesh/` scripts + the tile drop-in override).
 *
 * This script on the Mac:
 *   1. Spawns mcast-relay.py  — joins the Pi LAN multicast group on the Pi
 *      LAN interface (bypasses Bun's broken IPv6 addMembership on non-default
 *      ifaces) and forwards raw datagrams to 127.0.0.1:47101
 *   2. Spawns mesh-bridge.ts  — reads from relay port, serves SSE on :4400
 *   3. Spawns serve.ts        — demo HTTP server on :4321
 *   4. Spawns mesh-snapshot-anchor.ts — periodic dry-run anchor on :4401
 *
 * For the MULTITENANT mode (D-SRS-multitenant-spawn, --multitenant):
 *   Pi nodes must be running run-multitenant-pi.sh (N brains + gateway per Pi).
 *   The Mac bridge then observes all N×6 tile streams via the gateway's LAN relay.
 *   All Pis now use the SNS-derived group by default (upgraded 2026-05-23).
 *
 * Usage:
 *   bun docs/demo/run-real-mesh.ts [--iface en8]
 *   bun docs/demo/run-real-mesh.ts [--iface en8] --multitenant   # N×6 tiles
 *
 * Then open http://localhost:4321/mnca-grid.html
 *
 * SAFETY: no real transactions; no mainnet contact; no private keys.
 */

import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { MNCA_TILE_TICK_GROUP } from '../../core/protocol-types/src/mnca/srv6';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));

// ── args ──────────────────────────────────────────────────────────────────
const iface = (() => {
  const i = process.argv.indexOf('--iface');
  return i >= 0 ? process.argv[i + 1] ?? 'en8' : 'en8';
})();

// --multitenant: Pi nodes running run-multitenant-pi.sh (N brains + gateway).
// Default: single-brain mode. Both use MNCA_TILE_TICK_GROUP since the
// Skyminer Pis were upgraded to the SNS-derived group on 2026-05-23.
const multitenant = process.argv.includes('--multitenant');
const MCAST_GROUP = MNCA_TILE_TICK_GROUP;  // ff15:4ed1:aabd:873d:e970:0000:0000:0000

// ── spawn helpers ─────────────────────────────────────────────────────────
const children: ReturnType<typeof Bun.spawn>[] = [];
let shuttingDown = false;

function spawnChild(cmd: string[], env: Record<string, string>, label: string) {
  const proc = Bun.spawn(cmd, { env: { ...process.env, ...env }, stdout: 'inherit', stderr: 'inherit' });
  children.push(proc);
  console.log(`  [${label}] pid ${proc.pid}  ${cmd.join(' ')}`);
  return proc;
}

function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log('\nShutting down…');
  for (const p of children) try { p.kill(); } catch { /* gone */ }
  process.exit(0);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

// ── launch ────────────────────────────────────────────────────────────────

const modeLabel = multitenant ? 'multitenant (N×6 tiles)' : 'single-brain (6 tiles)';
console.log(`\nConnecting to real Pi mesh on interface ${iface} (${modeLabel}):`);
console.log(`  SNS group: ${MCAST_GROUP}\n`);

spawnChild(
  ['python3', join(SCRIPT_DIR, 'mcast-relay.py')],
  { MCAST_GROUP, MCAST_IFACE: iface, RELAY_PORT: '47101' },
  'mcast-relay',
);

spawnChild(
  ['bun', join(SCRIPT_DIR, 'mesh-bridge.ts')],
  { RELAY_PORT: '47101', BRIDGE_PORT: '4400' },
  'mesh-bridge',
);

spawnChild(
  ['bun', join(SCRIPT_DIR, 'serve.ts')],
  { DEMO_PORT: '4321' },
  'demo-server',
);

spawnChild(
  ['bun', join(SCRIPT_DIR, 'mesh-snapshot-anchor.ts')],
  { BRIDGE_URL: 'http://localhost:4400', ANCHOR_PORT: '4401', ANCHOR_INTERVAL_MS: '30000' },
  'anchor',
);

// ── wait for tiles ────────────────────────────────────────────────────────

async function waitForTiles(ms = 8000): Promise<boolean> {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    await Bun.sleep(800);
    try {
      const r = await fetch('http://localhost:4400/tiles', { signal: AbortSignal.timeout(1000) });
      const t = await r.json() as unknown[];
      if (t.length > 0) return true;
    } catch { /* not ready */ }
  }
  return false;
}

console.log('\nWaiting for Pi tiles…');
const ok = await waitForTiles();
if (ok) {
  const tiles = await (await fetch('http://localhost:4400/tiles')).json() as Array<{ tileX: number; tileY: number; tick: number }>;
  console.log(`\n  ✓ ${tiles.length} tiles from real Pi mesh:`);
  for (const t of tiles.sort((a, b) => a.tileY - b.tileY || a.tileX - b.tileX))
    console.log(`      (${t.tileX},${t.tileY}) tick=${t.tick}`);
} else {
  console.warn('\n  ✗ No tiles after 8 s — check mcast-relay output above.');
  console.warn(`    Is the Pi mesh running? Try --iface <other> (current: ${iface})`);
}
console.log(`\n  ✓ Demo page:  http://localhost:4321/mnca-grid.html`);
console.log('  Press Ctrl+C to stop.\n');

await new Promise<void>(() => { /* run until SIGINT */ });

```
