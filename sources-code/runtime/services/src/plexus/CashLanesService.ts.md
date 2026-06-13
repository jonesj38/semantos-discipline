---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/plexus/CashLanesService.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.101473+00:00
---

# runtime/services/src/plexus/CashLanesService.ts

```ts
/**
 * CashLanesService — thin settlement bridge delegating Bitcoin mechanics to CashLanes.
 *
 * All Bitcoin operations (multisig, signing, coin management, broadcast) live in CashLanes.
 * The workbench only calls these methods and records results as evidence chain patches.
 *
 * Currently fully stubbed — no CashLanes backend required.
 */

/** SHA-256 hex digest of a string. Browser-native via Web Crypto API. */
async function sha256hex(input: string): Promise<string> {
  const encoded = new TextEncoder().encode(input);
  const hashBuffer = await crypto.subtle.digest('SHA-256', encoded);
  const hashArray = new Uint8Array(hashBuffer);
  return Array.from(hashArray).map(b => b.toString(16).padStart(2, '0')).join('');
}

export interface SettlementTx {
  unsignedTx: string;
  channelId: string;
  ownerAmount: number;
  counterpartyAmount: number;
}

export interface SettlementSignatures {
  ownerSig: string;
  counterpartySig: string;
}

export interface SettlementResult {
  txid: string;
  broadcastTime: number;
  status: 'broadcast' | 'confirmed';
}

export interface ConfirmationResult {
  confirmed: boolean;
  blockHeight: number;
  timestamp: number;
}

export class CashLanesService {
  /**
   * Prepare a settlement transaction splitting channel funds between owner and counterparty.
   * CashLanes handles 2-of-2 multisig input construction and output splitting.
   */
  async prepareCashLanesSettlement(
    channelId: string,
    ownerAmount: number,
    counterpartyAmount: number,
    feePercent: number,
  ): Promise<SettlementTx> {
    const fee = Math.floor((ownerAmount + counterpartyAmount) * (feePercent / 100));
    const unsignedTx = await sha256hex(`settlement:${channelId}:${ownerAmount}:${counterpartyAmount}:${Date.now()}`);

    return {
      unsignedTx,
      channelId,
      ownerAmount: ownerAmount - Math.floor(fee / 2),
      counterpartyAmount: counterpartyAmount - Math.ceil(fee / 2),
    };
  }

  /**
   * Collect signatures from both parties for the settlement transaction.
   * CashLanes coordinates the signing ceremony.
   */
  async collectCashLanesSignatures(
    channelId: string,
    channelCertId: string,
    settlementTx: SettlementTx,
  ): Promise<SettlementSignatures> {
    const ownerSig = await sha256hex(`owner_sig:${channelCertId}:${settlementTx.unsignedTx}`);
    const counterpartySig = await sha256hex(`counterparty_sig:${channelId}:${settlementTx.unsignedTx}`);

    return { ownerSig, counterpartySig };
  }

  /**
   * Broadcast the signed settlement transaction to the Bitcoin network.
   * CashLanes handles serialization and network broadcast.
   */
  async broadcastCashLanesSettlement(
    channelId: string,
    settlementTx: SettlementTx,
    signatures: SettlementSignatures,
  ): Promise<SettlementResult> {
    const txid = await sha256hex(`txid:${channelId}:${signatures.ownerSig}:${signatures.counterpartySig}:${Date.now()}`);

    return {
      txid,
      broadcastTime: Date.now(),
      status: 'broadcast',
    };
  }

  /**
   * Await on-chain confirmation of the settlement transaction.
   * CashLanes monitors the blockchain for the specified number of confirmations.
   */
  async awaitCashLanesConfirmation(
    txid: string,
    _confirmations = 6,
  ): Promise<ConfirmationResult> {
    return {
      confirmed: true,
      blockHeight: 800000 + Math.floor(Date.now() / 600000),
      timestamp: Date.now(),
    };
  }
}

// === Singleton ===

let cashLanesService: CashLanesService | null = null;

export function initializeCashLanesService(): CashLanesService {
  cashLanesService = new CashLanesService();
  return cashLanesService;
}

export function getCashLanesService(): CashLanesService {
  if (!cashLanesService) {
    cashLanesService = new CashLanesService();
  }
  return cashLanesService;
}

```
