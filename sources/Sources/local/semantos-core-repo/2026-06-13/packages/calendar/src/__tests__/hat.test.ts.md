---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/__tests__/hat.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.481914+00:00
---

# packages/calendar/src/__tests__/hat.test.ts

```ts
/**
 * D-A5 — Calendar Hat → BRC-52 migration tests.
 *
 * Coverage:
 *   H1 createHat (legacy opaque-id path) round-trips through getHat with
 *      certBacking == null (backward compat).
 *   H2 deriveHatCertId is deterministic and yields a 64-char lowercase
 *      hex string equal to computeCertId of the synthesised cert.
 *   H3 cross-context isolation (§4.4): two hats with the same
 *      displayName + subjectPublicKey but different contextTags produce
 *      different cert_ids.
 *   H4 cross-context isolation under different subject keys: distinct
 *      BRC-42-derived subject keys (different domain flags) produce
 *      different cert_ids regardless of contextTag — the BRC-42-mediated
 *      key separation is what §4.4 ultimately requires.
 *   H5 BRC-52-backed createHat asserts input.id == computeCertId(cert);
 *      mismatched ids are rejected.
 *   H6 contextTag mismatch between input.contextTag and cert.fields.contextTag
 *      is rejected.
 *   H7 createHat with a fully-formed Brc52Cert persists certBacking and
 *      round-trips it through getHat / listHats.
 *   H8 hatIdOf alias returns record.id (deprecated alias path).
 *   H9 Migration: a payload row stored under the legacy schema (no
 *      certBacking field) round-trips through getHat without throwing —
 *      certBacking comes back null.
 *
 * §4.4 cross-context isolation language:
 *   "Key universes for distinct contexts MUST be mathematically
 *    isolated via divergent BRC-42 derivation paths using domain flags
 *    (§4.5); keys derived in one context MUST NOT be mathematically
 *    related to keys in another."
 *
 * The mathematical isolation lives in the BRC-42 derivation function
 * itself (which is the responsibility of the wallet / vendor SDK).
 * D-A5's contribution is the cert_id layer: even if BRC-42 is bypassed,
 * the contextTag participates in the BRC-52 preimage so the cert_id
 * diverges, and the record's certBacking captures contextTag for audit.
 */
import { describe, expect, test } from 'bun:test';
import { computeCertId, type Brc52Cert } from '@plexus/contracts';
import { makeTestDb } from './setup.js';
import {
  createHat,
  getHat,
  listHats,
  hatIdOf,
  deriveHatCertId,
  buildHatCert,
  type HatRecord,
} from '../domain/hat.js';

const PUBKEY_A = '02' + 'aa'.repeat(32);
const PUBKEY_B = '02' + 'bb'.repeat(32);
const ROOT_PUBKEY = '02' + 'cc'.repeat(32);

describe('D-A5 — Calendar Hat → BRC-52 cert backing', () => {
  test('H1 legacy opaque-id createHat round-trips with certBacking == null', async () => {
    const { db, close } = await makeTestDb();
    try {
      const created = await createHat(db, {
        id: 'legacy-handyman',
        displayName: 'Todd (handyman)',
        timezone: 'Australia/Brisbane',
        ownerCertId: 'cert-todd',
      });
      expect(created.id).toBe('legacy-handyman');
      expect(created.certBacking).toBeNull();

      const fetched = await getHat(db, 'legacy-handyman');
      expect(fetched).not.toBeNull();
      expect((fetched as HatRecord).certBacking).toBeNull();
      expect((fetched as HatRecord).displayName).toBe('Todd (handyman)');
    } finally {
      await close();
    }
  });

  test('H2 deriveHatCertId is deterministic and matches computeCertId', () => {
    const id1 = deriveHatCertId({
      subjectPublicKey: PUBKEY_A,
      certifierPublicKey: ROOT_PUBKEY,
      contextTag: 'personal-calendar',
      displayName: 'Todd',
    });
    const id2 = deriveHatCertId({
      subjectPublicKey: PUBKEY_A,
      certifierPublicKey: ROOT_PUBKEY,
      contextTag: 'personal-calendar',
      displayName: 'Todd',
    });
    expect(id1).toBe(id2);
    expect(id1).toMatch(/^[0-9a-f]{64}$/);

    const cert = buildHatCert({
      subjectPublicKey: PUBKEY_A,
      certifierPublicKey: ROOT_PUBKEY,
      contextTag: 'personal-calendar',
      displayName: 'Todd',
    });
    expect(cert.certId).toBe(id1);
    expect(computeCertId(cert)).toBe(id1);
  });

  test('H3 §4.4 cross-context isolation — same key, two contextTags → different cert_ids', () => {
    const personal = deriveHatCertId({
      subjectPublicKey: PUBKEY_A,
      certifierPublicKey: ROOT_PUBKEY,
      contextTag: 'personal-calendar',
      displayName: 'Todd',
    });
    const work = deriveHatCertId({
      subjectPublicKey: PUBKEY_A,
      certifierPublicKey: ROOT_PUBKEY,
      contextTag: 'work-calendar',
      displayName: 'Todd',
    });
    expect(personal).not.toBe(work);
  });

  test('H4 §4.4 — distinct BRC-42-derived subject keys → different cert_ids', () => {
    // Simulates BRC-42 BKDS divergence: domain flag 0x01 vs 0x02 yields
    // mathematically unrelated subject keys; cert_ids must diverge too.
    const ctx = 'personal-calendar';
    const idA = deriveHatCertId({
      subjectPublicKey: PUBKEY_A,
      certifierPublicKey: ROOT_PUBKEY,
      contextTag: ctx,
      displayName: 'Todd',
    });
    const idB = deriveHatCertId({
      subjectPublicKey: PUBKEY_B,
      certifierPublicKey: ROOT_PUBKEY,
      contextTag: ctx,
      displayName: 'Todd',
    });
    expect(idA).not.toBe(idB);
  });

  test('H5 BRC-52-backed createHat rejects id ≠ computeCertId(cert)', async () => {
    const { db, close } = await makeTestDb();
    try {
      const cert = buildHatCert({
        subjectPublicKey: PUBKEY_A,
        certifierPublicKey: ROOT_PUBKEY,
        contextTag: 'personal-calendar',
        displayName: 'Todd',
      });
      let err: unknown = null;
      try {
        await createHat(db, {
          id: 'wrong-id',
          displayName: 'Todd',
          timezone: 'UTC',
          ownerCertId: 'cert-todd',
          cert,
        });
      } catch (e) { err = e; }
      expect(err).toBeInstanceOf(Error);
      expect((err as Error).message).toContain('input.id');
    } finally {
      await close();
    }
  });

  test('H6 createHat rejects contextTag/cert.fields.contextTag mismatch', async () => {
    const { db, close } = await makeTestDb();
    try {
      const cert = buildHatCert({
        subjectPublicKey: PUBKEY_A,
        certifierPublicKey: ROOT_PUBKEY,
        contextTag: 'personal-calendar',
        displayName: 'Todd',
      });
      let err: unknown = null;
      try {
        await createHat(db, {
          id: cert.certId,
          displayName: 'Todd',
          timezone: 'UTC',
          ownerCertId: 'cert-todd',
          cert,
          contextTag: 'work-calendar',
        });
      } catch (e) { err = e; }
      expect(err).toBeInstanceOf(Error);
      expect((err as Error).message).toContain('contextTag mismatch');
    } finally {
      await close();
    }
  });

  test('H7 BRC-52-backed createHat persists certBacking and round-trips', async () => {
    const { db, close } = await makeTestDb();
    try {
      const cert: Brc52Cert = buildHatCert({
        subjectPublicKey: PUBKEY_A,
        certifierPublicKey: ROOT_PUBKEY,
        contextTag: 'personal-calendar',
        displayName: 'Todd',
      });
      const created = await createHat(db, {
        id: cert.certId,
        displayName: 'Todd',
        timezone: 'Australia/Brisbane',
        ownerCertId: 'cert-todd',
        cert,
      });
      expect(created.id).toBe(cert.certId);
      expect(created.certBacking).not.toBeNull();
      expect(created.certBacking?.subjectPublicKey).toBe(PUBKEY_A);
      expect(created.certBacking?.contextTag).toBe('personal-calendar');
      expect(created.certBacking?.type).toBe('calendar.hat');

      const fetched = await getHat(db, cert.certId);
      expect(fetched).not.toBeNull();
      expect((fetched as HatRecord).certBacking?.subjectPublicKey).toBe(PUBKEY_A);
      expect((fetched as HatRecord).certBacking?.contextTag).toBe('personal-calendar');

      const all = await listHats(db);
      const found = all.find((h) => h.id === cert.certId);
      expect(found).toBeDefined();
      expect(found?.certBacking?.subjectPublicKey).toBe(PUBKEY_A);
    } finally {
      await close();
    }
  });

  test('H8 hatIdOf returns record.id (deprecated alias path)', async () => {
    const { db, close } = await makeTestDb();
    try {
      const created = await createHat(db, {
        id: 'alias-test',
        displayName: 'Aliased Hat',
        timezone: 'UTC',
        ownerCertId: 'cert-todd',
      });
      expect(hatIdOf(created)).toBe('alias-test');
      expect(hatIdOf(created)).toBe(created.id);
    } finally {
      await close();
    }
  });

  test('H9 migration: pre-existing seeded hat (no certBacking) round-trips', async () => {
    // The default makeTestDb seeds 'todd-operator', 'todd-handyman',
    // 'todd-advisor' via the legacy opaque-id path. This test asserts
    // that getHat / listHats handle the absent-certBacking case
    // gracefully — i.e. the migration is non-breaking for serialised
    // records that pre-date D-A5.
    const { db, close } = await makeTestDb();
    try {
      const operator = await getHat(db, 'todd-operator');
      expect(operator).not.toBeNull();
      expect((operator as HatRecord).certBacking).toBeNull();

      const handyman = await getHat(db, 'todd-handyman');
      expect(handyman).not.toBeNull();
      expect((handyman as HatRecord).certBacking).toBeNull();

      const all = await listHats(db);
      // All seeded fixture hats lack certBacking by construction.
      for (const h of all) {
        expect(h.certBacking).toBeNull();
      }
    } finally {
      await close();
    }
  });
});

```
