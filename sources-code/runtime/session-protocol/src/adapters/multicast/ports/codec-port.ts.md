---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/ports/codec-port.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.072042+00:00
---

# runtime/session-protocol/src/adapters/multicast/ports/codec-port.ts

```ts
/**
 * CodecPort — pluggable serialization seam for multicast envelope bodies.
 *
 * The legacy `MulticastAdapter` baked CBOR-via-`require('cbor-x')` (with a
 * JSON fallback) directly into the file. Per the prompt-38 acceptance
 * criterion ("Codec is a port; swapping it requires only constructor
 * wiring") we lift it behind a constructor-injected interface so:
 *
 *   - Tests can pass a deterministic in-memory codec.
 *   - Phase 34 can swap CBOR for a versioned schema codec without
 *     touching the orchestrator.
 *
 * Note: this is a constructor-port, not a global `port<T>('codec')`.
 * Each `MulticastAdapter` instance can carry a different codec, which
 * matters for tests that want bit-exact wire fixtures.
 *
 * Cross-references:
 *   docs/prd/refactor-monoliths/38-multicast-adapter-split.md
 *   ../multicast-adapter.ts — orchestrator that injects this port
 */
export interface CodecPort {
  /** Encode an arbitrary CBOR/JSON-friendly value to bytes. */
  encode(value: unknown): Uint8Array;
  /** Decode previously-encoded bytes back to a value. */
  decode(buf: Uint8Array): unknown;
}

/**
 * Default codec: prefers `cbor-x` if installed (production path matching
 * the hackathon wire format), falls back to JSON-via-TextEncoder for
 * environments without the optional dependency (browser, gate-test
 * sandboxes). Wire-compatible behaviour is preserved exactly as in the
 * legacy file.
 */
export function createDefaultCodec(): CodecPort {
  let encode: (obj: unknown) => Uint8Array;
  let decode: (buf: Uint8Array) => unknown;

  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const cbor = require("cbor-x");
    encode = (obj: unknown) => cbor.encode(obj);
    decode = (buf: Uint8Array) => cbor.decode(buf);
  } catch {
    encode = (obj: unknown) =>
      new TextEncoder().encode(JSON.stringify(obj));
    decode = (buf: Uint8Array) =>
      JSON.parse(new TextDecoder().decode(buf));
  }

  return { encode, decode };
}

/**
 * In-memory JSON codec — used by tests so wire bytes stay deterministic
 * regardless of whether `cbor-x` happens to be available in the local
 * `node_modules`. Identical to the JSON fallback branch of
 * `createDefaultCodec` but without the runtime feature-detection.
 */
export function createJsonCodec(): CodecPort {
  return {
    encode: (obj: unknown) =>
      new TextEncoder().encode(JSON.stringify(obj)),
    decode: (buf: Uint8Array) =>
      JSON.parse(new TextDecoder().decode(buf)),
  };
}

```
