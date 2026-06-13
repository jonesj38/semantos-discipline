---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/BRC100-CANONICAL-DIGEST.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.743307+00:00
---

# BRC-100 Canonical Signed-Payload Digest

**Version**: 1.0
**Status**: Normative
**Authors**: Todd
**Related**: `apps/wallet-browser/src/brc100.ts`, `runtime/node/src/brc100.zig`,
`docs/design/WALLET-TIER-CUSTODY.md` §8

---

## 0. Purpose

Every BRC-100 wallet runtime — browser bundle (W5), sovereign-node daemon (W6),
future targets — verifies the same transport signature against the same
canonical digest. Without a single normative formula, two runtimes can produce
signatures the other cannot verify even when they're logically equivalent.

This document pins the digest formula. Wire-format encodings around it (HTTP
headers, postMessage records, JSON envelopes) MAY differ per transport as long
as both ends reconstruct the same `(identityKey, nonce, timestamp, body)`
inputs.

---

## 1. The formula

```
digest = SHA256( identityKey(33) ‖ nonce(32) ‖ timestamp_le8 ‖ body )
```

| Component | Encoding | Notes |
|---|---|---|
| `identityKey` | 33 raw bytes | SEC1 compressed secp256k1 public key. |
| `nonce` | 32 raw bytes | Random per request. Replay protection. |
| `timestamp_le8` | 8 raw bytes (u64 little-endian) | Unix time in **seconds**, fitting in u32, zero-extended into the u64 field. |
| `body` | opaque bytes | Whatever the caller signs. Treated as a byte string — no canonicalization, no UTF-8 normalization. |

The signature commits to this digest under the wallet's identity private key
(ECDSA secp256k1 with low-S normalization, BSV convention).

---

## 2. What "body" is

`body` is opaque to the BRC-100 envelope layer. Conventions per use case:

- **Wallet RPC** (browser dApp ↔ sovereign-node daemon): body is the UTF-8
  bytes of `JSON.stringify({method, params, id})`. The daemon parses body as
  JSON internally to route the request, but the digest is computed over the
  body bytes as they appear on the wire.

- **Plexus dispatch** (W7): body is the UTF-8 bytes of the dispatch envelope
  JSON (per `WALLET-TIER-CUSTODY.md` §8.2).

- **Generic signed message**: body is whatever bytes the dApp wants the wallet
  to commit to.

The digest formula does NOT distinguish between these. It hashes whatever bytes
are passed.

---

## 3. Why this formula

- **All raw bytes, no text encoding ambiguity.** Hex / decimal / newline
  separators all introduce edge cases (case sensitivity, whitespace, locale).
  Raw bytes have none.
- **Body is opaque.** The signing layer doesn't need to understand the inner
  RPC structure. Generic and reusable.
- **u64 LE timestamp is consistent with BSV transaction-format conventions.**
- **Matches W5's existing implementation** — chosen as the canonical anchor
  because it landed first and has more tests.

---

## 4. Conforming implementations

### Browser bundle (W5)
`apps/wallet-browser/src/brc100.ts::envelopeDigest` — implements §1 directly.

### Sovereign-node daemon (W6)
`runtime/node/src/brc100.zig::computeDigest` — implements §1 directly.

### Future Plexus dispatch (W7)
`apps/wallet-browser/src/plexus.ts` — uses `envelopeDigest` for the
identity-signed dispatch envelope.

---

## 5. Wire-format conventions per transport

These differ per transport but reconstruct the same digest inputs.

### Browser postMessage (W5)
```js
{
  identityKey: "<33-byte sec1, hex>",
  nonce:       "<32-byte hex>",
  timestamp:   <u32 unix seconds, JSON number>,
  signature:   "<DER bytes, hex>",
  body:        Uint8Array | "<utf-8 string>",
}
```

### Sovereign-node WSS (W6)
```json
{
  "headers": {
    "x-brc100-identitykey": "<33-byte sec1, hex>",
    "x-brc100-nonce":       "<32-byte hex>",
    "x-brc100-timestamp":   "<u32 unix seconds, decimal string>",
    "x-brc100-signature":   "<DER bytes, hex>"
  },
  "body": "<utf-8 string>"
}
```

### Plexus dispatch (W7)
HTTP `POST /enrollment/dispatch` with the wire format inherited from W5
(Plexus operator's HTTP server speaks BRC-100).

---

## 6. Replay protection

Each runtime maintains a per-`identityKey` window of seen `(nonce, timestamp)`
pairs. The window:

- MUST reject any envelope whose `(identityKey, nonce)` pair has been seen
  before within `replayWindowSecs` seconds.
- MUST reject any envelope whose `timestamp` is older than `replayWindowSecs`
  seconds in the past.
- MUST reject any envelope whose `timestamp` is more than 60 seconds in the
  future (clock skew tolerance).

`replayWindowSecs` defaults to 300 (5 minutes).

---

## 7. Versioning

This is digest format **v1**. If a future incompatible format ships:
- Bump to v2 in a parallel doc.
- Add a `version` byte at the front of the digest input: `0x02 ‖ identityKey ‖ ...`.
- Continue accepting v1 envelopes during a deprecation window.

v1 has no version byte (digest input starts with `identityKey`). Implementations
detecting `version_byte=0x01` at the front of any future envelope MUST reject
— that byte is reserved for the v1↔vN bridge.

---

## 8. Test vectors

Implementations MUST agree on these vectors. The pinned digests below are
reproduced bit-for-bit by:
- `apps/wallet-browser/test/brc100-vectors.spec.ts` (W5 TS / WebCrypto)
- `runtime/node/tests/brc100_vectors.zig` (W6 Zig / std.crypto)

Adding a new vector requires landing it in **both** files in the same commit.

### Vector 1 — empty body

```
sk          = 00 ** 31 || 01                           (the well-known
                                                        "1" private key —
                                                        derived pk is the
                                                        secp256k1 generator
                                                        point in compressed
                                                        SEC1 form)
identityKey = 02 79be667ef9dcbbac55a06295ce870b07
              029bfcdb2dce28d959f2815b16f81798         (33 bytes)
nonce       = 00 ** 32
timestamp   = 0
body        = ""

digest      = 9967659398ba69b0913a7d5eb65b58a9
              a390d2ab1584cb77bb4dbdd505a9eaed
```

### Vector 2 — RPC body

```
identityKey = same as Vector 1
nonce       = ff ** 32
timestamp   = 0x66666666  (u32 little-endian: 66 66 66 66 00 00 00 00)
body        = utf8("{\"method\":\"getPublicKey\",\"params\":{},\"id\":\"req-1\"}")
              (50 bytes, no trailing newline)

digest      = d8bb125589659f49df927ca2da6510ac
              8fb4d6bffa957ed5519253db59b653d5
```

Both digests verified against W5 (`@noble/hashes` SHA256) and W6
(`std.crypto.hash.sha2.Sha256`) during the W7 reconciliation cycle.
