---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/policy-runtime/src/__tests__/authority.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.492612+00:00
---

# packages/policy-runtime/src/__tests__/authority.test.ts

```ts
/**
 * D-A6 — extension authority gate at PolicyRuntime.loadExtension.
 *
 * Covers:
 *   1. Loading an extension with a valid authority succeeds; the
 *      authority cert_id is recorded as the capability scope key.
 *   2. Loading without an injected verifier defaults to
 *      RejectAuthorityVerifier and refuses every authority.
 *   3. A malformed cert is rejected at load time
 *      (ExtensionAuthorityError code = authority_cert_invalid).
 *   4. A missing grammar signature is rejected
 *      (code = grammar_signature_missing).
 *   5. Two extensions with different authority cert_ids produce
 *      isolated capability scopes — the runtime exposes them via
 *      separate authorityCertId values.
 *   6. unloadExtension drops the record so subsequent
 *      capability-scope dispatch is structurally impossible.
 */

import { describe, test, expect } from 'bun:test';
import { PolicyRuntime } from '../runtime';
import {
  ExtensionAuthorityError,
  StubAuthorityVerifier,
  type AuthorityVerifier,
  type LexiconAuthority,
} from '../authority';

// ── Test doubles ─────────────────────────────────────────────
//
// PolicyRuntime accepts CellEngine + HostFunctionRegistry in its
// constructor. Authority-gating tests don't exercise the WASM path —
// they only validate `loadExtension` / `getExtension` / `unloadExtension`,
// so a thin no-op double for engine/registry is sufficient.

const fakeEngine: any = {
  executeScript: () => ({ success: true, opcodeCount: 0 }),
};
const fakeRegistry: any = {
  call: () => 0,
  setContext: () => {},
  clearContext: () => {},
};

function makeRuntime(verifier?: AuthorityVerifier): PolicyRuntime {
  return new PolicyRuntime(fakeEngine, fakeRegistry, [], {
    authorityVerifier: verifier,
  });
}

const VALID_AUTHORITY: LexiconAuthority = {
  cert: {
    certId: 'a'.repeat(64),
    subjectPublicKey: '02' + 'b'.repeat(64),
  },
  grammarSignature: '30' + 'cd'.repeat(35),
  grammarBytes: new TextEncoder().encode('{"grammarId":"com.example.cdm"}'),
};

// ── Tests ────────────────────────────────────────────────────

describe('D-A6 — PolicyRuntime extension authority gate', () => {
  test('PA1: valid authority loads successfully and records cert_id as scope key', async () => {
    const rt = makeRuntime(new StubAuthorityVerifier());
    const record = await rt.loadExtension('cdm', VALID_AUTHORITY);
    expect(record.extensionId).toBe('cdm');
    expect(record.authorityCertId).toBe(VALID_AUTHORITY.cert.certId);
    expect(rt.getExtension('cdm')?.authorityCertId).toBe(
      VALID_AUTHORITY.cert.certId,
    );
  });

  test('PA2: default verifier (no injection) rejects every authority', async () => {
    const rt = makeRuntime(); // no verifier injected
    let thrown: unknown;
    try {
      await rt.loadExtension('cdm', VALID_AUTHORITY);
    } catch (err) {
      thrown = err;
    }
    expect(thrown).toBeInstanceOf(ExtensionAuthorityError);
    expect((thrown as ExtensionAuthorityError).code).toBe('authority_cert_invalid');
    expect(rt.getExtension('cdm')).toBeUndefined();
  });

  test('PA3: malformed cert (missing subjectPublicKey) is rejected at load', async () => {
    const rt = makeRuntime(new StubAuthorityVerifier());
    const bad: LexiconAuthority = {
      ...VALID_AUTHORITY,
      cert: { certId: VALID_AUTHORITY.cert.certId, subjectPublicKey: '' },
    };
    let err: ExtensionAuthorityError | null = null;
    try {
      await rt.loadExtension('cdm', bad);
    } catch (e) {
      err = e as ExtensionAuthorityError;
    }
    expect(err).not.toBeNull();
    expect(err!.code).toBe('authority_cert_invalid');
    expect(err!.extensionId).toBe('cdm');
    expect(rt.getExtension('cdm')).toBeUndefined();
  });

  test('PA4: missing grammar signature is rejected at load', async () => {
    const rt = makeRuntime(new StubAuthorityVerifier());
    const bad: LexiconAuthority = { ...VALID_AUTHORITY, grammarSignature: '' };
    let err: ExtensionAuthorityError | null = null;
    try {
      await rt.loadExtension('cdm', bad);
    } catch (e) {
      err = e as ExtensionAuthorityError;
    }
    expect(err).not.toBeNull();
    expect(err!.code).toBe('grammar_signature_missing');
  });

  test('PA5: capability-scope isolation — two extensions, two different cert_ids', async () => {
    const rt = makeRuntime(new StubAuthorityVerifier());
    const certA: LexiconAuthority = {
      ...VALID_AUTHORITY,
      cert: { ...VALID_AUTHORITY.cert, certId: 'a'.repeat(64) },
    };
    const certB: LexiconAuthority = {
      ...VALID_AUTHORITY,
      cert: { ...VALID_AUTHORITY.cert, certId: 'b'.repeat(64) },
    };

    await rt.loadExtension('cdm', certA);
    await rt.loadExtension('scada', certB);

    expect(rt.getExtension('cdm')?.authorityCertId).toBe(certA.cert.certId);
    expect(rt.getExtension('scada')?.authorityCertId).toBe(certB.cert.certId);
    expect(rt.getExtension('cdm')?.authorityCertId).not.toBe(
      rt.getExtension('scada')?.authorityCertId,
    );
  });

  test('PA6: unloadExtension removes the record so cross-scope dispatch is impossible', async () => {
    const rt = makeRuntime(new StubAuthorityVerifier());
    await rt.loadExtension('cdm', VALID_AUTHORITY);
    expect(rt.getExtension('cdm')).toBeDefined();

    const removed = rt.unloadExtension('cdm');
    expect(removed).toBe(true);
    expect(rt.getExtension('cdm')).toBeUndefined();

    // Idempotent: second unload is a no-op (returns false).
    expect(rt.unloadExtension('cdm')).toBe(false);
  });

  test('PA7: re-loading the same extensionId re-verifies (no stale-state hazard)', async () => {
    let verifyCalls = 0;
    const tracking: AuthorityVerifier = {
      verifyAuthority(authority) {
        verifyCalls += 1;
        return { ok: true, certId: authority.cert.certId };
      },
    };
    const rt = makeRuntime(tracking);
    await rt.loadExtension('cdm', VALID_AUTHORITY);
    await rt.loadExtension('cdm', VALID_AUTHORITY);
    expect(verifyCalls).toBe(2);
  });

  test('PA8: a verifier failing with grammar_signature_invalid surfaces that code unchanged', async () => {
    const failing: AuthorityVerifier = {
      verifyAuthority() {
        return {
          ok: false,
          code: 'grammar_signature_invalid',
          message: 'ECDSA verify returned false',
        };
      },
    };
    const rt = makeRuntime(failing);
    let err: ExtensionAuthorityError | null = null;
    try {
      await rt.loadExtension('cdm', VALID_AUTHORITY);
    } catch (e) {
      err = e as ExtensionAuthorityError;
    }
    expect(err).not.toBeNull();
    expect(err!.code).toBe('grammar_signature_invalid');
  });
});

```
