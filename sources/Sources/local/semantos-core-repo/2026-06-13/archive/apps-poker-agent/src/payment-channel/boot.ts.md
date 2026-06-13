---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/boot.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.765053+00:00
---

# archive/apps-poker-agent/src/payment-channel/boot.ts

```ts
/**
 * Boot — wires every effect atom into the effect bus at startup.
 *
 * Idempotent: a second call returns the same handles. Tests that need
 * to swap effects call `bootEffects({ persistStore, swap: { ... } })`
 * — passing a per-effect override that takes the place of the default
 * factory.
 *
 * `bindDefaultPaymentChannelPorts` (prompt 14) covers the *port*
 * wiring; this module covers the *effect-atom* wiring on top.
 */

import { bindDefaultPaymentChannelPorts } from './ports/default-bindings';
import {
  makeBroadcastEffect,
  makeFeeCreditEffect,
  makeLogEffect,
  makePersistEffect,
  makeSpvEffect,
  type BroadcastEffect,
  type FeeCreditEffect,
  type LogEffect,
  type PersistEffect,
  type PersistStore,
  type SpvEffect,
} from './effects';

export interface EffectHandles {
  persist: PersistEffect;
  broadcast: BroadcastEffect;
  spv: SpvEffect;
  feeCredit: FeeCreditEffect;
  log: LogEffect;
}

export interface BootEffectsOptions {
  /** Required — persist-effect's storage backend. */
  persistStore: PersistStore;
  /** Forwarded to `bindDefaultPaymentChannelPorts`. */
  ports?: Parameters<typeof bindDefaultPaymentChannelPorts>[0];
  /** Test-only swap-ins; replace one or more default factories. */
  swap?: Partial<EffectHandles>;
  /** Set to `true` to skip auto-binding ports (tests that bind doubles). */
  skipPortBinding?: boolean;
}

let cached: EffectHandles | null = null;

export function bootEffects(opts: BootEffectsOptions): EffectHandles {
  if (cached) return cached;

  if (!opts.skipPortBinding) {
    bindDefaultPaymentChannelPorts(opts.ports ?? {});
  }

  const handles: EffectHandles = {
    persist: opts.swap?.persist ?? makePersistEffect({ store: opts.persistStore }),
    broadcast: opts.swap?.broadcast ?? makeBroadcastEffect(),
    spv: opts.swap?.spv ?? makeSpvEffect(),
    feeCredit: opts.swap?.feeCredit ?? makeFeeCreditEffect(),
    log: opts.swap?.log ?? makeLogEffect(),
  };
  cached = handles;
  return handles;
}

/** Tear down + clear cache. Idempotent. */
export function shutdownEffects(): void {
  if (!cached) return;
  cached.persist.dispose();
  cached.broadcast.dispose();
  cached.spv.dispose();
  cached.feeCredit.dispose();
  cached.log.dispose();
  cached = null;
}

/** Test inspector — returns null until `bootEffects` runs. */
export function currentEffects(): EffectHandles | null {
  return cached;
}

```
