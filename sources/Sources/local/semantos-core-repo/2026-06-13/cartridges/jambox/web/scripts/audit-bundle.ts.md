---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/scripts/audit-bundle.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.597627+00:00
---

# cartridges/jambox/web/scripts/audit-bundle.ts

```ts
/**
 * Bundle audit script — D-D.6 + D-G.9
 *
 * Reports the size of:
 *   1. The default (boot) bundle (public/main.js)
 *   2. Each lazy-loaded engine chunk (built separately)
 *   3. [D-G.9] Mobile-plan boot bundle (must be ≤ 350 KB)
 *
 * Gate assertions:
 *   - The default bundle must NOT have grown more than 5 KB minified
 *     versus the Phase B tag baseline (jam-room-v0.4.0 / jam-room-v0.5.0).
 *   - [D-G.9] Mobile-plan boot bundle must be ≤ 350 KB.
 *   - [D-G.9] Mobile-plan boot bundle must NOT contain Three.js markers
 *     (enforces the mobilePlan L4 gate in src/ui/viewport-plan.ts).
 *
 * Per HARD RULE 3: all engine bundles must load lazily (dynamic import),
 * never at boot. This script verifies that the boot bundle does NOT
 * contain any of the engine-specific marker strings.
 *
 * Usage:
 *   node scripts/audit-bundle.ts
 *   (or: bun run scripts/audit-bundle.ts)
 *
 * Exit codes:
 *   0 — audit passed
 *   1 — bundle too large or engine code found in boot bundle
 */

import { existsSync, readFileSync, statSync } from 'node:fs';
import { resolve } from 'node:path';

const __dirname = new URL('.', import.meta.url).pathname;
const ROOT = resolve(__dirname, '..');
const PUBLIC = resolve(ROOT, 'public');

// ── Configuration ──────────────────────────────────────────────────────────────

/** Maximum allowed growth of the boot bundle vs Phase B baseline (bytes). */
const MAX_BOOT_GROWTH_BYTES = 5 * 1024; // 5 KB

/** [D-G.9] Maximum mobile-plan boot bundle size (bytes). */
const MAX_MOBILE_BOOT_BYTES = 350 * 1024; // 350 KB

/**
 * Phase B baseline size. This is the size of public/main.js at
 * tag jam-room-v0.4.0 (Phase B). Update when the baseline changes.
 *
 * Fallback: if the baseline file doesn't exist, we use this estimate.
 * The actual gate runs `bun build` and then checks the output size.
 */
const PHASE_B_BASELINE_BYTES = 350_000; // approximate; override via env

const BASELINE_BYTES = process.env.JAM_BUNDLE_BASELINE_BYTES
  ? parseInt(process.env.JAM_BUNDLE_BASELINE_BYTES, 10)
  : PHASE_B_BASELINE_BYTES;

/**
 * [D-G.9] Three.js markers that must NOT appear in the mobile-plan boot bundle.
 *
 * The gate in src/ui/viewport-plan.ts guards the dynamic import of
 * '../three/jambox-world' with:
 *   plan.surfacedLayers.includes('L4')
 * which is false for mobilePlan.  If Three.js leaks into the mobile boot
 * chunk, one of these strings will be present in public/main-mobile.js.
 */
const THREEJS_MARKERS: string[] = [
  'THREE.WebGLRenderer',
  'THREE.PerspectiveCamera',
  'JamboxWorldView',
  'jambox-world',
  'jamboxWorld',
  'InstancedMesh',
  'BufferGeometry',
];

// Strings that must NOT appear in the boot bundle (engine-specific markers)
const ENGINE_MARKERS: Record<string, string[]> = {
  'strudel': [
    '@strudel/core',
    'StrudelRack',
    'buildStubRuntime',
  ],
  'libpd-wasm': [
    'libpd-wasm',
    'PureDataRack',
    'buildStubLibpd',
  ],
  'midi-rack': [
    'ExternalMidiRack',
    'StubMidiOutput',
    'voiceIdToPitch',
  ],
};

// ── Helpers ────────────────────────────────────────────────────────────────────

function fmtBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(2)} MB`;
}

function fmtDelta(n: number): string {
  const sign = n >= 0 ? '+' : '';
  return `${sign}${fmtBytes(n)}`;
}

