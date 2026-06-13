---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/hat-context.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.346000+00:00
---

# runtime/intent/src/hat-context.ts

```ts
/**
 * buildHatContext — resolve the active hat into a pipeline-ready shape.
 *
 * Precondition for `processIntent`. If no hat is signed in, the pipeline
 * aborts before any stage event fires (this is a system state problem,
 * not an intent problem — there is no trace to anchor to a hat).
 *
 * The HatContext is populated from an IdentityStore-shaped service plus
 * an extension resolver. Both are passed by interface (not concrete
 * class) so this module stays decoupled from runtime/services and is
 * unit-testable with a fake.
 *
 * D-A3 (Helm wires to Plexus identity, Phase 1b): the production path
 * requires a real cert on the active hat. The legacy "no-cert hat" mode
 * (used in dev / first-boot when Plexus identity has not yet issued a
 * cert) is now gated behind the explicit env flag
 * `SEMANTOS_DEV_IDENTITY=stub`. Cert absence with the flag unset throws
 * `MissingCertError` with a clear hint so boot fails fast — no silent
 * downgrade to an unsigned identity. See docs/spec/protocol-v0.5.md §4
 * for the cert flow contract this gate protects.
 *
 * See docs/INTENT-PIPELINE.md §"HatContext".
 */

import type { HatContext } from './types';
import type { TrustClass } from '@semantos/semantos-sir';

// ── Narrow service surfaces ─────────────────────────────────
//
// The real IdentityStore has ~50 methods; we only need one. Taking a
// minimal interface instead of the full class means tests don't have
// to stub IO, adapters, or event emitters.

export interface HatLike {
  id: string;
  certId?: string | null;
  capabilities: number[];
}

export interface IdentityLike {
  id: string;
  certId?: string | null;
  activeHatId: string;
  hats: HatLike[];
}

export interface IdentityServiceLike {
  getIdentity(): IdentityLike | null;
  getActiveHat(): HatLike | null;
}

export interface ExtensionContextLike {
  extensionId: string;
  domainFlag: number;
}

// ── buildHatContext ──────────────────────────────────────────

export class NoActiveHatError extends Error {
  constructor() {
    super(
      'buildHatContext: no active hat — identity or active hat is missing. ' +
        'The pipeline cannot run without a signed-in hat.',
    );
    this.name = 'NoActiveHatError';
  }
}

/**
 * D-A3 — thrown when the active hat has no cert and the dev-stub
 * escape hatch is not enabled. The message names the env flag so the
 * fix is one read away from the failure.
 */
export class MissingCertError extends Error {
  constructor(hatId: string) {
    super(
      `buildHatContext: active hat '${hatId}' has no cert. ` +
        'Helm requires a real BRC-52 cert from Plexus identity ' +
        '(D-A3 / docs/spec/protocol-v0.5.md §4). To run with a ' +
        "no-cert stub for local dev, set SEMANTOS_DEV_IDENTITY=stub.",
    );
    this.name = 'MissingCertError';
  }
}

/**
 * D-A3 dev escape hatch.
 *
 * Returns true when the no-cert hat path is explicitly enabled via the
 * `SEMANTOS_DEV_IDENTITY` env flag. Any other value (including unset)
 * keeps the production behaviour: cert absence throws.
 *
 * The flag is read at every call rather than cached so test setups can
 * toggle it inside `beforeEach` blocks without module reset gymnastics.
 */
export function isDevIdentityStub(): boolean {
  if (typeof process === 'undefined' || !process.env) return false;
  return process.env.SEMANTOS_DEV_IDENTITY === 'stub';
}

export interface BuildHatContextInput {
  identity: IdentityServiceLike;
  extension: ExtensionContextLike;
  /**
   * Trust-ceiling rule. Injected rather than hard-coded so the ceiling
   * policy lives at the callsite (published-hat = authoritative-capable,
   * unpublished-hat = interpretive-capped, etc.) and can be unit-tested
   * independently of IdentityStore wiring.
   */
  resolveMaxTrustClass: (hat: HatLike, identity: IdentityLike) => TrustClass;
  /**
   * Override the cert-required policy. Defaults to the env-flag rule:
   * required unless `SEMANTOS_DEV_IDENTITY=stub`. Tests pass an explicit
   * boolean to avoid env coupling.
   */
  requireCert?: boolean;
}

export function buildHatContext(input: BuildHatContextInput): HatContext {
  const identity = input.identity.getIdentity();
  const hat = input.identity.getActiveHat();
  if (!identity || !hat) {
    throw new NoActiveHatError();
  }

  const requireCert = input.requireCert ?? !isDevIdentityStub();
  if (requireCert && (hat.certId === null || hat.certId === undefined)) {
    throw new MissingCertError(hat.id);
  }

  return {
    hatId: hat.id,
    certId: hat.certId ?? null,
    capabilities: hat.capabilities.slice(),
    extensionId: input.extension.extensionId,
    domainFlag: input.extension.domainFlag,
    maxTrustClass: input.resolveMaxTrustClass(hat, identity),
  };
}

/**
 * Conservative default trust-ceiling rule: a hat with a published
 * certificate can claim up to 'interpretive'; formal-proof claims
 * (authoritative) require explicit opt-in at the callsite. Unpublished
 * hats are capped at 'cosmetic'.
 *
 * This is a *default* — production sites should pass a rule that
 * reflects their actual attestation policy.
 */
export const defaultTrustCeiling = (
  hat: HatLike,
  _identity: IdentityLike,
): TrustClass => {
  return hat.certId ? 'interpretive' : 'cosmetic';
};

```
