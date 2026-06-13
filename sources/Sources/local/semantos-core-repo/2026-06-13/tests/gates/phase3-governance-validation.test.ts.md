---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase3-governance-validation.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.568958+00:00
---

# tests/gates/phase3-governance-validation.test.ts

```ts
/**
 * Phase 3 Gate Tests — Governance Validation for Commerce
 *
 * T1–T3:   Commerce constraint enforcement (enforceCommerceConstraints)
 * T4–T6:   Service constraint validation
 * T7–T9:   Order constraint validation
 * T10–T12: Review constraint validation
 * T13–T14: Payment constraint validation
 * T15–T16: Version compatibility for commerce manifest
 */

import { describe, test, expect } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';

import { enforceCommerceConstraints } from '../../packages/extraction/src/governance/constraint-engine';
import type { CommerceConstraintRules } from '../../packages/extraction/src/governance/constraint-engine';

const ROOT = join(import.meta.dir, '../..');

// ── Fixtures ──────────────────────────────────────────────────

function loadConstraintRules(): CommerceConstraintRules {
  const manifestPath = join(ROOT, 'configs/extensions/commerce-manifest.json');
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf-8'));
  return manifest.governanceConfig.constraintRules;
}

// ── T1–T3: Commerce Constraint Enforcement ─────────────────────

describe('Phase 3: Commerce Constraint Enforcement', () => {
  test('T1: Valid Service passes all constraints', () => {
    const rules = loadConstraintRules();
    const result = enforceCommerceConstraints('Service', {
      name: 'Basic Plumbing Repair',
      categoryPath: 'commerce.services.trades',
      priceType: 'fixed',
      basePrice: 450,
    }, rules);
    expect(result.valid).toBe(true);
    expect(result.violations.length).toBe(0);
  });

  test('T2: Missing required field causes violation', () => {
    const rules = loadConstraintRules();
    const result = enforceCommerceConstraints('Service', {
      // Missing: name, categoryPath, priceType
      basePrice: 100,
    }, rules);
    expect(result.valid).toBe(false);
    expect(result.violations.length).toBeGreaterThan(0);
    expect(result.violations.some(v => v.message.includes('name'))).toBe(true);
  });

  test('T3: Unknown object type passes (no rules)', () => {
    const rules = loadConstraintRules();
    const result = enforceCommerceConstraints('Widget', { foo: 'bar' }, rules);
    expect(result.valid).toBe(true);
  });
});

// ── T4–T6: Service Constraints ──────────────────────────────────

describe('Phase 3: Service Constraint Validation', () => {
  test('T4: Service with invalid priceType is rejected', () => {
    const rules = loadConstraintRules();
    const result = enforceCommerceConstraints('Service', {
      name: 'Test Service',
      categoryPath: 'commerce.services.trades',
      priceType: 'subscription', // Not valid
      basePrice: 100,
    }, rules);
    expect(result.valid).toBe(false);
    expect(result.violations.some(v => v.rule === 'commerce-service-invalid-price-type')).toBe(true);
  });

  test('T5: Service exceeding maxBasePrice is rejected', () => {
    const rules = loadConstraintRules();
    const result = enforceCommerceConstraints('Service', {
      name: 'Expensive Service',
      categoryPath: 'commerce.services.trades',
      priceType: 'fixed',
      basePrice: 200000, // Exceeds 100000
    }, rules);
    expect(result.valid).toBe(false);
    expect(result.violations.some(v => v.rule === 'commerce-service-max-price')).toBe(true);
  });

  test('T6: Service with valid priceType passes', () => {
    const rules = loadConstraintRules();
    for (const priceType of ['fixed', 'hourly', 'rom']) {
      const result = enforceCommerceConstraints('Service', {
        name: `Test ${priceType}`,
        categoryPath: 'commerce.services.trades',
        priceType,
        basePrice: 100,
      }, rules);
      expect(result.valid).toBe(true);
    }
  });
});

// ── T7–T9: Order Constraints ────────────────────────────────────

describe('Phase 3: Order Constraint Validation', () => {
  test('T7: Valid Order with all required fields passes', () => {
    const rules = loadConstraintRules();
    const result = enforceCommerceConstraints('Order', {
      status: 'pending',
      serviceId: 'svc-001',
      customerId: 'cust-001',
      totalAmount: 450,
    }, rules);
    expect(result.valid).toBe(true);
  });

  test('T8: Order missing customerId is rejected', () => {
    const rules = loadConstraintRules();
    const result = enforceCommerceConstraints('Order', {
      status: 'pending',
      serviceId: 'svc-001',
      // Missing: customerId, totalAmount
    }, rules);
    expect(result.valid).toBe(false);
    expect(result.violations.some(v => v.message.includes('customerId'))).toBe(true);
  });

  test('T9: Order with invalid status is rejected', () => {
    const rules = loadConstraintRules();
    const result = enforceCommerceConstraints('Order', {
      status: 'invalid_status',
      serviceId: 'svc-001',
      customerId: 'cust-001',
      totalAmount: 100,
    }, rules);
    expect(result.valid).toBe(false);
    expect(result.violations.some(v => v.rule === 'commerce-order-invalid-status')).toBe(true);
  });
});

// ── T10–T12: Review Constraints ─────────────────────────────────

describe('Phase 3: Review Constraint Validation', () => {
  test('T10: Valid Review with rating 1-5 passes', () => {
    const rules = loadConstraintRules();
    for (const rating of [1, 2, 3, 4, 5]) {
      const result = enforceCommerceConstraints('Review', {
        orderId: 'order-001',
        rating,
      }, rules);
      expect(result.valid).toBe(true);
    }
  });

  test('T11: Review with rating 0 is rejected', () => {
    const rules = loadConstraintRules();
    const result = enforceCommerceConstraints('Review', {
      orderId: 'order-001',
      rating: 0,
    }, rules);
    expect(result.valid).toBe(false);
    expect(result.violations.some(v => v.rule === 'commerce-review-rating-range')).toBe(true);
  });

  test('T12: Review with rating 6 is rejected', () => {
    const rules = loadConstraintRules();
    const result = enforceCommerceConstraints('Review', {
      orderId: 'order-001',
      rating: 6,
    }, rules);
    expect(result.valid).toBe(false);
    expect(result.violations.some(v => v.rule === 'commerce-review-rating-range')).toBe(true);
  });
});

// ── T13–T14: Payment Constraints ────────────────────────────────

describe('Phase 3: Payment Constraint Validation', () => {
  test('T13: Valid Payment passes', () => {
    const rules = loadConstraintRules();
    const result = enforceCommerceConstraints('Payment', {
      orderId: 'order-001',
      amount: 450,
      status: 'pending',
      method: 'brc100',
    }, rules);
    expect(result.valid).toBe(true);
  });

  test('T14: Payment with invalid method is rejected', () => {
    const rules = loadConstraintRules();
    const result = enforceCommerceConstraints('Payment', {
      orderId: 'order-001',
      amount: 450,
      status: 'pending',
      method: 'paypal', // Not valid
    }, rules);
    expect(result.valid).toBe(false);
    expect(result.violations.some(v => v.rule === 'commerce-payment-invalid-method')).toBe(true);
  });
});

// ── T15–T16: Manifest Version & Role Mapping ────────────────────

describe('Phase 3: Commerce Manifest Governance', () => {
  test('T15: Manifest constraintRules cover Order status transitions', () => {
    const rules = loadConstraintRules();
    expect(rules.order?.statusTransitions).toBeTruthy();
    const transitions = rules.order!.statusTransitions!;
    // pending can go to accepted or cancelled
    expect(transitions.pending).toContain('accepted');
    expect(transitions.pending).toContain('cancelled');
    // completed can go to reviewed
    expect(transitions.completed).toContain('reviewed');
    // reviewed is terminal
    expect(transitions.reviewed?.length).toBe(0);
  });

  test('T16: Manifest defines review constraint flags', () => {
    const rules = loadConstraintRules();
    expect(rules.review?.maxOnePerCustomerPerOrg).toBe(true);
    expect(rules.review?.requiresVerifiedPurchase).toBe(true);
    expect(rules.review?.ratingRange).toEqual([1, 5]);
  });
});

```
