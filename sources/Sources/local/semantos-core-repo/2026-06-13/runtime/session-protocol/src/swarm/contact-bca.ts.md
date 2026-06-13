---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/contact-bca.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.058089+00:00
---

# runtime/session-protocol/src/swarm/contact-bca.ts

```ts
/**
 * contact-bca — address a transfer peer by IDENTITY, not IP.
 *
 * A contact's BCA (the 16-byte IPv6-shaped Blockchain Address) is DERIVED from
 * its cert pubkey — the exact same derivation the XMPP/SRS layer uses for a
 * node's address (`deriveBCABytes` + `bcaBytesToIPv6`, runtime/session-protocol/
 * src/signer; createXmppNode line ~134). So a contact's pubkey → its BCA → a
 * transfer transport address that is byte-identical to where the XMPP presence
 * layer reaches it. This is the seam that turns "fetch from a peer at some IP"
 * into "fetch from <contact> at their identity-derived address".
 *
 * `makeBcaResolver` is the concrete `BcaResolver` the xmpp-node config asks for
 * (callers supply it) — built once here so transfer + XMPP share one convention.
 */

import { fromHex } from '@semantos/protocol-types';
import { deriveBCABytes, bcaBytesToIPv6 } from '../signer';
import type { SeederInfo } from './brain-client';

/** BCA network parameters a node/subnet lives under (mirrors XmppNodeNetwork). */
export interface BcaNetwork {
  /** 8-byte subnet prefix the BCA lives under (Phase-26D). */
  subnetPrefix: Uint8Array;
  /** 16-byte BCA modifier. */
  modifier: Uint8Array;
  /** Security/scope nibble (0-7). */
  sec: number;
}

/** Minimal contact slice needed to address it (structural — no contact-book dep). */
export interface ContactRef {
  certId: string;
  /** 33-byte compressed secp256k1 pubkey, hex. */
  publicKey: string;
}

/** Resolve a contact → BCA IPv6 string (the transfer transport address). */
export type ContactBcaResolver = (c: ContactRef) => string;

/** Raw 16-byte BCA for a contact under a network — same derivation as the SRS. */
export function deriveContactBcaBytes(network: BcaNetwork, c: ContactRef): Uint8Array {
  return deriveBCABytes(fromHex(c.publicKey), network.subnetPrefix, network.modifier, network.sec);
}

/** A `BcaResolver` bound to a network — drop into createXmppNode AND transfer. */
export function makeBcaResolver(network: BcaNetwork): ContactBcaResolver {
  return (c) => bcaBytesToIPv6(deriveContactBcaBytes(network, c));
}

/** A contact as a swarm SeederInfo, addressed by its identity-derived BCA. */
export function contactSeederInfo(network: BcaNetwork, c: ContactRef, bitfield?: Uint8Array): SeederInfo {
  const bca = deriveContactBcaBytes(network, c);
  return { address: bcaBytesToIPv6(bca), bca, bitfield };
}

```
