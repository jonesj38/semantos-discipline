---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/xmpp/roster-bridge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.863754+00:00
---

# core/protocol-types/src/xmpp/roster-bridge.ts

```ts
/**
 * D-XMPP-roster-bridge — ContactBook ⇄ XMPP roster + presence subscriptions.
 *
 * The ContactBook IS the roster, and it is strictly stronger than the vanilla
 * version: an XMPP presence subscription is normally server-vouched, but here
 * the authorising fact is a SIGNED `MESSAGING` EdgeRecord (carrying a
 * `signingKeyIndex`).  So:
 *
 *   Contact                       → roster item (bare JID certId@[BCA])
 *   active MESSAGING EdgeRecord    → subscription = "both"
 *   no edge / revoked edge         → subscription = "none"
 *   inbound <presence subscribe>   → APPROVE iff an active MESSAGING edge
 *                                    exists; else DEFER (needs connectTo);
 *                                    DENY if the contact is unknown
 *   revokeEdge()                   → <presence unsubscribe>+<unsubscribed>
 *
 * This module is pure: it reads a narrow slice of the ContactBook and emits
 * roster items, presence stanza strings, and subscription DECISIONS.  It never
 * mutates the book or talks to a transport — wiring code applies the decisions
 * (e.g. calls connectTo / revokeEdge) and sends the stanzas.
 *
 * A contact's BCA is not stored on the Contact; the caller supplies a resolver
 * (`bcaIPv6For`) — typically `bcaBytesToIPv6(deriveBCABytes(publicKey, …))` with
 * the network's subnet prefix, or a peer-locator lookup.  Contacts whose BCA
 * cannot be resolved are skipped (returned in `unresolved`).
 *
 * Cross-reference: docs/design/SRS-XMPP-IDENTITY-TRANSPORT.md §4.
 */

import type { Contact, ContactBook, EdgeRecord } from '../../../contact-book/src/types';
import { bareJidForNode, parseBareJid } from './jid';

/** The narrow ContactBook slice the bridge depends on (eases faking/testing). */
export type RosterBook = Pick<ContactBook, 'listContacts' | 'getContact' | 'getEdge'>;

/** Resolve a contact's BCA to an unbracketed IPv6 string, or null if unknown. */
export type BcaResolver = (contact: Contact) => string | null;

export type RosterSubscription = 'none' | 'to' | 'from' | 'both';

export interface RosterItem {
  /** Bare JID: certId@[BCA]. */
  jid: string;
  /** Display name. */
  name: string;
  /** Presence subscription state, derived from the MESSAGING edge. */
  subscription: RosterSubscription;
  /** Contact cert id (roster key). */
  certId: string;
}

/** True iff an EdgeRecord exists, is MESSAGING, and is not revoked. */
function isActiveMessagingEdge(edge: EdgeRecord | null): boolean {
  return !!edge && edge.edgeType === 'MESSAGING' && edge.revokedAt === undefined;
}

/**
 * Map a single contact to a roster item.  Returns null if its BCA can't be
 * resolved (caller collects these separately).
 */
export function contactToRosterItem(
  contact: Contact,
  book: RosterBook,
  bcaIPv6For: BcaResolver,
): RosterItem | null {
  const bcaIPv6 = bcaIPv6For(contact);
  if (!bcaIPv6) return null;
  const edge = book.getEdge(contact.certId, 'MESSAGING');
  return {
    jid: bareJidForNode({ certId: contact.certId, bcaIPv6 }),
    name: contact.displayName,
    subscription: isActiveMessagingEdge(edge) ? 'both' : 'none',
    certId: contact.certId,
  };
}

export interface RosterBuildResult {
  items: RosterItem[];
  /** Cert ids whose BCA could not be resolved (omitted from the roster). */
  unresolved: string[];
}

/** Build the full roster from the contact book. */
export function buildRoster(book: RosterBook, bcaIPv6For: BcaResolver): RosterBuildResult {
  const items: RosterItem[] = [];
  const unresolved: string[] = [];
  for (const contact of book.listContacts()) {
    const item = contactToRosterItem(contact, book, bcaIPv6For);
    if (item) items.push(item);
    else unresolved.push(contact.certId);
  }
  return { items, unresolved };
}

// ─────────────────────────────────────────────────────────────────────
// Presence subscription stanzas (RFC 6121 §3).  Bare JID in `to`.
// ─────────────────────────────────────────────────────────────────────

type PresenceType = 'subscribe' | 'subscribed' | 'unsubscribe' | 'unsubscribed';

function presenceStanza(toBareJid: string, type: PresenceType): string {
  // toBareJid is certId@[ipv6]; only `&`,`<`,`"` are meaningful in the attr.
  const esc = toBareJid.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
  return `<presence to="${esc}" type="${type}"/>`;
}

/** Ask a peer to share presence (sent when establishing a MESSAGING edge). */
export const presenceSubscribe = (toBareJid: string) => presenceStanza(toBareJid, 'subscribe');
/** Approve a peer's presence-subscription request. */
export const presenceSubscribed = (toBareJid: string) => presenceStanza(toBareJid, 'subscribed');
/** Withdraw our subscription to a peer. */
export const presenceUnsubscribe = (toBareJid: string) => presenceStanza(toBareJid, 'unsubscribe');
/** Reject / revoke a peer's subscription. */
export const presenceUnsubscribed = (toBareJid: string) => presenceStanza(toBareJid, 'unsubscribed');

// ─────────────────────────────────────────────────────────────────────
// Inbound presence-subscription decision.  The signed edge is the
// authorisation — not the server.
// ─────────────────────────────────────────────────────────────────────

export interface SubscriptionDecision {
  decision: 'approve' | 'defer' | 'deny';
  /** Parsed cert id of the requester (null if the JID was unparseable). */
  certId: string | null;
  reason: string;
}

/**
 * Decide how to answer an inbound `<presence type="subscribe">`.
 *
 *   approve — a signed active MESSAGING edge already authorises this peer
 *   defer   — known contact but no active edge yet (wiring should prompt /
 *             connectTo before approving)
 *   deny    — unknown cert (not in the contact book)
 */
export function decidePresenceSubscription(
  fromBareJid: string,
  book: RosterBook,
): SubscriptionDecision {
  let certId: string;
  try {
    certId = parseBareJid(fromBareJid).certId;
  } catch {
    return { decision: 'deny', certId: null, reason: 'unparseable JID' };
  }
  const contact = book.getContact(certId);
  if (!contact) {
    return { decision: 'deny', certId, reason: 'unknown cert (not in contact book)' };
  }
  if (isActiveMessagingEdge(book.getEdge(certId, 'MESSAGING'))) {
    return { decision: 'approve', certId, reason: 'active signed MESSAGING edge authorises presence' };
  }
  return { decision: 'defer', certId, reason: 'known contact but no active MESSAGING edge' };
}

/**
 * Stanzas to tear down presence after an edge is revoked — withdraw our
 * subscription and reject theirs.  Returns [] if the contact's BCA is
 * unresolvable.
 */
export function edgeRevocationTeardown(
  theirCertId: string,
  book: RosterBook,
  bcaIPv6For: BcaResolver,
): string[] {
  const contact = book.getContact(theirCertId);
  if (!contact) return [];
  const bcaIPv6 = bcaIPv6For(contact);
  if (!bcaIPv6) return [];
  const jid = bareJidForNode({ certId: theirCertId, bcaIPv6 });
  return [presenceUnsubscribe(jid), presenceUnsubscribed(jid)];
}

```
