---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/research/experiments/hrr-encoding-feasibility.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.045497+00:00
---

# research/experiments/hrr-encoding-feasibility.ts

```ts
#!/usr/bin/env bun
/**
 * WI-A4 — Empirical HRR encoding feasibility measurement.
 *
 * Plate (1995) circular-convolution HRR, D=1024.
 * Role vectors seeded by (domain_flag, role_name) via SHA-256.
 * Filler vectors seeded by (domain_flag, filler_value) via SHA-256.
 *
 * A "program" is encoded as the L2-normalised sum of (role ⊛ filler)
 * bindings, one per structural slot: category, lexicon, action,
 * trustClass, objectType. This is the minimal feasibility check —
 * if the clustering numbers pass we promote to a real IRProgram encoder
 * in WI-B1.
 *
 * Three measurements (falsification gate for Tier B):
 *   1. Same-category mean cosine     — target > 0.7
 *   2. Cross-category mean cosine    — target < 0.5
 *   3. Cross-domain mean cosine      — target |cos| < 0.1
 *
 * Run:  bun research/experiments/hrr-encoding-feasibility.ts
 *
 * See research/cognition-implementation-plan.md §WI-A4.
 */

import { createHash } from 'crypto';

// ── Constants ─────────────────────────────────────────────────────────────────

const D = 1024; // vector dimensionality (must be power of 2)

// ── Deterministic unit vector seeded by SHA-256 ───────────────────────────────

/**
 * Produce a deterministic unit vector in R^D from `seed`.
 * Uses 128 SHA-256 calls, each producing 8 int32-normalised floats = 1024 total.
 */
function seedVec(seed: string): Float64Array {
  const v = new Float64Array(D);
  const blocksNeeded = D / 8; // 128 blocks
  for (let block = 0; block < blocksNeeded; block++) {
    const h = createHash('sha256').update(`${seed}:${block}`).digest();
    for (let j = 0; j < 8; j++) {
      v[block * 8 + j] = h.readInt32BE(j * 4) / 0x80000000;
    }
  }
  return l2normalize(v);
}

// ── Vector math ───────────────────────────────────────────────────────────────

function dot(a: Float64Array, b: Float64Array): number {
  let s = 0;
  for (let i = 0; i < a.length; i++) s += a[i] * b[i];
  return s;
}

function l2norm(a: Float64Array): number {
  return Math.sqrt(dot(a, a));
}

function l2normalize(a: Float64Array): Float64Array {
  const n = l2norm(a);
  if (n < 1e-15) return a;
  const out = new Float64Array(a.length);
  for (let i = 0; i < a.length; i++) out[i] = a[i] / n;
  return out;
}

function cosine(a: Float64Array, b: Float64Array): number {
  return Math.max(-1, Math.min(1, dot(a, b)));
}

// ── In-place radix-2 DIT FFT ─────────────────────────────────────────────────

/** In-place complex FFT. n must be a power of 2. Operates on separate re/im arrays. */
function fft(re: Float64Array, im: Float64Array): void {
  const n = re.length;
  // bit-reversal permutation
  let j = 0;
  for (let i = 1; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) {
      let tmp = re[i]; re[i] = re[j]; re[j] = tmp;
      tmp = im[i]; im[i] = im[j]; im[j] = tmp;
    }
  }
  // butterfly stages
  for (let len = 2; len <= n; len <<= 1) {
    const ang = (-2 * Math.PI) / len;
    const wRe = Math.cos(ang);
    const wIm = Math.sin(ang);
    for (let i = 0; i < n; i += len) {
      let curRe = 1, curIm = 0;
      const half = len >> 1;
      for (let k = 0; k < half; k++) {
        const uRe = re[i + k];
        const uIm = im[i + k];
        const vRe = re[i + k + half] * curRe - im[i + k + half] * curIm;
        const vIm = re[i + k + half] * curIm + im[i + k + half] * curRe;
        re[i + k] = uRe + vRe;
        im[i + k] = uIm + vIm;
        re[i + k + half] = uRe - vRe;
        im[i + k + half] = uIm - vIm;
        const nRe = curRe * wRe - curIm * wIm;
        curIm = curRe * wIm + curIm * wRe;
        curRe = nRe;
      }
    }
  }
}

/** In-place IFFT via conjugate trick. */
function ifft(re: Float64Array, im: Float64Array): void {
  for (let i = 0; i < im.length; i++) im[i] = -im[i];
  fft(re, im);
  const n = re.length;
  for (let i = 0; i < n; i++) {
    re[i] /= n;
    im[i] = (-im[i]) / n;
  }
}

/** Circular convolution of two real vectors via FFT. */
function circConv(a: Float64Array, b: Float64Array): Float64Array {
  const n = a.length;
  const aRe = new Float64Array(a);
  const aIm = new Float64Array(n);
  const bRe = new Float64Array(b);
  const bIm = new Float64Array(n);
  fft(aRe, aIm);
  fft(bRe, bIm);
  // pointwise complex multiply
  for (let k = 0; k < n; k++) {
    const ar = aRe[k], ai = aIm[k];
    const br = bRe[k], bi = bIm[k];
    aRe[k] = ar * br - ai * bi;
    aIm[k] = ar * bi + ai * br;
  }
  ifft(aRe, aIm);
  return aRe; // real part is the convolution result
}

// ── HRR program encoding ──────────────────────────────────────────────────────

interface Binding {
  role: string;   // slot name (e.g. "category")
  filler: string; // slot value (e.g. "obligation")
  domain: number; // domain_flag — bakes the basis into both role and filler
}

/**
 * Encode a structured program as a single HRR vector.
 * Returns a normalised D-dimensional vector.
 */
function encodeProgram(bindings: Binding[]): Float64Array {
  const sum = new Float64Array(D);
  for (const b of bindings) {
    const rv = seedVec(`${b.domain}:role:${b.role}`);
    const fv = seedVec(`${b.domain}:filler:${b.filler}`);
    const bnd = circConv(rv, fv);
    for (let i = 0; i < D; i++) sum[i] += bnd[i];
  }
  return l2normalize(sum);
}

// ── Program definitions ───────────────────────────────────────────────────────
// Derived from trades-fixtures.ts (domainFlag=7) and scada-fixtures.ts (domainFlag=11).
// 5 bindings per program: category, lexicon, action, trustClass, objectType.
//
// Same-category pairs share all 5 slots except `action` → 4/5 shared.
// Cross-category pairs share `lexicon` + `trustClass` only → 2/5 shared.
// Cross-domain pairs share nothing (domain bakes into role basis) → ~0 shared.

// Helper builders
function tradesMeta(cat: string, action: string, objType: string): Binding[] {
  return [
    { role: 'category',  filler: cat,           domain: 7 },
    { role: 'lexicon',   filler: 'jural',        domain: 7 },
    { role: 'action',    filler: action,          domain: 7 },
    { role: 'trustClass',filler: 'interpretive', domain: 7 },
    { role: 'objectType',filler: objType,         domain: 7 },
  ];
}

function scadaMeta(cat: string, action: string, objType: string): Binding[] {
  return [
    { role: 'category',  filler: cat,             domain: 11 },
    { role: 'lexicon',   filler: 'control-systems',domain: 11 },
    { role: 'action',    filler: action,            domain: 11 },
    { role: 'trustClass',filler: 'authoritative',  domain: 11 },
    { role: 'objectType',filler: objType,           domain: 11 },
  ];
}

// ── Same-category pairs (trades, two categories each with 2 variants) ─────────

const SAME_CAT = [
  {
    label: '(trades, obligation) pair',
    a: { name: 'trades_obligation_reportIssue',  vec: encodeProgram(tradesMeta('obligation', 'report_issue', 'maintenance.job')) },
    b: { name: 'trades_obligation_payInvoice',   vec: encodeProgram(tradesMeta('obligation', 'pay_invoice',  'maintenance.job')) },
  },
  {
    label: '(trades, transfer) pair',
    a: { name: 'trades_transfer_issueInvoice',   vec: encodeProgram(tradesMeta('transfer', 'issue_invoice', 'maintenance.invoice')) },
    b: { name: 'trades_transfer_payInvoice',     vec: encodeProgram(tradesMeta('transfer', 'pay_invoice',   'maintenance.invoice')) },
  },
  {
    label: '(scada, actuation) pair',
    a: { name: 'scada_actuation_openValve',      vec: encodeProgram(scadaMeta('actuation', 'open_valve',  'scada.equipment')) },
    b: { name: 'scada_actuation_closeValve',     vec: encodeProgram(scadaMeta('actuation', 'close_valve', 'scada.equipment')) },
  },
  {
    label: '(scada, measurement) pair',
    a: { name: 'scada_measurement_readTank',     vec: encodeProgram(scadaMeta('measurement', 'read_measurement',  'scada.equipment')) },
    b: { name: 'scada_measurement_calibrate',    vec: encodeProgram(scadaMeta('measurement', 'calibrate_sensor', 'scada.equipment')) },
  },
];

// ── Cross-category pairs (same domain, different category + objectType) ────────

const CROSS_CAT = [
  {
    label: '(trades, obligation) vs (trades, transfer)',
    a: { name: 'trades_obligation', vec: encodeProgram(tradesMeta('obligation', 'report_issue', 'maintenance.job')) },
    b: { name: 'trades_transfer',   vec: encodeProgram(tradesMeta('transfer',   'issue_invoice','maintenance.invoice')) },
  },
  {
    label: '(trades, obligation) vs (trades, declaration)',
    a: { name: 'trades_obligation',  vec: encodeProgram(tradesMeta('obligation',  'report_issue', 'maintenance.job')) },
    b: { name: 'trades_declaration', vec: encodeProgram(tradesMeta('declaration', 'request_quote','maintenance.quote')) },
  },
  {
    label: '(trades, obligation) vs (trades, power)',
    a: { name: 'trades_obligation', vec: encodeProgram(tradesMeta('obligation', 'report_issue',  'maintenance.job')) },
    b: { name: 'trades_power',      vec: encodeProgram(tradesMeta('power',      'approve_quote', 'maintenance.quote')) },
  },
  {
    label: '(scada, actuation) vs (scada, measurement)',
    a: { name: 'scada_actuation',   vec: encodeProgram(scadaMeta('actuation',   'open_valve',         'scada.equipment')) },
    b: { name: 'scada_measurement', vec: encodeProgram(scadaMeta('measurement', 'read_measurement',   'scada.equipment')) },
  },
  {
    label: '(scada, interlock) vs (scada, alarm)',
    a: { name: 'scada_interlock', vec: encodeProgram(scadaMeta('interlock', 'engage_interlock', 'scada.interlock')) },
    b: { name: 'scada_alarm',     vec: encodeProgram(scadaMeta('alarm',     'raise_alarm',      'scada.alarm')) },
  },
];

// ── Cross-domain pairs (trades vs SCADA) ──────────────────────────────────────

const CROSS_DOMAIN = [
  {
    label: '(trades, obligation) vs (scada, actuation)',
    a: { name: 'trades_obligation', vec: encodeProgram(tradesMeta('obligation', 'report_issue',  'maintenance.job')) },
    b: { name: 'scada_actuation',   vec: encodeProgram(scadaMeta('actuation',   'open_valve',    'scada.equipment')) },
  },
  {
    label: '(trades, transfer) vs (scada, measurement)',
    a: { name: 'trades_transfer',   vec: encodeProgram(tradesMeta('transfer',   'issue_invoice', 'maintenance.invoice')) },
    b: { name: 'scada_measurement', vec: encodeProgram(scadaMeta('measurement', 'read_measurement','scada.equipment')) },
  },
  {
    label: '(trades, power) vs (scada, interlock)',
    a: { name: 'trades_power',    vec: encodeProgram(tradesMeta('power',    'approve_quote',   'maintenance.quote')) },
    b: { name: 'scada_interlock', vec: encodeProgram(scadaMeta('interlock', 'engage_interlock','scada.interlock')) },
  },
  {
    label: '(trades, declaration) vs (scada, alarm)',
    a: { name: 'trades_declaration', vec: encodeProgram(tradesMeta('declaration', 'request_quote', 'maintenance.quote')) },
    b: { name: 'scada_alarm',        vec: encodeProgram(scadaMeta('alarm',        'raise_alarm',   'scada.alarm')) },
  },
  {
    label: '(trades, condition) vs (scada, acknowledgement)',
    a: { name: 'trades_condition',      vec: encodeProgram(tradesMeta('condition',      'schedule_visit',   'maintenance.visit')) },
    b: { name: 'scada_acknowledgement', vec: encodeProgram(scadaMeta('acknowledgement', 'acknowledge_alarm','scada.alarm')) },
  },
];

// ── Measurement ───────────────────────────────────────────────────────────────

function mean(xs: number[]): number {
  return xs.reduce((s, x) => s + x, 0) / xs.length;
}

function absMean(xs: number[]): number {
  return mean(xs.map(Math.abs));
}

function measureGroup(
  label: string,
  pairs: Array<{ label: string; a: { name: string; vec: Float64Array }; b: { name: string; vec: Float64Array } }>,
): number[] {
  console.log(`\n── ${label} ─────────────────────────────────────────────────`);
  const cosines: number[] = [];
  for (const p of pairs) {
    const c = cosine(p.a.vec, p.b.vec);
    cosines.push(c);
    console.log(`  ${p.label}`);
    console.log(`    ${p.a.name} ↔ ${p.b.name}  cos = ${c.toFixed(4)}`);
  }
  return cosines;
}

// ── Main ──────────────────────────────────────────────────────────────────────

console.log('WI-A4 — HRR encoding feasibility (D=1024, Plate circular convolution)');
console.log(`  domain flags: trades=7, scada=11`);
console.log(`  5 bindings/program: category, lexicon, action, trustClass, objectType`);
console.log(`  same-category pairs share 4/5 bindings; cross-cat 2/5; cross-domain 0`);

const sameCatCosines   = measureGroup('1. Same-category pairs',   SAME_CAT);
const crossCatCosines  = measureGroup('2. Cross-category pairs',  CROSS_CAT);
const crossDomCosines  = measureGroup('3. Cross-domain pairs',    CROSS_DOMAIN);

const sameMean   = mean(sameCatCosines);
const crossMean  = mean(crossCatCosines);
const crossDomMean = absMean(crossDomCosines);

const PASS_SAME  = sameMean > 0.7;
const PASS_CROSS = crossMean < 0.5;
const PASS_DOM   = crossDomMean < 0.1;

console.log('\n══ Results ══════════════════════════════════════════════════════');
console.log(`  1. Same-category mean cosine:   ${sameMean.toFixed(4)}  target > 0.7   ${PASS_SAME  ? '✓ PASS' : '✗ FAIL'}`);
console.log(`  2. Cross-category mean cosine:  ${crossMean.toFixed(4)}  target < 0.5   ${PASS_CROSS ? '✓ PASS' : '✗ FAIL'}`);
console.log(`  3. Cross-domain mean |cosine|:  ${crossDomMean.toFixed(4)}  target < 0.1   ${PASS_DOM   ? '✓ PASS' : '✗ FAIL'}`);

const allPass = PASS_SAME && PASS_CROSS && PASS_DOM;
console.log(`\n  Gate verdict: ${allPass ? '✓ TIER B UNBLOCKED' : '✗ REDESIGN REQUIRED — tier B blocked'}`);

// Write the results markdown
import { writeFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const here = dirname(fileURLToPath(import.meta.url));

const allPairs = [
  ...SAME_CAT.map(p => ({ group: 'same-category', ...p })),
  ...CROSS_CAT.map(p => ({ group: 'cross-category', ...p })),
  ...CROSS_DOMAIN.map(p => ({ group: 'cross-domain', ...p })),
];

const tableRows = allPairs
  .map(p => {
    const c = cosine(p.a.vec, p.b.vec);
    return `| ${p.group} | ${p.a.name} | ${p.b.name} | ${c.toFixed(4)} |`;
  })
  .join('\n');

const md = `# WI-A4 — HRR Encoding Feasibility Results

