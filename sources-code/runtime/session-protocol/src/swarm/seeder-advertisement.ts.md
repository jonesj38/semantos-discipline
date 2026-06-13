---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/seeder-advertisement.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.056692+00:00
---

# runtime/session-protocol/src/swarm/seeder-advertisement.ts

```ts
/**
 * Seeder advertisement — the payload a seeder publishes to the overlay so it
 * becomes globally discoverable (BRC-24 SLAP, indexed by infohash). On publish/
 * announce, LayeredBrainClient pushes one of these through an overlay submit
 * port; on locate, it pulls them back via an overlay query port. The production
 * adapter wraps TopicManagerClient.submit (a wallet-signed PushDrop carrying the
 * infohash as an indexable field) and LookupServiceClient.queryByContent.
 *
 * Wire format (little-endian, compact):
 *   [0]      version (u8, =1)
 *   [1..33]  infohash (32 bytes)
 *   [33..49] bca (16 bytes; all-zero = none)
 *   [49..57] expiresAtMs (u64 LE; 0 = no expiry)
 *   [57..59] addressLen (u16 LE)
 *   [59..]   address (utf8)
 *   [..2]    bitfieldLen (u16 LE)
 *   [..]     bitfield
 */

import { toHex, fromHex, bytesEqual } from '@semantos/protocol-types';
import type { SeederInfo } from './brain-client';
import type { SeederRegistry } from './layered-brain-client';
import { mergeSeeders } from './layered-brain-client';

export const SEEDER_AD_VERSION = 1;

export interface SeederAdvertisement {
  infohash: Uint8Array;
  address?: string;
  bca?: Uint8Array;
  bitfield: Uint8Array;
  /** Epoch ms; 0 = no expiry. */
  expiresAtMs: number;
}

const ZERO_BCA = new Uint8Array(16);

export function encodeSeederAd(ad: SeederAdvertisement): Uint8Array {
  const addr = new TextEncoder().encode(ad.address ?? '');
  const bca = ad.bca && ad.bca.length === 16 ? ad.bca : ZERO_BCA;
  const total = 1 + 32 + 16 + 8 + 2 + addr.length + 2 + ad.bitfield.length;
  const buf = new Uint8Array(total);
  const dv = new DataView(buf.buffer);
  let o = 0;
  buf[o] = SEEDER_AD_VERSION; o += 1;
  buf.set(ad.infohash.subarray(0, 32), o); o += 32;
  buf.set(bca, o); o += 16;
  dv.setBigUint64(o, BigInt(ad.expiresAtMs >>> 0 ? ad.expiresAtMs : 0), true); o += 8;
  dv.setUint16(o, addr.length, true); o += 2;
  buf.set(addr, o); o += addr.length;
  dv.setUint16(o, ad.bitfield.length, true); o += 2;
  buf.set(ad.bitfield, o); o += ad.bitfield.length;
  return buf;
}

export function decodeSeederAd(buf: Uint8Array): SeederAdvertisement | null {
  try {
    if (buf.length < 1 + 32 + 16 + 8 + 2 || buf[0] !== SEEDER_AD_VERSION) return null;
    const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
    let o = 1;
    const infohash = buf.slice(o, o + 32); o += 32;
    const bcaRaw = buf.slice(o, o + 16); o += 16;
    const expiresAtMs = Number(dv.getBigUint64(o, true)); o += 8;
    const addrLen = dv.getUint16(o, true); o += 2;
    if (o + addrLen + 2 > buf.length) return null;
    const address = addrLen ? new TextDecoder().decode(buf.subarray(o, o + addrLen)) : undefined;
    o += addrLen;
    const bfLen = dv.getUint16(o, true); o += 2;
    if (o + bfLen > buf.length) return null;
    const bitfield = buf.slice(o, o + bfLen);
    const bca = bytesEqual(bcaRaw, ZERO_BCA) ? undefined : bcaRaw;
    return { infohash, address, bca, bitfield, expiresAtMs };
  } catch {
    return null;
  }
}

/** Submit a seeder advertisement to the overlay (wraps a wallet + TopicManagerClient). */
export type OverlaySubmit = (adBytes: Uint8Array, infohashHex: string) => Promise<void>;
/** Pull raw advertisement payloads for an infohash (wraps LookupServiceClient). */
export type OverlayQuery = (infohashHex: string) => Promise<Uint8Array[]>;

export interface OverlaySeederRegistryIo {
  submit?: OverlaySubmit;
  query?: OverlayQuery;
  /** Clock for expiry checks. Default Date.now. */
  now?: () => number;
  /** TTL applied to advertisements this node publishes. Default 1h. */
  ttlMs?: number;
}

/**
 * A SeederRegistry backed by an overlay submit/query pair. Injected I/O keeps it
 * testable offline; the daemon supplies the live adapters (TopicManagerClient /
 * LookupServiceClient) at deploy time.
 */
export function overlaySeederRegistry(io: OverlaySeederRegistryIo): SeederRegistry {
  const now = io.now ?? (() => Date.now());
  const ttlMs = io.ttlMs ?? 60 * 60_000;

  return {
    async lookup(infohashHex: string): Promise<SeederInfo[]> {
      if (!io.query) return [];
      const raw = await io.query(infohashHex);
      const t = now();
      let seeders: SeederInfo[] = [];
      for (const bytes of raw) {
        const ad = decodeSeederAd(bytes);
        if (!ad) continue;
        if (toHex(ad.infohash) !== infohashHex) continue; // bind to the queried hash
        if (ad.expiresAtMs !== 0 && ad.expiresAtMs <= t) continue; // drop expired
        seeders = mergeSeeders(seeders, [{ address: ad.address, bca: ad.bca, bitfield: ad.bitfield }]);
      }
      return seeders;
    },

    async advertise(infohashHex: string, seeder: SeederInfo): Promise<void> {
      if (!io.submit) return;
      const ad = encodeSeederAd({
        infohash: fromHex(infohashHex),
        address: seeder.address,
        bca: seeder.bca,
        bitfield: seeder.bitfield ?? new Uint8Array(0),
        expiresAtMs: now() + ttlMs,
      });
      await io.submit(ad, infohashHex);
    },
  };
}

```
