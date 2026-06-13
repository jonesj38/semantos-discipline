---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/research/experiments/chess-hrr-experiment.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.046061+00:00
---

# research/experiments/chess-hrr-experiment.ts

```ts
#!/usr/bin/env bun
/**
 * WI-E1 — Chess opening HRR clustering experiment.
 *
 * Tests whether HRR encoding captures structural similarity across chess
 * openings — a domain where ground truth is well-established (ECO taxonomy,
 * 500+ years of human consensus on opening families).
 *
 * Connection to the cognition stack:
 *   The Pask conformance test (core/pask/tests/chess_conformance.zig) showed
 *   that 1500 GM games → stable threads = canonical opening theory. Here we
 *   encode those same stable prefixes as HRR vectors and check whether the
 *   encoding respects known opening family relationships.
 *
 *   If it does: HRR + Pask stability is a tractable substrate for "recognising
 *   that a novel situation instantiates an existing category" — the 50-year
 *   hard problem from Pask (1975).
 *
 * Encoding:
 *   Prefix "e4 c5 Nf3 d6" → four (role, filler) bindings:
 *     { role: 'ply_1', filler: 'e4'  }
 *     { role: 'ply_2', filler: 'c5'  }
 *     { role: 'ply_3', filler: 'Nf3' }
 *     { role: 'ply_4', filler: 'd6'  }
 *   all with CHESS_DOMAIN = 42.
 *
 * Three falsification gates:
 *   G1  Sibling lines (share 8-9 of 10 plies):  mean cosine > 0.7
 *   G2  Cousin pairs (share 1-4 plies):          mean cosine 0.1–0.5
 *   G3  Cross-system e4 vs d4 (0 shared plies):  mean cosine < 0.2
 *   G4  Corpus: intra-family mean > inter-family mean (ECO separation)
 *
 * Run:  bun research/experiments/chess-hrr-experiment.ts
 *
 * Corpus: ../../../friend-semantos/scripts/chess-paskian-rig/data/twic1500.pgn
 */

import { readFileSync, writeFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { createHash } from 'crypto';

// ── Constants ─────────────────────────────────────────────────────────────────

const D            = 1024;
const CHESS_DOMAIN = 42;
const MAX_PLY      = 10;   // matches chess_conformance.zig
const MAX_GAMES    = 1500; // matches chess_conformance.zig
const STABLE_PCT   = 3;    // prefix in >= 3% of games ≈ stable (45/1500)

const here        = dirname(fileURLToPath(import.meta.url));
const CORPUS_PATH = join(here, '../../../friend-semantos/scripts/chess-paskian-rig/data/twic1500.pgn');

// ── HRR maths (self-contained, same as hrr-encoding-feasibility.ts) ──────────

function seedVec(seed: string): Float64Array {
  const v = new Float64Array(D);
  const blocks = D / 8;
  for (let b = 0; b < blocks; b++) {
    const h = createHash('sha256').update(`${seed}:${b}`).digest();
    for (let j = 0; j < 8; j++) v[b * 8 + j] = h.readInt32BE(j * 4) / 0x80000000;
  }
  return l2norm_vec(v);
}

function dot(a: Float64Array, b: Float64Array): number {
  let s = 0; for (let i = 0; i < a.length; i++) s += a[i] * b[i]; return s;
}
function l2norm_scalar(a: Float64Array): number { return Math.sqrt(dot(a, a)); }
function l2norm_vec(a: Float64Array): Float64Array {
  const n = l2norm_scalar(a);
  if (n < 1e-15) return a;
  const out = new Float64Array(a.length);
  for (let i = 0; i < a.length; i++) out[i] = a[i] / n;
  return out;
}
function cosine(a: Float64Array, b: Float64Array): number {
  return Math.max(-1, Math.min(1, dot(a, b)));
}

function fft(re: Float64Array, im: Float64Array): void {
  const n = re.length;
  let j = 0;
  for (let i = 1; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) {
      let t = re[i]; re[i] = re[j]; re[j] = t;
      t = im[i]; im[i] = im[j]; im[j] = t;
    }
  }
  for (let len = 2; len <= n; len <<= 1) {
    const ang = (-2 * Math.PI) / len;
    const wRe = Math.cos(ang), wIm = Math.sin(ang);
    for (let i = 0; i < n; i += len) {
      let cRe = 1, cIm = 0;
      const half = len >> 1;
      for (let k = 0; k < half; k++) {
        const uRe = re[i+k], uIm = im[i+k];
        const vRe = re[i+k+half]*cRe - im[i+k+half]*cIm;
        const vIm = re[i+k+half]*cIm + im[i+k+half]*cRe;
        re[i+k] = uRe+vRe; im[i+k] = uIm+vIm;
        re[i+k+half] = uRe-vRe; im[i+k+half] = uIm-vIm;
        const nRe = cRe*wRe - cIm*wIm; cIm = cRe*wIm + cIm*wRe; cRe = nRe;
      }
    }
  }
}
function ifft(re: Float64Array, im: Float64Array): void {
  for (let i = 0; i < im.length; i++) im[i] = -im[i];
  fft(re, im);
  const n = re.length;
  for (let i = 0; i < n; i++) { re[i] /= n; im[i] = (-im[i]) / n; }
}
function circConv(a: Float64Array, b: Float64Array): Float64Array {
  const n = a.length;
  const aRe = new Float64Array(a), aIm = new Float64Array(n);
  const bRe = new Float64Array(b), bIm = new Float64Array(n);
  fft(aRe, aIm); fft(bRe, bIm);
  for (let k = 0; k < n; k++) {
    const ar = aRe[k], ai = aIm[k], br = bRe[k], bi = bIm[k];
    aRe[k] = ar*br - ai*bi; aIm[k] = ar*bi + ai*br;
  }
  ifft(aRe, aIm);
  return aRe;
}

/** Encode a chess opening prefix (array of SAN moves) as a single HRR vector. */
function encodePrefix(moves: string[]): Float64Array {
  const sum = new Float64Array(D);
  for (let i = 0; i < moves.length; i++) {
    const rv = seedVec(`${CHESS_DOMAIN}:role:ply_${i + 1}`);
    const fv = seedVec(`${CHESS_DOMAIN}:filler:${moves[i]}`);
    const bnd = circConv(rv, fv);
    for (let j = 0; j < D; j++) sum[j] += bnd[j];
  }
  return l2norm_vec(sum);
}

// ── PGN parser (minimal, inline) ──────────────────────────────────────────────

interface ParsedGame {
  eco:     string;   // ECO code e.g. "B90"
  opening: string;   // Opening name e.g. "Sicilian"
  moves:   string[]; // SAN tokens up to MAX_PLY
}

function parsePGN(text: string, maxGames: number): ParsedGame[] {
  const games: ParsedGame[] = [];
  const blocks = text.split(/\n\s*\n(?=\[)/);
  for (const block of blocks) {
    if (games.length >= maxGames) break;
    if (!block.trim()) continue;
    const game = parseGame(block);
    if (game && game.moves.length >= 2) games.push(game);
  }
  return games;
}

function parseGame(block: string): ParsedGame | null {
  const headers: Record<string, string> = {};
  const lines = block.split('\n');
  let movetextStart = 0;
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].trim().match(/^\[(\w+)\s+"(.*)"\]$/);
    if (m) { headers[m[1]] = m[2]; }
    else if (lines[i].trim()) { movetextStart = i; break; }
  }
  const movetext = lines.slice(movetextStart).join(' ');
  const moves = tokenise(movetext).slice(0, MAX_PLY);
  if (moves.length < 2) return null;
  return {
    eco:     headers['ECO']     ?? '',
    opening: headers['Opening'] ?? '',
    moves,
  };
}

function tokenise(text: string): string[] {
  let s = text.replace(/\{[^}]*\}/g, ' ');
  let prev = '';
  while (s !== prev) { prev = s; s = s.replace(/\([^()]*\)/g, ' '); }
  s = s.replace(/\$\d+/g, ' ').replace(/\b\d+\.(\.\.)?/g, ' ');
  return s.split(/\s+/).filter(t =>
    t.length > 0 &&
    !t.startsWith(';') &&
    !/^(1-0|0-1|1\/2-1\/2|\*)$/.test(t)
  );
}

// ── ECO taxonomy ─────────────────────────────────────────────────────────────
// Map ECO code prefixes to family names.  Ordered most-specific first.

const ECO_FAMILIES: Array<{ prefix: string; family: string }> = [
  { prefix: 'B9',  family: 'Sicilian Najdorf/Dragon'     }, // B90-B99
  { prefix: 'B8',  family: 'Sicilian Scheveningen/Sozin'  }, // B80-B89
  { prefix: 'B7',  family: 'Sicilian Dragon+Pirc'         }, // B70-B79
  { prefix: 'B6',  family: 'Sicilian Richter/Rauzer'      }, // B60-B69
  { prefix: 'B4',  family: 'Sicilian Classical/Kan/Taimanov' },
  { prefix: 'B3',  family: 'Sicilian Nimzo/Accelerated'   },
  { prefix: 'B2',  family: 'Sicilian general'              },
  { prefix: 'B1',  family: 'Caro-Kann'                    },
  { prefix: 'C1',  family: 'French Defence'                },
  { prefix: 'C0',  family: 'French Defence'                },
  { prefix: 'C2',  family: 'Open games (1.e4 e5)'          },
  { prefix: 'C3',  family: 'Open games (1.e4 e5)'          },
  { prefix: 'C4',  family: 'Open games (1.e4 e5)'          },
  { prefix: 'C5',  family: 'Open games (Giuoco/Italian)'   },
  { prefix: 'C6',  family: 'Ruy Lopez'                     },
  { prefix: 'C7',  family: 'Ruy Lopez'                     },
  { prefix: 'C8',  family: 'Ruy Lopez'                     },
  { prefix: 'C9',  family: 'Ruy Lopez'                     },
  { prefix: 'D7',  family: 'Grünfeld Defence'              },
  { prefix: 'D8',  family: 'Grünfeld Defence'              },
  { prefix: 'D9',  family: 'Grünfeld Defence'              },
  { prefix: 'D4',  family: "Queen's Gambit"                },
  { prefix: 'D5',  family: "Queen's Gambit"                },
  { prefix: 'D6',  family: "Queen's Gambit"                },
  { prefix: 'D2',  family: "QGA/Slav"                      },
  { prefix: 'D3',  family: "Semi-Slav"                     },
  { prefix: 'D1',  family: "Slav"                          },
  { prefix: 'D0',  family: "d4 d5 unusual"                 },
  { prefix: 'E9',  family: "King's Indian"                 },
  { prefix: 'E8',  family: "King's Indian"                 },
  { prefix: 'E7',  family: "King's Indian"                 },
  { prefix: 'E6',  family: "King's Indian"                 },
  { prefix: 'E5',  family: 'Nimzo/QID complex'             },
  { prefix: 'E4',  family: 'Nimzo/QID complex'             },
  { prefix: 'E3',  family: 'Nimzo/QID complex'             },
  { prefix: 'E2',  family: 'Nimzo/QID complex'             },
  { prefix: 'E1',  family: 'Catalan / Blumenfeld'          },
  { prefix: 'E0',  family: 'Catalan / Blumenfeld'          },
  { prefix: 'A',   family: 'Flank openings / English'      },
];

function ecoFamily(eco: string): string {
  for (const { prefix, family } of ECO_FAMILIES) {
    if (eco.startsWith(prefix)) return family;
  }
  return 'Other';
}

// Broad groups for cross-system gate (e4-world vs d4-world).
function ecoSystem(eco: string): 'e4' | 'd4' | 'flank' | 'unknown' {
  if (!eco) return 'unknown';
  const c = eco[0];
  if (c === 'B' || c === 'C') return 'e4';
  if (c === 'D' || c === 'E') return 'd4';
  return 'flank';
}

// ── Part 1: Named-pair qualitative table ──────────────────────────────────────

interface NamedLine { name: string; moves: string[] }

const NAMED_OPENINGS: Array<{ family: string; lines: NamedLine[] }> = [
  {
    family: 'Sicilian Open (Najdorf/Dragon/Scheveningen)',
    lines: [
      { name: 'Najdorf',      moves: ['e4','c5','Nf3','d6','d4','cxd4','Nxd4','Nf6','Nc3','a6'] },
      { name: 'Dragon',       moves: ['e4','c5','Nf3','d6','d4','cxd4','Nxd4','Nf6','Nc3','g6'] },
      { name: 'Scheveningen', moves: ['e4','c5','Nf3','d6','d4','cxd4','Nxd4','Nf6','Nc3','e6'] },
      { name: 'Classical',    moves: ['e4','c5','Nf3','d6','d4','cxd4','Nxd4','Nc6'] },
    ],
  },
  {
    family: "King's Indian / Grünfeld complex",
    lines: [
      { name: "King's Indian", moves: ['d4','Nf6','c4','g6','Nc3','Bg7','e4','d6'] },
      { name: 'Grünfeld',      moves: ['d4','Nf6','c4','g6','Nc3','d5'] },
      { name: 'Benoni',        moves: ['d4','Nf6','c4','c5','d5','e6'] },
    ],
  },
  {
    family: 'Nimzo / QID complex',
    lines: [
      { name: 'Nimzo-Indian',    moves: ['d4','Nf6','c4','e6','Nc3','Bb4'] },
      { name: "Queen's Indian",  moves: ['d4','Nf6','c4','e6','Nf3','b6'] },
      { name: 'Catalan',         moves: ['d4','Nf6','c4','e6','g3','d5'] },
    ],
  },
  {
    family: 'Ruy Lopez',
    lines: [
      { name: 'Berlin',          moves: ['e4','e5','Nf3','Nc6','Bb5','Nf6'] },
      { name: 'Closed',          moves: ['e4','e5','Nf3','Nc6','Bb5','a6','Ba4','Nf6'] },
      { name: 'Open (Marshall)', moves: ['e4','e5','Nf3','Nc6','Bb5','a6','Ba4','Nf6','O-O','Nxe4'] },
    ],
  },
];

// Cross-system comparison pairs (e4 world vs d4 world)
const CROSS_SYSTEM_PAIRS: Array<{ a: NamedLine; b: NamedLine }> = [
  {
    a: { name: 'Sicilian Najdorf', moves: ['e4','c5','Nf3','d6','d4','cxd4','Nxd4','Nf6','Nc3','a6'] },
    b: { name: "King's Indian",    moves: ['d4','Nf6','c4','g6','Nc3','Bg7','e4','d6'] },
  },
  {
    a: { name: 'French Defence',   moves: ['e4','e6','d4','d5'] },
    b: { name: 'Nimzo-Indian',     moves: ['d4','Nf6','c4','e6','Nc3','Bb4'] },
  },
  {
    a: { name: 'Ruy Lopez Berlin', moves: ['e4','e5','Nf3','Nc6','Bb5','Nf6'] },
    b: { name: "Queen's Gambit",   moves: ['d4','d5','c4','e6','Nc3','Nf6','cxd5','exd5'] },
  },
  {
    a: { name: 'Caro-Kann',        moves: ['e4','c6','d4','d5','Nd2','dxe4','Nxe4','Bf5'] },
    b: { name: 'Grünfeld',         moves: ['d4','Nf6','c4','g6','Nc3','d5'] },
  },
];

// Cousin pairs — same first move, different family
const COUSIN_PAIRS: Array<{ label: string; a: NamedLine; b: NamedLine }> = [
  {
    label: 'Sicilian vs French (share only 1.e4)',
    a: { name: 'Sicilian Najdorf', moves: ['e4','c5','Nf3','d6','d4','cxd4','Nxd4','Nf6','Nc3','a6'] },
    b: { name: 'French Defence',   moves: ['e4','e6','d4','d5'] },
  },
  {
    label: 'Sicilian vs Caro-Kann (share only 1.e4)',
    a: { name: 'Sicilian Najdorf', moves: ['e4','c5','Nf3','d6','d4','cxd4','Nxd4','Nf6','Nc3','a6'] },
    b: { name: 'Caro-Kann',        moves: ['e4','c6','d4','d5','Nd2','dxe4','Nxe4','Bf5'] },
  },
  {
    label: "KID vs Nimzo (share d4 Nf6 c4, differ at ply 4)",
    a: { name: "King's Indian", moves: ['d4','Nf6','c4','g6','Nc3','Bg7','e4','d6'] },
    b: { name: 'Nimzo-Indian',  moves: ['d4','Nf6','c4','e6','Nc3','Bb4'] },
  },
  {
    label: "Ruy Lopez vs Italian (share e4 e5 Nf3 Nc6, differ at ply 5)",
    a: { name: 'Ruy Lopez', moves: ['e4','e5','Nf3','Nc6','Bb5','a6'] },
    b: { name: 'Italian',   moves: ['e4','e5','Nf3','Nc6','Bc4','Bc5'] },
  },
];

// ── Part 2: Corpus-level ECO family clustering ────────────────────────────────

function samplePairs<T>(arr: T[], n: number): Array<[T, T]> {
  const pairs: Array<[T, T]> = [];
  if (arr.length < 2) return pairs;
  // deterministic pseudo-random sampling using index arithmetic
  let ai = 0, bi = 1;
  while (pairs.length < n && ai < arr.length) {
    pairs.push([arr[ai], arr[bi]]);
    bi += 3; if (bi >= arr.length) { ai++; bi = ai + 1; }
    if (bi >= arr.length) { ai++; bi = ai + 1; }
  }
  return pairs.slice(0, n);
}

function mean(xs: number[]): number {
  if (xs.length === 0) return 0;
  return xs.reduce((s, x) => s + x, 0) / xs.length;
}

// ── Main ──────────────────────────────────────────────────────────────────────

console.log('WI-E1 — Chess opening HRR clustering (D=1024, Plate circular convolution)');
console.log(`Corpus: ${CORPUS_PATH}`);
console.log(`Config: MAX_PLY=${MAX_PLY}, MAX_GAMES=${MAX_GAMES}, STABLE_PCT=${STABLE_PCT}%\n`);

// ── Load corpus ───────────────────────────────────────────────────────────────
console.log('Loading corpus...');
const pgnText = readFileSync(CORPUS_PATH, 'utf8');
const games   = parsePGN(pgnText, MAX_GAMES);
console.log(`  Parsed ${games.length} games.\n`);

// ── Part 1: Named pair cosines ────────────────────────────────────────────────

console.log('══ Part 1: Named opening-pair cosines ═══════════════════════════════════');

const siblingCosines: number[] = [];
for (const fam of NAMED_OPENINGS) {
  console.log(`\n── ${fam.family}`);
  const vecs = fam.lines.map(l => ({ name: l.name, vec: encodePrefix(l.moves), ply: l.moves.length }));
  for (let i = 0; i < vecs.length; i++) {
    for (let j = i + 1; j < vecs.length; j++) {
      const c = cosine(vecs[i].vec, vecs[j].vec);
      // How many plies do they share?
      const li = NAMED_OPENINGS.find(f => f.family === fam.family)!.lines[i].moves;
      const lj = NAMED_OPENINGS.find(f => f.family === fam.family)!.lines[j].moves;
      let shared = 0;
      for (let k = 0; k < Math.min(li.length, lj.length); k++) {
        if (li[k] === lj[k]) shared++; else break;
      }
      const minPly = Math.min(li.length, lj.length);
      console.log(`  ${vecs[i].name} ↔ ${vecs[j].name}`);
      console.log(`    shared ${shared}/${minPly} plies  cos = ${c.toFixed(4)}`);
      siblingCosines.push(c);
    }
  }
}

console.log('\n── Cousin pairs (same first move, different family)');
const cousinCosines: number[] = [];
for (const p of COUSIN_PAIRS) {
  const c = cosine(encodePrefix(p.a.moves), encodePrefix(p.b.moves));
  // Count shared plies
  let shared = 0;
  for (let k = 0; k < Math.min(p.a.moves.length, p.b.moves.length); k++) {
    if (p.a.moves[k] === p.b.moves[k]) shared++; else break;
  }
  const minPly = Math.min(p.a.moves.length, p.b.moves.length);
  console.log(`  [${p.label}]`);
  console.log(`    ${p.a.name} ↔ ${p.b.name}  shared ${shared}/${minPly}  cos = ${c.toFixed(4)}`);
  cousinCosines.push(c);
}

console.log('\n── Cross-system pairs (e4 world vs d4 world — 0 shared plies)');
const crossSysCosines: number[] = [];
for (const p of CROSS_SYSTEM_PAIRS) {
  const c = cosine(encodePrefix(p.a.moves), encodePrefix(p.b.moves));
  console.log(`  ${p.a.name} ↔ ${p.b.name}  cos = ${c.toFixed(4)}`);
  crossSysCosines.push(c);
}

const g1Pass = mean(siblingCosines) > 0.7;
const g2Pass = mean(cousinCosines) > 0.1 && mean(cousinCosines) < 0.5;
const g3Pass = mean(crossSysCosines) < 0.2;

console.log(`\n  Part 1 summary:`);
console.log(`    G1 sibling mean cosine:       ${mean(siblingCosines).toFixed(4)}  target > 0.7   ${g1Pass ? '✓ PASS' : '✗ FAIL'}`);
console.log(`    G2 cousin mean cosine:         ${mean(cousinCosines).toFixed(4)}  target 0.1-0.5 ${g2Pass ? '✓ PASS' : '✗ FAIL'}`);
console.log(`    G3 cross-system mean cosine:   ${mean(crossSysCosines).toFixed(4)}  target < 0.2   ${g3Pass ? '✓ PASS' : '✗ FAIL'}`);

// ── Part 2: Corpus-level ECO clustering ──────────────────────────────────────

console.log('\n══ Part 2: Corpus-level ECO family clustering ═══════════════════════════');
console.log('Encoding all games as HRR...');

interface GameVec {
  eco:    string;
  family: string;
  system: ReturnType<typeof ecoSystem>;
  vec:    Float64Array;
}

const gameVecs: GameVec[] = games
  .filter(g => g.eco.length > 0)
  .map(g => ({
    eco:    g.eco,
    family: ecoFamily(g.eco),
    system: ecoSystem(g.eco),
    vec:    encodePrefix(g.moves),
  }));

console.log(`  Encoded ${gameVecs.length} games with ECO tags.`);

// Group by family
const byFamily = new Map<string, GameVec[]>();
for (const gv of gameVecs) {
  const arr = byFamily.get(gv.family) ?? [];
  arr.push(gv);
  byFamily.set(gv.family, arr);
}

// Show family distribution
console.log('\n  Opening family distribution:');
const famCounts = [...byFamily.entries()].sort((a, b) => b[1].length - a[1].length);
for (const [fam, gvs] of famCounts.slice(0, 12)) {
  console.log(`    ${gvs.length.toString().padStart(4)}  ${fam}`);
}

// Compute intra-family cosines per family (sample up to 50 pairs)
console.log('\n  Intra-family cosines (sample of pairs within same family):');
const intraFamilyCosines: number[] = [];
const familyStats: Array<{ family: string; n: number; mean: number }> = [];

for (const [fam, gvs] of famCounts.slice(0, 10)) {
  if (gvs.length < 4) continue;
  const pairs = samplePairs(gvs, 50);
  const cos = pairs.map(([a, b]) => cosine(a.vec, b.vec));
  const m = mean(cos);
  intraFamilyCosines.push(...cos);
  familyStats.push({ family: fam, n: gvs.length, mean: m });
  console.log(`    n=${gvs.length.toString().padStart(4)}  mean=${m.toFixed(4)}  ${fam}`);
}

// Compute inter-family cosines (pairs across different families)
console.log('\n  Inter-family cosines (sample of pairs across different families):');
const allFamsList = [...byFamily.values()].filter(g => g.length >= 4);
const interFamilyCosines: number[] = [];
for (let i = 0; i < allFamsList.length && i < 8; i++) {
  for (let j = i + 1; j < allFamsList.length && j < 8; j++) {
    const fa = allFamsList[i], fb = allFamsList[j];
    const faN = fa[0].family, fbN = fb[0].family;
    // Sample 20 cross-family pairs
    const pairs = samplePairs(fa, 10).map(([a]) => a);
    const bPairs = samplePairs(fb, 10).map(([b]) => b);
    for (let k = 0; k < Math.min(pairs.length, bPairs.length); k++) {
      interFamilyCosines.push(cosine(pairs[k].vec, bPairs[k].vec));
    }
  }
}
const interMean = mean(interFamilyCosines);
const intraMean = mean(intraFamilyCosines);
console.log(`    Inter-family mean cosine: ${interMean.toFixed(4)}  (n=${interFamilyCosines.length} pairs)`);
console.log(`    Intra-family mean cosine: ${intraMean.toFixed(4)}  (n=${intraFamilyCosines.length} pairs)`);
console.log(`    Separation ratio:         ${(intraMean / interMean).toFixed(2)}×`);
const g4Pass = intraMean > interMean;

// e4 vs d4 system-level stats
const e4Vecs = gameVecs.filter(g => g.system === 'e4');
const d4Vecs = gameVecs.filter(g => g.system === 'd4');
const e4d4Pairs = samplePairs(e4Vecs, 20).map(([a]) => a);
const d4sample  = samplePairs(d4Vecs, 20).map(([b]) => b);
const e4d4Cos: number[] = [];
for (let k = 0; k < Math.min(e4d4Pairs.length, d4sample.length); k++) {
  e4d4Cos.push(cosine(e4d4Pairs[k].vec, d4sample[k].vec));
}
const e4d4Mean = mean(e4d4Cos);
console.log(`\n  e4 system vs d4 system mean cosine: ${e4d4Mean.toFixed(4)}  (should be low)`);

// ── Part 3: Stable prefix analysis ───────────────────────────────────────────

console.log('\n══ Part 3: Pask stability — prefix frequency analysis ═══════════════════');
console.log('Building prefix frequency table...');

const freqMap = new Map<string, number>();
for (const g of games) {
  const seen = new Set<string>();
  for (let i = 1; i <= g.moves.length; i++) {
    const prefix = g.moves.slice(0, i).join(' ');
    if (!seen.has(prefix)) { seen.add(prefix); freqMap.set(prefix, (freqMap.get(prefix) ?? 0) + 1); }
  }
}

const threshold = Math.ceil(games.length * STABLE_PCT / 100);
const stablePrefixes = [...freqMap.entries()]
  .filter(([, n]) => n >= threshold)
  .sort((a, b) => b[1] - a[1]);

console.log(`  Stable threshold: ${threshold} games (${STABLE_PCT}% of ${games.length})`);
console.log(`  Stable prefixes found: ${stablePrefixes.length}`);
console.log('\n  Top 30 stable prefixes by frequency:');

// Annotate with opening name by looking up first game using this prefix
const prefixAnnotations = new Map<string, string>();
for (const g of games) {
  for (let i = 1; i <= g.moves.length; i++) {
    const prefix = g.moves.slice(0, i).join(' ');
    if (!prefixAnnotations.has(prefix) && g.opening) {
      prefixAnnotations.set(prefix, g.opening.split(',')[0].split('(')[0].trim());
    }
  }
}

for (const [prefix, n] of stablePrefixes.slice(0, 30)) {
  const pct = (100 * n / games.length).toFixed(1);
  const ply = prefix.split(' ').length;
  const ann = prefixAnnotations.get(prefix) ?? '';
  console.log(`  n=${n.toString().padStart(4)} (${pct.padStart(4)}%)  ply=${ply}  ${prefix.padEnd(40)}  ${ann}`);
}

// Encode stable prefixes and check sibling clustering
console.log('\n  Sibling stable-prefix cosines (Pask-confirmed + HRR):');
const stableVecs = new Map(
  stablePrefixes.slice(0, 100).map(([p]) => [p, encodePrefix(p.split(' '))])
);

// Find pairs that share a long common prefix
const stableKeys = [...stableVecs.keys()];
const siblingStablePairs: Array<{ a: string; b: string; shared: number; cos: number }> = [];
for (let i = 0; i < stableKeys.length; i++) {
  for (let j = i + 1; j < stableKeys.length; j++) {
    const ma = stableKeys[i].split(' ');
    const mb = stableKeys[j].split(' ');
    let shared = 0;
    for (let k = 0; k < Math.min(ma.length, mb.length); k++) {
      if (ma[k] === mb[k]) shared++; else break;
    }
    const minPly = Math.min(ma.length, mb.length);
    if (shared >= 4 && shared < minPly) { // share most but not all plies
      const c = cosine(stableVecs.get(stableKeys[i])!, stableVecs.get(stableKeys[j])!);
      siblingStablePairs.push({ a: stableKeys[i], b: stableKeys[j], shared, cos: c });
    }
  }
}
siblingStablePairs.sort((a, b) => b.shared - a.shared || b.cos - a.cos);
for (const p of siblingStablePairs.slice(0, 15)) {
  const minPly = Math.min(p.a.split(' ').length, p.b.split(' ').length);
  console.log(`  shared ${p.shared}/${minPly}  cos=${p.cos.toFixed(4)}  [${p.a}] ↔ [${p.b}]`);
}

const stableSiblingMean = siblingStablePairs.length > 0
  ? mean(siblingStablePairs.map(p => p.cos))
  : 0;

// ── Results summary ───────────────────────────────────────────────────────────

console.log('\n══ Gate results ═════════════════════════════════════════════════════════');
console.log(`  G1  Sibling lines (8-9/10 shared):  mean=${mean(siblingCosines).toFixed(4)}  target >0.7   ${g1Pass ? '✓ PASS' : '✗ FAIL'}`);
console.log(`  G2  Cousin pairs (1-4 shared):       mean=${mean(cousinCosines).toFixed(4)}  target 0.1-0.5 ${g2Pass ? '✓ PASS' : '✗ FAIL'}`);
console.log(`  G3  Cross-system (0 shared):          mean=${mean(crossSysCosines).toFixed(4)}  target <0.2   ${g3Pass ? '✓ PASS' : '✗ FAIL'}`);
console.log(`  G4  Intra > inter-family (corpus):   ${intraMean.toFixed(4)} > ${interMean.toFixed(4)}   ${g4Pass ? '✓ PASS' : '✗ FAIL'}`);
const allPass = g1Pass && g2Pass && g3Pass && g4Pass;
console.log(`\n  Overall verdict: ${allPass ? '✓ HRR CLUSTERING VALIDATES ON CHESS DATA' : '✗ SOME GATES FAILED — see above'}`);

// ── Write results markdown ────────────────────────────────────────────────────

const sibRows = NAMED_OPENINGS.flatMap(fam =>
  fam.lines.flatMap((la, i) =>
    fam.lines.slice(i + 1).map(lb => {
      let shared = 0;
      for (let k = 0; k < Math.min(la.moves.length, lb.moves.length); k++) {
        if (la.moves[k] === lb.moves[k]) shared++; else break;
      }
      const c = cosine(encodePrefix(la.moves), encodePrefix(lb.moves));
      return `| sibling | ${fam.family} | ${la.name} ↔ ${lb.name} | ${shared}/${Math.min(la.moves.length, lb.moves.length)} | ${c.toFixed(4)} |`;
    })
  )
);
const cousinRows = COUSIN_PAIRS.map(p => {
  let shared = 0;
  for (let k = 0; k < Math.min(p.a.moves.length, p.b.moves.length); k++) {
    if (p.a.moves[k] === p.b.moves[k]) shared++; else break;
  }
  const c = cosine(encodePrefix(p.a.moves), encodePrefix(p.b.moves));
  return `| cousin | — | ${p.a.name} ↔ ${p.b.name} | ${shared}/${Math.min(p.a.moves.length, p.b.moves.length)} | ${c.toFixed(4)} |`;
});
const crossRows = CROSS_SYSTEM_PAIRS.map(p => {
  const c = cosine(encodePrefix(p.a.moves), encodePrefix(p.b.moves));
  return `| cross-system | — | ${p.a.name} ↔ ${p.b.name} | 0 | ${c.toFixed(4)} |`;
});

const familyStatsRows = familyStats
  .map(s => `| ${s.family} | ${s.n} | ${s.mean.toFixed(4)} |`)
  .join('\n');

const stablePreviewRows = stablePrefixes.slice(0, 20)
  .map(([p, n]) => {
    const pct = (100 * n / games.length).toFixed(1);
    const ann = prefixAnnotations.get(p) ?? '';
    return `| ${p} | ${n} | ${pct}% | ${ann} |`;
  })
  .join('\n');

const md = `# WI-E1 — Chess Opening HRR Clustering Results

