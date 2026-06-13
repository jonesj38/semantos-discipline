---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/template-version.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.536481+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/template-version.test.ts

```ts
/**
 * Versioned template registry conformance.
 *
 * Guards: hash determinism, descriptor shape, version pinning, and —
 * crucially — that decisionTreeHash is content-addressed over
 * THRESHOLDS so a threshold retune is ALWAYS visible in the audit
 * log even if DECISION_TREE_VERSION isn't bumped. The pinned-hash
 * assertion is a tripwire: if it fails, THRESHOLDS changed — bump
 * DECISION_TREE_VERSION and re-pin (intentional), or you have
 * unintended decision-tree drift.
 */

import { describe, expect, test } from 'bun:test';
import {
  PROMPT_TEMPLATE_ID,
  PROMPT_TEMPLATE_VERSION,
  DECISION_TREE_ID,
  DECISION_TREE_VERSION,
  sha256hex,
  promptHash,
  decisionTreeHash,
  intakeTemplateDescriptor,
} from '../template-version.js';

describe('template-version — hashing', () => {
  test('sha256hex is deterministic + 64-hex', () => {
    const a = sha256hex('hello');
    expect(a).toBe(sha256hex('hello'));
    expect(a).toMatch(/^[0-9a-f]{64}$/);
    expect(a).not.toBe(sha256hex('hello '));
  });

  test('promptHash reflects the exact assembled prompt bytes', () => {
    const p1 = 'You are an intake bot.\n\n[ROM from estimator: $120–$280]';
    const p2 = 'You are an intake bot.\n\n[ROM from estimator: $120–$300]';
    expect(promptHash(p1)).toBe(promptHash(p1));
    expect(promptHash(p1)).not.toBe(promptHash(p2));
  });

  test('decisionTreeHash is stable across calls (content-addressed)', () => {
    expect(decisionTreeHash()).toBe(decisionTreeHash());
    expect(decisionTreeHash()).toMatch(/^[0-9a-f]{64}$/);
  });

  // Tripwire: pin the current THRESHOLDS hash. A failure here means
  // the operator-tuned decision tree changed. That's allowed — but
  // it MUST be intentional: bump DECISION_TREE_VERSION and re-pin
  // this constant in the SAME change, so every audited turn's
  // decisionTree.{version,hash} stays honest about which logic ran.
  test('decisionTreeHash tripwire — THRESHOLDS unchanged since pin', () => {
    expect(decisionTreeHash()).toBe(
      'a98750352ec10c2c1b1751b2ae35f9985d340a8a0647572768890a8c45e14c1e',
    );
  });
});

describe('template-version — descriptor', () => {
  test('version constants are pinned', () => {
    expect(PROMPT_TEMPLATE_ID).toBe('oddjobz.intake.prompt');
    expect(PROMPT_TEMPLATE_VERSION).toBe('1.0.0');
    expect(DECISION_TREE_ID).toBe('oddjobz.intake.decision-tree');
    expect(DECISION_TREE_VERSION).toBe('2026-04');
  });

  test('intakeTemplateDescriptor binds prompt + decision-tree provenance', () => {
    const d = intakeTemplateDescriptor('SYSTEM PROMPT v1\n[ROM: $1–$2]');
    expect(d.prompt.id).toBe('oddjobz.intake.prompt');
    expect(d.prompt.version).toBe('1.0.0');
    expect(d.prompt.hash).toMatch(/^[0-9a-f]{64}$/);
    expect(d.decisionTree.id).toBe('oddjobz.intake.decision-tree');
    expect(d.decisionTree.version).toBe('2026-04');
    expect(d.decisionTree.hash).toBe(decisionTreeHash());
    // Distinct assembled prompts → distinct descriptors; decision
    // tree hash is constant across turns (same THRESHOLDS).
    const d2 = intakeTemplateDescriptor('SYSTEM PROMPT v1\n[ROM: $9–$9]');
    expect(d2.prompt.hash).not.toBe(d.prompt.hash);
    expect(d2.decisionTree.hash).toBe(d.decisionTree.hash);
  });
});

```
