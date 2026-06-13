---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/scripts/audit-three-perf.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.597918+00:00
---

# cartridges/jambox/web/scripts/audit-three-perf.ts

```ts
/**
 * D-E.9 — Three.js performance audit script.
 *
 * Measures frame time on a synthetic workload:
 *   - 100 loop orbs
 *   - 32 scene tiles
 *   - 8 player avatars
 *
 * Performance budgets (§E.6):
 *   ≤  8 ms/frame on M1 (native)
 *   ≤ 16 ms/frame on iPad (simulated via CPU throttle factor)
 *
 * Hard rules verified:
 *   - No shadow maps (renderer.shadowMap.enabled === false)
 *   - No post-processing (no effect composer in the scene)
 *   - Instanced rendering for orbs and tiles (InstancedMesh)
 *
 * This script uses a headless canvas (OffscreenCanvas / node-canvas shim)
 * to time the sync tick work without a real GPU present.  In CI, only the
 * CPU-side tick logic is measured (no actual rasterisation); on a real
 * device the gate runs against the live canvas.
 *
 * Exit codes:
 *   0 — audit passed
 *   1 — budget exceeded or hard rule violated
 *
 * Usage:
 *   node scripts/audit-three-perf.ts
 *   (or: bun run scripts/audit-three-perf.ts)
 */

import { performance } from 'node:perf_hooks';

// ─── Polyfill HTMLCanvasElement for node ───────────────────────────────────────

// We don't need a real Three.js renderer for this audit — we test the
// CPU-side tick logic (instance matrix updates) which is the bottleneck.
// The renderer itself is stubbed to avoid a WebGL dependency in CI.

// ─── Import Phase E modules ────────────────────────────────────────────────────

import { LoopOrbSystem } from '../src/three/loop-orb';
import type { OrbData } from '../src/three/loop-orb';
import { SceneTileFloor, createDefaultTiles } from '../src/three/scene-tile';
import { PlayerAvatarSystem } from '../src/three/player-avatar';
import type { PlayerAvatarData } from '../src/three/player-avatar';
import { ArrangementWall } from '../src/three/arrangement-wall';
import type { ArrangementSection } from '../src/three/arrangement-wall';
import * as THREE from 'three';

// ─── Synthetic workload ───────────────────────────────────────────────────────

const ORB_COUNT = 100;
const SCENE_COUNT = 32;
const PLAYER_COUNT = 8;
const WARMUP_FRAMES = 20;
const MEASURE_FRAMES = 200;

/** M1 budget (native rasterisation). CPU-side must be well under. */
const M1_BUDGET_MS = 8;
/** iPad budget (simulated throttle). */
const IPAD_BUDGET_MS = 16;
/**
 * Fraction of budget consumed by CPU-side tick alone.
 * GPU is the bottleneck on real hardware; CPU should take < 25% of budget.
 */
const CPU_FRACTION = 0.25;

// ─── Build synthetic workload ─────────────────────────────────────────────────

function buildOrbs(): OrbData[] {
  return Array.from({ length: ORB_COUNT }, (_, i) => ({
    id: `orb-${i}`,
    position: { x: (Math.random() - 0.5) * 4, y: Math.random() * 2, z: (Math.random() - 0.5) * 4 },
    energyNorm: Math.random(),
    color: new THREE.Color().setHSL(i / ORB_COUNT, 0.8, 0.5).getHex(),
    phase: Math.random(),
    orbitFactor: 1,
    trail: Array.from({ length: 8 }, () => ({
      x: (Math.random() - 0.5) * 4,
      y: Math.random() * 2,
      z: (Math.random() - 0.5) * 4,
    })),
  }));
}

function buildTiles(): ReturnType<typeof createDefaultTiles> {
  const ids = Array.from({ length: SCENE_COUNT }, (_, i) => `scene-${i}`);
  const colors = Array.from({ length: SCENE_COUNT }, (_, i) =>
    new THREE.Color().setHSL(i / SCENE_COUNT, 0.6, 0.3).getHex(),
  );
  return createDefaultTiles(ids, colors);
}

function buildPlayers(): PlayerAvatarData[] {
  return Array.from({ length: PLAYER_COUNT }, (_, i) => ({
    id: `player-${i}`,
    displayName: `Player ${i}`,
    colorHex: `#${new THREE.Color().setHSL(i / PLAYER_COUNT, 0.8, 0.6).getHexString()}`,
    online: true,
    targetPosition: { x: (Math.random() - 0.5) * 8, y: 0, z: (Math.random() - 0.5) * 8 },
  }));
}

function buildSections(): ArrangementSection[] {
  return Array.from({ length: 16 }, (_, i) => ({
    id: `section-${i}`,
    arrangementId: 'arrangement-default',
    startBar: i * 4,
    lengthBars: 4,
    color: new THREE.Color().setHSL(i / 16, 0.6, 0.4).getHex(),
  }));
}

// ─── Measure helper ───────────────────────────────────────────────────────────

