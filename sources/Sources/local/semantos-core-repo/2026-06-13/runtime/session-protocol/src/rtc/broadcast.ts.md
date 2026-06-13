---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/broadcast.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.043735+00:00
---

# runtime/session-protocol/src/rtc/broadcast.ts

```ts
/**
 * rtc.broadcast — the shell-native broadcast/VOD surface (RTC matrix A4 axis H,
 * S7). The latency-tolerant one-to-many regime: a talk, a livestream, a
 * recording, where 1–2s delay is fine. It does NOT ride WebRTC/SRTP — it rides
 * the existing paid swarm as segmented files behind an ordered playlist, gated
 * by an engine-checked `access.grant` (one broadcast-level grant admits the
 * whole stream).
 *
 * This is a thin re-export: the media-broadcast primitive lives with the swarm
 * data plane (`../swarm/media-broadcast`), and the `rtc` substrate surfaces it
 * so cartridges bind ONE import (`@semantos/session-protocol/rtc`) for every
 * calling/streaming regime — interactive (S1–S5) and broadcast (A4) alike.
 * Interactive calls and broadcasts share no transport code (SRTP vs swarm
 * chunks) but share the one shell surface, exactly as the roadmap §4 contract
 * specifies. Importing the swarm sibling is allowed by the rtc one-way-dep gate
 * (rtc → runtime sibling is fine; only rtc → cartridge is forbidden).
 *
 * Cross-reference: docs/prd/RTC-ROADMAP.md §4–§5 (A4), docs/canon/rtc-matrix.yml
 * row A4, ../swarm/media-broadcast.ts, ../swarm/access-grant-serve.ts.
 */

export {
  segmentBuffer,
  MediaSegmenter,
  encodeBroadcastPlaylist,
  decodeBroadcastPlaylist,
  broadcastContentHash,
  publishBroadcast,
  consumeBroadcast,
  type MediaSegment,
  type SegmenterOptions,
  type BroadcastSegmentRef,
  type BroadcastPlaylist,
  type BroadcastPublishResult,
  type SegmentFetcher,
  type ConsumeOptions,
} from '../swarm/media-broadcast';

// A4 axes E/G — run a broadcast over real SwarmSessions (gated + metered).
export {
  seedBroadcast,
  swarmBroadcastFetcher,
  consumeSwarmBroadcast,
  type BroadcastSessionFactory,
} from '../swarm/swarm-broadcast';

```
