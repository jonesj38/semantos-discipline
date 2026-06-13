---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/contrib/policy.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.607453+00:00
---

# cartridges/jambox/web/src/contrib/policy.ts

```ts
/**
 * D-F.2 — Default contribution split policy.
 *
 * Documented line-by-line in policy.md alongside this file.
 * The gate test diffs policy.md against runtime behaviour — keep them in sync.
 *
 * HARD RULE: Contributions are NEVER retroactively mutable. Fork to edit.
 */

export interface ContributionInput {
  player: string;
  /** Room time of this event in ms — used for macro-range coverage. */
  roomTimeMs: number;
  /** Event family (e.g. 'jam.input.pad', 'jam.rack.macro.set') — used for weight. */
  family?: string;
}

export interface PlayerStats {
  player: string;
  /** Raw event count. */
  eventCount: number;
  /** Macro range covered in ms (max time - min time across player's events). */
  macroRangeMs: number;
  /** Unweighted raw score before normalisation. */
  rawScore: number;
}

const TOTAL_BPS = 10_000;

/**
 * Weight table for event families.
 * Infrastructure events (clock, room, mapping) carry weight 0.
 * Families not listed default to weight 1.
 */
const FAMILY_WEIGHT: Record<string, number> = {
  'jam.note.on':                 4,
  'jam.note.off':                1,
  'jam.note.expression':         2,
  'jam.trigger':                 4,
  'jam.input.pad':               2,
  'jam.input.key':               2,
  'jam.input.touch':             2,
  'jam.input.knob':              1,
  'jam.input.fader':             1,
  'jam.input.gamepad':           1,
  'jam.rack.macro.set':          1,
  'jam.pattern.step.toggle':     1,
  'jam.pattern.step.setVelocity':1,
  'jam.pattern.step.setProbability': 1,
  'jam.clip.launch.queue':       2,
  'jam.scene.launch':            2,
  'jam.arrangement.take.capture':3,
  // Extension accounting: zero weight in player splits;
  // royalty attribution is handled separately at session close.
  'jam.extension.install':       0,
  'jam.extension.uninstall':     0,
  'jam.extension.fire':          0,
  // Infrastructure: zero weight
  'jam.clock.tick':              0,
  'jam.clock.start':             0,
  'jam.clock.stop':              0,
  'jam.clock.nudge':             0,
  'jam.room.broadcast.statePatch': 0,
  'jam.room.player.join':        0,
  'jam.room.player.leave':       0,
  'jam.mapping.install':         0,
  'jam.mapping.uninstall':       0,
};

/**
 * Compute the default contribution splits for a set of captured events.
 *
 * Algorithm (documented in policy.md):
 *   1. For each player, count weighted events.
 *   2. For each player, compute macro range = (lastEventMs - firstEventMs).
 *   3. Raw score = weighted_event_count + (macroRangeMs / 1000) * 0.1
 *   4. Normalise raw scores to 10 000 bps.
 *   5. Rounding remainder added to highest-scoring player.
 *   6. Solo player always receives 10 000 bps.
 *
 * @returns Map<playerId, splitBps> — splits sum to exactly 10 000 bps.
 */
export function computeContributionSplits(
  events: ContributionInput[],
): Map<string, number> {
  if (events.length === 0) return new Map();

  const statsMap = new Map<string, {
    weightedCount: number;
    minTimeMs: number;
    maxTimeMs: number;
  }>();

  for (const ev of events) {
    const weight = ev.family !== undefined ? (FAMILY_WEIGHT[ev.family] ?? 1) : 1;
    if (weight === 0) continue;

    const existing = statsMap.get(ev.player);
    if (existing) {
      existing.weightedCount += weight;
      if (ev.roomTimeMs < existing.minTimeMs) existing.minTimeMs = ev.roomTimeMs;
      if (ev.roomTimeMs > existing.maxTimeMs) existing.maxTimeMs = ev.roomTimeMs;
    } else {
      statsMap.set(ev.player, {
        weightedCount: weight,
        minTimeMs: ev.roomTimeMs,
        maxTimeMs: ev.roomTimeMs,
      });
    }
  }

  if (statsMap.size === 0) {
    const players = [...new Set(events.map((e) => e.player))];
    return distributeEqually(players);
  }

  const playerScores: Array<{ player: string; rawScore: number }> = [];
  for (const [player, stats] of statsMap) {
    const macroRangeMs = stats.maxTimeMs - stats.minTimeMs;
    const rawScore = stats.weightedCount + (macroRangeMs / 1000) * 0.1;
    playerScores.push({ player, rawScore });
  }

  const totalRaw = playerScores.reduce((sum, p) => sum + p.rawScore, 0);
  if (totalRaw === 0) {
    return distributeEqually(playerScores.map((p) => p.player));
  }

  const splits = new Map<string, number>();
  let allocated = 0;
  let highestPlayer = playerScores[0]!.player;
  let highestBps = 0;

  for (const { player, rawScore } of playerScores) {
    const bps = Math.floor((rawScore / totalRaw) * TOTAL_BPS);
    splits.set(player, bps);
    allocated += bps;
    if (bps > highestBps) {
      highestBps = bps;
      highestPlayer = player;
    }
  }

  const remainder = TOTAL_BPS - allocated;
  if (remainder !== 0) {
    splits.set(highestPlayer, (splits.get(highestPlayer) ?? 0) + remainder);
  }

  return splits;
}

const INHERITANCE_RATE = 0.10;

export interface InheritanceClaim {
  player: string;
  originalFraction: number;
}

export function applyInheritanceSplits(
  newSplits: Map<string, number>,
  inheritanceClaims: InheritanceClaim[],
): Map<string, number> {
  if (inheritanceClaims.length === 0) return newSplits;

  const inheritancePoolBps = Math.floor(INHERITANCE_RATE * TOTAL_BPS);
  const remainingBps = TOTAL_BPS - inheritancePoolBps;

  const result = new Map<string, number>();
  for (const [player, bps] of newSplits) {
    result.set(player, Math.floor((bps / TOTAL_BPS) * remainingBps));
  }

  for (const claim of inheritanceClaims) {
    const inheritBps = Math.floor(claim.originalFraction * inheritancePoolBps);
    const existing = result.get(claim.player) ?? 0;
    result.set(claim.player, existing + inheritBps);
  }

  const total = [...result.values()].reduce((a, b) => a + b, 0);
  const delta = TOTAL_BPS - total;
  if (delta !== 0) {
    let maxPlayer = '';
    let maxBps = -1;
    for (const [p, b] of result) {
      if (b > maxBps) { maxBps = b; maxPlayer = p; }
    }
    if (maxPlayer) result.set(maxPlayer, (result.get(maxPlayer) ?? 0) + delta);
  }

  return result;
}

export function distributeEqually(players: string[]): Map<string, number> {
  if (players.length === 0) return new Map();
  const result = new Map<string, number>();
  const base = Math.floor(TOTAL_BPS / players.length);
  let allocated = 0;
  for (const p of players) {
    result.set(p, base);
    allocated += base;
  }
  const remainder = TOTAL_BPS - allocated;
  if (remainder !== 0) {
    result.set(players[0]!, (result.get(players[0]!) ?? 0) + remainder);
  }
  return result;
}

```
