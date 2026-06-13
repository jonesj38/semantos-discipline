---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/message.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.502679+00:00
---

# cartridges/oddjobz/brain/src/cell-types/message.ts

```ts
/**
 * `oddjobz.message.v1` — PATCH cell.
 *
 * Customer/operator chat messages. Per §O2: "patches Job or Customer".
 * Wire-level RELEVANT (DUP allowed, no DROP) — many message cells
 * accumulate against the same Job; the §O8 compaction phase reduces
 * them periodically. The cell's `parentHash` (set in the wire envelope
 * by §O3 minting) points at the Job (or Customer) being patched.
 *
 * Field shape derived from the legacy `messages` table (text + voice
 * channels, with optional structured-extraction JSON). Uploads are
 * referenced by ID rather than embedded — the legacy `uploads` table
 * stores the actual artefact location.
 */

import { defineCellType, type CellTypeDef } from './cell-type.js';
import {
  assertUuid,
  assertOptionalUuid,
  assertOptionalString,
  assertEnum,
  assertOptionalEnum,
  assertNonEmptyString,
  assertIsoDateString,
} from './validators.js';

export const SENDER_TYPES = ['customer', 'operator', 'system', 'ai'] as const;
export type SenderType = (typeof SENDER_TYPES)[number];

export const MESSAGE_TYPES = ['text', 'voice', 'image', 'file', 'system'] as const;
export type MessageType = (typeof MESSAGE_TYPES)[number];

export const CONTACT_CHANNELS_M = [
  'phone',
  'sms',
  'email',
  'webchat',
  'in_person',
  'facebook',
  'instagram',
] as const;
export type MessageChannel = (typeof CONTACT_CHANNELS_M)[number];

export interface OddjobzMessage {
  /** Stable message identifier (UUID v4). */
  readonly messageId: string;
  /** Job the message patches (UUID v4). May be null if it patches a Customer directly. */
  readonly jobId?: string;
  /** Customer the message patches (UUID v4). */
  readonly customerId?: string;
  /** Channel the message arrived on / was sent over. */
  readonly channel?: MessageChannel;
  /** Channel session identifier (UUID v4); links to a sem_channels row. */
  readonly channelId?: string;

  /** Sender role. */
  readonly senderType: SenderType;
  /** Operator UUID v4 if `senderType` is `operator`. */
  readonly senderOperatorId?: string;

  /** Kind of message. */
  readonly messageType: MessageType;
  /** Raw content as received (text, transcript fallback, etc.). */
  readonly rawContent: string;
  /** Voice transcript when `messageType=voice`. */
  readonly transcript?: string;
  /** ID of an attached upload (UUID v4); the upload itself lives elsewhere. */
  readonly uploadId?: string;

  /** ISO-8601 cell creation timestamp. */
  readonly createdAt: string;
}

function validate(v: OddjobzMessage): void {
  assertUuid('messageId', v.messageId);
  assertOptionalUuid('jobId', v.jobId);
  assertOptionalUuid('customerId', v.customerId);
  assertOptionalEnum('channel', v.channel, CONTACT_CHANNELS_M);
  assertOptionalUuid('channelId', v.channelId);
  assertEnum('senderType', v.senderType, SENDER_TYPES);
  assertOptionalUuid('senderOperatorId', v.senderOperatorId);
  assertEnum('messageType', v.messageType, MESSAGE_TYPES);
  assertNonEmptyString('rawContent', v.rawContent);
  assertOptionalString('transcript', v.transcript);
  assertOptionalUuid('uploadId', v.uploadId);
  assertIsoDateString('createdAt', v.createdAt);

  // A patch must point at SOMETHING — either a job or a customer.
  if (v.jobId === undefined && v.customerId === undefined) {
    throw new Error('message: must reference at least one of jobId or customerId');
  }
  if (v.senderType === 'operator' && v.senderOperatorId === undefined) {
    throw new Error('message: senderType=operator requires senderOperatorId');
  }
  if (v.messageType === 'voice' && v.transcript === undefined) {
    // Not a hard error — transcript may arrive later — but warn shape
    // by requiring rawContent to look like a placeholder URL/ref.
    if (v.rawContent.length === 0) {
      throw new Error('message: voice messageType requires non-empty rawContent (audio ref)');
    }
  }
}

function toCanonical(v: OddjobzMessage): Record<string, unknown> {
  const out: Record<string, unknown> = {
    messageId: v.messageId,
    senderType: v.senderType,
    messageType: v.messageType,
    rawContent: v.rawContent,
    createdAt: v.createdAt,
  };
  if (v.jobId !== undefined) out.jobId = v.jobId;
  if (v.customerId !== undefined) out.customerId = v.customerId;
  if (v.channel !== undefined) out.channel = v.channel;
  if (v.channelId !== undefined) out.channelId = v.channelId;
  if (v.senderOperatorId !== undefined) out.senderOperatorId = v.senderOperatorId;
  if (v.transcript !== undefined) out.transcript = v.transcript;
  if (v.uploadId !== undefined) out.uploadId = v.uploadId;
  return out;
}

function fromCanonical(c: unknown): OddjobzMessage {
  if (typeof c !== 'object' || c === null) throw new Error('message: payload not an object');
  const r = c as Record<string, unknown>;
  return {
    messageId: r.messageId as string,
    jobId: r.jobId as string | undefined,
    customerId: r.customerId as string | undefined,
    channel: r.channel as MessageChannel | undefined,
    channelId: r.channelId as string | undefined,
    senderType: r.senderType as SenderType,
    senderOperatorId: r.senderOperatorId as string | undefined,
    messageType: r.messageType as MessageType,
    rawContent: r.rawContent as string,
    transcript: r.transcript as string | undefined,
    uploadId: r.uploadId as string | undefined,
    createdAt: r.createdAt as string,
  };
}

export const messageCellType: CellTypeDef<OddjobzMessage> = defineCellType({
  name: 'oddjobz.message.v1',
  identity: {
    whatPath: 'oddjobz.message',
    howSlug: 'communicate',
    instPath: 'inst.signal.chat-message',
  },
  // §O2's draft table labelled this PATCH. PATCH has no formal Lean
  // backing — see linearity.ts header. The parentHash-anchoring +
  // compaction semantics that distinguish a "patch" from plain
  // RELEVANT live at the state-machine layer (D-O4), not at the
  // kernel-gate layer. We ship as PERSISTENT (wire RELEVANT) so the
  // kernel-gate check inherits Lean K1's RELEVANT proof; the
  // patch-anchoring semantics are tracked separately when D-O4 wires
  // the messaging FSM.
  linearity: 'PERSISTENT',
  toCanonical,
  fromCanonical,
  validate,
});

```
