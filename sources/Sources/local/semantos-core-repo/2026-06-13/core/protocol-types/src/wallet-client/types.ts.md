---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.871883+00:00
---

# core/protocol-types/src/wallet-client/types.ts

```ts
/**
 * Public types for the BRC-100 wallet client.
 *
 * Shape preserved from the pre-split `wallet-client.ts` so downstream
 * consumers (poker-agent, agent-context, etc.) compile unchanged.
 */

/** Output specification for createAction. */
export interface WalletOutput {
  /** Locking script in hex. Any valid Bitcoin script including OP_RETURN. */
  lockingScript: string;
  /** Amount in satoshis. 0 for OP_RETURN. */
  satoshis: number;
  /** Human-readable description of this output. */
  outputDescription?: string;
  /** Basket for output tracking (BRC-45/46). */
  basket?: string;
  /** Tags for output-level metadata. */
  tags?: string[];
}

/**
 * Array-style input for createAction (metanet-desktop format).
 *
 * metanet-desktop expects `inputs` as an array (it calls .map() internally),
 * not the BRC-4 Record<txid, envelope> format. This matches what the wallet
 * actually implements.
 */
export interface CreateActionInput {
  /** Outpoint to spend: "txid.vout" */
  outpoint: string;
  /** Human-readable description. */
  inputDescription: string;
  /** Estimated unlocking script byte length (for fee calc). Default: 73. */
  unlockingScriptLength?: number;
  /** Hex unlocking script (if pre-signed). */
  unlockingScript?: string;
  /** Sequence number. Default: 0xFFFFFFFF. */
  sequenceNumber?: number;
  /**
   * BEEF-encoded source transaction. Required by metanet-desktop to
   * verify the input UTXO exists and compute fees.
   * Wallet expects number[] (byte array), not hex string.
   */
  sourceTransaction?: number[] | string;
  /** Satoshis of the output being spent (fee calc fallback). */
  sourceSatoshis?: number;
  /** Locking script hex of the output being spent. */
  sourceLockingScript?: string;
}

/**
 * Input specification for createAction (BRC-4).
 * Kept exported for type-only consumers; runtime uses CreateActionInput
 * (the array shape metanet-desktop accepts).
 */
export interface WalletInput {
  outpoint: string;
  outputIndex: number;
  inputDescription: string;
  sequenceNumber?: number;
  unlockingScript?: string;
  unlockingScriptLength?: number;
}

export interface CreateActionRequest {
  description: string;
  labels?: string[];
  outputs: WalletOutput[];
  inputs?: CreateActionInput[];
  inputBEEF?: number[] | string;
}

export interface InternalizeOutput {
  outputIndex: number;
  protocol: 'wallet payment' | 'basket insertion';
  insertionRemittance?: {
    basket: string;
    customInstructions?: string;
    tags?: string[];
  };
  paymentRemittance?: {
    derivationPrefix: string;
    derivationSuffix: string;
    senderIdentityKey: string;
  };
}

export interface InternalizeActionRequest {
  tx: number[] | string;
  outputs: InternalizeOutput[];
  description: string;
  labels?: string[];
}

export interface CreateActionResult {
  txid: string;
  tx?: string | number[];
  rawTx?: string;
  proof?: string;
  signableTransaction?: string;
}

export interface WalletOutputEntry {
  outpoint: string;
  satoshis: number;
  lockingScript?: string;
  customInstructions?: string;
  tags?: string[];
  basket?: string;
  spendable?: boolean;
}

export interface WalletError {
  status: 'error';
  code: string;
  description: string;
}

export interface WalletClientConfig {
  /**
   * Base URL of the wallet's BRC-100 endpoint.
   * - metanet-desktop: 'http://localhost:3321'
   * - bsv-desktop:     'https://localhost:2121'
   */
  baseUrl: string;
  /** Request timeout in ms. Default: 120_000 (2 minutes). */
  timeout?: number;
  /** Optional originator for BRC-100 request context. */
  originator?: string;
  /** Origin header value for CORS validation. Default: 'http://localhost'. */
  origin?: string;
  /** Skip TLS certificate verification (for self-signed bsv-desktop certs). */
  allowSelfSigned?: boolean;
}

export type HttpMethod = 'GET' | 'POST';

/** Inputs every method passes through to the transport. */
export interface RequestSpec {
  method: HttpMethod;
  paths: string[];
  body?: unknown;
}

```
