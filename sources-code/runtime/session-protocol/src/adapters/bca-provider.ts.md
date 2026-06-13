---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/bca-provider.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.045270+00:00
---

# runtime/session-protocol/src/adapters/bca-provider.ts

```ts
/**
 * BCA provider contract.
 *
 * A `BCAProvider` composes a `Signer` with the ability to derive the node's
 * IPv6 BCA from its public key (via `core/cell-engine/src/bca.zig`).
 *
 * Implementations (`PlexusCertBCAProvider`, `DeterministicBCAProvider`) land
 * when this file is populated in the next TDD step. Exported here as the
 * type seam so `types.ts` / `index.ts` can reference it.
 */

import type { Signer } from "../signer.js";
import type { Identity } from "../types.js";
import { StubSigner, deriveBCABytes, bcaBytesToIPv6 } from "../signer.js";

export interface BCAProvider extends Signer {
  /**
   * Compute and return this provider's BCA.
   *
   * Implementations derive the IPv6 address from the underlying pubkey.
   * Production: `PlexusCertBCAProvider` using the Semantos BCA algorithm
   * (bit-identical to `core/cell-engine/src/bca.zig`). Tests:
   * `DeterministicBCAProvider` using the hackathon `2602:f9f8::<index>`
   * stub shape.
   */
  deriveBCA(): Promise<string>;
}

/**
 * Production-shaped BCA provider.
 *
 * Derives the IPv6 BCA from a Plexus-cert-carried pubkey using the Semantos
 * BCA algorithm. The bytes it produces are bit-identical to what
 * `core/cell-engine/src/bca.zig::deriveBCA` produces — the `bca_basic.json`
 * golden vectors are the shared source of truth for both implementations.
 *
 * Why pure TS rather than calling the WASM:
 *   - `core/cell-engine/bindings/index.ts` is a stub loader; there's no
 *     ready-made `loadCellEngine()` → `{ deriveBCA }` surface at the runtime
 *     layer. The WASM path goes through ad-hoc `WebAssembly.instantiate`
 *     with host-function wiring in `tests-bun/bca_compat.test.ts`.
 *   - The algorithm is tiny (SHA-256 → bit ops → slice) and the gate test
 *     cross-verifies against `bca_basic.json`, the same vectors the WASM
 *     is tested against — so byte-equivalence is enforced even without a
 *     runtime WASM dependency.
 *   - When/if the cell-engine ships a clean `loadCellEngine()` surface,
 *     callers can swap the internal deriver by passing the optional
 *     `deriver` config; the default stays TS-native.
 *
 * The algorithm (simplified Semantos BCA, per bca.zig):
 *   data = modifier(16) || subnetPrefix(8) || collisionCount=0(1) || pubkey(33)
 *   hash = SHA-256(data)
 *   iid  = hash[0..8]   — interface identifier
 *   iid[0] &= ~0x03     — clear u-bit and g-bit
 *   iid[0] = (iid[0] & 0x1f) | ((sec & 0x07) << 5)   — encode sec in bits 5-7
 *   address = subnetPrefix || iid  → 16 bytes
 */
export interface PlexusCertBCAProviderConfig {
  signer: Signer;
  /** 8-byte subnet prefix. Defaults to 2001:db8:0:1 (the doc-range prefix). */
  subnetPrefix?: Uint8Array;
  /** 16-byte modifier. Required for non-default deployments. */
  modifier?: Uint8Array;
  /** Security level 0-7. Defaults to 0. */
  sec?: number;
  /**
   * Optional deriver override — swap in a WASM-backed implementation
   * when that path is available. Return the 16 raw address bytes.
   */
  deriver?: (
    pubkey: Uint8Array,
    prefix: Uint8Array,
    modifier: Uint8Array,
    sec: number,
  ) => Promise<Uint8Array> | Uint8Array;
}

const DEFAULT_PREFIX = new Uint8Array([
  0x20, 0x01, 0x0d, 0xb8, 0x00, 0x00, 0x00, 0x01,
]);
const DEFAULT_MODIFIER = new Uint8Array([
  0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
  0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff,
]);

export class PlexusCertBCAProvider implements BCAProvider {
  private readonly signer: Signer;
  private readonly subnetPrefix: Uint8Array;
  private readonly modifier: Uint8Array;
  private readonly sec: number;
  private readonly deriver: (
    pubkey: Uint8Array,
    prefix: Uint8Array,
    modifier: Uint8Array,
    sec: number,
  ) => Promise<Uint8Array> | Uint8Array;

  private cachedBCA?: string;

  constructor(config: PlexusCertBCAProviderConfig) {
    this.signer = config.signer;
    this.subnetPrefix = config.subnetPrefix ?? DEFAULT_PREFIX;
    this.modifier = config.modifier ?? DEFAULT_MODIFIER;
    this.sec = config.sec ?? 0;
    this.deriver = config.deriver ?? deriveBCABytes;

    if (this.subnetPrefix.length !== 8) {
      throw new Error(
        `PlexusCertBCAProvider: subnetPrefix must be 8 bytes, got ${this.subnetPrefix.length}`,
      );
    }
    if (this.modifier.length !== 16) {
      throw new Error(
        `PlexusCertBCAProvider: modifier must be 16 bytes, got ${this.modifier.length}`,
      );
    }
    if (this.sec < 0 || this.sec > 7) {
      throw new Error(
        `PlexusCertBCAProvider: sec must be 0-7, got ${this.sec}`,
      );
    }
  }

  async identity(): Promise<Identity> {
    const base = await this.signer.identity();
    return { ...base, bca: await this.deriveBCA() };
  }

  sign(bytes: Uint8Array): Promise<Uint8Array> {
    return this.signer.sign(bytes);
  }

  /** Return the 16 raw BCA bytes (useful for byte-level tests). */
  async deriveBCABytes(): Promise<Uint8Array> {
    const id = await this.signer.identity();
    const out = await this.deriver(
      id.pubkey,
      this.subnetPrefix,
      this.modifier,
      this.sec,
    );
    return out instanceof Uint8Array ? out : new Uint8Array(out);
  }

  async deriveBCA(): Promise<string> {
    if (this.cachedBCA) return this.cachedBCA;
    const bytes = await this.deriveBCABytes();
    this.cachedBCA = bcaBytesToIPv6(bytes);
    return this.cachedBCA;
  }
}

/**
 * Deterministic test-only BCA provider.
 *
 * Reproduces the hackathon `2602:f9f8::<index>` stub shape so docker-swarm
 * tests keep working. Internally uses a `StubSigner` keyed from a short
 * numeric index. Not suitable for production — `PlexusCertBCAProvider`
 * is the production implementation.
 */
export class DeterministicBCAProvider implements BCAProvider {
  private readonly signer: StubSigner;
  private readonly index: number;

  constructor(index: number) {
    this.index = index & 0xffff;
    // Derive a 32-byte seed from the index — spread over the whole key so
    // the resulting pubkey's last bytes (used by deriveNodeIdShort) are
    // predictable per-index.
    const seedHex = this.index.toString(16).padStart(4, "0").padEnd(64, "0");
    this.signer = new StubSigner(seedHex);
  }

  async identity(): Promise<Identity> {
    const base = await this.signer.identity();
    return { ...base, bca: await this.deriveBCA() };
  }

  sign(bytes: Uint8Array): Promise<Uint8Array> {
    return this.signer.sign(bytes);
  }

  async deriveBCA(): Promise<string> {
    return `2602:f9f8::${this.index.toString(16).padStart(4, "0")}`;
  }
}

```
