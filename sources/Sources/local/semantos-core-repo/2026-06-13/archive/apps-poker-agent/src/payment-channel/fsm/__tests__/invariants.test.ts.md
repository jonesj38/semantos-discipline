---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/fsm/__tests__/invariants.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.797771+00:00
---

# archive/apps-poker-agent/src/payment-channel/fsm/__tests__/invariants.test.ts

```ts
/**
 * CLAUDE.md guardrail tests — each describe block names the rule
 * number it pins.
 */

import { describe, expect, test } from 'bun:test';
import {
  assertArtifactsImmutable,
  assertFundingInvariants,
  assertKeyIds,
  assertNoP2SH,
  assertRoleScopedKeyId,
  assertSpvAttached,
} from '../invariants';
import { consumerKeyIds, freshState, validArtifacts, validSpv } from './fixtures';
import type { RoleScopedKeyId } from '../types';

describe('CLAUDE.md rule 1 — freeze envelopeHex/simpleRawTx at FUNDED', () => {
  test('1a. allows initial assignment when current is undefined', () => {
    expect(assertArtifactsImmutable(undefined, validArtifacts).ok).toBe(true);
  });
  test('1b. accepts identical artifacts on re-fund', () => {
    expect(assertArtifactsImmutable(validArtifacts, validArtifacts).ok).toBe(true);
  });
  test('1c. rejects envelopeHex mutation', () => {
    const out = assertArtifactsImmutable(validArtifacts, { ...validArtifacts, envelopeHex: 'aa' });
    expect(out.ok).toBe(false);
    if (!out.ok) expect(out.reason).toMatch(/invariant 1.*envelopeHex/);
  });
  test('1d. rejects simpleRawTx mutation', () => {
    const out = assertArtifactsImmutable(validArtifacts, { ...validArtifacts, simpleRawTx: 'bb' });
    expect(out.ok).toBe(false);
    if (!out.ok) expect(out.reason).toMatch(/invariant 1.*simpleRawTx/);
  });
  test('1e. rejects txid mutation', () => {
    const out = assertArtifactsImmutable(validArtifacts, { ...validArtifacts, txid: 'cc' });
    expect(out.ok).toBe(false);
    if (!out.ok) expect(out.reason).toMatch(/invariant 1.*txid/);
  });
});

describe('CLAUDE.md rule 2 — only advance on real wallet success / SPV proof', () => {
  test('2a. rejects undefined SPV proof', () => {
    const out = assertSpvAttached(undefined);
    expect(out.ok).toBe(false);
    if (!out.ok) expect(out.reason).toMatch(/invariant 2.*SPV proof must be attached/);
  });
  test('2b. rejects empty bumpHash', () => {
    const out = assertSpvAttached({ ...validSpv, bumpHash: '' });
    expect(out.ok).toBe(false);
    if (!out.ok) expect(out.reason).toMatch(/empty bumpHash/);
  });
  test('2c. accepts a real SPV proof', () => {
    expect(assertSpvAttached(validSpv).ok).toBe(true);
  });
});

describe('CLAUDE.md rule 3 — no P2SH', () => {
  test('3a. rejects non-native multisig', () => {
    const out = assertNoP2SH(false);
    expect(out.ok).toBe(false);
    if (!out.ok) expect(out.reason).toMatch(/invariant 3.*native 2-of-2/);
  });
  test('3b. accepts native multisig', () => {
    expect(assertNoP2SH(true).ok).toBe(true);
  });
});

describe('CLAUDE.md rule 4 — role-scoped keyID format', () => {
  const valid: RoleScopedKeyId = consumerKeyIds[0]!;

  test('4a. accepts valid <role>-<scope>:<orgId>:<ts>:<nonce> form', () => {
    expect(assertRoleScopedKeyId(valid).ok).toBe(true);
  });
  test('4b. accepts bare <role>:<orgId>:<ts>:<nonce> (no scope segment)', () => {
    expect(
      assertRoleScopedKeyId({ role: 'consumer', keyId: 'consumer:org-1:170:nonce' }).ok,
    ).toBe(true);
  });
  test('4c. rejects missing role prefix', () => {
    const out = assertRoleScopedKeyId({
      role: 'consumer',
      keyId: 'admin-root:org:1700:n',
    });
    expect(out.ok).toBe(false);
    if (!out.ok) expect(out.reason).toMatch(/invariant 4/);
  });
  test('4d. rejects keyID where role does not match channel role', () => {
    const out = assertRoleScopedKeyId({
      role: 'provider',
      keyId: 'consumer-root:org:1700:n',
    });
    expect(out.ok).toBe(false);
    if (!out.ok) expect(out.reason).toMatch(/role prefix/);
  });
  test('4e. rejects keyID with too few segments', () => {
    const out = assertRoleScopedKeyId({ role: 'consumer', keyId: 'consumer-root' });
    expect(out.ok).toBe(false);
  });
  test('4f. assertKeyIds short-circuits on first failure', () => {
    const out = assertKeyIds([
      consumerKeyIds[0]!,
      { role: 'consumer', keyId: 'bogus' },
    ]);
    expect(out.ok).toBe(false);
  });
  test('4g. assertKeyIds accepts an empty list', () => {
    expect(assertKeyIds([]).ok).toBe(true);
  });
});

describe('assertFundingInvariants — bundled rules 1+3+4', () => {
  test('5a. accepts a clean funding event', () => {
    const out = assertFundingInvariants({
      current: freshState(),
      artifacts: validArtifacts,
      isNativeMultisig: true,
      keyIds: consumerKeyIds,
    });
    expect(out.ok).toBe(true);
  });
  test('5b. rejects on rule 3 failure', () => {
    const out = assertFundingInvariants({
      current: freshState(),
      artifacts: validArtifacts,
      isNativeMultisig: false,
      keyIds: consumerKeyIds,
    });
    expect(out.ok).toBe(false);
    if (!out.ok) expect(out.reason).toMatch(/invariant 3/);
  });
  test('5c. rejects on rule 4 failure', () => {
    const out = assertFundingInvariants({
      current: freshState(),
      artifacts: validArtifacts,
      isNativeMultisig: true,
      keyIds: [{ role: 'consumer', keyId: 'bogus' }],
    });
    expect(out.ok).toBe(false);
    if (!out.ok) expect(out.reason).toMatch(/invariant 4/);
  });
  test('5d. rejects on rule 1 failure (mutated artifact)', () => {
    const current = { ...freshState(), state: 'FUNDED' as const, artifacts: validArtifacts };
    const out = assertFundingInvariants({
      current,
      artifacts: { ...validArtifacts, envelopeHex: 'cafe' },
      isNativeMultisig: true,
      keyIds: consumerKeyIds,
    });
    expect(out.ok).toBe(false);
    if (!out.ok) expect(out.reason).toMatch(/invariant 1/);
  });
});

```
