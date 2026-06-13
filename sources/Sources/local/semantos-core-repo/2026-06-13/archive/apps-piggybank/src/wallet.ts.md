---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-piggybank/src/wallet.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.720314+00:00
---

# archive/apps-piggybank/src/wallet.ts

```ts
/**
 * Wallet Types
 *
 * On-device wallet state for the piggy bank. Tracks UTXOs via stored
 * BEEF cells, manages the kid's balance, and handles spending.
 *
 * The piggy bank is a receive-heavy wallet: most of the time it's
 * accepting payments. Spending is less frequent and optionally requires
 * parent co-signature.
 */

// ── Stored UTXO ─────────────────────────────────────────────────────────────

/**
 * A UTXO known to the piggy bank, backed by a stored BEEF cell.
 *
 * The device stores the full SPV proof (BEEF envelope) in flash, so it
 * can prove ownership and validity without going online.
 */
export interface StoredUtxo {
  /** Transaction ID (hex, 32 bytes, big-endian display order) */
  txid: string;

  /** Output index within the transaction */
  vout: number;

  /** Value in satoshis */
  satoshis: number;

  /** Locking script (hex) — typically P2PKH to the kid's derived key */
  lockingScriptHex: string;

  /** Block height where this tx was mined (from BUMP) */
  blockHeight: number;

  /** Unix timestamp (ms) when this UTXO was received on device */
  receivedAt: number;

  /** Flash offset where the BEEF cell is stored (for retrieval) */
  cellStorageKey: string;

  /** Whether this UTXO has been spent */
  spent: boolean;

  /** If spent: the txid of the spending transaction */
  spentInTxid: string | null;
}

// ── Wallet State ────────────────────────────────────────────────────────────

/**
 * Aggregate wallet state, reconstructed from stored UTXOs.
 */
export interface WalletState {
  /** All known UTXOs (spent and unspent) */
  utxos: StoredUtxo[];

  /** Total confirmed balance (sum of unspent UTXOs) */
  confirmedBalanceSats: number;

  /** Number of transactions received */
  totalReceived: number;

  /** Number of transactions sent */
  totalSent: number;

  /** Cumulative satoshis ever received */
  lifetimeReceivedSats: number;

  /** Cumulative satoshis ever spent */
  lifetimeSpentSats: number;

  /** Current receiving address (hex P2PKH address) */
  currentReceivingAddress: string;

  /** Index in the PAYMENT_RECEIPT derivation path for the current address */
  currentAddressIndex: number;
}

// ── Spend Request ───────────────────────────────────────────────────────────

export enum SpendStatus {
  /** Created on device, awaiting parent approval (if required) */
  PENDING_APPROVAL = 'PENDING_APPROVAL',
  /** Parent approved, ready to broadcast */
  APPROVED = 'APPROVED',
  /** Parent rejected */
  REJECTED = 'REJECTED',
  /** Transaction broadcast successfully */
  BROADCAST = 'BROADCAST',
  /** Transaction confirmed in a block */
  CONFIRMED = 'CONFIRMED',
}

/**
 * A request to spend from the piggy bank.
 *
 * Created on the kid's device when they want to buy something.
 * May require parent co-signature depending on spending limits.
 */
export interface SpendRequest {
  /** Unique request ID */
  requestId: string;

  /** Hex cert ID of the kid requesting the spend */
  kidCertId: string;

  /** Destination address (hex) */
  destinationAddress: string;

  /** Amount in satoshis */
  amountSats: number;

  /** Fee in satoshis */
  feeSats: number;

  /** UTXO outpoints selected for this spend (txid:vout format) */
  selectedUtxos: string[];

  /** Current status */
  status: SpendStatus;

  /** Optional memo ("Birthday present for dad") */
  memo: string;

  /** Unix timestamp (ms) when request was created */
  createdAt: number;

  /** Kid's partial signature (hex, for parent co-sign flow) */
  kidSignatureHex: string | null;

  /** Parent's co-signature (hex, if required and approved) */
  parentSignatureHex: string | null;

  /** Final signed transaction (hex, ready for broadcast) */
  signedTxHex: string | null;
}

// ── Payment QR ──────────────────────────────────────────────────────────────

/**
 * Data encoded in the payment QR code displayed on the device.
 *
 * Format: "bitcoin:<address>?sv&amount=<bsv>"
 * The BIP21-style URI is compatible with standard BSV wallets.
 */
export interface PaymentQrData {
  /** BSV address (base58check) */
  address: string;

  /** Requested amount in BSV (null = any amount) */
  amountBsv: number | null;

  /** Kid name for display on the payer's wallet */
  label: string;

  /** Optional message ("Pocket money for Mia") */
  message: string | null;
}

/**
 * Encode payment data as a BIP21 URI string for QR display.
 */
export function encodePaymentUri(data: PaymentQrData): string {
  let uri = `bitcoin:${data.address}?sv`;
  if (data.amountBsv !== null) {
    uri += `&amount=${data.amountBsv}`;
  }
  if (data.label) {
    uri += `&label=${encodeURIComponent(data.label)}`;
  }
  if (data.message) {
    uri += `&message=${encodeURIComponent(data.message)}`;
  }
  return uri;
}

```
