---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/local/recovery-share-manager.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.914834+00:00
---

# core/protocol-types/src/identity-adapters/local/recovery-share-manager.ts

```ts
/**
 * Recovery flow handlers — initiate + answer-submission.
 *
 * The challenge bank lives in {@link recoveryChallengesPort}; tests
 * bind a deterministic stub before driving the flow.
 */

import { makeIdentityError } from '../../identity';
import type { RecoveryShareManager, RecoverySession } from '../RecoveryShareManager';
import { getRecoveryChallenges } from './ports';
import { sha256HexStr } from './signing-key-deriver';

export interface RecoveryDeps {
  recovery: RecoveryShareManager;
  recoveryThreshold: number;
}

export async function initiateRecovery(
  deps: RecoveryDeps,
  email: string,
): Promise<{
  sessionId: string;
  challengeCount: number;
  challenges?: Array<{ id: string; prompt: string }>;
}> {
  const challenges = getRecoveryChallenges();
  const sessionId = 'session:' + sha256HexStr('recovery:' + email + ':local').slice(0, 32);

  const session: RecoverySession = {
    sessionId,
    email,
    challenges: challenges.map((c) => ({
      id: c.id,
      prompt: c.prompt,
      answerHash: '',
    })),
    threshold: deps.recoveryThreshold,
    verified: false,
    created: Date.now(),
  };

  await deps.recovery.storeSession(session);

  return {
    sessionId,
    challengeCount: challenges.length,
    challenges: challenges.map(({ id, prompt }) => ({ id, prompt })),
  };
}

export async function submitChallengeAnswers(
  deps: RecoveryDeps,
  sessionId: string,
  answers: Array<{ challengeId: string; answer: string }>,
): Promise<{ verified: boolean; exportPayload?: string }> {
  const session = await deps.recovery.loadSession(sessionId);
  if (!session) {
    throw makeIdentityError(
      'SESSION_NOT_FOUND',
      `Recovery session ${sessionId} not found`,
      true,
    );
  }

  for (const answer of answers) {
    const challenge = session.challenges.find((c) => c.id === answer.challengeId);
    if (challenge) {
      challenge.answerHash = sha256HexStr(answer.answer.toLowerCase().trim());
    }
  }

  const answeredCount = session.challenges.filter((c) => c.answerHash.length > 0).length;
  if (answeredCount < session.threshold) return { verified: false };

  session.verified = true;
  await deps.recovery.storeSession(session);

  const recoveryToken = sha256HexStr('token:' + sessionId + ':' + session.email);
  const exportPayload = Buffer.from(
    JSON.stringify({
      sessionId,
      email: session.email,
      recoveredAt: Date.now(),
      recoveryToken,
    }),
  ).toString('base64');

  return { verified: true, exportPayload };
}

```
