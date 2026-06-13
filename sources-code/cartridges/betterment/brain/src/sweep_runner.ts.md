---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/sweep_runner.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.564106+00:00
---

# cartridges/betterment/brain/src/sweep_runner.ts

```ts
/**
 * sweep_runner.ts — Bun subprocess script for the brain's betterment-sweep endpoint.
 *
 * Reads from stdin:
 *   { "cells": [ { "typeHashHex": "<64hex>", "cellId": "<64hex>",
 *                  "mintedAtMs": <number>, "payload": <json-object> }, ... ] }
 *
 * Categorises cells by typeHashHex using `bettermentCellTypeByHashHex`, builds a
 * PaskSweepInput with typed arrays, calls sweepPracticeHistory, and writes
 * the PaskSweepResult JSON to stdout.
 *
 * The Zig reactor (`runtime/semantos-brain/src/site_server/reactor.zig`,
 * `reactorHandleBettermentSweep`) builds the stdin envelope from cells in the
 * betterment namespace, with `mintedAtMs` already converted from the header
 * timestamp (u64 ns ÷ 1e6). It returns this script's stdout verbatim as the
 * `GET /api/v1/betterment/sweep` 200 body.
 *
 * Trajectory: a `windowSplitMs` is computed (default: now − 24h) so the result's
 * primed themes carry a day-over-day `trend` (escalating / settling / steady / new).
 *
 * Exit 0 on success (even when the result is the empty / field-is-clear shape).
 * Any error → exit 1 + stderr message.
 */

import { bettermentCellTypeByHashHex } from './cell-types/index.js';
import { sweepPracticeHistory } from './pask_sweep.js';
import type {
  PaskSweepInput,
  ReleaseCellInput,
  InsightCellInput,
  PatternCellInput,
  SealCellInput,
  SessionCellInput,
} from './pask_sweep.js';

/** Default trajectory split: cells minted in the last 24h are the "current" window. */
const DEFAULT_WINDOW_MS = 24 * 60 * 60 * 1000;

interface StdinCell {
  typeHashHex: string;
  cellId: string;
  mintedAtMs: number;
  payload: unknown;
}

/**
 * Pure core — categorise cells and run the sweep.  Exported so unit tests can
 * exercise it without spawning a subprocess.
 */
export function runSweep(
  cells: readonly StdinCell[],
  windowSplitMs: number,
): ReturnType<typeof sweepPracticeHistory> {
  const releaseCells: ReleaseCellInput[] = [];
  const insightCells: InsightCellInput[] = [];
  const patternCells: PatternCellInput[] = [];
  const sealCells: SealCellInput[] = [];
  const sessionCells: SessionCellInput[] = [];

  for (const c of cells) {
    const def = bettermentCellTypeByHashHex[c.typeHashHex];
    if (!def) continue; // unknown type — skip silently

    const mintedAt = c.mintedAtMs > 0 ? c.mintedAtMs : undefined;
    const p = (c.payload ?? {}) as Record<string, unknown>;

    switch (def.name) {
      case 'betterment.practice.release':
        releaseCells.push({
          cellId: c.cellId,
          mintedAt,
          payload: {
            rawText: typeof p['rawText'] === 'string' ? p['rawText'] : '',
            themes: typeof p['themes'] === 'string' ? p['themes'] : undefined,
            day: typeof p['day'] === 'string' ? p['day'] : undefined,
            valence: typeof p['valence'] === 'number' ? p['valence'] : undefined,
            elevation: typeof p['elevation'] === 'number' ? p['elevation'] : undefined,
          },
        });
        break;

      case 'betterment.practice.insight':
        insightCells.push({
          cellId: c.cellId,
          mintedAt,
          payload: {
            content: typeof p['content'] === 'string' ? p['content'] : '',
            dimensions: typeof p['dimensions'] === 'string' ? p['dimensions'] : undefined,
            source: typeof p['source'] === 'string' ? p['source'] : undefined,
            tags: typeof p['tags'] === 'string' ? p['tags'] : undefined,
          },
        });
        break;

      case 'betterment.practice.pattern':
        patternCells.push({
          cellId: c.cellId,
          mintedAt,
          payload: {
            description: typeof p['description'] === 'string' ? p['description'] : '',
            category: typeof p['category'] === 'string' ? p['category'] : 'belief',
            polarity: typeof p['polarity'] === 'string' ? p['polarity'] : 'neutral',
            strength: typeof p['strength'] === 'number' ? p['strength'] : undefined,
            occurrenceCount: typeof p['occurrenceCount'] === 'number' ? p['occurrenceCount'] : undefined,
          },
        });
        break;

      case 'betterment.practice.seal':
        sealCells.push({
          cellId: c.cellId,
          mintedAt,
          payload: {
            sealedReleaseIds: typeof p['sealedReleaseIds'] === 'string' ? p['sealedReleaseIds'] : '',
            elevation: typeof p['elevation'] === 'number' ? p['elevation'] : undefined,
          },
        });
        break;

      case 'betterment.practice.session':
        sessionCells.push({
          cellId: c.cellId,
          mintedAt,
          payload: {
            date: typeof p['date'] === 'string' ? p['date'] : '',
            elevation: typeof p['elevation'] === 'number' ? p['elevation'] : 5,
          },
        });
        break;

      // intention / connection / vacuum cells: not sweep inputs (no relevant
      // theme-extraction surface for the current algorithm); skip silently.
      default:
        break;
    }
  }

  const sweepInput: PaskSweepInput = {
    recentReleaseCells: releaseCells,
    recentInsightCells: insightCells,
    recentPatternCells: patternCells,
    recentSealCells: sealCells,
    recentSessionCells: sessionCells,
    windowSplitMs,
  };

  return sweepPracticeHistory(sweepInput);
}

/** Subprocess entrypoint — only runs when invoked as the main module. */
async function main(): Promise<void> {
  const chunks: Buffer[] = [];
  for await (const chunk of Bun.stdin.stream()) {
    chunks.push(Buffer.from(chunk));
  }
  const raw = Buffer.concat(chunks).toString('utf8');

  let input: { cells: StdinCell[] };
  try {
    input = JSON.parse(raw);
  } catch (e) {
    console.error('sweep_runner: failed to parse stdin JSON:', e);
    process.exit(1);
  }

  if (!Array.isArray(input.cells)) {
    console.error('sweep_runner: expected { cells: [...] } on stdin');
    process.exit(1);
  }

  const windowSplitMs = Date.now() - DEFAULT_WINDOW_MS;
  const result = runSweep(input.cells, windowSplitMs);
  process.stdout.write(JSON.stringify(result));
}

// Bun sets import.meta.main for the entry module.
if (import.meta.main) {
  await main();
}

```