**Date run:** ${new Date().toISOString().slice(0, 10)}
**Method:** Plate (1995) circular-convolution HRR, D=1024, CHESS_DOMAIN=42.
**Corpus:** twic1500.pgn — ${games.length} GM games, MAX_PLY=${MAX_PLY}.
**Encoding:** prefix "m1 m2 … mN" → N bindings { role:ply_i, filler:m_i }.

## Part 1: Named opening-pair cosines

| type | family | pair | shared/min_ply | cosine |
|---|---|---|---|---|
${[...sibRows, ...cousinRows, ...crossRows].join('\n')}

## Part 2: ECO family clustering (corpus-level)

| family | games | intra-family mean cosine |
|---|---|---|
${familyStatsRows}

**Intra-family mean:** ${intraMean.toFixed(4)}
**Inter-family mean:** ${interMean.toFixed(4)}
**Separation ratio:** ${(intraMean / interMean).toFixed(2)}×
**e4 vs d4 cross-system mean:** ${e4d4Mean.toFixed(4)}

## Part 3: Top stable prefixes (Pask-stability proxy: freq ≥ ${STABLE_PCT}%)

| prefix | games | % | annotated opening |
|---|---|---|---|
${stablePreviewRows}

**Stable prefixes total:** ${stablePrefixes.length}
**Sibling stable-prefix mean cosine:** ${stableSiblingMean.toFixed(4)}