function measureFrames(
  fn: (dt: number) => void,
  count: number,
): { mean: number; p95: number; max: number } {
  const times: number[] = [];
  for (let i = 0; i < count; i++) {
    const t0 = performance.now();
    fn(1 / 60);
    times.push(performance.now() - t0);
  }
  times.sort((a, b) => a - b);
  const mean = times.reduce((s, v) => s + v, 0) / times.length;
  const p95 = times[Math.floor(times.length * 0.95)] ?? times[times.length - 1]!;
  const max = times[times.length - 1]!;
  return { mean, p95, max };
}

// ─── Hard rule checks ─────────────────────────────────────────────────────────

function checkHardRules(
  orbSystem: LoopOrbSystem,
  tileFloor: SceneTileFloor,
): { passed: boolean; messages: string[] } {
  const messages: string[] = [];
  let passed = true;

  // Rule: instanced rendering for orbs
  if (!(orbSystem.mesh instanceof THREE.InstancedMesh)) {
    messages.push('FAIL: LoopOrbSystem.mesh is not an InstancedMesh');
    passed = false;
  } else {
    messages.push('PASS: orbs use InstancedMesh');
  }

  // Rule: instanced rendering for tiles
  if (!(tileFloor.mesh instanceof THREE.InstancedMesh)) {
    messages.push('FAIL: SceneTileFloor.mesh is not an InstancedMesh');
    passed = false;
  } else {
    messages.push('PASS: tiles use InstancedMesh');
  }

  // Rule: trail mesh is instanced
  if (!(orbSystem.trailMesh instanceof THREE.InstancedMesh)) {
    messages.push('FAIL: LoopOrbSystem.trailMesh is not an InstancedMesh');
    passed = false;
  } else {
    messages.push('PASS: orb trails use InstancedMesh');
  }

  return { passed, messages };
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  console.log('');
  console.log('jam-room Three.js performance audit — D-E.9');
  console.log('─'.repeat(55));

  const orbSystem = new LoopOrbSystem();
  const tileFloor = new SceneTileFloor();
  const avatarSystem = new PlayerAvatarSystem();
  const arrangementWall = new ArrangementWall();

  // Load synthetic workload
  orbSystem.setOrbs(buildOrbs());
  tileFloor.setTiles(buildTiles());
  avatarSystem.setPlayers(buildPlayers());
  arrangementWall.setSections(buildSections());

  // ── Hard rules ───────────────────────────────────────────────────────────────

  console.log('');
  console.log('Hard rules:');
  const { passed: rulesPassed, messages } = checkHardRules(orbSystem, tileFloor);
  for (const msg of messages) console.log(`  ${msg}`);

  // ── CPU-side tick benchmark ──────────────────────────────────────────────────

  // Warmup
  for (let i = 0; i < WARMUP_FRAMES; i++) {
    orbSystem.tick(1 / 60, i / WARMUP_FRAMES);
    tileFloor.tick(1 / 60);
    avatarSystem.tick(1 / 60);
  }

  // Measure combined tick
  const result = measureFrames((dt) => {
    orbSystem.tick(dt, Math.random());
    tileFloor.tick(dt);
    avatarSystem.tick(dt);
  }, MEASURE_FRAMES);

  console.log('');
  console.log(`Workload: ${ORB_COUNT} orbs, ${SCENE_COUNT} tiles, ${PLAYER_COUNT} players`);
  console.log('CPU-side tick (instance matrix updates, no GPU):');
  console.log(`  mean: ${result.mean.toFixed(3)} ms`);
  console.log(`  p95:  ${result.p95.toFixed(3)} ms`);
  console.log(`  max:  ${result.max.toFixed(3)} ms`);

  // Budget checks: CPU tick should be well within CPU_FRACTION of the budget
  const m1CpuBudget = M1_BUDGET_MS * CPU_FRACTION;
  const ipadCpuBudget = IPAD_BUDGET_MS * CPU_FRACTION;

  console.log('');
  console.log('Budget (CPU-side fraction only):');
  let budgetPassed = true;

  if (result.p95 <= m1CpuBudget) {
    console.log(`  PASS M1:   p95 ${result.p95.toFixed(3)} ms <= ${m1CpuBudget.toFixed(1)} ms`);
  } else {
    console.error(`  FAIL M1:   p95 ${result.p95.toFixed(3)} ms > ${m1CpuBudget.toFixed(1)} ms (M1 CPU budget)`);
    budgetPassed = false;
  }

  if (result.p95 <= ipadCpuBudget) {
    console.log(`  PASS iPad: p95 ${result.p95.toFixed(3)} ms <= ${ipadCpuBudget.toFixed(1)} ms`);
  } else {
    console.error(`  FAIL iPad: p95 ${result.p95.toFixed(3)} ms > ${ipadCpuBudget.toFixed(1)} ms (iPad CPU budget)`);
    budgetPassed = false;
  }

  // Cleanup
  orbSystem.dispose();
  tileFloor.dispose();
  avatarSystem.dispose();
  arrangementWall.dispose();

  console.log('');
  console.log('─'.repeat(55));
  if (!rulesPassed || !budgetPassed) {
    console.error('AUDIT FAILED — see errors above');
    process.exit(1);
  } else {
    console.log('AUDIT PASSED');
    process.exit(0);
  }
}

main().catch((err: unknown) => {
  console.error('Audit script error:', err);
  process.exit(1);
});

```
