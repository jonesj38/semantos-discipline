---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.765334+00:00
---

# archive/apps-poker-agent/src/payment-channel/index.ts

```ts
/**
 * Payment-channel public surface — atoms + facade + effects + ports.
 *
 * The legacy `apps/poker-agent/src/payment-channel.ts` (poker
 * `PaymentChannelManager`) remains as the existing 2-of-2 multisig
 * orchestrator for kernel-validated tick proofs. Future poker-stack
 * prompts (Phase 7) will retire it onto the new facade. For now the
 * two coexist:
 *
 *   - new code should `import { fund, settle, close, getChannelAtoms }
 *     from './payment-channel'` to use the reducer-backed facade.
 *   - existing poker call sites continue to use `PaymentChannelManager`
 *     directly until their owning prompt migrates them.
 */

export {
  getChannelAtoms,
  resetChannelAtoms,
  listChannelIds,
  type ChannelAtoms,
} from './atoms';

export {
  bindConsumer,
  close,
  dispatch,
  extract,
  fund,
  getState,
  internalizeConsumer,
  internalizeProvider,
  settle,
  type BindConsumerArgs,
  type CloseArgs,
  type ExtractArgs,
  type FundArgs,
  type SettleArgs,
} from './facade';

export {
  bootEffects,
  shutdownEffects,
  currentEffects,
  type BootEffectsOptions,
  type EffectHandles,
} from './boot';

// Re-export ports + fsm + effects barrels for convenience.
export * from './fsm';
export * from './effects';
export * from './ports';

```
