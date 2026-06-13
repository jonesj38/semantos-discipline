---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-sir/src/__tests__/authority.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.814773+00:00
---

# core/semantos-sir/src/__tests__/authority.test.ts

```ts
/**
 * D-A6 — lexicon authority gating in the SIR lowering pass.
 *
 * Covers:
 *   1. A program with no `authority` lowers as before (back-compat).
 *   2. A program with an authority but no verification → REJECT
 *      with LEXICON_AUTHORITY_INVALID.
 *   3. `lowerSIRWithAuthority` + StubAuthorityVerifier accepts a
 *      well-formed authority.
 *   4. Missing grammar signature → GRAMMAR_SIGNATURE_INVALID.
 *   5. Different `cert.certId` values produce different OIR
 *      authority-scope domainCheck flags (capability-scope isolation).
 *   6. The default `RejectAuthorityVerifier` rejects every authority.
 *
 * Spec source: docs/spec/protocol-v0.5.md §4 (Identity), §5 (Capability tokens).
 */

import { describe, test, expect } from 'bun:test';
import { lowerSIR, lowerSIRWithAuthority } from '../lower-sir';
import {
  StubAuthorityVerifier,
  RejectAuthorityVerifier,
  type AuthorityVerifier,
  type AuthorityVerificationResult,
  type LexiconAuthority,
} from '../authority';
import type { SIRNode, SIRProgram, GovernanceContext } from '../types';

// ── Fixtures ─────────────────────────────────────────────────

function gov(overrides: Partial<GovernanceContext> = {}): GovernanceContext {
  return {
    trustClass: 'interpretive',
    proofRequirement: 'attestation',
    executionAuthority: 'hat_scoped',
    linearity: 'AFFINE',
    ...overrides,
  };
}

const prov = {
  source: 'manual' as const,
  expressedAt: '2026-04-26T00:00:00Z',
  trustAtExpression: 'interpretive' as const,
};

function nodeWithCapability(): SIRNode {
  return {
    id: '$s0',
    category: { lexicon: 'jural', category: 'permission' },
    taxonomy: { what: 'rates.swap', how: 'lifecycle', why: 'mint-cap' },
    identity: { subject: { type: 'role', name: 'cdm-issuer' } },
    governance: gov(),
    action: 'mint',
    constraint: { kind: 'capability', required: 0x07, name: 'cap-mint' },
    provenance: prov,
  };
}

function programWith(authority?: LexiconAuthority): SIRProgram {
  const node = nodeWithCapability();
  return {
    nodes: [node],
    primaryNodeId: node.id,
    programGovernance: gov(),
    authority,
  };
}

const VALID_AUTHORITY: LexiconAuthority = {
  cert: {
    certId: 'a'.repeat(64),
    subjectPublicKey: '02' + 'b'.repeat(64),
  },
  grammarSignature: '30' + 'cd'.repeat(35), // dummy DER hex
  grammarBytes: new TextEncoder().encode('{"grammarId":"com.example.cdm"}'),
};

// ── Tests ────────────────────────────────────────────────────

describe('D-A6 — lexicon authority gating', () => {
  test('SA1: program without authority lowers normally (back-compat)', () => {
    const prog = programWith(undefined);
    const r = lowerSIR(prog);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    // No domainCheck-by-cert binding when no authority is declared.
    const certScopeCheck = r.program.bindings.find(
      (b) => b.kind === 'domainCheck' && typeof b.domainFlag === 'string' && b.domainFlag.length === 64,
    );
    expect(certScopeCheck).toBeUndefined();
  });

  test('SA2: sync lowerSIR rejects programs with authority and no precomputed verification', () => {
    const prog = programWith(VALID_AUTHORITY);
    const r = lowerSIR(prog);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe('LEXICON_AUTHORITY_INVALID');
  });

  test('SA3: lowerSIRWithAuthority + StubAuthorityVerifier accepts valid authority', async () => {
    const prog = programWith(VALID_AUTHORITY);
    const r = await lowerSIRWithAuthority(prog, new StubAuthorityVerifier());
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    // The authority cert_id MUST appear as a domainCheck flag in the OIR.
    const scopeBinding = r.program.bindings.find(
      (b) => b.kind === 'domainCheck' && b.domainFlag === VALID_AUTHORITY.cert.certId,
    );
    expect(scopeBinding).toBeDefined();
  });

  test('SA4: missing grammar signature → GRAMMAR_SIGNATURE_INVALID', async () => {
    const bad: LexiconAuthority = {
      ...VALID_AUTHORITY,
      grammarSignature: '',
    };
    const r = await lowerSIRWithAuthority(programWith(bad), new StubAuthorityVerifier());
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe('GRAMMAR_SIGNATURE_INVALID');
  });

  test('SA5: missing grammarBytes → GRAMMAR_SIGNATURE_INVALID', async () => {
    const bad: LexiconAuthority = {
      ...VALID_AUTHORITY,
      grammarBytes: new Uint8Array(0),
    };
    const r = await lowerSIRWithAuthority(programWith(bad), new StubAuthorityVerifier());
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe('GRAMMAR_SIGNATURE_INVALID');
  });

  test('SA6: malformed cert (missing subjectPublicKey) → LEXICON_AUTHORITY_INVALID', async () => {
    const bad: LexiconAuthority = {
      ...VALID_AUTHORITY,
      cert: { certId: VALID_AUTHORITY.cert.certId, subjectPublicKey: '' },
    };
    const r = await lowerSIRWithAuthority(programWith(bad), new StubAuthorityVerifier());
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe('LEXICON_AUTHORITY_INVALID');
  });

  test('SA7: default verifier (RejectAuthorityVerifier) refuses every authority', async () => {
    const r = await lowerSIRWithAuthority(programWith(VALID_AUTHORITY));
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe('LEXICON_AUTHORITY_INVALID');
  });

  test('SA8: capability-scope isolation — different cert_ids → different OIR scope flag', async () => {
    const certA = { ...VALID_AUTHORITY, cert: { ...VALID_AUTHORITY.cert, certId: 'a'.repeat(64) } };
    const certB = { ...VALID_AUTHORITY, cert: { ...VALID_AUTHORITY.cert, certId: 'b'.repeat(64) } };

    const verifier = new StubAuthorityVerifier();
    const rA = await lowerSIRWithAuthority(programWith(certA), verifier);
    const rB = await lowerSIRWithAuthority(programWith(certB), verifier);

    expect(rA.ok).toBe(true);
    expect(rB.ok).toBe(true);
    if (!rA.ok || !rB.ok) return;

    const flagA = rA.program.bindings.find((b) => b.kind === 'domainCheck' && b.domainFlag === certA.cert.certId);
    const flagB = rB.program.bindings.find((b) => b.kind === 'domainCheck' && b.domainFlag === certB.cert.certId);

    expect(flagA).toBeDefined();
    expect(flagB).toBeDefined();
    expect(flagA!.domainFlag).not.toBe(flagB!.domainFlag);
  });

  test('SA9: failing verifier surfaces its code mapped to LEXICON_AUTHORITY_INVALID', async () => {
    const failingVerifier: AuthorityVerifier = {
      verifyAuthority(): AuthorityVerificationResult {
        return {
          ok: false,
          code: 'authority_cert_invalid',
          message: 'cert_id_mismatch (test fixture)',
        };
      },
    };
    const r = await lowerSIRWithAuthority(programWith(VALID_AUTHORITY), failingVerifier);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.code).toBe('LEXICON_AUTHORITY_INVALID');
    expect(r.message).toContain('cert_id_mismatch');
  });

  test('SA10: programs without authority bypass the verifier entirely', async () => {
    let calls = 0;
    const trackingVerifier: AuthorityVerifier = {
      verifyAuthority() {
        calls += 1;
        return { ok: true, certId: 'never-reached' };
      },
    };
    const r = await lowerSIRWithAuthority(programWith(undefined), trackingVerifier);
    expect(r.ok).toBe(true);
    expect(calls).toBe(0);
  });
});

```
