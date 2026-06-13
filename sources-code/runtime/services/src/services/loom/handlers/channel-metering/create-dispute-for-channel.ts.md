---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/handlers/channel-metering/create-dispute-for-channel.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.118728+00:00
---

# runtime/services/src/services/loom/handlers/channel-metering/create-dispute-for-channel.ts

```ts
/**
 * Spawn the Dispute + Ballot objects when a payment channel enters the
 * `disputed` phase. No-op when the active extension config doesn't
 * declare the relevant type definitions.
 */

import { get, type Atom } from '@semantos/state';

import type { ExtensionConfig } from '../../../../config/extensionConfig';
import type { LoomObject } from '../../../../types/loom';
import { dispatchTo } from '../../loom-atoms';
import type { LoomState } from '../../loom-types';
import { createObjectFromType } from '../object-lifecycle';

export interface CreateDisputeForChannelArgs {
  channelId: string;
  channel: LoomObject;
  config: ExtensionConfig;
  hatId?: string;
  hatCapabilities?: number[];
}

export async function createDisputeForChannel(
  stateAtom: Atom<LoomState>,
  args: CreateDisputeForChannelArgs,
): Promise<void> {
  const disputeTypeDef = args.config.objectTypes.find((t) => t.category === 'governance.dispute');
  if (!disputeTypeDef) return;

  const disputeId = createObjectFromType(
    stateAtom,
    disputeTypeDef,
    undefined,
    args.hatId,
    args.hatCapabilities,
    false,
  );
  if (get(stateAtom).objects.get(disputeId)) {
    dispatchTo(stateAtom, {
      type: 'UPDATE_PAYLOAD',
      objectId: disputeId,
      field: 'subjectObjectId',
      value: args.channelId,
    });
    dispatchTo(stateAtom, {
      type: 'UPDATE_PAYLOAD',
      objectId: disputeId,
      field: 'status',
      value: 'open',
    });
    dispatchTo(stateAtom, {
      type: 'UPDATE_PAYLOAD',
      objectId: disputeId,
      field: 'claimantHatId',
      value: args.hatId || '',
    });
  }

  const ballotTypeDef = args.config.objectTypes.find((t) => t.category === 'governance.ballot');
  if (!ballotTypeDef) return;

  const ballotId = createObjectFromType(
    stateAtom,
    ballotTypeDef,
    undefined,
    args.hatId,
    args.hatCapabilities,
    false,
  );
  if (get(stateAtom).objects.get(ballotId)) {
    dispatchTo(stateAtom, {
      type: 'UPDATE_PAYLOAD',
      objectId: ballotId,
      field: 'motion',
      value: `Channel Settlement Dispute: ${args.channelId}`,
    });
    dispatchTo(stateAtom, {
      type: 'UPDATE_PAYLOAD',
      objectId: ballotId,
      field: 'status',
      value: 'open',
    });
  }

  dispatchTo(stateAtom, {
    type: 'UPDATE_PAYLOAD',
    objectId: args.channelId,
    field: 'disputeId',
    value: disputeId,
  });
  dispatchTo(stateAtom, {
    type: 'UPDATE_PAYLOAD',
    objectId: args.channelId,
    field: 'ballotId',
    value: ballotId,
  });
}

```
