---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/swarm-broadcast.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.049915+00:00
---

# runtime/session-protocol/src/swarm/swarm-broadcast.ts

```ts
/**
 * swarm-broadcast — run a segmented broadcast over real SwarmSessions
 * (RTC matrix A4 axes E + G: one-to-many distribution + per-chunk metering).
 *
 * `media-broadcast.ts` produces the segments + playlist and a transport-agnostic
 * `consumeBroadcast(playlist, fetcher)`. This module supplies the swarm fetcher
 * + a seeding helper, so a broadcast rides the actual paid swarm: each segment
 * is its own swarm file (a SwarmSession is single-file), seeded + served
 * independently, and gated/metered by the SAME per-segment policies.
 *
 * THE PAID-PRIVATE-BROADCAST COMPOSITION (the capstone of A4):
 *   serve  = andServePolicies(AccessGrantServePolicy(broadcastHash), PaidSeeder)
 *   pay    = andPayPolicies(makeGrantPayPolicy(broadcastGrant), makePayPolicy(sats))
 * One broadcast-level access.grant admits the subscriber to EVERY segment
 * (authorization, engine-checked — #987), and the swarm's existing per-cell
 * metering charges for delivery (#977 paid loop). Authorization and payment are
 * orthogonal and compose via the combinators — a broadcast can be gated, paid,
 * both, or neither.
 *
 * The caller supplies a `BroadcastSessionFactory` so this stays transport-
 * agnostic (UDP multicast, WSS, loopback in tests) and so it can wire the
 * grant + pay policies per session.
 *
 * Cross-reference: media-broadcast.ts (segments + playlist), access-grant-serve.ts
 * (the grant gate + combinators), paid-seeder.ts (the metering ServePolicy).
 */

import type { PublishedFile } from '@semantos/protocol-types';
import { SwarmSession } from './swarm-session';
import {
  consumeBroadcast,
  type BroadcastPlaylist,
  type ConsumeOptions,
  type SegmentFetcher,
} from './media-broadcast';

/**
 * Make a SwarmSession for one segment. `role` distinguishes the seeder leg
 * (serve policy) from the subscriber leg (pay policy); `segmentIndex` lets the
 * caller pick a distinct transport address per segment.
 */
export type BroadcastSessionFactory = (role: 'seed' | 'fetch', segmentIndex: number) => SwarmSession;

/**
 * Seed every segment of a published broadcast, each on its own SwarmSession.
 * Returns the seeder sessions so the caller can `flushReceipts()` (metered
 * settlement) and `stop()` them.
 */
export async function seedBroadcast(
  published: PublishedFile[],
  makeSession: BroadcastSessionFactory,
): Promise<SwarmSession[]> {
  const sessions: SwarmSession[] = [];
  for (let i = 0; i < published.length; i++) {
    const s = makeSession('seed', i);
    await s.seed(published[i]!);
    sessions.push(s);
  }
  return sessions;
}

/**
 * A `SegmentFetcher` that downloads each segment over a fresh SwarmSession (the
 * factory wires the grant + pay policies), then stops it. consumeBroadcast
 * fetches in order, so at most one fetch session is live at a time.
 */
export function swarmBroadcastFetcher(makeSession: BroadcastSessionFactory): SegmentFetcher {
  return async (ref) => {
    const s = makeSession('fetch', ref.index);
    try {
      return await s.download(ref.infohash);
    } finally {
      await s.stop();
    }
  };
}

/**
 * Convenience: consume a whole broadcast over the swarm — fetch every segment in
 * order (verifying each content hash), stream via `onSegment`, and return the
 * reassembled media. Equivalent to
 * `consumeBroadcast(playlist, swarmBroadcastFetcher(makeSession), opts)`.
 */
export function consumeSwarmBroadcast(
  playlist: BroadcastPlaylist,
  makeSession: BroadcastSessionFactory,
  opts: ConsumeOptions = {},
): Promise<Uint8Array> {
  return consumeBroadcast(playlist, swarmBroadcastFetcher(makeSession), opts);
}

```
