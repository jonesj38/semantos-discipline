---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/stub-identity-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.877153+00:00
---

# core/protocol-types/src/adapters/stub-identity-adapter.ts

```ts
/**
 * StubIdentityAdapter — in-memory implementation for dev/test.
 *
 * Does NOT require wallet, network, or running identity service.
 * All identities and keys are deterministic based on input data.
 * Enforces monotonic child_index and full tree semantics.
 *
 * This stub is PERMANENT infrastructure — it is the test harness forever.
 * Do not build it as a temporary thing.
 */

import type { IdentityAdapter, IdentityConfig, IdentityError } from '../identity';
import { makeIdentityError } from '../identity';

/** SHA-256 hex digest of a string. Browser-native via Web Crypto API. */
async function sha256hex(input: string): Promise<string> {
  const encoded = new TextEncoder().encode(input);
  const hashBuffer = await crypto.subtle.digest('SHA-256', encoded);
  const hashArray = new Uint8Array(hashBuffer);
  return Array.from(hashArray).map(b => b.toString(16).padStart(2, '0')).join('');
}

/** Convert hex string to base64 (browser-native, no Buffer dependency). */
function hexToBase64(hex: string): string {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
  }
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

/** Fake PEM public key from a certId (structurally valid, not cryptographically real). */
async function fakePEM(certId: string): Promise<string> {
  const hash = await sha256hex(certId);
  const b64 = hexToBase64(hash);
  return `-----BEGIN PUBLIC KEY-----\n${b64}\n-----END PUBLIC KEY-----`;
}

interface StubIdentity {
  email: string;
  publicKey: string;
  created: number;
  /** Children keyed by childIndex. */
  children: Map<number, {
    certId: string;
    resourceId: string;
    childIndex: number;
  }>;
}

interface StubEdge {
  edgeId: string;
  initiator: string;
  responder: string;
  sharedSecret: string;
}

interface StubRecoverySession {
  sessionId: string;
  email: string;
  challenges: Array<{ id: string; prompt: string; answer: string }>;
  verified: boolean;
}

export class StubIdentityAdapter implements IdentityAdapter {
  private debugLogging: boolean;
  private identities = new Map<string, StubIdentity>();
  private edges = new Map<string, StubEdge>();
  /** Monotonic child index per parent — never decrements, even after deletion. */
  private nextChildIndex = new Map<string, number>();
  private recoverySessions = new Map<string, StubRecoverySession>();

  constructor(config: IdentityConfig) {
    this.debugLogging = config.debugLogging ?? false;
  }

  async registerIdentity(email: string): Promise<{
    certId: string;
    publicKey: string;
  }> {
    if (this.debugLogging) {
      console.log(`[IdentityStub] registerIdentity(${email})`);
    }

    const seed = (await sha256hex(email + ':phase-14-stub')).slice(0, 32);
    const certId = 'cert:' + seed;
    const publicKey = await fakePEM(certId);

    this.identities.set(certId, {
      email,
      publicKey,
      created: Date.now(),
      children: new Map(),
    });

    this.nextChildIndex.set(certId, 0);

    return { certId, publicKey };
  }

  async deriveChild(
    parentCertId: string,
    resourceId: string,
    domainFlag: number,
  ): Promise<{
    certId: string;
    publicKey: string;
    childIndex: number;
  }> {
    if (this.debugLogging) {
      console.log(
        `[IdentityStub] deriveChild(${parentCertId}, ${resourceId}, domainFlag=${domainFlag})`,
      );
    }

    const parent = this.identities.get(parentCertId);
    if (!parent) {
      throw makeIdentityError(
        'CERT_NOT_FOUND',
        `Parent cert_id ${parentCertId} not found`,
        true,
      );
    }

    // Monotonic child_index: get next available, increment for next time
    const childIndex = this.nextChildIndex.get(parentCertId) ?? 0;
    this.nextChildIndex.set(parentCertId, childIndex + 1);

    const seed = (await sha256hex(
      parentCertId + ':' + resourceId + ':' + domainFlag + ':' + childIndex,
    )).slice(0, 32);

    const certId = 'cert:' + seed;
    const publicKey = await fakePEM(certId);

    // Record child under parent
    parent.children.set(childIndex, {
      certId,
      resourceId,
      childIndex,
    });

    // Register child as an identity (so it can have its own children)
    this.identities.set(certId, {
      email: parent.email,
      publicKey,
      created: Date.now(),
      children: new Map(),
    });

    this.nextChildIndex.set(certId, 0);

    return { certId, publicKey, childIndex };
  }

  async resolveIdentity(certId: string): Promise<{
    certId: string;
    publicKey: string;
    email?: string;
    created: number;
    updated: number;
    children?: Array<{ certId: string; childIndex: number; resourceId: string }>;
  }> {
    if (this.debugLogging) {
      console.log(`[IdentityStub] resolveIdentity(${certId})`);
    }

    const identity = this.identities.get(certId);
    if (!identity) {
      throw makeIdentityError(
        'CERT_NOT_FOUND',
        `Identity ${certId} not found`,
        true,
      );
    }

    const children = Array.from(identity.children.values());

    return {
      certId,
      publicKey: identity.publicKey,
      email: identity.email,
      created: identity.created,
      updated: Date.now(),
      children,
    };
  }

  async createEdge(
    initiatorCertId: string,
    responderCertId: string,
  ): Promise<{
    edgeId: string;
    sharedSecret: string;
  }> {
    if (this.debugLogging) {
      console.log(
        `[IdentityStub] createEdge(${initiatorCertId}, ${responderCertId})`,
      );
    }

    const initiator = this.identities.get(initiatorCertId);
    const responder = this.identities.get(responderCertId);

    if (!initiator || !responder) {
      throw makeIdentityError(
        'CERT_NOT_FOUND',
        'One or both certs not found',
        true,
      );
    }

    const sharedSecret = await sha256hex(initiatorCertId + ':' + responderCertId);
    const edgeId = 'edge:' + sharedSecret.slice(0, 32);

    this.edges.set(edgeId, {
      edgeId,
      initiator: initiatorCertId,
      responder: responderCertId,
      sharedSecret,
    });

    return { edgeId, sharedSecret };
  }

  async querySubtree(rootCertId: string, depth: number): Promise<{
    root: string;
    children: Array<{
      certId: string;
      childIndex: number;
      resourceId: string;
      grandchildren?: Array<{
        certId: string;
        childIndex: number;
        resourceId: string;
      }>;
    }>;
  }> {
    if (this.debugLogging) {
      console.log(`[IdentityStub] querySubtree(${rootCertId}, depth=${depth})`);
    }

    const root = this.identities.get(rootCertId);
    if (!root) {
      throw makeIdentityError(
        'CERT_NOT_FOUND',
        `Root cert_id ${rootCertId} not found`,
        true,
      );
    }

    const children = Array.from(root.children.values());

    if (depth <= 1) {
      return { root: rootCertId, children };
    }

    // Recursively fetch grandchildren
    const childrenWithGrandchildren = await Promise.all(
      children.map(async (child) => {
        const subtree = await this.querySubtree(child.certId, depth - 1);
        return {
          ...child,
          grandchildren: subtree.children.map((gc) => ({
            certId: gc.certId,
            childIndex: gc.childIndex,
            resourceId: gc.resourceId,
          })),
        };
      }),
    );

    return { root: rootCertId, children: childrenWithGrandchildren };
  }

  async presentCapability(
    certId: string,
    capabilityId: string,
  ): Promise<{
    valid: boolean;
    reason?: string;
  }> {
    if (this.debugLogging) {
      console.log(
        `[IdentityStub] presentCapability(${certId}, ${capabilityId})`,
      );
    }

    // Stub mode: all capabilities are valid
    return { valid: true };
  }

  async initiateRecovery(email: string): Promise<{
    sessionId: string;
    challengeCount: number;
    challenges?: Array<{ id: string; prompt: string }>;
  }> {
    if (this.debugLogging) {
      console.log(`[IdentityStub] initiateRecovery(${email})`);
    }

    // Deterministic session ID from email
    const sessionId = 'session:' + (await sha256hex('recovery:' + email)).slice(0, 32);

    const challenges = [
      { id: 'c1', prompt: 'What is your email?', answer: email },
      { id: 'c2', prompt: 'What is 2 + 2?', answer: '4' },
      { id: 'c3', prompt: 'True or false: Plexus is a graph?', answer: 'true' },
      { id: 'c4', prompt: 'What is the meaning of life?', answer: '42' },
    ];

    this.recoverySessions.set(sessionId, {
      sessionId,
      email,
      challenges,
      verified: false,
    });

    return {
      sessionId,
      challengeCount: challenges.length,
      challenges: challenges.map(({ id, prompt }) => ({ id, prompt })),
    };
  }

  async submitChallengeAnswers(
    sessionId: string,
    answers: Array<{ challengeId: string; answer: string }>,
  ): Promise<{
    verified: boolean;
    exportPayload?: string;
  }> {
    if (this.debugLogging) {
      console.log(`[IdentityStub] submitChallengeAnswers(${sessionId})`);
    }

    const session = this.recoverySessions.get(sessionId);
    if (!session) {
      throw makeIdentityError(
        'SESSION_NOT_FOUND',
        `Recovery session ${sessionId} not found`,
        true,
      );
    }

    // Check each answer against stored challenges
    const verified = answers.every((answer) => {
      const challenge = session.challenges.find((c) => c.id === answer.challengeId);
      return challenge && challenge.answer === answer.answer;
    });

    if (!verified) {
      return { verified: false };
    }

    session.verified = true;

    // Deterministic export payload (browser-native, no Buffer dependency)
    const exportPayload = btoa(
      JSON.stringify({
        sessionId,
        email: session.email,
        recoveredAt: session.challenges.length,
        recoveryToken: await sha256hex('token:' + sessionId),
      }),
    );

    return { verified: true, exportPayload };
  }

  async sendAuthenticated(
    senderCertId: string,
    receiverCertId: string,
    payload: Record<string, string>,
  ): Promise<{ messageId: string }> {
    if (this.debugLogging) {
      console.log(
        `[IdentityStub] sendAuthenticated(${senderCertId} → ${receiverCertId})`,
      );
      // Log payload keys only — never log values (may contain sensitive data)
      console.log(`[IdentityStub]   payload keys: ${Object.keys(payload).join(', ')}`);
    }

    const messageId = 'msg:' + (await sha256hex(
      senderCertId + ':' + receiverCertId + ':' + JSON.stringify(payload),
    )).slice(0, 32);

    return { messageId };
  }

  /**
   * L11 substrate-side port — deterministic STUB implementation for
   * tests. Returns a 66-char hex pubkey-shaped value derived from the
   * inputs via SHA-256.
   *
   * NOT REAL CURVE MATH — this stub doesn't claim to produce a key
   * that's a valid secp256k1 point. The structural contract (66-char
   * lowercase hex starting with `02` or `03`, deterministic for the
   * same inputs) is preserved so caller-side tests can exercise the
   * adapter surface without depending on @bsv/sdk.
   *
   * Real implementations (LocalIdentityAdapter, brain-side) use the
   * L11 primitive deriveSegmentPub for byte-equal-to-priv-side output.
   */
  async deriveSegmentPublicKey(
    parentPubKeyHex: string,
    segment: Uint8Array | string,
  ): Promise<{ childPubKeyHex: string }> {
    if (typeof parentPubKeyHex !== 'string' || !/^[0-9a-f]{66}$/.test(parentPubKeyHex)) {
      throw new Error(
        `deriveSegmentPublicKey: parentPubKeyHex must be 66-char lowercase hex SEC1 compressed (got ${parentPubKeyHex.length} chars)`,
      );
    }
    const segmentHex =
      typeof segment === 'string'
        ? Buffer.from(segment, 'utf8').toString('hex')
        : Buffer.from(segment).toString('hex');
    const digest = await sha256hex(parentPubKeyHex + ':' + segmentHex);
    // Take 64 hex chars of the digest as the "x-coordinate" + prefix
    // with a stub compressed marker (`02` or `03`) derived from the
    // last byte's parity. Doesn't matter that this isn't on-curve —
    // it's only the stub.
    const xHex = digest.slice(0, 64);
    const prefix = parseInt(digest.slice(62, 64), 16) & 1 ? '03' : '02';
    const childPubKeyHex = prefix + xHex;
    if (this.debugLogging) {
      console.log(
        `[IdentityStub] deriveSegmentPublicKey(parent=${parentPubKeyHex.slice(0, 8)}..., segment=${segmentHex.slice(0, 16)}...) → ${childPubKeyHex.slice(0, 16)}...`,
      );
    }
    return { childPubKeyHex };
  }

  /**
   * Stub of the L11.5 domain-separated derivation. Deterministic and
   * distinct per (domainFlag, segment) — folds the u32 flag into the digest
   * input. NOT on-curve / NOT byte-equal to the real primitive; stub only.
   */
  async deriveDomainSegmentPublicKey(
    parentPubKeyHex: string,
    domainFlag: number,
    segment: Uint8Array | string,
  ): Promise<{ childPubKeyHex: string }> {
    if (typeof parentPubKeyHex !== 'string' || !/^[0-9a-f]{66}$/.test(parentPubKeyHex)) {
      throw new Error(
        `deriveDomainSegmentPublicKey: parentPubKeyHex must be 66-char lowercase hex SEC1 compressed (got ${parentPubKeyHex.length} chars)`,
      );
    }
    if (!Number.isInteger(domainFlag) || domainFlag < 0 || domainFlag > 0xffff_ffff) {
      throw new Error(`deriveDomainSegmentPublicKey: domainFlag must be a u32 (got ${domainFlag})`);
    }
    const segmentHex =
      typeof segment === 'string'
        ? Buffer.from(segment, 'utf8').toString('hex')
        : Buffer.from(segment).toString('hex');
    const flagHex = (domainFlag >>> 0).toString(16).padStart(8, '0');
    const digest = await sha256hex(parentPubKeyHex + ':' + flagHex + ':' + segmentHex);
    const xHex = digest.slice(0, 64);
    const prefix = parseInt(digest.slice(62, 64), 16) & 1 ? '03' : '02';
    const childPubKeyHex = prefix + xHex;
    if (this.debugLogging) {
      console.log(
        `[IdentityStub] deriveDomainSegmentPublicKey(parent=${parentPubKeyHex.slice(0, 8)}..., flag=0x${flagHex}, segment=${segmentHex.slice(0, 16)}...) → ${childPubKeyHex.slice(0, 16)}...`,
      );
    }
    return { childPubKeyHex };
  }
}

```
