---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/media-broadcast.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.058365+00:00
---

# runtime/session-protocol/src/swarm/media-broadcast.ts

```ts
/**
 * Media broadcast — segment a media source into swarm-published segments + an
 * ordered playlist, so a stream rides the paid swarm as latency-tolerant
 * broadcast/VOD (RTC matrix A4 axes D + E + H).
 *
 * This is the A4 media leg: the swarm already distributes files (chunk →
 * manifest/infohash → fan-out → metered delivery) and #987 gates serving on an
 * engine-checked `access.grant`. What was missing is the segmenter + the
 * playlist that ties many segments into one ordered broadcast — the semantos
 * analogue of an HLS `.m3u8` / DASH MPD, where each segment URI is a swarm
 * infohash instead of an HTTP URL.
 *
 *   segment(media)         → [seg0, seg1, …]        (byte-size segmentation)
 *   publishBroadcast(segs) → playlist + PublishedFile[]   (each segment a swarm file)
 *   consumeBroadcast(pl)   → fetch in order, verify, reassemble (+ live onSegment)
 *
 * THE GATING MODEL (the A4 ↔ DAM convergence): a broadcast is admitted by ONE
 * broadcast-level `access.grant`, NOT one grant per segment. The grant binds to
 * `broadcastContentHash(playlist)` (expiry = the subscription window); every
 * segment seeder gates on the same hash via `AccessGrantServePolicy`, and the
 * subscriber attaches the one broadcast grant proof to every segment request.
 * Admission is per-subscription, evaluated by the 2-PDA at subscribe time — not
 * per media frame (RTC §7: media never rides inside cells; the cell rail
 * carries the authz decision + metering receipts).
 *
 * Codec-agnostic by design: segmentation is by byte size (an honest transport
 * primitive); a codec-aware caller passes `durationMs` per segment for the
 * playlist's EXTINF analogue. Real keyframe-aligned segmentation is the
 * encoder's job, upstream of this.
 *
 * Cross-reference: docs/canon/rtc-matrix.yml row A4, swarm-file.ts (publishFile),
 * access-grant-serve.ts (the per-segment serve gate), paid-swarm metering.
 */

import { publishFile, sha256, bytesEqual, type PublishedFile } from '@semantos/protocol-types';

// ── segmentation ───────────────────────────────────────────────────────

export interface MediaSegment {
  /** 0-based position in the broadcast. */
  index: number;
  /** The segment's raw bytes. */
  bytes: Uint8Array;
  /** Presentation duration in ms (HLS EXTINF analogue), if the caller knows it. */
  durationMs?: number;
}

export interface SegmenterOptions {
  /** Emit a segment once the buffer reaches/exceeds this many bytes. */
  targetBytes: number;
  /** Fixed per-segment duration in ms, if known (else omitted from the playlist). */
  durationMs?: number;
}

/** Split a complete (VOD) media buffer into fixed-size segments. */
export function segmentBuffer(media: Uint8Array, opts: SegmenterOptions): MediaSegment[] {
  if (opts.targetBytes <= 0) throw new Error('segmentBuffer: targetBytes must be > 0');
  const segs: MediaSegment[] = [];
  for (let off = 0, index = 0; off < media.length; off += opts.targetBytes, index++) {
    const bytes = media.subarray(off, Math.min(off + opts.targetBytes, media.length));
    segs.push({ index, bytes, ...(opts.durationMs !== undefined ? { durationMs: opts.durationMs } : {}) });
  }
  return segs;
}

/**
 * Streaming segmenter for LIVE broadcasts: push encoded media chunks as they
 * arrive; a segment is emitted each time the accumulated buffer reaches
 * `targetBytes`. `flush()` emits the trailing partial segment (end of stream).
 * Segment indices are sequential across the whole broadcast.
 */
export class MediaSegmenter {
  private buf: Uint8Array = new Uint8Array(0);
  private nextIndex = 0;
  constructor(private readonly opts: SegmenterOptions) {
    if (opts.targetBytes <= 0) throw new Error('MediaSegmenter: targetBytes must be > 0');
  }

  /** Append media bytes; return any segments that completed as a result. */
  push(chunk: Uint8Array): MediaSegment[] {
    const merged = new Uint8Array(this.buf.length + chunk.length);
    merged.set(this.buf, 0);
    merged.set(chunk, this.buf.length);
    this.buf = merged;
    const out: MediaSegment[] = [];
    while (this.buf.length >= this.opts.targetBytes) {
      out.push(this.emit(this.buf.subarray(0, this.opts.targetBytes)));
      this.buf = this.buf.slice(this.opts.targetBytes);
    }
    return out;
  }

  /** Emit the trailing partial segment (if any) at end of stream. */
  flush(): MediaSegment[] {
    if (this.buf.length === 0) return [];
    const seg = this.emit(this.buf);
    this.buf = new Uint8Array(0);
    return [seg];
  }

  private emit(bytes: Uint8Array): MediaSegment {
    return {
      index: this.nextIndex++,
      bytes: bytes.slice(),
      ...(this.opts.durationMs !== undefined ? { durationMs: this.opts.durationMs } : {}),
    };
  }
}

// ── playlist (the .m3u8 / MPD analogue) ────────────────────────────────

export interface BroadcastSegmentRef {
  index: number;
  /** The segment's swarm infohash (the "URI"). */
  infohash: Uint8Array;
  /** sha256 of the segment bytes (== its manifest contentHash). */
  contentHash: Uint8Array;
  byteLength: number;
  durationMs?: number;
}

export interface BroadcastPlaylist {
  /** Broadcast id / semantic path root (e.g. "talk/2026-06-12"). */
  broadcastId: string;
  /** Segments in presentation order. */
  segments: BroadcastSegmentRef[];
  /** false = live (more segments coming); true = VOD / ended. */
  complete: boolean;
}

const PL_MAGIC = 0x42434130; // "BCA0"

/** Encode a playlist to a compact, self-describing binary form (distributable). */
export function encodeBroadcastPlaylist(pl: BroadcastPlaylist): Uint8Array {
  const id = new TextEncoder().encode(pl.broadcastId);
  if (id.length > 0xffff) throw new Error('encodeBroadcastPlaylist: broadcastId too long');
  const size = 4 + 1 + 2 + id.length + 4 + pl.segments.length * (4 + 32 + 32 + 4 + 4);
  const buf = new Uint8Array(size);
  const dv = new DataView(buf.buffer);
  let off = 0;
  dv.setUint32(off, PL_MAGIC, true); off += 4;
  buf[off++] = pl.complete ? 1 : 0;
  dv.setUint16(off, id.length, true); off += 2;
  buf.set(id, off); off += id.length;
  dv.setUint32(off, pl.segments.length, true); off += 4;
  for (const s of pl.segments) {
    if (s.infohash.length !== 32 || s.contentHash.length !== 32) {
      throw new Error('encodeBroadcastPlaylist: infohash/contentHash must be 32 bytes');
    }
    dv.setUint32(off, s.index >>> 0, true); off += 4;
    buf.set(s.infohash, off); off += 32;
    buf.set(s.contentHash, off); off += 32;
    dv.setUint32(off, s.byteLength >>> 0, true); off += 4;
    dv.setUint32(off, s.durationMs ?? 0, true); off += 4;
  }
  return buf;
}

export function decodeBroadcastPlaylist(buf: Uint8Array): BroadcastPlaylist {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  let off = 0;
  if (dv.getUint32(off, true) !== PL_MAGIC) throw new Error('decodeBroadcastPlaylist: bad magic');
  off += 4;
  const complete = buf[off++] === 1;
  const idLen = dv.getUint16(off, true); off += 2;
  const broadcastId = new TextDecoder().decode(buf.subarray(off, off + idLen)); off += idLen;
  const count = dv.getUint32(off, true); off += 4;
  const segments: BroadcastSegmentRef[] = [];
  for (let i = 0; i < count; i++) {
    const index = dv.getUint32(off, true); off += 4;
    const infohash = buf.slice(off, off + 32); off += 32;
    const contentHash = buf.slice(off, off + 32); off += 32;
    const byteLength = dv.getUint32(off, true); off += 4;
    const durationMs = dv.getUint32(off, true); off += 4;
    segments.push({ index, infohash, contentHash, byteLength, ...(durationMs ? { durationMs } : {}) });
  }
  return { broadcastId, segments, complete };
}

/**
 * The stable content-address a broadcast-level `access.grant` binds to. A
 * subscriber's grant authorizes the WHOLE broadcast: every segment seeder
 * configures its `AccessGrantServePolicy` with this hash, so one grant gates
 * all segments. Computed over the ordered (infohash, contentHash) of every
 * segment + the broadcast id — independent of segment payloads, so a
 * still-growing live playlist with the same prefix yields a stable value once
 * `complete`.
 */
export function broadcastContentHash(pl: BroadcastPlaylist): Uint8Array {
  const parts: number[] = [...new TextEncoder().encode(pl.broadcastId)];
  for (const s of pl.segments) {
    parts.push(...s.infohash, ...s.contentHash);
  }
  return sha256(new Uint8Array(parts));
}

// ── publish / consume over the swarm ───────────────────────────────────

export interface BroadcastPublishResult {
  playlist: BroadcastPlaylist;
  /** Each segment's PublishedFile — seed these on a SwarmSession to serve them. */
  published: PublishedFile[];
}

/**
 * Publish a broadcast: each segment becomes a swarm file; the playlist lists
 * them in order. The caller seeds each `published[i]` on a SwarmSession (gated
 * by an `AccessGrantServePolicy` over `broadcastContentHash(playlist)` for the
 * paid/private case).
 */
export function publishBroadcast(
  segments: MediaSegment[],
  broadcastId: string,
  opts: { complete?: boolean } = {},
): BroadcastPublishResult {
  const published: PublishedFile[] = [];
  const refs: BroadcastSegmentRef[] = [];
  for (const seg of segments) {
    const pub = publishFile(seg.bytes, `${broadcastId}/seg/${seg.index}`);
    published.push(pub);
    refs.push({
      index: seg.index,
      infohash: pub.infohash,
      contentHash: pub.manifest.contentHash,
      byteLength: seg.bytes.length,
      ...(seg.durationMs !== undefined ? { durationMs: seg.durationMs } : {}),
    });
  }
  return { playlist: { broadcastId, segments: refs, complete: opts.complete ?? true }, published };
}

/** Fetch a segment's bytes by its ref (wire to `SwarmSession.download`). */
export type SegmentFetcher = (ref: BroadcastSegmentRef) => Promise<Uint8Array>;

export interface ConsumeOptions {
  /** Called as each verified segment arrives, in order (live playback hook). */
  onSegment?: (bytes: Uint8Array, ref: BroadcastSegmentRef) => void;
}

/**
 * Consume a broadcast: fetch every segment in order, verify each against its
 * `contentHash`, stream them to `onSegment`, and return the reassembled media.
 * Throws on a content-hash mismatch (a seeder served the wrong/corrupt bytes).
 */
export async function consumeBroadcast(
  playlist: BroadcastPlaylist,
  fetch: SegmentFetcher,
  opts: ConsumeOptions = {},
): Promise<Uint8Array> {
  const ordered = [...playlist.segments].sort((a, b) => a.index - b.index);
  const parts: Uint8Array[] = [];
  let total = 0;
  for (const ref of ordered) {
    const bytes = await fetch(ref);
    if (!bytesEqual(sha256(bytes), ref.contentHash)) {
      throw new Error(`consumeBroadcast: segment ${ref.index} content-hash mismatch`);
    }
    opts.onSegment?.(bytes, ref);
    parts.push(bytes);
    total += bytes.length;
  }
  const out = new Uint8Array(total);
  let off = 0;
  for (const p of parts) { out.set(p, off); off += p.length; }
  return out;
}

```
