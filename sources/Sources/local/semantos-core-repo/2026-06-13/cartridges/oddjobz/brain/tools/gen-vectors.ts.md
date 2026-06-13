---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tools/gen-vectors.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.468203+00:00
---

# cartridges/oddjobz/brain/tools/gen-vectors.ts

```ts
/**
 * Conformance vector generator.
 *
 * Emits one JSON file per cell type at
 * `cartridges/oddjobz/brain/tests/vectors/oddjobz_<type>.json`. Each file
 * contains an array of N≥3 vectors covering different optional-field
 * combinations to exercise the canonical-JSON encoder paths and the
 * round-trip identity.
 *
 * Vector shape:
 *   {
 *     "name": "human-readable label",
 *     "input": <typed value>,
 *     "packed": "<hex bytes>",
 *     "typeHash": "<hex bytes>",
 *     "linearity": "<§O2 label>"
 *   }
 *
 * Run with `bun tools/gen-vectors.ts` from this package, or via
 * `pnpm gen:vectors`. The generator overwrites existing vector files
 * deterministically — same inputs ⇒ same bytes.
 */

import { writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  customerCellType,
  siteCellType,
  jobCellType,
  quoteCellType,
  visitCellType,
  invoiceCellType,
  estimateCellType,
  messageCellType,
  leadCellType,
  attachmentCellType,
  pricingPolicyCellType,
  type CellTypeDef,
} from '../src/cell-types/index.js';
import { AU_DEFAULT_PRICING_POLICY } from '../src/pricing-policy-defaults.js';
import type {
  OddjobzCustomer,
  OddjobzSite,
  OddjobzJob,
  OddjobzQuote,
  OddjobzVisit,
  OddjobzInvoice,
  OddjobzEstimate,
  OddjobzMessage,
  OddjobzLead,
  OddjobzAttachment,
  OddjobzPricingPolicy,
} from '../src/cell-types/index.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = resolve(HERE, '..', 'tests', 'vectors');

interface Vector<T> {
  name: string;
  input: T;
  packed: string;
  typeHash: string;
  linearity: string;
}

function bytesToHex(b: Uint8Array): string {
  let out = '';
  for (let i = 0; i < b.length; i++) {
    out += (b[i] as number).toString(16).padStart(2, '0');
  }
  return out;
}

function build<T>(type: CellTypeDef<T>, samples: { name: string; input: T }[]): Vector<T>[] {
  return samples.map(({ name, input }) => ({
    name,
    input,
    packed: bytesToHex(type.pack(input)),
    typeHash: type.typeHashHex,
    linearity: type.linearity,
  }));
}

function write(filename: string, vectors: unknown[]): void {
  const json = JSON.stringify(vectors, null, 2) + '\n';
  const path = resolve(OUT_DIR, filename);
  writeFileSync(path, json, 'utf-8');
  // eslint-disable-next-line no-console
  console.log(`wrote ${vectors.length.toString().padStart(2)} vectors → ${path}`);
}

// ── Sample data ──────────────────────────────────────────────────────

// Stable UUIDs so re-running the generator produces identical bytes.
const C1 = '11111111-1111-4111-8111-111111111111';
const C2 = '22222222-2222-4222-8222-222222222222';
const SITE1 = '33333333-3333-4333-8333-333333333333';
const SITE2 = '44444444-4444-4444-8444-444444444444';
const JOB1 = '55555555-5555-4555-8555-555555555555';
const JOB2 = '66666666-6666-4666-8666-666666666666';
const JOB3 = '77777777-7777-4777-8777-777777777777';
const QUOTE1 = '88888888-8888-4888-8888-888888888888';
const QUOTE2 = '99999999-9999-4999-8999-999999999999';
const QUOTE3 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const VISIT1 = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const VISIT2 = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const VISIT3 = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const INV1 = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const INV2 = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
const INV3 = '12121212-1212-4212-8212-121212121212';
const EST1 = '13131313-1313-4313-8313-131313131313';
const EST2 = '14141414-1414-4414-8414-141414141414';
const EST3 = '15151515-1515-4515-8515-151515151515';
const MSG1 = '16161616-1616-4616-8616-161616161616';
const MSG2 = '17171717-1717-4717-8717-171717171717';
const MSG3 = '18181818-1818-4818-8818-181818181818';
const MSG4 = '19191919-1919-4919-8919-191919191919';
const OP1 = '20202020-2020-4020-8020-202020202020';
const OP2 = '21212121-2121-4121-8121-212121212121';
const LEGACY1 = '22002200-2200-4200-8200-220022002200';
const UPLOAD1 = '23232323-2323-4323-8323-232323232323';
const CHANNEL1 = '24242424-2424-4424-8424-242424242424';

const T0 = '2026-04-01T09:00:00Z';
const T1 = '2026-04-01T10:30:00Z';
const T2 = '2026-04-15T14:00:00Z';
const T3 = '2026-04-15T16:30:00Z';
const T4 = '2026-04-20T08:00:00Z';
const T5 = '2026-04-22T12:00:00Z';
const T6 = '2026-04-25T11:30:00Z';
const T7 = '2026-04-30T17:45:00Z';

// ── Vectors ──────────────────────────────────────────────────────────

const customerVectors = build<OddjobzCustomer>(customerCellType, [
  {
    name: 'minimal — just identity',
    input: {
      customerId: C1,
      name: 'Jane Customer',
      createdAt: T0,
      updatedAt: T0,
    },
  },
  {
    name: 'with phone + preferred channel',
    input: {
      customerId: C2,
      name: 'Bob Customer',
      phone: '+61400000000',
      preferredChannel: 'sms',
      createdAt: T0,
      updatedAt: T1,
    },
  },
  {
    name: 'fully populated — verified contact + notes + legacy id',
    input: {
      customerId: C1,
      name: 'Carol Customer',
      phone: '+61400111222',
      email: 'carol@example.com',
      preferredChannel: 'email',
      mobileVerifiedAt: T1,
      emailVerifiedAt: T2,
      notes: 'Prefers afternoon visits. Pays by bank transfer.',
      legacyCustomerId: LEGACY1,
      createdAt: T0,
      updatedAt: T2,
    },
  },
]);
write('oddjobz_customer.json', customerVectors);

const siteVectors = build<OddjobzSite>(siteCellType, [
  {
    name: 'minimal — id + customer',
    input: {
      siteId: SITE1,
      customerId: C1,
      createdAt: T0,
      updatedAt: T0,
    },
  },
  {
    name: 'address + suburb',
    input: {
      siteId: SITE2,
      customerId: C2,
      addressLine1: '12 Example Lane',
      suburb: 'Toowong',
      postcode: '4066',
      state: 'QLD',
      createdAt: T0,
      updatedAt: T0,
    },
  },
  {
    name: 'fully populated — geo + access notes',
    input: {
      siteId: SITE1,
      customerId: C1,
      addressLine1: '7 Demo Street',
      addressLine2: 'Unit 3',
      suburb: 'Indooroopilly',
      postcode: '4068',
      state: 'QLD',
      lat: -27.501,
      lng: 152.972,
      accessNotes: 'Side gate. Watch for the dog.',
      siteNotes: 'Old asbestos eaves on west side.',
      legacySiteId: LEGACY1,
      createdAt: T0,
      updatedAt: T1,
    },
  },
]);
write('oddjobz_site.json', siteVectors);

const jobVectors = build<OddjobzJob>(jobCellType, [
  {
    name: 'fresh lead — minimum viable Job',
    input: {
      jobId: JOB1,
      status: 'lead',
      createdAt: T0,
      updatedAt: T0,
    },
  },
  {
    name: 'lead with description + scoring',
    input: {
      jobId: JOB2,
      customerId: C1,
      siteId: SITE1,
      createdByOperatorId: OP1,
      categoryPath: 'services.trades.plumbing',
      txType: 'hire',
      instrumentType: 'inst.contract.service-agreement',
      descriptionRaw: 'Leaking tap in main bathroom.',
      descriptionSummary: 'Bathroom tap leak.',
      status: 'lead',
      urgency: 'urgent',
      leadSource: 'website_chat',
      effortBand: 'short',
      estimatedHoursMin: 0.5,
      estimatedHoursMax: 1.5,
      estimatedCostMin: 12000,
      estimatedCostMax: 25000,
      customerFitScore: 85,
      quoteWorthinessScore: 72,
      confidenceScore: 60,
      completenessScore: 75,
      recommendation: 'worth_quoting',
      needsReview: false,
      isRepeatCustomer: false,
      repeatJobCount: 0,
      requiresSiteVisit: false,
      createdAt: T0,
      updatedAt: T1,
    },
  },
  {
    name: 'scheduled — with assigned operator',
    input: {
      jobId: JOB3,
      customerId: C2,
      siteId: SITE2,
      assignedOperatorId: OP2,
      categoryPath: 'services.trades.electrical',
      txType: 'hire',
      status: 'scheduled',
      urgency: 'flexible',
      effortBand: 'half_day',
      estimatedCostMin: 80000,
      estimatedCostMax: 120000,
      isRepeatCustomer: true,
      repeatJobCount: 3,
      legacyJobId: LEGACY1,
      createdAt: T0,
      updatedAt: T2,
    },
  },
  {
    name: 'closed — terminal state',
    input: {
      jobId: JOB1,
      customerId: C1,
      siteId: SITE1,
      assignedOperatorId: OP1,
      status: 'closed',
      urgency: 'unspecified',
      createdAt: T0,
      updatedAt: T7,
    },
  },
]);
write('oddjobz_job.json', jobVectors);

const quoteVectors = build<OddjobzQuote>(quoteCellType, [
  {
    name: 'draft — no expiry, no acceptance',
    input: {
      quoteId: QUOTE1,
      jobId: JOB1,
      issuedByOperatorId: OP1,
      status: 'draft',
      costMin: 25000,
      costMax: 35000,
      createdAt: T1,
      updatedAt: T1,
    },
  },
  {
    name: 'presented — full pricing detail + expiry',
    input: {
      quoteId: QUOTE2,
      jobId: JOB2,
      issuedByOperatorId: OP1,
      status: 'presented',
      effortBand: 'half_day',
      hoursMin: 4,
      hoursMax: 6,
      costMin: 60000,
      costMax: 90000,
      labourOnly: false,
      materialsNote: 'Pipe + fittings ~$80; tap ~$120.',
      assumptionNotes: 'Existing pipework in good condition.',
      customerSummary: 'Replace leaking mixer + worn-out service valve.',
      expiresAt: T5,
      createdAt: T1,
      updatedAt: T2,
    },
  },
  {
    name: 'accepted',
    input: {
      quoteId: QUOTE3,
      jobId: JOB3,
      issuedByOperatorId: OP2,
      status: 'accepted',
      effortBand: 'full_day',
      costMin: 120000,
      costMax: 180000,
      labourOnly: true,
      acceptedAt: T2,
      createdAt: T1,
      updatedAt: T2,
    },
  },
]);
write('oddjobz_quote.json', quoteVectors);

const visitVectors = build<OddjobzVisit>(visitCellType, [
  {
    name: 'scheduled — minimum viable Visit',
    input: {
      visitId: VISIT1,
      jobId: JOB1,
      visitType: 'inspection',
      status: 'scheduled',
      createdAt: T1,
      updatedAt: T1,
    },
  },
  {
    name: 'scheduled — with timeslot + operator',
    input: {
      visitId: VISIT2,
      jobId: JOB2,
      siteId: SITE1,
      assignedOperatorId: OP1,
      visitType: 'scheduled_work',
      status: 'scheduled',
      scheduledStart: T2,
      scheduledEnd: T3,
      notes: 'Bring step ladder.',
      createdAt: T1,
      updatedAt: T1,
    },
  },
  {
    name: 'completed — outcome attached',
    input: {
      visitId: VISIT3,
      jobId: JOB3,
      siteId: SITE2,
      assignedOperatorId: OP2,
      visitType: 'scheduled_work',
      status: 'completed',
      scheduledStart: T2,
      scheduledEnd: T3,
      actualStart: T2,
      actualEnd: T3,
      outcome: 'completed',
      notes: 'Job finished on schedule. Customer paid via card.',
      nextAction: 'Send invoice within 24h.',
      createdAt: T1,
      updatedAt: T3,
    },
  },
]);
write('oddjobz_visit.json', visitVectors);

const invoiceVectors = build<OddjobzInvoice>(invoiceCellType, [
  {
    name: 'draft — no external id yet',
    input: {
      invoiceId: INV1,
      jobId: JOB1,
      status: 'draft',
      amount: 33000,
      createdAt: T3,
      updatedAt: T3,
    },
  },
  {
    name: 'sent — with currency + due date',
    input: {
      invoiceId: INV2,
      jobId: JOB2,
      customerId: C1,
      status: 'sent',
      externalInvoiceId: 'INV-00042',
      currency: 'AUD',
      amount: 75000,
      sentAt: T3,
      dueAt: T6,
      summary: 'Bathroom tap repair — labour + parts.',
      createdAt: T3,
      updatedAt: T3,
    },
  },
  {
    name: 'paid — full settlement',
    input: {
      invoiceId: INV3,
      jobId: JOB3,
      customerId: C2,
      status: 'paid',
      externalInvoiceId: 'INV-00043',
      currency: 'AUD',
      amount: 150000,
      amountPaid: 150000,
      sentAt: T3,
      viewedAt: T4,
      paidAt: T6,
      dueAt: T6,
      createdAt: T3,
      updatedAt: T6,
    },
  },
]);
write('oddjobz_invoice.json', invoiceVectors);

const estimateVectors = build<OddjobzEstimate>(estimateCellType, [
  {
    name: 'auto_rom — bare draft',
    input: {
      estimateId: EST1,
      jobId: JOB1,
      estimateType: 'auto_rom',
      effortBand: 'quick',
      costMin: 8000,
      costMax: 18000,
      createdAt: T0,
      updatedAt: T0,
    },
  },
  {
    name: 'operator_rom — with assumptions',
    input: {
      estimateId: EST2,
      jobId: JOB2,
      authoredByOperatorId: OP1,
      estimateType: 'operator_rom',
      effortBand: 'short',
      hoursMin: 1,
      hoursMax: 2,
      costMin: 18000,
      costMax: 30000,
      labourOnly: true,
      assumptionNotes: 'Assumes existing isolation valve works.',
      createdAt: T0,
      updatedAt: T1,
    },
  },
  {
    name: 'revised — customer pushback recorded',
    input: {
      estimateId: EST3,
      jobId: JOB3,
      authoredByOperatorId: OP2,
      estimateType: 'revised',
      effortBand: 'half_day',
      hoursMin: 3,
      hoursMax: 5,
      costMin: 50000,
      costMax: 80000,
      labourOnly: false,
      materialsNote: 'Cabling 50m, two GPOs, isolator.',
      ackStatus: 'pushback',
      acknowledgedAt: T2,
      customerAcknowledgedEstimate: true,
      createdAt: T0,
      updatedAt: T2,
    },
  },
]);
write('oddjobz_estimate.json', estimateVectors);

const messageVectors = build<OddjobzMessage>(messageCellType, [
  {
    name: 'customer text — basic',
    input: {
      messageId: MSG1,
      jobId: JOB1,
      senderType: 'customer',
      messageType: 'text',
      rawContent: 'Hi, my kitchen tap is leaking. Can someone come look at it?',
      createdAt: T0,
    },
  },
  {
    name: 'operator text — with channel + operator id',
    input: {
      messageId: MSG2,
      jobId: JOB2,
      customerId: C1,
      channel: 'sms',
      channelId: CHANNEL1,
      senderType: 'operator',
      senderOperatorId: OP1,
      messageType: 'text',
      rawContent: 'Sure — can do tomorrow morning between 9 and 11. Does that work?',
      createdAt: T1,
    },
  },
  {
    name: 'voice with transcript',
    input: {
      messageId: MSG3,
      jobId: JOB3,
      customerId: C2,
      channel: 'webchat',
      senderType: 'customer',
      messageType: 'voice',
      rawContent: 'audio://upload/voice-msg-1.webm',
      transcript: 'Sorry I missed your call earlier. Thursday afternoon would be perfect.',
      uploadId: UPLOAD1,
      createdAt: T2,
    },
  },
  {
    name: 'system patch on customer (no jobId)',
    input: {
      messageId: MSG4,
      customerId: C1,
      senderType: 'system',
      messageType: 'system',
      rawContent: 'Customer mobile number verified via SMS code at 2026-04-22T12:00:00Z.',
      createdAt: T5,
    },
  },
]);
write('oddjobz_message.json', messageVectors);

// ── D-O6b — Lead vectors ─────────────────────────────────────────────
const LEAD1 = '30303030-3030-4030-8030-303030303030';
const LEAD2 = '31313131-3131-4131-8131-313131313131';
const LEAD3 = '32323232-3232-4232-8232-323232323232';
// 16-byte hex operator cert ids (32 hex chars).
const OPCERT1 = '20202020202040208020202020202020';
const OPCERT2 = '21212121212141218121212121212121';
const T_RATIFY1 = '2026-05-01T09:30:00Z';
const T_RATIFY2 = '2026-05-02T11:15:00Z';
const T_RATIFY3 = '2026-05-03T16:45:00Z';

const leadVectors = build<OddjobzLead>(leadCellType, [
  {
    name: 'from_chat — deck repair extracted from anonymous chat',
    input: {
      leadId: LEAD1,
      chatSessionId: 'session-deck-repair-abc-123',
      extractedEstimateId: EST1,
      customerHint: 'Sam Tradie / 0400-111-222 / urgent deck repair, ~$3000 budget',
      jobId: JOB1,
      ratifiedBy: OPCERT1,
      ratifiedAt: T_RATIFY1,
      provenance: 'from_chat',
    },
  },
  {
    name: 'from_walk_in — operator created lead at site, no chat session',
    input: {
      leadId: LEAD2,
      chatSessionId: '',
      extractedEstimateId: EST2,
      customerHint: 'Walk-in: bathroom tile regrout job',
      jobId: JOB2,
      ratifiedBy: OPCERT2,
      ratifiedAt: T_RATIFY2,
      provenance: 'from_walk_in',
    },
  },
  {
    name: 'from_phone — phone enquiry, customer hint empty (operator skipped detail)',
    input: {
      leadId: LEAD3,
      chatSessionId: '',
      extractedEstimateId: EST3,
      customerHint: '',
      jobId: JOB3,
      ratifiedBy: OPCERT1,
      ratifiedAt: T_RATIFY3,
      provenance: 'from_phone',
    },
  },
]);
write('oddjobz_lead.json', leadVectors);

// ── D-O5m.followup-8 substrate — Attachment vectors ────────────────────
const ATT1 = '4a4a4a4a-4a4a-4a4a-8a4a-4a4a4a4a4a4a';
const ATT2 = '4b4b4b4b-4b4b-4b4b-8b4b-4b4b4b4b4b4b';
const ATT3 = '4c4c4c4c-4c4c-4c4c-8c4c-4c4c4c4c4c4c';
const DEVICE_CERT_1 = '20202020202040208020202020202020';
const DEVICE_CERT_2 = '21212121212141218121212121212121';
const T_CAP1 = '2026-05-15T14:30:00Z';
const T_CAP2 = '2026-05-15T14:32:15Z';
const T_CAP3 = '2026-05-15T14:35:42Z';
const T_RX1 = '2026-05-15T14:30:01Z';
const T_RX2 = '2026-05-15T14:32:16Z';
const T_RX3 = '2026-05-15T14:35:43Z';
// Stable sha256-hex placeholders (deterministic so the generator
// produces identical bytes across re-runs).
const HASH_PHOTO = 'a'.repeat(64);
const HASH_VOICE = 'b'.repeat(64);
const HASH_GPS = 'c'.repeat(64);

const attachmentVectors = build<OddjobzAttachment>(attachmentCellType, [
  {
    name: 'photo — minimum viable Attachment',
    input: {
      attachmentId: ATT1,
      visitId: VISIT2,
      kind: 'photo',
      contentHash: HASH_PHOTO,
      contentSize: 2_457_600,
      mimeType: 'image/heic',
      capturedAt: T_CAP1,
      capturedByCertId: DEVICE_CERT_1,
      createdAt: T_RX1,
    },
  },
  {
    name: 'voice_memo — with caption',
    input: {
      attachmentId: ATT2,
      visitId: VISIT2,
      kind: 'voice_memo',
      contentHash: HASH_VOICE,
      contentSize: 184_320,
      mimeType: 'audio/m4a',
      capturedAt: T_CAP2,
      capturedByCertId: DEVICE_CERT_1,
      caption: 'Customer asked about the asbestos eaves on the west side.',
      createdAt: T_RX2,
    },
  },
  {
    name: 'gps_pin — different device cert',
    input: {
      attachmentId: ATT3,
      visitId: VISIT3,
      kind: 'gps_pin',
      contentHash: HASH_GPS,
      contentSize: 64,
      mimeType: 'application/json',
      capturedAt: T_CAP3,
      capturedByCertId: DEVICE_CERT_2,
      caption: 'Side gate access point.',
      createdAt: T_RX3,
    },
  },
]);
write('oddjobz_attachment.json', attachmentVectors);

// ── oddjobz.pricing_policy.v1 (A5 / DEBT-XLANG-CELL-CONTRACT) ─────────
//
// These vectors are the SINGLE CANONICAL ORACLE for the operator
// pricing-policy cell contract. The TS cell-type (the source of truth)
// authors them; the §O2-style parity test pins them on the TS side;
// and the Zig P2.d set_pricing_policy handler's conformance test
// consumes these exact (input → packed) pairs so a hand-mirrored Zig
// implementation cannot silently drift from the TS encoding /
// validation / amendment-chain invariants. Stable ids + fixed
// timestamps ⇒ re-running the generator is byte-identical.
const POLICY_ID = '99999999-9999-4999-8999-999999999999';
const OP_CERT = 'abad1deabad1deab';
const PREV_HASH_2 =
  '1111111111111111111111111111111111111111111111111111111111111111';
const PREV_HASH_3 =
  '2222222222222222222222222222222222222222222222222222222222222222';
const POLICY_T0 = '2026-05-18T00:00:00.000Z';
const POLICY_T1 = '2026-06-01T00:00:00.000Z';
const POLICY_T2 = '2026-07-01T00:00:00.000Z';

const pricingPolicyVectors = build<OddjobzPricingPolicy>(pricingPolicyCellType, [
  {
    name: 'genesis — minimal policy (v1, no prevPolicyHash)',
    input: {
      policyId: POLICY_ID,
      hatId: 'hat-operator-todd',
      version: 1,
      signedByOperatorId: OP_CERT,
      policy: {
        baseRates: { short: { min: 200, max: 400 } },
        travelModifiers: { core: { surcharge: 0, label: 'Core' } },
        categoryModifiers: {},
        complexityModifiers: {},
        presentation: {
          roundTo: 10,
          rangeLabel: 'Typically',
          disclaimer: 'Ballpark only.',
        },
      },
      createdAt: POLICY_T0,
      updatedAt: POLICY_T0,
    },
  },
  {
    name: 'genesis — AU default policy (the seeded starting policy)',
    input: {
      policyId: POLICY_ID,
      hatId: 'hat-operator-todd',
      version: 1,
      signedByOperatorId: OP_CERT,
      policy: AU_DEFAULT_PRICING_POLICY,
      createdAt: POLICY_T0,
      updatedAt: POLICY_T0,
    },
  },
  {
    name: 'amendment — v2 (prevPolicyHash chain link, orgMarkup added)',
    input: {
      policyId: POLICY_ID,
      hatId: 'hat-operator-todd',
      version: 2,
      prevPolicyHash: PREV_HASH_2,
      signedByOperatorId: OP_CERT,
      policy: {
        baseRates: { short: { min: 200, max: 400 } },
        travelModifiers: { core: { surcharge: 0, label: 'Core' } },
        categoryModifiers: {},
        complexityModifiers: {},
        orgMarkup: { percent: 12, label: 'Founder premium' },
        presentation: {
          roundTo: 10,
          rangeLabel: 'Typically',
          disclaimer: 'Ballpark only.',
        },
      },
      createdAt: POLICY_T0,
      updatedAt: POLICY_T1,
    },
  },
  {
    name: 'amendment — v3 (full chain link, urgency + minimumCallout)',
    input: {
      policyId: POLICY_ID,
      hatId: 'hat-operator-todd',
      version: 3,
      prevPolicyHash: PREV_HASH_3,
      signedByOperatorId: OP_CERT,
      policy: {
        baseRates: { short: { min: 200, max: 400 } },
        travelModifiers: { core: { surcharge: 0, label: 'Core' } },
        categoryModifiers: {},
        complexityModifiers: {},
        urgencyModifiers: {
          emergency: { premiumPct: 50, label: 'Emergency response' },
        },
        minimumCallout: { amount: 120, label: 'Minimum call-out' },
        presentation: {
          roundTo: 10,
          rangeLabel: 'Typically',
          disclaimer: 'Ballpark only.',
        },
      },
      createdAt: POLICY_T0,
      updatedAt: POLICY_T2,
    },
  },
]);
write('oddjobz_pricing_policy.json', pricingPolicyVectors);

// eslint-disable-next-line no-console
console.log('done.');

```
