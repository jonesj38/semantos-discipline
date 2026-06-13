---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/fsm/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.792963+00:00
---

# archive/apps-poker-agent/src/payment-channel/fsm/index.ts

```ts
/**
 * Payment-channel FSM barrel — public surface for the split.
 */

export { channelReducer } from './reducer';
export {
  initialChannelState,
  type ChannelArtifacts,
  type ChannelCommand,
  type ChannelEvent,
  type ChannelRole,
  type ChannelState,
  type ChannelStateValue,
  type ReducerResult,
  type RoleScopedKeyId,
  type SpvProof,
} from './types';
export {
  assertArtifactsImmutable,
  assertFundingInvariants,
  assertKeyIds,
  assertNoP2SH,
  assertRoleScopedKeyId,
  assertSpvAttached,
} from './invariants';

```
