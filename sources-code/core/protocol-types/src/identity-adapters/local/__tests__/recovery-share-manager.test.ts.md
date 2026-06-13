---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/local/__tests__/recovery-share-manager.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.918401+00:00
---

# core/protocol-types/src/identity-adapters/local/__tests__/recovery-share-manager.test.ts

```ts
/**
 * Recovery flow tests — initiateRecovery + submitChallengeAnswers.
 */

import { afterEach, describe, expect, test } from 'bun:test';
import { recoveryChallengesPort } from '../ports';
import { initiateRecovery, submitChallengeAnswers } from '../recovery-share-manager';
import { RecoveryShareManager } from '../../RecoveryShareManager';
import { MemoryAdapter } from '../../../adapters/memory-adapter';

afterEach(() => recoveryChallengesPort.unbind());

function makeDeps(threshold = 3) {
  const recovery = new RecoveryShareManager(new MemoryAdapter());
  return { recovery, recoveryThreshold: threshold };
}

describe('initiateRecovery', () => {
  test('1. produces a deterministic sessionId for the same email', async () => {
    const a = await initiateRecovery(makeDeps(), 'alice@example.com');
    const b = await initiateRecovery(makeDeps(), 'alice@example.com');
    expect(b.sessionId).toBe(a.sessionId);
  });

  test('2. returns the canonical 4-prompt bank by default', async () => {
    const out = await initiateRecovery(makeDeps(), 'alice@example.com');
    expect(out.challengeCount).toBe(4);
    expect(out.challenges?.map((c) => c.id).sort()).toEqual(['c1', 'c2', 'c3', 'c4']);
  });

  test('3. honours the recoveryChallengesPort override', async () => {
    recoveryChallengesPort.bind([
      { id: 'why', prompt: 'why?' },
      { id: 'what', prompt: 'what?' },
    ]);
    const out = await initiateRecovery(makeDeps(), 'alice@example.com');
    expect(out.challengeCount).toBe(2);
    expect(out.challenges?.map((c) => c.id)).toEqual(['why', 'what']);
  });
});

describe('submitChallengeAnswers', () => {
  test('4. throws SESSION_NOT_FOUND for an unknown sessionId', async () => {
    const deps = makeDeps();
    await expect(
      submitChallengeAnswers(deps, 'session:bogus', [{ challengeId: 'c1', answer: 'red' }]),
    ).rejects.toThrow(/Recovery session/);
  });

  test('5. fewer than threshold answers → verified:false', async () => {
    const deps = makeDeps(3);
    const session = await initiateRecovery(deps, 'alice@example.com');
    const out = await submitChallengeAnswers(deps, session.sessionId, [
      { challengeId: 'c1', answer: 'red' },
      { challengeId: 'c2', answer: 'sydney' },
    ]);
    expect(out.verified).toBe(false);
  });

  test('6. ≥threshold answers → verified:true with exportPayload', async () => {
    const deps = makeDeps(3);
    const session = await initiateRecovery(deps, 'alice@example.com');
    const out = await submitChallengeAnswers(deps, session.sessionId, [
      { challengeId: 'c1', answer: 'a@b.com' },
      { challengeId: 'c2', answer: 'red' },
      { challengeId: 'c3', answer: 'sydney' },
    ]);
    expect(out.verified).toBe(true);
    const decoded = JSON.parse(Buffer.from(out.exportPayload!, 'base64').toString('utf8'));
    expect(decoded.email).toBe('alice@example.com');
    expect(typeof decoded.recoveryToken).toBe('string');
  });

  test('7. answers are normalized (lowercased + trimmed) before hashing', async () => {
    const deps = makeDeps(1);
    const session = await initiateRecovery(deps, 'alice@example.com');
    const a = await submitChallengeAnswers(deps, session.sessionId, [
      { challengeId: 'c1', answer: '  Alice@Example.com  ' },
    ]);
    expect(a.verified).toBe(true);
  });
});

```
