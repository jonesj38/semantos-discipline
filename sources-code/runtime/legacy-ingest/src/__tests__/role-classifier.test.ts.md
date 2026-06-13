---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/role-classifier.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.144270+00:00
---

# runtime/legacy-ingest/src/__tests__/role-classifier.test.ts

```ts
/**
 * D-RTC.2 — role-classifier conformance tests.
 *
 * Reference: docs/prd/D-Reingest-Typed-Cells.md §Deliverables / D-RTC.2.
 *
 * Acceptance gate: 50 representative email contexts; classifier hits
 * ≥80% precision per role with `unknown` rate ≤15%.
 *
 * Cases pulled from OJT-realistic email shapes: Clever Property / RJR /
 * Bricks PM emails, gmail tenants and owners, plumber/electrician
 * contractors, witnesses on incident reports.
 */

import { describe, test, expect } from 'bun:test';
import {
  classifyRole,
  classifyRoleHeuristic,
  type ClassifyArgs,
  type ClassifyResult,
  type ContactRole,
  type RoleLLMFallback,
} from '../role-classifier';

/* ──────────────────────────────────────────────────────────────────────
 * Labelled corpus — 50 cases
 * ────────────────────────────────────────────────────────────────────── */

interface LabelledCase {
  readonly label: string;
  readonly expected: ContactRole;
  readonly args: ClassifyArgs;
}

const CORPUS: readonly LabelledCase[] = [
  // ── property_manager (10) ──────────────────────────────────────────
  {
    label: 'PM: Clever Property signature',
    expected: 'property_manager',
    args: {
      name: 'Anna Smith',
      email: 'anna@cleverproperty.com.au',
      signatureBlock: 'Anna Smith\nProperty Manager\nClever Property',
    },
  },
  {
    label: 'PM: Ray White leasing consultant',
    expected: 'property_manager',
    args: {
      name: 'Lisa Chen',
      email: 'lisa.chen@raywhite.com.au',
      signatureBlock: 'Lisa Chen\nLeasing Consultant\nRay White Brisbane',
    },
  },
  {
    label: 'PM: Harcourts senior PM',
    expected: 'property_manager',
    args: {
      name: 'Mark Davies',
      email: 'mark@harcourts.com.au',
      signatureBlock: 'Mark Davies\nSenior PM | Harcourts',
    },
  },
  {
    label: 'PM: McGrath property manager',
    expected: 'property_manager',
    args: {
      email: 'pm@mcgrath.com.au',
      signatureBlock: 'Property Manager - Northern Beaches',
    },
  },
  {
    label: 'PM: domain only',
    expected: 'property_manager',
    args: { email: 'lettings@cleverproperty.com.au' },
  },
  {
    label: 'PM: LJ Hooker',
    expected: 'property_manager',
    args: {
      email: 'office@ljhooker.com.au',
      signatureBlock: 'Property Manager\nLJ Hooker',
    },
  },
  {
    label: 'PM: Belle Property',
    expected: 'property_manager',
    args: {
      email: 'leasing@belleproperty.com',
      signatureBlock: 'Leasing Manager',
    },
  },
  {
    label: 'PM: mentioned in body',
    expected: 'property_manager',
    args: {
      email: 'sender@cleverproperty.com.au',
      bodyContext: 'Your property manager will be in touch.',
    },
  },
  {
    label: 'PM: PM domain weak + signature strong',
    expected: 'property_manager',
    args: {
      email: 'team@cleverproperty.com.au',
      name: 'Anna',
      signatureBlock: 'Anna - Property Manager',
    },
  },
  {
    label: 'PM: leasing consultant in sig',
    expected: 'property_manager',
    args: {
      email: 'gen@example.com',
      signatureBlock: 'Sarah Lim\nLeasing Consultant',
    },
  },

  // ── agent (8) ──────────────────────────────────────────────────────
  {
    label: 'agent: RJR domain + on behalf body',
    expected: 'agent',
    args: {
      email: 'admin@robertjamesrealty.com.au',
      bodyContext: 'Issued on behalf of the owner.',
    },
  },
  {
    label: 'agent: real estate agent signature',
    expected: 'agent',
    args: {
      email: 'tony@example.com.au',
      signatureBlock: 'Tony Briggs\nReal Estate Agent\nIndependent',
    },
  },
  {
    label: 'agent: principal',
    expected: 'agent',
    args: {
      email: 'principal@boutique-re.com',
      signatureBlock: 'Mary Hopkins\nPrincipal | Boutique Real Estate',
    },
  },
  {
    label: 'agent: sales associate',
    expected: 'agent',
    args: {
      email: 'jake@bayside-realty.com.au',
      signatureBlock: 'Jake Howard\nSales Associate',
    },
  },
  {
    label: 'agent: .realty domain',
    expected: 'agent',
    args: { email: 'enquiries@stellar.realty' },
  },
  {
    label: 'agent: realestate.com.au',
    expected: 'agent',
    args: {
      email: 'agent@coastal-realestate.com.au',
      signatureBlock: 'Real Estate Agent',
    },
  },
  {
    label: 'agent: RJR mentioned in body',
    expected: 'agent',
    args: {
      email: 'office@robertjamesrealty.com.au',
      bodyContext: 'On behalf of the owner — please attend.',
    },
  },
  {
    label: 'agent: sales consultant only',
    expected: 'agent',
    args: { email: 'rep@example.com', signatureBlock: 'Sales Consultant — Boutique RE' },
  },

  // ── site_owner (8) ─────────────────────────────────────────────────
  {
    label: 'owner: I am the owner',
    expected: 'site_owner',
    args: {
      email: 'john@gmail.com',
      bodyContext: "I'm the owner of the property at 10 List Lane.",
    },
  },
  {
    label: 'owner: I am the landlord',
    expected: 'site_owner',
    args: {
      email: 'sue@hotmail.com',
      bodyContext: "I am the landlord. Please send the invoice to me.",
    },
  },
  {
    label: 'owner: signature says Landlord',
    expected: 'site_owner',
    args: {
      email: 'jane@bigpond.com',
      signatureBlock: 'Jane Wilson\nLandlord — 15 Pine St',
    },
  },
  {
    label: 'owner: investor in sig',
    expected: 'site_owner',
    args: {
      email: 'mike@gmail.com',
      signatureBlock: 'Mike Hopkins\nInvestor / Owner',
    },
  },
  {
    label: 'owner: the owner has requested',
    expected: 'site_owner',
    args: {
      email: 'someone@example.com',
      bodyContext: 'The owner has requested a quote for the roofing repair.',
    },
  },
  {
    label: 'owner: explicit landlord declaration',
    expected: 'site_owner',
    args: {
      email: 'kev@yahoo.com.au',
      bodyContext: "I'm the landlord of unit 3.",
    },
  },
  {
    label: 'owner: bigpond + signature',
    expected: 'site_owner',
    args: {
      email: 'cynthia@bigpond.net.au',
      signatureBlock: 'Cynthia\nLandlord',
    },
  },
  {
    label: 'owner: gmail + body owner mention',
    expected: 'site_owner',
    args: {
      email: 'paul@gmail.com',
      bodyContext: 'As the owner I want the quote in writing first.',
      signatureBlock: 'Paul',
    },
  },

  // ── tenant (8) ─────────────────────────────────────────────────────
  {
    label: 'tenant: I am the tenant',
    expected: 'tenant',
    args: {
      email: 'sara@gmail.com',
      bodyContext: "I'm the tenant at 12 Oak Road. The hot water is broken.",
    },
  },
  {
    label: 'tenant: signature Tenant',
    expected: 'tenant',
    args: {
      email: 'dave@hotmail.com',
      signatureBlock: 'Dave\nTenant — Unit 4',
    },
  },
  {
    label: 'tenant: gmail + tenant body (3p)',
    expected: 'tenant',
    args: {
      email: 'someone@gmail.com',
      bodyContext: 'The tenant has reported a leak in the bathroom.',
    },
  },
  {
    label: 'tenant: outlook + signature',
    expected: 'tenant',
    args: {
      email: 'sarah@outlook.com',
      signatureBlock: 'Sarah\nTenant of unit 2',
    },
  },
  {
    label: 'tenant: bigpond personal address',
    expected: 'tenant',
    args: {
      email: 'phil@bigpond.com',
      bodyContext: "I'm the tenant. When can you come?",
    },
  },
  {
    label: 'tenant: tenant called',
    expected: 'tenant',
    args: {
      email: 'unknown@example.com',
      bodyContext: 'The tenant called twice today about the toilet.',
    },
  },
  {
    label: 'tenant: tenant advised',
    expected: 'tenant',
    args: {
      email: 'jen@gmail.com',
      bodyContext: 'The tenant advised water leaking from ceiling.',
    },
  },
  {
    label: 'tenant: yahoo personal',
    expected: 'tenant',
    args: {
      email: 'kris@yahoo.com.au',
      bodyContext: "I'm the tenant at 8 Maple Lane.",
    },
  },

  // ── contractor (6) ─────────────────────────────────────────────────
  {
    label: 'contractor: plumbing domain',
    expected: 'contractor',
    args: {
      email: 'jobs@brisbane-plumbing.com.au',
      signatureBlock: 'Brisbane Plumbing\n24/7 Service',
    },
  },
  {
    label: 'contractor: electrician sig',
    expected: 'contractor',
    args: {
      email: 'mike@example.com',
      signatureBlock: 'Mike Wilson\nElectrician',
    },
  },
  {
    label: 'contractor: tradie signature',
    expected: 'contractor',
    args: {
      email: 'pete@example.com',
      signatureBlock: 'Pete the Tradie',
    },
  },
  {
    label: 'contractor: construction domain',
    expected: 'contractor',
    args: {
      email: 'office@apex-construction.com.au',
      signatureBlock: 'Project Manager',
    },
  },
  {
    label: 'contractor: builder sig',
    expected: 'contractor',
    args: {
      email: 'tom@gmail.com',
      signatureBlock: 'Tom Stevens\nLicensed Builder QBCC 12345',
    },
  },
  {
    label: 'contractor: roofing domain',
    expected: 'contractor',
    args: {
      email: 'admin@brisbane-roofing.com.au',
      signatureBlock: 'Brisbane Roofing — Estimating',
    },
  },

  // ── witness (3) ────────────────────────────────────────────────────
  {
    label: 'witness: I am a witness',
    expected: 'witness',
    args: {
      email: 'neighbour@gmail.com',
      bodyContext: "I'm a witness to the incident that occurred.",
    },
  },
  {
    label: 'witness: as a witness',
    expected: 'witness',
    args: {
      email: 'bob@gmail.com',
      bodyContext: 'As a witness I can confirm what happened.',
    },
  },
  {
    label: 'witness: as the witness',
    expected: 'witness',
    args: {
      email: 'maria@gmail.com',
      bodyContext: 'I attended the property as the witness on 12 March.',
    },
  },

  // ── unknown (7) — ambiguous / no signal ────────────────────────────
  {
    label: 'unknown: no signal at all',
    expected: 'unknown',
    args: { name: 'someone' },
  },
  {
    label: 'unknown: empty args',
    expected: 'unknown',
    args: {},
  },
  {
    label: 'unknown: business domain, no role context',
    expected: 'unknown',
    args: { email: 'enquiries@somefirm.com.au' },
  },
  {
    label: 'unknown: gmail with no body context',
    expected: 'unknown',
    args: { email: 'random@gmail.com' },
  },
  {
    label: 'unknown: empty signature',
    expected: 'unknown',
    args: { email: 'someone@example.com', signatureBlock: '' },
  },
  {
    label: 'unknown: hello in body',
    expected: 'unknown',
    args: {
      email: 'someone@example.com',
      bodyContext: 'Hello, please send me an update on the schedule.',
    },
  },
  {
    label: 'unknown: signature with no role keywords',
    expected: 'unknown',
    args: {
      email: 'staff@example.com',
      signatureBlock: 'Best regards,\nStaff Member',
    },
  },
];

/* ──────────────────────────────────────────────────────────────────────
 * Corpus-level acceptance gate
 * ────────────────────────────────────────────────────────────────────── */

describe('classifier: PRD acceptance gate (50-case corpus)', () => {
  test('corpus is at least 50 cases', () => {
    expect(CORPUS.length).toBeGreaterThanOrEqual(50);
  });

  test('≥80% precision per role; ≤15% unknown-rate on labelled non-unknown cases', () => {
    type Tally = { hits: number; classified: number; total: number };
    const perRole: Record<ContactRole, Tally> = {
      site_owner: { hits: 0, classified: 0, total: 0 },
      tenant: { hits: 0, classified: 0, total: 0 },
      property_manager: { hits: 0, classified: 0, total: 0 },
      agent: { hits: 0, classified: 0, total: 0 },
      contractor: { hits: 0, classified: 0, total: 0 },
      witness: { hits: 0, classified: 0, total: 0 },
      unknown: { hits: 0, classified: 0, total: 0 },
    };
    let unknownReturned = 0;
    let labelledNonUnknown = 0;

    for (const c of CORPUS) {
      const r = classifyRoleHeuristic(c.args);
      perRole[c.expected].total += 1;
      if (r.role === c.expected) perRole[c.expected].hits += 1;
      if (r.role !== 'unknown') {
        perRole[r.role].classified += 1;
      }
      if (c.expected !== 'unknown') {
        labelledNonUnknown += 1;
        if (r.role === 'unknown') unknownReturned += 1;
      }
    }

    // Per-role precision (hits / classified-as-that-role).
    for (const role of Object.keys(perRole) as ContactRole[]) {
      if (role === 'unknown') continue;
      const { hits, classified } = perRole[role];
      if (classified === 0) continue; // no claims made for this role
      const precision = hits / classified;
      expect(precision).toBeGreaterThanOrEqual(0.8);
    }

    // Unknown rate on labelled-non-unknown cases.
    const unknownRate = labelledNonUnknown === 0 ? 0 : unknownReturned / labelledNonUnknown;
    expect(unknownRate).toBeLessThanOrEqual(0.15);
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * Per-case spot checks (key shapes)
 * ────────────────────────────────────────────────────────────────────── */

describe('classifier: spot checks on key shapes', () => {
  test('domain alone is enough for known PM platforms', () => {
    const r = classifyRoleHeuristic({ email: 'leasing@cleverproperty.com.au' });
    expect(r.role).toBe('property_manager');
    expect(r.confidence).toBeGreaterThanOrEqual(0.5);
  });

  test('signature override: gmail address + Landlord sig → site_owner', () => {
    const r = classifyRoleHeuristic({
      email: 'paul@gmail.com',
      signatureBlock: 'Paul\nLandlord',
    });
    expect(r.role).toBe('site_owner');
  });

  test('returns structured reasons', () => {
    const r = classifyRoleHeuristic({
      email: 'mark@harcourts.com.au',
      signatureBlock: 'Property Manager',
    });
    expect(r.reasons.length).toBeGreaterThan(0);
    expect(r.reasons.some(s => s.includes('property_manager'))).toBe(true);
  });

  test('empty input returns unknown with confidence 0', () => {
    const r = classifyRoleHeuristic({});
    expect(r.role).toBe('unknown');
    expect(r.confidence).toBe(0);
  });

  test('confidence ≤ 1 across the corpus', () => {
    for (const c of CORPUS) {
      const r = classifyRoleHeuristic(c.args);
      expect(r.confidence).toBeLessThanOrEqual(1);
      expect(r.confidence).toBeGreaterThanOrEqual(0);
    }
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * Async classifyRole + LLM fallback wiring
 * ────────────────────────────────────────────────────────────────────── */

describe('classifyRole async: LLM fallback wiring', () => {
  test('heuristic above trust floor: LLM not consulted', async () => {
    let consulted = false;
    const llm: RoleLLMFallback = async () => {
      consulted = true;
      return { role: 'site_owner', confidence: 0.99, reasons: ['llm'] };
    };
    const r = await classifyRole(
      { email: 'mark@cleverproperty.com.au', signatureBlock: 'Property Manager' },
      llm,
    );
    expect(r.role).toBe('property_manager');
    expect(consulted).toBe(false);
  });

  test('heuristic below trust floor: LLM consulted; higher confidence wins', async () => {
    const llm: RoleLLMFallback = async () => ({
      role: 'tenant',
      confidence: 0.9,
      reasons: ['llm: tenant from email body'],
    });
    const r = await classifyRole(
      { email: 'someone@example.com', bodyContext: 'Maybe I should email back later.' },
      llm,
    );
    expect(r.role).toBe('tenant');
    expect(r.confidence).toBe(0.9);
  });

  test('LLM returns null: classifier falls back to heuristic', async () => {
    const llm: RoleLLMFallback = async () => null;
    const r = await classifyRole({ email: 'foo@gmail.com' }, llm);
    // heuristic: gmail → tenant weight 0.2, low confidence
    expect(r.confidence).toBeLessThan(0.7);
  });

  test('LLM throws: classifier swallows + falls back', async () => {
    const llm: RoleLLMFallback = async () => {
      throw new Error('rate limited');
    };
    const r = await classifyRole({ email: 'foo@gmail.com' }, llm);
    expect(r).toBeDefined();
    // Should NOT throw; should be a valid ClassifyResult.
    const ok: ClassifyResult = r;
    expect(['site_owner', 'tenant', 'property_manager', 'agent', 'contractor', 'witness', 'unknown']).toContain(ok.role);
  });

  test('no LLM provided: heuristic is the only path', async () => {
    const r = await classifyRole({ email: 'mark@cleverproperty.com.au' });
    expect(r.role).toBe('property_manager');
  });
});

```
