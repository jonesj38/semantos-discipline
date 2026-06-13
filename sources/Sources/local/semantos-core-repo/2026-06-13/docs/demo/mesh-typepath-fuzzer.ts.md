---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/demo/mesh-typepath-fuzzer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.746797+00:00
---

# docs/demo/mesh-typepath-fuzzer.ts

```ts
#!/usr/bin/env bun
/**
 * mesh-typepath-fuzzer.ts — D-SRS-typepath-fuzzer
 *
 * Coverage-guided semantic type-path fuzzer.
 *
 * The coverage signal is the emergent MNCA state — a fuzzed path that drives
 * the CA into a novel state region discovered new subscriber topology (keep +
 * emit); an already-explored state is redundant (deprioritise).
 *
 * HRR (Holographic Reduced Representation) makes the walk semantic: bigram
 * similarity between type paths guides mutation toward adjacent regions in
 * binding space rather than pure random exploration.
 *
 * SAFETY: all generated paths contain ".fuzz." so production subscriber state
 * is never perturbed (*.fuzz.* namespace is reserved for probe cells per the
 * D-SRS spec §3.3-3.4). No mainnet transactions; no private keys; no broadcast.
 *
 * Architecture:
 *   1. Seed corpus from the 5 canonical MNCA type paths.
 *   2. Each fuzz round: pick SEEDS_PER_ROUND top seeds, generate
 *      MUTATIONS_PER_SEED mutations each, derive their SNS multicast group.
 *   3. Fingerprint each group (proxy for the MNCA state that would emerge from
 *      subscribers on that group). Novel fingerprint → high priority + emit.
 *   4. Optionally cross-check live MNCA state from DATA_URL (:4402).
 *   5. Serve GET /corpus (all discovered paths), GET /novel (novel subset),
 *      and GET /events (SSE stream of novel discoveries) on FUZZER_PORT.
 *
 * Run:
 *   bun docs/demo/mesh-typepath-fuzzer.ts
 * Env:
 *   DATA_URL           (http://localhost:4402)  data-cell source (optional)
 *   FUZZER_PORT        (4403)                   port for this service
 *   ROUND_MS           (800)                    fuzz round interval
 *   MUTATIONS_PER_SEED (8)                      mutations per seed per round
 *   SEEDS_PER_ROUND    (4)                      seeds to expand per round
 *   ANCHOR_EVERY       (10)                     log anchor candidate every N novel paths
 *
 * D-SRS deliverable: D-SRS-typepath-fuzzer (docs/canon/deliverables.yml).
 */

import { deriveMulticastGroup, type TypeAxes } from '../../core/protocol-types/src/mnca/srv6';

// ── safety ────────────────────────────────────────────────────────────────────

/**
 * Return true iff the path is safe to probe.
 *
 * All fuzz probe paths must contain ".fuzz." (separating a prefix namespace
 * from the probe slug) OR start with "fuzz." (dedicated fuzz root). This
 * ensures no production subscriber state is perturbed.
 *
 * @example
 *   isSafePath('mnca.fuzz.tile.burst')  // true
 *   isSafePath('fuzz.probe123')         // true
 *   isSafePath('mnca.tile.tick')        // false — production path
 */
export function isSafePath(path: string): boolean {
  return path.includes('.fuzz.') || path.startsWith('fuzz.');
}

// ── path analysis (HRR walk) ──────────────────────────────────────────────────

/**
 * Split a dotted type path into its segment array.
 * @example pathSegments('mnca.tile.tick') → ['mnca', 'tile', 'tick']
 */
export function pathSegments(path: string): string[] {
  return path.split('.');
}

/**
 * Compute sliding-window bigrams of path segments.
 *
 * Bigrams are the granularity unit for HRR similarity: two paths that share
 * many adjacent-segment pairs are semantically close; disjoint bigram sets
 * indicate distant type regions.
 *
 * @example
 *   pathBigrams('a.b.c') → Set { 'a.b', 'b.c' }
 *   pathBigrams('x')     → Set {}   (single segment — no bigrams)
 */
export function pathBigrams(path: string): Set<string> {
  const segs = pathSegments(path);
  const out  = new Set<string>();
  for (let i = 0; i < segs.length - 1; i++) {
    out.add(`${segs[i]}.${segs[i + 1]}`);
  }
  return out;
}

/**
 * Jaccard similarity of bigram sets — the HRR proximity metric.
 *
 * Returns 1.0 for identical paths, 0.0 for completely disjoint paths.
 * Paths with fewer than 2 segments have empty bigram sets; two single-segment
 * paths compare as 1.0 (vacuously equal).
 *
 * @example
 *   hrrSimilarity('mnca.tile.tick',  'mnca.tile.v0')    → 0.333  (share 'mnca.tile')
 *   hrrSimilarity('mnca.tile.tick',  'mnca.tile.tick')  → 1.0
 *   hrrSimilarity('mnca.tile.tick',  'data.stream.log') → 0.0
 */
export function hrrSimilarity(a: string, b: string): number {
  const ba = pathBigrams(a);
  const bb = pathBigrams(b);
  if (ba.size === 0 && bb.size === 0) return 1.0;
  if (ba.size === 0 || bb.size === 0) return 0.0;
  let intersection = 0;
  for (const g of ba) { if (bb.has(g)) intersection++; }
  const union = ba.size + bb.size - intersection;
  return intersection / union;
}

// ── axes extraction ───────────────────────────────────────────────────────────

/**
 * Derive SNS TypeAxes from a dotted type path.
 *
 * Convention: last segment = HOW; everything before = WHAT; no INST.
 * This mirrors the canonical MNCA axis table in `srv6.ts`.
 *
 * @example
 *   deriveAxes('mnca.tile.tick')       → { what: 'mnca.tile', how: 'tick' }
 *   deriveAxes('mnca.fuzz.probe.burst')→ { what: 'mnca.fuzz.probe', how: 'burst' }
 * @throws if fewer than 2 segments
 */
export function deriveAxes(path: string): TypeAxes {
  const segs = pathSegments(path);
  if (segs.length < 2) {
    throw new Error(`Type path needs at least 2 segments: "${path}"`);
  }
  const how  = segs[segs.length - 1]!;
  const what = segs.slice(0, -1).join('.');
  return { what, how };
}

// ── deterministic PRNG ────────────────────────────────────────────────────────

/** Vocabulary for mutation slugs — semantically resonant with MNCA / mesh concepts. */
export const MUTATION_VOCAB = [
  'probe', 'sweep', 'burst', 'tick',  'sync',  'edge',  'pulse', 'echo',
  'wave',  'flux',  'drift', 'seed',  'scan',  'snap',  'mesh',  'cell',
  'gate',  'span',  'flow',  'link',  'ring',  'node',  'hop',   'arc',
  'fan',   'step',  'decay', 'spawn', 'relay', 'bloom', 'quench','inject',
] as const;

/**
 * Linear Congruential Generator — fast, deterministic, reproducible.
 *
 * Used so that mutation sequences can be replayed from a seed, enabling
 * fuzzer regression tests and corpus replay.
 */
export class Lcg {
  private state: number;

  constructor(seed: number) {
    this.state = seed >>> 0;
  }

  /** Advance the generator and return the next 32-bit value. */
  next(): number {
    // Numerical Recipes parameters
    this.state = (Math.imul(this.state, 1664525) + 1013904223) >>> 0;
    return this.state;
  }

  /** Return a value in [0, max). */
  nextInt(max: number): number {
    return this.next() % max;
  }

  /** Pick a random word from MUTATION_VOCAB. */
  nextWord(): string {
    return MUTATION_VOCAB[this.nextInt(MUTATION_VOCAB.length)]!;
  }
}

// ── mutation engine ───────────────────────────────────────────────────────────

/**
 * Generate N safe mutations of a seed type path.
 *
 * All produced paths contain ".fuzz." (safety invariant verified internally).
 * Duplication is avoided; if the same candidate is produced by multiple
 * strategies the Set absorbs it and the loop continues until N distinct
 * candidates are accumulated.
 *
 * Mutation strategies:
 *   0. Insert ".fuzz." after the first segment: `mnca.fuzz.tile.tick`
 *   1. Append ".fuzz.<word>" to the WHAT prefix: `mnca.tile.fuzz.probe`
 *   2. Cross-graft: root.fuzz.<word>.<last-segment>: `mnca.fuzz.probe.tick`
 *   3. Full regen from the root segment: `mnca.fuzz.<word>`
 *
 * @param seed  Source type path to mutate (may be a production or fuzz path).
 * @param lcg   Pseudo-random source (pass a fresh Lcg for reproducibility).
 * @param n     Number of distinct mutations to return.
 */
export function generateMutations(seed: string, lcg: Lcg, n: number): string[] {
  const segs = pathSegments(seed);
  const out  = new Set<string>();

  // Maximum iterations before giving up — prevents infinite loops when the
  // vocabulary is exhausted for a given namespace (safety-only, should not
  // trigger in normal use since total unique paths >> n).
  const MAX_ITERS = Math.max(4096, n * 64);
  let iters = 0;

  while (out.size < n && iters++ < MAX_ITERS) {
    const strategy = lcg.nextInt(4);
    let candidate: string;

    switch (strategy) {
      case 0: {
        // Insert .fuzz. after the first segment: `root.fuzz.<rest-of-seed>`
        const rest = segs.length > 1 ? segs.slice(1).join('.') : lcg.nextWord();
        candidate = `${segs[0]}.fuzz.${rest}`;
        break;
      }
      case 1: {
        // Append .fuzz.<word> to the WHAT prefix (all segments except last).
        const what = segs.length > 1 ? segs.slice(0, -1).join('.') : segs[0]!;
        candidate = `${what}.fuzz.${lcg.nextWord()}`;
        break;
      }
      case 2: {
        // Cross-graft: root.fuzz.<word>.<last-segment> — different from strategy 1.
        const last = segs[segs.length - 1]!;
        candidate = `${segs[0]}.fuzz.${lcg.nextWord()}.${last}`;
        break;
      }
      default: {
        // Full regen from root: root.fuzz.<word>
        candidate = `${segs[0]}.fuzz.${lcg.nextWord()}`;
        break;
      }
    }

    // Safety gate — must hold by construction but checked defensively.
    if (isSafePath(candidate)) out.add(candidate);
  }

  return Array.from(out);
}

// ── coverage fingerprinting ───────────────────────────────────────────────────

/**
 * Compute a stable 32-bit fingerprint from an IPv6 multicast group address.
 *
 * In a live mesh, the fingerprint would be a hash of the MNCA tile states
 * observed after probing a group (subscribers self-select → different MNCA
 * state patterns). In the demo harness, the group address bytes ARE the
 * coverage signal — each unique group identifies a distinct subscriber region.
 *
 * The hash is Murmur-inspired to give good avalanche effect: a 1-bit change
 * in any group nibble flips ~half the output bits.
 *
 * @param group  Fully-expanded IPv6 group, e.g. `"ff15:4ed1:aabd:873d:e970:0000:0000:0000"`.
 * @returns      32-bit fingerprint (unsigned).
 */
export function fingerprintGroup(group: string): number {
  const parts = group.split(':');
  let h = 0x811c9dc5 >>> 0;  // FNV offset basis
  for (let i = 0; i < parts.length; i++) {
    const v = (parseInt(parts[i]!, 16) || 0) >>> 0;
    // Murmur-inspired mix
    h = (Math.imul(h ^ v, 2654435769) >>> 0);
    h = (Math.imul(h, 2246822519) ^ (h >>> 13)) >>> 0;
  }
  h ^= h >>> 16;
  return h >>> 0;
}

// ── corpus management ─────────────────────────────────────────────────────────

/** A single entry in the fuzzer corpus. */
export interface CorpusEntry {
  /** Dotted type path — always safe (isSafePath === true). */
  path:        string;
  /** Derived SNS multicast group address. */
  group:       string;
  /** Coverage fingerprint (proxy for emergent MNCA state). */
  fingerprint: number;
  /** True if the fingerprint was new when this path was first evaluated. */
  novel:       boolean;
  /** Monotonic discovery counter (lower = earlier). */
  discovered:  number;
  /** Exploration priority (higher = expand first). */
  priority:    number;
}

/**
 * Compute an exploration priority score for a candidate path.
 *
 * Novel fingerprints score 1.0 — they discovered new state space.
 * Known fingerprints score by their HRR distance from the nearest
 * already-explored path: more distant = higher exploration value.
 *
 * @param path        Candidate type path.
 * @param novel       Whether the fingerprint is new.
 * @param knownPaths  All paths already in the corpus (for HRR comparison).
 */
export function computePriority(
  path:        string,
  novel:       boolean,
  knownPaths:  string[],
): number {
  if (novel) return 1.0;
  if (knownPaths.length === 0) return 0.5;

  // Distance from the NEAREST known path = 1 - max(similarity).
  // High similarity to a known path means the region is already explored → low value.
  // Maximum distance from any known path → most frontier-like → high priority.
  let maxSim = 0.0;
  for (const k of knownPaths) {
    const sim = hrrSimilarity(path, k);
    if (sim > maxSim) maxSim = sim;
  }
  return 1.0 - maxSim;  // 0 = identical to a known path; 1 = maximally different
}

/**
 * Pick the next K seeds to expand from the corpus.
 *
 * Sorts by descending priority: novel paths first, then by HRR distance
 * from the explored frontier.
 *
 * @param corpus  Full list of discovered entries.
 * @param k       Number of seeds to return.
 */
export function pickNextSeeds(corpus: CorpusEntry[], k: number): CorpusEntry[] {
  return [...corpus]
    .sort((a, b) => b.priority - a.priority || a.discovered - b.discovered)
    .slice(0, k);
}

// ── main server ───────────────────────────────────────────────────────────────

if (import.meta.main) {
  // ── config ──────────────────────────────────────────────────────────────────

  const DATA_URL           = process.env.DATA_URL           ?? 'http://localhost:4402';
  const FUZZER_PORT        = Number(process.env.FUZZER_PORT        ?? 4403);
  const ROUND_MS           = Number(process.env.ROUND_MS           ?? 800);
  const MUTATIONS_PER_SEED = Number(process.env.MUTATIONS_PER_SEED ?? 8);
  const SEEDS_PER_ROUND    = Number(process.env.SEEDS_PER_ROUND    ?? 4);
  const ANCHOR_EVERY       = Number(process.env.ANCHOR_EVERY       ?? 10);

  // ── state ────────────────────────────────────────────────────────────────────

  const SEED_PATHS = [
    'mnca.tile.tick',
    'mnca.tile.v0',
    'mnca.tile.injection',
    'mnca.snapshot',
    'mnca.perturb',
  ];

  const corpus:   CorpusEntry[]           = [];
  const coverage: Map<number, string>     = new Map();  // fingerprint → first path
  const clients:  Set<(d: string) => void> = new Set();
  let   counter   = 0;
  let   lcg       = new Lcg(Date.now() & 0xFFFFFFFF);
  let   roundCount = 0;

  // ── optional live tile fingerprint (D-SRS-mnca-cell-source integration) ──────

  /** Fetch MNCA tile state fingerprint from the data source if available. */
  async function fetchLiveTileFp(): Promise<number | null> {
    try {
      const res   = await fetch(`${DATA_URL}/tiles`, { signal: AbortSignal.timeout(500) });
      if (!res.ok) return null;
      const tiles = await res.json() as Array<{ cells: number[] }>;
      if (tiles.length === 0) return null;
      // XOR-fold all cell values into a 32-bit fingerprint.
      let h = 0;
      for (const t of tiles) {
        for (let i = 0; i < t.cells.length; i++) {
          h = (Math.imul(h ^ (t.cells[i]! + i), 2654435769)) >>> 0;
        }
      }
      return h >>> 0;
    } catch {
      return null;
    }
  }

  // ── fuzz round ───────────────────────────────────────────────────────────────

  async function fuzzRound(): Promise<void> {
    roundCount++;

    // Pick seeds: use canonical seeds for the first round; then use corpus.
    const seeds: string[] = corpus.length < SEEDS_PER_ROUND
      ? SEED_PATHS.slice(0, SEEDS_PER_ROUND)
      : pickNextSeeds(corpus, SEEDS_PER_ROUND).map(e => e.path);

    // Optional live-tile fingerprint (mix into coverage signal if available).
    const liveFp = await fetchLiveTileFp();

    for (const seed of seeds) {
      const mutations = generateMutations(seed, lcg, MUTATIONS_PER_SEED);

      for (const path of mutations) {
        // Derive the SNS multicast group.
        let group: string;
        try {
          group = await deriveMulticastGroup(deriveAxes(path));
        } catch {
          continue;  // malformed path — skip
        }

        // Compute coverage fingerprint.  Mix live tile state if present.
        let fp = fingerprintGroup(group);
        if (liveFp !== null) {
          fp = (Math.imul(fp ^ liveFp, 2654435769)) >>> 0;
        }

        const novel = !coverage.has(fp);
        if (novel) coverage.set(fp, path);

        const knownPaths = corpus.map(e => e.path);
        const priority   = computePriority(path, novel, knownPaths);

        const entry: CorpusEntry = {
          path, group, fingerprint: fp, novel, discovered: ++counter, priority,
        };
        corpus.push(entry);

        if (novel) {
          const json = JSON.stringify(entry);
          for (const send of clients) send(json);
          console.log(
            `  ★ novel path=${path} group=${group} fp=0x${fp.toString(16).padStart(8,'0')}`,
          );

          // Log anchor candidate every ANCHOR_EVERY novel discoveries.
          if (coverage.size % ANCHOR_EVERY === 0) {
            console.log(
              `  ⚓ anchor candidate #${coverage.size}: "${path}"  group=${group}` +
              `  (dry-run only — broadcast gated on operator)`,
            );
          }
        }
      }
    }

    if (roundCount % 10 === 1) {
      const novelPct = corpus.length > 0
        ? ((coverage.size / corpus.length) * 100).toFixed(1)
        : '0.0';
      console.log(
        `  [fuzzer] round=${roundCount} corpus=${corpus.length}` +
        ` novel=${coverage.size} (${novelPct}%)` +
        ` live_fp=${liveFp !== null ? '0x' + liveFp.toString(16) : 'none'}`,
      );
    }
  }

  // ── HTTP server ───────────────────────────────────────────────────────────────

  const cors = { 'Access-Control-Allow-Origin': '*', 'Content-Type': 'application/json' };

  Bun.serve({
    port: FUZZER_PORT,
    async fetch(req) {
      const url = new URL(req.url);

      // GET /corpus — all discovered paths.
      if (url.pathname === '/corpus') {
        return Response.json(corpus, { headers: cors });
      }

      // GET /novel — novel paths only.
      if (url.pathname === '/novel') {
        return Response.json(corpus.filter(e => e.novel), { headers: cors });
      }

      // GET /stats — coverage summary.
      if (url.pathname === '/stats') {
        return Response.json({
          corpus:   corpus.length,
          novel:    coverage.size,
          rounds:   roundCount,
          coverage: corpus.length > 0
            ? Number(((coverage.size / corpus.length) * 100).toFixed(1))
            : 0,
        }, { headers: cors });
      }

      // GET /events — SSE stream of novel discoveries.
      if (url.pathname === '/events') {
        let send!: (data: string) => void;
        const stream = new ReadableStream<Uint8Array>({
          start(controller) {
            const enc = new TextEncoder();
            send = (data) => {
              try { controller.enqueue(enc.encode(`data: ${data}\n\n`)); }
              catch { /* closed */ }
            };
            // Replay existing novel corpus entries to the new subscriber.
            for (const e of corpus.filter(n => n.novel)) {
              send(JSON.stringify(e));
            }
            clients.add(send);
          },
          cancel() { clients.delete(send); },
        });
        return new Response(stream, {
          headers: {
            'Content-Type':                 'text/event-stream',
            'Cache-Control':                'no-cache',
            'Connection':                   'keep-alive',
            'Access-Control-Allow-Origin':  '*',
          },
        });
      }

      return new Response(
        'mesh-typepath-fuzzer — D-SRS-typepath-fuzzer\n' +
        'GET /corpus   — all discovered fuzz paths\n' +
        'GET /novel    — novel paths (new MNCA state regions)\n' +
        'GET /stats    — coverage summary\n' +
        'GET /events   — SSE stream of novel discoveries\n' +
        'SAFETY: all paths are *.fuzz.* scoped; no production state perturbed\n',
        { headers: { 'Content-Type': 'text/plain', 'Access-Control-Allow-Origin': '*' } },
      );
    },
  });

  // ── start fuzz loop ───────────────────────────────────────────────────────────

  console.log(`mesh-typepath-fuzzer: D-SRS-typepath-fuzzer`);
  console.log(`  Fuzzing type paths scoped to *.fuzz.* (SAFETY: no production state perturbed)`);
  console.log(`  ROUND_MS=${ROUND_MS} MUTATIONS_PER_SEED=${MUTATIONS_PER_SEED} SEEDS_PER_ROUND=${SEEDS_PER_ROUND}`);
  console.log(`  Corpus SSE:  http://localhost:${FUZZER_PORT}/events`);
  console.log(`  Stats:       http://localhost:${FUZZER_PORT}/stats`);
  console.log(`  Corpus JSON: http://localhost:${FUZZER_PORT}/corpus`);

  // Run the first round immediately, then on interval.
  fuzzRound();
  setInterval(fuzzRound, ROUND_MS);
}

```
