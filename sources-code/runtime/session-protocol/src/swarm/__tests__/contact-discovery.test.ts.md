---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/contact-discovery.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.078199+00:00
---

# runtime/session-protocol/src/swarm/__tests__/contact-discovery.test.ts

```ts
/**
 * Identity-bound discovery — fetch from a CONTACT, not an IP.
 *
 *  - makeBcaResolver derives the SAME address the XMPP/SRS layer uses (the
 *    integration linchpin: transfer dials a contact at its presence address).
 *  - contactSeederRegistry surfaces only known contacts you hold a signed edge
 *    with, each addressed by its identity-derived BCA.
 *  - the registry plugs into LayeredBrainClient → a contact seeder flows into
 *    locate().seeders.
 */
import { describe, expect, test } from 'bun:test';
import { fromHex, publishFile, toHex } from '@semantos/protocol-types';
import { deriveBCABytes, bcaBytesToIPv6 } from '../../signer';
import { PrivateKey } from '../metered-flow';
import {
  makeBcaResolver,
  deriveContactBcaBytes,
  contactSeederInfo,
  type BcaNetwork,
  type ContactRef,
} from '../contact-bca';
import {
  contactSeederRegistry,
  InMemorySeedPresence,
  type ContactRoster,
} from '../contact-seeder-registry';
import { LayeredBrainClient } from '../layered-brain-client';
import { FakeBrainClient } from '../brain-client';

const NETWORK: BcaNetwork = {
  subnetPrefix: Uint8Array.from([0xfd, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01]),
  modifier: new Uint8Array(16).fill(0xab),
  sec: 1,
};

function contactOf(name: string): ContactRef & { name: string } {
  const pub = PrivateKey.fromRandom().toPublicKey().toString(); // 33-byte compressed hex
  return { certId: `cert-${name}`, publicKey: pub, name };
}

/** A tiny ContactRoster with an explicit set of edged certIds. */
function roster(contacts: ContactRef[], edged: Set<string>): ContactRoster {
  const byId = new Map(contacts.map(c => [c.certId, c]));
  return {
    getContact: (id) => byId.get(id) ?? null,
    listContacts: () => [...byId.values()],
    isConnected: (id) => edged.has(id),
  };
}

describe('contact → BCA addressing', () => {
  test('makeBcaResolver matches the canonical SRS derivation byte-for-byte', () => {
    const c = contactOf('alice');
    const resolver = makeBcaResolver(NETWORK);
    // The exact expression createXmppNode uses for a node address.
    const canonical = bcaBytesToIPv6(deriveBCABytes(fromHex(c.publicKey), NETWORK.subnetPrefix, NETWORK.modifier, NETWORK.sec));
    expect(resolver(c)).toBe(canonical);
  });

  test('derivation is deterministic, 16-byte, IPv6-shaped', () => {
    const c = contactOf('bob');
    const a = deriveContactBcaBytes(NETWORK, c);
    const b = deriveContactBcaBytes(NETWORK, c);
    expect(a.length).toBe(16);
    expect([...a]).toEqual([...b]);
    const info = contactSeederInfo(NETWORK, c, new Uint8Array([1]));
    expect(info.bca && info.bca.length).toBe(16);
    expect(info.address).toBe(bcaBytesToIPv6(a));
  });

  test('different contacts get different addresses', () => {
    const resolver = makeBcaResolver(NETWORK);
    expect(resolver(contactOf('x'))).not.toBe(resolver(contactOf('y')));
  });
});

describe('contactSeederRegistry — identity-gated discovery', () => {
  test('only known + edged contacts surface, addressed by their BCA', async () => {
    const alice = contactOf('alice');  // contact + edge → should surface
    const bob = contactOf('bob');      // contact, NO edge → filtered
    const mallory = contactOf('mal');  // NOT a contact → filtered
    const r = roster([alice, bob], new Set([alice.certId]));

    const fabric = InMemorySeedPresence.fabric();
    const ihHex = toHex(publishFile(new Uint8Array(2 * 1016), 'f.bin').infohash);
    // All three announce they seed it…
    for (const c of [alice, bob, mallory]) {
      await new InMemorySeedPresence(c.certId, fabric).announce(ihHex);
    }

    const registry = contactSeederRegistry({ roster: r, network: NETWORK, presence: new InMemorySeedPresence('me', fabric) });
    const seeders = await registry.lookup(ihHex);

    expect(seeders.length).toBe(1); // only alice (known + edged)
    expect(seeders[0].address).toBe(makeBcaResolver(NETWORK)(alice));
    expect(seeders[0].bca && seeders[0].bca.length).toBe(16);
  });

  test('requireEdge:false surfaces any known contact (still BCA-addressed)', async () => {
    const bob = contactOf('bob');
    const r = roster([bob], new Set()); // no edges
    const fabric = InMemorySeedPresence.fabric();
    const ihHex = toHex(publishFile(new Uint8Array(2 * 1016), 'g.bin').infohash);
    await new InMemorySeedPresence(bob.certId, fabric).announce(ihHex);

    const registry = contactSeederRegistry({ roster: r, network: NETWORK, presence: new InMemorySeedPresence('me', fabric), requireEdge: false });
    expect((await registry.lookup(ihHex)).length).toBe(1);
  });

  test('plugs into LayeredBrainClient: a contact seeder flows into locate()', async () => {
    const alice = contactOf('alice');
    const r = roster([alice], new Set([alice.certId]));
    const fabric = InMemorySeedPresence.fabric();
    const pub = publishFile(new Uint8Array(3 * 1016), 'h.bin');
    const ihHex = toHex(pub.infohash);
    await new InMemorySeedPresence(alice.certId, fabric).announce(ihHex);

    const inner = new FakeBrainClient();
    await inner.publish({ infohash: pub.infohash, manifestCell: pub.manifestCell, semanticPath: 'h.bin' });

    const layered = new LayeredBrainClient({
      inner,
      registry: contactSeederRegistry({ roster: r, network: NETWORK, presence: new InMemorySeedPresence('me', fabric) }),
    });
    const res = await layered.locate(pub.infohash);
    expect(res.seeders.map(s => s.address)).toEqual([makeBcaResolver(NETWORK)(alice)]);
  });
});

```
