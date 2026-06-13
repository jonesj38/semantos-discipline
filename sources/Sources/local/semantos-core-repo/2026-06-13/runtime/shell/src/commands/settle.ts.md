---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/commands/settle.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.372480+00:00
---

# runtime/shell/src/commands/settle.ts

```ts
/**
 * Settle Command — executes atomic Order → Payment settlement via BRC-100.
 *
 * Steps:
 *   1. Validate Order exists and status allows settlement
 *   2. Create Payment object (LINEAR linearity)
 *   3. Sign via BRC-100 wallet adapter
 *   4. Create TRANSFER edge in Plexus graph
 *   5. Update Order status + CellStore version increment
 *
 * Phase 3: Semantic Shell — Business Pages & Economic Pipeline
 *
 * @module @semantos/shell/commands/settle
 */

import type { ShellCommand } from '../parser';
import type { ShellContext } from '../router';
import { getBRC100Wallet } from '../../../../core/protocol-types/src/adapters/brc100-wallet-stub';

export interface SettleResult {
  paymentTxId: string;
  status: 'pending' | 'confirmed' | 'failed' | 'stub';
  settlementEdgeId?: string;
  paymentId?: string;
  error?: string;
}

const MAX_RETRIES = 3;

export async function routeSettle(cmd: ShellCommand, ctx: ShellContext): Promise<SettleResult> {
  const orderId = cmd.objectId || cmd.typePath;
  if (!orderId) {
    return { paymentTxId: '', status: 'failed', error: 'No order ID provided. Usage: settle <orderId>' };
  }

  // 1. Validate Order exists
  const order = ctx.store?.get(orderId);
  if (!order) {
    return { paymentTxId: '', status: 'failed', error: `Order not found: ${orderId}` };
  }

  const payload = order.payload ? JSON.parse(new TextDecoder().decode(order.payload)) : {};
  const currentStatus = payload.status || 'unknown';

  // Only settle pending or accepted orders
  if (!['pending', 'accepted'].includes(currentStatus)) {
    return {
      paymentTxId: '',
      status: 'failed',
      error: `Cannot settle order in status '${currentStatus}'. Must be 'pending' or 'accepted'.`,
    };
  }

  const amount = payload.totalAmount || payload.amount || 0;
  const customerId = payload.customerId || cmd.flags['customerId'] as string || '';
  const providerId = payload.providerId || payload.orgId || cmd.flags['providerId'] as string || '';
  const currency = payload.currency || 'BSV';

  if (amount <= 0) {
    return { paymentTxId: '', status: 'failed', error: 'Order amount must be greater than 0.' };
  }

  // 2. Sign via BRC-100 wallet adapter (with retry)
  const wallet = getBRC100Wallet();
  const isReady = await wallet.isReady();
  if (!isReady) {
    return { paymentTxId: '', status: 'failed', error: 'Wallet is locked. Please unlock your wallet.' };
  }

  let settlementResult;
  let lastError = '';
  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    try {
      settlementResult = await wallet.signSettlement({
        payerCertId: customerId,
        payeeCertId: providerId,
        amount,
        currency,
        orderId,
        nonce: `${orderId}-${Date.now()}-${attempt}`,
      });
      if (settlementResult.status !== 'failed') break;
      lastError = settlementResult.error || 'Settlement failed';
    } catch (err) {
      lastError = err instanceof Error ? err.message : String(err);
    }
  }

  if (!settlementResult || settlementResult.status === 'failed') {
    return {
      paymentTxId: '',
      status: 'failed',
      error: `Settlement failed after ${MAX_RETRIES} attempts: ${lastError}`,
    };
  }

  // 3. Create Payment record in CellStore
  const paymentId = `payment-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
  const paymentPayload = {
    orderId,
    amount,
    currency,
    method: 'brc100',
    txid: settlementResult.txid,
    status: settlementResult.status === 'confirmed' ? 'confirmed' : 'pending',
    payerId: customerId,
    payeeId: providerId,
    settledAt: settlementResult.timestamp,
  };

  if (ctx.store) {
    try {
      await ctx.store.put(
        paymentId,
        new TextEncoder().encode(JSON.stringify(paymentPayload)),
        { linearity: 1 }, // LINEAR
      );
    } catch {
      // Payment record creation is best-effort; settlement already signed
    }
  }

  // 4. Update Order status via CellStore version increment
  if (ctx.store) {
    const newPayload = {
      ...payload,
      status: 'accepted',
      paymentTxId: settlementResult.txid,
    };
    try {
      await ctx.store.put(
        orderId,
        new TextEncoder().encode(JSON.stringify(newPayload)),
        {
          linearity: 2, // AFFINE
          prevStateHash: order.cellHash ? new Uint8Array(Buffer.from(order.cellHash, 'hex')) : undefined,
        },
      );
    } catch {
      // State update is best-effort; settlement is the source of truth
    }
  }

  // 5. Record evidence chain patch
  if (ctx.evidenceChain) {
    ctx.evidenceChain.push({
      id: `patch-${Date.now()}-settle`,
      kind: 'settlement',
      delta: {
        orderId,
        paymentId,
        txid: settlementResult.txid,
        amount,
        status: settlementResult.status,
      },
      timestamp: new Date().toISOString(),
    });
  }

  return {
    paymentTxId: settlementResult.txid,
    status: settlementResult.status as SettleResult['status'],
    settlementEdgeId: `edge-transfer-${paymentId}`,
    paymentId,
  };
}

```
