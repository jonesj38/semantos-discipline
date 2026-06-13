---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/types/metering.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.398723+00:00
---

# src/types/metering.ts

```ts
/**
 * Metered Flow Protocol: Usage Quotas and Payment Channels
 *
 * Types for managing metered access via payment channels using the 2PDA
 * (Two-Party Turing Complete Deterministic Automation) model.
 */

import type { DomainFlag } from './domain-flags.js';

/**
 * ChannelState: Enumeration of metering channel lifecycle states.
 */
export enum ChannelState {
  /** Participants negotiating terms before funding */
  NEGOTIATING = 'NEGOTIATING',

  /** Channel has been funded but not yet active */
  FUNDED = 'FUNDED',

  /** Channel is active and processing metered transactions */
  ACTIVE = 'ACTIVE',

  /** Channel is temporarily paused (e.g., dispute waiting) */
  PAUSED = 'PAUSED',

  /** One party has requested closing */
  CLOSING_REQUESTED = 'CLOSING_REQUESTED',

  /** Both parties have confirmed closure intent */
  CLOSING_CONFIRMED = 'CLOSING_CONFIRMED',

  /** Channel settlement transaction has been broadcast */
  SETTLED = 'SETTLED',

  /** Channel state is disputed; requires arbiter/blockchain resolution */
  DISPUTED = 'DISPUTED',
}

/**
 * MeteringChannel: Represents an open metering channel between provider and consumer.
 *
 * Tracks the state of a METERING-domain key derivation context and associated
 * UTXO that funds usage quotas.
 */
export interface MeteringChannel {
  /** Unique channel identifier (typically txid.vout of funding) */
  channelId: string;

  /** Current state of the channel */
  state: ChannelState;

  /** Hex cert ID of the service provider */
  providerCertId: string;

  /** Hex cert ID of the service consumer */
  consumerCertId: string;

  /** Outpoint of the funding UTXO (txid.vout). null until confirmed. */
  fundingOutpoint: string | null;

  /** Current metering tick (monotonically increasing counter) */
  currentTick: number;

  /** nSequence value used in channel transactions */
  nSequence: number;

  /** Always 0x0A (METERING) — identifies the domain for key derivation */
  domainFlag: DomainFlag;

  /** Unix timestamp (ms) when channel was created */
  createdAt: number;

  /** Unix timestamp (ms) of last state update */
  updatedAt: number;
}

/**
 * TickProof: Cryptographic proof of a metering tick.
 *
 * Proves consumption of one unit in the metered flow, signed by the provider.
 */
export interface TickProof {
  /** The tick counter value this proof is for */
  tick: number;

  /** HMAC (hex string) authenticating this tick */
  hmac: string;

  /** Unix timestamp (ms) when tick was issued */
  timestamp: number;

  /** Cumulative satoshis paid up to this tick */
  cumulativeSatoshis: number;
}

/**
 * SettlementRecord: Final settlement state of a metering channel.
 *
 * Captures the agreed-upon final tick and both parties' signatures authorizing settlement.
 */
export interface SettlementRecord {
  /** Channel identifier being settled */
  channelId: string;

  /** Final tick counter value */
  finalTick: number;

  /** Hex signature from the provider authorizing settlement */
  providerSignature: string;

  /** Hex signature from the consumer authorizing settlement */
  consumerSignature: string;

  /** Transaction ID of the settlement transaction. null until broadcast. */
  settlementTxId: string | null;
}

/**
 * Create a metering channel.
 *
 * @param channelId Unique channel identifier
 * @param providerCertId Hex cert ID of provider
 * @param consumerCertId Hex cert ID of consumer
 * @returns A new MeteringChannel in NEGOTIATING state
 */
export function createMeteringChannel(
  channelId: string,
  providerCertId: string,
  consumerCertId: string
): MeteringChannel {
  const now = Date.now();
  return {
    channelId,
    state: ChannelState.NEGOTIATING,
    providerCertId,
    consumerCertId,
    fundingOutpoint: null,
    currentTick: 0,
    nSequence: 0,
    domainFlag: 0x0a, // METERING
    createdAt: now,
    updatedAt: now,
  };
}

/**
 * Create a tick proof.
 *
 * @param tick The tick counter value
 * @param hmac HMAC proof (hex string)
 * @param cumulativeSatoshis Total satoshis paid through this tick
 * @returns A new TickProof
 */
export function createTickProof(
  tick: number,
  hmac: string,
  cumulativeSatoshis: number
): TickProof {
  return {
    tick,
    hmac,
    timestamp: Date.now(),
    cumulativeSatoshis,
  };
}

/**
 * Create a settlement record.
 *
 * @param channelId Channel being settled
 * @param finalTick The final tick counter
 * @param providerSignature Hex signature from provider
 * @param consumerSignature Hex signature from consumer
 * @returns A new SettlementRecord
 */
export function createSettlementRecord(
  channelId: string,
  finalTick: number,
  providerSignature: string,
  consumerSignature: string
): SettlementRecord {
  return {
    channelId,
    finalTick,
    providerSignature,
    consumerSignature,
    settlementTxId: null,
  };
}

```
