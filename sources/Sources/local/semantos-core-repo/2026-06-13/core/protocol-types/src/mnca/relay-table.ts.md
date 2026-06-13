---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/mnca/relay-table.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.898069+00:00
---

# core/protocol-types/src/mnca/relay-table.ts

```ts
/**
 * Relay service table + originator-side selection — the paid-pubsub
 * demand/supply matching layer.
 *
 * Spec source: `docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md` §13.4 (the market
 * for paid delivery) + §13.6 (subscription topology IS the routing).
 *
 * Two sides of the market, both pure (no transport, no ambient clock —
 * callers pass `nowMs`; no @semantos/state):
 *
 *  - SUPPLY (relay side): a `RelayServiceTable` records which type-paths
 *    this node can serve and at what price. `emitAdvertisements` turns the
 *    table into signed `RelayAdvertisement`s ready to publish on the
 *    overlay topic (`RELAY_ADVERTISEMENT_TOPIC`).
 *
 *  - DEMAND (originator side): `selectRelay` filters a set of received
 *    advertisements by validity + path-endpoint match and returns the
 *    cheapest viable relay.
 *
 * The actual overlay submit/subscribe (BRC-22 topic-manager) is the
 * transport binding and is NOT done here — this module produces and
 * consumes advertisement *values*; moving them over the wire is the
 * relay/originator runtime's job.
 *
 * Crypto stays OUT of protocol-types: `emitAdvertisements` takes an
 * injected `signFn` that signs the canonical signing input. The relay
 * runtime supplies a real secp256k1 signer; tests supply a stub.
 */

import {
  RELAY_ADVERTISEMENT_VERSION_V1,
  relayAdvertisementSigningInput,
  isAdvertisementCurrent,
  pathEndpointsMatch,
  type RelayAdvertisement,
} from '../overlay/relay-advertisement';

const TYPE_HASH_SIZE = 32 as const;
const REACH_SIZE = 32 as const;

function hex(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += bytes[i]!.toString(16).padStart(2, '0');
  return s;
}

/** One (input → output) transform this relay offers, with its price. */
export interface RelayServiceEntry {
  /** 32-byte type-hash the relay accepts on input. */
  inputTypeHash: Uint8Array;
  /** 32-byte type-hash the relay emits on output. */
  outputTypeHash: Uint8Array;
  /** Forwarding price per cell, in satoshis. */
  pricePerCellSats: bigint;
  /**
   * 32-byte commitment to the downstream subscriber set this relay can
   * reach (§13.4). 32 zero bytes = "best-effort discovery" (used during
   * the demo when consumer sets are dynamic).
   */
  subscriberSetReach: Uint8Array;
}

/**
 * Per-node table of the type-paths a relay can serve. Keyed internally by
 * `hex(input) + ':' + hex(output)` so a relay offers at most one price per
 * (input, output) pair (re-adding the same pair overwrites).
 */
export class RelayServiceTable {
  private readonly entries = new Map<string, RelayServiceEntry>();

  private static key(input: Uint8Array, output: Uint8Array): string {
    return `${hex(input)}:${hex(output)}`;
  }

  /** Add (or overwrite) the offer for an (input, output) pair. */
  add(entry: RelayServiceEntry): this {
    if (entry.inputTypeHash.length !== TYPE_HASH_SIZE) {
      throw new Error(`RelayServiceTable.add: inputTypeHash must be ${TYPE_HASH_SIZE} bytes`);
    }
    if (entry.outputTypeHash.length !== TYPE_HASH_SIZE) {
      throw new Error(`RelayServiceTable.add: outputTypeHash must be ${TYPE_HASH_SIZE} bytes`);
    }
    if (entry.subscriberSetReach.length !== REACH_SIZE) {
      throw new Error(`RelayServiceTable.add: subscriberSetReach must be ${REACH_SIZE} bytes`);
    }
    if (entry.pricePerCellSats < 0n) {
      throw new Error('RelayServiceTable.add: pricePerCellSats must be >= 0');
    }
    this.entries.set(RelayServiceTable.key(entry.inputTypeHash, entry.outputTypeHash), {
      inputTypeHash: entry.inputTypeHash.slice(),
      outputTypeHash: entry.outputTypeHash.slice(),
      pricePerCellSats: entry.pricePerCellSats,
      subscriberSetReach: entry.subscriberSetReach.slice(),
    });
    return this;
  }

  /** Remove the offer for an (input, output) pair. Returns true if present. */
  remove(inputTypeHash: Uint8Array, outputTypeHash: Uint8Array): boolean {
    return this.entries.delete(RelayServiceTable.key(inputTypeHash, outputTypeHash));
  }

  /** True when an offer exists for this (input, output) pair. */
  has(inputTypeHash: Uint8Array, outputTypeHash: Uint8Array): boolean {
    return this.entries.has(RelayServiceTable.key(inputTypeHash, outputTypeHash));
  }

  /** All entries, in insertion order. */
  list(): RelayServiceEntry[] {
    return [...this.entries.values()];
  }

  /** Number of (input, output) offers in the table. */
  get size(): number {
    return this.entries.size;
  }
}

/** Produces a fresh 16-byte nonce per advertisement (anti-replay). */
export type NonceFactory = () => Uint8Array;

/** Signs the canonical signing input, returning a 64-byte ECDSA signature. */
export type SignFn = (signingInput: Uint8Array) => Uint8Array;

export interface EmitAdvertisementsInput {
  /** 16-byte BCA of the advertising relay. */
  relayBca: Uint8Array;
  /** u64 ms — start of each advertisement's validity window. */
  validFromMs: bigint;
  /** u64 ms — how long each advertisement stays valid (added to validFromMs). */
  validForMs: bigint;
  /** Supplies a fresh 16-byte nonce per ad. */
  nonceFactory: NonceFactory;
  /** Signs the canonical signing input. Real secp256k1 in prod; stub in tests. */
  signFn: SignFn;
  /** Optional u64 flow-label echo (0 when not pre-committing). */
  flowLabel?: bigint;
}

/**
 * Turn a relay's service table into one signed `RelayAdvertisement` per
 * entry, ready to publish on `RELAY_ADVERTISEMENT_TOPIC`. The signature
 * is produced by `signFn` over `relayAdvertisementSigningInput` (the
 * encoded form minus the trailing signature), so crypto stays out of
 * protocol-types.
 */
export function emitAdvertisements(
  table: RelayServiceTable,
  input: EmitAdvertisementsInput,
): RelayAdvertisement[] {
  if (input.relayBca.length !== 16) {
    throw new Error(`emitAdvertisements: relayBca must be 16 bytes (got ${input.relayBca.length})`);
  }
  if (input.validForMs <= 0n) {
    throw new Error('emitAdvertisements: validForMs must be > 0');
  }
  const validNotBefore = input.validFromMs;
  const validNotAfter = input.validFromMs + input.validForMs;
  const flowLabel = input.flowLabel ?? 0n;

  return table.list().map((entry) => {
    const nonce = input.nonceFactory();
    if (nonce.length !== 16) {
      throw new Error(`emitAdvertisements: nonceFactory must return 16 bytes (got ${nonce.length})`);
    }
    // Build the unsigned ad, derive the signing input, sign, attach.
    const unsigned: RelayAdvertisement = {
      version: RELAY_ADVERTISEMENT_VERSION_V1,
      relayBca: input.relayBca.slice(),
      typeHashPath: { typeHashes: [entry.inputTypeHash.slice(), entry.outputTypeHash.slice()] },
      pricePerCellSats: entry.pricePerCellSats,
      subscriberSetReach: entry.subscriberSetReach.slice(),
      validNotBefore,
      validNotAfter,
      flowLabel,
      nonce,
      signature: new Uint8Array(64),
    };
    const signingInput = relayAdvertisementSigningInput(unsigned);
    const signature = input.signFn(signingInput);
    if (signature.length !== 64) {
      throw new Error(`emitAdvertisements: signFn must return 64 bytes (got ${signature.length})`);
    }
    return { ...unsigned, signature };
  });
}

/**
 * Originator-side relay selection. Filters `ads` to those that are
 * currently valid (`isAdvertisementCurrent`) AND whose typed path's
 * endpoints match the desired (input, output) transform
 * (`pathEndpointsMatch`), then returns them sorted cheapest-first along
 * with the cheapest as `chosen` (null when none match).
 *
 * This is the §13.4 demand side: the originator queries the overlay,
 * collects advertisements, and picks. No path search — just a filter +
 * min over advertised supply.
 */
export interface RelaySelection {
  chosen: RelayAdvertisement | null;
  viable: RelayAdvertisement[];
}

export function selectRelay(
  ads: RelayAdvertisement[],
  inputTypeHash: Uint8Array,
  outputTypeHash: Uint8Array,
  nowMs: bigint,
): RelaySelection {
  const viable = ads
    .filter((ad) => isAdvertisementCurrent(ad, nowMs) && pathEndpointsMatch(ad, inputTypeHash, outputTypeHash))
    .sort((a, b) => (a.pricePerCellSats < b.pricePerCellSats ? -1 : a.pricePerCellSats > b.pricePerCellSats ? 1 : 0));
  return { chosen: viable.length > 0 ? viable[0]! : null, viable };
}

```
