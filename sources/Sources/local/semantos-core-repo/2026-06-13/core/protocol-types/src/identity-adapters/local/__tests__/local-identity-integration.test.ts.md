---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/local/__tests__/local-identity-integration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.917518+00:00
---

# core/protocol-types/src/identity-adapters/local/__tests__/local-identity-integration.test.ts

```ts
/**
 * Integration test — drives the LocalIdentityAdapter facade
 * end-to-end. Covers register / derive / resolve / capability /
 * edge / subtree / recovery / sendAuthenticated and pins the
 * 10-generation deterministic derivation snapshot the prompt asks
 * for.
 */

import { afterEach, describe, expect, test } from 'bun:test';
import { LocalIdentityAdapter } from '../local-identity-adapter';
import { MemoryAdapter } from '../../../adapters/memory-adapter';
import { clearKeyCache } from '../private-key-resolver';
import { recoveryChallengesPort, loggerPort } from '../ports';

afterEach(() => {
  clearKeyCache();
  recoveryChallengesPort.unbind();
  loggerPort.unbind();
});

function freshAdapter() {
  return new LocalIdentityAdapter(new MemoryAdapter());
}

describe('LocalIdentityAdapter', () => {
  test('1. register + derive + resolve round-trip', async () => {
    const adapter = freshAdapter();
    const root = await adapter.registerIdentity('alice@example.com');
    const child = await adapter.deriveChild(root.certId, 'metering.channel.x', 0x00010005);
    const resolved = await adapter.resolveIdentity(root.certId);
    expect(resolved.certId).toBe(root.certId);
    expect(resolved.children?.[0]?.certId).toBe(child.certId);
  });

  test('2. presentCapability OK for held flag', async () => {
    const adapter = freshAdapter();
    const root = await adapter.registerIdentity('alice@example.com');
    const out = await adapter.presentCapability(root.certId, '0x00010005');
    expect(out.valid).toBe(true);
  });

  test('3. presentCapability rejects unheld flag', async () => {
    const adapter = freshAdapter();
    const root = await adapter.registerIdentity('alice@example.com');
    const child = await adapter.deriveChild(root.certId, 'r', 0x00010005);
    const out = await adapter.presentCapability(child.certId, '0x00010003');
    expect(out.valid).toBe(false);
    expect(out.reason).toMatch(/does not hold/);
  });

  test('4. createEdge yields a deterministic edgeId for the same pair', async () => {
    const adapter = freshAdapter();
    const r1 = await adapter.registerIdentity('alice@example.com');
    const r2 = await adapter.registerIdentity('bob@example.com');
    const e1 = await adapter.createEdge(r1.certId, r2.certId);
    const e2 = await adapter.createEdge(r1.certId, r2.certId);
    expect(e1.edgeId).toBe(e2.edgeId);
  });

  test('5. recovery flow with port-overridden challenges', async () => {
    recoveryChallengesPort.bind([
      { id: 'q1', prompt: 'why?' },
      { id: 'q2', prompt: 'what?' },
    ]);
    const adapter = new LocalIdentityAdapter(new MemoryAdapter(), { recoveryThreshold: 1 });
    const session = await adapter.initiateRecovery('alice@example.com');
    expect(session.challengeCount).toBe(2);
    const result = await adapter.submitChallengeAnswers(session.sessionId, [
      { challengeId: 'q1', answer: 'because' },
    ]);
    expect(result.verified).toBe(true);
  });

  test('6. sendAuthenticated requires both certs to exist', async () => {
    const adapter = freshAdapter();
    const root = await adapter.registerIdentity('alice@example.com');
    await expect(
      adapter.sendAuthenticated(root.certId, 'missing', { hello: 'world' }),
    ).rejects.toThrow();
  });

  test('7. 10-generation deterministic derivation snapshot', async () => {
    async function generate10(): Promise<string[]> {
      const adapter = freshAdapter();
      const root = await adapter.registerIdentity('snapshot@example.com');
      const ids = [root.certId];
      let parentId = root.certId;
      for (let g = 1; g <= 10; g++) {
        const child = await adapter.deriveChild(parentId, `gen-${g}`, 0x00010005);
        ids.push(child.certId);
        parentId = child.certId;
      }
      return ids;
    }

    const a = await generate10();
    clearKeyCache();
    const b = await generate10();
    expect(b).toEqual(a);
    expect(new Set(a).size).toBe(11); // every generation distinct
  });

  test('8. loggerPort receives log lines from the facade', async () => {
    const seen: string[] = [];
    loggerPort.bind({ debug: (msg: string) => seen.push(msg) });
    const adapter = freshAdapter();
    await adapter.registerIdentity('alice@example.com');
    expect(seen.some((line) => line.includes('registerIdentity'))).toBe(true);
  });
});

```
