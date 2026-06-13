---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/__tests__/capability-utxo-k15.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.913614+00:00
---

# core/protocol-types/src/identity-adapters/__tests__/capability-utxo-k15.test.ts

```ts
/**
 * W1 conformance — CapabilityUtxoK15.lean discharged against the
 * shipped CapabilityTokenValidator.checkCapability (PRD §0.1 bridge).
 *
 * Each test mirrors a K15 clause statement and asserts the REAL
 * validator exhibits exactly that behaviour. This is what makes the
 * (abstract) Lean theorem load-bearing for W1's scope:
 *
 *   K15a — correctness: the per-clause result is exactly the
 *          three-conjunct contract (for the conjuncts W1 owns).
 *   K15d — wrong cert fails: signing key ≠ holder subject ⇒ ¬authorized.
 *   K15e — wrong domain fails: queryDomain ≠ cap domain ⇒ ¬authorized.
 *   (B-1) — a SUBSTRATE_SCHEMA / non-capability-page flag never authorizes.
 *
 * Honest boundary: K15a-unspent / K15b / K15c are W2/W3. W1 fails
 * CLOSED — even an otherwise-perfect token returns authorized:false
 * with the explicit W2 reason. The test asserts that boundary so the
 * "proven but unwired" failure mode cannot hide.
 */

import { describe, test, expect } from 'bun:test';
import {
  CapabilityTokenValidator,
  isCapabilityDomainFlag,
  PERMISSION_GRANT_DERIVATION,
  CHILD_CREATION_DERIVATION,
} from '../CapabilityTokenValidator';
import type { CertChainStore, CertData } from '../CertChainStore';
import { ODDJOBZ_PAGE, SUBSTRATE_SCHEMA_PAGE } from '../../constants';
import { OPERATOR_BASE } from '../../namespace';

const HOLDER_PUBKEY = '-----BEGIN PUBLIC KEY-----\nHOLDER\n-----END PUBLIC KEY-----';
const ATTACKER_PUBKEY = '-----BEGIN PUBLIC KEY-----\nATTACKER\n-----END PUBLIC KEY-----';

function fakeStore(certs: Record<string, CertData>): CertChainStore {
  return {
    get: async (id: string) => certs[id] ?? null,
  } as unknown as CertChainStore;
}

const holderCert: CertData = {
  certId: 'holder-1',
  publicKey: HOLDER_PUBKEY,
  domainFlags: [],
  created: 0,
  revoked: false,
};

const CAP_DOMAIN = ODDJOBZ_PAGE | 0x01; // 0x00010101 — a registered capability-page flag
const SIGNING_KEY = new Uint8Array(32).fill(7);

function makeToken(
  v: CapabilityTokenValidator,
  over: Partial<{ holderCertId: string; domainFlag: number; expiry: number }> = {},
): Uint8Array {
  return v.createBrc108Token(
    {
      outpoint: { txid: 'a'.repeat(64), vout: 0 },
      issuerCertId: 'issuer-1',
      holderCertId: over.holderCertId ?? 'holder-1',
      domainFlag: over.domainFlag ?? CAP_DOMAIN,
      // SW4: a capability grant is issued from PERMISSION_GRANT (0x07).
      issuerDerivationDomain: PERMISSION_GRANT_DERIVATION,
      expiry: over.expiry ?? Date.now() + 60_000,
    },
    SIGNING_KEY,
  );
}

describe('W1 — K15 against the shipped checkCapability', () => {
  test('isCapabilityDomainFlag: B-1 — schema page & sub-operator flags rejected', () => {
    expect(isCapabilityDomainFlag(CAP_DOMAIN)).toBe(true);
    expect(isCapabilityDomainFlag(SUBSTRATE_SCHEMA_PAGE | 0x01)).toBe(false); // schema-id never authorizes
    expect(isCapabilityDomainFlag(OPERATOR_BASE - 1)).toBe(false); // below Tier-3
    expect(isCapabilityDomainFlag(0x00010300)).toBe(false); // unregistered page
  });

  test('K15e — queryDomain ≠ capability domain ⇒ ¬authorized', async () => {
    const v = new CapabilityTokenValidator(fakeStore({ 'holder-1': holderCert }));
    const r = await v.checkCapability(makeToken(v), HOLDER_PUBKEY, CAP_DOMAIN + 1);
    expect(r.clauses.domainMatches).toBe(false);
    expect(r.authorized).toBe(false);
    expect(r.reason).toContain('K15e');
  });

  test('K15d — signing key ≠ holder cert subject ⇒ ¬authorized', async () => {
    const v = new CapabilityTokenValidator(fakeStore({ 'holder-1': holderCert }));
    const r = await v.checkCapability(makeToken(v), ATTACKER_PUBKEY, CAP_DOMAIN);
    expect(r.clauses.certBinds).toBe(false);
    expect(r.authorized).toBe(false);
    expect(r.reason).toContain('K15d');
  });

  test('B-1 — capability on SUBSTRATE_SCHEMA page never authorizes', async () => {
    const v = new CapabilityTokenValidator(fakeStore({ 'holder-1': holderCert }));
    const tok = makeToken(v, { domainFlag: SUBSTRATE_SCHEMA_PAGE | 0x02 });
    const r = await v.checkCapability(tok, HOLDER_PUBKEY, SUBSTRATE_SCHEMA_PAGE | 0x02);
    expect(r.clauses.domainPageValid).toBe(false);
    expect(r.authorized).toBe(false);
  });

  test('revoked holder cert ⇒ K15d certBinds false', async () => {
    const v = new CapabilityTokenValidator(
      fakeStore({ 'holder-1': { ...holderCert, revoked: true } }),
    );
    const r = await v.checkCapability(makeToken(v), HOLDER_PUBKEY, CAP_DOMAIN);
    expect(r.clauses.certBinds).toBe(false);
    expect(r.authorized).toBe(false);
  });

  test('expired token ⇒ ¬authorized', async () => {
    const v = new CapabilityTokenValidator(fakeStore({ 'holder-1': holderCert }));
    const tok = makeToken(v, { expiry: Date.now() - 1 });
    const r = await v.checkCapability(tok, HOLDER_PUBKEY, CAP_DOMAIN);
    expect(r.authorized).toBe(false);
    expect(r.reason).toContain('expired');
  });

  test('HONEST BOUNDARY — perfect token still ¬authorized: K15a unspent is W2-deferred (fails closed)', async () => {
    const v = new CapabilityTokenValidator(fakeStore({ 'holder-1': holderCert }));
    const r = await v.checkCapability(makeToken(v), HOLDER_PUBKEY, CAP_DOMAIN);
    // W1 clauses all pass …
    expect(r.clauses.domainMatches).toBe(true);
    expect(r.clauses.certBinds).toBe(true);
    expect(r.clauses.domainPageValid).toBe(true);
    // … but the unspent conjunct is the explicit W2 seam, never a silent pass.
    expect(r.clauses.unspentCheck).toBe('deferred:W2-spv');
    expect(r.authorized).toBe(false);
    expect(r.reason).toContain('fail-closed');
  });

  test('parseBrc108Token rejects malformed / legacy bearer JSON', async () => {
    const v = new CapabilityTokenValidator(fakeStore({}));
    const bearer = new TextEncoder().encode(
      JSON.stringify({ issuerCertId: 'x', holderCertId: 'y', domainFlags: [1], expiry: 1, signature: 'z' }),
    );
    const r = await v.checkCapability(bearer, HOLDER_PUBKEY, CAP_DOMAIN);
    expect(r.authorized).toBe(false);
    expect(r.reason).toContain('BRC-108');
  });

  test('LEGACY bearer path DELETED (Wave Cap-Substrate Phase 2)', () => {
    // Todd 2026-05-17 "Decouple + delete": the vestigial bearer token
    // is gone — BRC-108 checkCapability/SW4 is the sole authorization
    // path. Invariant flipped from "preserved" to "absent".
    const v = new CapabilityTokenValidator(fakeStore({})) as unknown as Record<string, unknown>;
    expect(v.createToken).toBeUndefined();
    expect(v.parseToken).toBeUndefined();
    expect(v.validateToken).toBeUndefined();
    expect(v.extractDomainFlags).toBeUndefined();
    expect(v.checkExpiry).toBeUndefined();
  });
});

// ── W2 — indexer-less BEEF SPV realizes K15a / K15b ────────────────

import type { SpvContext } from '../CapabilityTokenValidator';

/** Stub SpvVerifier — no third-party indexer; the BEEF self-carries
 *  its proof, here modelled by a boolean. */
function spvCtx(opts: {
  beefValid: boolean;
  spentOutpoints?: Set<string>;
}): SpvContext {
  return {
    verifier: {
      verifyBeef: async () => opts.beefValid,
      verifyBump: async () => opts.beefValid,
    },
    beef: 'beef-envelope-bytes',
    isOutpointSpent: async (op) =>
      (opts.spentOutpoints ?? new Set()).has(`${op.txid}:${op.vout}`),
  };
}

describe('W2 — K15a/K15b against the shipped checkCapability + SpvContext', () => {
  test('K15a — valid BEEF + unspent + all conjuncts ⇒ AUTHORIZED', async () => {
    const v = new CapabilityTokenValidator(fakeStore({ 'holder-1': holderCert }));
    const r = await v.checkCapability(
      makeToken(v),
      HOLDER_PUBKEY,
      CAP_DOMAIN,
      spvCtx({ beefValid: true }),
    );
    expect(r.clauses.domainMatches).toBe(true);
    expect(r.clauses.certBinds).toBe(true);
    expect(r.clauses.domainPageValid).toBe(true);
    expect(r.clauses.unspentCheck).toBe('unspent');
    expect(r.authorized).toBe(true); // first time authorized:true is reachable
    expect(r.reason).toBeUndefined();
  });

  test('K15b — capability outpoint spent ⇒ ¬authorized (revoked)', async () => {
    const v = new CapabilityTokenValidator(fakeStore({ 'holder-1': holderCert }));
    const r = await v.checkCapability(
      makeToken(v),
      HOLDER_PUBKEY,
      CAP_DOMAIN,
      spvCtx({
        beefValid: true,
        spentOutpoints: new Set([`${'a'.repeat(64)}:0`]),
      }),
    );
    expect(r.clauses.unspentCheck).toBe('spent');
    expect(r.authorized).toBe(false);
    expect(r.reason).toContain('K15b');
  });

  test('K15a — invalid BEEF (no SPV proof) ⇒ ¬authorized, fail closed', async () => {
    const v = new CapabilityTokenValidator(fakeStore({ 'holder-1': holderCert }));
    const r = await v.checkCapability(
      makeToken(v),
      HOLDER_PUBKEY,
      CAP_DOMAIN,
      spvCtx({ beefValid: false }),
    );
    expect(r.clauses.unspentCheck).toBe('unprovable:beef-invalid');
    expect(r.authorized).toBe(false);
    expect(r.reason).toContain('SPV-proven');
  });

  test('K15 composite — spent overrides even with valid cert+domain (K15b dominates)', async () => {
    const v = new CapabilityTokenValidator(fakeStore({ 'holder-1': holderCert }));
    const r = await v.checkCapability(
      makeToken(v),
      HOLDER_PUBKEY,
      CAP_DOMAIN,
      spvCtx({ beefValid: true, spentOutpoints: new Set([`${'a'.repeat(64)}:0`]) }),
    );
    // cert + domain conjuncts still individually true …
    expect(r.clauses.certBinds).toBe(true);
    expect(r.clauses.domainMatches).toBe(true);
    // … but K15b makes the composite false (spend = revoke).
    expect(r.authorized).toBe(false);
  });

  test('W1 fail-closed default still holds when no SpvContext supplied', async () => {
    const v = new CapabilityTokenValidator(fakeStore({ 'holder-1': holderCert }));
    const r = await v.checkCapability(makeToken(v), HOLDER_PUBKEY, CAP_DOMAIN);
    expect(r.clauses.unspentCheck).toBe('deferred:W2-spv');
    expect(r.authorized).toBe(false);
  });
});

// ── W3 — K15c spend irreversibility against the shipped impl ───────

import { MonotoneSpendOracle } from '../CapabilityTokenValidator';

const aliveVerifier = { verifyBeef: async () => true, verifyBump: async () => true };

describe('W3 — K15c (spend irreversibility) against checkCapability + MonotoneSpendOracle', () => {
  test('K15c — once spent, capCheck on that outpoint is permanently ¬authorized', async () => {
    const v = new CapabilityTokenValidator(fakeStore({ 'holder-1': holderCert }));
    const oracle = new MonotoneSpendOracle();
    const tok = makeToken(v); // outpoint aaaa…:0
    const ctx = oracle.spvContext(aliveVerifier, 'beef');

    // unspent ⇒ authorized
    const before = await v.checkCapability(tok, HOLDER_PUBKEY, CAP_DOMAIN, ctx);
    expect(before.authorized).toBe(true);
    expect(before.clauses.unspentCheck).toBe('unspent');

    // spend it (revoke)
    oracle.markSpent({ txid: 'a'.repeat(64), vout: 0 });

    // K15b transition + K15c: never re-authorizes across repeated checks
    for (let i = 0; i < 5; i++) {
      const after = await v.checkCapability(tok, HOLDER_PUBKEY, CAP_DOMAIN, ctx);
      expect(after.authorized).toBe(false);
      expect(after.clauses.unspentCheck).toBe('spent');
    }
  });

  test('K15c — only a FRESH mint (new outpoint) yields a new unspent capability', async () => {
    const v = new CapabilityTokenValidator(fakeStore({ 'holder-1': holderCert }));
    const oracle = new MonotoneSpendOracle();
    const ctx = oracle.spvContext(aliveVerifier, 'beef');

    oracle.markSpent({ txid: 'a'.repeat(64), vout: 0 }); // old cap spent

    // same (spent) outpoint — never authorizes
    const spent = await v.checkCapability(makeToken(v), HOLDER_PUBKEY, CAP_DOMAIN, ctx);
    expect(spent.authorized).toBe(false);

    // fresh mint = different outpoint — authorizes (K15c: minting a
    // new UTXO is the ONLY way to a successful capCheck again)
    const freshTok = v.createBrc108Token(
      {
        outpoint: { txid: 'b'.repeat(64), vout: 0 },
        issuerCertId: 'issuer-1',
        holderCertId: 'holder-1',
        domainFlag: CAP_DOMAIN,
        issuerDerivationDomain: PERMISSION_GRANT_DERIVATION,
        expiry: Date.now() + 60_000,
      },
      SIGNING_KEY,
    );
    const fresh = await v.checkCapability(freshTok, HOLDER_PUBKEY, CAP_DOMAIN, ctx);
    expect(fresh.authorized).toBe(true);
  });

  test('MonotoneSpendOracle — isSpent never regresses (append-only)', async () => {
    const oracle = new MonotoneSpendOracle();
    const op = { txid: 'c'.repeat(64), vout: 2 };
    expect(await oracle.isSpent(op)).toBe(false);
    oracle.markSpent(op);
    expect(await oracle.isSpent(op)).toBe(true);
    oracle.markSpent(op); // idempotent
    expect(await oracle.isSpent(op)).toBe(true); // still true — no unspend
  });
});

// ════════════════════════════════════════════════════════════════════
// SW4 — grant-domain enforcement (Wave Cap-Substrate).
//
// Oracle: CapabilityUtxoK15.lean K15d/K15e (wrong-cert/wrong-domain)
// SPECIALISED to grant/child-creation, discharged against the SHIPPED
// CapabilityTokenValidator.checkCapability + verifyChildCertIssuanceDomain
// (Client Reqs §2.2.3–4). "Proven but unwired" would fail PRD §0.2 —
// every assertion drives the real validator.
// ════════════════════════════════════════════════════════════════════

describe('SW4 — grant/child derivation-domain (K15 wrong-domain specialised)', () => {
  function tokenFromDomain(
    v: CapabilityTokenValidator,
    issuerDerivationDomain: number,
  ): Uint8Array {
    return v.createBrc108Token(
      {
        outpoint: { txid: 'd'.repeat(64), vout: 0 },
        issuerCertId: 'issuer-1',
        holderCertId: 'holder-1',
        domainFlag: CAP_DOMAIN,
        issuerDerivationDomain,
        expiry: Date.now() + 60_000,
      },
      SIGNING_KEY,
    );
  }

  test('K15-grant: a grant NOT from PERMISSION_GRANT (0x07) is rejected end-to-end', async () => {
    const v = new CapabilityTokenValidator(fakeStore({ 'holder-1': holderCert }));
    const ctx = new MonotoneSpendOracle().spvContext(aliveVerifier, 'beef');
    // Wrong derivation domains: child-creation, edge-creation, zero.
    for (const bad of [CHILD_CREATION_DERIVATION, 0x01, 0x00, 0x0a]) {
      const r = await v.checkCapability(
        tokenFromDomain(v, bad),
        HOLDER_PUBKEY,
        CAP_DOMAIN,
        ctx,
      );
      expect(r.authorized).toBe(false);
      expect(r.clauses.grantDomainValid).toBe(false);
      expect(r.reason).toContain('PERMISSION_GRANT');
      // Isolate SW4: the OTHER K15 conjuncts all held — only the
      // derivation-domain clause failed (true wrong-domain specialisation).
      expect(r.clauses.domainMatches).toBe(true);
      expect(r.clauses.certBinds).toBe(true);
      expect(r.clauses.unspentCheck).toBe('unspent');
    }
  });

  test('K15-grant: a grant from PERMISSION_GRANT (0x07) passes the SW4 clause and authorizes', async () => {
    const v = new CapabilityTokenValidator(fakeStore({ 'holder-1': holderCert }));
    const ctx = new MonotoneSpendOracle().spvContext(aliveVerifier, 'beef');
    const r = await v.checkCapability(
      tokenFromDomain(v, PERMISSION_GRANT_DERIVATION),
      HOLDER_PUBKEY,
      CAP_DOMAIN,
      ctx,
    );
    expect(r.clauses.grantDomainValid).toBe(true);
    expect(r.authorized).toBe(true);
  });

  test('K15-child: child-cert issuance MUST be CHILD_CREATION (0x06)', () => {
    const v = new CapabilityTokenValidator(fakeStore({ 'holder-1': holderCert }));
    // 0x06 ⇒ valid
    const ok = v.verifyChildCertIssuanceDomain(
      tokenFromDomain(v, CHILD_CREATION_DERIVATION),
    );
    expect(ok.valid).toBe(true);
    // Any other domain (incl. PERMISSION_GRANT) ⇒ rejected
    for (const bad of [PERMISSION_GRANT_DERIVATION, 0x01, 0x00]) {
      const r = v.verifyChildCertIssuanceDomain(tokenFromDomain(v, bad));
      expect(r.valid).toBe(false);
      if (!r.valid) expect(r.reason).toContain('CHILD_CREATION');
    }
  });

  test('SW4: issuerDerivationDomain is required — a token missing it fails parse', async () => {
    const v = new CapabilityTokenValidator(fakeStore({ 'holder-1': holderCert }));
    // Hand-craft a BRC-108 token WITHOUT issuerDerivationDomain.
    const noDomain = new TextEncoder().encode(
      JSON.stringify({
        version: 'brc108-v1',
        outpoint: { txid: 'e'.repeat(64), vout: 0 },
        issuerCertId: 'issuer-1',
        holderCertId: 'holder-1',
        domainFlag: CAP_DOMAIN,
        expiry: Date.now() + 60_000,
        signature: 'deadbeef',
      }),
    );
    const r = await v.checkCapability(noDomain, HOLDER_PUBKEY, CAP_DOMAIN);
    expect(r.authorized).toBe(false);
    expect(r.clauses.grantDomainValid).toBe(false);
    const c = v.verifyChildCertIssuanceDomain(noDomain);
    expect(c.valid).toBe(false);
  });
});

```
