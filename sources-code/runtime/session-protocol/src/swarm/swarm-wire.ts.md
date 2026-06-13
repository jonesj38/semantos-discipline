---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/swarm-wire.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.052180+00:00
---

# runtime/session-protocol/src/swarm/swarm-wire.ts

```ts
/**
 * Swarm wire frames — HAVE / REQUEST / CELL / PAY, layered on the existing
 * 12-byte multicast `wire-header.ts`.
 *
 * The hot path is multicast frames only (engine↔engine); these codecs define
 * their payloads. The 12-byte CoAP-like header (version/msgType/msgId/node/
 * timestamp/payloadLen) wraps every payload via `framePacket`.
 *
 *   MSG_SWARM_HAVE    0x10  broadcast bitfield (see have-bitfield.encodeHave)
 *   MSG_SWARM_REQUEST 0x11  unicast: "send me cell i" (+ optional prepayment)
 *   MSG_SWARM_CELL    0x12  unicast: the cell bytes + per-cell merkle proof
 *   MSG_SWARM_PAY     0x13  unicast: a post-pay receipt for a served cell
 *
 * The CELL frame embeds the inclusion proof so a leecher verifies against the
 * manifest's merkle root without the full leaf-hash vector. Proof size grows
 * ~log2(totalCells) (≤528B at 65536 cells); for typical files the whole frame
 * stays under a 1500B datagram. Files large enough to overflow one datagram
 * would need proof-batching / segmented delivery — a future data-plane
 * optimisation, out of scope for v1.
 *
 * Pure — no transport. Frames are built/parsed here; the adapter sends them.
 */

import { CELL_SIZE, type CellMerkleProof } from '@semantos/protocol-types';
import {
  HEADER_SIZE,
  encodeHeader,
  decodeHeader,
  framePacket,
  type WireHeader,
} from '../adapters/multicast/wire-header';
import { encodeHave, decodeHave, type HavePayload } from './have-bitfield';

export const MSG_SWARM_HAVE = 0x10;
export const MSG_SWARM_REQUEST = 0x11;
export const MSG_SWARM_CELL = 0x12;
export const MSG_SWARM_PAY = 0x13;

export { encodeHave, decodeHave };
export type { HavePayload };

const SIBLING_ENTRY_SIZE = 33; // 32B hash + 1B position
const CURRENCY_SIZE = 4;
const BCA_SIZE = 16;

// ── currency (4-byte ascii, NUL-padded) ───────────────────────────────────────

function encodeCurrency(currency: string): Uint8Array {
  const buf = new Uint8Array(CURRENCY_SIZE);
  const ascii = new TextEncoder().encode(currency);
  if (ascii.length > CURRENCY_SIZE) throw new Error(`currency "${currency}" exceeds ${CURRENCY_SIZE} bytes`);
  buf.set(ascii, 0);
  return buf;
}
function decodeCurrency(buf: Uint8Array): string {
  let end = 0;
  while (end < buf.length && buf[end] !== 0) end++;
  return new TextDecoder().decode(buf.subarray(0, end));
}

// ── payment proof (shared by REQUEST prepay + PAY receipt) ─────────────────────

export interface SwarmPayment {
  /** Tx id / BEEF root that anchors the spend (32B). */
  txAnchor: Uint8Array;
  amount: bigint;
  currency: string;
}

/** Encoded payment size: txAnchor(32) + amount(8) + currency(4). */
const PAYMENT_SIZE = 32 + 8 + CURRENCY_SIZE;

function writePayment(view: DataView, buf: Uint8Array, off: number, p: SwarmPayment): number {
  if (p.txAnchor.length !== 32) throw new Error('payment.txAnchor must be 32 bytes');
  buf.set(p.txAnchor, off);
  view.setBigUint64(off + 32, p.amount, true);
  buf.set(encodeCurrency(p.currency), off + 40);
  return off + PAYMENT_SIZE;
}
function readPayment(view: DataView, buf: Uint8Array, off: number): SwarmPayment {
  return {
    txAnchor: buf.slice(off, off + 32),
    amount: view.getBigUint64(off + 32, true),
    currency: decodeCurrency(buf.subarray(off + 40, off + 44)),
  };
}

// ── metered-flow commitment (payment-channel alternative to a per-cell tx) ─────

/** A signed MFP channel commitment — the running off-chain tab. */
export interface CommitmentPayment {
  flowId: string;
  seq: number;
  cumulativeSats: bigint;
  signature: Uint8Array;
}

function writeCommitment(view: DataView, buf: Uint8Array, off: number, c: CommitmentPayment): number {
  const fid = new TextEncoder().encode(c.flowId);
  if (fid.length > 255 || c.signature.length > 255) throw new Error('commitment: flowId/signature too long');
  view.setUint32(off, c.seq >>> 0, true);
  view.setBigUint64(off + 4, c.cumulativeSats, true);
  off += 12;
  buf[off++] = fid.length;
  buf.set(fid, off); off += fid.length;
  buf[off++] = c.signature.length;
  buf.set(c.signature, off); off += c.signature.length;
  return off;
}
function commitmentSize(c: CommitmentPayment): number {
  return 12 + 1 + new TextEncoder().encode(c.flowId).length + 1 + c.signature.length;
}

// ── access-grant proof (engine-checked DATA_ACCESS authorization) ──────────────

/**
 * A grantee's proof that they hold a valid `access.grant` for this content: the
 * 32-byte content-address of the grant cell + the grantee's signature over the
 * canonical access-challenge digest. The seeder runs the engine-checked verify
 * `.handler` (the real 2-PDA) against it before serving. This is the swarm's
 * authorization leg, distinct from payment — see `AccessGrantServePolicy`.
 */
export interface SwarmGrantProof {
  /** 32-byte content-address of the `access.grant` cell being proven. */
  grantHash: Uint8Array;
  /** The grantee's signature over `accessChallengeDigest(grantHash, granteePk)`. */
  signature: Uint8Array;
}

function writeGrant(buf: Uint8Array, off: number, g: SwarmGrantProof): number {
  if (g.grantHash.length !== 32) throw new Error('grant proof: grantHash must be 32 bytes');
  if (g.signature.length > 255) throw new Error('grant proof: signature too long');
  buf.set(g.grantHash, off); off += 32;
  buf[off++] = g.signature.length;
  buf.set(g.signature, off); off += g.signature.length;
  return off;
}
function readGrant(buf: Uint8Array, off: number): SwarmGrantProof {
  const grantHash = buf.slice(off, off + 32); off += 32;
  const sigLen = buf[off++]!;
  const signature = buf.slice(off, off + sigLen);
  return { grantHash, signature };
}
function grantSize(g: SwarmGrantProof): number {
  return 32 + 1 + g.signature.length;
}
function readCommitment(view: DataView, buf: Uint8Array, off: number): { commitment: CommitmentPayment; next: number } {
  const seq = view.getUint32(off, true);
  const cumulativeSats = view.getBigUint64(off + 4, true);
  off += 12;
  const fidLen = buf[off++]!;
  const flowId = new TextDecoder().decode(buf.subarray(off, off + fidLen)); off += fidLen;
  const sigLen = buf[off++]!;
  const signature = buf.slice(off, off + sigLen); off += sigLen;
  return { commitment: { flowId, seq, cumulativeSats, signature }, next: off };
}

// ── REQUEST ────────────────────────────────────────────────────────────────────

export interface SwarmRequest {
  infohash: Uint8Array;
  cellIndex: number;
  /** 16-byte BCA of the requester, so the seeder can unicast the reply. */
  requesterBca: Uint8Array;
  /** Prepayment proof (per-cell on-chain tx), when paying up front. */
  payment?: SwarmPayment;
  /** Metered-flow commitment (off-chain channel tab) — the cheaper path. */
  commitment?: CommitmentPayment;
  /** Engine-checked access-grant proof (DATA_ACCESS authorization). */
  grant?: SwarmGrantProof;
}

export function encodeRequest(req: SwarmRequest): Uint8Array {
  if (req.infohash.length !== 32) throw new Error('encodeRequest: infohash must be 32 bytes');
  if (req.requesterBca.length !== BCA_SIZE) throw new Error('encodeRequest: requesterBca must be 16 bytes');
  const hasPayment = req.payment ? 1 : 0;
  const hasCommit = req.commitment ? 1 : 0;
  const hasGrant = req.grant ? 1 : 0;
  const size =
    53 +
    (hasPayment ? PAYMENT_SIZE : 0) +
    1 + (req.commitment ? commitmentSize(req.commitment) : 0) +
    1 + (req.grant ? grantSize(req.grant) : 0);
  const buf = new Uint8Array(size);
  const dv = new DataView(buf.buffer);
  buf.set(req.infohash, 0);
  dv.setUint32(32, req.cellIndex >>> 0, true);
  buf.set(req.requesterBca, 36);
  buf[52] = hasPayment;
  let off = 53;
  if (req.payment) off = writePayment(dv, buf, off, req.payment);
  buf[off++] = hasCommit;
  if (req.commitment) off = writeCommitment(dv, buf, off, req.commitment);
  buf[off++] = hasGrant;
  if (req.grant) off = writeGrant(buf, off, req.grant);
  return buf;
}

export function decodeRequest(payload: Uint8Array): SwarmRequest {
  if (payload.length < 53) throw new Error(`decodeRequest: payload too small (${payload.length})`);
  const dv = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
  const hasPayment = payload[52] === 1;
  let off = 53;
  let payment: SwarmPayment | undefined;
  if (hasPayment) {
    if (payload.length < off + PAYMENT_SIZE) throw new Error('decodeRequest: payment flag set but payload truncated');
    payment = readPayment(dv, payload, off);
    off += PAYMENT_SIZE;
  }
  let commitment: CommitmentPayment | undefined;
  if (off < payload.length && payload[off] === 1) {
    const r = readCommitment(dv, payload, off + 1);
    commitment = r.commitment;
    off = r.next;
  } else {
    off += 1; // consume the (zero) commitment flag
  }
  let grant: SwarmGrantProof | undefined;
  if (off < payload.length && payload[off] === 1) {
    grant = readGrant(payload, off + 1);
  }
  return {
    infohash: payload.slice(0, 32),
    cellIndex: dv.getUint32(32, true),
    requesterBca: payload.slice(36, 52),
    payment,
    commitment,
    grant,
  };
}

// ── CELL (cell bytes + inclusion proof) ────────────────────────────────────────

export interface SwarmCell {
  infohash: Uint8Array;
  cellIndex: number;
  proof: CellMerkleProof;
  cellBytes: Uint8Array;
}

export function encodeCell(c: SwarmCell): Uint8Array {
  if (c.infohash.length !== 32) throw new Error('encodeCell: infohash must be 32 bytes');
  if (c.cellBytes.length !== CELL_SIZE) throw new Error(`encodeCell: cellBytes must be ${CELL_SIZE} bytes`);
  const sibs = c.proof.siblings;
  if (sibs.length > 255) throw new Error('encodeCell: too many proof siblings');
  const size = 32 + 4 + 1 + sibs.length * SIBLING_ENTRY_SIZE + CELL_SIZE;
  const buf = new Uint8Array(size);
  const dv = new DataView(buf.buffer);
  buf.set(c.infohash, 0);
  dv.setUint32(32, c.cellIndex >>> 0, true);
  buf[36] = sibs.length;
  let off = 37;
  for (const sib of sibs) {
    if (sib.hash.length !== 32) throw new Error('encodeCell: sibling hash must be 32 bytes');
    buf.set(sib.hash, off);
    buf[off + 32] = sib.position === 'left' ? 0x00 : 0x01;
    off += SIBLING_ENTRY_SIZE;
  }
  buf.set(c.cellBytes, off);
  return buf;
}

export function decodeCell(payload: Uint8Array): SwarmCell {
  if (payload.length < 37) throw new Error(`decodeCell: payload too small (${payload.length})`);
  const dv = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
  const cellIndex = dv.getUint32(32, true);
  const sibCount = payload[36]!;
  const cellStart = 37 + sibCount * SIBLING_ENTRY_SIZE;
  if (payload.length < cellStart + CELL_SIZE) {
    throw new Error(`decodeCell: payload too small for ${sibCount} siblings + cell (need ${cellStart + CELL_SIZE}, got ${payload.length})`);
  }
  const siblings: CellMerkleProof['siblings'] = [];
  let off = 37;
  for (let i = 0; i < sibCount; i++) {
    siblings.push({
      hash: payload.slice(off, off + 32),
      position: payload[off + 32] === 0x00 ? 'left' : 'right',
    });
    off += SIBLING_ENTRY_SIZE;
  }
  return {
    infohash: payload.slice(0, 32),
    cellIndex,
    proof: { leafIndex: cellIndex, siblings },
    cellBytes: payload.slice(cellStart, cellStart + CELL_SIZE),
  };
}

// ── PAY (post-pay receipt) ─────────────────────────────────────────────────────

export interface SwarmPay {
  infohash: Uint8Array;
  cellIndex: number;
  payment: SwarmPayment;
}

export function encodePay(p: SwarmPay): Uint8Array {
  if (p.infohash.length !== 32) throw new Error('encodePay: infohash must be 32 bytes');
  const buf = new Uint8Array(32 + 4 + PAYMENT_SIZE);
  const dv = new DataView(buf.buffer);
  buf.set(p.infohash, 0);
  dv.setUint32(32, p.cellIndex >>> 0, true);
  writePayment(dv, buf, 36, p.payment);
  return buf;
}

export function decodePay(payload: Uint8Array): SwarmPay {
  if (payload.length < 36 + PAYMENT_SIZE) throw new Error(`decodePay: payload too small (${payload.length})`);
  const dv = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
  return {
    infohash: payload.slice(0, 32),
    cellIndex: dv.getUint32(32, true),
    payment: readPayment(dv, payload, 36),
  };
}

// ── full-packet helpers (12-byte header + payload) ─────────────────────────────

export interface FrameContext {
  msgId: number;
  nodeIdShort: number;
  timestamp: number;
}

/** Wrap a swarm payload in the 12-byte header → a complete packet. */
export function frameSwarm(msgType: number, payload: Uint8Array, ctx: FrameContext): Uint8Array {
  return framePacket(encodeHeader(msgType, ctx.msgId, ctx.nodeIdShort, ctx.timestamp, payload.length), payload);
}

export interface ParsedSwarmPacket {
  header: WireHeader;
  payload: Uint8Array;
}

/** Split a received packet into its header + payload (validates payloadLen). */
export function parseSwarm(packet: Uint8Array): ParsedSwarmPacket {
  if (packet.length < HEADER_SIZE) throw new Error(`parseSwarm: packet smaller than header (${packet.length})`);
  const header = decodeHeader(packet.subarray(0, HEADER_SIZE));
  const payload = packet.subarray(HEADER_SIZE, HEADER_SIZE + header.payloadLen);
  if (payload.length < header.payloadLen) {
    throw new Error(`parseSwarm: payloadLen ${header.payloadLen} exceeds available bytes ${payload.length}`);
  }
  return { header, payload };
}

/** True iff `msgType` is one of the swarm message types. */
export function isSwarmMsgType(msgType: number): boolean {
  return msgType >= MSG_SWARM_HAVE && msgType <= MSG_SWARM_PAY;
}

```
