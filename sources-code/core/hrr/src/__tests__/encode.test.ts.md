---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/hrr/src/__tests__/encode.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.022832+00:00
---

# core/hrr/src/__tests__/encode.test.ts

```ts
/**
 * WI-B1 encode tests.
 *
 * Four RED→GREEN tests per the implementation plan:
 *   WI-B1-T-encode-deterministic
 *   WI-B1-T-bind-unbind-roundtrip
 *   WI-B1-T-orthogonal-basis-across-domains
 *   WI-B1-T-fixture-cosines  (re-runs WI-A4 measurements as assertions)
 */

import { describe, it, expect } from 'bun:test';
import type { IRProgram } from '@semantos/semantos-ir';
import { encodeSIRProgram, bind, unbind, cosine, D } from '../encode';
import { roleVec, fillerVec, l2norm } from '../role-vectors';

// ── Fixtures (structured metadata from trades + SCADA grammar stubs) ──────────

/** Build an IRProgram from the structural metadata the reducer would produce. */
function makeProgram(
  kinds: string[],
  ops?: string[],
  fields?: string[],
): IRProgram {
  return {
    bindings: kinds.map((kind, i) => ({
      name: `$${i}`,
      kind: kind as IRProgram['bindings'][number]['kind'],
      op: ops?.[i],
      field: fields?.[i],
    })),
    result: `$${kinds.length - 1}`,
  };
}

// Trades domain programs (flag=7)
const tradesDomain = 7;
const scadaDomain = 11;

// Same-category pair: both are (obligation, comparison) programs differing only in field
const obligationA: IRProgram = makeProgram(['comparison', 'comparison'], ['>=', '<='], ['amount', 'amount']);
const obligationB: IRProgram = makeProgram(['comparison', 'comparison'], ['>=', '<='], ['amount', 'due_date']);

// Cross-category: obligation (comparison) vs transfer (capability)
const transferA: IRProgram = {
  bindings: [
    { name: '$0', kind: 'capability', capabilityNumber: 2 },
    { name: '$1', kind: 'comparison', op: '>=', field: 'amount' },
  ],
  result: '$1',
};

// Cross-domain: SCADA (flag=11) — interlock + comparison
const scadaA: IRProgram = {
  bindings: [
    { name: '$0', kind: 'comparison', op: '>', field: 'pressure' },
    { name: '$1', kind: 'domainCheck', domainFlag: 11 },
  ],
  result: '$1',
};

// ── WI-B1-T-encode-deterministic ─────────────────────────────────────────────

describe('WI-B1-T-encode-deterministic', () => {
  it('same program and domainFlag always produces the same vector', () => {
    const v1 = encodeSIRProgram(obligationA, tradesDomain);
    const v2 = encodeSIRProgram(obligationA, tradesDomain);
    expect(v1.length).toBe(D);
    // Exact equality: every element must match
    for (let i = 0; i < D; i++) {
      expect(v1[i]).toBe(v2[i]);
    }
  });

  it('result is a unit vector (L2 norm ≈ 1)', () => {
    const v = encodeSIRProgram(obligationA, tradesDomain);
    expect(Math.abs(l2norm(v) - 1)).toBeLessThan(1e-9);
  });

  it('different domain flag produces a different vector for the same program', () => {
    const vTrades = encodeSIRProgram(obligationA, tradesDomain);
    const vScada  = encodeSIRProgram(obligationA, scadaDomain);
    // Should not be equal
    let allEqual = true;
    for (let i = 0; i < D; i++) {
      if (vTrades[i] !== vScada[i]) { allEqual = false; break; }
    }
    expect(allEqual).toBe(false);
  });

  it('empty program encodes to zero vector (no bindings)', () => {
    const empty: IRProgram = { bindings: [], result: '' };
    const v = encodeSIRProgram(empty, tradesDomain);
    // Only the domain anchor binding is present → unit vector, not all-zeros
    expect(l2norm(v)).toBeCloseTo(1, 9);
  });
});

// ── WI-B1-T-bind-unbind-roundtrip ────────────────────────────────────────────

describe('WI-B1-T-bind-unbind-roundtrip', () => {
  it('unbind(bind(r, f), r) recovers f with cosine > 0.9', () => {
    const r = roleVec(tradesDomain, 'category');
    const f = fillerVec(tradesDomain, 'obligation');
    const bound = bind(r, f);
    const recovered = unbind(bound, r);

    // Recovered vector should be similar to f
    const sim = cosine(
      new Float64Array(recovered),
      f,
    );
    // HRR noise budget for D=1024, single binding: expected cosine ≈ 1.0
    expect(sim).toBeGreaterThan(0.9);
  });

  it('unbind with wrong role key gives low similarity to filler', () => {
    const r = roleVec(tradesDomain, 'category');
    const rWrong = roleVec(tradesDomain, 'lexicon');
    const f = fillerVec(tradesDomain, 'obligation');
    const bound = bind(r, f);
    const recovered = unbind(bound, rWrong);
    const sim = cosine(new Float64Array(recovered), f);
    expect(Math.abs(sim)).toBeLessThan(0.15);
  });

  it('result of bind is approximately unit-length', () => {
    const r = roleVec(tradesDomain, 'action');
    const f = fillerVec(tradesDomain, 'pay_invoice');
    const bound = bind(r, f);
    expect(Math.abs(l2norm(bound) - 1)).toBeLessThan(0.05);
  });
});

// ── WI-B1-T-orthogonal-basis-across-domains ───────────────────────────────────

describe('WI-B1-T-orthogonal-basis-across-domains', () => {
  it('roleVec("category") is near-orthogonal across domain flags', () => {
    const r7  = roleVec(7,  'category');
    const r11 = roleVec(11, 'category');
    expect(Math.abs(cosine(r7, r11))).toBeLessThan(0.15);
  });

  it('fillerVec("obligation") is near-orthogonal across domain flags', () => {
    const f7  = fillerVec(7,  'obligation');
    const f11 = fillerVec(11, 'obligation');
    expect(Math.abs(cosine(f7, f11))).toBeLessThan(0.15);
  });

  it('encoded programs from different domains are near-orthogonal', () => {
    const vTrades = encodeSIRProgram(obligationA, tradesDomain);
    const vScada  = encodeSIRProgram(scadaA,      scadaDomain);
    expect(Math.abs(cosine(vTrades, vScada))).toBeLessThan(0.15);
  });

  it('role vectors for distinct role names in same domain are near-orthogonal', () => {
    const rCat = roleVec(tradesDomain, 'category');
    const rLex = roleVec(tradesDomain, 'lexicon');
    expect(Math.abs(cosine(rCat, rLex))).toBeLessThan(0.15);
  });
});

// ── WI-B1-T-fixture-cosines ───────────────────────────────────────────────────
//
// Re-runs WI-A4's three measurements as unit tests with explicit assertions.
// Uses IRProgram-level encodings rather than raw metadata structs to prove
// the production encoder (not just the experiment script) produces the right
// clustering.
//
// Programs are built from the trades/SCADA grammar stub vocabulary; they
// mirror what the reducer would produce for the fixture inputs.

describe('WI-B1-T-fixture-cosines', () => {
  // -- Same-category programs: share kind + op + field, differ in field value only
  const sameCatPairs: Array<{ label: string; a: IRProgram; b: IRProgram; domain: number }> = [
    {
      label: 'trades obligation: amount comparison vs amount+date comparison',
      a: makeProgram(['comparison', 'logical_and'], ['>='], ['amount']),
      b: makeProgram(['comparison', 'logical_and'], ['<='], ['amount']),
      domain: tradesDomain,
    },
    {
      label: 'trades transfer: two capability+comparison programs',
      a: { bindings: [{ name: '$0', kind: 'capability', capabilityNumber: 2 }, { name: '$1', kind: 'comparison', op: '>=', field: 'amount' }], result: '$1' },
      b: { bindings: [{ name: '$0', kind: 'capability', capabilityNumber: 2 }, { name: '$1', kind: 'comparison', op: '<=', field: 'amount' }], result: '$1' },
      domain: tradesDomain,
    },
    {
      label: 'scada actuation: two domainCheck+comparison programs',
      a: { bindings: [{ name: '$0', kind: 'domainCheck', domainFlag: 11 }, { name: '$1', kind: 'comparison', op: '>', field: 'pressure' }], result: '$1' },
      b: { bindings: [{ name: '$0', kind: 'domainCheck', domainFlag: 11 }, { name: '$1', kind: 'comparison', op: '<', field: 'pressure' }], result: '$1' },
      domain: scadaDomain,
    },
  ];

  it('same-category mean cosine > 0.7', () => {
    const cosines = sameCatPairs.map(p =>
      cosine(encodeSIRProgram(p.a, p.domain), encodeSIRProgram(p.b, p.domain)),
    );
    const mean = cosines.reduce((s, c) => s + c, 0) / cosines.length;
    expect(mean).toBeGreaterThan(0.7);
  });

  // -- Cross-category: same domain, different kind profile
  const crossCatPairs: Array<{ label: string; a: IRProgram; b: IRProgram; domain: number }> = [
    {
      label: 'trades: comparison-heavy vs capability-heavy',
      a: makeProgram(['comparison', 'comparison', 'logical_and'], ['>=', '<='], ['amount', 'due_date']),
      b: { bindings: [{ name: '$0', kind: 'capability', capabilityNumber: 3 }, { name: '$1', kind: 'capability', capabilityNumber: 4 }, { name: '$2', kind: 'logical_and', operands: ['$0', '$1'] }], result: '$2' },
      domain: tradesDomain,
    },
    {
      label: 'trades: comparison vs timeConstraint',
      a: makeProgram(['comparison'], ['>='], ['amount']),
      b: { bindings: [{ name: '$0', kind: 'timeConstraint', timeOp: 'timeAfter', timestamp: 1000000 }], result: '$0' },
      domain: tradesDomain,
    },
    {
      label: 'scada: domainCheck vs timeConstraint',
      a: { bindings: [{ name: '$0', kind: 'domainCheck', domainFlag: 11 }, { name: '$1', kind: 'comparison', op: '>', field: 'temp' }], result: '$1' },
      b: { bindings: [{ name: '$0', kind: 'timeConstraint', timeOp: 'timeBefore', timestamp: 2000000 }, { name: '$1', kind: 'comparison', op: '<', field: 'flow' }], result: '$1' },
      domain: scadaDomain,
    },
  ];

  it('cross-category mean cosine < 0.5', () => {
    const cosines = crossCatPairs.map(p =>
      cosine(encodeSIRProgram(p.a, p.domain), encodeSIRProgram(p.b, p.domain)),
    );
    const mean = cosines.reduce((s, c) => s + c, 0) / cosines.length;
    expect(mean).toBeLessThan(0.5);
  });

  // -- Cross-domain: trades programs vs SCADA programs
  const crossDomainPairs: Array<{ label: string; a: IRProgram; b: IRProgram }> = [
    {
      label: 'trades comparison vs scada comparison',
      a: makeProgram(['comparison'], ['>='], ['amount']),
      b: makeProgram(['comparison'], ['>'],  ['pressure']),
    },
    {
      label: 'trades capability vs scada domainCheck',
      a: { bindings: [{ name: '$0', kind: 'capability', capabilityNumber: 2 }], result: '$0' },
      b: { bindings: [{ name: '$0', kind: 'domainCheck', domainFlag: 11 }],    result: '$0' },
    },
    {
      label: 'trades timeConstraint vs scada timeConstraint',
      a: { bindings: [{ name: '$0', kind: 'timeConstraint', timeOp: 'timeAfter',  timestamp: 1000 }], result: '$0' },
      b: { bindings: [{ name: '$0', kind: 'timeConstraint', timeOp: 'timeBefore', timestamp: 1000 }], result: '$0' },
    },
  ];

  it('cross-domain mean |cosine| < 0.1', () => {
    const cosines = crossDomainPairs.map(p =>
      cosine(encodeSIRProgram(p.a, tradesDomain), encodeSIRProgram(p.b, scadaDomain)),
    );
    const meanAbs = cosines.reduce((s, c) => s + Math.abs(c), 0) / cosines.length;
    expect(meanAbs).toBeLessThan(0.1);
  });
});

```
