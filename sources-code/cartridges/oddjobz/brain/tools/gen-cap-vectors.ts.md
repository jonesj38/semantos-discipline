---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tools/gen-cap-vectors.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.469942+00:00
---

# cartridges/oddjobz/brain/tools/gen-cap-vectors.ts

```ts
/**
 * D-O3 — capability mint conformance-vector generator.
 *
 * Emits one JSON file per cap into
 * `cartridges/oddjobz/brain/tests/vectors/capabilities/<name>.json` plus a
 * counter-example vector at `.../carpenter_vs_musician.json` exercising
 * the §2.5 hat-isolation invariant.
 *
 * Each per-cap file shape:
 *   {
 *     "name":         "cap.oddjobz.<verb>",
 *     "domainFlag":   <uint32>,
 *     "domainFlagHex": "0x000101nn",
 *     "holder":       "operator-root" | "node-service",
 *     "contextTag":   <uint8>,
 *     "ownerIdHex":   "<32 hex>",
 *     "cellHex":      "<2048 hex chars = 1024 bytes>",
 *     "expectedDomainFlag": <uint32>,
 *     "expectedTypeHashHex": "<64 hex>"
 *   }
 *
 * The `carpenter_vs_musician.json` file pairs two mint outputs of the
 * same cap minted under context tags 0x10 and 0x11 — surfacing the §2.5
 * invariant that a cap minted under one hat must not match-verify
 * against another.
 */

import { writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  ODDJOBZ_CAPABILITIES,
  ODDJOBZ_CAP_TYPE_HASH_HEX,
  mintCapabilityCell,
  bytesToHex,
  type OddjobzCapability,
} from '../src/capabilities.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = resolve(HERE, '..', 'tests', 'vectors', 'capabilities');

mkdirSync(OUT_DIR, { recursive: true });

/** Stable 16-byte ownerId — the operator's tenant id, hex-decoded.
 *  Same shape as the existing oddjobz cell-type vectors' UUID-typed
 *  fields. The bytes are deterministic so re-running the generator
 *  produces identical vectors. */
const STABLE_OPERATOR_OWNER_ID = new Uint8Array([
  0x00, 0x70, 0x65, 0x72, 0x61, 0x74, 0x6f, 0x72,
  0x2d, 0x72, 0x6f, 0x6f, 0x74, 0x2d, 0x69, 0x64,
]);

const STABLE_SERVICE_OWNER_ID = new Uint8Array([
  0x00, 0x6f, 0x64, 0x64, 0x6a, 0x6f, 0x62, 0x7a,
  0x2d, 0x73, 0x65, 0x72, 0x76, 0x69, 0x63, 0x65,
]);

/** Carpenter context tag (per BRAIN-DISPATCHER-UNIFICATION.md §2.5). */
const CARPENTER_TAG = 0x10;
/** Musician context tag (per §2.5). */
const MUSICIAN_TAG = 0x11;

function fileSafeName(capName: string): string {
  // Drop "cap.oddjobz." prefix; replace dots with underscores.
  return capName.replace(/^cap\.oddjobz\./, '').replace(/\./g, '_');
}

function ownerIdFor(cap: OddjobzCapability): Uint8Array {
  return cap.holder === 'operator-root'
    ? STABLE_OPERATOR_OWNER_ID
    : STABLE_SERVICE_OWNER_ID;
}

function defaultContextTagFor(cap: OddjobzCapability): number {
  // Operator-root caps default to the carpenter tag for the canonical
  // vectors (matches the §2.5 motivating example). Service caps mint
  // under tag 0x00 (no specific hat — they belong to the daemon).
  return cap.holder === 'operator-root' ? CARPENTER_TAG : 0x00;
}

interface CapabilityVector {
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

function buildPerCapVectors(): void {
  for (const cap of ODDJOBZ_CAPABILITIES) {
    const contextTag = defaultContextTagFor(cap);
    const ownerId = ownerIdFor(cap);
    const cell = mintCapabilityCell(cap, contextTag, ownerId);
    const vector: CapabilityVector = {
      name: cap.name,
      domainFlag: cap.domainFlag,
      domainFlagHex: `0x${cap.domainFlag.toString(16).padStart(8, '0')}`,
      holder: cap.holder,
      contextTag,
      ownerIdHex: bytesToHex(ownerId),
      cellHex: bytesToHex(cell),
      expectedDomainFlag: cap.domainFlag,
      expectedTypeHashHex: ODDJOBZ_CAP_TYPE_HASH_HEX,
    };
    const path = resolve(OUT_DIR, `${fileSafeName(cap.name)}.json`);
    writeFileSync(path, JSON.stringify(vector, null, 2) + '\n', 'utf-8');
    // eslint-disable-next-line no-console
    console.log(`wrote vector for ${cap.name} → ${path}`);
  }
}

interface CarpenterVsMusicianVector {
  description: string;
  cap: string;
  domainFlag: number;
  ownerIdHex: string;
  carpenter: { contextTag: number; cellHex: string };
  musician: { contextTag: number; cellHex: string };
  expectedError: string;
}

function buildHatIsolationVector(): void {
  // Mint cap.oddjobz.quote under both carpenter (0x10) and musician
  // (0x11) context tags. The §2.5 invariant says the bytes must
  // differ — and the canonical OP_CHECKDOMAINFLAG check, while it
  // doesn't read the context tag, the dispatcher's hat-resolution
  // must consider them structurally distinct. The conformance test
  // asserts the kernel-level domain_flag check on the wrong cap's
  // flag yields domain_flag_mismatch — the K3 invariant.
  const cap = ODDJOBZ_CAPABILITIES.find((c) => c.name === 'cap.oddjobz.quote')!;
  const ownerId = STABLE_OPERATOR_OWNER_ID;
  const carpenterCell = mintCapabilityCell(cap, CARPENTER_TAG, ownerId);
  const musicianCell = mintCapabilityCell(cap, MUSICIAN_TAG, ownerId);

  const vector: CarpenterVsMusicianVector = {
    description:
      '§2.5 carpenter+musician hat isolation: same cap, different context tags. ' +
      'Cell bytes MUST differ; dispatcher hat-resolution MUST treat them as ' +
      'structurally distinct UTXOs.',
    cap: cap.name,
    domainFlag: cap.domainFlag,
    ownerIdHex: bytesToHex(ownerId),
    carpenter: {
      contextTag: CARPENTER_TAG,
      cellHex: bytesToHex(carpenterCell),
    },
    musician: {
      contextTag: MUSICIAN_TAG,
      cellHex: bytesToHex(musicianCell),
    },
    expectedError: 'domain_flag_mismatch (or hat-context mismatch upstream)',
  };
  const path = resolve(OUT_DIR, 'carpenter_vs_musician.json');
  writeFileSync(path, JSON.stringify(vector, null, 2) + '\n', 'utf-8');
  // eslint-disable-next-line no-console
  console.log(`wrote hat-isolation vector → ${path}`);
}

interface WrongFlagCounterExampleVector {
  description: string;
  cap: string;
  cellHex: string;
  presentedFlag: number;
  presentedFlagHex: string;
  expectedDomainFlag: number;
  expectedDomainFlagHex: string;
  expectedError: string;
}

function buildWrongFlagVector(): void {
  // Mint cap.oddjobz.quote, then "present" cap.oddjobz.invoice's flag
  // — kernel-gate must surface domain_flag_mismatch.
  const quoteCap = ODDJOBZ_CAPABILITIES.find((c) => c.name === 'cap.oddjobz.quote')!;
  const invoiceCap = ODDJOBZ_CAPABILITIES.find((c) => c.name === 'cap.oddjobz.invoice')!;
  const ownerId = STABLE_OPERATOR_OWNER_ID;
  const cell = mintCapabilityCell(quoteCap, CARPENTER_TAG, ownerId);
  const vector: WrongFlagCounterExampleVector = {
    description:
      'OP_CHECKDOMAINFLAG counter-example: quote cap presented against ' +
      'invoice cap\'s flag. Kernel returns domain_flag_mismatch (K3a per ' +
      'proofs/lean/Semantos/Theorems/DomainIsolationK3.lean).',
    cap: quoteCap.name,
    cellHex: bytesToHex(cell),
    presentedFlag: invoiceCap.domainFlag,
    presentedFlagHex: `0x${invoiceCap.domainFlag.toString(16).padStart(8, '0')}`,
    expectedDomainFlag: quoteCap.domainFlag,
    expectedDomainFlagHex: `0x${quoteCap.domainFlag.toString(16).padStart(8, '0')}`,
    expectedError: 'domain_flag_mismatch',
  };
  const path = resolve(OUT_DIR, 'wrong_flag_counter_example.json');
  writeFileSync(path, JSON.stringify(vector, null, 2) + '\n', 'utf-8');
  // eslint-disable-next-line no-console
  console.log(`wrote wrong-flag counter-example vector → ${path}`);
}

buildPerCapVectors();
buildHatIsolationVector();
buildWrongFlagVector();

// eslint-disable-next-line no-console
console.log('done.');

```
