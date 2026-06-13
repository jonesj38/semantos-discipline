---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/handlers/channel-metering/record-settlement.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.119941+00:00
---

# runtime/services/src/services/loom/handlers/channel-metering/record-settlement.ts

```ts
/**
 * Record settlement — calls CashLanes (prepare/sign/broadcast/confirm)
 * and adds settlement evidence patches to the channel object.
 */

import { get, type Atom } from '@semantos/state';

import type { ObjectPatch } from '../../../../types/loom';
import { dispatchTo } from '../../loom-atoms';
import type { LoomState } from '../../loom-types';
import type { CashLanesPort } from '../../ports';

export interface RecordSettlementArgs {
  objectId: string;
  hatId?: string;
  hatCapabilities?: number[];
}

export async function recordSettlement(
  stateAtom: Atom<LoomState>,
  ports: { cashLanes: CashLanesPort },
  args: RecordSettlementArgs,
): Promise<void> {
  const obj = get(stateAtom).objects.get(args.objectId);
  if (!obj) return;

  const channelCertId = (obj.payload.channelCertId as string) || '';
  const balanceTracking = (obj.payload.balanceTracking as Record<string, number>) || {};
  const ownerAmount = Object.values(balanceTracking).reduce((a, b) => a + b, 0);

  const settlementTx = await ports.cashLanes.prepareCashLanesSettlement(
    args.objectId,
    ownerAmount,
    0,
    0,
  );
  const sigs = await ports.cashLanes.collectCashLanesSignatures(
    args.objectId,
    channelCertId,
    settlementTx,
  );
  const settlement = await ports.cashLanes.broadcastCashLanesSettlement(
    args.objectId,
    settlementTx,
    sigs,
  );

  const settlementPatch: ObjectPatch = {
    id: `patch-${Date.now()}-settlement`,
    kind: 'channel_settlement',
    timestamp: Date.now(),
    delta: {
      txid: settlement.txid,
      broadcastTime: settlement.broadcastTime,
      status: settlement.status,
    },
    ...(args.hatId !== undefined ? { hatId: args.hatId } : {}),
    ...(args.hatCapabilities !== undefined ? { hatCapabilities: args.hatCapabilities } : {}),
  };
  dispatchTo(stateAtom, { type: 'ADD_PATCH', objectId: args.objectId, patch: settlementPatch });
  dispatchTo(stateAtom, {
    type: 'UPDATE_PAYLOAD',
    objectId: args.objectId,
    field: 'settlementTxId',
    value: settlement.txid,
  });

  const confirmation = await ports.cashLanes.awaitCashLanesConfirmation(settlement.txid);
  if (confirmation.confirmed) {
    dispatchTo(stateAtom, {
      type: 'UPDATE_PAYLOAD',
      objectId: args.objectId,
      field: 'settlementConfirmed',
      value: true,
    });
  }
}

```
