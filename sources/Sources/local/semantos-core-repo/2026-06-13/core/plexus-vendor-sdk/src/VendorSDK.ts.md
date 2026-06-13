---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-vendor-sdk/src/VendorSDK.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.018463+00:00
---

# core/plexus-vendor-sdk/src/VendorSDK.ts

```ts
/**
 * VendorSDK — client-side DAG management.
 *
 * Local stand-in for Dusk Inc's @plexus/vendor-sdk.
 * Uses @bsv/sdk for cryptographic operations and bun:sqlite for persistence.
 *
 * Key design: No private keys are stored. All keys are re-derived
 * deterministically from the root seed via stored derivation paths.
 *
 * Two derivation surfaces, two specialisations of the EP3259724B1 foundation
 * (CW Lift L11):
 *   - Nodes (the identity DAG) are UNILATERAL — derived via `deriveNodeKey`
 *     (canonical kdf-v2 = `deriveSegment`; legacy kdf-v1 = BRC-42 self-derive).
 *   - Edges (relationships) are BILATERAL — derived via real ECDH; see
 *     `createEdge`. BRC-42 is load-bearing there, not for nodes.
 */

import type { PlexusCert, ChallengeSpec } from '@plexus/contracts';
import PublicKey from '@bsv/sdk/primitives/PublicKey';
import { PlexusStore } from './store';
import {
  deriveRootKey,
  deriveNodeKey,
  DEFAULT_KDF_VERSION,
  type KdfVersion,
  computeCertId,
  computeSharedSecret,
  compressedPubKeyHex,
  sha256hex,
  buildRootPreimage,
  buildChildPreimage,
} from './crypto';
import type PrivateKey from '@bsv/sdk/primitives/PrivateKey';

export interface VendorSDKConfig {
  /** Path to SQLite database file. Use ':memory:' for in-memory. */
  dbPath?: string;
  /** Salt for PBKDF2 root key derivation. Fixed for determinism. */
  salt?: string;
  /** Number of PBKDF2 iterations. Default 100000. Use lower values for tests. */
  pbkdf2Iterations?: number;
  /**
   * KDF algorithm version for NEW trees minted by this instance. Defaults to
   * the canonical 'plexus-kdf-v2' (EP3259724B1 `deriveSegment`). Existing trees
   * always replay under the version stored on their root cert, so this only
   * affects roots created via `registerIdentity` here.
   */
  kdfVersion?: KdfVersion;
}

export class VendorSDK {
  private store: PlexusStore;
  private salt: string;
  private pbkdf2Iterations: number;
  private kdfVersion: KdfVersion;

  constructor(config: VendorSDKConfig = {}) {
    this.store = new PlexusStore(config.dbPath);
    this.salt = config.salt ?? 'plexus-local-v1';
    this.pbkdf2Iterations = config.pbkdf2Iterations ?? 100_000;
    this.kdfVersion = config.kdfVersion ?? DEFAULT_KDF_VERSION;
  }

  /**
   * The KDF version a tree was minted under. Read from the root cert; a NULL
   * (pre-migration / legacy) value means the tree predates the L11 reframe and
   * must replay under 'plexus-kdf-v1'. Never default a legacy tree to v2 — that
   * would derive different keys and break recovery.
   */
  private treeVersion(email: string): KdfVersion {
    const root = this.store.getRootByEmail(email);
    return (root?.kdf_version as KdfVersion | undefined) ?? 'plexus-kdf-v1';
  }

  /**
   * Re-derive a private key from root given a derivation path.
   * Path format: "root" for root key, "root/invoiceNum1/invoiceNum2/..." for descendants.
   */
  private rederiveKey(email: string, derivationPath: string): PrivateKey {
    const rootKey = deriveRootKey(email, this.salt, this.pbkdf2Iterations);
    if (derivationPath === 'root') return rootKey;

    const segments = derivationPath.split('/').slice(1); // skip "root"
    const version = this.treeVersion(email);
    let currentKey = rootKey;
    for (const segment of segments) {
      // Unilateral node derivation — replay under the tree's minted KDF version.
      currentKey = deriveNodeKey(currentKey, segment, version);
    }
    return currentKey;
  }

  /**
   * Find the root email for any cert by walking up the parent chain.
   */
  private findRootEmail(certId: string): string {
    let current = this.store.getCertificate(certId);
    while (current) {
      if (current.email && !current.parent_cert_id) return current.email;
      if (!current.parent_cert_id) break;
      current = this.store.getCertificate(current.parent_cert_id);
    }
    throw { code: 'CERT_NOT_FOUND', message: `Cannot find root email for cert ${certId}`, recoverable: true };
  }

  registerIdentity(email: string): { certId: string; publicKey: string } {
    // Check if already registered — return existing cert for determinism
    const existing = this.store.getRootByEmail(email);
    if (existing) {
      return { certId: existing.cert_id, publicKey: existing.public_key };
    }

    const rootKey = deriveRootKey(email, this.salt, this.pbkdf2Iterations);
    const pubKey = rootKey.toPublicKey();
    const publicKeyHex = compressedPubKeyHex(pubKey);
    const preimage = buildRootPreimage(publicKeyHex, email);
    const certId = computeCertId(preimage);

    this.store.insertCertificate({
      cert_id: certId,
      parent_cert_id: null,
      email,
      public_key: publicKeyHex,
      child_index: -1,
      resource_id: null,
      domain_flag: null,
      derivation_path: 'root',
      created_at: Date.now(),
      kdf_version: this.kdfVersion,
    });

    return { certId, publicKey: publicKeyHex };
  }

  resolveIdentity(certId: string): {
    certId: string;
    publicKey: string;
    email?: string;
    created: number;
    updated: number;
    children?: Array<{ certId: string; childIndex: number; resourceId: string }>;
  } {
    const cert = this.store.getCertificate(certId);
    if (!cert) {
      throw { code: 'CERT_NOT_FOUND', message: `Identity ${certId} not found`, recoverable: true };
    }

    const children = this.store.getChildren(certId).map(c => ({
      certId: c.cert_id,
      childIndex: c.child_index,
      resourceId: c.resource_id ?? '',
    }));

    return {
      certId: cert.cert_id,
      publicKey: cert.public_key,
      email: cert.email ?? undefined,
      created: cert.created_at,
      updated: Date.now(),
      children,
    };
  }

  deriveChild(
    parentCertId: string,
    resourceId: string,
    domainFlag: number,
  ): { certId: string; publicKey: string; childIndex: number } {
    const parent = this.store.getCertificate(parentCertId);
    if (!parent) {
      throw { code: 'CERT_NOT_FOUND', message: `Parent cert_id ${parentCertId} not found`, recoverable: true };
    }

    // Monotonic child index
    const childIndex = this.store.incrementChildIndex(parentCertId);

    // Re-derive parent's private key
    const email = this.findRootEmail(parentCertId);
    const version = this.treeVersion(email);
    const parentPrivKey = this.rederiveKey(email, parent.derivation_path);

    // Unilateral node derivation (EP3259724B1 `deriveSegment` under kdf-v2;
    // legacy BRC-42 self-derivation under kdf-v1). No counterparty — not an edge.
    const invoiceNumber = `${resourceId}:${domainFlag}:${childIndex}`;
    const childPrivKey = deriveNodeKey(parentPrivKey, invoiceNumber, version);
    const childPubKey = childPrivKey.toPublicKey();
    const childPubKeyHex = compressedPubKeyHex(childPubKey);

    const preimage = buildChildPreimage(
      childPubKeyHex, parent.public_key, resourceId, domainFlag, childIndex,
    );
    const certId = computeCertId(preimage);
    const derivationPath = `${parent.derivation_path}/${invoiceNumber}`;

    this.store.insertCertificate({
      cert_id: certId,
      parent_cert_id: parentCertId,
      email: null,
      public_key: childPubKeyHex,
      child_index: childIndex,
      resource_id: resourceId,
      domain_flag: domainFlag,
      derivation_path: derivationPath,
      created_at: Date.now(),
      kdf_version: version,
    });

    return { certId, publicKey: childPubKeyHex, childIndex };
  }

  createEdge(
    initiatorCertId: string,
    responderCertId: string,
  ): { edgeId: string; sharedSecret: string } {
    const initiator = this.store.getCertificate(initiatorCertId);
    const responder = this.store.getCertificate(responderCertId);

    if (!initiator || !responder) {
      throw { code: 'CERT_NOT_FOUND', message: 'One or both certs not found', recoverable: true };
    }

    // Re-derive initiator's private key for ECDH
    const email = this.findRootEmail(initiatorCertId);
    const initiatorPrivKey = this.rederiveKey(email, initiator.derivation_path);

    // Import responder's public key
    const responderPubKey = PublicKey.fromString(responder.public_key);

    // BILATERAL specialisation: a genuine two-party ECDH shared secret. This is
    // the surface where BRC-42 is the correct primitive (vs. node derivation,
    // which is unilateral and uses deriveSegment). The secret is never stored —
    // only its hash, per the edge-recovery (BRC-69 recipe) model.
    const sharedSecret = computeSharedSecret(initiatorPrivKey, responderPubKey);

    // Edge ID is SHA-256 of the two cert IDs (directional)
    const edgeId = sha256hex(`${initiatorCertId}:${responderCertId}`);

    this.store.insertEdge({
      edge_id: edgeId,
      initiator_cert_id: initiatorCertId,
      responder_cert_id: responderCertId,
      shared_secret_hash: sharedSecret,
      created_at: Date.now(),
    });

    return { edgeId, sharedSecret };
  }

  querySubtree(
    rootCertId: string,
    depth: number,
  ): {
    root: string;
    children: Array<{
      certId: string;
      childIndex: number;
      resourceId: string;
      grandchildren?: Array<{ certId: string; childIndex: number; resourceId: string }>;
    }>;
  } {
    const root = this.store.getCertificate(rootCertId);
    if (!root) {
      throw { code: 'CERT_NOT_FOUND', message: `Root cert_id ${rootCertId} not found`, recoverable: true };
    }

    const children = this.store.getChildren(rootCertId).map(c => ({
      certId: c.cert_id,
      childIndex: c.child_index,
      resourceId: c.resource_id ?? '',
    }));

    if (depth <= 1) {
      return { root: rootCertId, children };
    }

    // Recursively fetch grandchildren
    const childrenWithGrandchildren = children.map(child => {
      const subtree = this.querySubtree(child.certId, depth - 1);
      return {
        ...child,
        grandchildren: subtree.children.map(gc => ({
          certId: gc.certId,
          childIndex: gc.childIndex,
          resourceId: gc.resourceId,
        })),
      };
    });

    return { root: rootCertId, children: childrenWithGrandchildren };
  }

  presentCapability(
    _certId: string,
    _capabilityId: string,
  ): { valid: boolean; reason?: string } {
    // Local mode: no UTXO-based capability verification.
    // All capabilities are valid. Real Plexus Capability Domain (component 7)
    // will do SPV checks on BRC-108 tokens.
    return { valid: true };
  }

  initiateRecovery(email: string): {
    sessionId: string;
    challengeCount: number;
    challenges?: ChallengeSpec[];
  } {
    // Deterministic session ID from email
    const sessionId = sha256hex(`recovery:${email}`);

    const challenges: ChallengeSpec[] = [
      { id: 'c1', prompt: 'What is your email?' },
      { id: 'c2', prompt: 'What is 2 + 2?' },
      { id: 'c3', prompt: 'True or false: Plexus is a graph?' },
      { id: 'c4', prompt: 'What is the meaning of life?' },
    ];

    // Per Plexus spec: answers are normalized (lowercase, trimmed), salted with sessionId, SHA-256 hashed
    const correctAnswers = [email, '4', 'true', '42'];
    const answerHashes = correctAnswers.map(a =>
      sha256hex(`${sessionId}:${a.toLowerCase().trim()}`),
    );

    this.store.insertRecoverySession({
      session_id: sessionId,
      email,
      challenges_json: JSON.stringify(challenges),
      answer_hashes_json: JSON.stringify(answerHashes),
      status: 'pending',
    });

    return {
      sessionId,
      challengeCount: challenges.length,
      challenges,
    };
  }

  submitChallengeAnswers(
    sessionId: string,
    answers: Array<{ challengeId: string; answer: string }>,
  ): { verified: boolean; exportPayload?: string } {
    const session = this.store.getRecoverySession(sessionId);
    if (!session) {
      throw { code: 'SESSION_NOT_FOUND', message: `Recovery session ${sessionId} not found`, recoverable: true };
    }

    const challenges: ChallengeSpec[] = JSON.parse(session.challenges_json);
    const storedHashes: string[] = JSON.parse(session.answer_hashes_json);

    // Verify each answer
    const verified = answers.every(answer => {
      const idx = challenges.findIndex(c => c.id === answer.challengeId);
      if (idx === -1) return false;
      const hash = sha256hex(`${sessionId}:${answer.answer.toLowerCase().trim()}`);
      return hash === storedHashes[idx];
    });

    if (!verified) {
      return { verified: false };
    }

    this.store.updateRecoveryStatus(sessionId, 'verified');

    // Build export payload (base64 JSON per Plexus Recovery Service spec)
    const exportPayload = btoa(JSON.stringify({
      sessionId,
      email: session.email,
      recoveredAt: challenges.length,
      recoveryToken: sha256hex(`token:${sessionId}`),
    }));

    return { verified: true, exportPayload };
  }

  sendAuthenticated(
    senderCertId: string,
    receiverCertId: string,
    payload: Record<string, string>,
  ): { messageId: string } {
    // Local mode: no real BRC-100 transport. Generate deterministic messageId.
    // Real Plexus Network SDK (component 4) will handle BRC-100 headers.
    const messageId = sha256hex(
      `${senderCertId}:${receiverCertId}:${JSON.stringify(payload)}`,
    );
    return { messageId };
  }

  close(): void {
    this.store.close();
  }
}

```
