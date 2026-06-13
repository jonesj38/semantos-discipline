---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/xmpp/jid.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.864037+00:00
---

# core/protocol-types/src/xmpp/jid.ts

```ts
/**
 * D-XMPP-jid-binding — JID ⇄ (certId, BCA/multicast, hat) binding.
 *
 * A Semantos XMPP address packs three derived primitives into one JID:
 *
 *     <certId>@[<BCA-or-multicast-IPv6>]/<context-tag>
 *      ───┬──   ────────┬───────────────   ─────┬─────
 *      localpart       domainpart (IP literal)  resource
 *
 *   • localpart  = certId   — SHA-256(BRC-52 cert preimage)[0:16], 32-hex
 *   • domainpart = BCA       — pubkey-derived unicast IPv6 (deriveBCABytes),
 *                  OR a type-multicast group (deriveMulticastGroup, Phase 34A)
 *                  for pubsub.  Carried as a bracketed IPv6 literal.
 *   • resource   = hat       — CertRef.context_tag (root=0, carpenter=0x10,
 *                  musician=0x11), encoded as 2-char lowercase hex.
 *
 * This module is intentionally string-only: it does NOT import the BCA
 * deriver (that lives in runtime/session-protocol; importing it here would
 * invert layering).  Callers format the BCA bytes with
 * `bcaBytesToIPv6(...)` and pass the resulting string in.
 *
 * Cross-reference: docs/design/SRS-XMPP-IDENTITY-TRANSPORT.md §2.
 */

const CERT_ID_RE = /^[0-9a-f]{32}$/;

export interface NodeJidParts {
  /** 32-hex cert id. */
  certId: string;
  /** RFC 5952 IPv6 string, WITHOUT brackets (e.g. from bcaBytesToIPv6). */
  bcaIPv6: string;
  /** Hat / context tag, 0-255. */
  contextTag: number;
}

/** Encode a context tag (0-255) as the 2-char lowercase-hex JID resource. */
export function contextTagToResource(contextTag: number): string {
  if (!Number.isInteger(contextTag) || contextTag < 0 || contextTag > 255) {
    throw new Error(`context_tag must be an integer 0-255, got ${contextTag}`);
  }
  return contextTag.toString(16).padStart(2, '0');
}

/** Decode a 2-char hex JID resource back to a context tag (0-255). */
export function resourceToContextTag(resource: string): number {
  if (!/^[0-9a-f]{2}$/.test(resource)) {
    throw new Error(`JID resource must be 2 hex chars, got "${resource}"`);
  }
  return parseInt(resource, 16);
}

/**
 * Build a node JID from its derived parts.
 *
 *   jidForNode({ certId, bcaIPv6: "2602:f9f8::a3f8:b2c1", contextTag: 0x10 })
 *     → "….@[2602:f9f8::a3f8:b2c1]/10"
 */
export function jidForNode(parts: NodeJidParts): string {
  if (!CERT_ID_RE.test(parts.certId)) {
    throw new Error(`certId must be 32 lowercase-hex chars, got "${parts.certId}"`);
  }
  if (parts.bcaIPv6.includes('[') || parts.bcaIPv6.includes(']')) {
    throw new Error(`bcaIPv6 must be an unbracketed IPv6 string, got "${parts.bcaIPv6}"`);
  }
  const resource = contextTagToResource(parts.contextTag);
  return `${parts.certId}@[${parts.bcaIPv6}]/${resource}`;
}

/**
 * Build a BARE node JID (no resource): `certId@[BCA]`.  Roster items and
 * presence-subscription stanzas address the bare JID; the resource (hat) is a
 * per-session presence concern, not a roster-identity one.
 */
export function bareJidForNode(parts: Pick<NodeJidParts, 'certId' | 'bcaIPv6'>): string {
  if (!CERT_ID_RE.test(parts.certId)) {
    throw new Error(`certId must be 32 lowercase-hex chars, got "${parts.certId}"`);
  }
  if (parts.bcaIPv6.includes('[') || parts.bcaIPv6.includes(']')) {
    throw new Error(`bcaIPv6 must be an unbracketed IPv6 string, got "${parts.bcaIPv6}"`);
  }
  return `${parts.certId}@[${parts.bcaIPv6}]`;
}

const BARE_JID_RE = /^([0-9a-f]{32})@\[([0-9a-fA-F:]+)\]$/;

/** Parse a bare JID `certId@[BCA]`.  Inverse of `bareJidForNode`. */
export function parseBareJid(jid: string): Pick<NodeJidParts, 'certId' | 'bcaIPv6'> {
  const m = BARE_JID_RE.exec(jid);
  if (!m) {
    throw new Error(`not a Semantos bare JID (expected certId@[ipv6]): "${jid}"`);
  }
  return { certId: m[1]!, bcaIPv6: m[2]!.toLowerCase() };
}

const NODE_JID_RE = /^([0-9a-f]{32})@\[([0-9a-fA-F:]+)\]\/([0-9a-f]{2})$/;

/** Parse a node JID back into its parts.  Inverse of `jidForNode`. */
export function parseJid(jid: string): NodeJidParts {
  const m = NODE_JID_RE.exec(jid);
  if (!m) {
    throw new Error(`not a Semantos node JID (expected certId@[ipv6]/hat): "${jid}"`);
  }
  return {
    certId: m[1]!,
    bcaIPv6: m[2]!.toLowerCase(),
    contextTag: resourceToContextTag(m[3]!),
  };
}

// ─────────────────────────────────────────────────────────────────────
// PubSub addressing — a type-multicast group IS the pubsub node.
// XMPP pubsub publishes to `{ service, node }`; we map the multicast IPv6
// (from Phase 34A deriveMulticastGroup) to the node name, hosted at the
// home/relay BCA's pubsub service JID.  Collection-node hierarchy (XEP-0248)
// mirrors the SNS longest-prefix-match trie (WHAT ⊃ HOW ⊃ INST).
// ─────────────────────────────────────────────────────────────────────

export interface PubSubAddress {
  /** Pubsub service JID (e.g. the home/relay BCA host). */
  service: string;
  /** Pubsub node id = the type-multicast IPv6 group string. */
  node: string;
}

/**
 * Build a pubsub address from a type-multicast group + a service JID.
 * The multicast group string is the `deriveMulticastGroup(...)` output, e.g.
 * "ff03:WWWW:WWWW:HHHH:HHHH:IIII:IIII:0000".
 */
export function pubsubAddressForType(opts: {
  multicastIPv6: string;
  serviceJid: string;
}): PubSubAddress {
  return { service: opts.serviceJid, node: opts.multicastIPv6 };
}

```
