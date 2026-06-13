---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/contrib/policy.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.607173+00:00
---

# Contribution Split Policy

## Overview

Contribution splits determine how credit and (optionally) revenue is divided among
players in a jam session. Splits are expressed in **basis points** (bps) where
**10,000 bps = 100%**.

Splits are **immutable** once a `JamboxContributionObject` is committed. A fork of
a session may narrow (reduce) splits but never widen them — enforcement is in
`validateForkLicense()`.

---

## Scoring algorithm (`computeContributionSplits`)

### Step 1 — Event weights

| Event type         | Weight |
| ------------------ | ------ |
| `jam.note.on`      | 4      |
| `jam.trigger`      | 4      |
| `jam.input.pad`    | 2      |
| `jam.rack.macro.set` | 1    |
| `jam.clock.*`      | 0      |

### Step 2 — Weighted count

For each player, sum the weights of their contribution events:

```
rawScore(player) = Σ weight(event) for each event by player
```

For macro events specifically, the continuous range duration (ms) also adds a small
bonus:

```
macroBonus(player) = (totalMacroRangeMs / 1000) * 0.1
finalScore(player) = rawScore(player) + macroBonus(player)
```

### Step 3 — Normalise to 10,000 bps

```
totalScore = Σ finalScore(player)
rawBps(player) = floor(finalScore(player) / totalScore * 10_000)
```

Rounding remainder is assigned to the player with the highest score to ensure
splits always sum to exactly 10,000.

### Step 4 — Edge cases

- **All infrastructure** (zero musical scores): `distributeEqually()` returns equal
  shares, with remainder to the first player.
- **Single player**: 10,000 bps.

---

## Inheritance pool (`applyInheritanceSplits`)

When a new session forks or remixes an existing one, a **10% inheritance pool** is
reserved from the new session's total splits and distributed to players named in
the parent's `claims` object (the `parentSplits` parameter).

```
inheritancePool = 900 bps  (9% of 10,000)
newPlayerPool   = 9,100 bps
```

Parent players receive `floor(parentSplit_bps / 10_000 * inheritancePool)` bps,
with the remainder distributed proportionally. New-session splits are then
re-normalised to fill the remaining 9,100 bps.

---

## License lattice

```
personal  (0)  <  remixable  (1)  <  commercial  (2)
```

A fork may only use a license that is **equal to or narrower** than the parent's
license. Attempting to widen the license throws `LicenseViolationError`.

This is enforced by `validateForkLicense()` in `src/contrib/fork.ts`.

---

## Hard rules

1. Splits are computed once per take and written into the `JamboxContributionPayload`.
2. Once a `JamboxContributionObject` is installed in the registry, its splits cannot
   be modified.
3. Audio bounce requires **explicit per-session consent** from all players — no
   "remember my choice", no automatic bounce.
4. Anchoring (on-chain commit) is always triggered explicitly by the user — never
   automatic.
