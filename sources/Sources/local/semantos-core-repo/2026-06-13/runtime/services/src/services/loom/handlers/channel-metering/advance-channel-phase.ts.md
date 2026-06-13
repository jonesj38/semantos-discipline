---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/handlers/channel-metering/advance-channel-phase.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.119645+00:00
---

# runtime/services/src/services/loom/handlers/channel-metering/advance-channel-phase.ts

```ts
/**
 * Advance a channel's phase using FlowRunner-style guard evaluation.
 * On `disputed`: spawns a Dispute + Ballot via createDisputeForChannel.
 * On `settled`: triggers settlement via the cashLanes port.
 */

import { get, type Atom } from '@semantos/state';

import type { ExtensionConfig } from '../../../../config/extensionConfig';
import type { ObjectPatch } from '../../../../types/loom';
import type {
  ChannelLifecycleFlow,
  GuardContext,
  PhaseTransitionResult,
} from '../../../FlowRunner';
import { dispatchTo } from '../../loom-atoms';
import type { LoomState } from '../../loom-types';
import type { ChannelMeteringPorts } from './ports';
import { createDisputeForChannel } from './create-dispute-for-channel';
import { recordSettlement } from './record-settlement';

export interface AdvanceChannelPhaseArgs {
  objectId: string;
  lifecycle: ChannelLifecycleFlow;
  targetPhase: string;
  context: GuardContext;
  config?: ExtensionConfig;
  hatId?: string;
  hatCapabilities?: number[];
}

export async function advanceChannelPhase(
  stateAtom: Atom<LoomState>,
  ports: ChannelMeteringPorts,
  args: AdvanceChannelPhaseArgs,
): Promise<PhaseTransitionResult> {
  const obj = get(stateAtom).objects.get(args.objectId);
  if (!obj) return { ok: false, reason: `Object not found: ${args.objectId}` };

  const currentPhase = (obj.payload.status as string) || 'prefunding';
  const result = ports.flowRunner.transitionPhase(
    args.lifecycle,
    currentPhase,
    args.targetPhase,
    args.context,
  );
  if (!result.ok) return result;

  dispatchTo(stateAtom, {
    type: 'UPDATE_PAYLOAD',
    objectId: args.objectId,
    field: 'status',
    value: args.targetPhase,
  });

  const transitionPatch: ObjectPatch = {
    id: `patch-${Date.now()}-transition`,
    kind: 'state_transition',
    timestamp: Date.now(),
    delta: {
      action: 'channel_phase_transition',
      fromPhase: currentPhase,
      toPhase: args.targetPhase,
    },
    ...(args.hatId !== undefined ? { hatId: args.hatId } : {}),
    ...(args.hatCapabilities !== undefined ? { hatCapabilities: args.hatCapabilities } : {}),
  };
  dispatchTo(stateAtom, { type: 'ADD_PATCH', objectId: args.objectId, patch: transitionPatch });

  if (args.targetPhase === 'disputed' && args.config) {
    await createDisputeForChannel(stateAtom, {
      channelId: args.objectId,
      channel: obj,
      config: args.config,
      ...(args.hatId !== undefined ? { hatId: args.hatId } : {}),
      ...(args.hatCapabilities !== undefined ? { hatCapabilities: args.hatCapabilities } : {}),
    });
  }

  if (args.targetPhase === 'settled') {
    await recordSettlement(stateAtom, ports, {
      objectId: args.objectId,
      ...(args.hatId !== undefined ? { hatId: args.hatId } : {}),
      ...(args.hatCapabilities !== undefined ? { hatCapabilities: args.hatCapabilities } : {}),
    });
  }

  return result;
}

```
