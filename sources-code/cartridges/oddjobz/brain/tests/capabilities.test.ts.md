---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/capabilities.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.471195+00:00
---

# cartridges/oddjobz/brain/tests/capabilities.test.ts

```ts
/**
 * D-O3 — Oddjobz capability mint conformance tests.
 *
 * Reference:
 *   - docs/design/ODDJOBZ-EXTENSION-PLAN.md §O3 (cap mint table), §9
 *     (acceptance gates: K1/K2/K4 enforcement, conformance vectors,
 *     recovery round-trip; §9.8 "no new top-level boot step" — that
 *     one is exercised in the Zig conformance suite).
 *   - docs/design/BRAIN-DISPATCHER-UNIFICATION.md §2.5 (carpenter +
 *     musician hat isolation invariant).
 *   - core/cell-engine/src/opcodes/plexus.zig (the OP_CHECKDOMAINFLAG
 *     opcode the `opCheckDomainFlag` model below faithfully reflects).
 *   - proofs/lean/Semantos/Theorems/DomainIsolationK3.lean (the K3a
 *     mismatch theorem the negative test case exhibits).
 *
 * Asserts the §9.2 (K1/K2/K4 — uniqueness, isolation, idempotence),
 * §9.3 (vector round-trip), and §9.4 (recovery round-trip) gates for
 * the canonical six-cap set.
 */

import { describe, expect, test } from 'bun:test';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  ODDJOBZ_CAPABILITIES,
  ODDJOBZ_CAP_NAMES,
  ODDJOBZ_CAP_TYPE_HASH_HEX,
  OPERATOR_ROOT_CAPS,
  NODE_SERVICE_CAPS,
  capabilityByName,
  capabilityByDomainFlag,
  capWriteCustomer,
  capQuote,
  capDispatch,
  capInvoice,
  capClose,
  capPublicChatServe,
  mintCapabilityCell,
  decodeCapabilityCell,
  readDomainFlag,
  readContextTag,
  opCheckDomainFlag,
  encodeRecoveryPayload,
  decodeRecoveryPayload,
  bytesToHex,
  hexToBytes,
  CAP_CELL_SIZE,
  type OddjobzCapability,
  type OddjobzCapName,
} from '../src/index.js';
import {
  oddjobzManifest,
  manifestToWire,
} from '../src/manifest.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const VECTORS_DIR = resolve(HERE, 'vectors', 'capabilities');

const STABLE_OPERATOR_OWNER_ID = new Uint8Array([
  0x00, 0x70, 0x65, 0x72, 0x61, 0x74, 0x6f, 0x72,
  0x2d, 0x72, 0x6f, 0x6f, 0x74, 0x2d, 0x69, 0x64,
]);
const STABLE_SERVICE_OWNER_ID = new Uint8Array([
  0x00, 0x6f, 0x64, 0x64, 0x6a, 0x6f, 0x62, 0x7a,
  0x2d, 0x73, 0x65, 0x72, 0x76, 0x69, 0x63, 0x65,
]);
const CARPENTER_TAG = 0x10;
const MUSICIAN_TAG = 0x11;

/* ══════════════════════════════════════════════════════════════════════
 * §O3 — registry shape
 * ══════════════════════════════════════════════════════════════════════ */

describe('§O3 — capability registry', () => {
  test('exports sixteen caps in §O3 plan order', () => {
    // D-O5.followup-1 / D-O5m.followup-4 — the 7th cap
    // (`cap.oddjobz.read_jobs`, `0x00010107`) is the typed read cap
    // for the Semantos Brain dispatcher's `jobs.find` / `jobs.find_by_id`
    // resource commands.  D-O5.followup-3 — the 8th cap
    // (`cap.oddjobz.read_customers`, `0x00010108`) is the typed read
    // cap for the Semantos Brain dispatcher's `customers.find` /
    // `customers.find_by_id` resource commands.  D-O4.followup-2 —
    // the 9th + 10th caps (`cap.oddjobz.read_visits`, `0x00010109` +
    // `cap.oddjobz.write_visit`, `0x0001010A`) are the typed read /
    // write caps for the Semantos Brain dispatcher's `visits.*` resource cmds
    // landing the Visit FSM cutover.  D-O4.followup-3 — the 11th +
    // 12th caps (`cap.oddjobz.read_quotes`, `0x0001010B` +
    // `cap.oddjobz.write_quote`, `0x0001010C`) are the typed read /
    // write caps for the Semantos Brain dispatcher's `quotes.*` resource cmds
    // landing the Quote FSM cutover.  D-O4.followup-4 — the 13th +
    // 14th caps (`cap.oddjobz.read_invoices`, `0x0001010D` +
    // `cap.oddjobz.write_invoice`, `0x0001010E`) are the typed read /
    // write caps for the Semantos Brain dispatcher's `invoices.*` resource cmds
    // landing the Invoice FSM cutover — closing the Semantos Brain-side cutover
    // of all 4 oddjobz FSMs.  D-O5m.followup-8 substrate — the 15th
    // + 16th caps (`cap.oddjobz.read_attachments`, `0x0001010F` +
    // `cap.oddjobz.write_attachment`, `0x00010110`) are the typed
    // read / write caps for the Semantos Brain dispatcher's `attachments.*`
    // resource cmds.  This PR ships only the read-only substrate +
    // metadata-cell create; mobile camera capture + binary blob
    // upload land in the subsequent PR.  All ten post-§O3 entries
    // appended at the end of the array so the original six entries
    // (and their fixture / conformance vectors) keep their byte-
    // identical pre-followup shape.
    // A5.P2 — `cap.oddjobz.write_policy` appended at the end
    // (operator pricing-policy config-intent walker), growing the
    // registry sixteen → seventeen; pre-A5 fixtures iterating the
    // first sixteen in order keep their byte-identical shape.
    expect(ODDJOBZ_CAPABILITIES).toHaveLength(17);
    expect(ODDJOBZ_CAPABILITIES.map((c) => c.name)).toEqual([
      'cap.oddjobz.write_customer',
      'cap.oddjobz.quote',
      'cap.oddjobz.dispatch',
      'cap.oddjobz.invoice',
      'cap.oddjobz.close',
      'cap.oddjobz.public_chat_serve',
      'cap.oddjobz.read_jobs',
      'cap.oddjobz.read_customers',
      'cap.oddjobz.read_visits',
      'cap.oddjobz.write_visit',
      'cap.oddjobz.read_quotes',
      'cap.oddjobz.write_quote',
      'cap.oddjobz.read_invoices',
      'cap.oddjobz.write_invoice',
      'cap.oddjobz.read_attachments',
      'cap.oddjobz.write_attachment',
      'cap.oddjobz.write_policy',
    ]);
  });

  test('ODDJOBZ_CAP_NAMES tuple matches the registry', () => {
    expect([...ODDJOBZ_CAP_NAMES]).toEqual(
      ODDJOBZ_CAPABILITIES.map((c) => c.name),
    );
  });

  test('capabilityByName lookup hits every cap', () => {
    for (const c of ODDJOBZ_CAPABILITIES) {
      expect(capabilityByName[c.name]).toBe(c);
    }
  });

  test('capabilityByDomainFlag lookup hits every cap', () => {
    for (const c of ODDJOBZ_CAPABILITIES) {
      expect(capabilityByDomainFlag[c.domainFlag]).toBe(c);
    }
  });

  test('individual exports tie to the registry', () => {
    expect(capWriteCustomer.name).toBe('cap.oddjobz.write_customer');
    expect(capQuote.name).toBe('cap.oddjobz.quote');
    expect(capDispatch.name).toBe('cap.oddjobz.dispatch');
    expect(capInvoice.name).toBe('cap.oddjobz.invoice');
    expect(capClose.name).toBe('cap.oddjobz.close');
    expect(capPublicChatServe.name).toBe('cap.oddjobz.public_chat_serve');
  });

  test('OPERATOR_ROOT_CAPS / NODE_SERVICE_CAPS partition the registry', () => {
    // D-O5.followup-1 — `cap.oddjobz.read_jobs` is operator-root-held
    // (and delegated to phone child certs by default), so
    // OPERATOR_ROOT_CAPS grew from 5 → 6.  D-O5.followup-3 —
    // `cap.oddjobz.read_customers` is also operator-root-held, growing
    // it 6 → 7.  D-O4.followup-2 — `cap.oddjobz.read_visits` and
    // `cap.oddjobz.write_visit` are both operator-root-held, growing
    // it 7 → 9.  D-O4.followup-3 — `cap.oddjobz.read_quotes` and
    // `cap.oddjobz.write_quote` are both operator-root-held, growing
    // it 9 → 11.  D-O4.followup-4 — `cap.oddjobz.read_invoices` and
    // `cap.oddjobz.write_invoice` are both operator-root-held,
    // growing it 11 → 13.  D-O5m.followup-8 substrate —
    // `cap.oddjobz.read_attachments` and `cap.oddjobz.write_attachment`
    // are both operator-root-held, growing it 13 → 15.  A5.P2 —
    // `cap.oddjobz.write_policy` is operator-root-held, growing it
    // 15 → 16.
    // NODE_SERVICE_CAPS still holds only `public_chat_serve`.
    expect(OPERATOR_ROOT_CAPS).toHaveLength(16);
    expect(NODE_SERVICE_CAPS).toHaveLength(1);
    expect(NODE_SERVICE_CAPS[0]?.name).toBe('cap.oddjobz.public_chat_serve');
    expect(
      [...OPERATOR_ROOT_CAPS, ...NODE_SERVICE_CAPS].map((c) => c.name).sort(),
    ).toEqual([...ODDJOBZ_CAPABILITIES].map((c) => c.name).sort());
  });
});

/* ══════════════════════════════════════════════════════════════════════
 * §O3 — domain-flag scheme
 * ══════════════════════════════════════════════════════════════════════ */

describe('§O3 — domain-flag scheme', () => {
  test('flags sit on the canonical oddjobz page 0x000101xx', () => {
    // Page-aligned canonical low-bits assignment per Plexus client-spec
    // requirement 2.2.2 + tech-spec §30. The high 24 bits identify the
    // canonical extension page; the low byte distinguishes caps within
    // the page. See `capabilities.ts` module head for the page table.
    for (const c of ODDJOBZ_CAPABILITIES) {
      expect(c.domainFlag >>> 8).toBe(0x000101);
    }
  });

  test('canonical assignments match the page-aligned table', () => {
    // Verbatim from the §O3 plan + capabilities.ts module head.  The
    // 7th entry (`read_jobs` at `0x00010107`) was added by D-O5.
    // followup-1 alongside the typed find_jobs dispatcher resource;
    // the 8th entry (`read_customers` at `0x00010108`) was added by
    // D-O5.followup-3 alongside the typed find_customers resource;
    // the 9th + 10th entries (`read_visits` at `0x00010109` +
    // `write_visit` at `0x0001010A`) were added by D-O4.followup-2
    // alongside the typed visits resource (Visit FSM cutover); the
    // 11th + 12th entries (`read_quotes` at `0x0001010B` +
    // `write_quote` at `0x0001010C`) were added by D-O4.followup-3
    // alongside the typed quotes resource (Quote FSM cutover); the
    // 13th + 14th entries (`read_invoices` at `0x0001010D` +
    // `write_invoice` at `0x0001010E`) were added by D-O4.followup-4
    // alongside the typed invoices resource (Invoice FSM cutover —
    // closes the Semantos Brain-side cutover of all 4 oddjobz FSMs).
    const expected: Record<string, number> = {
      'cap.oddjobz.quote':              0x00010101,
      'cap.oddjobz.dispatch':           0x00010102,
      'cap.oddjobz.invoice':            0x00010103,
      'cap.oddjobz.close':              0x00010104,
      'cap.oddjobz.write_customer':     0x00010105,
      'cap.oddjobz.public_chat_serve':  0x00010106,
      'cap.oddjobz.read_jobs':          0x00010107,
      'cap.oddjobz.read_customers':     0x00010108,
      'cap.oddjobz.read_visits':        0x00010109,
      'cap.oddjobz.write_visit':        0x0001010a,
      'cap.oddjobz.read_quotes':        0x0001010b,
      'cap.oddjobz.write_quote':        0x0001010c,
      'cap.oddjobz.read_invoices':      0x0001010d,
      'cap.oddjobz.write_invoice':      0x0001010e,
      'cap.oddjobz.read_attachments':   0x0001010f,
      'cap.oddjobz.write_attachment':   0x00010110,
    };
    for (const c of ODDJOBZ_CAPABILITIES) {
      expect(c.domainFlag).toBe(expected[c.name]);
    }
  });

  test('K1: domain flags are unique across all caps', () => {
    const flags = ODDJOBZ_CAPABILITIES.map((c) => c.domainFlag);
    const unique = new Set(flags);
    expect(unique.size).toBe(flags.length);
  });

  test('flags are in the client-sovereignty range (>= 0x00010000)', () => {
    for (const c of ODDJOBZ_CAPABILITIES) {
      expect(c.domainFlag).toBeGreaterThanOrEqual(0x00010000);
      expect(c.domainFlag).toBeLessThanOrEqual(0xffffffff);
    }
  });

  test('flags do NOT collide with the reserved Plexus tier (<= 0xFF)', () => {
    for (const c of ODDJOBZ_CAPABILITIES) {
      expect(c.domainFlag).toBeGreaterThan(0xff);
      expect(c.domainFlag).toBeGreaterThan(0xffff);
    }
  });

  test('flags do NOT collide with the loom-shell page 0x000100xx', () => {
    // The loom-shell verb caps (runtime/shell/src/capabilities.ts)
    // claim 0x00010001..0x0001000B on the 0x000100xx page. Oddjobz
    // sits one page over at 0x000101xx — assert no overlap.
    for (const c of ODDJOBZ_CAPABILITIES) {
      expect(c.domainFlag >>> 8).not.toBe(0x000100);
    }
  });
});

/* ══════════════════════════════════════════════════════════════════════
 * §9.3 — vector round-trip (per-cap + counter-examples)
 * ══════════════════════════════════════════════════════════════════════ */

interface PerCapVector {
  name: string;
  domainFlag: number;
  domainFlagHex: string;
  holder: string;
  contextTag: number;
  ownerIdHex: string;
  cellHex: string;
  expectedDomainFlag: number;
  expectedTypeHashHex: string;
}

function loadVector<T>(filename: string): T {
  return JSON.parse(readFileSync(resolve(VECTORS_DIR, filename), 'utf-8')) as T;
}

describe('§9.3 — capability mint round-trip', () => {
  test('every per-cap vector packs byte-identically', () => {
    for (const cap of ODDJOBZ_CAPABILITIES) {
      const fileSafe = cap.name.replace(/^cap\.oddjobz\./, '').replace(/\./g, '_');
      const vector = loadVector<PerCapVector>(`${fileSafe}.json`);

      // Reconstruct the cell and assert byte-identical.
      const ownerId = hexToBytes(vector.ownerIdHex);
      const cell = mintCapabilityCell(cap, vector.contextTag, ownerId);
      expect(bytesToHex(cell)).toBe(vector.cellHex);

      // Round-trip: the rebuilt bytes decode to the original payload.
      const decoded = decodeCapabilityCell(cell);
      expect(decoded.capName).toBe(cap.name);
      expect(decoded.contextTag).toBe(vector.contextTag);
      expect(decoded.domainFlag).toBe(cap.domainFlag);
      expect(decoded.holder).toBe(cap.holder);
      expect(decoded.ownerIdHex).toBe(vector.ownerIdHex);

      // Header reads.
      expect(readDomainFlag(cell)).toBe(cap.domainFlag);
      expect(readContextTag(cell)).toBe(vector.contextTag);
    }
  });

  test('every per-cap vector carries the canonical cap type-hash', () => {
    for (const cap of ODDJOBZ_CAPABILITIES) {
      const fileSafe = cap.name.replace(/^cap\.oddjobz\./, '').replace(/\./g, '_');
      const vector = loadVector<PerCapVector>(`${fileSafe}.json`);
      expect(vector.expectedTypeHashHex).toBe(ODDJOBZ_CAP_TYPE_HASH_HEX);
    }
  });

  test('cell size is 1024 bytes and 256-byte header layout matches', () => {
    const cell = mintCapabilityCell(capQuote, CARPENTER_TAG, STABLE_OPERATOR_OWNER_ID);
    expect(cell.length).toBe(CAP_CELL_SIZE);
    // Magic
    expect(cell[0]).toBe(0xef);
    expect(cell[1]).toBe(0xbe);
    expect(cell[2]).toBe(0xad);
    expect(cell[3]).toBe(0xde);
    // Linearity = 1 (LINEAR) at offset 16
    expect(cell[16]).toBe(1);
    // Version = 1 at offset 20
    expect(cell[20]).toBe(1);
  });

  test('directory contains the expected vector set', () => {
    const files = readdirSync(VECTORS_DIR).sort();
    expect(files).toContain('write_customer.json');
    expect(files).toContain('quote.json');
    expect(files).toContain('dispatch.json');
    expect(files).toContain('invoice.json');
    expect(files).toContain('close.json');
    expect(files).toContain('public_chat_serve.json');
    // D-O5.followup-1 — read_jobs vector ships alongside the other
    // six per-cap fixtures.
    expect(files).toContain('read_jobs.json');
    // D-O5.followup-3 — read_customers vector ships alongside.
    expect(files).toContain('read_customers.json');
    // D-O4.followup-2 — read_visits + write_visit vectors ship
    // alongside as part of the Visit FSM cutover.
    expect(files).toContain('read_visits.json');
    expect(files).toContain('write_visit.json');
    // D-O4.followup-3 — read_quotes + write_quote vectors ship
    // alongside as part of the Quote FSM cutover.
    expect(files).toContain('read_quotes.json');
    expect(files).toContain('write_quote.json');
    // D-O4.followup-4 — read_invoices + write_invoice vectors ship
    // alongside as part of the Invoice FSM cutover.  Closes the
    // brain-side cutover of all 4 oddjobz FSMs.
    expect(files).toContain('read_invoices.json');
    expect(files).toContain('write_invoice.json');
    // D-O5m.followup-8 substrate — read_attachments + write_attachment
    // vectors ship alongside as the substrate for the mobile
    // sensor-capture flow (mobile camera capture + blob upload land
    // in the subsequent PR).
    expect(files).toContain('read_attachments.json');
    expect(files).toContain('write_attachment.json');
    expect(files).toContain('carpenter_vs_musician.json');
    expect(files).toContain('wrong_flag_counter_example.json');
  });
});

/* ══════════════════════════════════════════════════════════════════════
 * K3 — OP_CHECKDOMAINFLAG positive + negative
 * ══════════════════════════════════════════════════════════════════════ */

describe('K3 — OP_CHECKDOMAINFLAG enforcement', () => {
  test('positive: presenting a cap UTXO with the right flag passes', () => {
    for (const cap of ODDJOBZ_CAPABILITIES) {
      const cell = mintCapabilityCell(cap, CARPENTER_TAG, STABLE_OPERATOR_OWNER_ID);
      expect(opCheckDomainFlag(cell, cap.domainFlag)).toBe(true);
    }
  });

  test('K3a: negative — wrong flag yields domain_flag_mismatch (false)', () => {
    const quoteCell = mintCapabilityCell(
      capQuote,
      CARPENTER_TAG,
      STABLE_OPERATOR_OWNER_ID,
    );
    // Present quote cell against invoice's flag — must fail.
    expect(opCheckDomainFlag(quoteCell, capInvoice.domainFlag)).toBe(false);
    // And against every other cap's flag — must all fail.
    for (const otherCap of ODDJOBZ_CAPABILITIES) {
      if (otherCap.domainFlag === capQuote.domainFlag) continue;
      expect(opCheckDomainFlag(quoteCell, otherCap.domainFlag)).toBe(false);
    }
  });

  test('counter-example vector fails-closed under wrong flag', () => {
    interface WrongFlagVec {
      cellHex: string;
      presentedFlag: number;
      expectedDomainFlag: number;
    }
    const vec = loadVector<WrongFlagVec>('wrong_flag_counter_example.json');
    const cell = hexToBytes(vec.cellHex);
    expect(opCheckDomainFlag(cell, vec.presentedFlag)).toBe(false);
    expect(opCheckDomainFlag(cell, vec.expectedDomainFlag)).toBe(true);
  });
});

/* ══════════════════════════════════════════════════════════════════════
 * §2.5 — carpenter + musician hat isolation invariant
 * ══════════════════════════════════════════════════════════════════════ */

describe('§2.5 — hat isolation', () => {
  test('same cap minted under different context tags yields distinct cell bytes', () => {
    const carpenterCell = mintCapabilityCell(
      capQuote,
      CARPENTER_TAG,
      STABLE_OPERATOR_OWNER_ID,
    );
    const musicianCell = mintCapabilityCell(
      capQuote,
      MUSICIAN_TAG,
      STABLE_OPERATOR_OWNER_ID,
    );
    expect(bytesToHex(carpenterCell)).not.toBe(bytesToHex(musicianCell));
  });

  test('context tag is byte 0 of OWNER_ID block (offset 62)', () => {
    const carpenterCell = mintCapabilityCell(
      capQuote,
      CARPENTER_TAG,
      STABLE_OPERATOR_OWNER_ID,
    );
    const musicianCell = mintCapabilityCell(
      capQuote,
      MUSICIAN_TAG,
      STABLE_OPERATOR_OWNER_ID,
    );
    expect(carpenterCell[62]).toBe(CARPENTER_TAG);
    expect(musicianCell[62]).toBe(MUSICIAN_TAG);
    expect(readContextTag(carpenterCell)).toBe(CARPENTER_TAG);
    expect(readContextTag(musicianCell)).toBe(MUSICIAN_TAG);
  });

  test('K3-equivalent isolation: cap minted under 0x10 fails K3 under 0x11 dispatcher hat', () => {
    // The kernel-gate's OP_CHECKDOMAINFLAG checks domain_flag, not
    // context tag — but the dispatcher's hat resolution gate gates
    // on (cell, expected_domain_flag, active_hat_context_tag). We
    // model the dispatcher gate as: a cap UTXO presented under one
    // hat must not satisfy a transition belonging to another hat.
    const carpenterCell = mintCapabilityCell(
      capQuote,
      CARPENTER_TAG,
      STABLE_OPERATOR_OWNER_ID,
    );

    // The dispatcher gate (modelled here): require cell.contextTag ===
    // active_hat. A musician hat (0x11) presenting a carpenter-tagged
    // (0x10) cell must fail.
    const carpenterPresentingAsMusician =
      readContextTag(carpenterCell) === MUSICIAN_TAG;
    expect(carpenterPresentingAsMusician).toBe(false);

    // And a carpenter hat presenting its own cell passes the same gate.
    const carpenterPresentingAsCarpenter =
      readContextTag(carpenterCell) === CARPENTER_TAG;
    expect(carpenterPresentingAsCarpenter).toBe(true);
  });

  test('canonical hat-isolation vector is loadable and structurally distinct', () => {
    interface HatVec {
      cap: string;
      domainFlag: number;
      ownerIdHex: string;
      carpenter: { contextTag: number; cellHex: string };
      musician: { contextTag: number; cellHex: string };
    }
    const v = loadVector<HatVec>('carpenter_vs_musician.json');
    expect(v.cap).toBe('cap.oddjobz.quote');
    expect(v.domainFlag).toBe(capQuote.domainFlag);
    expect(v.carpenter.contextTag).toBe(CARPENTER_TAG);
    expect(v.musician.contextTag).toBe(MUSICIAN_TAG);
    expect(v.carpenter.cellHex).not.toBe(v.musician.cellHex);

    // Same domainFlag in both — context-tag swap reshapes the bytes
    // BUT the kernel-gate flag check still passes for both. The
    // dispatcher's hat-context check is what enforces the §2.5
    // structural-invisibility property.
    const carpCell = hexToBytes(v.carpenter.cellHex);
    const musCell = hexToBytes(v.musician.cellHex);
    expect(readDomainFlag(carpCell)).toBe(v.domainFlag);
    expect(readDomainFlag(musCell)).toBe(v.domainFlag);
    expect(readContextTag(carpCell)).toBe(CARPENTER_TAG);
    expect(readContextTag(musCell)).toBe(MUSICIAN_TAG);
  });
});

/* ══════════════════════════════════════════════════════════════════════
 * §9.4 — recovery payload round-trip
 * ══════════════════════════════════════════════════════════════════════ */

describe('§9.4 — recovery round-trip', () => {
  test('encode → decode produces a structurally-identical cap set', () => {
    const rootSeed = new TextEncoder().encode('test-root-seed-for-d-o3-recovery');
    const payload = encodeRecoveryPayload(rootSeed, CARPENTER_TAG, STABLE_OPERATOR_OWNER_ID);
    const recovered = decodeRecoveryPayload(payload, rootSeed);

    expect(recovered.v).toBe(1);
    expect(recovered.contextTag).toBe(CARPENTER_TAG);
    expect(recovered.ownerIdHex).toBe(bytesToHex(STABLE_OPERATOR_OWNER_ID));
    // D-O5m.followup-8 substrate — registry grew from fourteen to
    // sixteen; the recovery payload round-trips every cap including
    // the new `read_jobs` (D-O5.followup-1), `read_customers`
    // (D-O5.followup-3), `read_visits` + `write_visit`
    // (D-O4.followup-2), `read_quotes` + `write_quote`
    // (D-O4.followup-3), `read_invoices` + `write_invoice`
    // (D-O4.followup-4), `read_attachments` + `write_attachment`
    // (D-O5m.followup-8 substrate) entries.
    expect(recovered.caps).toHaveLength(17);

    for (let i = 0; i < ODDJOBZ_CAPABILITIES.length; i++) {
      const recoveredCap = recovered.caps[i];
      const cap = ODDJOBZ_CAPABILITIES[i] as OddjobzCapability;
      expect(recoveredCap?.name).toBe(cap.name);
      expect(recoveredCap?.domainFlag).toBe(cap.domainFlag);
      expect(recoveredCap?.holder).toBe(cap.holder);
      // The cell bytes match the canonical mint output.
      const expectedCell = mintCapabilityCell(
        cap,
        CARPENTER_TAG,
        STABLE_OPERATOR_OWNER_ID,
      );
      expect(recoveredCap?.cellHex).toBe(bytesToHex(expectedCell));
    }
  });

  test('decode under a wrong root seed produces undecodable JSON', () => {
    const rootSeed = new TextEncoder().encode('test-seed-recovery-good');
    const wrongSeed = new TextEncoder().encode('test-seed-recovery-evil');
    const payload = encodeRecoveryPayload(rootSeed, CARPENTER_TAG, STABLE_OPERATOR_OWNER_ID);
    expect(() => decodeRecoveryPayload(payload, wrongSeed)).toThrow();
  });

  test('encode is deterministic for the same inputs', () => {
    const rootSeed = new TextEncoder().encode('test-root-seed-determinism');
    const a = encodeRecoveryPayload(rootSeed, CARPENTER_TAG, STABLE_OPERATOR_OWNER_ID);
    const b = encodeRecoveryPayload(rootSeed, CARPENTER_TAG, STABLE_OPERATOR_OWNER_ID);
    expect(bytesToHex(a)).toBe(bytesToHex(b));
  });
});

/* ══════════════════════════════════════════════════════════════════════
 * Manifest shape (the Semantos Brain first-boot reads this)
 * ══════════════════════════════════════════════════════════════════════ */

describe('manifest', () => {
  test('manifest matches the canonical cap registry', () => {
    expect(oddjobzManifest.id).toBe('oddjobz');
    expect(oddjobzManifest.lexiconId).toBe('trades');
    expect(oddjobzManifest.bootStep).toBe('step-6-capability-mint');
    expect(oddjobzManifest.capabilities).toBe(ODDJOBZ_CAPABILITIES);
    expect(oddjobzManifest.capabilityTypeHashHex).toBe(ODDJOBZ_CAP_TYPE_HASH_HEX);
  });

  test('manifest wire format is parseable JSON with the cap list', () => {
    const json = manifestToWire(oddjobzManifest);
    const parsed = JSON.parse(json) as {
      v: number;
      capabilities: { name: string; domainFlag: number; domainFlagHex: string }[];
    };
    expect(parsed.v).toBe(1);
    // D-O5m.followup-8 substrate — registry grew to sixteen; the wire
    // manifest mirrors that growth (read_jobs + read_customers +
    // read_visits + write_visit + read_quotes + write_quote +
    // read_invoices + write_invoice + read_attachments +
    // write_attachment entries).
    expect(parsed.capabilities).toHaveLength(17);
    expect(parsed.capabilities.map((c) => c.name)).toEqual(
      ODDJOBZ_CAPABILITIES.map((c) => c.name) as OddjobzCapName[],
    );
    for (let i = 0; i < ODDJOBZ_CAPABILITIES.length; i++) {
      expect(parsed.capabilities[i]?.domainFlag).toBe(
        (ODDJOBZ_CAPABILITIES[i] as OddjobzCapability).domainFlag,
      );
      expect(parsed.capabilities[i]?.domainFlagHex).toBe(
        `0x${(ODDJOBZ_CAPABILITIES[i] as OddjobzCapability).domainFlag
          .toString(16)
          .padStart(8, '0')}`,
      );
    }
  });
});

/* ══════════════════════════════════════════════════════════════════════
 * Validation
 * ══════════════════════════════════════════════════════════════════════ */

describe('mintCapabilityCell — validation', () => {
  test('rejects ownerId of wrong length', () => {
    const tooShort = new Uint8Array(15);
    expect(() => mintCapabilityCell(capQuote, CARPENTER_TAG, tooShort)).toThrow();
    const tooLong = new Uint8Array(17);
    expect(() => mintCapabilityCell(capQuote, CARPENTER_TAG, tooLong)).toThrow();
  });

  test('rejects context tags outside uint8 range', () => {
    expect(() =>
      mintCapabilityCell(capQuote, -1, STABLE_OPERATOR_OWNER_ID),
    ).toThrow();
    expect(() =>
      mintCapabilityCell(capQuote, 256, STABLE_OPERATOR_OWNER_ID),
    ).toThrow();
    expect(() =>
      mintCapabilityCell(capQuote, 0.5, STABLE_OPERATOR_OWNER_ID),
    ).toThrow();
  });

  test('decodeCapabilityCell rejects a bad-magic cell', () => {
    const cell = mintCapabilityCell(capQuote, CARPENTER_TAG, STABLE_OPERATOR_OWNER_ID);
    cell[0] = 0; // corrupt magic
    expect(() => decodeCapabilityCell(cell)).toThrow();
  });

  test('decodeCapabilityCell rejects a cell of wrong size', () => {
    const cell = mintCapabilityCell(capQuote, CARPENTER_TAG, STABLE_OPERATOR_OWNER_ID);
    expect(() => decodeCapabilityCell(cell.subarray(0, 1023))).toThrow();
  });
});

// silence unused-import warnings for type symbols re-exported only for
// downstream consumers' sake.
void basename;

```