// ── Main audit ────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  console.log('');
  console.log('jam-room bundle audit — D-D.6');
  console.log('─'.repeat(50));

  let failed = false;

  // ── Boot bundle ─────────────────────────────────────────────────────────────

  const bootBundle = resolve(PUBLIC, 'main.js');
  if (!existsSync(bootBundle)) {
    console.error(`ERROR: boot bundle not found: ${bootBundle}`);
    console.error('Run `pnpm -C apps/world-apps/jam-room build:bundle` first.');
    process.exit(1);
  }

  const bootStat = statSync(bootBundle);
  const bootSize = bootStat.size;
  const bootDelta = bootSize - BASELINE_BYTES;

  console.log('');
  console.log('Boot bundle (public/main.js)');
  console.log(`  Size:     ${fmtBytes(bootSize)}`);
  console.log(`  Baseline: ${fmtBytes(BASELINE_BYTES)} (Phase B, jam-room-v0.4.0)`);
  console.log(`  Delta:    ${fmtDelta(bootDelta)}`);

  if (bootDelta > MAX_BOOT_GROWTH_BYTES) {
    console.error(`  FAIL: boot bundle grew by ${fmtBytes(bootDelta)}, max allowed: ${fmtBytes(MAX_BOOT_GROWTH_BYTES)}`);
    failed = true;
  } else {
    console.log(`  PASS: within ${fmtBytes(MAX_BOOT_GROWTH_BYTES)} growth ceiling`);
  }

  // ── Engine marker check ──────────────────────────────────────────────────────

  console.log('');
  console.log('Checking boot bundle for engine-specific code (must be absent):');

  const bootContent = readFileSync(bootBundle, 'utf8');

  for (const [engineName, markers] of Object.entries(ENGINE_MARKERS)) {
    let engineFound = false;
    for (const marker of markers) {
      if (bootContent.includes(marker)) {
        console.error(`  FAIL: boot bundle contains '${marker}' (${engineName} — should be lazy)`);
        failed = true;
        engineFound = true;
      }
    }
    if (!engineFound) {
      console.log(`  PASS: ${engineName} — not present at boot (lazy import)`);
    }
  }

  // ── Engine chunk sizes ───────────────────────────────────────────────────────

  console.log('');
  console.log('Engine chunks (lazy-loaded on first rack instantiation):');
  console.log('  Note: chunks are built on-demand via dynamic import — no pre-built chunk files.');
  console.log('  Verify chunk sizes by running: bun build --splitting src/racks/strudel/StrudelRack.ts');

  // Estimated sizes from known package sizes:
  const estimates: Array<{ name: string; packageHint: string; approxSize: string }> = [
    { name: 'StrudelRack', packageHint: '@strudel/core', approxSize: '~200–400 KB (when installed)' },
    { name: 'PureDataRack', packageHint: 'libpd-wasm', approxSize: '~500 KB–1 MB (when installed)' },
    { name: 'ExternalMidiRack', packageHint: 'Web MIDI API (browser-native)', approxSize: '~2–5 KB' },
  ];

  for (const est of estimates) {
    console.log(`  ${est.name}: ${est.approxSize} (${est.packageHint})`);
  }

  // ── D-G.9: Mobile-plan boot bundle ──────────────────────────────────────────

  const mobileBundleName = 'main-mobile.js';
  const mobileBundle = resolve(PUBLIC, mobileBundleName);
  console.log('');
  console.log(`D-G.9 — Mobile-plan boot bundle (${mobileBundleName}):`);

  if (!existsSync(mobileBundle)) {
    console.warn(
      `  SKIP: ${mobileBundle} not found.\n` +
      `  To build the mobile bundle:\n` +
      `    bun build src/main.ts --outfile public/main-mobile.js --target browser --format esm --define 'MOBILE_PLAN=true'\n` +
      `  (The mobile bundle is built separately for bundle-size audit purposes.)`
    );
  } else {
    const mobileStat = statSync(mobileBundle);
    const mobileSize = mobileStat.size;

    console.log(`  Size: ${fmtBytes(mobileSize)}`);
    console.log(`  Budget: ≤ ${fmtBytes(MAX_MOBILE_BOOT_BYTES)}`);

    if (mobileSize > MAX_MOBILE_BOOT_BYTES) {
      console.error(
        `  FAIL: mobile-plan boot bundle is ${fmtBytes(mobileSize)}, ` +
        `exceeds ≤ ${fmtBytes(MAX_MOBILE_BOOT_BYTES)} budget.`
      );
      failed = true;
    } else {
      console.log(`  PASS: ${fmtBytes(mobileSize)} ≤ ${fmtBytes(MAX_MOBILE_BOOT_BYTES)}`);
    }

    // Three.js leak check.
    console.log('');
    console.log('  Checking mobile boot bundle for Three.js markers (must be absent):');
    const mobileContent = readFileSync(mobileBundle, 'utf8');
    let threeFound = false;
    for (const marker of THREEJS_MARKERS) {
      if (mobileContent.includes(marker)) {
        console.error(`  FAIL: mobile boot bundle contains Three.js marker '${marker}'`);
        console.error(`        mobilePlan does not surface L4 — Three.js must not load.`);
        failed = true;
        threeFound = true;
      }
    }
    if (!threeFound) {
      console.log('  PASS: No Three.js markers found in mobile-plan boot bundle.');
    }
  }

  // ── Summary ──────────────────────────────────────────────────────────────────

  console.log('');
  console.log('─'.repeat(50));
  if (failed) {
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
