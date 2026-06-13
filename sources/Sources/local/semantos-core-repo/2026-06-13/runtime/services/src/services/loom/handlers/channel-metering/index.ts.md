---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/handlers/channel-metering/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.119035+00:00
---

# runtime/services/src/services/loom/handlers/channel-metering/index.ts

```ts
/**
 * Channel-metering handler barrel — splits the Phase 18 surface into
 * one file per entry point so each stays under the 200-LOC ceiling.
 */

export { createPaymentChannel, type CreatePaymentChannelArgs } from './create-payment-channel';
export { advanceChannelPhase, type AdvanceChannelPhaseArgs } from './advance-channel-phase';
export {
  recordChannelTransaction,
  type RecordChannelTransactionArgs,
} from './record-channel-transaction';
export { recordSettlement, type RecordSettlementArgs } from './record-settlement';
export {
  createDisputeForChannel,
  type CreateDisputeForChannelArgs,
} from './create-dispute-for-channel';
export type { ChannelMeteringPorts } from './ports';

```
