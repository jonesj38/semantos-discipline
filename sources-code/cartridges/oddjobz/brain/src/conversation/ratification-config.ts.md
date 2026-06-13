---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/ratification-config.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.519593+00:00
---

# cartridges/oddjobz/brain/src/conversation/ratification-config.ts

```ts
/**
 * D-OJ-conv-confidence-threshold — Ratification config loader.
 *
 * Pure config loader: reads `ratificationThreshold` from `cartridge.json`
 * and exposes `meetsRatificationThreshold()` for use in `buildCanonicalTurns`.
 *
 * Design rules:
 *  - loadRatificationConfig reads a file — that's fine (filesystem, not brain HTTP).
 *  - meetsRatificationThreshold is a pure function.
 *  - Both are safe to call from buildCanonicalTurns in the intake child.
 *  - Config errors degrade gracefully to DEFAULT_RATIFICATION_THRESHOLD (0.85).
 *    We do NOT throw — a misconfigured cartridge.json should not break the intake path.
 */

import { readFileSync } from 'node:fs';

export const DEFAULT_RATIFICATION_THRESHOLD = 0.85;

export interface RatificationConfig {
  readonly ratificationThreshold: number;
}

/**
 * Load ratificationThreshold from cartridge.json.
 * Returns DEFAULT_RATIFICATION_THRESHOLD when the field is absent or invalid.
 * Does NOT throw — config errors degrade to the safe default.
 */
export function loadRatificationConfig(cartridgeJsonPath: string): RatificationConfig {
  try {
    const raw = readFileSync(cartridgeJsonPath, 'utf8');
    const parsed = JSON.parse(raw) as unknown;
    if (
      parsed !== null &&
      typeof parsed === 'object' &&
      'ratificationThreshold' in parsed &&
      typeof (parsed as Record<string, unknown>).ratificationThreshold === 'number'
    ) {
      const threshold = (parsed as Record<string, unknown>).ratificationThreshold as number;
      // Ensure it's a finite number in [0, 1] range (sanity check)
      if (Number.isFinite(threshold) && threshold >= 0 && threshold <= 1) {
        return { ratificationThreshold: threshold };
      }
    }
  } catch {
    // File not found, parse error, or read error — degrade gracefully
  }
  return { ratificationThreshold: DEFAULT_RATIFICATION_THRESHOLD };
}

/**
 * Pure helper: given replyConfidence + threshold, returns whether the turn
 * auto-approves.
 *
 * Returns true iff replyConfidence !== undefined && replyConfidence >= threshold.
 * Operator turns must check this themselves — this helper makes no role-based
 * decision; the caller gates it to AI turns only.
 */
export function meetsRatificationThreshold(
  replyConfidence: number | undefined,
  threshold: number,
): boolean {
  return replyConfidence !== undefined && replyConfidence >= threshold;
}

```
