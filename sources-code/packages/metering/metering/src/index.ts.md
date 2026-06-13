---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/metering/metering/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.486065+00:00
---

# packages/metering/metering/src/index.ts

```ts
/**
 * Plexus metering module: Metered Flow Protocol channel FSM and settlement logic.
 *
 * Phase 29.5: Added kernel-enforced settlement policies, host functions,
 * PolicyEnforcedChannel wrapper, and HostFunctionProvider.
 */

export * from './channel-fsm.js';
export * from './settlement.js';

// Phase 29.5: Kernel enforcement
export * from './policies.js';
export { registerMeteringHostFunctions } from './host-functions.js';
export { PolicyEnforcedChannel, type SettlementContext, type DisputeContext, type ResolveContext } from './policy-enforced-channel.js';
export { createMeteringHostFunctionProvider, MeteringHostFunctionProvider } from './kernel-provider.js';

```
