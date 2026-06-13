---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/cartridge-license.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.888826+00:00
---

# core/protocol-types/src/identity-adapters/cartridge-license.ts

```ts
/**
 * Cartridge license gate — Wave Cap-Substrate Decision-A enforcement.
 *
 * Ref: docs/design/CARTRIDGE-MARKETPLACE-OWNERSHIP.md (RATIFIED) §2/§4.
 *
 * A cartridge's ownership is an **affine PushDrop license UTXO**,
 * required at load. Decision A §2/§4 collapses this onto the
 * already-proven BRC-108 capability-UTXO model: the license IS a
 * capability UTXO whose domain is the cartridge's registered page, so
 * verification is `CapabilityTokenValidator.checkCapability` (K15a–e,
 * proven-against-impl in W1–W3) over the SW2-concrete SPV path
 * (`beef.verifyBeefSpv`). **No new crypto, no PushDrop decoder** — the
 * PushDrop script is the on-chain *form*; the loader verifies via the
 * capability model.
 *
 * This is the loader call-site Decision A §4 specifies ("SW3.<cartridge>
 * adds the loader call-site, not new crypto"). Wiring it as a *mandatory*
 * brain-loader gate for non-first-party cartridges is sequenced after
 * DLO.1c (manifest-driven registration) — see the marketplace doc §4;
 * here it ships as a reusable gate + a non-breaking opt-in loader hook.
 */

import type { ExtensionManifest } from '../extension-manifest';
import type {
  CapabilityTokenValidator,
  SpvContext,
} from './CapabilityTokenValidator';

/** Inputs for the license check. The `licenseToken` is the BRC-108
 *  capability token whose `outpoint` is the affine PushDrop license
 *  UTXO — resolved from the cartridge's signed bundle / license file
 *  at load time (out of band of this pure check). */
export interface CartridgeLicenseContext {
  validator: CapabilityTokenValidator;
  /** BRC-108 license token bytes (the capability token bound to the
   *  license UTXO outpoint). Omit only with `allowUnlicensed`. */
  licenseToken?: Uint8Array;
  /** Loading node/operator identity pubkey (PEM). Must equal the
   *  license holder cert subject (K15d). */
  loaderPubKey: string;
  /** The cartridge's registered capability-page flag (K15e domain the
   *  license must be scoped to). */
  cartridgePageFlag: number;
  /** SW2 SPV context (SW2-concrete `beef.verifyBeefSpv`). Omit ⇒
   *  checkCapability fails closed (W1 default) ⇒ unlicensed. */
  spv?: SpvContext;
  /** First-party / dev escape hatch (marketplace doc §6): allow an
   *  unlicensed cartridge (no `licenseOutpointRef`) to load. Default
   *  false ⇒ unlicensed cartridges are rejected (fail-closed). */
  allowUnlicensed?: boolean;
}

export type CartridgeLicenseVerdict =
  | { licensed: true; reason?: string }
  | { licensed: false; reason: string };

const refOf = (txid: string, vout: number): string => `${txid}:${vout}`;

/**
 * Verify a cartridge's affine PushDrop license, reusing the proven
 * BRC-108 capability-UTXO check verbatim.
 *
 * Fail-closed at every branch:
 *  - no `licenseOutpointRef` ⇒ unlicensed (unless `allowUnlicensed`);
 *  - token's bound outpoint ≠ the manifest's claimed
 *    `licenseOutpointRef` ⇒ reject (can't point at a foreign UTXO);
 *  - `checkCapability` not authorized ⇒ reject with the K15 reason
 *    (K15a unspent / K15b spent / K15d holder-bind / K15e page).
 */
export async function verifyCartridgeLicense(
  manifest: ExtensionManifest,
  ctx: CartridgeLicenseContext,
): Promise<CartridgeLicenseVerdict> {
  const ref = manifest.licenseOutpointRef;

  if (!ref) {
    if (ctx.allowUnlicensed) {
      return {
        licensed: true,
        reason: 'unlicensed cartridge admitted via explicit escape hatch',
      };
    }
    return {
      licensed: false,
      reason:
        'unlicensed: manifest has no licenseOutpointRef (Decision A: ownership is a required affine PushDrop license UTXO)',
    };
  }

  if (manifest.licenseLinearity !== undefined && manifest.licenseLinearity !== 'AFFINE') {
    return {
      licensed: false,
      reason: `license must be AFFINE (consume-at-most-once); manifest.licenseLinearity=${String(manifest.licenseLinearity)}`,
    };
  }

  if (!ctx.licenseToken) {
    return { licensed: false, reason: 'licensed cartridge but no license token presented at load' };
  }

  // Parse + bind: the token's outpoint MUST equal the manifest's
  // claimed licenseOutpointRef (prevents a manifest pointing at some
  // other live capability UTXO it does not own).
  let boundRef: string;
  try {
    const tok = ctx.validator.parseBrc108Token(ctx.licenseToken);
    boundRef = refOf(tok.outpoint.txid, tok.outpoint.vout);
  } catch (e: unknown) {
    const err = e as { message?: string };
    return { licensed: false, reason: err.message ?? 'license token parse failed' };
  }
  if (boundRef !== ref) {
    return {
      licensed: false,
      reason: `license token outpoint ${boundRef} ≠ manifest.licenseOutpointRef ${ref}`,
    };
  }

  // Reuse the proven K15 path verbatim (SW2-concrete SPV verifier does
  // the unspent check; W1 the cert-binding + domain-page).
  const r = await ctx.validator.checkCapability(
    ctx.licenseToken,
    ctx.loaderPubKey,
    ctx.cartridgePageFlag,
    ctx.spv,
  );
  if (!r.authorized) {
    return {
      licensed: false,
      reason: `license UTXO check failed (K15): ${r.reason ?? 'not authorized'}`,
    };
  }
  return { licensed: true };
}

```
