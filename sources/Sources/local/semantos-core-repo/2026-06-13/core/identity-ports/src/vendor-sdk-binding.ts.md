---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/identity-ports/src/vendor-sdk-binding.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.943360+00:00
---

# core/identity-ports/src/vendor-sdk-binding.ts

```ts
/**
 * Vendor SDK binding for the four identity ports.
 *
 * Wraps an instance of `@plexus/vendor-sdk`'s `VendorSDK` class (the
 * local stand-in with real BRC-42 + SQLite — see core/plexus-vendor-sdk)
 * into the application-facing port surface declared in `./types.ts`.
 *
 * Surface coverage today:
 *   - identityPort:   FULL — VendorSDK has registerIdentity / resolveIdentity /
 *                     deriveChild / createEdge / querySubtree.
 *   - recoveryPort:   FULL — VendorSDK has initiateRecovery /
 *                     submitChallengeAnswers.
 *   - attestationPort: STUBBED here — VendorSDK does not yet expose
 *                      Attestation Authority methods. The binding returns
 *                      `verified: 'stub'` attestations until the real
 *                      Capability/Attestation domains land in Plexus
 *                      (see Plexus Technical Requirements §11 attestation
 *                      byproduct + §7 capability domain).
 *   - capabilityPort: PASSTHROUGH — VendorSDK.presentCapability returns
 *                     `{ valid: true }` unconditionally in local mode
 *                     (per its own comment, real SPV verification is the
 *                     Capability Domain's job). We mirror that as
 *                     `verifier: 'stub'` so consumers can detect.
 *
 * When PR-C lands (real Plexus availability), the `verified:'stub'`
 * branches in this file are the only places that need to flip to
 * `verified:'spv'` — search for `STUB_BRANCH:` to find them.
 */

import type { ChallengeAnswer, EdgeRecoveryPolicy, PlexusCert } from '@plexus/contracts';
import type { VendorSDK } from '@plexus/vendor-sdk';

import type {
  AttestationPort,
  CapabilityPort,
  ChildDerivation,
  ChildNodeRef,
  EdgeCreation,
  IdentityPort,
  IdentityRegistration,
  IdentityResolution,
  RecoveryInitiation,
  RecoveryPort,
  RecoveryVerdict,
  SPVAttestation,
  SubtreeQuery,
} from './types.js';
import type { IdentityPortBundle } from './ports.js';

export interface VendorSdkBindingOptions {
  /** A constructed VendorSDK instance. The binding does not own its lifecycle. */
  vendorSdk: VendorSDK;
  /**
   * 33-byte compressed pubkey hex of the RaaS authority key used to sign
   * stubbed attestations. In production this comes from Plexus's
   * `authority_keys` table (key_type='attestation', flag 0x05). For the
   * local binding default to a well-known marker so consumers can detect.
   */
  attestorPublicKeyHex?: string;
  /** Wall clock; defaults to `Date.now`. Test override hook. */
  now?: () => number;
}

/**
 * Build an `IdentityPortBundle` backed by an existing VendorSDK instance.
 * Caller is responsible for VendorSDK lifecycle (`new VendorSDK(...)` /
 * `.close()`).
 */
export function makeVendorSdkBindings(
  options: VendorSdkBindingOptions,
): IdentityPortBundle {
  const { vendorSdk } = options;
  const now = options.now ?? Date.now;
  const attestorPublicKey =
    options.attestorPublicKeyHex ??
    '02deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';

  // ─── identityPort ──────────────────────────────────────────────────────

  const identity: IdentityPort = {
    registerIdentity(email: string): IdentityRegistration {
      const r = vendorSdk.registerIdentity(email);
      return { certId: r.certId, publicKey: r.publicKey };
    },

    resolveIdentity(certId: string): IdentityResolution {
      const r = vendorSdk.resolveIdentity(certId);
      const children: ChildNodeRef[] = (r.children ?? []).map((c) => ({
        certId: c.certId,
        childIndex: c.childIndex,
        resourceId: c.resourceId,
      }));
      return {
        certId: r.certId,
        publicKey: r.publicKey,
        email: r.email,
        created: r.created,
        updated: r.updated,
        children,
      };
    },

    deriveChild(parentCertId, resourceId, domainFlag): ChildDerivation {
      const r = vendorSdk.deriveChild(parentCertId, resourceId, domainFlag);
      return { certId: r.certId, publicKey: r.publicKey, childIndex: r.childIndex };
    },

    createEdge(initiatorCertId, responderCertId, _policy?: EdgeRecoveryPolicy): EdgeCreation {
      // STUB_BRANCH: edge-signing-key-index
      // VendorSDK.createEdge does not yet expose the BKDS signingKeyIndex
      // (invoiceNumber). Per Plexus §2.5.5 the shared secret must never be
      // stored or returned — only the index used to re-derive it locally.
      //
      // Until VendorSDK surfaces signingKeyIndex (tracked in Plexus backlog
      // alongside BACKUP_ON_CREATE recipe extraction for BRC-69), we return 0
      // as a placeholder. Production code that needs to re-derive the ECDH
      // secret will need the real index from VendorSDK when that lands.
      //
      // Also: VendorSDK.createEdge does not yet accept a recovery policy
      // parameter — thread `_policy` through when BACKUP_ON_CREATE lands.
      // STUB_BRANCH: edge-recovery-policy
      const r = vendorSdk.createEdge(initiatorCertId, responderCertId);
      void r; // r.sharedSecret intentionally discarded — must not be propagated (§2.5.5)
      const edgeId = r.edgeId;
      return { edgeId, signingKeyIndex: 0 };
    },

    querySubtree(rootCertId, depth): SubtreeQuery {
      const r = vendorSdk.querySubtree(rootCertId, depth);
      return {
        root: r.root,
        children: r.children.map((c) => ({
          certId: c.certId,
          childIndex: c.childIndex,
          resourceId: c.resourceId,
          grandchildren: c.grandchildren?.map((g) => ({
            certId: g.certId,
            childIndex: g.childIndex,
            resourceId: g.resourceId,
          })),
        })),
      };
    },

    getCert(_certId: string): PlexusCert | null {
      // VendorSDK exposes resolveIdentity which throws on miss; reshape into
      // null-on-miss for consumers that prefer that contract.
      try {
        const r = vendorSdk.resolveIdentity(_certId);
        return {
          certId: r.certId,
          publicKey: r.publicKey,
          email: r.email,
          parentCertId: null, // VendorSDK.resolveIdentity doesn't return parent — leave null
          childIndex: 0,
          derivationPath: 'root',
          createdAt: r.created,
        };
      } catch {
        return null;
      }
    },
  };

  // ─── recoveryPort ──────────────────────────────────────────────────────

  const recovery: RecoveryPort = {
    initiateRecovery(email: string): RecoveryInitiation {
      const r = vendorSdk.initiateRecovery(email);
      return {
        sessionId: r.sessionId,
        challengeCount: r.challengeCount,
        challenges: r.challenges ?? [],
      };
    },

    submitChallengeAnswers(sessionId, answers: readonly ChallengeAnswer[]): RecoveryVerdict {
      const r = vendorSdk.submitChallengeAnswers(
        sessionId,
        answers.map((a) => ({ challengeId: a.challengeId, answer: a.answer })),
      );
      return { verified: r.verified, exportPayload: r.exportPayload };
    },
  };

  // ─── attestationPort (stubbed until §7+§11 land) ───────────────────────

  // STUB_BRANCH: attestation-not-yet-implemented
  // VendorSDK has no `proveContinuity` / `proveEdgePresence` /
  // `proveAppPresence` methods today. Until the real Attestation Authority
  // is exposed (Plexus §11 — natural byproduct of Recovery Service), we
  // return shape-correct attestations marked `verified: 'stub'`.
  function stubAttestation(certId: string, kind: SPVAttestation['kind']): SPVAttestation {
    return {
      certId,
      kind,
      // No real signature available. Consumers MUST check `verified`.
      signature: '00'.repeat(64),
      attestorPublicKey: attestorPublicKey,
      generatedAt: now(),
      verified: 'stub',
    };
  }

  const attestation: AttestationPort = {
    proveContinuity: async (certId) => stubAttestation(certId, 'continuity'),
    proveEdgePresence: async (certId, _edgeType) => stubAttestation(certId, 'edge_presence'),
    proveAppPresence: async (certId, _resourceId) => stubAttestation(certId, 'app_presence'),
  };

  // ─── capabilityPort ────────────────────────────────────────────────────

  const capability: CapabilityPort = {
    present(certId, capabilityId) {
      const r = vendorSdk.presentCapability(certId, capabilityId);
      // STUB_BRANCH: capability-spv-not-yet-implemented
      // VendorSDK.presentCapability returns `{ valid: true }` in local mode
      // because real SPV verification is the Capability Domain's job (§7).
      // Surface that as `verifier: 'stub'` so consumers can detect.
      return { valid: r.valid, reason: r.reason, verifier: 'stub' };
    },
  };

  return { identity, recovery, attestation, capability };
}

```
