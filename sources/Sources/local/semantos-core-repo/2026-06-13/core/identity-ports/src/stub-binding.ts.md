---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/identity-ports/src/stub-binding.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.943645+00:00
---

# core/identity-ports/src/stub-binding.ts

```ts
/**
 * In-memory stub binding for the four identity ports.
 *
 * Used by:
 *   - test cases that need a deterministic identity surface without
 *     spinning up SQLite or hitting the BSV crypto path
 *   - the cube demo (apps/cube-demo, PR-B) — exercises the full
 *     port surface end-to-end with no external dependencies
 *
 * Determinism: every output is a pure function of inputs. `certId`s are
 * `sha256`-shaped hex strings (we use a tiny hex-formatted hash here — NOT a
 * real SHA-256, just a stable 32-byte-looking string keyed off the input).
 * Public keys are `04`-prefixed-looking but are NOT real secp256k1 — they're
 * marker strings starting with `stubpk:`.
 *
 * Why "fake" keys: the stub explicitly does not attempt to be a partial
 * BRC-42 implementation. Tests that need real crypto contracts should bind
 * the vendor-sdk binding instead (which calls into `@plexus/vendor-sdk`).
 * The stub's contract is "shape-correct, deterministic, fast" — that's it.
 *
 * Anything that would do work in production (SPV checks, BRC-108 minting,
 * BRC-100 signed exports) returns a marker payload with `verified: 'stub'`
 * or `verifier: 'stub'` so downstream code can detect the non-production
 * binding.
 */

import type { ChallengeAnswer, ChallengeSpec, EdgeRecoveryPolicy, PlexusCert } from '@plexus/contracts';

import type {
  AttestationPort,
  CapabilityPort,
  CapabilityType,
  ChildDerivation,
  ChildNodeRef,
  EconomicPort,
  EdgeCreation,
  IdentityPort,
  IdentityRegistration,
  IdentityResolution,
  PaymentVerification,
  RecoveryInitiation,
  RecoveryPort,
  RecoveryVerdict,
  SPVAttestation,
  SignSpendInput,
  SignedSpend,
  SubtreeQuery,
} from './types.js';
import type { IdentityPortBundle } from './ports.js';

// ─── deterministic helpers ────────────────────────────────────────────────

/** Tiny FNV-1a-style 64-bit-ish hash, formatted as 64 hex chars. NOT secure. */
function stubHash(input: string): string {
  let h1 = 0xcbf29ce4n;
  let h2 = 0x84222325n;
  for (let i = 0; i < input.length; i++) {
    h1 ^= BigInt(input.charCodeAt(i));
    h1 = (h1 * 0x100000001b3n) & 0xffffffffffffffffn;
    h2 ^= BigInt(input.charCodeAt(i) * 31);
    h2 = (h2 * 0x100000001b3n) & 0xffffffffffffffffn;
  }
  const part = (n: bigint): string => n.toString(16).padStart(16, '0');
  // 64 hex chars (32 bytes) — same shape as a real SHA-256 result.
  return `${part(h1)}${part(h2)}${part(h1 ^ h2)}${part(h2 ^ 0xdeadbeefn)}`;
}

function stubPubKey(seed: string): string {
  // 33-byte (66 hex char) compressed-pubkey-shaped string. Prefix `02` makes
  // it pass shape checks but the body is `stubpk:` followed by hash hex.
  return `02${'stubpk00'}${stubHash(seed).slice(0, 50)}`;
}

// ─── in-memory store ──────────────────────────────────────────────────────

interface StubCertRow {
  certId: string;
  publicKey: string;
  email: string | null;
  parentCertId: string | null;
  childIndex: number;
  resourceId: string | null;
  domainFlag: number | null;
  derivationPath: string;
  createdAt: number;
}

interface StubEdgeRow {
  edgeId: string;
  initiatorCertId: string;
  responderCertId: string;
  /** Per §2.5.5 — BKDS invoiceNumber only; shared secret is never stored. */
  signingKeyIndex: number;
  recoveryPolicy: EdgeRecoveryPolicy;
  createdAt: number;
}

interface StubRecoveryRow {
  sessionId: string;
  email: string;
  challenges: ChallengeSpec[];
  expectedAnswers: Record<string, string>; // challengeId -> normalized expected answer
  verified: boolean;
}

interface StubCapabilityRow {
  capabilityId: string;
  certId: string;
  capType: CapabilityType;
  consumed: boolean;
}

interface StubSpendRow {
  txAnchor: string;
  payerCertId: string;
  targetId: string;
  amount: number;
  currency: string;
  signedAt: number;
}

export interface StubStore {
  certs: Map<string, StubCertRow>;
  childIndices: Map<string, number>; // key = parentCertId, value = next child index
  certsByEmail: Map<string, string>; // email -> certId
  edges: Map<string, StubEdgeRow>;
  /** Monotonic counter for BKDS signing key indices. Per §2.5.5 — never stores the secret. */
  nextSigningKeyIndex: number;
  recoverySessions: Map<string, StubRecoveryRow>;
  capabilities: Map<string, StubCapabilityRow>;
  /** Spend ledger keyed by `txAnchor`. Populated by `economicPort.signSpend`. */
  spends: Map<string, StubSpendRow>;
  /** Wall-clock fn — overridable so tests can pin `createdAt`. */
  now: () => number;
}

export interface StubBindingOptions {
  /** Seed material for deterministic hashing prefixes. Defaults to `'stub'`. */
  namespace?: string;
  /** Override clock; defaults to `Date.now`. */
  now?: () => number;
  /**
   * Pre-seed challenge questions for the recovery flow. If omitted, the stub
   * uses a fixed default set (3 questions, all answered "yes"). Tests that
   * exercise the failure path should provide their own.
   */
  defaultChallenges?: { challenges: ChallengeSpec[]; answers: Record<string, string> };
}

const DEFAULT_CHALLENGES: ChallengeSpec[] = [
  { id: 'q1', prompt: 'stub-q1' },
  { id: 'q2', prompt: 'stub-q2' },
  { id: 'q3', prompt: 'stub-q3' },
];

const DEFAULT_ANSWERS: Record<string, string> = {
  q1: 'yes',
  q2: 'yes',
  q3: 'yes',
};

// ─── error helpers ────────────────────────────────────────────────────────

export class StubIdentityError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.name = 'StubIdentityError';
    this.code = code;
  }
}

function notImpl(method: string): never {
  throw new StubIdentityError(
    'NOT_IMPLEMENTED',
    `${method} is not implemented in the stub binding. Bind the vendor-sdk binding (or wait for PR-C / Plexus availability) to exercise this path.`,
  );
}

// ─── factory ──────────────────────────────────────────────────────────────

/**
 * Build a fresh stub bundle. Each call returns a new isolated store —
 * tests should typically create one per `describe` block to avoid
 * cross-test bleed.
 */
export function makeStubBindings(options: StubBindingOptions = {}): {
  bundle: IdentityPortBundle;
  store: StubStore;
} {
  const namespace = options.namespace ?? 'stub';
  const now = options.now ?? Date.now;
  const defaults = options.defaultChallenges ?? {
    challenges: DEFAULT_CHALLENGES,
    answers: DEFAULT_ANSWERS,
  };

  const store: StubStore = {
    certs: new Map(),
    childIndices: new Map(),
    certsByEmail: new Map(),
    edges: new Map(),
    nextSigningKeyIndex: 0,
    recoverySessions: new Map(),
    capabilities: new Map(),
    spends: new Map(),
    now,
  };

  // ─── identityPort impl ─────────────────────────────────────────────────

  const identity: IdentityPort = {
    registerIdentity(email: string): IdentityRegistration {
      const existing = store.certsByEmail.get(email);
      if (existing) {
        const row = store.certs.get(existing)!;
        return { certId: row.certId, publicKey: row.publicKey };
      }
      const certId = stubHash(`${namespace}:identity:${email}`);
      const publicKey = stubPubKey(`${namespace}:pk:${email}`);
      const row: StubCertRow = {
        certId,
        publicKey,
        email,
        parentCertId: null,
        childIndex: -1,
        resourceId: null,
        domainFlag: null,
        derivationPath: 'root',
        createdAt: now(),
      };
      store.certs.set(certId, row);
      store.certsByEmail.set(email, certId);
      return { certId, publicKey };
    },

    resolveIdentity(certId: string): IdentityResolution {
      const row = store.certs.get(certId);
      if (!row) {
        throw new StubIdentityError('CERT_NOT_FOUND', `cert ${certId} not registered in stub store`);
      }
      const children: ChildNodeRef[] = [];
      for (const c of store.certs.values()) {
        if (c.parentCertId === certId) {
          children.push({
            certId: c.certId,
            childIndex: c.childIndex,
            resourceId: c.resourceId ?? '',
          });
        }
      }
      children.sort((a, b) => a.childIndex - b.childIndex);
      return {
        certId: row.certId,
        publicKey: row.publicKey,
        email: row.email ?? undefined,
        created: row.createdAt,
        updated: now(),
        children,
      };
    },

    deriveChild(parentCertId: string, resourceId: string, domainFlag: number): ChildDerivation {
      const parent = store.certs.get(parentCertId);
      if (!parent) {
        throw new StubIdentityError(
          'CERT_NOT_FOUND',
          `parent cert ${parentCertId} not registered in stub store`,
        );
      }
      const next = (store.childIndices.get(parentCertId) ?? 0);
      store.childIndices.set(parentCertId, next + 1);

      const certId = stubHash(`${namespace}:child:${parentCertId}:${resourceId}:${domainFlag}:${next}`);
      const publicKey = stubPubKey(`${namespace}:childpk:${parentCertId}:${resourceId}:${domainFlag}:${next}`);
      const row: StubCertRow = {
        certId,
        publicKey,
        email: null,
        parentCertId,
        childIndex: next,
        resourceId,
        domainFlag,
        derivationPath: `${parent.derivationPath}/${resourceId}:${domainFlag}:${next}`,
        createdAt: now(),
      };
      store.certs.set(certId, row);
      return { certId, publicKey, childIndex: next };
    },

    createEdge(
      initiatorCertId: string,
      responderCertId: string,
      edgeRecoveryPolicy: EdgeRecoveryPolicy = 'NONE',
    ): EdgeCreation {
      if (!store.certs.has(initiatorCertId) || !store.certs.has(responderCertId)) {
        throw new StubIdentityError('CERT_NOT_FOUND', 'one or both edge participants are not registered');
      }
      const edgeId = stubHash(`${namespace}:edge:${initiatorCertId}:${responderCertId}`);
      // Per §2.5.5: assign a monotonic BKDS signing key index — never compute or
      // store the shared secret itself. The client re-derives the secret locally.
      const signingKeyIndex = store.nextSigningKeyIndex++;
      const row: StubEdgeRow = {
        edgeId,
        initiatorCertId,
        responderCertId,
        signingKeyIndex,
        recoveryPolicy: edgeRecoveryPolicy,
        createdAt: now(),
      };
      store.edges.set(edgeId, row);
      return { edgeId, signingKeyIndex };
    },

    querySubtree(rootCertId: string, depth: number): SubtreeQuery {
      const root = store.certs.get(rootCertId);
      if (!root) {
        throw new StubIdentityError('CERT_NOT_FOUND', `root cert ${rootCertId} not registered`);
      }
      const directChildren: ChildNodeRef[] = [];
      for (const c of store.certs.values()) {
        if (c.parentCertId === rootCertId) {
          directChildren.push({
            certId: c.certId,
            childIndex: c.childIndex,
            resourceId: c.resourceId ?? '',
          });
        }
      }
      directChildren.sort((a, b) => a.childIndex - b.childIndex);

      if (depth <= 1) {
        return { root: rootCertId, children: directChildren };
      }
      const withGrand = directChildren.map((child) => {
        const grand: ChildNodeRef[] = [];
        for (const c of store.certs.values()) {
          if (c.parentCertId === child.certId) {
            grand.push({
              certId: c.certId,
              childIndex: c.childIndex,
              resourceId: c.resourceId ?? '',
            });
          }
        }
        grand.sort((a, b) => a.childIndex - b.childIndex);
        return { ...child, grandchildren: grand };
      });
      return { root: rootCertId, children: withGrand };
    },

    getCert(certId: string): PlexusCert | null {
      const row = store.certs.get(certId);
      if (!row) return null;
      return {
        certId: row.certId,
        publicKey: row.publicKey,
        email: row.email ?? undefined,
        parentCertId: row.parentCertId,
        childIndex: row.childIndex,
        resourceId: row.resourceId ?? undefined,
        domainFlag: row.domainFlag ?? undefined,
        derivationPath: row.derivationPath,
        createdAt: row.createdAt,
      };
    },
  };

  // ─── recoveryPort impl ─────────────────────────────────────────────────

  const recovery: RecoveryPort = {
    initiateRecovery(email: string): RecoveryInitiation {
      const sessionId = stubHash(`${namespace}:recovery:${email}`);
      const row: StubRecoveryRow = {
        sessionId,
        email,
        challenges: [...defaults.challenges],
        expectedAnswers: { ...defaults.answers },
        verified: false,
      };
      store.recoverySessions.set(sessionId, row);
      return {
        sessionId,
        challengeCount: row.challenges.length,
        challenges: row.challenges,
      };
    },

    submitChallengeAnswers(sessionId: string, answers: readonly ChallengeAnswer[]): RecoveryVerdict {
      const session = store.recoverySessions.get(sessionId);
      if (!session) {
        throw new StubIdentityError('SESSION_NOT_FOUND', `recovery session ${sessionId} unknown`);
      }
      const allCorrect = answers.every((a) => {
        const expected = session.expectedAnswers[a.challengeId];
        if (expected === undefined) return false;
        return expected.toLowerCase().trim() === a.answer.toLowerCase().trim();
      });
      if (!allCorrect) {
        return { verified: false };
      }
      session.verified = true;
      // The "export payload" is a marker — real impl returns a base64 JSON blob
      // signed by the Plexus RaaS authority key. Stub just embeds the session
      // shape so consumers can detect the non-production binding.
      const exportPayload = btoa(
        JSON.stringify({
          stub: true,
          sessionId,
          email: session.email,
          recoveredAt: store.now(),
        }),
      );
      return { verified: true, exportPayload };
    },
  };

  // ─── attestationPort impl ──────────────────────────────────────────────

  function makeAttestation(certId: string, kind: SPVAttestation['kind']): SPVAttestation {
    if (!store.certs.has(certId)) {
      throw new StubIdentityError('CERT_NOT_FOUND', `cannot attest unknown cert ${certId}`);
    }
    return {
      certId,
      kind,
      signature: stubHash(`${namespace}:attest:${kind}:${certId}`),
      attestorPublicKey: stubPubKey(`${namespace}:raas-attestor`),
      generatedAt: store.now(),
      verified: 'stub',
    };
  }

  const attestation: AttestationPort = {
    proveContinuity: async (certId) => makeAttestation(certId, 'continuity'),
    proveEdgePresence: async (certId, _edgeType) => makeAttestation(certId, 'edge_presence'),
    proveAppPresence: async (certId, _resourceId) => makeAttestation(certId, 'app_presence'),
  };

  // ─── capabilityPort impl ───────────────────────────────────────────────

  const capability: CapabilityPort = {
    present(certId: string, capabilityId: string) {
      const row = store.capabilities.get(capabilityId);
      if (!row) {
        return { valid: false, reason: 'unknown_capability', verifier: 'stub' };
      }
      if (row.certId !== certId) {
        return { valid: false, reason: 'cert_mismatch', verifier: 'stub' };
      }
      if (row.consumed) {
        return { valid: false, reason: 'already_consumed', verifier: 'stub' };
      }
      return { valid: true, verifier: 'stub' };
    },
  };

  // ─── economicPort impl ─────────────────────────────────────────────────

  const economic: EconomicPort = {
    async signSpend(input: SignSpendInput): Promise<SignedSpend> {
      if (input.amount <= 0) {
        throw new StubIdentityError(
          'INVALID_AMOUNT',
          `signSpend: amount must be positive, got ${input.amount}`,
        );
      }
      const txAnchor = stubHash(
        `${namespace}:spend:${input.payerCertId}:${input.targetId}:${input.amount}:${input.currency}:${store.spends.size}`,
      );
      store.spends.set(txAnchor, {
        txAnchor,
        payerCertId: input.payerCertId,
        targetId: input.targetId,
        amount: input.amount,
        currency: input.currency,
        signedAt: store.now(),
      });
      return {
        txAnchor,
        amount: input.amount,
        currency: input.currency,
        verifier: 'stub',
      };
    },
    async verifyPayment(input): Promise<PaymentVerification> {
      const row = store.spends.get(input.txAnchor);
      if (!row) {
        return { valid: false, reason: 'unknown_anchor', verifier: 'stub' };
      }
      if (row.amount < input.amount) {
        return { valid: false, reason: 'amount_short', verifier: 'stub' };
      }
      if (row.currency !== input.currency) {
        return { valid: false, reason: 'currency_mismatch', verifier: 'stub' };
      }
      return { valid: true, verifier: 'stub' };
    },
  };

  return {
    bundle: { identity, recovery, attestation, capability, economic },
    store,
  };
}

// ─── test helpers ─────────────────────────────────────────────────────────

/**
 * Helper for tests/demos that need to seed a capability without going
 * through a real mint flow. Direct write into the stub store.
 */
export function seedStubCapability(
  store: StubStore,
  capabilityId: string,
  certId: string,
  capType: CapabilityType,
): void {
  store.capabilities.set(capabilityId, {
    capabilityId,
    certId,
    capType,
    consumed: false,
  });
}

/** Mark a stub capability as consumed (for testing the post-consume path). */
export function consumeStubCapability(store: StubStore, capabilityId: string): void {
  const row = store.capabilities.get(capabilityId);
  if (row) row.consumed = true;
}

/** Re-export the not-implemented helper so adapter wrappers can call it consistently. */
export { notImpl as throwNotImplemented };

```
