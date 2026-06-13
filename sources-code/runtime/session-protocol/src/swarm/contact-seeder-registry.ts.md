---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/contact-seeder-registry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.053853+00:00
---

# runtime/session-protocol/src/swarm/contact-seeder-registry.ts

```ts
/**
 * contact-seeder-registry — identity-gated discovery for the transfer primitive.
 *
 * A SeederRegistry (the Phase-B port LayeredBrainClient consumes) backed by the
 * ContactBook + the BCA addressing above. Instead of "anyone in the room", a
 * seeder only surfaces if it is (a) a known contact and (b) one you hold a
 * signed edge with — `decidePresenceSubscription`'s rule, applied to discovery.
 * Each resolved seeder is addressed by its identity-derived BCA, so the fetch
 * dials the contact at the same address the XMPP presence layer uses.
 *
 * Who-is-seeding-what comes from a narrow `SeedPresence` port (real impl wraps
 * the XMPP pubsub/presence; InMemorySeedPresence for tests) — the same
 * port-over-stub idiom as the overlay/UHRP legs.
 */

import type { SeederInfo } from './brain-client';
import type { SeederRegistry } from './layered-brain-client';
import { mergeSeeders } from './layered-brain-client';
import { type BcaNetwork, type ContactRef, contactSeederInfo } from './contact-bca';

/** Structural slice of a ContactBook needed for identity-gated discovery. */
export interface ContactRoster {
  getContact(certId: string): ContactRef | null;
  listContacts(): ContactRef[];
  /** True iff an active (non-revoked) signed edge of `edgeType` exists. */
  isConnected(certId: string, edgeType?: string): boolean;
}

/** Presence source: which certIds are currently seeding a given infohash. */
export interface SeedPresence {
  /** This node announces it seeds `infohashHex`. */
  announce(infohashHex: string): Promise<void>;
  /** CertIds currently advertising they seed `infohashHex`. */
  seedersFor(infohashHex: string): Promise<string[]>;
}

export interface ContactSeederRegistryOptions {
  roster: ContactRoster;
  network: BcaNetwork;
  presence: SeedPresence;
  /** Require a signed edge to surface a seeder. Default true (identity-gated). */
  requireEdge?: boolean;
  /** Edge type gating discovery. Default 'DATA_ACCESS'. */
  edgeType?: string;
}

/** A SeederRegistry over contacts: identity-gated + BCA-addressed. */
export function contactSeederRegistry(o: ContactSeederRegistryOptions): SeederRegistry {
  const requireEdge = o.requireEdge ?? true;
  const edgeType = o.edgeType ?? 'DATA_ACCESS';
  return {
    async lookup(infohashHex: string): Promise<SeederInfo[]> {
      const certIds = await o.presence.seedersFor(infohashHex);
      let seeders: SeederInfo[] = [];
      for (const certId of certIds) {
        const c = o.roster.getContact(certId);
        if (!c) continue;                                              // unknown identity
        if (requireEdge && !o.roster.isConnected(certId, edgeType)) continue; // no signed edge
        seeders = mergeSeeders(seeders, [contactSeederInfo(o.network, c)]);
      }
      return seeders;
    },
    async advertise(infohashHex: string, _seeder: SeederInfo): Promise<void> {
      await o.presence.announce(infohashHex);
    },
  };
}

/**
 * In-memory SeedPresence. Two instances sharing one `bus` map model a presence
 * fabric: each announces under its own certId; all see each other.
 */
export class InMemorySeedPresence implements SeedPresence {
  constructor(
    private readonly selfCertId: string,
    private readonly bus: Map<string, Set<string>> = new Map(),
  ) {}

  /** A fresh shared presence fabric for several InMemorySeedPresence nodes. */
  static fabric(): Map<string, Set<string>> {
    return new Map<string, Set<string>>();
  }

  async announce(infohashHex: string): Promise<void> {
    let s = this.bus.get(infohashHex);
    if (!s) { s = new Set(); this.bus.set(infohashHex, s); }
    s.add(this.selfCertId);
  }

  async seedersFor(infohashHex: string): Promise<string[]> {
    return [...(this.bus.get(infohashHex) ?? [])];
  }
}

```
