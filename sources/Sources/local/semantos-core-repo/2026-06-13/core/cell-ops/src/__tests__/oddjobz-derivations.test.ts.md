---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/__tests__/oddjobz-derivations.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.831779+00:00
---

# core/cell-ops/src/__tests__/oddjobz-derivations.test.ts

```ts
/**
 * D-DOG.1.0c Phase 2B.4 — TS-side parity-oracle test for the
 * oddjobz cell-derivation surface.
 *
 * Drives every case in `tests/vectors/oddjobz-derivations.json`
 * through the TS implementation and asserts the output matches the
 * stamped `expected.*` field exactly. The Zig-side counterpart
 * (`runtime/semantos-brain/tests/oddjobz_derivations_parity_conformance.zig`)
 * loads the SAME fixture and asserts the SAME expected values — the
 * cross-language byte-equality claim is what makes this an oracle:
 * if either side drifts, one of the two tests fails.
 *
 * Three derivations covered:
 *
 *   1. `normaliseAddress` + `deriveLookupKey` (address → canonical
 *      form + lookup-key)
 *   2. `uuidV5LikeFromBytes` (32-byte cellID → 32-char UUID-shape hex)
 *   3. cellID hashes for site / customer / job / attachment
 *      (separator-string SHA-256)
 *
 * The TS implementations live in two packages:
 *
 *   • `cartridges/oddjobz/brain/src/cell-types/site.v2.ts` — public surface
 *     (normaliseAddress, deriveLookupKey)
 *   • `runtime/legacy-ingest/src/cell-writer/brain-rpc.ts` — internal
 *     FS-fallback derivations exposed via `__FS_FALLBACK_INTERNALS__`
 *     (the four cellID hashers + uuidV5LikeFromBytes + the local
 *     normaliseAddress mirror).
 *
 * Both TS sources MUST produce identical output for the address +
 * lookup-key derivations — the test asserts that explicitly via the
 * `address` cases.
 */

import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
  normaliseAddress as siteNormaliseAddress,
  deriveLookupKey as siteDeriveLookupKey,
} from '../../../../cartridges/oddjobz/brain/src/address-normalisation';
import { __FS_FALLBACK_INTERNALS__ } from '../../../../runtime/legacy-ingest/src/cell-writer/brain-rpc';

const {
  computeSiteCellId,
  computeCustomerCellId,
  computeJobCellId,
  computeAttachmentCellId,
  uuidV5LikeFromBytes,
  normaliseAddress: rpcNormaliseAddress,
  deriveLookupKey: rpcDeriveLookupKey,
} = __FS_FALLBACK_INTERNALS__;

// ─── Fixture types (mirror the generator's emitted shape) ─────────────

interface AddressCase {
  kind: 'address';
  name: string;
  input: { address: string; keyNumber: string | null };
  expected: { normalisedAddress: string; lookupKey: string };
}

interface UuidCase {
  kind: 'uuid';
  name: string;
  input: { bytes32Hex: string };
  expected: { uuidHex: string };
}

interface SiteCellCase {
  kind: 'site_cell_id';
  name: string;
  input: { normalisedAddress: string; keyNumber: string | null; fullAddress: string };
  expected: { cellIdHex: string };
}

interface CustomerCellCase {
  kind: 'customer_cell_id';
  name: string;
  input: { name: string; role: string; siteCellIdHex: string; phone: string; email: string };
  expected: { cellIdHex: string };
}

interface JobCellCase {
  kind: 'job_cell_id';
  name: string;
  input: {
    siteCellIdHex: string;
    customerRefs: Array<{ cellIdHex: string; role: string; primary: boolean }>;
    workOrderNumber: string;
    issuanceDate: string;
    dueDate: string;
    displayName: string;
    createdAt: string;
  };
  expected: { cellIdHex: string };
}

interface AttachmentCellCase {
  kind: 'attachment_cell_id';
  name: string;
  input: { jobCellIdHex: string; sourceAttachmentPath: string; createdAt: string };
  expected: { cellIdHex: string };
}

type Case =
  | AddressCase
  | UuidCase
  | SiteCellCase
  | CustomerCellCase
  | JobCellCase
  | AttachmentCellCase;

interface Fixture {
  _comment: string;
  version: number;
  cases: Case[];
}

// ─── Load fixture ─────────────────────────────────────────────────────

const FIXTURE_PATH = resolve(__dirname, '..', '..', 'tests', 'vectors', 'oddjobz-derivations.json');
const fixture = JSON.parse(readFileSync(FIXTURE_PATH, 'utf8')) as Fixture;

function fromHex(hex: string): Buffer {
  return Buffer.from(hex, 'hex');
}

// ─── Test entry ───────────────────────────────────────────────────────

describe('D-DOG.1.0c Phase 2B.4 — oddjobz derivation parity oracle (TS side)', () => {
  test('fixture file has the expected version + at least 20 cases', () => {
    expect(fixture.version).toBe(1);
    expect(fixture.cases.length).toBeGreaterThanOrEqual(20);
  });

  // Group cases by kind for readable output, but every case still runs.
  const byKind = new Map<string, Case[]>();
  for (const c of fixture.cases) {
    const arr = byKind.get(c.kind) ?? [];
    arr.push(c);
    byKind.set(c.kind, arr);
  }

  describe('address normalisation + lookupKey', () => {
    const addressCases = (byKind.get('address') ?? []) as AddressCase[];
    test('at least 5 address cases', () => {
      expect(addressCases.length).toBeGreaterThanOrEqual(5);
    });
    for (const c of addressCases) {
      test(`[address] ${c.name}`, () => {
        // Site-source-of-truth path (cartridges/oddjobz/brain).
        const norm = siteNormaliseAddress(c.input.address);
        const lookup = siteDeriveLookupKey(norm, c.input.keyNumber);
        expect(norm).toBe(c.expected.normalisedAddress);
        expect(lookup).toBe(c.expected.lookupKey);

        // Legacy-ingest mirror path — must also match. The two TS
        // implementations are independent (deliberately, to avoid
        // pulling extension code into the legacy-ingest pack); the
        // parity oracle asserts they stay byte-equal.
        const normRpc = rpcNormaliseAddress(c.input.address);
        const lookupRpc = rpcDeriveLookupKey(normRpc, c.input.keyNumber);
        expect(normRpc).toBe(c.expected.normalisedAddress);
        expect(lookupRpc).toBe(c.expected.lookupKey);
      });
    }
  });

  describe('uuidV5LikeFromBytes', () => {
    const uuidCases = (byKind.get('uuid') ?? []) as UuidCase[];
    test('at least 3 uuid cases', () => {
      expect(uuidCases.length).toBeGreaterThanOrEqual(3);
    });
    for (const c of uuidCases) {
      test(`[uuid] ${c.name}`, () => {
        const out = uuidV5LikeFromBytes(fromHex(c.input.bytes32Hex));
        expect(out).toBe(c.expected.uuidHex);
        // Output shape: 32 lowercase hex chars.
        expect(out).toMatch(/^[0-9a-f]{32}$/);
        // Version nibble (high nibble of byte 6, i.e. char index 12) is 4.
        expect(out.charAt(12)).toBe('4');
        // Variant high two bits (high nibble of byte 8, char 16) is 8/9/a/b.
        expect(['8', '9', 'a', 'b']).toContain(out.charAt(16));
      });
    }
  });

  describe('site cellID', () => {
    const siteCases = (byKind.get('site_cell_id') ?? []) as SiteCellCase[];
    test('at least 3 site cellID cases', () => {
      expect(siteCases.length).toBeGreaterThanOrEqual(3);
    });
    for (const c of siteCases) {
      test(`[site_cell_id] ${c.name}`, () => {
        const cellId = computeSiteCellId(
          c.input.normalisedAddress,
          c.input.keyNumber,
          c.input.fullAddress,
        );
        expect(cellId.length).toBe(32);
        expect(cellId.toString('hex')).toBe(c.expected.cellIdHex);
      });
    }
  });

  describe('customer cellID', () => {
    const customerCases = (byKind.get('customer_cell_id') ?? []) as CustomerCellCase[];
    test('at least 3 customer cellID cases', () => {
      expect(customerCases.length).toBeGreaterThanOrEqual(3);
    });
    for (const c of customerCases) {
      test(`[customer_cell_id] ${c.name}`, () => {
        const cellId = computeCustomerCellId(
          c.input.name,
          c.input.role,
          fromHex(c.input.siteCellIdHex),
          c.input.phone,
          c.input.email,
        );
        expect(cellId.toString('hex')).toBe(c.expected.cellIdHex);
      });
    }
  });

  describe('job cellID', () => {
    const jobCases = (byKind.get('job_cell_id') ?? []) as JobCellCase[];
    test('at least 3 job cellID cases', () => {
      expect(jobCases.length).toBeGreaterThanOrEqual(3);
    });
    for (const c of jobCases) {
      test(`[job_cell_id] ${c.name}`, () => {
        const cellId = computeJobCellId({
          siteCellIdBytes: fromHex(c.input.siteCellIdHex),
          customerRefs: c.input.customerRefs.map(r => ({
            cellIdBytes: fromHex(r.cellIdHex),
            role: r.role,
            primary: r.primary,
          })),
          workOrderNumber: c.input.workOrderNumber,
          issuanceDate: c.input.issuanceDate,
          dueDate: c.input.dueDate,
          displayName: c.input.displayName,
          createdAt: c.input.createdAt,
        });
        expect(cellId.toString('hex')).toBe(c.expected.cellIdHex);
      });
    }
  });

  describe('attachment cellID', () => {
    const attachmentCases = (byKind.get('attachment_cell_id') ?? []) as AttachmentCellCase[];
    test('at least 3 attachment cellID cases', () => {
      expect(attachmentCases.length).toBeGreaterThanOrEqual(3);
    });
    for (const c of attachmentCases) {
      test(`[attachment_cell_id] ${c.name}`, () => {
        const cellId = computeAttachmentCellId(
          fromHex(c.input.jobCellIdHex),
          c.input.sourceAttachmentPath,
          c.input.createdAt,
        );
        expect(cellId.toString('hex')).toBe(c.expected.cellIdHex);
      });
    }
  });
});

```
