---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/__tests__/fingerprint.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.060476+00:00
---

# runtime/session-protocol/src/rtc/__tests__/fingerprint.test.ts

```ts
/**
 * Fingerprint pin tests — RTC axis A. The pin records a peer's committed DTLS
 * fingerprint and the verify gate fails closed unless the observed handshake
 * fingerprint matches it.
 */

import { describe, it, expect } from '@jest/globals';
import { FingerprintPinStore, fingerprintsMatch } from '../fingerprint';
import type { DtlsFingerprint } from '../jingle';

const fp = (value: string, hash = 'sha-256', setup = 'actpass'): DtlsFingerprint => ({ hash, setup, value });
const A = 'AB:CD:EF:01:23:45';
const B = '99:88:77:66:55:44';
const CERT_A = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const CERT_B = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

describe('fingerprintsMatch', () => {
  it('matches identical values regardless of case / whitespace', () => {
    expect(fingerprintsMatch(fp(A), fp(A.toLowerCase()))).toBe(true);
    expect(fingerprintsMatch(fp(A), fp(` ${A} `))).toBe(true);
  });
  it('rejects a different value or a different hash algorithm', () => {
    expect(fingerprintsMatch(fp(A), fp(B))).toBe(false);
    expect(fingerprintsMatch(fp(A, 'sha-256'), fp(A, 'sha-1'))).toBe(false);
  });
  it('rejects an empty fingerprint', () => {
    expect(fingerprintsMatch(fp(''), fp(''))).toBe(false);
  });
});

describe('FingerprintPinStore', () => {
  it('pins, retrieves, and verifies a matching observed fingerprint', () => {
    const store = new FingerprintPinStore({ now: () => 1000 });
    const pin = store.pin('sid1', CERT_A, fp(A));
    expect(pin.pinnedAt).toBe(1000);
    expect(store.get('sid1')!.peerCertId).toBe(CERT_A);
    expect(store.verify('sid1', fp(A))).toBe(true);
  });

  it('fails closed — an unpinned call never verifies', () => {
    const store = new FingerprintPinStore();
    expect(store.verify('unknown', fp(A))).toBe(false);
  });

  it('rejects an endpoint presenting the wrong fingerprint (MITM)', () => {
    const store = new FingerprintPinStore();
    store.pin('sid1', CERT_A, fp(A));
    expect(store.verify('sid1', fp(B))).toBe(false);
  });

  it('is idempotent on an identical re-commit (retransmit)', () => {
    const store = new FingerprintPinStore();
    store.pin('sid1', CERT_A, fp(A));
    expect(() => store.pin('sid1', CERT_A, fp(A))).not.toThrow();
  });

  it('throws on a conflicting re-commit for the same sid (tamper signal)', () => {
    const store = new FingerprintPinStore();
    store.pin('sid1', CERT_A, fp(A));
    expect(() => store.pin('sid1', CERT_A, fp(B))).toThrow(/conflicting fingerprint/);
    expect(() => store.pin('sid1', CERT_B, fp(A))).toThrow(/refusing re-pin/);
  });

  it('clears a pin when the call ends', () => {
    const store = new FingerprintPinStore();
    store.pin('sid1', CERT_A, fp(A));
    store.clear('sid1');
    expect(store.get('sid1')).toBeUndefined();
    expect(store.verify('sid1', fp(A))).toBe(false);
  });
});

```
