---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/handlers/channel-metering/record-channel-transaction.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.120581+00:00
---

# runtime/services/src/services/loom/handlers/channel-metering/record-channel-transaction.ts

```ts
/**
 * Record a metered transaction on the channel's evidence chain. Each
 * transaction includes a witness hash chained off the previous patch
 * id, the amount, and the channelCertId; balance + cumulative + tick
 * payload fields are updated atomically (one dispatch each).
 */

import { get, type Atom } from '@semantos/state';

import type { ObjectPatch } from '../../../../types/loom';
import { dispatchTo } from '../../loom-atoms';
import type { LoomState } from '../../loom-types';
import type { HashPort } from '../../ports';

export interface RecordChannelTransactionArgs {
  objectId: string;
  from: string;
  to: string;
  amount: number;
  meterUnit: string;
  hatId?: string;
  hatCapabilities?: number[];
}

export async function recordChannelTransaction(
  stateAtom: Atom<LoomState>,
  ports: { hash: HashPort },
  args: RecordChannelTransactionArgs,
): Promise<void> {
  const obj = get(stateAtom).objects.get(args.objectId);
  if (!obj) throw new Error(`Object not found: ${args.objectId}`);

  const channelCertId = (obj.payload.channelCertId as string) || '';
  const lastPatch = obj.patches[obj.patches.length - 1];
  const prevHash = lastPatch?.id || '';

  const witnessHash = await ports.hash.sha256hex(
    prevHash + String(args.amount) + channelCertId,
  );

  const txPatch: ObjectPatch = {
    id: `patch-${Date.now()}-tx`,
    kind: 'channel_transaction',
    timestamp: Date.now(),
    delta: {
      from: args.from,
      to: args.to,
      amount: args.amount,
      meterUnit: args.meterUnit,
      witnessHash,
    },
    ...(args.hatId !== undefined ? { hatId: args.hatId } : {}),
    ...(args.hatCapabilities !== undefined ? { hatCapabilities: args.hatCapabilities } : {}),
  };
  dispatchTo(stateAtom, { type: 'ADD_PATCH', objectId: args.objectId, patch: txPatch });

  const balanceTracking = (obj.payload.balanceTracking as Record<string, number>) || {};
  balanceTracking[args.to] = (balanceTracking[args.to] || 0) + args.amount;
  dispatchTo(stateAtom, {
    type: 'UPDATE_PAYLOAD',
    objectId: args.objectId,
    field: 'balanceTracking',
    value: { ...balanceTracking },
  });

  const newCumulative = ((obj.payload.cumulativeSatoshis as number) || 0) + args.amount;
  dispatchTo(stateAtom, {
    type: 'UPDATE_PAYLOAD',
    objectId: args.objectId,
    field: 'cumulativeSatoshis',
    value: newCumulative,
  });
  dispatchTo(stateAtom, {
    type: 'UPDATE_PAYLOAD',
    objectId: args.objectId,
    field: 'currentTick',
    value: ((obj.payload.currentTick as number) || 0) + 1,
  });
}

```
