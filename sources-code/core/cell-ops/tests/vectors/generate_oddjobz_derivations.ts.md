---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/tests/vectors/generate_oddjobz_derivations.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.826296+00:00
---

# core/cell-ops/tests/vectors/generate_oddjobz_derivations.ts

```ts
/**
 * D-DOG.1.0c Phase 2B.4 — generator for the oddjobz cell-derivations
 * cross-language parity oracle.
 *
 * Usage:
 *
 *   bun core/cell-ops/tests/vectors/generate_oddjobz_derivations.ts
 *
 * Produces `oddjobz-derivations.json` next to this file. The file is
 * consumed by:
 *
 *   • `core/cell-ops/src/__tests__/oddjobz-derivations.test.ts` (TS),
 *   • `runtime/semantos-brain/tests/oddjobz_derivations_parity_conformance.zig`
 *     (Zig).
 *
 * Both tests assert that the implementation in their language produces
 * EXACTLY the expected output stamped in the fixture. If TS and Zig
 * produce divergent output for the same input, one of the tests fails
 * — that's the parity oracle.
 *
 * The generator imports the TS implementations directly and stamps
 * their output into `expected.*`. The Zig side is checked against the
 * same expected values. By construction, the fixture cannot land
 * mis-stamped: regenerating it always re-derives `expected` from the
 * TS source.
 *
 * Deterministic — no Date.now(), no Math.random(). Re-running the
 * generator on a clean tree must produce a byte-identical JSON file.
 */

import { writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  normaliseAddress,
  deriveLookupKey,
} from '../../../../cartridges/oddjobz/brain/src/address-normalisation.js';
import { __FS_FALLBACK_INTERNALS__ } from '../../../../runtime/legacy-ingest/src/cell-writer/brain-rpc.js';

const {
  computeSiteCellId,
  computeCustomerCellId,
  computeJobCellId,
  computeAttachmentCellId,
  uuidV5LikeFromBytes,
} = __FS_FALLBACK_INTERNALS__;

// ─── Vector shape ─────────────────────────────────────────────────────

type AddressCase = {
  readonly kind: 'address';
  readonly name: string;
  readonly input: { readonly address: string; readonly keyNumber: string | null };
  readonly expected: { readonly normalisedAddress: string; readonly lookupKey: string };
};

type UuidCase = {
  readonly kind: 'uuid';
  readonly name: string;
  readonly input: { readonly bytes32Hex: string };
  readonly expected: { readonly uuidHex: string };
};

type SiteCellCase = {
  readonly kind: 'site_cell_id';
  readonly name: string;
  readonly input: {
    readonly normalisedAddress: string;
    readonly keyNumber: string | null;
    readonly fullAddress: string;
  };
  readonly expected: { readonly cellIdHex: string };
};

type CustomerCellCase = {
  readonly kind: 'customer_cell_id';
  readonly name: string;
  readonly input: {
    readonly name: string;
    readonly role: string;
    readonly siteCellIdHex: string;
    readonly phone: string;
    readonly email: string;
  };
  readonly expected: { readonly cellIdHex: string };
};

type JobCellCase = {
  readonly kind: 'job_cell_id';
  readonly name: string;
  readonly input: {
    readonly siteCellIdHex: string;
    readonly customerRefs: ReadonlyArray<{
      readonly cellIdHex: string;
      readonly role: string;
      readonly primary: boolean;
    }>;
    readonly workOrderNumber: string;
    readonly issuanceDate: string;
    readonly dueDate: string;
    readonly displayName: string;
    readonly createdAt: string;
  };
  readonly expected: { readonly cellIdHex: string };
};

type AttachmentCellCase = {
  readonly kind: 'attachment_cell_id';
  readonly name: string;
  readonly input: {
    readonly jobCellIdHex: string;
    readonly sourceAttachmentPath: string;
    readonly createdAt: string;
  };
  readonly expected: { readonly cellIdHex: string };
};

type Case =
  | AddressCase
  | UuidCase
  | SiteCellCase
  | CustomerCellCase
  | JobCellCase
  | AttachmentCellCase;

// ─── Helpers ──────────────────────────────────────────────────────────

function fromHex(hex: string): Buffer {
  return Buffer.from(hex, 'hex');
}

function toHex(buf: Buffer): string {
  return buf.toString('hex');
}

// Stable 32-byte vector source — repeating the byte index lets the
// reader-by-eye spot the offsets in the hex.
function bytes32At(seed: number): string {
  const out = Buffer.alloc(32);
  for (let i = 0; i < 32; i++) {
    out[i] = (seed + i) & 0xff;
  }
  return toHex(out);
}

// ─── Vectors ──────────────────────────────────────────────────────────

const cases: Case[] = [];

// ── 1. Address normalisation + lookup-key cases ─────────────────────
const addressInputs: Array<{ name: string; address: string; keyNumber: string | null }> = [
  {
    name: 'whitespace-collapse and lowercase typical Australian address',
    address: '  29 Foedera   Cres,  Tewantin QLD 4565  ',
    keyNumber: 'key #177',
  },
  { name: 'no key number → empty suffix after pipe', address: '13 Orealla Cr', keyNumber: null },
  {
    name: 'key number present (apartment/unit suffix)',
    address: '13 Orealla Cr',
    keyNumber: 'unit 4',
  },
  { name: 'empty input → empty normalised → bare pipe', address: '', keyNumber: null },
  {
    name: 'whitespace-only input collapses to empty',
    address: '     \t\n  ',
    keyNumber: null,
  },
  {
    name: 'tabs and newlines treated as whitespace',
    address: '7\tBay\nView\rRd',
    keyNumber: null,
  },
  {
    name: 'unicode preserved (no folding) but ASCII lowercased',
    address: '12 Café Lane, Tewantin',
    keyNumber: null,
  },
  {
    name: 'multiple internal spaces collapse to one',
    address: 'A    B    C',
    keyNumber: 'k1',
  },
  {
    name: 'key number with pipe character (does not break separator since pipe is part of suffix)',
    address: '5 Test St',
    keyNumber: 'key|1',
  },
  {
    name: 'long input',
    address:
      '  Lot 42  Hawkesbury  Heights  Pacific  Highway  Wagga  Wagga  NSW  2650  Australia  ',
    keyNumber: 'site-A',
  },
];

for (const c of addressInputs) {
  const normalised = normaliseAddress(c.address);
  const lookupKey = deriveLookupKey(normalised, c.keyNumber);
  cases.push({
    kind: 'address',
    name: c.name,
    input: { address: c.address, keyNumber: c.keyNumber },
    expected: { normalisedAddress: normalised, lookupKey },
  });
}

// ── 2. UUID v4-shape from cellID bytes ──────────────────────────────
const uuidSeeds: Array<{ name: string; hex: string }> = [
  { name: 'all-zero source', hex: '00'.repeat(32) },
  { name: 'all-0xff source (forces version+variant nibble masks)', hex: 'ff'.repeat(32) },
  {
    name: 'sequential bytes 0..31',
    hex: bytes32At(0),
  },
  {
    name: 'sequential bytes 0x80..0x9f (variant byte starts at 0x88, exercises mask)',
    hex: bytes32At(0x80),
  },
  {
    name: 'realistic SHA-256 output (computed by computeSiteCellId)',
    hex: toHex(computeSiteCellId('29 foedera cres', 'k1', '29 Foedera Cres')),
  },
  {
    name: 'realistic SHA-256 output (computed by computeCustomerCellId)',
    hex: toHex(
      computeCustomerCellId(
        'Jane Doe',
        'agent',
        fromHex(bytes32At(0)),
        '+61400111222',
        'jane@example.com',
      ),
    ),
  },
];

for (const u of uuidSeeds) {
  const uuidHex = uuidV5LikeFromBytes(fromHex(u.hex));
  cases.push({
    kind: 'uuid',
    name: u.name,
    input: { bytes32Hex: u.hex },
    expected: { uuidHex },
  });
}

// ── 3. Site cellID cases ────────────────────────────────────────────
const siteInputs: Array<{
  name: string;
  normalisedAddress: string;
  keyNumber: string | null;
  fullAddress: string;
}> = [
  {
    name: 'typical site with key number',
    normalisedAddress: '29 foedera cres, tewantin qld 4565',
    keyNumber: 'key #177',
    fullAddress: '29 Foedera Cres, Tewantin QLD 4565',
  },
  {
    name: 'site without key number (null collapses to empty in hash preimage)',
    normalisedAddress: '13 orealla cr',
    keyNumber: null,
    fullAddress: '13 Orealla Cr',
  },
  {
    name: 'site with empty fullAddress (still hashes deterministically)',
    normalisedAddress: '',
    keyNumber: null,
    fullAddress: '',
  },
  {
    name: 'two units at the same building disambiguate via keyNumber',
    normalisedAddress: 'apartments at 100 main st',
    keyNumber: 'unit 4',
    fullAddress: 'Apartments at 100 Main St',
  },
  {
    name: 'unicode in fullAddress',
    normalisedAddress: '12 café lane, tewantin',
    keyNumber: null,
    fullAddress: '12 Café Lane, Tewantin',
  },
];

for (const s of siteInputs) {
  const cellId = computeSiteCellId(s.normalisedAddress, s.keyNumber, s.fullAddress);
  cases.push({
    kind: 'site_cell_id',
    name: s.name,
    input: {
      normalisedAddress: s.normalisedAddress,
      keyNumber: s.keyNumber,
      fullAddress: s.fullAddress,
    },
    expected: { cellIdHex: toHex(cellId) },
  });
}

// ── 4. Customer cellID cases ────────────────────────────────────────
const fixedSiteHex = bytes32At(0x10);
const customerInputs: Array<{
  name: string;
  customerName: string;
  role: string;
  siteCellIdHex: string;
  phone: string;
  email: string;
}> = [
  {
    name: 'agent with phone + email',
    customerName: 'Jane Doe',
    role: 'agent',
    siteCellIdHex: fixedSiteHex,
    phone: '+61400111222',
    email: 'jane@example.com',
  },
  {
    name: 'tenant with phone only',
    customerName: 'John Smith',
    role: 'tenant',
    siteCellIdHex: fixedSiteHex,
    phone: '+61400333444',
    email: '',
  },
  {
    name: 'owner with email only',
    customerName: 'Owner Person',
    role: 'owner',
    siteCellIdHex: fixedSiteHex,
    phone: '',
    email: 'owner@example.com',
  },
  {
    name: 'customer with empty phone+email (matches name+role+site fallback in dedupe ladder)',
    customerName: 'Anon Person',
    role: 'agent',
    siteCellIdHex: fixedSiteHex,
    phone: '',
    email: '',
  },
  {
    name: 'unicode name',
    customerName: 'Зоя Петрова',
    role: 'tenant',
    siteCellIdHex: fixedSiteHex,
    phone: '',
    email: '',
  },
];

for (const c of customerInputs) {
  const siteBytes = fromHex(c.siteCellIdHex);
  const cellId = computeCustomerCellId(c.customerName, c.role, siteBytes, c.phone, c.email);
  cases.push({
    kind: 'customer_cell_id',
    name: c.name,
    input: {
      name: c.customerName,
      role: c.role,
      siteCellIdHex: c.siteCellIdHex,
      phone: c.phone,
      email: c.email,
    },
    expected: { cellIdHex: toHex(cellId) },
  });
}

// ── 5. Job cellID cases ─────────────────────────────────────────────
const jobInputs: Array<{
  name: string;
  siteCellIdHex: string;
  customerRefs: Array<{ cellIdHex: string; role: string; primary: boolean }>;
  workOrderNumber: string;
  issuanceDate: string;
  dueDate: string;
  displayName: string;
  createdAt: string;
}> = [
  {
    name: 'job with one primary customer (typical lead)',
    siteCellIdHex: fixedSiteHex,
    customerRefs: [{ cellIdHex: bytes32At(0x20), role: 'agent', primary: true }],
    workOrderNumber: '',
    issuanceDate: '',
    dueDate: '',
    displayName: 'Jane Doe',
    createdAt: '1730000000000',
  },
  {
    name: 'job with primary + one secondary customer',
    siteCellIdHex: fixedSiteHex,
    customerRefs: [
      { cellIdHex: bytes32At(0x20), role: 'agent', primary: true },
      { cellIdHex: bytes32At(0x30), role: 'tenant', primary: false },
    ],
    workOrderNumber: 'WO-12345',
    issuanceDate: '2026-05-04',
    dueDate: '2026-05-11',
    displayName: 'Jane Doe',
    createdAt: '1730000000001',
  },
  {
    name: 'job with three customers (primary + two secondaries)',
    siteCellIdHex: fixedSiteHex,
    customerRefs: [
      { cellIdHex: bytes32At(0x20), role: 'agent', primary: true },
      { cellIdHex: bytes32At(0x30), role: 'tenant', primary: false },
      { cellIdHex: bytes32At(0x40), role: 'owner', primary: false },
    ],
    workOrderNumber: 'WO-99',
    issuanceDate: '2026-06-01',
    dueDate: '2026-06-15',
    displayName: '(untitled lead)',
    createdAt: '1730000000002',
  },
  {
    name: 'job with no customers (empty customerRefs slice)',
    siteCellIdHex: fixedSiteHex,
    customerRefs: [],
    workOrderNumber: 'WO-EMPTY',
    issuanceDate: '',
    dueDate: '',
    displayName: 'No-contact lead',
    createdAt: '1730000000003',
  },
  {
    name: 'two ratifies of the same payload at different timestamps produce different jobs',
    siteCellIdHex: fixedSiteHex,
    customerRefs: [{ cellIdHex: bytes32At(0x20), role: 'agent', primary: true }],
    workOrderNumber: '',
    issuanceDate: '',
    dueDate: '',
    displayName: 'Jane Doe',
    createdAt: '1730000000099',
  },
];

for (const j of jobInputs) {
  const siteBytes = fromHex(j.siteCellIdHex);
  const customerRefs = j.customerRefs.map(r => ({
    cellIdBytes: fromHex(r.cellIdHex),
    role: r.role,
    primary: r.primary,
  }));
  const cellId = computeJobCellId({
    siteCellIdBytes: siteBytes,
    customerRefs,
    workOrderNumber: j.workOrderNumber,
    issuanceDate: j.issuanceDate,
    dueDate: j.dueDate,
    createdAt: j.createdAt,
    displayName: j.displayName,
  });
  cases.push({
    kind: 'job_cell_id',
    name: j.name,
    input: {
      siteCellIdHex: j.siteCellIdHex,
      customerRefs: j.customerRefs,
      workOrderNumber: j.workOrderNumber,
      issuanceDate: j.issuanceDate,
      dueDate: j.dueDate,
      displayName: j.displayName,
      createdAt: j.createdAt,
    },
    expected: { cellIdHex: toHex(cellId) },
  });
}

// ── 6. Attachment cellID cases ──────────────────────────────────────
const fixedJobHex = bytes32At(0x50);
const attachmentInputs: Array<{
  name: string;
  jobCellIdHex: string;
  sourceAttachmentPath: string;
  createdAt: string;
}> = [
  {
    name: 'PDF attachment with typical source path',
    jobCellIdHex: fixedJobHex,
    sourceAttachmentPath: '/var/lib/oddjobz/inbox/proposal-12345.pdf',
    createdAt: '1730000000000',
  },
  {
    name: 'attachment with empty source path (boundary)',
    jobCellIdHex: fixedJobHex,
    sourceAttachmentPath: '',
    createdAt: '1730000000001',
  },
  {
    name: 'attachment with unicode in source path',
    jobCellIdHex: fixedJobHex,
    sourceAttachmentPath: '/incoming/Pétition de M. Dupont.pdf',
    createdAt: '1730000000002',
  },
  {
    name: 'attachment with pipe in source path',
    jobCellIdHex: fixedJobHex,
    sourceAttachmentPath: '/path/with|pipe.pdf',
    createdAt: '1730000000003',
  },
];

for (const a of attachmentInputs) {
  const jobBytes = fromHex(a.jobCellIdHex);
  const cellId = computeAttachmentCellId(jobBytes, a.sourceAttachmentPath, a.createdAt);
  cases.push({
    kind: 'attachment_cell_id',
    name: a.name,
    input: {
      jobCellIdHex: a.jobCellIdHex,
      sourceAttachmentPath: a.sourceAttachmentPath,
      createdAt: a.createdAt,
    },
    expected: { cellIdHex: toHex(cellId) },
  });
}

// ─── Emit ─────────────────────────────────────────────────────────────

const fixture = {
  _comment:
    'D-DOG.1.0c Phase 2B.4 oddjobz cell-derivation parity oracle. Generated by core/cell-ops/tests/vectors/generate_oddjobz_derivations.ts — DO NOT EDIT BY HAND. Re-generate with: bun core/cell-ops/tests/vectors/generate_oddjobz_derivations.ts',
  version: 1,
  cases,
};

const __filename = fileURLToPath(import.meta.url);
const outPath = resolve(dirname(__filename), 'oddjobz-derivations.json');
writeFileSync(outPath, JSON.stringify(fixture, null, 2) + '\n', 'utf8');

console.log(`wrote ${cases.length} fixtures to ${outPath}`);

```
