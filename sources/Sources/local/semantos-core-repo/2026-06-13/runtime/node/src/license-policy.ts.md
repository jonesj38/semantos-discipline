---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/license-policy.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.303124+00:00
---

# runtime/node/src/license-policy.ts

```ts
/**
 * License policy — load + validate a License cell at node boot.
 *
 * A node REFUSES TO START when its config declares `license.path` but the
 * pointed-to file is missing, unreadable, malformed, expired, or signed by
 * an issuer the current mode doesn't accept.
 *
 * Dev mode:
 *
 *   - `SEMANTOS_DEV_MODE=1` OR `config.license.devMode=true` → dev-issued
 *     licenses are accepted.
 *   - Neither → dev-issued licenses fail validation with reason
 *     `"dev-issuer-rejected"`. Production must use Plexus-issued licenses.
 *
 * The dev issuer is a well-known deterministic keypair derived from
 * `DEV_ISSUER_PRIVKEY_SEED = "semantos-dev-issuer"` via
 * `PrivateKey.fromHex(sha256(seed))`. Same derivation on every machine, so
 * a license minted on one dev laptop is recognised by a fresh checkout.
 */

import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { PrivateKey } from "@bsv/sdk";
import { BsvSdkVerifier } from "@semantos/session-protocol";
import {
  decodeLicense,
  verifyLicense,
  DEV_ISSUER_PRIVKEY_SEED,
  type License,
} from "@semantos/protocol-types/license";
import {
  CapabilityTokenValidator,
  CertChainStore,
  type SpvContext,
} from "@semantos/protocol-types";

// ---------------------------------------------------------------------------
// Dev-issuer derivation
// ---------------------------------------------------------------------------

export interface DevIssuer {
  /** 64-char hex — SHA-256 of `DEV_ISSUER_PRIVKEY_SEED`. */
  privKeyHex: string;
  /** `PrivateKey` instance loaded from `privKeyHex`. */
  privKey: PrivateKey;
  /** 33-byte compressed secp256k1 pubkey. */
  pubkey: Uint8Array;
}

let cachedDevIssuer: DevIssuer | undefined;

/**
 * Derive the dev issuer's keypair from `DEV_ISSUER_PRIVKEY_SEED`.
 * Deterministic — every call returns the same keys. Result is cached.
 */
export function deriveDevIssuer(): DevIssuer {
  if (cachedDevIssuer) return cachedDevIssuer;

  const privKeyHex = createHash("sha256")
    .update(DEV_ISSUER_PRIVKEY_SEED)
    .digest("hex");
  const privKey = PrivateKey.fromHex(privKeyHex);
  const pubkey = Uint8Array.from(
    privKey.toPublicKey().encode(true) as number[],
  );

  cachedDevIssuer = { privKeyHex, privKey, pubkey };
  return cachedDevIssuer;
}

/**
 * Is `license.issuer` the dev issuer's pubkey?
 */
export function isDevIssuedLicense(license: License): boolean {
  const dev = deriveDevIssuer();
  if (license.issuer.length !== dev.pubkey.length) return false;
  for (let i = 0; i < license.issuer.length; i++) {
    if (license.issuer[i] !== dev.pubkey[i]) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Disk load
// ---------------------------------------------------------------------------

/**
 * Read a license file from disk and decode it. Throws a descriptive error
 * if the file is missing, unreadable, or malformed.
 */
export async function loadLicenseFromDisk(
  path: string,
): Promise<{ license: License; bytes: Uint8Array }> {
  let buf: Buffer;
  try {
    buf = await readFile(path);
  } catch (e) {
    throw new Error(
      `license: cannot read file at "${path}": ${(e as Error).message}`,
    );
  }

  const bytes = new Uint8Array(buf);
  const license = decodeLicense(bytes);
  return { license, bytes };
}

// ---------------------------------------------------------------------------
// Boot-time validation
// ---------------------------------------------------------------------------

export interface LicensePolicyOptions {
  /**
   * Override for dev-mode. When undefined, the function consults
   * `SEMANTOS_DEV_MODE` in the provided env (defaults to `process.env`).
   */
  devMode?: boolean;
  env?: NodeJS.ProcessEnv;
  /** Injectable current time (unix seconds) for testing. */
  now?: number;
}

export type LicenseBootVerdict =
  | { ok: true; license: License; devIssued: boolean }
  | {
      ok: false;
      reason:
        | "invalid-signature"
        | "expired"
        | "malformed"
        | "dev-issuer-rejected";
      detail?: string;
    };

/**
 * Run full boot-time validation on a decoded license:
 *
 *   1. `verifyLicense` — issuer sig + expiry
 *   2. Dev-issuer gate — reject dev-issued licenses when dev mode is off
 */
export async function validateLicenseForBoot(
  license: License,
  options: LicensePolicyOptions = {},
): Promise<LicenseBootVerdict> {
  const verifier = new BsvSdkVerifier();
  const verdict = await verifyLicense(license, verifier, {
    now: options.now,
  });
  if (!verdict.ok) {
    if (verdict.reason === "expired") {
      return { ok: false, reason: "expired", detail: verdict.detail };
    }
    if (verdict.reason === "malformed") {
      return { ok: false, reason: "malformed", detail: verdict.detail };
    }
    return {
      ok: false,
      reason: "invalid-signature",
      detail: verdict.detail,
    };
  }

  const devIssued = isDevIssuedLicense(license);
  const devMode = resolveDevMode(options);
  if (devIssued && !devMode) {
    return {
      ok: false,
      reason: "dev-issuer-rejected",
      detail:
        "license was signed by the semantos dev issuer; set SEMANTOS_DEV_MODE=1 or config.license.devMode=true to accept",
    };
  }

  return { ok: true, license, devIssued };
}

function resolveDevMode(options: LicensePolicyOptions): boolean {
  if (options.devMode !== undefined) return options.devMode;
  const env = options.env ?? process.env;
  return env.SEMANTOS_DEV_MODE === "1";
}

// ---------------------------------------------------------------------------
// Node cap-UTXO authorization layer (Wave node-license NL-1).
//
// Ref: docs/design/SELLABLE-NODE-LICENSE.md N3 (AMENDED — "Layer").
//
// The signed `License` above is the IDENTITY / anti-clone credential
// (who / which machine). This is the orthogonal AUTHORIZATION /
// kill-switch layer: an affine node-license cap-UTXO, verified via the
// proven BRC-108 path (`CapabilityTokenValidator.checkCapability` +
// SW2-concrete `beef.verifyBeefSpv`, K15a–e proven incl. Phase-1
// positive). No new crypto — verbatim reuse, exactly like
// `cartridge-license.ts`.
//
// ADDITIVE & NON-BREAKING: engaged only when `capLicenseOutpointRef` is
// configured. Absent ⇒ no-op pass (Phase-35B clusters unaffected). On
// an *unauthorized* result the caller (daemon) must DISABLE FEDERATION
// but NOT exit — N3: non-payment kills network participation, never
// local sovereign use, and the provisioner still cannot read data.
// ---------------------------------------------------------------------------

export interface NodeCapAuthInput {
  /** Validator over the node's cert store (daemon builds it). */
  validator: CapabilityTokenValidator;
  /** BRC-108 node-license token bytes (from capLicenseTokenPath).
   *  Required when capLicenseOutpointRef is set. */
  licenseToken?: Uint8Array;
  /** The node's BRC-52 owner identity pubkey (PEM) — must equal the
   *  license holder cert subject (K15d). */
  nodePubKey: string;
  /** Registered capability-page flag the node-license is scoped to
   *  (K15e). `checkCapability` fails closed if not page-valid. */
  nodeParticipationDomainFlag: number;
  /** SW2 SPV context (proven `beef.verifyBeefSpv`). Omit ⇒
   *  checkCapability fails closed (W1 default) ⇒ unauthorized. */
  spv?: SpvContext;
  /** Configured node-license UTXO outpoint `"<txid>:<vout>"`. Absent
   *  ⇒ cap-UTXO layer not engaged ⇒ no-op pass (non-breaking). */
  capLicenseOutpointRef?: string;
}

export type NodeCapAuthVerdict =
  | { authorized: true; configured: boolean; reason?: string }
  | { authorized: false; configured: true; reason: string };

/** Read the node-license token bytes from disk (mirrors
 *  `loadLicenseFromDisk` for the cap-UTXO layer). */
export async function loadNodeCapLicenseToken(
  tokenPath: string,
): Promise<Uint8Array> {
  const buf = await readFile(tokenPath);
  return new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
}

/**
 * Verify the node cap-UTXO authorization, reusing the proven BRC-108
 * K15 check verbatim. Fail-closed at every branch.
 *
 *  - no `capLicenseOutpointRef` ⇒ not configured ⇒ no-op pass
 *    (`configured:false` — the daemon keeps Phase-35B behaviour);
 *  - configured but no token ⇒ unauthorized;
 *  - token outpoint ≠ configured ref ⇒ unauthorized (can't point at a
 *    foreign live UTXO);
 *  - `checkCapability` not authorized ⇒ unauthorized with the K15
 *    reason (K15a unspent / K15b spent / K15d holder-bind / K15e page).
 */
export async function verifyNodeCapAuthorization(
  input: NodeCapAuthInput,
): Promise<NodeCapAuthVerdict> {
  const ref = input.capLicenseOutpointRef;
  if (!ref) {
    return {
      authorized: true,
      configured: false,
      reason: "node cap-UTXO authorization not configured (Phase-35B signature-only)",
    };
  }
  if (!input.licenseToken) {
    return {
      authorized: false,
      configured: true,
      reason: "node cap-license configured (capLicenseOutpointRef) but no token at capLicenseTokenPath",
    };
  }
  let boundRef: string;
  try {
    const tok = input.validator.parseBrc108Token(input.licenseToken);
    boundRef = `${tok.outpoint.txid}:${tok.outpoint.vout}`;
  } catch (e: unknown) {
    const err = e as { message?: string };
    return {
      authorized: false,
      configured: true,
      reason: err.message ?? "node-license token parse failed",
    };
  }
  if (boundRef !== ref) {
    return {
      authorized: false,
      configured: true,
      reason: `node-license token outpoint ${boundRef} ≠ configured capLicenseOutpointRef ${ref}`,
    };
  }
  const r = await input.validator.checkCapability(
    input.licenseToken,
    input.nodePubKey,
    input.nodeParticipationDomainFlag,
    input.spv,
  );
  if (!r.authorized) {
    return {
      authorized: false,
      configured: true,
      reason: `node-license UTXO check failed (K15): ${r.reason ?? "not authorized"}`,
    };
  }
  return { authorized: true, configured: true };
}

/** Structural slice of NodeConfig the boot gate needs. */
export interface NodeCapBootConfig {
  nodeCert: string;
  storage: ConstructorParameters<typeof CertChainStore>[0];
  license?: {
    capLicenseOutpointRef?: string;
    capLicenseTokenPath?: string;
    nodeParticipationDomainFlag?: number;
  };
}

/**
 * Boot-time node cap-UTXO gate from NodeConfig (Todd 2026-05-17
 * decision): the node-license holder == the node's BRC-52 owner cert
 * (`config.nodeCert`), resolved via `new CertChainStore(config.storage)`
 * — the established `LocalIdentityAdapter` pattern, no interface change.
 * K15d therefore binds the kill-switch to the genuine owner: the gate
 * authorizes only if the unspent cap-UTXO's `holderCertId` resolves, in
 * the node's own store, to the cert whose subject == `config.nodeCert`'s
 * public key.
 *
 * `deps` is test-injection only. `spv` defaults undefined ⇒
 * `checkCapability` fails closed ⇒ federation disabled — the correct
 * conservative kill-switch default. Provisioning the real SpvContext
 * (BEEF envelope + verifier + spend oracle) is the shared open boundary
 * with `cartridge-license.ts`, not an NL-1 regression.
 */
export async function evaluateNodeCapAuthorizationFromConfig(
  config: NodeCapBootConfig,
  deps: { validator?: CapabilityTokenValidator; spv?: SpvContext } = {},
): Promise<NodeCapAuthVerdict> {
  const ref = config.license?.capLicenseOutpointRef;
  if (!ref) {
    return {
      authorized: true,
      configured: false,
      reason: "node cap-UTXO authorization not configured (Phase-35B signature-only)",
    };
  }
  const store = new CertChainStore(config.storage);
  const validator = deps.validator ?? new CapabilityTokenValidator(store);

  const ownerCert = await store.get(config.nodeCert);
  if (!ownerCert) {
    return {
      authorized: false,
      configured: true,
      reason: `node owner cert ${config.nodeCert} not found in the node cert store (K15d holder cannot be bound)`,
    };
  }
  const domainFlag = config.license?.nodeParticipationDomainFlag;
  if (domainFlag === undefined) {
    return {
      authorized: false,
      configured: true,
      reason: "license.nodeParticipationDomainFlag is required when capLicenseOutpointRef is set",
    };
  }
  const licenseToken = config.license?.capLicenseTokenPath
    ? await loadNodeCapLicenseToken(config.license.capLicenseTokenPath)
    : undefined;

  return verifyNodeCapAuthorization({
    validator,
    licenseToken,
    nodePubKey: ownerCert.publicKey,
    nodeParticipationDomainFlag: domainFlag,
    spv: deps.spv,
    capLicenseOutpointRef: ref,
  });
}

```
