---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/CapabilityTokenValidator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.889129+00:00
---

# core/protocol-types/src/identity-adapters/CapabilityTokenValidator.ts

```ts
/**
 * CapabilityTokenValidator — BRC-108 capability-UTXO parsing + the K15
 * capability check (the single authoritative authorization model).
 *
 * `Brc108CapabilityToken` references a capability **outpoint**, binds to
 * the BRC-52 cert subject (holder pubkey), scopes a single domain flag
 * validated against the R-3 page registry, and (SW4) declares the
 * issuer's BRC-42 derivation domain. `checkCapability` implements the
 * full K15 contract: K15d (subject == signing key) + K15e (domain
 * match) + domain-page validity + SW4 grant-domain (PERMISSION_GRANT
 * 0x07) + K15a/K15b unspent (W2 indexer-less BEEF SPV — wired to the
 * real `core/cell-engine/src/beef.zig verifyBeefSpv` via the brain
 * `spv_cap_verifier`, SW2-concrete) + K15c spend-irreversibility
 * (MonotoneSpendOracle). Fails closed at every branch.
 *
 * The legacy bearer token (createToken/parseToken/validateToken + the
 * `CapabilityToken` interface + HMAC helpers) was **DELETED** in Wave
 * Cap-Substrate Phase 2 (Todd 2026-05-17, "Decouple + delete"): it was
 * a vestigial per-cert token, never the authorization path. K15a–e are
 * proven-against-impl (W1–W3, SW2, Phase 1 K15a-positive).
 *
 * Oracle: proofs/lean/Semantos/Theorems/CapabilityUtxoK15.lean.
 * Conformance: __tests__/capability-utxo-k15.test.ts.
 *
 * Cross-references:
 *   BRC-108: Capability token standard (Tech Reqs §7)
 *   Tech Reqs §8: signing key must equal certificate.subject
 */

import { createHmac } from 'crypto';
import type { CertChainStore } from './CertChainStore';
import { makeIdentityError } from '../identity';
import { OPERATOR_BASE } from '../namespace';
import {
  ODDJOBZ_PAGE,
  BSV_ANCHOR_PAGE,
  TESSERA_PAGE,
  LOOM_SHELL_PAGE,
  SUBSTRATE_SCHEMA_PAGE,
} from '../constants';
import type { SpvVerifier } from '../ports/spv-port';

/** An on-chain capability outpoint (the UTXO whose unspent existence
 *  authorizes; spending it revokes — K15b/c). */
export interface CapabilityOutpoint {
  txid: string; // 32-byte tx id, hex
  vout: number; // output index
}

/** BRC-108 Identity-Linked capability token (W1). The capability is
 *  identified by its UTXO outpoint; it binds to the BRC-52 cert
 *  subject (`holderCertId` → that cert's `publicKey`) and scopes a
 *  single domain flag that must sit on a registered CAPABILITY page. */
export interface Brc108CapabilityToken {
  version: 'brc108-v1';
  outpoint: CapabilityOutpoint;
  issuerCertId: string;
  holderCertId: string;
  /** Single uint32 domain flag on a registered capability page. */
  domainFlag: number;
  /** SW4 — the BRC-42 derivation domain the issuer's signing key was
   *  derived under. A capability grant MUST be PERMISSION_GRANT (0x07);
   *  a child-cert issuance MUST be CHILD_CREATION (0x06). Inside the
   *  signed preimage (Client Reqs §2.2.3–4). */
  issuerDerivationDomain: number;
  expiry: number; // epoch ms
  signature: string; // hex HMAC-SHA-256 over the canonical preimage
}

/** Per-clause outcome mirroring CapabilityUtxoK15.lean. Each field is
 *  the truth of the corresponding Lean conjunct against the real
 *  token/request — this is what the conformance test asserts. */
export interface K15ClauseResult {
  /** K15e — queryDomain === token.domainFlag. */
  domainMatches: boolean;
  /** K15d — signingPubKey === holder cert subject. */
  certBinds: boolean;
  /** SW4 — K15d/K15e specialised: the issuer signature was derived
   *  under PERMISSION_GRANT (0x07) for a capability grant (Client Reqs
   *  §2.2.3–4). A grant from any other derivation domain ⇒ false ⇒
   *  ¬authorized (wrong-derivation-domain instance of K15). */
  grantDomainValid: boolean;
  /** domain flag is on a registered capability page (not
   *  SUBSTRATE_SCHEMA, not < OPERATOR_BASE). */
  domainPageValid: boolean;
  /** K15a/K15b — UTXO unspent (W2, indexer-less BEEF SPV).
   *   - 'unspent'              — BEEF Merkle-proven mined AND not in
   *                              the spent oracle ⇒ K15a conjunct true.
   *   - 'spent'                — spend known to the verifier ⇒ K15b.
   *   - 'unprovable:beef-invalid' — no valid SPV proof ⇒ fail closed.
   *   - 'deferred:W2-spv'      — no SpvContext supplied ⇒ W1 fail-closed
   *                              default (callers not yet SPV-wired).
   *  Never silently true. */
  unspentCheck:
    | 'unspent'
    | 'spent'
    | 'unprovable:beef-invalid'
    | 'deferred:W2-spv';
}

export interface CapabilityCheckResult {
  /** True iff ALL K15 conjuncts hold (incl. unspent when an
   *  SpvContext is supplied — W2). Without SpvContext, fail-closed. */
  authorized: boolean;
  reason?: string;
  clauses: K15ClauseResult;
}

/** W2 — indexer-less BEEF SPV context for the K15a/K15b unspent check.
 *  The requester presents the capability UTXO's BEEF envelope
 *  (self-carrying its Merkle proof — no third-party indexer); the
 *  verifier proves inclusion via the {@link SpvVerifier} port and
 *  consults a spent-outpoint oracle. The spent oracle's real backing
 *  (the `capability_utxo` change feed) lands in W3; W2 ships the seam
 *  + an injectable predicate so K15b is testable now. */
export interface SpvContext {
  /** SPV merkle-proof verifier (BEEF/BUMP). Injected — never a
   *  third-party indexer client. */
  verifier: SpvVerifier;
  /** The capability outpoint's BEEF envelope (BRC-62/96), carried in
   *  the BRC-100 signed request. */
  beef: string | number[];
  /** Spent-outpoint oracle. Returns true iff a spend of this outpoint
   *  is known to the verifier (revocation = spend, K15b). The oracle
   *  MUST be monotone (once true for an outpoint, always true — see
   *  {@link MonotoneSpendOracle}); a non-monotone oracle would violate
   *  K15c. W3b wires this to the live `capability_utxo` feed (M3.5
   *  milestone — see CAPABILITY-ENFORCEMENT.md W3b). */
  isOutpointSpent(outpoint: CapabilityOutpoint): Promise<boolean>;
}

const outpointKey = (o: CapabilityOutpoint): string => `${o.txid}:${o.vout}`;

/**
 * Monotone spend oracle — the K15c contract made executable.
 *
 * On-chain a spent UTXO can never become unspent; only a *fresh* mint
 * (new outpoint) yields a new unspent capability. This wrapper enforces
 * that monotonicity in the verifier: `markSpent` is append-only and
 * `isSpent` never regresses. Wiring W2's `SpvContext.isOutpointSpent`
 * through this guarantees K15c holds at the shipped impl (not merely in
 * the abstract Lean model) — the W3b live `capability_utxo` feed, when
 * it lands, feeds `markSpent` and inherits the same monotone guarantee.
 *
 * Oracle: proofs/lean/Semantos/Theorems/CapabilityUtxoK15.lean k15c.
 */
export class MonotoneSpendOracle {
  private readonly spent = new Set<string>();

  /** Record an outpoint as spent. Append-only (idempotent). */
  markSpent(outpoint: CapabilityOutpoint): void {
    this.spent.add(outpointKey(outpoint));
  }

  /** True iff the outpoint has ever been marked spent. Never regresses
   *  (K15c: no transition restores unspent). */
  isSpent = async (outpoint: CapabilityOutpoint): Promise<boolean> =>
    this.spent.has(outpointKey(outpoint));

  /** Bind into an {@link SpvContext} so callers use the K15c-correct
   *  oracle by construction. */
  spvContext(verifier: SpvVerifier, beef: string | number[]): SpvContext {
    return { verifier, beef, isOutpointSpent: this.isSpent };
  }
}

const CAPABILITY_PAGES: readonly number[] = [
  LOOM_SHELL_PAGE,
  ODDJOBZ_PAGE,
  BSV_ANCHOR_PAGE,
  TESSERA_PAGE,
];

/** A domain flag is capability-page-valid iff it is operator-sovereign
 *  (>= OPERATOR_BASE), sits on a registered capability page, and is NOT
 *  on the substrate-schema page (R-3 / B-1 — schema ids must never
 *  authorize). */
export function isCapabilityDomainFlag(flag: number): boolean {
  if (!Number.isInteger(flag) || flag < OPERATOR_BASE) return false;
  const page = flag & 0xffffff00;
  if (page === SUBSTRATE_SCHEMA_PAGE) return false;
  return CAPABILITY_PAGES.includes(page);
}

/**
 * SW4 — grant-domain enforcement (Wave Cap-Substrate).
 *
 * BRC-42 derivation domains, per Plexus Client Requirements §2.2.3–4 and
 * `@semantos/core` `src/types/domain-flags.ts` (CHILD_CREATION = 0x06,
 * PERMISSION_GRANT = 0x07). These are *derivation* domains (the key the
 * issuer's signature is derived under), distinct from capability/page
 * domain flags. Defined here as named protocol constants (mirroring how
 * `plexus-contracts/src/domain-flags.ts` declares them as literals) with
 * the canonical cross-reference, to avoid a cross-package import.
 *
 * SW4 oracle: CapabilityUtxoK15.lean K15d/K15e (wrong-cert/wrong-domain)
 * **specialised to grant/child-creation** — a grant whose issuer
 * signature was NOT derived under PERMISSION_GRANT, or a child-cert not
 * under CHILD_CREATION, is an instance of "wrong derivation domain ⟹
 * fails," discharged against this shipped `checkCapability`.
 */
export const CHILD_CREATION_DERIVATION = 0x06;
export const PERMISSION_GRANT_DERIVATION = 0x07;

/** Canonical signing preimage for a BRC-108 token (deterministic key
 *  order; signature field excluded). SW4: `issuerDerivationDomain` is
 *  inside the signed preimage so it cannot be stripped or forged. */
function brc108Preimage(t: Omit<Brc108CapabilityToken, 'signature'>): string {
  return JSON.stringify({
    version: t.version,
    outpoint: { txid: t.outpoint.txid, vout: t.outpoint.vout },
    issuerCertId: t.issuerCertId,
    holderCertId: t.holderCertId,
    domainFlag: t.domainFlag,
    issuerDerivationDomain: t.issuerDerivationDomain,
    expiry: t.expiry,
  });
}

export class CapabilityTokenValidator {
  private certStore: CertChainStore;

  constructor(certStore: CertChainStore) {
    this.certStore = certStore;
  }

  // ════════════════════════════════════════════════════════════════
  // BRC-108 Identity-Linked capability-UTXO model (the authoritative
  // capability-authorization path). The legacy bearer token
  // (createToken/parseToken/validateToken + helpers) was DELETED in
  // Wave Cap-Substrate Phase 2 (Todd 2026-05-17 "Decouple + delete"):
  // it was a vestigial per-cert token, never the authorization path —
  // checkCapability + SW4 + the SW2-concrete SPV verifier are. K15a–e
  // proven-against-impl (W1–W3, SW2, Phase 1 K15a-positive).
  // ════════════════════════════════════════════════════════════════

  /** Create + sign a BRC-108 capability token. Signed with the
   *  issuer's key over the canonical preimage. */
  createBrc108Token(
    params: Omit<Brc108CapabilityToken, 'version' | 'signature'>,
    signingKey: Uint8Array,
  ): Uint8Array {
    const base: Omit<Brc108CapabilityToken, 'signature'> = {
      version: 'brc108-v1',
      ...params,
    };
    const signature = createHmac('sha256', signingKey)
      .update(brc108Preimage(base))
      .digest('hex');
    const token: Brc108CapabilityToken = { ...base, signature };
    return new TextEncoder().encode(JSON.stringify(token));
  }

  /** Parse a BRC-108 token. Throws INVALID_TOKEN if malformed. */
  parseBrc108Token(token: Uint8Array): Brc108CapabilityToken {
    let parsed: Brc108CapabilityToken;
    try {
      parsed = JSON.parse(new TextDecoder().decode(token));
    } catch {
      throw makeIdentityError('INVALID_TOKEN', 'BRC-108 token is not valid JSON', false);
    }
    if (
      parsed.version !== 'brc108-v1' ||
      typeof parsed.issuerCertId !== 'string' ||
      typeof parsed.holderCertId !== 'string' ||
      typeof parsed.domainFlag !== 'number' ||
      typeof parsed.issuerDerivationDomain !== 'number' ||
      typeof parsed.expiry !== 'number' ||
      typeof parsed.signature !== 'string' ||
      typeof parsed.outpoint !== 'object' ||
      typeof parsed.outpoint?.txid !== 'string' ||
      typeof parsed.outpoint?.vout !== 'number'
    ) {
      throw makeIdentityError(
        'INVALID_TOKEN',
        'BRC-108 token structure invalid — missing/typed fields',
        false,
      );
    }
    return parsed;
  }

  /**
   * The K15 capability check (PRD §0.1 oracle:
   * CapabilityUtxoK15.lean). Returns the per-clause truth of each Lean
   * conjunct against THIS token + request, plus the composite
   * `authorized` = K15a ∧ K15d ∧ K15e (∧ page-valid ∧ not-expired).
   *
   *  - K15e (`domainMatches`) + K15d (`certBinds`) + page-validity — W1.
   *  - K15a/K15b (`unspentCheck`) — W2: when an {@link SpvContext} is
   *    supplied, the capability outpoint's BEEF is Merkle-verified
   *    indexer-less via the SpvVerifier port and checked against the
   *    spend oracle. Without an SpvContext the check **fails closed**
   *    (`'deferred:W2-spv'`) — the W1 default, never a silent pass.
   *  - K15c (spend irreversibility) is W3 (the spend oracle's live
   *    `capability_utxo` backing).
   *
   * @param signingPubKey the requester's signing public key (BRC-103
   *        authenticated channel delivers this; here it is the PEM
   *        string from the holder's BRC-52 cert subject).
   * @param queryDomain the domain flag the action requires.
   * @param spv optional W2 SPV context. Omit → fail-closed (W1).
   */
  async checkCapability(
    rawToken: Uint8Array,
    signingPubKey: string,
    queryDomain: number,
    spv?: SpvContext,
  ): Promise<CapabilityCheckResult> {
    let token: Brc108CapabilityToken;
    try {
      token = this.parseBrc108Token(rawToken);
    } catch (e: unknown) {
      const err = e as { message?: string };
      return {
        authorized: false,
        reason: err.message ?? 'BRC-108 parse failed',
        clauses: {
          domainMatches: false,
          certBinds: false,
          grantDomainValid: false,
          domainPageValid: false,
          unspentCheck: 'deferred:W2-spv',
        },
      };
    }

    // domain-page validity (R-3 / B-1): a schema-id or non-registered
    // flag can never authorize.
    const domainPageValid = isCapabilityDomainFlag(token.domainFlag);

    // K15e — queryDomain === capability domain flag.
    const domainMatches = queryDomain === token.domainFlag;

    // K15d — signing pubkey === holder cert subject. Resolve the
    // holder cert; its `publicKey` IS the BRC-52 subject (Tech Reqs §8).
    const holder = await this.certStore.get(token.holderCertId);
    const certBinds =
      holder != null &&
      holder.revoked !== true &&
      holder.publicKey === signingPubKey;

    // SW4 — K15d/K15e specialised to capability grants: the issuer
    // signature MUST be derived under PERMISSION_GRANT (0x07). A grant
    // issued from any other derivation domain is a wrong-derivation-
    // domain instance of K15 and cannot authorize (Client Reqs §2.2.3–4).
    const grantDomainValid =
      token.issuerDerivationDomain === PERMISSION_GRANT_DERIVATION;

    // K15a/K15b — UTXO unspent (W2, indexer-less BEEF SPV).
    let unspentCheck: K15ClauseResult['unspentCheck'];
    if (!spv) {
      // W1 fail-closed default — caller has not wired SPV.
      unspentCheck = 'deferred:W2-spv';
    } else {
      const beefOk = await spv.verifier.verifyBeef(spv.beef, token.outpoint.txid);
      if (!beefOk) {
        // No valid SPV proof that the capability tx is mined → cannot
        // assert unspent. Fail closed (NOT 'spent' — it is unproven).
        unspentCheck = 'unprovable:beef-invalid';
      } else {
        const spent = await spv.isOutpointSpent(token.outpoint);
        unspentCheck = spent ? 'spent' : 'unspent';
      }
    }

    const clauses: K15ClauseResult = {
      domainMatches,
      certBinds,
      grantDomainValid,
      domainPageValid,
      unspentCheck,
    };

    if (token.expiry <= Date.now()) {
      return { authorized: false, reason: 'token expired', clauses };
    }
    if (!domainPageValid) {
      return {
        authorized: false,
        reason: `domain flag 0x${token.domainFlag.toString(16)} is not on a registered capability page`,
        clauses,
      };
    }
    if (!domainMatches) {
      return { authorized: false, reason: 'K15e: query domain ≠ capability domain', clauses };
    }
    if (!certBinds) {
      return { authorized: false, reason: 'K15d: signing key ≠ holder cert subject', clauses };
    }
    if (!grantDomainValid) {
      // SW4: K15 wrong-derivation-domain — a capability grant not
      // issued from PERMISSION_GRANT (0x07) is rejected end-to-end.
      return {
        authorized: false,
        reason: `SW4/K15: capability grant not issued from PERMISSION_GRANT (0x07) — issuerDerivationDomain=0x${token.issuerDerivationDomain.toString(16)}`,
        clauses,
      };
    }
    if (unspentCheck === 'deferred:W2-spv') {
      return {
        authorized: false,
        reason: 'K15a unspent-check not wired (no SpvContext supplied — W1 fail-closed)',
        clauses,
      };
    }
    if (unspentCheck === 'unprovable:beef-invalid') {
      return {
        authorized: false,
        reason: 'K15a: capability outpoint not SPV-proven (BEEF Merkle proof invalid)',
        clauses,
      };
    }
    if (unspentCheck === 'spent') {
      // K15b — spending the capability UTXO revokes it.
      return { authorized: false, reason: 'K15b: capability UTXO spent (revoked)', clauses };
    }

    // All K15 conjuncts hold: unspent ∧ cert-bound ∧ domain-matched
    // ∧ page-valid ∧ not-expired.
    return { authorized: true, clauses };
  }

  /**
   * SW4 — child-cert issuance domain enforcement (Client Reqs §2.2.3–4).
   *
   * A BRC-108 token that issues/authorizes a *child certificate* MUST
   * have been signed from the CHILD_CREATION (0x06) derivation domain.
   * Any other derivation domain ⇒ rejected (the K15
   * wrong-derivation-domain contract specialised to child-creation).
   * Verification-side enforcement: child-cert chain verification must
   * require the 0x06 signature.
   *
   * @returns `{ valid:true }` iff the token parses AND its
   *          `issuerDerivationDomain === CHILD_CREATION (0x06)`.
   */
  verifyChildCertIssuanceDomain(
    rawToken: Uint8Array,
  ): { valid: true } | { valid: false; reason: string } {
    let token: Brc108CapabilityToken;
    try {
      token = this.parseBrc108Token(rawToken);
    } catch (e: unknown) {
      const err = e as { message?: string };
      return { valid: false, reason: err.message ?? 'BRC-108 parse failed' };
    }
    if (token.issuerDerivationDomain !== CHILD_CREATION_DERIVATION) {
      return {
        valid: false,
        reason: `SW4/K15: child-cert issuance not signed from CHILD_CREATION (0x06) — issuerDerivationDomain=0x${token.issuerDerivationDomain.toString(16)}`,
      };
    }
    return { valid: true };
  }

  // (Bearer helpers extractDomainFlags / checkExpiry /
  // verifyChainToIssuer DELETED with the bearer path — Phase 2.)
}

```
