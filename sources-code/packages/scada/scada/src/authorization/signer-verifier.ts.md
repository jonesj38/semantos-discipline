---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/authorization/signer-verifier.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.472483+00:00
---

# packages/scada/scada/src/authorization/signer-verifier.ts

```ts
/**
 * Signer-verifier — wraps signature verification for SCADA capability
 * tokens via the shared `signerPort` (`@semantos/protocol-types/ports`).
 *
 * The legacy `CommandAuthorizationEngine` carried a `cellBytes:
 * Uint8Array` placeholder on every capability token but never actually
 * verified it. Spec 28 calls for a dedicated signer-verifier so the
 * placeholder can graduate to a real ECDSA signature check without
 * touching orchestrator code.
 *
 * Until SCADA tokens carry real signatures end-to-end, this module
 * deliberately defaults to **permit** so refactoring stays
 * zero-behaviour-change. Callers can flip the strict-mode switch when
 * the token format catches up.
 */

import { signerPort, type Signer } from '@semantos/protocol-types/ports';

import type { SCADACapabilityToken } from '../types';

export type VerifySignatureResult =
  | { ok: true; via: 'signer-port' | 'permit-default' }
  | { ok: false; reason: 'INVALID_SIGNATURE' | 'NO_SIGNER_BOUND'; detail: string };

export interface VerifySignatureOptions {
  /**
   * If `true`, returns `{ ok: false }` when no signer is bound.
   * Defaults to `false` (permit) for behaviour-preserving refactors —
   * the legacy engine never verified signatures.
   */
  strict?: boolean;
  /**
   * Explicit signer to use, bypassing the port lookup. Mostly for
   * tests. Production code binds via `signerPort.bind(...)`.
   */
  signer?: Signer;
}

/**
 * Verify the signature on a capability token.
 *
 * The token's `cellBytes` is treated as the message body; the
 * `grantedBy` field as the keyId. A real signer compares the signature
 * to the derived public key. Until tokens carry an explicit signature
 * field, the wrapper is "shape-ready": it asks the signer to derive a
 * public key for the granter and treats success as a verified token.
 *
 * This is structurally faithful to the underlying `signerPort` contract
 * while preserving zero behaviour change at the orchestrator level
 * (default: permit if not strict).
 */
export async function verifyCapabilitySignature(
  token: SCADACapabilityToken,
  opts: VerifySignatureOptions = {},
): Promise<VerifySignatureResult> {
  const signer = opts.signer ?? (signerPort.isBound() ? signerPort.get() : undefined);
  if (!signer) {
    if (opts.strict) {
      return {
        ok: false,
        reason: 'NO_SIGNER_BOUND',
        detail: 'signerPort not bound and signer-verifier is in strict mode',
      };
    }
    return { ok: true, via: 'permit-default' };
  }

  try {
    // Shape check: the signer can derive a public key for the granter.
    // Replace with a true signature check once tokens carry one.
    await signer.derivePublicKey(token.grantedBy);
    return { ok: true, via: 'signer-port' };
  } catch (err) {
    return {
      ok: false,
      reason: 'INVALID_SIGNATURE',
      detail: err instanceof Error ? err.message : String(err),
    };
  }
}

```
