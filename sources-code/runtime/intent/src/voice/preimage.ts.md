---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/voice/preimage.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.352167+00:00
---

# runtime/intent/src/voice/preimage.ts

```ts
/**
 * Canonical preimages for the voice stub.
 *
 * Two deterministic byte serialisations:
 *
 *   1. `voiceSessionPreimage(certId, startedAt)` — the bytes hashed to
 *      produce a `VoiceSessionId`. Encoding: `cert_id_bytes(32) ‖
 *      started_at_be_u64(8)`. The cert_id is parsed as 32 hex bytes;
 *      `started_at` is encoded as big-endian uint64 milliseconds since
 *      epoch.
 *
 *   2. `canonicalTranscriptPreimage(transcript)` — the bytes a
 *      transcript signature covers. Encoding: a deterministic JSON
 *      serialisation of the signed fields with sorted keys, UTF-8
 *      encoded. JSON is used (vs raw concat) because `text` is variable
 *      length and the canon discipline already accepts deterministic
 *      JSON for cross-language signing (see protocol-v0.5.md §4.2 on
 *      canonical preimages — this module follows the same shape).
 *
 * No I/O. No mutation of inputs. Pure functions only.
 */

import { Hash } from '@bsv/sdk';

import type { Transcript, VoiceSessionId } from './types';

// ── Hex helpers (kept local — no protocol-types dep on the runtime tier) ─

const HEX_RE = /^[0-9a-f]+$/i;

/** Convert a lowercase hex string to a Uint8Array. */
export function hexToBytes(hex: string): Uint8Array {
  if (hex.length === 0) {
    throw new Error('voice: hex string is empty');
  }
  if (hex.length % 2 !== 0) {
    throw new Error(`voice: hex string has odd length ${hex.length}; must be even`);
  }
  if (!HEX_RE.test(hex)) {
    throw new Error('voice: hex string contains non-hex characters');
  }
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    out[i / 2] = parseInt(hex.slice(i, i + 2), 16);
  }
  return out;
}

/** Convert a Uint8Array to a lowercase hex string. */
export function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/** Encode a non-negative integer (ms since epoch) as 8 BE bytes. */
function u64BE(n: number): Uint8Array {
  if (!Number.isFinite(n) || n < 0 || !Number.isInteger(n)) {
    throw new Error(`voice: started_at must be a non-negative integer, got ${n}`);
  }
  const out = new Uint8Array(8);
  // JS numbers are safe up to 2^53; ms-since-epoch fits comfortably.
  let v = n;
  for (let i = 7; i >= 0; i--) {
    out[i] = v & 0xff;
    v = Math.floor(v / 256);
  }
  return out;
}

// ── Voice session preimage ───────────────────────────────────

/**
 * Bytes hashed to derive a `VoiceSessionId`.
 *
 * Encoding: `cert_id_bytes(32) ‖ started_at_be_u64(8)` = 40 bytes.
 *
 * @param certIdHex   - 64-char lowercase hex of the speaker's cert_id.
 * @param startedAt   - Milliseconds since epoch.
 */
export function voiceSessionPreimage(certIdHex: string, startedAt: number): Uint8Array {
  const certBytes = hexToBytes(certIdHex);
  if (certBytes.length !== 32) {
    throw new Error(
      `voice: cert_id must be 32 bytes (64 hex chars), got ${certBytes.length}`,
    );
  }
  const ts = u64BE(startedAt);
  const out = new Uint8Array(40);
  out.set(certBytes, 0);
  out.set(ts, 32);
  return out;
}

/**
 * Compute a deterministic `VoiceSessionId` from a cert_id and start
 * time. Two transcripts in the same session share this id.
 */
export function deriveVoiceSessionId(certIdHex: string, startedAt: number): VoiceSessionId {
  const preimage = voiceSessionPreimage(certIdHex, startedAt);
  const digest = Hash.sha256(Array.from(preimage)) as number[];
  return bytesToHex(new Uint8Array(digest)) as VoiceSessionId;
}

// ── Transcript canonical preimage ────────────────────────────

/**
 * Build the canonical preimage that a transcript signature covers.
 *
 * The covered fields are everything *except* `signature` and `id`:
 * `sessionId`, `certId`, `sequence`, `text`, `timestamp`. Fields are
 * serialised as a JSON object with keys in sorted order (for
 * deterministic byte output across implementations) and UTF-8 encoded.
 */
export function canonicalTranscriptPreimage(
  fields: Pick<Transcript, 'sessionId' | 'certId' | 'sequence' | 'text' | 'timestamp'>,
): Uint8Array {
  // Build with explicit key order; sorted alphabetically for stability.
  const obj = {
    certId: fields.certId,
    sequence: fields.sequence,
    sessionId: fields.sessionId,
    text: fields.text,
    timestamp: fields.timestamp,
  };
  // JSON.stringify with explicit key list = deterministic ordering.
  const json = JSON.stringify(obj, [
    'certId',
    'sequence',
    'sessionId',
    'text',
    'timestamp',
  ]);
  return new TextEncoder().encode(json);
}

/**
 * Compute a deterministic per-transcript id from
 * `(sessionId, sequence)` so transcripts in the same session can be
 * correlated without a separate id registry.
 *
 * Encoding: `SHA-256(sessionId_utf8 ‖ ":" ‖ sequence_decimal_utf8)`.
 */
export function deriveTranscriptId(sessionId: VoiceSessionId, sequence: number): string {
  if (!Number.isInteger(sequence) || sequence < 0) {
    throw new Error(`voice: sequence must be a non-negative integer, got ${sequence}`);
  }
  const enc = new TextEncoder();
  const buf = enc.encode(`${sessionId}:${sequence}`);
  const digest = Hash.sha256(Array.from(buf)) as number[];
  return bytesToHex(new Uint8Array(digest));
}

```
