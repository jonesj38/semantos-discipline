---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/local/local-identity-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.916252+00:00
---

# core/protocol-types/src/identity-adapters/local/local-identity-adapter.ts

```ts
/**
 * LocalIdentityAdapter facade — orchestrates the offline identity
 * sub-modules. Implements `IdentityAdapter` with the same surface
 * the pre-split monolith exposed; behaviour is byte-identical
 * (deterministic key derivation in particular).
 *
 * `debugLogging` config is gone — bind the loggerPort instead.
 * Recovery challenges come from the recoveryChallengesPort with the
 * same defaults as before. Both ports auto-resolve to silent / canonical
 * defaults when unbound.
 */

import type { IdentityAdapter } from '../../identity';
import type { StorageAdapter } from '../../storage';
import { CapabilityTokenValidator } from '../CapabilityTokenValidator';
import { KeyDerivationService } from '../KeyDerivationService';
import { RecoveryShareManager } from '../RecoveryShareManager';
import { CertChainStore } from './cert-chain-store-facade';
import { getLogger } from './ports';
import {
  resolvePrivateKey,
  cacheKey,
} from './private-key-resolver';
import {
  ALL_DOMAIN_FLAGS,
  DEFAULT_TOKEN_TTL,
  deriveChildIdentity,
  registerRootIdentity,
} from './identity-registrar';
import {
  initiateRecovery,
  submitChallengeAnswers,
} from './recovery-share-manager';
import { querySubtree } from './subtree-querier';
import { sha256HexStr } from './signing-key-deriver';

export interface LocalIdentityConfig {
  /**
   * @deprecated bind `loggerPort` to {@link consoleDebugLogger} instead.
   * Setting this to true at construction-time still works for backward
   * compat — it temporarily overrides the port resolution.
   */
  debugLogging?: boolean;
  keyDerivationAlgorithm?: 'brc42';
  /** Number of recovery shares to generate. Default: 5. */
  recoveryTotalShares?: number;
  /** Threshold for recovery reconstruction. Default: 3. */
  recoveryThreshold?: number;
}

// Re-exports for facade-only consumers.
export { ALL_DOMAIN_FLAGS, DEFAULT_TOKEN_TTL };

export class LocalIdentityAdapter implements IdentityAdapter {
  private readonly certStore: CertChainStore;
  private readonly validator: CapabilityTokenValidator;
  private readonly keyDerivation: KeyDerivationService;
  private readonly recovery: RecoveryShareManager;
  private readonly recoveryThreshold: number;
  private readonly debugLoggingOverride: boolean;

  constructor(storageAdapter: StorageAdapter, config?: LocalIdentityConfig) {
    this.certStore = new CertChainStore(storageAdapter);
    this.validator = new CapabilityTokenValidator(this.certStore);
    this.keyDerivation = new KeyDerivationService();
    this.recovery = new RecoveryShareManager(storageAdapter);
    this.recoveryThreshold = config?.recoveryThreshold ?? 3;
    this.debugLoggingOverride = config?.debugLogging ?? false;
    void config?.recoveryTotalShares; // accepted for compat; not used here
  }

  private log(message: string): void {
    if (this.debugLoggingOverride) console.log(message);
    getLogger().debug(message);
  }

  async registerIdentity(email: string): Promise<{ certId: string; publicKey: string }> {
    this.log(`[LocalIdentity] registerIdentity(${email})`);
    return registerRootIdentity(
      { certStore: this.certStore, validator: this.validator, keyDerivation: this.keyDerivation },
      email,
    );
  }

  async deriveChild(
    parentCertId: string,
    resourceId: string,
    domainFlag: number,
  ): Promise<{ certId: string; publicKey: string; childIndex: number }> {
    this.log(`[LocalIdentity] deriveChild(${parentCertId}, ${resourceId}, 0x${domainFlag.toString(16)})`);
    return deriveChildIdentity(
      { certStore: this.certStore, validator: this.validator, keyDerivation: this.keyDerivation },
      parentCertId,
      resourceId,
      domainFlag,
    );
  }

  async resolveIdentity(certId: string): Promise<{
    certId: string;
    publicKey: string;
    email?: string;
    created: number;
    updated: number;
    children?: Array<{ certId: string; childIndex: number; resourceId: string }>;
  }> {
    this.log(`[LocalIdentity] resolveIdentity(${certId})`);
    const cert = await this.certStore.getOrThrow(certId);
    const childCerts = await this.certStore.getChildren(certId);
    const children = childCerts.map((c) => ({
      certId: c.certId,
      childIndex: c.childIndex ?? 0,
      resourceId: c.resourceId ?? '',
    }));
    return {
      certId: cert.certId,
      publicKey: cert.publicKey,
      email: cert.email,
      created: cert.created,
      updated: Date.now(),
      children: children.length > 0 ? children : undefined,
    };
  }

  async presentCapability(
    certId: string,
    capabilityId: string,
  ): Promise<{ valid: boolean; reason?: string }> {
    this.log(`[LocalIdentity] presentCapability(${certId}, ${capabilityId})`);
    const cert = await this.certStore.get(certId);
    if (!cert) return { valid: false, reason: `Certificate ${certId} not found` };
    if (cert.revoked) return { valid: false, reason: `Certificate ${certId} is revoked` };

    const domainFlag = capabilityId.startsWith('0x')
      ? parseInt(capabilityId, 16)
      : parseInt(capabilityId, 10);
    if (isNaN(domainFlag)) return { valid: false, reason: `Invalid capability ID: ${capabilityId}` };
    if (!cert.domainFlags.includes(domainFlag)) {
      return {
        valid: false,
        reason: `Certificate ${certId} does not hold domain flag 0x${domainFlag.toString(16)}`,
      };
    }
    // Wave Cap-Substrate Phase 2: the per-cert bearer capabilityToken
    // validation was DELETED (Todd 2026-05-17, "Decouple + delete").
    // Authority = the cert holding the domain flag (checked above);
    // capability-UTXO authorization is the BRC-108 checkCapability
    // path (SW4), not this vestigial token.
    return { valid: true };
  }

  async createEdge(
    initiatorCertId: string,
    responderCertId: string,
  ): Promise<{ edgeId: string; sharedSecret: string }> {
    this.log(`[LocalIdentity] createEdge(${initiatorCertId}, ${responderCertId})`);
    await this.certStore.getOrThrow(initiatorCertId);
    await this.certStore.getOrThrow(responderCertId);
    const sharedSecret = this.keyDerivation.deriveSharedSecret(
      initiatorCertId,
      responderCertId,
      'edge',
    );
    const edgeId =
      'edge:' + sha256HexStr(initiatorCertId + ':' + responderCertId).slice(0, 32);
    await this.certStore.putEdge(edgeId, {
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
      grandchildren?: Array<{ certId: string; childIndex: number; resourceId: string }>;
    }>;
  }> {
    this.log(`[LocalIdentity] querySubtree(${rootCertId}, depth=${depth})`);
    return querySubtree(this.certStore, rootCertId, depth);
  }

  async initiateRecovery(email: string) {
    this.log(`[LocalIdentity] initiateRecovery(${email})`);
    return initiateRecovery({ recovery: this.recovery, recoveryThreshold: this.recoveryThreshold }, email);
  }

  async submitChallengeAnswers(
    sessionId: string,
    answers: Array<{ challengeId: string; answer: string }>,
  ) {
    this.log(`[LocalIdentity] submitChallengeAnswers(${sessionId})`);
    return submitChallengeAnswers(
      { recovery: this.recovery, recoveryThreshold: this.recoveryThreshold },
      sessionId,
      answers,
    );
  }

  async sendAuthenticated(
    senderCertId: string,
    receiverCertId: string,
    payload: Record<string, string>,
  ): Promise<{ messageId: string }> {
    this.log(`[LocalIdentity] sendAuthenticated(${senderCertId} → ${receiverCertId})`);
    this.log(`[LocalIdentity]   payload keys: ${Object.keys(payload).join(', ')}`);
    await this.certStore.getOrThrow(senderCertId);
    await this.certStore.getOrThrow(receiverCertId);
    const messageId =
      'msg:' +
      sha256HexStr(senderCertId + ':' + receiverCertId + ':' + Date.now()).slice(0, 32);
    return { messageId };
  }

  /**
   * L11 substrate-side port — derive a child pubkey from a parent
   * pubkey + segment without registering it as a hat.
   *
   * Delegates to the L11 primitive in `@plexus/vendor-sdk`. The
   * cartridges importing IdentityAdapter never see vendor-sdk; only
   * this substrate-side adapter does.
   *
   * See `IdentityAdapter.deriveSegmentPublicKey` doc-comment for full
   * mechanism (`child_pub = parent_pub + SHA-256(segment) * G`).
   */
  async deriveSegmentPublicKey(
    parentPubKeyHex: string,
    segment: Uint8Array | string,
  ): Promise<{ childPubKeyHex: string }> {
    // Lazy-load to keep vendor-sdk out of the import graph of any
    // consumer that doesn't need this method.
    const PublicKey = (await import('@bsv/sdk/primitives/PublicKey')).default;
    const { deriveScalarPub } = await import('@plexus/vendor-sdk');
    const { sha256 } = await import('@bsv/sdk/primitives/Hash');

    if (typeof parentPubKeyHex !== 'string' || !/^[0-9a-f]{66}$/.test(parentPubKeyHex)) {
      throw new Error(
        `deriveSegmentPublicKey: parentPubKeyHex must be 66-char lowercase hex SEC1 compressed (got ${parentPubKeyHex.length} chars)`,
      );
    }
    const parentPub = PublicKey.fromString(parentPubKeyHex);
    const segmentBytes =
      typeof segment === 'string'
        ? Array.from(new TextEncoder().encode(segment))
        : Array.from(segment);
    const scalarBytes = sha256(segmentBytes);
    const childPub = deriveScalarPub(parentPub, scalarBytes);
    const childPubKeyHex = childPub.toDER('hex') as string;
    return { childPubKeyHex };
  }

  /**
   * L11.5 domain-separated public-key derivation (kdf-v3). See
   * `IdentityAdapter.deriveDomainSegmentPublicKey` for the mechanism
   * (`child_pub = parent_pub + SHA-256(u32_be(domainFlag) ‖ segment) * G`).
   */
  async deriveDomainSegmentPublicKey(
    parentPubKeyHex: string,
    domainFlag: number,
    segment: Uint8Array | string,
  ): Promise<{ childPubKeyHex: string }> {
    const PublicKey = (await import('@bsv/sdk/primitives/PublicKey')).default;
    const { deriveDomainSegmentPub } = await import('@plexus/vendor-sdk');

    if (typeof parentPubKeyHex !== 'string' || !/^[0-9a-f]{66}$/.test(parentPubKeyHex)) {
      throw new Error(
        `deriveDomainSegmentPublicKey: parentPubKeyHex must be 66-char lowercase hex SEC1 compressed (got ${parentPubKeyHex.length} chars)`,
      );
    }
    const parentPub = PublicKey.fromString(parentPubKeyHex);
    // deriveDomainSegmentPub range-checks domainFlag and folds u32_be(flag)
    // into the SHA-256 tweak — keep the segment as raw bytes/string.
    const childPub = deriveDomainSegmentPub(parentPub, domainFlag, segment);
    const childPubKeyHex = childPub.toDER('hex') as string;
    return { childPubKeyHex };
  }

  // ── Internal helpers (kept for back-compat callers that imported them) ──

  private async resolvePrivateKey(certId: string): Promise<Uint8Array> {
    return resolvePrivateKey(this.certStore, this.keyDerivation, certId);
  }

  /** Test/debug only — expose the in-memory cache write side. */
  protected cacheKey(certId: string, key: Uint8Array): void {
    cacheKey(certId, key);
  }
}

```
