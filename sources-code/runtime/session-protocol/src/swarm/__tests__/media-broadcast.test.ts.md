---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/media-broadcast.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.074649+00:00
---

# runtime/session-protocol/src/swarm/__tests__/media-broadcast.test.ts

```ts
/**
 * Media broadcast — A4 segmenter + playlist + publish/consume over the swarm,
 * and the one-grant-gates-the-whole-broadcast convergence with #987's serve
 * gate.
 */
import { describe, expect, test } from 'bun:test';
import { sha256, bytesEqual, toHex } from '@semantos/protocol-types';
import {
  encodeAccessGrantCell,
  accessGrantCellHash,
  type AccessGrant,
} from '@semantos/protocol-types/bsv/access-grant';
import {
  segmentBuffer,
  MediaSegmenter,
  encodeBroadcastPlaylist,
  decodeBroadcastPlaylist,
  broadcastContentHash,
  publishBroadcast,
  consumeBroadcast,
  type BroadcastSegmentRef,
  type SegmentFetcher,
} from '../media-broadcast';
import { AccessGrantServePolicy, type AccessGrantVerifier } from '../access-grant-serve';
import type { SwarmRequest } from '../swarm-wire';

function mediaOf(n: number): Uint8Array {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 53 + 7) & 0xff;
  return b;
}
function concat(parts: Uint8Array[]): Uint8Array {
  const total = parts.reduce((a, p) => a + p.length, 0);
  const out = new Uint8Array(total);
  let off = 0;
  for (const p of parts) { out.set(p, off); off += p.length; }
  return out;
}

// ── segmentation ───────────────────────────────────────────────────────

describe('segmentBuffer (VOD)', () => {
  test('splits into target-sized segments, last shorter, reassembles exactly', () => {
    const media = mediaOf(2500);
    const segs = segmentBuffer(media, { targetBytes: 1000, durationMs: 2000 });
    expect(segs.map((s) => s.index)).toEqual([0, 1, 2]);
    expect(segs.map((s) => s.bytes.length)).toEqual([1000, 1000, 500]);
    expect(segs.every((s) => s.durationMs === 2000)).toBe(true);
    expect(bytesEqual(concat(segs.map((s) => s.bytes)), media)).toBe(true);
  });

  test('a buffer smaller than one segment yields a single segment', () => {
    const segs = segmentBuffer(mediaOf(300), { targetBytes: 1000 });
    expect(segs).toHaveLength(1);
    expect(segs[0]!.durationMs).toBeUndefined();
  });

  test('rejects a non-positive target', () => {
    expect(() => segmentBuffer(mediaOf(10), { targetBytes: 0 })).toThrow(/targetBytes/);
  });
});

describe('MediaSegmenter (live)', () => {
  test('emits at byte boundaries across arbitrary push sizes; flush yields the tail', () => {
    const media = mediaOf(2300);
    const seg = new MediaSegmenter({ targetBytes: 1000 });
    const emitted: Uint8Array[] = [];
    // Push the media in irregular steps; segments must still fall on 1000B.
    let off = 0;
    for (const size of [512, 1, 999, 788]) {
      const chunk = media.subarray(off, Math.min(off + size, media.length));
      off += chunk.length;
      for (const s of seg.push(chunk)) emitted.push(s.bytes);
    }
    for (const s of seg.flush()) emitted.push(s.bytes);
    expect(emitted.slice(0, -1).every((e) => e.length === 1000)).toBe(true);
    expect(emitted.at(-1)!.length).toBe(300); // 2300 → 1000,1000,300
    expect(bytesEqual(concat(emitted), media)).toBe(true);
  });

  test('indices are sequential across the whole stream', () => {
    const seg = new MediaSegmenter({ targetBytes: 100 });
    const idx: number[] = [];
    for (const s of seg.push(mediaOf(250))) idx.push(s.index);
    for (const s of seg.push(mediaOf(150))) idx.push(s.index);
    for (const s of seg.flush()) idx.push(s.index);
    expect(idx).toEqual([0, 1, 2, 3]); // 250+150=400 → 4 segments of 100
  });

  test('flush with an empty buffer emits nothing', () => {
    const seg = new MediaSegmenter({ targetBytes: 100 });
    seg.push(mediaOf(100)); // exactly one segment, buffer empty after
    expect(seg.flush()).toHaveLength(0);
  });
});

// ── playlist codec ─────────────────────────────────────────────────────

describe('broadcast playlist codec', () => {
  const refs: BroadcastSegmentRef[] = [
    { index: 0, infohash: new Uint8Array(32).fill(1), contentHash: new Uint8Array(32).fill(2), byteLength: 1000, durationMs: 2000 },
    { index: 1, infohash: new Uint8Array(32).fill(3), contentHash: new Uint8Array(32).fill(4), byteLength: 512 },
  ];

  test('round-trips a complete (VOD) playlist', () => {
    const pl = { broadcastId: 'talk/2026', segments: refs, complete: true };
    const back = decodeBroadcastPlaylist(encodeBroadcastPlaylist(pl));
    expect(back.broadcastId).toBe('talk/2026');
    expect(back.complete).toBe(true);
    expect(back.segments).toHaveLength(2);
    expect(bytesEqual(back.segments[0]!.infohash, refs[0]!.infohash)).toBe(true);
    expect(back.segments[0]!.durationMs).toBe(2000);
    expect(back.segments[1]!.durationMs).toBeUndefined();
  });

  test('round-trips a live (incomplete) playlist', () => {
    const back = decodeBroadcastPlaylist(encodeBroadcastPlaylist({ broadcastId: 'live', segments: refs.slice(0, 1), complete: false }));
    expect(back.complete).toBe(false);
    expect(back.segments).toHaveLength(1);
  });

  test('rejects a corrupt playlist (bad magic)', () => {
    expect(() => decodeBroadcastPlaylist(new Uint8Array(64))).toThrow(/bad magic/);
  });
});

describe('broadcastContentHash', () => {
  test('is stable for the same playlist and changes with segments or id', () => {
    const { playlist } = publishBroadcast(segmentBuffer(mediaOf(2048), { targetBytes: 1024 }), 'b/1');
    const h1 = broadcastContentHash(playlist);
    expect(bytesEqual(broadcastContentHash(playlist), h1)).toBe(true);
    const other = publishBroadcast(segmentBuffer(mediaOf(2048), { targetBytes: 1024 }), 'b/2');
    expect(bytesEqual(broadcastContentHash(other.playlist), h1)).toBe(false); // different id
  });
});

// ── publish / consume ──────────────────────────────────────────────────

/** Build an in-memory swarm: infohash → original segment bytes. */
function memFetcher(media: Uint8Array, refs: BroadcastSegmentRef[], targetBytes: number): SegmentFetcher {
  const byHash = new Map<string, Uint8Array>();
  const segs = segmentBuffer(media, { targetBytes });
  for (let i = 0; i < refs.length; i++) byHash.set(toHex(refs[i]!.infohash), segs[i]!.bytes);
  return async (ref) => byHash.get(toHex(ref.infohash))!;
}

describe('publish / consume', () => {
  test('publishBroadcast lists segments with correct infohash + content hash + length', () => {
    const media = mediaOf(3000);
    const segs = segmentBuffer(media, { targetBytes: 1024 });
    const { playlist, published } = publishBroadcast(segs, 'vod/x');
    expect(playlist.segments).toHaveLength(segs.length);
    expect(published).toHaveLength(segs.length);
    for (let i = 0; i < segs.length; i++) {
      expect(bytesEqual(playlist.segments[i]!.contentHash, sha256(segs[i]!.bytes))).toBe(true);
      expect(bytesEqual(playlist.segments[i]!.infohash, published[i]!.infohash)).toBe(true);
      expect(playlist.segments[i]!.byteLength).toBe(segs[i]!.bytes.length);
    }
  });

  test('consumeBroadcast fetches in order, verifies, and reassembles the original', async () => {
    const media = mediaOf(3500);
    const TARGET = 1024;
    const { playlist } = publishBroadcast(segmentBuffer(media, { targetBytes: TARGET }), 'vod/y');
    const order: number[] = [];
    const got = await consumeBroadcast(playlist, memFetcher(media, playlist.segments, TARGET), {
      onSegment: (_b, ref) => order.push(ref.index),
    });
    expect(bytesEqual(got, media)).toBe(true);
    expect(order).toEqual([0, 1, 2, 3]); // ceil(3500/1024)=4, streamed in order
  });

  test('consumeBroadcast reorders an out-of-order playlist by index', async () => {
    const media = mediaOf(2048);
    const TARGET = 1024;
    const { playlist } = publishBroadcast(segmentBuffer(media, { targetBytes: TARGET }), 'vod/z');
    const shuffled = { ...playlist, segments: [playlist.segments[1]!, playlist.segments[0]!] };
    const got = await consumeBroadcast(shuffled, memFetcher(media, playlist.segments, TARGET));
    expect(bytesEqual(got, media)).toBe(true);
  });

  test('consumeBroadcast throws on a content-hash mismatch (corrupt/wrong segment)', async () => {
    const media = mediaOf(2048);
    const { playlist } = publishBroadcast(segmentBuffer(media, { targetBytes: 1024 }), 'vod/bad');
    const evil: SegmentFetcher = async () => mediaOf(64); // wrong bytes
    await expect(consumeBroadcast(playlist, evil)).rejects.toThrow(/content-hash mismatch/);
  });
});

// ── the convergence: ONE broadcast grant gates ALL segments ────────────

describe('broadcast access — one grant gates the whole stream', () => {
  test('the per-segment serve gate authorizes a broadcast-level grant', async () => {
    const media = mediaOf(4096);
    const { playlist } = publishBroadcast(segmentBuffer(media, { targetBytes: 1024 }), 'paid/talk');
    const broadcastHash = broadcastContentHash(playlist);

    // A grant bound to the BROADCAST (not a single segment), expiry = sub window.
    const grant: AccessGrant = { granteePubkey: new Uint8Array(33).fill(2), contentHash: broadcastHash, expiry: 9_999_999_999n };
    const cell = encodeAccessGrantCell(grant);
    const grantHash = accessGrantCellHash(cell);

    const verifier: AccessGrantVerifier = { verify: async () => ({ ok: true, contentHash: broadcastHash }) };
    // Every segment seeder gates on the SAME broadcast hash.
    const policy = new AccessGrantServePolicy({ verifier, resolveGrant: () => ({ cell, grant }), contentHash: broadcastHash });

    const req = (g?: SwarmRequest['grant']): SwarmRequest => ({
      infohash: playlist.segments[2]!.infohash, // any segment
      cellIndex: 0,
      requesterBca: new Uint8Array(16),
      grant: g,
    });
    // The one broadcast grant authorizes serving any segment.
    expect(await policy.authorizeServe(req({ grantHash, signature: new Uint8Array(71).fill(0x30) }))).toBe(true);
    // No grant → refused (fail-closed), same as a non-subscriber.
    expect(await policy.authorizeServe(req(undefined))).toBe(false);
  });
});

```
