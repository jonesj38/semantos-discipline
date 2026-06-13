---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/scripts/sentinel2-ndvi-ingest.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.419820+00:00
---

# cartridges/inference-gate/scripts/sentinel2-ndvi-ingest.ts

```ts
#!/usr/bin/env bun
/**
 * sentinel2-ndvi-ingest.ts
 *
 * Downloads Sentinel-2 Band 4 (Red) + Band 8 (NIR) COGs from Element84's
 * public S3 archive, computes NDVI, normalises to 0-255, and writes a
 * 50×50 grid-state JSON that the MNCA rehab demo server loads as a seed.
 *
 * NDVI = (NIR - Red) / (NIR + Red)
 * Normalised → cell state (0-255):
 *   NDVI < 0    → state 0-110  (mine waste, bare rock)
 *   NDVI 0-0.3  → state 110-180 (sparse / establishing veg)
 *   NDVI 0.3+   → state 180-255 (moderate → dense canopy)
 *
 * Usage
 * ─────
 *   bun cartridges/inference-gate/scripts/sentinel2-ndvi-ingest.ts
 *   bun cartridges/inference-gate/scripts/sentinel2-ndvi-ingest.ts --tile S2B_56HKK_20240831_0_L2A
 *   bun cartridges/inference-gate/scripts/sentinel2-ndvi-ingest.ts --synth   # no download, synthetic mine pattern
 *
 * Output
 * ──────
 *   cartridges/inference-gate/mnca-grid-real.json
 *   { tileId, date, bbox, ndviMin, ndviMax, gridW, gridH, cells: number[] }
 */

import { fromUrl } from 'geotiff';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

// ── Config ─────────────────────────────────────────────────────────────────────

const GRID_W = 50;
const GRID_H = 50;

// Hunter Valley NSW — Ravensworth / Huntley mine rehabilitation area
// Sentinel-2 MGRS tile 56HKK, 0% cloud cover, 2024-08-31
// Sourced via Element84 STAC: earth-search.aws.element84.com/v1
const KNOWN_TILES: Record<string, { date: string; location: string }> = {
  'S2B_56HKK_20240831_0_L2A': { date: '2024-08-31', location: 'Hunter Valley NSW (Ravensworth area)' },
  'S2B_56HKJ_20240910_0_L2A': { date: '2024-09-10', location: 'Hunter Valley NSW (Singleton area)' },
  'S2B_56HLK_20240831_0_L2A': { date: '2024-08-31', location: 'Hunter Valley NSW (Muswellbrook area)' },
};

const args = process.argv.slice(2);
const synthMode = args.includes('--synth');
const tileArg   = args.includes('--tile') ? args[args.indexOf('--tile') + 1] : undefined;
const TILE_ID   = tileArg ?? 'S2B_56HKK_20240831_0_L2A';
const TILE_META = KNOWN_TILES[TILE_ID] ?? { date: 'unknown', location: 'unknown' };

function tileBase(id: string): string {
  // Parse tile ID: S2B_56HKK_20240831_0_L2A → zone=56, row=H, col=KK, year=2024, month=8
  const m = id.match(/^S2[AB]_(\d{2})([A-Z])([A-Z]{2})_(\d{4})(\d{2})\d{2}_/);
  if (!m) throw new Error(`Cannot parse tile ID: ${id}`);
  const [, zone, latBand, col, year, month] = m;
  const mo = Number(month); // strip leading zero
  return `https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/${zone}/${latBand}/${col}/${year}/${mo}/${id}`;
}

const OUT_PATH = resolve(import.meta.dir, '..', 'mnca-grid-real.json');

// ── NDVI → cell state mapping ──────────────────────────────────────────────────
//
// aliveThreshold in the rehab MNCA rule is 128 (midpoint of 0-255).
// Map NDVI so that the alive/dead boundary sits at ~NDVI 0.1 (thin establishing
// veg) — giving ~40-50% initial alive cells on a real mine site, which keeps
// the CA in the interesting dynamic regime (not all-alive, not all-dead).
//
//   NDVI < 0    → bare rock/water  → state 0..80
//   NDVI 0-0.10 → bare soil/waste  → state 80..128 (boundary)
//   NDVI 0.1-0.4→ establishing veg → state 128..200
//   NDVI 0.4+   → dense canopy     → state 200..255

function ndviToState(ndvi: number): number {
  const v = Math.max(-1, Math.min(1, ndvi));
  if (v < 0)    return Math.round(((v + 1)) * 80);             // -1..0 → 0..80
  if (v < 0.10) return Math.round(80 + (v / 0.10) * 48);      // 0..0.1 → 80..128
  if (v < 0.40) return Math.round(128 + ((v - 0.10) / 0.30) * 72); // 0.1..0.4 → 128..200
  return Math.round(Math.min(255, 200 + ((v - 0.40) / 0.60) * 55)); // 0.4..1.0 → 200..255
}

// ── Synthetic fallback — realistic Hunter Valley mine pattern ──────────────────
//
// Used when --synth flag is passed or when S3 download fails.
// Generates a pattern that looks like a mine rehab site:
//   - Disturbed core (very low NDVI = mine waste)
//   - Rehabilitated perimeter (moderate-high NDVI = recovering veg)
//   - Noisy transitions (patchy revegetation)

function makeSyntheticGrid(): { cells: number[]; ndviMin: number; ndviMax: number; note: string } {
  const cells: number[] = new Array(GRID_W * GRID_H);
  let ndviMin = 1, ndviMax = -1;

  // Main open-cut pit in centre-left (large disturbed void)
  // Rehabilitation zones on the perimeter and upper-right quadrant
  // Multiple disturbance features: pit, overburden dumps, haulage roads
  for (let y = 0; y < GRID_H; y++) {
    for (let x = 0; x < GRID_W; x++) {
      const cx = 20, cy = 28; // main pit centre
      const dx = x - cx, dy = y - cy;
      const distToMain = Math.sqrt(dx * dx + dy * dy) / GRID_W;
      // Secondary dump
      const dx2 = x - 38, dy2 = y - 15;
      const distToDump = Math.sqrt(dx2 * dx2 + dy2 * dy2) / GRID_W;

      let ndvi: number;
      if (distToMain < 0.28) {
        // Active open-cut pit + immediate margin — very low NDVI (bare rock, dust)
        ndvi = -0.05 + Math.random() * 0.10;
      } else if (distToMain < 0.38 || distToDump < 0.14) {
        // Disturbed buffer / overburden dump (very sparse)
        ndvi = 0.03 + Math.random() * 0.10;
      } else if (distToMain < 0.48) {
        // Early rehabilitation zone (patchy establishing veg)
        ndvi = 0.06 + Math.random() * 0.20;
      } else {
        // Surrounding rehabilitated batters + remnant bush
        const base = 0.25 + Math.min(0.50, (distToMain - 0.48) * 2.5);
        ndvi = base + (Math.random() - 0.5) * 0.15;
      }

      // Haulage road corridors (bare)
      const onRoadH = y >= 26 && y <= 30 && x > 20;
      const onRoadV = x >= 32 && x <= 35 && y < 28;
      if (onRoadH || onRoadV) ndvi = 0.01 + Math.random() * 0.05;
      // Dense revegetation patches on upper right (early success areas)
      if (x > 35 && y < 20 && Math.random() < 0.4) ndvi = 0.50 + Math.random() * 0.30;

      ndvi = Math.max(-0.1, Math.min(0.9, ndvi));
      ndviMin = Math.min(ndviMin, ndvi);
      ndviMax = Math.max(ndviMax, ndvi);
      cells[y * GRID_W + x] = ndviToState(ndvi);
    }
  }
  return { cells, ndviMin, ndviMax, note: 'synthetic — Hunter Valley mine pattern' };
}

// ── COG download via geotiff.js ────────────────────────────────────────────────

async function downloadBand(url: string, bandName: string): Promise<Float32Array | number[]> {
  console.log(`[ingest] Fetching ${bandName}: ${url}`);
  const t0 = Date.now();

  const tiff = await fromUrl(url, {
    headers: { 'User-Agent': 'semantos-mnca-ingest/1.0' },
    allowHttpExceptions: true,
  });

  const imageCount = await tiff.getImageCount();
  console.log(`[ingest]   ${bandName} has ${imageCount} image(s) (1 full + ${imageCount - 1} overviews)`);

  // Use the smallest overview for fast download; it's still enough for a 50×50 demo
  // Overview ladder: 10980 → 5490 → 2745 → 1373 → 687 → 344 → 172
  // We want the 344px or 172px overview → read at index imageCount-2 or imageCount-1
  const overviewIdx = Math.max(0, imageCount - 2); // second-to-last = ~344px square
  const image = await tiff.getImage(overviewIdx);
  const w = image.getWidth();
  const h = image.getHeight();
  console.log(`[ingest]   Overview ${overviewIdx}: ${w}×${h} px → resampling to ${GRID_W}×${GRID_H}`);

  // readRasters with width/height resamples to the target size
  const [raster] = await image.readRasters({ width: GRID_W, height: GRID_H }) as unknown as [Float32Array | number[]];

  console.log(`[ingest]   ${bandName} done in ${Date.now() - t0}ms`);
  return raster;
}

// ── NDVI computation with contrast stretch ─────────────────────────────────────
//
// When reading an overview of a 110km tile, most pixels are forest (NDVI 0.6-0.9).
// A linear stretch based on the 5th-95th percentile maps the actual variation in
// the data to the full 0-255 range — the same technique used in satellite imagery
// visualisation tools (QGIS auto-stretch, Google Earth Engine percentile).

function percentile(arr: number[], p: number): number {
  const sorted = [...arr].sort((a, b) => a - b);
  const idx = Math.max(0, Math.min(sorted.length - 1, Math.floor(sorted.length * p / 100)));
  return sorted[idx]!;
}

function computeNdviGrid(
  red: Float32Array | number[],
  nir: Float32Array | number[],
): { cells: number[]; ndviMin: number; ndviMax: number; stretchLo: number; stretchHi: number } {
  const N = GRID_W * GRID_H;
  const ndvis: number[] = new Array(N);
  let ndviMin = 1, ndviMax = -1;

  // First pass: compute raw NDVI
  for (let i = 0; i < N; i++) {
    const r = red[i] as number;
    const n = nir[i] as number;
    const ndvi = (r === 0 && n === 0) ? -0.05 : (n - r) / (n + r + 1e-6);
    ndvis[i] = ndvi;
    ndviMin = Math.min(ndviMin, ndvi);
    ndviMax = Math.max(ndviMax, ndvi);
  }

  // Contrast stretch: map 5th-95th percentile to 0-255
  const stretchLo = percentile(ndvis, 5);
  const stretchHi = percentile(ndvis, 95);
  const range = stretchHi - stretchLo;

  console.log(`[ingest]   NDVI: raw=${ndviMin.toFixed(3)}..${ndviMax.toFixed(3)}, stretch p5=${stretchLo.toFixed(3)}..p95=${stretchHi.toFixed(3)}`);

  // Second pass: apply stretch then ndviToState
  // We remap ndvi into [-1,1] space relative to the stretch range so the
  // existing ndviToState colour/threshold mapping still applies correctly.
  const cells: number[] = new Array(N);
  for (let i = 0; i < N; i++) {
    const stretched = range > 0.01
      ? ((ndvis[i]! - stretchLo) / range) * 2 - 1   // → [-1, 1]
      : ndvis[i]!;
    cells[i] = ndviToState(stretched);
  }

  return { cells, ndviMin, ndviMax, stretchLo, stretchHi };
}

// ── Main ───────────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  console.log(`\n╔══════════════════════════════════════════════════════╗`);
  console.log(`║   Sentinel-2 NDVI Ingest — MNCA Rehab Demo          ║`);
  console.log(`╠══════════════════════════════════════════════════════╣`);
  console.log(`║  Tile:  ${TILE_ID.padEnd(44)} ║`);
  console.log(`║  Date:  ${TILE_META.date.padEnd(44)} ║`);
  console.log(`║  Area:  ${TILE_META.location.slice(0, 44).padEnd(44)} ║`);
  console.log(`║  Grid:  ${`${GRID_W}×${GRID_H} cells`.padEnd(44)} ║`);
  console.log(`╚══════════════════════════════════════════════════════╝\n`);

  let cells: number[];
  let ndviMin: number, ndviMax: number;
  let note = '';
  let source = 'sentinel2-cog';

  if (synthMode) {
    console.log('[ingest] --synth mode: using synthetic mine pattern');
    ({ cells, ndviMin, ndviMax, note } = makeSyntheticGrid());
    source = 'synthetic';
  } else {
    try {
      const base = tileBase(TILE_ID);
      const redUrl = `${base}/B04.tif`;
      const nirUrl = `${base}/B08.tif`;

      const [red, nir] = await Promise.all([
        downloadBand(redUrl, 'B04 (Red)'),
        downloadBand(nirUrl, 'B08 (NIR)'),
      ]);

      let stretchLo: number, stretchHi: number;
      ({ cells, ndviMin, ndviMax, stretchLo, stretchHi } = computeNdviGrid(red, nir));
      note = `NDVI stretch p5=${stretchLo.toFixed(3)}..p95=${stretchHi.toFixed(3)} (full tile overview at ~320m/px)`;
    } catch (err) {
      console.warn(`[ingest] COG download failed: ${err}`);
      console.warn('[ingest] Falling back to synthetic mine pattern');
      ({ cells, ndviMin, ndviMax, note } = makeSyntheticGrid());
      source = 'synthetic-fallback';
      note = `Real-data download failed (${err}); using synthetic Hunter Valley mine pattern`;
    }
  }

  // Stats
  const alive = cells.filter(v => v >= 128).length;
  const coveragePct = ((alive / cells.length) * 100).toFixed(1);
  const mean = (cells.reduce((s, v) => s + v, 0) / cells.length).toFixed(1);

  console.log(`\n[ingest] Results:`);
  console.log(`  NDVI range:    ${ndviMin.toFixed(3)} .. ${ndviMax.toFixed(3)}`);
  console.log(`  State mean:    ${mean} / 255`);
  console.log(`  Coverage:      ${coveragePct}% (state ≥ 128 = alive threshold)`);
  console.log(`  Source:        ${source}`);
  if (note) console.log(`  Note:          ${note}`);

  // Write output
  const output = {
    tileId:      TILE_ID,
    date:        TILE_META.date,
    location:    TILE_META.location,
    source,
    gridW:       GRID_W,
    gridH:       GRID_H,
    ndviMin:     parseFloat(ndviMin.toFixed(4)),
    ndviMax:     parseFloat(ndviMax.toFixed(4)),
    meanState:   parseFloat(mean),
    coveragePct: parseFloat(coveragePct),
    note:        note || undefined,
    generatedAt: new Date().toISOString(),
    cells,
  };

  writeFileSync(OUT_PATH, JSON.stringify(output, null, 2));
  console.log(`\n[ingest] ✓ Written: ${OUT_PATH}`);
  console.log('[ingest] Start mnca-rehab-server.ts — it will auto-load this grid.');
}

main().catch(err => {
  console.error('[ingest] Fatal:', err);
  process.exit(1);
});

```