## Gate results

| gate | description | value | target | result |
|---|---|---|---|---|
| G1 | Sibling lines (share 8-9/10 plies) | ${mean(siblingCosines).toFixed(4)} | > 0.7 | ${g1Pass ? '✓ PASS' : '✗ FAIL'} |
| G2 | Cousin pairs (share 1-4 plies) | ${mean(cousinCosines).toFixed(4)} | 0.1–0.5 | ${g2Pass ? '✓ PASS' : '✗ FAIL'} |
| G3 | Cross-system e4 vs d4 | ${mean(crossSysCosines).toFixed(4)} | < 0.2 | ${g3Pass ? '✓ PASS' : '✗ FAIL'} |
| G4 | Intra-family > inter-family (corpus) | ${intraMean.toFixed(4)} > ${interMean.toFixed(4)} | intra > inter | ${g4Pass ? '✓ PASS' : '✗ FAIL'} |

## Verdict

**${allPass ? '✓ HRR CLUSTERING VALIDATES ON CHESS DATA — structural analogy confirmed on 500-year human-consensus dataset' : '✗ SOME GATES FAILED'}**

## Notes

- Role vectors are seeded by \`(CHESS_DOMAIN, ply_N)\` — same basis for all chess positions.
- Filler vectors are seeded by \`(CHESS_DOMAIN, move)\` — each distinct move is a different filler.
- Two positions sharing K of N plies produce cosine ≈ K/N (for large D, HRR theorem).
- Cross-system pairs (e4 vs d4) share no ply bindings — cosine ≈ 0 by construction.
- The "stable prefix" proxy (frequency ≥ ${STABLE_PCT}%) mimics what the Pask kernel computes via avg|ΔH| < ε.
  The conformance test (core/pask/tests/chess_conformance.zig) confirms these prefixes emerge
  as stable threads when fed as Pask interactions.
- Connection to jural encoding: same encoding scheme as WI-A4, different domain flag.
  If this works for chess, it works for jural structures — both are structured (role, filler) spaces.
`;

writeFileSync(join(here, 'chess-hrr-experiment.results.md'), md);
console.log('\nResults written to research/experiments/chess-hrr-experiment.results.md');

```
