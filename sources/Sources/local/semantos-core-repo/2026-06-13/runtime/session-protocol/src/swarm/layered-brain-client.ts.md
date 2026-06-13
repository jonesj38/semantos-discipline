---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/layered-brain-client.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.051884+00:00
---

# runtime/session-protocol/src/swarm/layered-brain-client.ts

```ts
/**
 * LayeredBrainClient — degrade-gracefully discovery for the transfer primitive.
 *
 * Implements SwarmBrainClient by composing a fallback chain:
 *   1. brain (inner)          — the live tracker: LAN / known peers, fast path
 *   2. overlay SLAP registry  — decentralized seeder registry (BRC-24)
 *   3. manifest resolver      — content-availability fallback (overlay / UHRP)
 *
 * `locate()` starts from the brain's answer, then AUGMENTS seeders from the
 * overlay registry and BACKFILLS the manifest cell from the resolver when the
 * brain doesn't know it. A resolved manifest is verified (its recomputed
 * infohash must equal the queried infohash) before it's trusted.
 *
 * `announce()` writes to the brain AND advertises to the overlay registry, so a
 * seeder becomes globally discoverable, not just LAN-visible.
 *
 * The overlay/UHRP legs are injected as narrow ports (the repo's BundleTxSender
 * / BundleLookupPoller idiom) so this composes cleanly and unit-tests without a
 * live overlay; real adapters here wrap the existing core/ clients.
 */

import {
  toHex,
  bytesEqual,
  computeInfohash,
  parseManifestCell,
  type LookupServiceClient,
  type DecodedLookupOutput,
} from '@semantos/protocol-types';
import type { SwarmBrainClient, LocateResult, SeederInfo } from './brain-client';

/** A decentralized registry of who is seeding a given infohash. */
export interface SeederRegistry {
  /** Seeders advertised for this infohash (hex). Empty when none/unknown. */
  lookup(infohashHex: string): Promise<SeederInfo[]>;
  /** Advertise that this node serves the infohash (optional — overlay submit). */
  advertise?(infohashHex: string, seeder: SeederInfo): Promise<void>;
}

/** Resolves the 1024-byte swarm.manifest cell for an infohash (overlay / UHRP). */
export interface ManifestResolver {
  resolve(infohashHex: string): Promise<Uint8Array | null>;
}

export interface LayeredBrainClientOptions {
  /** The brain leg — RpcSwarmBrainClient / FileBrainClient / FakeBrainClient. */
  inner: SwarmBrainClient;
  /** Decentralized seeder registry (overlay SLAP). Optional. */
  registry?: SeederRegistry;
  /** Manifest content-availability fallback (overlay / UHRP). Optional. */
  manifestResolver?: ManifestResolver;
  /** Diagnostic logger for leg failures (the chain swallows them). */
  log?: (msg: string) => void;
}

function seederId(s: SeederInfo): string {
  return s.address ?? (s.bca ? toHex(s.bca) : 'unknown');
}

/** Merge seeder lists, deduped by address/BCA; existing entries win. */
export function mergeSeeders(existing: SeederInfo[], extra: SeederInfo[]): SeederInfo[] {
  const out = new Map<string, SeederInfo>();
  for (const s of existing) out.set(seederId(s), s);
  for (const s of extra) if (!out.has(seederId(s))) out.set(seederId(s), s);
  return [...out.values()];
}

/** A resolved cell is only trusted as the manifest if its infohash matches. */
export function isManifestFor(cellBytes: Uint8Array, infohash: Uint8Array): boolean {
  if (cellBytes.length < 1024) return false;
  try {
    return bytesEqual(computeInfohash(parseManifestCell(cellBytes)), infohash);
  } catch {
    return false;
  }
}

export class LayeredBrainClient implements SwarmBrainClient {
  constructor(private readonly o: LayeredBrainClientOptions) {}

  publish(args: { infohash: Uint8Array; manifestCell: Uint8Array; semanticPath: string }): Promise<{ infohash: string }> {
    return this.o.inner.publish(args);
  }

  async locate(infohash: Uint8Array): Promise<LocateResult> {
    const hashHex = toHex(infohash);
    const base = await this.o.inner.locate(infohash);
    let manifestCell = base.manifestCell;
    let seeders = [...base.seeders];

    // 2. Augment seeders from the decentralized overlay registry.
    if (this.o.registry) {
      try {
        const extra = await this.o.registry.lookup(hashHex);
        seeders = mergeSeeders(seeders, extra);
      } catch (e) {
        this.o.log?.(`registry.lookup(${hashHex.slice(0, 16)}…) failed: ${e}`);
      }
    }

    // 3. Backfill the manifest cell from the content-availability resolver.
    if (!manifestCell && this.o.manifestResolver) {
      try {
        const bytes = await this.o.manifestResolver.resolve(hashHex);
        if (bytes && isManifestFor(bytes, infohash)) manifestCell = bytes;
      } catch (e) {
        this.o.log?.(`manifestResolver(${hashHex.slice(0, 16)}…) failed: ${e}`);
      }
    }

    return { manifestCell, seeders, anchorProof: base.anchorProof };
  }

  async announce(args: { infohash: Uint8Array; address?: string; bca?: Uint8Array; bitfield: Uint8Array }): Promise<void> {
    await this.o.inner.announce(args);
    if (this.o.registry?.advertise) {
      try {
        await this.o.registry.advertise(toHex(args.infohash), {
          address: args.address,
          bca: args.bca,
          bitfield: args.bitfield,
        });
      } catch (e) {
        this.o.log?.(`registry.advertise failed: ${e}`);
      }
    }
  }

  settle(args: Parameters<SwarmBrainClient['settle']>[0]): ReturnType<SwarmBrainClient['settle']> {
    return this.o.inner.settle(args);
  }
}

// ── In-memory registry (tests + local-mesh / file scenarios) ──

export class InMemorySeederRegistry implements SeederRegistry {
  private readonly byHash = new Map<string, SeederInfo[]>();

  async lookup(infohashHex: string): Promise<SeederInfo[]> {
    return (this.byHash.get(infohashHex) ?? []).map(s => ({ ...s }));
  }

  async advertise(infohashHex: string, seeder: SeederInfo): Promise<void> {
    const cur = this.byHash.get(infohashHex) ?? [];
    this.byHash.set(infohashHex, mergeSeeders(cur, [seeder]));
  }
}

// ── Real overlay adapter (BRC-24 SLAP) ──

/** The slice of LookupServiceClient this adapter uses (real or faked). */
export type LookupLike = Pick<LookupServiceClient, 'queryByContent' | 'decodeLookupOutputs'>;

/**
 * Manifest resolver over BRC-24 SLAP: query overlay outputs indexed by the
 * infohash (contentHash), decode each PushDrop cell, and return the first that
 * is a valid manifest. Verification (infohash match) happens in the caller via
 * isManifestFor, so a malformed/forged output is rejected.
 */
export function overlayManifestResolver(client: LookupLike): ManifestResolver {
  return {
    async resolve(infohashHex: string): Promise<Uint8Array | null> {
      const answer = await client.queryByContent(infohashHex);
      const outs: DecodedLookupOutput[] = client.decodeLookupOutputs(answer);
      for (const out of outs) {
        if (out.cellBytes && out.cellBytes.length >= 1024) return out.cellBytes;
      }
      return null;
    },
  };
}

```
