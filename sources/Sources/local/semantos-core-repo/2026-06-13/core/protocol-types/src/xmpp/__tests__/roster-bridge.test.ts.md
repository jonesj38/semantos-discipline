---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/xmpp/__tests__/roster-bridge.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.903832+00:00
---

# core/protocol-types/src/xmpp/__tests__/roster-bridge.test.ts

```ts
/**
 * D-XMPP-roster-bridge tests — ContactBook <-> roster + presence.
 *
 *   1. buildRoster maps contacts → bare-JID items; active MESSAGING edge ⇒
 *      subscription "both", no/revoked edge ⇒ "none"
 *   2. contacts whose BCA can't be resolved land in `unresolved`, not `items`
 *   3. decidePresenceSubscription — approve (signed edge) / defer (known, no
 *      edge) / deny (unknown cert) / deny (unparseable JID)
 *   4. edgeRevocationTeardown emits unsubscribe+unsubscribed (or [] when
 *      unknown / unresolvable)
 *   5. presence stanza builders
 */

import { describe, it, expect } from '@jest/globals';
import {
  buildRoster,
  contactToRosterItem,
  decidePresenceSubscription,
  edgeRevocationTeardown,
  presenceSubscribe,
  presenceUnsubscribed,
  type RosterBook,
} from '../roster-bridge';
import { bareJidForNode } from '../jid';
import type { Contact, EdgeRecord, EdgeType } from '../../../../contact-book/src/types';

const CERT_A = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const CERT_B = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const CERT_UNKNOWN = 'cccccccccccccccccccccccccccccccc';

function contact(certId: string, name: string): Contact {
  return {
    certId,
    publicKey: '02' + '00'.repeat(32),
    displayName: name,
    source: 'manual',
    addedAt: 1,
    updatedAt: 1,
  };
}

function messagingEdge(theirCert: string, revoked = false): EdgeRecord {
  return {
    edgeId: `edge-${theirCert}`,
    initiatorCertId: 'self',
    responderCertId: theirCert,
    edgeType: 'MESSAGING',
    signingKeyIndex: 3,
    recoveryPolicy: 'NONE',
    createdAt: 10,
    ...(revoked ? { revokedAt: 20 } : {}),
  };
}

/** A fake ContactBook slice driven by plain maps. */
function fakeBook(
  contacts: Contact[],
  edges: Record<string, EdgeRecord | null>,
): RosterBook {
  const byId = new Map(contacts.map((c) => [c.certId, c]));
  return {
    listContacts: () => [...byId.values()],
    getContact: (id: string) => byId.get(id) ?? null,
    getEdge: (theirCertId: string, edgeType?: EdgeType) =>
      edgeType === 'MESSAGING' || edgeType === undefined ? edges[theirCertId] ?? null : null,
  };
}

// Every contact resolves to a distinct BCA except CERT_B (simulates an
// unresolvable peer).
const bcaFor = (c: Contact): string | null => (c.certId === CERT_B ? null : '2602:f9f8::1');

describe('buildRoster', () => {
  it('emits both-subscribed for an active MESSAGING edge', () => {
    const book = fakeBook([contact(CERT_A, 'Alice')], { [CERT_A]: messagingEdge(CERT_A) });
    const { items, unresolved } = buildRoster(book, () => '2602:f9f8::1');
    expect(unresolved).toEqual([]);
    expect(items).toHaveLength(1);
    expect(items[0]).toEqual({
      jid: bareJidForNode({ certId: CERT_A, bcaIPv6: '2602:f9f8::1' }),
      name: 'Alice',
      subscription: 'both',
      certId: CERT_A,
    });
  });

  it('emits none for a missing or revoked edge', () => {
    const book = fakeBook([contact(CERT_A, 'Alice')], { [CERT_A]: null });
    expect(buildRoster(book, () => '2602:f9f8::1').items[0]!.subscription).toBe('none');

    const revoked = fakeBook([contact(CERT_A, 'Alice')], { [CERT_A]: messagingEdge(CERT_A, true) });
    expect(buildRoster(revoked, () => '2602:f9f8::1').items[0]!.subscription).toBe('none');
  });

  it('routes BCA-unresolvable contacts to `unresolved`', () => {
    const book = fakeBook(
      [contact(CERT_A, 'Alice'), contact(CERT_B, 'Bob')],
      { [CERT_A]: messagingEdge(CERT_A), [CERT_B]: messagingEdge(CERT_B) },
    );
    const { items, unresolved } = buildRoster(book, bcaFor);
    expect(items.map((i) => i.certId)).toEqual([CERT_A]);
    expect(unresolved).toEqual([CERT_B]);
  });

  it('contactToRosterItem returns null for an unresolvable BCA', () => {
    const book = fakeBook([contact(CERT_B, 'Bob')], {});
    expect(contactToRosterItem(contact(CERT_B, 'Bob'), book, bcaFor)).toBeNull();
  });
});

describe('decidePresenceSubscription', () => {
  const book = fakeBook(
    [contact(CERT_A, 'Alice'), contact(CERT_B, 'Bob')],
    { [CERT_A]: messagingEdge(CERT_A) }, // Alice has an edge; Bob does not
  );

  it('approves when a signed active MESSAGING edge exists', () => {
    const d = decidePresenceSubscription(bareJidForNode({ certId: CERT_A, bcaIPv6: '2602:f9f8::1' }), book);
    expect(d.decision).toBe('approve');
    expect(d.certId).toBe(CERT_A);
  });

  it('defers a known contact with no active edge', () => {
    const d = decidePresenceSubscription(bareJidForNode({ certId: CERT_B, bcaIPv6: '2602:f9f8::2' }), book);
    expect(d.decision).toBe('defer');
    expect(d.certId).toBe(CERT_B);
  });

  it('denies an unknown cert', () => {
    const d = decidePresenceSubscription(
      bareJidForNode({ certId: CERT_UNKNOWN, bcaIPv6: '2602:f9f8::9' }),
      book,
    );
    expect(d.decision).toBe('deny');
    expect(d.certId).toBe(CERT_UNKNOWN);
  });

  it('denies an unparseable JID without throwing', () => {
    const d = decidePresenceSubscription('not-a-jid', book);
    expect(d.decision).toBe('deny');
    expect(d.certId).toBeNull();
  });
});

describe('edgeRevocationTeardown', () => {
  it('emits unsubscribe + unsubscribed for a resolvable contact', () => {
    const book = fakeBook([contact(CERT_A, 'Alice')], {});
    const stanzas = edgeRevocationTeardown(CERT_A, book, () => '2602:f9f8::1');
    const jid = bareJidForNode({ certId: CERT_A, bcaIPv6: '2602:f9f8::1' });
    expect(stanzas).toEqual([
      `<presence to="${jid}" type="unsubscribe"/>`,
      `<presence to="${jid}" type="unsubscribed"/>`,
    ]);
  });

  it('returns [] for an unknown or unresolvable contact', () => {
    const book = fakeBook([contact(CERT_B, 'Bob')], {});
    expect(edgeRevocationTeardown(CERT_UNKNOWN, book, () => '2602:f9f8::1')).toEqual([]);
    expect(edgeRevocationTeardown(CERT_B, book, bcaFor)).toEqual([]);
  });
});

describe('presence stanza builders', () => {
  it('build well-formed presence stanzas', () => {
    expect(presenceSubscribe('x@[2602::1]')).toBe('<presence to="x@[2602::1]" type="subscribe"/>');
    expect(presenceUnsubscribed('x@[2602::1]')).toBe('<presence to="x@[2602::1]" type="unsubscribed"/>');
  });
});

```
