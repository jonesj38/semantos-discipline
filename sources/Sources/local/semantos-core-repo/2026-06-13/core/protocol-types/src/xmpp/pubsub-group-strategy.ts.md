---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/xmpp/pubsub-group-strategy.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.864618+00:00
---

# core/protocol-types/src/xmpp/pubsub-group-strategy.ts

```ts
/**
 * D-XMPP-pubsub-type — type-multicast group strategy for the XMPP adapter.
 *
 * `XmppNetworkAdapter`'s default group strategy is a FLAT node per composite
 * typeHash (`urn:type:<hash>`): exact-type pub/sub works, but a subscriber
 * cannot join "all of this WHAT domain" because a `PublishableObject` carries
 * only the composite typeHash, not the WHAT/HOW/INST axes.
 *
 * This module closes that gap by deriving the *real* Phase-34A type-multicast
 * group (`deriveMulticastGroup`, `mnca/srv6.ts`) so the pubsub node id IS the
 * `ff<scope>:WWWW:WWWW:HHHH:HHHH:IIII:IIII:0000` address, and a WHAT-prefix
 * collection node (`whatPrefixGroup` → `ff<scope>:WWWW:WWWW::`) lets a
 * subscriber receive every HOW/INST variant under a domain.
 *
 * The derivation is async (Web Crypto SHA-256), but the adapter's
 * `groupForObject`/`groupForQuery` hooks are synchronous — a node knows the
 * types it publishes/subscribes up front, so we PRE-DERIVE a `typeHash → group`
 * table once (`buildTypeGroupTable`) and return sync closures backed by it
 * (`makeTypeGroupStrategies`).  Unknown typeHashes fall back to the flat node,
 * so the strategy degrades gracefully rather than dropping the publish.
 *
 * Cross-reference: docs/design/SRS-XMPP-IDENTITY-TRANSPORT.md §5 + §11
 * (`D-XMPP-pubsub-type`).
 */

import {
  deriveMulticastGroup,
  whatPrefixGroup,
  MNCA_MULTICAST_SCOPE,
  type TypeAxes,
} from '../mnca/srv6';
import { pubsubAddressForType, type PubSubAddress } from './jid';
import type { NetworkQuery, PublishableObject } from '../network';

/** A composite typeHash mapped to its WHAT/HOW/INST axis decomposition. */
export interface TypeGroupEntry {
  /** The composite typeHash exactly as it appears on objects/queries. */
  typeHash: string;
  /** WHAT/HOW/INST axes that derive the multicast group. */
  axes: TypeAxes;
}

/** Pre-derived routing table: composite typeHash → multicast group string. */
export interface TypeGroupTable {
  /** typeHash → leaf multicast group (`ff<scope>:W:W:H:H:I:I:0000`). */
  readonly leaf: ReadonlyMap<string, string>;
  /** WHAT path → prefix collection group (`ff<scope>:W:W::`). */
  readonly whatPrefix: ReadonlyMap<string, string>;
  readonly scope: number;
}

/**
 * Pre-derive the multicast groups for a known set of types.  Call once at
 * wiring time (it awaits Web Crypto); the result feeds `makeTypeGroupStrategies`.
 */
export async function buildTypeGroupTable(
  entries: readonly TypeGroupEntry[],
  scope: number = MNCA_MULTICAST_SCOPE,
): Promise<TypeGroupTable> {
  const leaf = new Map<string, string>();
  const whatPrefix = new Map<string, string>();
  for (const { typeHash, axes } of entries) {
    leaf.set(typeHash, await deriveMulticastGroup(axes, scope));
    if (!whatPrefix.has(axes.what)) {
      whatPrefix.set(axes.what, await whatPrefixGroup(axes.what, scope));
    }
  }
  return { leaf, whatPrefix, scope };
}

/** Flat fallback node id for a typeHash not in the table. */
function flatNode(typeHash: string): string {
  return `urn:type:${typeHash}`;
}

export interface TypeGroupStrategies {
  groupForObject: (o: PublishableObject) => PubSubAddress;
  groupForQuery: (q: NetworkQuery) => PubSubAddress | null;
}

/**
 * Build the sync `groupForObject`/`groupForQuery` closures the adapter config
 * accepts, backed by a pre-derived `TypeGroupTable`.
 *
 *   • An object publishes to its leaf multicast node (exact type).
 *   • A query with `whatPath` resolves to the WHAT-prefix collection node
 *     (subscribe to the whole domain); otherwise to the leaf node for its
 *     `typeHash`.  A query naming neither returns null (adapter → no-op).
 *
 * Unknown typeHashes fall back to the flat `urn:type:<hash>` node.
 */
export function makeTypeGroupStrategies(
  table: TypeGroupTable,
  serviceJid: string,
  opts: { whatPathFor?: (q: NetworkQuery) => string | undefined } = {},
): TypeGroupStrategies {
  const addr = (node: string): PubSubAddress =>
    pubsubAddressForType({ multicastIPv6: node, serviceJid });

  return {
    groupForObject: (o) => addr(table.leaf.get(o.typeHash) ?? flatNode(o.typeHash)),
    groupForQuery: (q) => {
      const whatPath = opts.whatPathFor?.(q);
      if (whatPath) {
        const prefix = table.whatPrefix.get(whatPath);
        if (prefix) return addr(prefix);
      }
      if (q.typeHash) return addr(table.leaf.get(q.typeHash) ?? flatNode(q.typeHash));
      return null;
    },
  };
}

```
