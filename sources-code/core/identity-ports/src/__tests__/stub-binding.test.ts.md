---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/identity-ports/src/__tests__/stub-binding.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.944269+00:00
---

# core/identity-ports/src/__tests__/stub-binding.test.ts

```ts
/**
 * Stub-binding contract tests. These pin the behavior the cube demo and
 * downstream tests rely on — every assertion here is something a consumer
 * is allowed to depend on.
 */

import { describe, test, expect, beforeEach, afterEach } from 'bun:test';

import {
  bindAllIdentityPorts,
  unbindAllIdentityPorts,
  identityPort,
  recoveryPort,
  attestationPort,
  capabilityPort,
  economicPort,
} from '../index.js';
import {
  makeStubBindings,
  seedStubCapability,
  consumeStubCapability,
  StubIdentityError,
  type StubStore,
} from '../stub-binding.js';

describe('stub binding — identity', () => {
  let store: StubStore;

  beforeEach(() => {
    const built = makeStubBindings();
    store = built.store;
    bindAllIdentityPorts(built.bundle);
  });

  afterEach(() => {
    unbindAllIdentityPorts();
  });

  test('registerIdentity is idempotent per email', () => {
    const a = identityPort.get().registerIdentity('alice@example.com');
    const b = identityPort.get().registerIdentity('alice@example.com');
    expect(a.certId).toBe(b.certId);
    expect(a.publicKey).toBe(b.publicKey);
  });

  test('registerIdentity is deterministic across fresh stores given the same namespace', () => {
    const built = makeStubBindings();
    const a = built.bundle.identity.registerIdentity('bob@example.com');
    const built2 = makeStubBindings();
    const b = built2.bundle.identity.registerIdentity('bob@example.com');
    expect(a.certId).toBe(b.certId);
  });

  test('different namespaces produce different cert IDs for the same email', () => {
    const ns1 = makeStubBindings({ namespace: 'ns1' });
    const ns2 = makeStubBindings({ namespace: 'ns2' });
    const a = ns1.bundle.identity.registerIdentity('eve@example.com');
    const b = ns2.bundle.identity.registerIdentity('eve@example.com');
    expect(a.certId).not.toBe(b.certId);
  });

  test('resolveIdentity throws for unknown cert', () => {
    expect(() => identityPort.get().resolveIdentity('00'.repeat(32))).toThrow(StubIdentityError);
  });

  test('deriveChild assigns monotonic childIndex per parent', () => {
    const root = identityPort.get().registerIdentity('parent@example.com');
    const a = identityPort.get().deriveChild(root.certId, 'app:a', 0x10001);
    const b = identityPort.get().deriveChild(root.certId, 'app:b', 0x10001);
    const c = identityPort.get().deriveChild(root.certId, 'app:a', 0x10001);
    expect(a.childIndex).toBe(0);
    expect(b.childIndex).toBe(1);
    expect(c.childIndex).toBe(2);
  });

  test('querySubtree returns sorted children at depth=1', () => {
    const root = identityPort.get().registerIdentity('tree@example.com');
    identityPort.get().deriveChild(root.certId, 'r0', 0x1);
    identityPort.get().deriveChild(root.certId, 'r1', 0x1);
    const tree = identityPort.get().querySubtree(root.certId, 1);
    expect(tree.root).toBe(root.certId);
    expect(tree.children).toHaveLength(2);
    expect(tree.children[0]!.childIndex).toBe(0);
    expect(tree.children[1]!.childIndex).toBe(1);
  });

  test('querySubtree at depth=2 includes grandchildren', () => {
    const root = identityPort.get().registerIdentity('grand@example.com');
    const child = identityPort.get().deriveChild(root.certId, 'r0', 0x1);
    identityPort.get().deriveChild(child.certId, 'r0.0', 0x1);
    identityPort.get().deriveChild(child.certId, 'r0.1', 0x1);
    const tree = identityPort.get().querySubtree(root.certId, 2);
    expect(tree.children[0]!.grandchildren).toHaveLength(2);
  });

  test('createEdge throws if either party is unregistered', () => {
    const alice = identityPort.get().registerIdentity('alice2@example.com');
    expect(() => identityPort.get().createEdge(alice.certId, '00'.repeat(32))).toThrow(
      StubIdentityError,
    );
  });

  test('createEdge stores recovery policy in the in-memory edge row', () => {
    const a = identityPort.get().registerIdentity('a@e.com');
    const b = identityPort.get().registerIdentity('b@e.com');
    const e = identityPort.get().createEdge(a.certId, b.certId, 'BACKUP_ON_CREATE');
    expect(e.edgeId).toBeDefined();
    // Per §2.5.5: signingKeyIndex is stored, sharedSecret is never returned.
    expect(e.signingKeyIndex).toBeGreaterThanOrEqual(0);
    expect((e as unknown as Record<string, unknown>).sharedSecret).toBeUndefined();
    expect(store.edges.get(e.edgeId)?.recoveryPolicy).toBe('BACKUP_ON_CREATE');
  });

  test('getCert returns null for unknown cert (does not throw)', () => {
    expect(identityPort.get().getCert('00'.repeat(32))).toBeNull();
  });

  test('getCert returns the full row for known cert', () => {
    const r = identityPort.get().registerIdentity('full@example.com');
    const cert = identityPort.get().getCert(r.certId);
    expect(cert).not.toBeNull();
    expect(cert!.certId).toBe(r.certId);
    expect(cert!.derivationPath).toBe('root');
    expect(cert!.email).toBe('full@example.com');
  });
});

describe('stub binding — recovery', () => {
  beforeEach(() => {
    const built = makeStubBindings();
    bindAllIdentityPorts(built.bundle);
  });

  afterEach(() => unbindAllIdentityPorts());

  test('initiateRecovery returns the default 3 challenges', () => {
    const r = recoveryPort.get().initiateRecovery('rec@example.com');
    expect(r.challengeCount).toBe(3);
    expect(r.challenges).toHaveLength(3);
  });

  test('correct answers verify and produce an exportPayload marked as stub', () => {
    const r = recoveryPort.get().initiateRecovery('rec@example.com');
    const v = recoveryPort.get().submitChallengeAnswers(r.sessionId, [
      { challengeId: 'q1', answer: 'yes' },
      { challengeId: 'q2', answer: 'yes' },
      { challengeId: 'q3', answer: 'yes' },
    ]);
    expect(v.verified).toBe(true);
    expect(v.exportPayload).toBeDefined();
    const decoded = JSON.parse(atob(v.exportPayload!));
    expect(decoded.stub).toBe(true);
    expect(decoded.email).toBe('rec@example.com');
  });

  test('wrong answers do NOT verify and do NOT produce an exportPayload', () => {
    const r = recoveryPort.get().initiateRecovery('rec@example.com');
    const v = recoveryPort.get().submitChallengeAnswers(r.sessionId, [
      { challengeId: 'q1', answer: 'no' },
      { challengeId: 'q2', answer: 'yes' },
      { challengeId: 'q3', answer: 'yes' },
    ]);
    expect(v.verified).toBe(false);
    expect(v.exportPayload).toBeUndefined();
  });

  test('answer comparison normalizes case and trims whitespace', () => {
    const r = recoveryPort.get().initiateRecovery('case@example.com');
    const v = recoveryPort.get().submitChallengeAnswers(r.sessionId, [
      { challengeId: 'q1', answer: '  YES  ' },
      { challengeId: 'q2', answer: 'Yes' },
      { challengeId: 'q3', answer: 'yes' },
    ]);
    expect(v.verified).toBe(true);
  });

  test('unknown sessionId throws StubIdentityError', () => {
    expect(() =>
      recoveryPort.get().submitChallengeAnswers('00'.repeat(32), []),
    ).toThrow(StubIdentityError);
  });

  test('custom defaultChallenges override the built-in set', () => {
    // Override the outer-scope binding from `beforeEach` with a custom one.
    // Using the bundle directly rather than the global ports so we don't
    // trip the re-bind warning.
    const built = makeStubBindings({
      defaultChallenges: {
        challenges: [{ id: 'pet', prompt: "first pet's name?" }],
        answers: { pet: 'Fluffy' },
      },
    });
    const r = built.bundle.recovery.initiateRecovery('cu@example.com');
    expect(r.challenges).toHaveLength(1);
    const v = built.bundle.recovery.submitChallengeAnswers(r.sessionId, [
      { challengeId: 'pet', answer: 'fluffy' },
    ]);
    expect(v.verified).toBe(true);
  });
});

describe('stub binding — attestation', () => {
  beforeEach(() => bindAllIdentityPorts(makeStubBindings().bundle));
  afterEach(() => unbindAllIdentityPorts());

  test('proveContinuity returns a stub-marked attestation for known cert', async () => {
    const r = identityPort.get().registerIdentity('att@example.com');
    const a = await attestationPort.get().proveContinuity(r.certId);
    expect(a.kind).toBe('continuity');
    expect(a.certId).toBe(r.certId);
    expect(a.verified).toBe('stub');
    expect(a.signature).toMatch(/^[0-9a-f]+$/);
  });

  test('proveContinuity throws for unknown cert', async () => {
    await expect(attestationPort.get().proveContinuity('00'.repeat(32))).rejects.toThrow(
      StubIdentityError,
    );
  });

  test('all three kinds round-trip the certId', async () => {
    const r = identityPort.get().registerIdentity('multi@example.com');
    const c = await attestationPort.get().proveContinuity(r.certId);
    const e = await attestationPort.get().proveEdgePresence(r.certId, 'edge_creation');
    const p = await attestationPort.get().proveAppPresence(r.certId, 'cube-demo');
    expect(c.kind).toBe('continuity');
    expect(e.kind).toBe('edge_presence');
    expect(p.kind).toBe('app_presence');
    expect(new Set([c.certId, e.certId, p.certId])).toEqual(new Set([r.certId]));
  });
});

describe('stub binding — capability', () => {
  let store: StubStore;

  beforeEach(() => {
    const built = makeStubBindings();
    store = built.store;
    bindAllIdentityPorts(built.bundle);
  });

  afterEach(() => unbindAllIdentityPorts());

  test('present returns invalid for unknown capability', () => {
    const r = capabilityPort.get().present('any-cert', 'no-such-cap');
    expect(r.valid).toBe(false);
    expect(r.reason).toBe('unknown_capability');
    expect(r.verifier).toBe('stub');
  });

  test('present returns valid after seedStubCapability with matching cert', () => {
    const id = identityPort.get().registerIdentity('cap@example.com');
    seedStubCapability(store, 'cap-1', id.certId, 'data_access');
    const r = capabilityPort.get().present(id.certId, 'cap-1');
    expect(r.valid).toBe(true);
    expect(r.verifier).toBe('stub');
  });

  test('present returns cert_mismatch when seeded cert differs', () => {
    const id = identityPort.get().registerIdentity('cap2@example.com');
    seedStubCapability(store, 'cap-2', id.certId, 'permission');
    const r = capabilityPort.get().present('different-cert', 'cap-2');
    expect(r.valid).toBe(false);
    expect(r.reason).toBe('cert_mismatch');
  });

  test('present returns already_consumed after consumeStubCapability', () => {
    const id = identityPort.get().registerIdentity('cap3@example.com');
    seedStubCapability(store, 'cap-3', id.certId, 'recovery');
    consumeStubCapability(store, 'cap-3');
    const r = capabilityPort.get().present(id.certId, 'cap-3');
    expect(r.valid).toBe(false);
    expect(r.reason).toBe('already_consumed');
  });
});

describe('stub binding — economic (RM-062)', () => {
  beforeEach(() => {
    const built = makeStubBindings();
    bindAllIdentityPorts(built.bundle);
  });
  afterEach(() => unbindAllIdentityPorts());

  test('signSpend returns a txAnchor and round-trips via verifyPayment', async () => {
    const payer = identityPort.get().registerIdentity('alice@example.com');
    const spend = await economicPort.get().signSpend({
      payerCertId: payer.certId,
      targetId: 'cell-1',
      amount: 1000,
      currency: 'sats',
    });
    expect(spend.txAnchor).toMatch(/^[0-9a-f]{64}$/);
    expect(spend.amount).toBe(1000);
    expect(spend.currency).toBe('sats');
    expect(spend.verifier).toBe('stub');

    const v = await economicPort.get().verifyPayment({
      txAnchor: spend.txAnchor,
      amount: 1000,
      currency: 'sats',
    });
    expect(v.valid).toBe(true);
    expect(v.verifier).toBe('stub');
  });

  test('verifyPayment returns unknown_anchor for an unseen txAnchor', async () => {
    const v = await economicPort.get().verifyPayment({
      txAnchor: 'deadbeef',
      amount: 1,
      currency: 'sats',
    });
    expect(v.valid).toBe(false);
    expect(v.reason).toBe('unknown_anchor');
  });

  test('verifyPayment rejects amount_short when required exceeds signed amount', async () => {
    const payer = identityPort.get().registerIdentity('bob@example.com');
    const spend = await economicPort.get().signSpend({
      payerCertId: payer.certId,
      targetId: 'cell-2',
      amount: 100,
      currency: 'sats',
    });
    const v = await economicPort.get().verifyPayment({
      txAnchor: spend.txAnchor,
      amount: 500,
      currency: 'sats',
    });
    expect(v.valid).toBe(false);
    expect(v.reason).toBe('amount_short');
  });

  test('verifyPayment rejects currency_mismatch', async () => {
    const payer = identityPort.get().registerIdentity('carol@example.com');
    const spend = await economicPort.get().signSpend({
      payerCertId: payer.certId,
      targetId: 'cell-3',
      amount: 100,
      currency: 'sats',
    });
    const v = await economicPort.get().verifyPayment({
      txAnchor: spend.txAnchor,
      amount: 100,
      currency: 'USD',
    });
    expect(v.valid).toBe(false);
    expect(v.reason).toBe('currency_mismatch');
  });

  test('signSpend throws on non-positive amount', async () => {
    const payer = identityPort.get().registerIdentity('dan@example.com');
    await expect(
      economicPort.get().signSpend({
        payerCertId: payer.certId,
        targetId: 'cell-x',
        amount: 0,
        currency: 'sats',
      }),
    ).rejects.toThrow(/INVALID_AMOUNT|amount must be positive/);
  });

  test('signSpend produces distinct txAnchors for sequential calls with same inputs', async () => {
    const payer = identityPort.get().registerIdentity('eve@example.com');
    const a = await economicPort.get().signSpend({
      payerCertId: payer.certId,
      targetId: 'cell-y',
      amount: 50,
      currency: 'sats',
    });
    const b = await economicPort.get().signSpend({
      payerCertId: payer.certId,
      targetId: 'cell-y',
      amount: 50,
      currency: 'sats',
    });
    expect(a.txAnchor).not.toBe(b.txAnchor);
  });
});

```
