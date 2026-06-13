---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/brc100-wallet-stub.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.880086+00:00
---

# core/protocol-types/src/adapters/brc100-wallet-stub.ts

```ts
/**
 * BRC-100 Wallet Stub — interface-compatible stub for Phase 3 settlement.
 *
 * Provides the BRC100WalletAdapter interface contract for atomic settlement.
 * StubBRC100Wallet returns deterministic stub responses; replaced with
 * real wallet integration in Phase 4.
 *
 * @module @semantos/protocol-types/adapters/brc100-wallet-stub
 */

// ── Interface ─────────────────────────────────────────────────

export interface SettlementParams {
  /** Payer (customer) certId. */
  payerCertId: string;
  /** Payee (business/founder) certId. */
  payeeCertId: string;
  /** Settlement amount. */
  amount: number;
  /** Currency code. */
  currency: string;
  /** Associated Order ID. */
  orderId: string;
  /** Unique nonce for idempotency. */
  nonce?: string;
}

export interface SettlementResult {
  /** Transaction ID (BSV TXID or stub placeholder). */
  txid: string;
  /** Settlement status. */
  status: 'stub' | 'pending' | 'confirmed' | 'failed';
  /** Timestamp of settlement attempt. */
  timestamp: string;
  /** Error message if status is 'failed'. */
  error?: string;
}

export interface VerificationResult {
  /** Whether the transaction is confirmed. */
  confirmed: boolean;
  /** Block height (if confirmed). */
  blockHeight?: number;
  /** Number of confirmations. */
  confirmations?: number;
}

/**
 * Adapter interface for BRC-100 settlement operations.
 * Implementors must provide atomic signing and verification.
 */
export interface BRC100WalletAdapter {
  /** Sign and broadcast a settlement transaction. */
  signSettlement(params: SettlementParams): Promise<SettlementResult>;
  /** Verify the status of a previously broadcast transaction. */
  verifySettlement(txid: string): Promise<VerificationResult>;
  /** Check if the wallet is unlocked and ready for signing. */
  isReady(): Promise<boolean>;
}

// ── Stub Implementation ───────────────────────────────────────

/**
 * Stub BRC-100 wallet for Phase 3 development.
 * Returns deterministic responses without actual BSV interaction.
 */
export class StubBRC100Wallet implements BRC100WalletAdapter {
  private settlements = new Map<string, SettlementResult>();

  async signSettlement(params: SettlementParams): Promise<SettlementResult> {
    const txid = `stub-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
    const result: SettlementResult = {
      txid,
      status: 'stub',
      timestamp: new Date().toISOString(),
    };
    this.settlements.set(txid, result);
    return result;
  }

  async verifySettlement(txid: string): Promise<VerificationResult> {
    const settlement = this.settlements.get(txid);
    if (!settlement) {
      return { confirmed: false };
    }
    // Stub: treat all settlements as confirmed after creation
    return {
      confirmed: true,
      blockHeight: 800000 + Math.floor(Math.random() * 1000),
      confirmations: 10,
    };
  }

  async isReady(): Promise<boolean> {
    return true;
  }
}

// ── Factory ───────────────────────────────────────────────────

let walletInstance: BRC100WalletAdapter | null = null;

/** Get the BRC-100 wallet adapter (stub by default). */
export function getBRC100Wallet(): BRC100WalletAdapter {
  if (!walletInstance) {
    walletInstance = new StubBRC100Wallet();
  }
  return walletInstance;
}

/** Replace the wallet adapter (for testing or real implementation). */
export function setBRC100Wallet(wallet: BRC100WalletAdapter): void {
  walletInstance = wallet;
}

```
