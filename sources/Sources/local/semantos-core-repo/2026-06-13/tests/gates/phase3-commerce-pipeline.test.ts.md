---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase3-commerce-pipeline.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.570091+00:00
---

# tests/gates/phase3-commerce-pipeline.test.ts

```ts
/**
 * Phase 3 Gate Tests — Commerce Pipeline End-to-End
 *
 * T1–T3:   Organization Node Creation & Key Derivation
 * T4–T6:   Commerce Extension & Service Listing
 * T7–T9:   ROM Pricing with Markup
 * T10–T12: Order State Machine & CellStore Persistence
 * T13–T15: Settlement via BRC-100 Stub
 * T16–T18: Paskian Reputation Scoring
 * T19–T21: Team Management via ROLE_ASSIGNMENT
 */

import { describe, test, expect, beforeAll } from 'bun:test';
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';

// ── Core imports ──────────────────────────────────────────────

import { PlexusService, initializePlexusService } from '../../runtime/services/src/plexus/PlexusService';
import { calculateROM, extractComplexityHints } from '../../runtime/shell/src/rom';
import type { PricingPolicy, ROMInput } from '../../runtime/shell/src/rom';
import { StubBRC100Wallet } from '../../core/protocol-types/src/adapters/brc100-wallet-stub';
import type { BRC100WalletAdapter } from '../../core/protocol-types/src/adapters/brc100-wallet-stub';
import { PaskianAdapter } from '../../apps/settlement/src/adapter';
import { enforceCommerceConstraints } from '../../packages/extraction/src/governance/constraint-engine';
import type { CommerceConstraintRules } from '../../packages/extraction/src/governance/constraint-engine';

const ROOT = join(import.meta.dir, '../..');

// ── Fixtures ──────────────────────────────────────────────────

function loadCommerceConfig() {
  const configPath = join(ROOT, 'configs/extensions/commerce.json');
  return JSON.parse(readFileSync(configPath, 'utf-8'));
}

function loadCommerceManifest() {
  const manifestPath = join(ROOT, 'configs/extensions/commerce-manifest.json');
  return JSON.parse(readFileSync(manifestPath, 'utf-8'));
}

function makePricingPolicy(orgMarkup?: { percent: number; label: string }): PricingPolicy {
  return {
    baseRates: {
      quick: { min: 50, max: 120 },
      short: { min: 100, max: 250 },
      quarter_day: { min: 200, max: 450 },
      half_day: { min: 350, max: 700 },
    },
    travelModifiers: {
      core: { surcharge: 0, label: 'Local' },
      extended: { surcharge: 40, label: 'Extended' },
    },
    categoryModifiers: {
      'commerce.services.trades': { factor: 1.0 },
      'commerce.services.consulting': { factor: 1.5 },
    },
    complexityModifiers: {
      '2_story': { factor: 1.15, label: 'Two-storey' },
      emergency: { factor: 1.5, label: 'Emergency' },
    },
    orgMarkup,
    presentation: {
      roundTo: 10,
      rangeLabel: 'Estimated cost',
      disclaimer: 'Estimate only.',
    },
  };
}

// ── T1–T3: Organization Node Creation ──────────────────────────

describe('Phase 3: Organization Node Creation', () => {
  let plexus: PlexusService;

  beforeAll(() => {
    plexus = initializePlexusService({ mode: 'stub' });
  });

  test('T1: deriveOrganization creates ORGANIZATION node with unique key', async () => {
    const founder = await plexus.registerIdentity('founder@test.com');
    const org = await plexus.deriveOrganization(founder.certId, 'Plumbing Co', {
      category: 'plumbing',
      serviceArea: 'Fremantle',
    });
    expect(org.orgCertId).toBeTruthy();
    expect(org.orgCertId).not.toBe(founder.certId);
    expect(org.orgName).toBe('Plumbing Co');
    expect(org.founderCertId).toBe(founder.certId);
    expect(org.metadata.category).toBe('plumbing');
  });

  test('T2: AUTHORITY edge created between founder and org', async () => {
    const founder = await plexus.registerIdentity('founder2@test.com');
    const org = await plexus.deriveOrganization(founder.certId, 'Electric Co');
    const authorityEdges = plexus.getEdgesByType(founder.certId, 'AUTHORITY');
    expect(authorityEdges.length).toBeGreaterThan(0);
    const orgEdge = authorityEdges.find(e => e.responder === org.orgCertId);
    expect(orgEdge).toBeTruthy();
  });

  test('T3: Two orgs under same founder derive different keys', async () => {
    const founder = await plexus.registerIdentity('founder3@test.com');
    const org1 = await plexus.deriveOrganization(founder.certId, 'Org A');
    const org2 = await plexus.deriveOrganization(founder.certId, 'Org B');
    expect(org1.orgCertId).not.toBe(org2.orgCertId);
    expect(org1.derivedPublicKey).not.toBe(org2.derivedPublicKey);
  });
});

// ── T4–T6: Commerce Extension ──────────────────────────────────

describe('Phase 3: Commerce Extension Config', () => {
  test('T4: commerce.json exists and is valid JSON', () => {
    const configPath = join(ROOT, 'configs/extensions/commerce.json');
    expect(existsSync(configPath)).toBe(true);
    const config = loadCommerceConfig();
    expect(config.id).toBe('commerce');
    expect(config.objectTypes).toBeArray();
    expect(config.objectTypes.length).toBe(6);
  });

  test('T5: Commerce extension defines all required object types', () => {
    const config = loadCommerceConfig();
    const typeNames = config.objectTypes.map((t: any) => t.name);
    expect(typeNames).toContain('Service');
    expect(typeNames).toContain('Product');
    expect(typeNames).toContain('Order');
    expect(typeNames).toContain('Payment');
    expect(typeNames).toContain('Review');
    expect(typeNames).toContain('Rating');
  });

  test('T6: Commerce extension has 4 flows defined', () => {
    const config = loadCommerceConfig();
    expect(config.flows.length).toBe(4);
    const flowIds = config.flows.map((f: any) => f.id);
    expect(flowIds).toContain('create-service');
    expect(flowIds).toContain('book-service');
    expect(flowIds).toContain('settle-payment');
    expect(flowIds).toContain('submit-review');
  });
});

// ── T7–T9: ROM Pricing with Markup ─────────────────────────────

describe('Phase 3: ROM Pricing with Organization Markup', () => {
  test('T7: calculateROM with 0% markup returns base price', () => {
    const policy = makePricingPolicy({ percent: 0, label: 'No markup' });
    const input: ROMInput = {
      effortBand: 'quarter_day',
      suburbGroup: 'core',
      categoryPath: 'commerce.services.trades',
      urgency: 'next_week',
      complexityHints: [],
    };
    const result = calculateROM(input, policy);
    expect(result.min).toBe(200);
    expect(result.max).toBe(450);
  });

  test('T8: calculateROM with 10% markup applies correctly', () => {
    const policy = makePricingPolicy({ percent: 10, label: 'Standard premium' });
    const input: ROMInput = {
      effortBand: 'quarter_day',
      suburbGroup: 'core',
      categoryPath: 'commerce.services.trades',
      urgency: 'next_week',
      complexityHints: [],
    };
    const result = calculateROM(input, policy);
    // Base: 200-450, +10% = 220-495
    expect(result.min).toBe(220);
    expect(result.max).toBe(500); // Rounded to nearest 10
    const markupItem = result.breakdown.find(b => b.component === 'orgMarkup');
    expect(markupItem).toBeTruthy();
  });

  test('T9: consulting category with 50% markup stacks correctly', () => {
    const policy = makePricingPolicy({ percent: 50, label: 'Premium' });
    const input: ROMInput = {
      effortBand: 'short',
      suburbGroup: 'core',
      categoryPath: 'commerce.services.consulting',
      urgency: 'next_week',
      complexityHints: [],
    };
    const result = calculateROM(input, policy);
    // Base: 100-250, category ×1.5 = 150-375, markup +50% = 225-562 → rounded
    expect(result.min).toBeGreaterThanOrEqual(220);
    expect(result.max).toBeGreaterThanOrEqual(560);
  });
});

// ── T10–T12: BRC-100 Settlement ─────────────────────────────────

describe('Phase 3: BRC-100 Settlement Stub', () => {
  let wallet: BRC100WalletAdapter;

  beforeAll(() => {
    wallet = new StubBRC100Wallet();
  });

  test('T10: Wallet stub reports ready', async () => {
    expect(await wallet.isReady()).toBe(true);
  });

  test('T11: signSettlement returns stub txid', async () => {
    const result = await wallet.signSettlement({
      payerCertId: 'customer-cert-001',
      payeeCertId: 'founder-cert-001',
      amount: 450,
      currency: 'BSV',
      orderId: 'order-001',
    });
    expect(result.txid).toStartWith('stub-');
    expect(result.status).toBe('stub');
    expect(result.timestamp).toBeTruthy();
  });

  test('T12: verifySettlement confirms stub settlement', async () => {
    const signed = await wallet.signSettlement({
      payerCertId: 'customer-cert-002',
      payeeCertId: 'founder-cert-002',
      amount: 300,
      currency: 'BSV',
      orderId: 'order-002',
    });
    const verification = await wallet.verifySettlement(signed.txid);
    expect(verification.confirmed).toBe(true);
    expect(verification.blockHeight).toBeGreaterThan(0);
  });
});

// ── T13–T15: Paskian Reputation Scoring ─────────────────────────

describe('Phase 3: Paskian Reputation Scoring', () => {
  let paskian: PaskianAdapter;

  beforeAll(() => {
    paskian = new PaskianAdapter({ dbPath: ':memory:' });
  });

  test('T13: logReview creates review node in Paskian graph', async () => {
    const affected = await paskian.logReview({
      providerCellId: 'org-plumbing-001',
      reviewerCellId: 'customer-001',
      rating: 5,
      orderId: 'order-001',
    });
    expect(affected.size).toBeGreaterThan(0);
    expect(affected.has('org-plumbing-001')).toBe(true);
  });

  test('T14: Multiple reviews aggregate into reputation score', async () => {
    // Add 10 reviews with ratings 4-5
    for (let i = 0; i < 10; i++) {
      await paskian.logReview({
        providerCellId: 'org-electric-001',
        reviewerCellId: `customer-${100 + i}`,
        rating: i < 7 ? 5 : 4,
        orderId: `order-${100 + i}`,
      });
    }
    const reputation = paskian.getReputationScore('org-electric-001');
    expect(reputation.totalReviews).toBeGreaterThan(0);
    // Score should exist (exact value depends on Paskian dynamics)
    expect(typeof reputation.score).toBe('number');
  });

  test('T15: Reputation histogram tracks distribution', async () => {
    const reputation = paskian.getReputationScore('org-electric-001');
    expect(reputation.histogram).toBeArray();
    expect(reputation.histogram.length).toBe(5);
  });
});

// ── T16–T18: Team Management ────────────────────────────────────

describe('Phase 3: Team Management via ROLE_ASSIGNMENT', () => {
  let plexus: PlexusService;

  beforeAll(() => {
    plexus = new PlexusService({ mode: 'stub' });
  });

  test('T16: addTeamMember creates ROLE_ASSIGNMENT edge', async () => {
    const founder = await plexus.registerIdentity('team-founder@test.com');
    const org = await plexus.deriveOrganization(founder.certId, 'Team Test Co');
    const alice = await plexus.registerIdentity('alice@test.com');

    const member = await plexus.addTeamMember(org.orgCertId, alice.certId, 'tradie');
    expect(member.certId).toBe(alice.certId);
    expect(member.role).toBe('tradie');
    expect(member.edgeId).toBeTruthy();

    const roleEdges = plexus.getEdgesByType(alice.certId, 'ROLE_ASSIGNMENT');
    expect(roleEdges.length).toBeGreaterThan(0);
  });

  test('T17: checkOrgCapability enforces role hierarchy', async () => {
    const founder = await plexus.registerIdentity('cap-founder@test.com');
    const org = await plexus.deriveOrganization(founder.certId, 'Cap Test Co');
    const viewer = await plexus.registerIdentity('viewer@test.com');
    await plexus.addTeamMember(org.orgCertId, viewer.certId, 'viewer');

    // Founder (admin) can do admin things
    expect(plexus.checkOrgCapability(org.orgCertId, founder.certId, 'admin')).toBe(true);
    // Viewer cannot do tradie things
    expect(plexus.checkOrgCapability(org.orgCertId, viewer.certId, 'tradie')).toBe(false);
    // Viewer can do viewer things
    expect(plexus.checkOrgCapability(org.orgCertId, viewer.certId, 'viewer')).toBe(true);
  });

  test('T18: removeTeamMember revokes access', async () => {
    const founder = await plexus.registerIdentity('remove-founder@test.com');
    const org = await plexus.deriveOrganization(founder.certId, 'Remove Test Co');
    const bob = await plexus.registerIdentity('bob@test.com');
    await plexus.addTeamMember(org.orgCertId, bob.certId, 'tradie');

    expect(plexus.getTeamMembers(org.orgCertId).length).toBe(2); // founder + bob

    plexus.removeTeamMember(org.orgCertId, bob.certId);
    expect(plexus.getTeamMembers(org.orgCertId).length).toBe(1); // founder only
    expect(plexus.checkOrgCapability(org.orgCertId, bob.certId, 'viewer')).toBe(false);
  });
});

// ── T19–T21: Commerce Manifest ──────────────────────────────────

describe('Phase 3: Commerce ExtensionManifest', () => {
  test('T19: commerce-manifest.json exists and is valid', () => {
    const manifestPath = join(ROOT, 'configs/extensions/commerce-manifest.json');
    expect(existsSync(manifestPath)).toBe(true);
    const manifest = loadCommerceManifest();
    expect(manifest.id).toBe('commerce');
    expect(manifest.version).toBe('1.0.0');
    expect(manifest.governanceConfig).toBeTruthy();
  });

  test('T20: Manifest defines constraint rules for all commerce types', () => {
    const manifest = loadCommerceManifest();
    const rules = manifest.governanceConfig.constraintRules;
    expect(rules.order).toBeTruthy();
    expect(rules.service).toBeTruthy();
    expect(rules.review).toBeTruthy();
    expect(rules.payment).toBeTruthy();
  });

  test('T21: Manifest defines facet roles', () => {
    const manifest = loadCommerceManifest();
    expect(manifest.hatRoles.founder).toBeTruthy();
    expect(manifest.hatRoles.tradie).toBeTruthy();
    expect(manifest.hatRoles.customer).toBeTruthy();
    expect(manifest.hatRoles.viewer).toBeTruthy();
  });
});

```
