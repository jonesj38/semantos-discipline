---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/der.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.650754+00:00
---

# cartridges/wallet-headers/brain/src/der.ts

```ts
// DER encode/decode for ECDSA secp256k1 signatures.
//
// @noble/secp256k1 v2 dropped DER helpers (compact 64-byte r||s only). The
// cell-engine `host_sign` extern is documented (core/cell-engine/src/host.zig
// line 35) to produce a "BSV-format DER signature WITHOUT the trailing
// sighash byte" — and `host_checksig` receives the same. This module
// implements just-enough DER for a 32-byte r and 32-byte s.
//
// DER layout (BSV/Bitcoin canonical):
//   0x30 || total_len || 0x02 || r_len || r_bytes || 0x02 || s_len || s_bytes
// r and s are big-endian; if the high bit is set, a leading 0x00 is prepended
// to keep them positive in DER's signed-integer encoding.

const SEQ = 0x30;
const INT = 0x02;

/** Trim leading zeros, then prepend a single 0x00 if the MSB is set. */
function trimAndPad(n: Uint8Array): Uint8Array {
  let start = 0;
  while (start < n.length - 1 && n[start] === 0) start++;
  const trimmed = n.subarray(start);
  if (trimmed[0]! & 0x80) {
    const padded = new Uint8Array(trimmed.length + 1);
    padded.set(trimmed, 1);
    return padded;
  }
  return trimmed;
}

/** Encode (r, s) bigint pair as canonical DER bytes (no sighash byte). */
export function encodeDer(r: bigint, s: bigint): Uint8Array {
  const rBytes = trimAndPad(bigintToBytes32(r));
  const sBytes = trimAndPad(bigintToBytes32(s));
  const total = 2 + rBytes.length + 2 + sBytes.length;
  const out = new Uint8Array(2 + total);
  out[0] = SEQ;
  out[1] = total;
  out[2] = INT;
  out[3] = rBytes.length;
  out.set(rBytes, 4);
  const sOff = 4 + rBytes.length;
  out[sOff] = INT;
  out[sOff + 1] = sBytes.length;
  out.set(sBytes, sOff + 2);
  return out;
}

/** Decode a DER signature into (r, s). Throws on malformed input. */
export function decodeDer(bytes: Uint8Array): { r: bigint; s: bigint } {
  if (bytes.length < 8 || bytes[0] !== SEQ) throw new Error('der: bad seq');
  const total = bytes[1]!;
  // Allow short-form length only (always the case for a 64–72 byte sig).
  if (total > 0x7f) throw new Error('der: long-form length unsupported');
  if (2 + total > bytes.length) throw new Error('der: total > buffer');
  let off = 2;
  if (bytes[off] !== INT) throw new Error('der: r not int');
  off++;
  const rLen = bytes[off]!;
  off++;
  if (off + rLen > bytes.length) throw new Error('der: r overflow');
  const r = bytesToBigint(bytes.subarray(off, off + rLen));
  off += rLen;
  if (bytes[off] !== INT) throw new Error('der: s not int');
  off++;
  const sLen = bytes[off]!;
  off++;
  if (off + sLen > bytes.length) throw new Error('der: s overflow');
  const s = bytesToBigint(bytes.subarray(off, off + sLen));
  return { r, s };
}

function bigintToBytes32(n: bigint): Uint8Array {
  const out = new Uint8Array(32);
  let x = n;
  for (let i = 31; i >= 0; i--) {
    out[i] = Number(x & 0xffn);
    x >>= 8n;
  }
  return out;
}

function bytesToBigint(b: Uint8Array): bigint {
  let n = 0n;
  for (const byte of b) n = (n << 8n) | BigInt(byte);
  return n;
}

```