**Date run:** ${new Date().toISOString().slice(0, 10)}
**Method:** Plate (1995) circular-convolution HRR, D=1024.
Role vectors seeded by \`(domain_flag, role_name)\` via SHA-256.
Filler vectors seeded by \`(domain_flag, filler_value)\` via SHA-256.
5 structural bindings per program: \`category\`, \`lexicon\`, \`action\`, \`trustClass\`, \`objectType\`.

## Measurements

| group | program A | program B | cosine |
|---|---|---|---|
${tableRows}

## Summary

| measurement | value | target | result |
|---|---|---|---|
| Same-category mean cosine | ${sameMean.toFixed(4)} | > 0.7 | ${PASS_SAME ? '✓ PASS' : '✗ FAIL'} |
| Cross-category mean cosine | ${crossMean.toFixed(4)} | < 0.5 | ${PASS_CROSS ? '✓ PASS' : '✗ FAIL'} |
| Cross-domain mean \|cosine\| | ${crossDomMean.toFixed(4)} | < 0.1 | ${PASS_DOM ? '✓ PASS' : '✗ FAIL'} |

## Gate verdict

**${allPass ? '✓ Tier B UNBLOCKED — promote to production encoder in WI-B1' : '✗ REDESIGN REQUIRED — tier B blocked until redesign produces these numbers'}**

## Notes

- Same-category programs share 4/5 structural slots (differ only in \`action\`).
- Cross-category programs share 2/5 slots (\`lexicon\` + \`trustClass\`; differ in \`category\`, \`action\`, \`objectType\`).
- Cross-domain programs have orthogonal role-vector bases by construction (domain flag baked into SHA-256 seed), so cosine ≈ 0 regardless of structural overlap.
- Domain flags: trades=7, SCADA=11 (from fixture grammar stubs).
- Vocabulary source: \`runtime/intent/src/reducer/__fixtures__/trades-fixtures.ts\` and \`scada-fixtures.ts\`.
`;

writeFileSync(join(here, 'hrr-encoding-feasibility.results.md'), md);
console.log('\nResults written to research/experiments/hrr-encoding-feasibility.results.md');

```
