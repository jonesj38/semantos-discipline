---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/popup-create-ux.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.666405+00:00
---

# cartridges/wallet-headers/brain/test/popup-create-ux.spec.ts

```ts
// popup-create UX hardening tests (v0.4).
//
// Coverage:
//   • validateChallengeAnswers — three hard-block rules + two soft-warn rules
//   • describeAnswerError / describeAnswerWarning — exact UI strings
//   • runCreateFlow — retype-confirm gate + duplicate / equals-question /
//     empty after normalize all surface BAD_INPUT before createWallet runs
//   • renderPostCreateBanner — produces buttons for the supplied transports
//     and runs them on click

import { beforeEach, describe, expect, test } from 'bun:test';
import 'fake-indexeddb/auto';
import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';

import {
  validateChallengeAnswers,
  describeAnswerError,
  describeAnswerWarning,
  runCreateFlow,
  renderPostCreateBanner,
  LOCAL_BACKUP_WARNING,
} from '../src/popup-create';
import { _resetRuntimeForTests } from '../src/wallet-ops';
import { _resetDbForTests } from '../src/storage';
import type { EnvelopeTransport, SerializedEnvelope, TransportResult } from '../src/transport';

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

const Q = ["Mother's maiden name?", 'City of birth?', 'First pet?'] as [string, string, string];

beforeEach(() => {
  _resetRuntimeForTests();
  _resetDbForTests();
  return new Promise<void>((resolve) => {
    const req = indexedDB.deleteDatabase('semantos-wallet');
    req.onsuccess = () => resolve();
    req.onerror = () => resolve();
    req.onblocked = () => resolve();
  });
});

// ──────────────────────────────────────────────────────────────────────
// validateChallengeAnswers — pure-state rules
// ──────────────────────────────────────────────────────────────────────

describe('validateChallengeAnswers — hard-block rules', () => {
  test('happy path: three distinct answers + matching confirms passes', () => {
    const v = validateChallengeAnswers(
      Q,
      ['Smith', 'Sydney', 'Rover'],
      ['Smith', 'Sydney', 'Rover'],
    );
    expect(v.ok).toBe(true);
    expect(v.perAnswer[0]!.normalized).toBe('smith');
    expect(v.perAnswer[1]!.normalized).toBe('sydney');
    expect(v.perAnswer[2]!.normalized).toBe('rover');
  });

  test('hard-block 1: empty after normalize', () => {
    const v = validateChallengeAnswers(
      Q,
      ['Smith', '   ', 'Rover'],
      ['Smith', '   ', 'Rover'],
    );
    expect(v.ok).toBe(false);
    expect(v.perAnswer[1]!.errors[0]!.kind).toBe('EMPTY');
  });

  test('hard-block 2: retype-confirm mismatch', () => {
    const v = validateChallengeAnswers(
      Q,
      ['Smith', 'Sydney', 'Rover'],
      ['Smith', 'Sidney', 'Rover'],
    );
    expect(v.ok).toBe(false);
    const codes = v.perAnswer[1]!.errors.map((e) => e.kind);
    expect(codes).toContain('MISMATCH');
  });

  test('hard-block 3: two slots normalize to the same string', () => {
    const v = validateChallengeAnswers(
      Q,
      ['Sydney', 'sydney', 'Rover'],
      ['Sydney', 'sydney', 'Rover'],
    );
    expect(v.ok).toBe(false);
    const e0 = v.perAnswer[0]!.errors.find((e) => e.kind === 'DUPLICATE_OF');
    const e1 = v.perAnswer[1]!.errors.find((e) => e.kind === 'DUPLICATE_OF');
    expect(e0).toBeDefined();
    expect(e1).toBeDefined();
  });

  test('hard-block 4: answer normalizes equal to the question text', () => {
    const v = validateChallengeAnswers(
      ['favourite city?', 'City of birth?', 'First pet?'] as [string, string, string],
      ['favourite city?', 'Sydney', 'Rover'],
      ['favourite city?', 'Sydney', 'Rover'],
    );
    expect(v.ok).toBe(false);
    expect(v.perAnswer[0]!.errors[0]!.kind).toBe('EQUALS_QUESTION');
  });

  test('confirms omitted: retype-confirm rule skipped (legacy callers)', () => {
    const v = validateChallengeAnswers(Q, ['Smith', 'Sydney', 'Rover']);
    expect(v.ok).toBe(true);
  });
});

describe('validateChallengeAnswers — soft-warn rules', () => {
  test('soft-warn 1: single-token answer', () => {
    const v = validateChallengeAnswers(Q, ['Smith', 'Sydney', 'Rover'], ['Smith', 'Sydney', 'Rover']);
    expect(v.ok).toBe(true); // soft-warns don't block
    for (let i = 0; i < 3; i++) {
      expect(v.perAnswer[i]!.warnings.some((w) => w.kind === 'SINGLE_WORD')).toBe(true);
    }
  });

  test('soft-warn 2: short all-numeric', () => {
    const v = validateChallengeAnswers(
      Q,
      ['1234567', 'two words', 'three more words'],
      ['1234567', 'two words', 'three more words'],
    );
    expect(v.ok).toBe(true);
    expect(v.perAnswer[0]!.warnings.some((w) => w.kind === 'SHORT_NUMERIC')).toBe(true);
    // Multi-word answers should NOT carry SINGLE_WORD.
    expect(v.perAnswer[1]!.warnings.some((w) => w.kind === 'SINGLE_WORD')).toBe(false);
  });

  test('long numeric (>= 8 chars) does not trigger SHORT_NUMERIC', () => {
    const v = validateChallengeAnswers(
      Q,
      ['12345678', 'two words', 'three more words'],
      ['12345678', 'two words', 'three more words'],
    );
    expect(v.perAnswer[0]!.warnings.some((w) => w.kind === 'SHORT_NUMERIC')).toBe(false);
  });
});

describe('describeAnswerError / describeAnswerWarning', () => {
  test('UI strings include retype-confirm advisory', () => {
    expect(describeAnswerError({ kind: 'MISMATCH' })).toContain('retype');
    expect(describeAnswerError({ kind: 'EMPTY' })).toContain('required');
    expect(describeAnswerError({ kind: 'DUPLICATE_OF', otherIndex: 1 })).toContain('answer #2');
    expect(describeAnswerError({ kind: 'EQUALS_QUESTION' })).toContain('same as the question');
    expect(describeAnswerWarning({ kind: 'SINGLE_WORD' })).toContain('Tip');
    expect(describeAnswerWarning({ kind: 'SHORT_NUMERIC' })).toContain('Tip');
  });
});

// ──────────────────────────────────────────────────────────────────────
// runCreateFlow — gate at the new validation layer
// ──────────────────────────────────────────────────────────────────────

describe('runCreateFlow — UX hardening gate', () => {
  test('mismatched confirms are rejected before createWallet runs', async () => {
    const r = await runCreateFlow({
      challengeQuestions: Q,
      challengeAnswers: ['Smith', 'Sydney', 'Rover'],
      challengeAnswersConfirm: ['Smith', 'Sidney', 'Rover'], // typo
      contactEmail: 'user@example.com',
      tier1Pin: '1234',
    });
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.error.kind).toBe('BAD_INPUT');
      if (r.error.kind === 'BAD_INPUT') {
        expect(r.error.reason).toContain('answer #2');
      }
    }
  });

  test('duplicate answers across slots are rejected', async () => {
    const r = await runCreateFlow({
      challengeQuestions: Q,
      challengeAnswers: ['Sydney', 'sydney', 'Rover'],
      challengeAnswersConfirm: ['Sydney', 'sydney', 'Rover'],
      contactEmail: 'user@example.com',
      tier1Pin: '1234',
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('BAD_INPUT');
  });

  test('answer equal to question text is rejected', async () => {
    const r = await runCreateFlow({
      challengeQuestions: ['Mother\'s maiden name?', 'City of birth?', 'First pet?'] as [string, string, string],
      challengeAnswers: ["Mother's maiden name?", 'Sydney', 'Rover'],
      challengeAnswersConfirm: ["Mother's maiden name?", 'Sydney', 'Rover'],
      contactEmail: 'user@example.com',
      tier1Pin: '1234',
    });
    expect(r.ok).toBe(false);
  });

  test('confirms matching primary + clean answers → wallet is created', async () => {
    const r = await runCreateFlow({
      challengeQuestions: Q,
      challengeAnswers: ['Smith Jones', 'Sydney Australia', 'Rover Hopkins'],
      challengeAnswersConfirm: ['Smith Jones', 'Sydney Australia', 'Rover Hopkins'],
      contactEmail: 'user@example.com',
      tier1Pin: '1234',
    });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value.recoveryEnvelope.envelopeVersion).toBe(1);
  });
});

// ──────────────────────────────────────────────────────────────────────
// renderPostCreateBanner — DOM picker
// ──────────────────────────────────────────────────────────────────────

class StubTransport implements EnvelopeTransport {
  readonly id: string;
  readonly name: string;
  readonly icon = '⊕';
  calls = 0;
  constructor(id: string, name: string, private readonly result: TransportResult = { ok: true }) {
    this.id = id;
    this.name = name;
  }
  isAvailable(): boolean {
    return true;
  }
  async send(_e: SerializedEnvelope): Promise<TransportResult> {
    this.calls++;
    return this.result;
  }
}

describe('renderPostCreateBanner', () => {
  test('renders one button per transport + runs send() on click', async () => {
    // Minimal document stub with createElement / appendChild / removeAttribute.
    const handlers = new Map<string, () => void>();
    interface FakeEl {
      id: string;
      type?: string;
      textContent: string;
      className: string;
      innerHTML: string;
      disabled: boolean;
      dataset: Record<string, string>;
      style: Record<string, string>;
      children: FakeEl[];
      addEventListener(name: string, fn: () => void): void;
      appendChild(c: FakeEl): void;
      click(): void;
      removeAttribute(_k: string): void;
    }
    const newEl = (): FakeEl => ({
      id: '',
      textContent: '',
      className: '',
      innerHTML: '',
      disabled: false,
      dataset: {},
      style: {},
      children: [],
      addEventListener(name, fn) {
        if (name === 'click') handlers.set(this.id, fn);
      },
      appendChild(c) {
        this.children.push(c);
      },
      click() {
        const h = handlers.get(this.id);
        if (h) h();
      },
      removeAttribute(_k) {
        /* noop */
      },
    });

    const banner = newEl();
    banner.id = 'create-banner';

    const origDoc = (globalThis as Record<string, unknown>).document;
    (globalThis as { document: unknown }).document = {
      createElement: (_t: string) => newEl(),
      getElementById: (_id: string) => banner,
    };

    try {
      const t1 = new StubTransport('test-a', 'Test A');
      const t2 = new StubTransport('test-b', 'Test B');

      // Synthesise a CreateWalletResult skeleton — we only need the
      // recoveryEnvelope shape for the picker.
      const fakeResult = {
        identity: {
          identityPkHex: '02' + 'aa'.repeat(32),
          identitySkEnvelopeHex: '00',
          certIdHex: 'bb'.repeat(32),
          createdAt: 0,
        },
        policy: {
          policyVersion: 1,
          tier1CeilingSats: 0,
          tier2CeilingSats: 0,
          tier3CeilingSats: 0,
          tier1FactorKind: 'pin' as const,
          tier2FactorKind: 'webauthn' as const,
          tier3FactorKind: 'passphrase' as const,
          tier3CooldownSeconds: 0,
        },
        recoveryEnvelope: {
          envelopeVersion: 1 as const,
          identityKey: '02' + 'aa'.repeat(32),
          certId: 'bb'.repeat(32),
          contactEmail: 'u@example.com',
          challengeBundle: {
            questions: ['q1', 'q2', 'q3'],
            salt: 'cc'.repeat(32),
            answerHashes: ['dd'.repeat(32), 'dd'.repeat(32), 'dd'.repeat(32)],
            kdfIterations: 100_000,
          },
          encryptedRecoverySeed: {
            ciphertext: '00'.repeat(64),
            nonce: '11'.repeat(12),
            tag: '22'.repeat(16),
            aad: '33'.repeat(34),
          },
          derivationContexts: [],
          edgeRecipes: [],
          derivationStateSnapshot: { records: [], snapshotTimestamp: '2026-04-27T00:00:00.000Z' },
          algorithmVersion: 1 as const,
        },
      };

      const seen: Array<{ id: string; r: TransportResult }> = [];
      renderPostCreateBanner(fakeResult, {
        transports: [t1, t2],
        element: banner as unknown as HTMLElement,
        onTransportResult: (id, r) => seen.push({ id, r }),
      });

      // Expected children: header <p>, value-cap <p>, backup header <p>,
      // button row <div>. The button row contains the Plexus button +
      // one button per stub transport.
      const buttonRow = banner.children.find((c) => c.className === 'transport-row');
      expect(buttonRow).toBeDefined();
      const buttons = buttonRow!.children.map((c) => c.id);
      expect(buttons).toContain('plexus-enroll-cta');
      expect(buttons).toContain('transport-test-a');
      expect(buttons).toContain('transport-test-b');

      // Plexus (operator-gated, recoverable-only-by-you) is the recommended
      // backup; the local self-custody options carry an explicit risk note.
      const plexusBtn = buttonRow!.children.find((c) => c.id === 'plexus-enroll-cta');
      expect(plexusBtn!.dataset.recommended).toBe('true');
      const riskNote = banner.children.find((c) => c.className === 'backup-risk-note');
      expect(riskNote).toBeDefined();
      expect(riskNote!.dataset.tone).toBe('warn');
      expect(riskNote!.textContent).toBe(LOCAL_BACKUP_WARNING);

      // Click each transport button and verify send() ran.
      buttonRow!.children.find((c) => c.id === 'transport-test-a')!.click();
      buttonRow!.children.find((c) => c.id === 'transport-test-b')!.click();
      // Allow microtasks (button click → async send) to flush.
      await new Promise((r) => setTimeout(r, 5));
      expect(t1.calls).toBe(1);
      expect(t2.calls).toBe(1);
      expect(seen.map((s) => s.id).sort()).toEqual(['test-a', 'test-b']);
    } finally {
      if (origDoc === undefined) {
        delete (globalThis as Record<string, unknown>).document;
      } else {
        (globalThis as { document: unknown }).document = origDoc;
      }
    }
  });
});

```
