---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/mnca-typepath-fuzzer.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.858336+00:00
---

# core/protocol-types/__tests__/mnca-typepath-fuzzer.test.ts

```ts
/**
 * Tests for the D-SRS-typepath-fuzzer pure functions.
 *
 * All tested functions are synchronous and importable without starting the
 * SSE server (import.meta.main guard). The async deriveMulticastGroup is
 * already tested in mnca-srv6.test.ts and is only used in the server
 * block — so it is NOT repeated here.
 *
 * Coverage:
 *   - isSafePath        (safety invariant)
 *   - pathSegments      (split)
 *   - pathBigrams       (HRR units)
 *   - hrrSimilarity     (Jaccard proximity)
 *   - deriveAxes        (WHAT / HOW extraction)
 *   - Lcg               (reproducible PRNG)
 *   - generateMutations (safety + count + distinctness + replay)
 *   - fingerprintGroup  (stability + avalanche)
 *   - computePriority   (novel=1, seen scoring by frontier distance)
 *   - pickNextSeeds     (sort by priority)
 */

import { describe, expect, test } from 'bun:test';
import {
  isSafePath,
  pathSegments,
  pathBigrams,
  hrrSimilarity,
  deriveAxes,
  Lcg,
  generateMutations,
  fingerprintGroup,
  computePriority,
  pickNextSeeds,
  type CorpusEntry,
} from '../../../docs/demo/mesh-typepath-fuzzer';

// ── isSafePath ────────────────────────────────────────────────────────────────

describe('isSafePath', () => {
  test('accepts paths containing .fuzz.', () => {
    expect(isSafePath('mnca.fuzz.tile.burst')).toBe(true);
    expect(isSafePath('mnca.tile.fuzz.probe')).toBe(true);
    expect(isSafePath('data.fuzz.stream.scan')).toBe(true);
  });

  test('accepts paths starting with fuzz.', () => {
    expect(isSafePath('fuzz.probe')).toBe(true);
    expect(isSafePath('fuzz.anything.else')).toBe(true);
  });

  test('rejects production paths (no .fuzz. or fuzz. prefix)', () => {
    expect(isSafePath('mnca.tile.tick')).toBe(false);
    expect(isSafePath('mnca.snapshot')).toBe(false);
    expect(isSafePath('data.stream.log')).toBe(false);
  });

  test('rejects "mnca.fuzz" (no trailing dot after fuzz)', () => {
    // ".fuzz." requires a dot on both sides; "mnca.fuzz" ends at fuzz
    expect(isSafePath('mnca.fuzz')).toBe(false);
    // bare "fuzz" has no leading dot, so it doesn't satisfy "fuzz." either
    expect(isSafePath('fuzz')).toBe(false);
  });
});

// ── pathSegments ──────────────────────────────────────────────────────────────

describe('pathSegments', () => {
  test('splits on dots', () => {
    expect(pathSegments('mnca.tile.tick')).toEqual(['mnca', 'tile', 'tick']);
  });

  test('single segment returns array of one', () => {
    expect(pathSegments('mnca')).toEqual(['mnca']);
  });

  test('preserves all segments for deep paths', () => {
    expect(pathSegments('mnca.fuzz.tile.probe.burst')).toEqual(
      ['mnca', 'fuzz', 'tile', 'probe', 'burst'],
    );
  });
});

// ── pathBigrams ───────────────────────────────────────────────────────────────

describe('pathBigrams', () => {
  test('single segment → empty set', () => {
    expect(pathBigrams('mnca').size).toBe(0);
  });

  test('two segments → one bigram', () => {
    const bg = pathBigrams('mnca.tile');
    expect(bg.size).toBe(1);
    expect(bg.has('mnca.tile')).toBe(true);
  });

  test('three segments → two bigrams', () => {
    const bg = pathBigrams('mnca.tile.tick');
    expect(bg.size).toBe(2);
    expect(bg.has('mnca.tile')).toBe(true);
    expect(bg.has('tile.tick')).toBe(true);
  });

  test('four segments → three bigrams', () => {
    const bg = pathBigrams('mnca.fuzz.tile.burst');
    expect(bg.size).toBe(3);
    expect(bg.has('mnca.fuzz')).toBe(true);
    expect(bg.has('fuzz.tile')).toBe(true);
    expect(bg.has('tile.burst')).toBe(true);
  });
});

// ── hrrSimilarity ─────────────────────────────────────────────────────────────

describe('hrrSimilarity', () => {
  test('identical paths → 1.0', () => {
    expect(hrrSimilarity('mnca.tile.tick', 'mnca.tile.tick')).toBe(1.0);
  });

  test('completely disjoint bigrams → 0.0', () => {
    // {mnca.tile, tile.tick} ∩ {data.stream, stream.log} = ∅
    expect(hrrSimilarity('mnca.tile.tick', 'data.stream.log')).toBe(0.0);
  });

  test('shared prefix bigram → partial similarity', () => {
    // 'mnca.tile.tick' bigrams: {mnca.tile, tile.tick}
    // 'mnca.tile.v0'   bigrams: {mnca.tile, tile.v0}
    // intersection={mnca.tile}=1, union=3 → Jaccard = 1/3
    const sim = hrrSimilarity('mnca.tile.tick', 'mnca.tile.v0');
    expect(sim).toBeCloseTo(1 / 3, 5);
  });

  test('two single-segment paths → 1.0 (vacuously equal empty bigram sets)', () => {
    expect(hrrSimilarity('mnca', 'data')).toBe(1.0);
  });

  test('one single-segment, one multi-segment → 0.0', () => {
    expect(hrrSimilarity('mnca', 'mnca.tile.tick')).toBe(0.0);
  });
});

// ── deriveAxes ────────────────────────────────────────────────────────────────

describe('deriveAxes', () => {
  test('3-segment path → WHAT=first2, HOW=last', () => {
    const axes = deriveAxes('mnca.tile.tick');
    expect(axes.what).toBe('mnca.tile');
    expect(axes.how).toBe('tick');
    expect(axes.inst).toBeUndefined();
  });

  test('2-segment path → WHAT=first, HOW=last', () => {
    const axes = deriveAxes('mnca.snapshot');
    expect(axes.what).toBe('mnca');
    expect(axes.how).toBe('snapshot');
  });

  test('4-segment fuzz path → WHAT=first3, HOW=last', () => {
    const axes = deriveAxes('mnca.fuzz.tile.burst');
    expect(axes.what).toBe('mnca.fuzz.tile');
    expect(axes.how).toBe('burst');
  });

  test('single segment throws', () => {
    expect(() => deriveAxes('mnca')).toThrow();
  });
});

// ── Lcg ───────────────────────────────────────────────────────────────────────

describe('Lcg', () => {
  test('reproducible: same seed → same sequence', () => {
    const a = new Lcg(42);
    const b = new Lcg(42);
    const seqA = Array.from({ length: 20 }, () => a.next());
    const seqB = Array.from({ length: 20 }, () => b.next());
    expect(seqA).toEqual(seqB);
  });

  test('different seeds → different sequences', () => {
    const a = new Lcg(42);
    const b = new Lcg(99);
    expect(a.next()).not.toBe(b.next());
  });

  test('nextInt stays in [0, max)', () => {
    const lcg = new Lcg(7);
    for (let i = 0; i < 100; i++) {
      const v = lcg.nextInt(10);
      expect(v).toBeGreaterThanOrEqual(0);
      expect(v).toBeLessThan(10);
    }
  });

  test('nextWord returns a non-empty string', () => {
    const lcg = new Lcg(123);
    const w = lcg.nextWord();
    expect(typeof w).toBe('string');
    expect(w.length).toBeGreaterThan(0);
  });
});

// ── generateMutations ─────────────────────────────────────────────────────────

describe('generateMutations', () => {
  test('returns exactly N paths', () => {
    const lcg = new Lcg(1);
    const ms  = generateMutations('mnca.tile.tick', lcg, 8);
    expect(ms.length).toBe(8);
  });

  test('all mutations are safe (contain .fuzz. or start with fuzz.)', () => {
    const lcg = new Lcg(2);
    const ms  = generateMutations('mnca.tile.tick', lcg, 20);
    for (const m of ms) {
      expect(isSafePath(m)).toBe(true);
    }
  });

  test('all mutations are distinct (no duplicates)', () => {
    const lcg = new Lcg(3);
    const ms  = generateMutations('mnca.tile.tick', lcg, 12);
    expect(new Set(ms).size).toBe(ms.length);
  });

  test('replay: same seed → same mutations', () => {
    const ms1 = generateMutations('mnca.snapshot', new Lcg(77), 8);
    const ms2 = generateMutations('mnca.snapshot', new Lcg(77), 8);
    expect(ms1).toEqual(ms2);
  });

  test('mutations from a single-segment seed are safe', () => {
    const lcg = new Lcg(99);
    const ms  = generateMutations('mnca', lcg, 8);
    for (const m of ms) {
      expect(isSafePath(m)).toBe(true);
    }
  });

  test('mutations share semantic root with the seed (HRR coherence)', () => {
    const lcg = new Lcg(55);
    const ms  = generateMutations('mnca.tile.tick', lcg, 10);
    // All mutations inherit the root segment from the seed.
    for (const m of ms) {
      expect(m.startsWith('mnca.')).toBe(true);
    }
  });
});

// ── fingerprintGroup ──────────────────────────────────────────────────────────

describe('fingerprintGroup', () => {
  test('returns a non-negative integer', () => {
    const fp = fingerprintGroup('ff15:4ed1:aabd:873d:e970:0000:0000:0000');
    expect(typeof fp).toBe('number');
    expect(fp).toBeGreaterThanOrEqual(0);
  });

  test('stable: same group → same fingerprint', () => {
    const g = 'ff15:4ed1:aabd:873d:e970:0000:0000:0000';
    expect(fingerprintGroup(g)).toBe(fingerprintGroup(g));
  });

  test('all 5 canonical MNCA groups produce distinct fingerprints', () => {
    const groups = [
      'ff15:4ed1:aabd:873d:e970:0000:0000:0000',  // TILE_TICK
      'ff15:4ed1:aabd:e05d:07d2:0000:0000:0000',  // TILE_V0
      'ff15:4ed1:aabd:52a2:420c:0000:0000:0000',  // TILE_INJECTION
      'ff15:60d4:edd5:7b2a:8222:0000:0000:0000',  // SNAPSHOT
      'ff15:60d4:edd5:1064:77f5:0000:0000:0000',  // PERTURB
    ];
    const fps = groups.map(fingerprintGroup);
    expect(new Set(fps).size).toBe(groups.length);
  });

  test('1-nibble group change produces a different fingerprint (avalanche)', () => {
    const g1 = 'ff15:4ed1:aabd:873d:e970:0000:0000:0000';
    const g2 = 'ff15:4ed1:aabd:873d:e971:0000:0000:0000';  // last nibble of group[4]
    expect(fingerprintGroup(g1)).not.toBe(fingerprintGroup(g2));
  });
});

// ── computePriority ───────────────────────────────────────────────────────────

describe('computePriority', () => {
  test('novel path → priority 1.0 regardless of known set', () => {
    expect(computePriority('mnca.fuzz.tile.burst', true, [])).toBe(1.0);
    expect(computePriority('mnca.fuzz.tile.burst', true, ['mnca.tile.tick'])).toBe(1.0);
  });

  test('seen path, identical to a known path → priority ~0 (explored region)', () => {
    // hrrSimilarity(path, path) = 1.0 → maxSim = 1.0 → priority = 1 - 1.0 = 0.0
    const p = computePriority('mnca.tile.fuzz.probe', false, ['mnca.tile.fuzz.probe']);
    expect(p).toBeLessThanOrEqual(0.05);
  });

  test('seen path, no known paths → fallback priority 0.5', () => {
    const p = computePriority('mnca.tile.fuzz.probe', false, []);
    expect(p).toBe(0.5);
  });

  test('seen path, completely disjoint from all known → high priority', () => {
    // 'data.stream.fuzz.probe' shares zero bigrams with 'mnca.tile.tick'
    // → maxSim = 0.0 → priority = 1.0 (maximally frontier-like)
    const p = computePriority('data.stream.fuzz.probe', false, ['mnca.tile.tick']);
    expect(p).toBeGreaterThan(0.8);
  });

  test('seen path, partially overlapping with known → intermediate priority', () => {
    // 'mnca.tile.fuzz.probe' shares 'mnca.tile' with 'mnca.tile.tick'
    // bigrams(path) = {mnca.tile, tile.fuzz, fuzz.probe}
    // bigrams(known) = {mnca.tile, tile.tick}
    // intersection=1, union=4 → sim=0.25 → priority = 1 - 0.25 = 0.75
    const p = computePriority('mnca.tile.fuzz.probe', false, ['mnca.tile.tick']);
    expect(p).toBeGreaterThan(0.5);
    expect(p).toBeLessThan(1.0);
  });
});

// ── pickNextSeeds ─────────────────────────────────────────────────────────────

describe('pickNextSeeds', () => {
  const makeEntry = (path: string, priority: number, discovered: number): CorpusEntry => ({
    path, group: 'ff15:0000:0000:0000:0000:0000:0000:0000',
    fingerprint: 0, novel: priority === 1.0, discovered, priority,
  });

  test('returns at most k entries', () => {
    const corpus: CorpusEntry[] = [
      makeEntry('mnca.fuzz.a', 0.8, 1),
      makeEntry('mnca.fuzz.b', 0.2, 2),
      makeEntry('mnca.fuzz.c', 1.0, 3),
    ];
    expect(pickNextSeeds(corpus, 2).length).toBe(2);
  });

  test('sorts by descending priority', () => {
    const corpus: CorpusEntry[] = [
      makeEntry('mnca.fuzz.low',  0.1, 1),
      makeEntry('mnca.fuzz.high', 1.0, 2),
      makeEntry('mnca.fuzz.mid',  0.5, 3),
    ];
    const seeds = pickNextSeeds(corpus, 3);
    expect(seeds[0]!.path).toBe('mnca.fuzz.high');
    expect(seeds[1]!.path).toBe('mnca.fuzz.mid');
    expect(seeds[2]!.path).toBe('mnca.fuzz.low');
  });

  test('breaks priority ties by discovery order (earlier first)', () => {
    const corpus: CorpusEntry[] = [
      makeEntry('mnca.fuzz.later',   1.0, 5),
      makeEntry('mnca.fuzz.earlier', 1.0, 2),
    ];
    const seeds = pickNextSeeds(corpus, 2);
    expect(seeds[0]!.path).toBe('mnca.fuzz.earlier');
  });

  test('k larger than corpus returns all entries', () => {
    const corpus: CorpusEntry[] = [
      makeEntry('mnca.fuzz.a', 0.3, 1),
      makeEntry('mnca.fuzz.b', 0.7, 2),
    ];
    expect(pickNextSeeds(corpus, 100).length).toBe(2);
  });

  test('empty corpus returns empty array', () => {
    expect(pickNextSeeds([], 4)).toEqual([]);
  });
});

```
