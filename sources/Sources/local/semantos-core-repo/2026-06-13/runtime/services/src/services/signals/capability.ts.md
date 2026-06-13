---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/signals/capability.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.111781+00:00
---

# runtime/services/src/services/signals/capability.ts

```ts
/**
 * Capability signal source — AS4.
 *
 * Emits signals when capability tokens are approaching expiry, when a
 * capability state changes (rotation, revocation), or when a
 * capability-required action is queued.
 */
import type { AttentionSignalSource, AttentionSignal } from '../AttentionSignals';
import type { LoomObject } from '../../types/loom';

export interface CapabilityState {
  readonly id: string;
  readonly name: string;
  readonly expiresAt: number | null;
  readonly status: 'active' | 'rotating' | 'revoked';
  readonly attachToObjectId?: string;
  readonly synthesizesObject?: LoomObject;
}

export interface CapabilityProvider {
  list(): CapabilityState[];
  /** Subscribe to state changes. */
  subscribe?(emit: (state: CapabilityState) => void): () => void;
}

export interface CapabilitySourceOptions {
  provider: CapabilityProvider;
  /** Lead time before expiry, ms. Default 7 days. */
  expiryWarningMs?: number;
}

export function createCapabilitySource(opts: CapabilitySourceOptions): AttentionSignalSource {
  const warnMs = opts.expiryWarningMs ?? 7 * 24 * 60 * 60 * 1000;
  return {
    id: 'capability',
    displayName: 'Capability',

    async poll(now: number): Promise<AttentionSignal[]> {
      const out: AttentionSignal[] = [];
      for (const cap of opts.provider.list()) {
        const sig = capabilityToSignal(cap, now, warnMs);
        if (sig) out.push(sig);
      }
      return out;
    },

    subscribe(emit: (signal: AttentionSignal) => void): () => void {
      if (!opts.provider.subscribe) return () => {};
      return opts.provider.subscribe((state) => {
        const sig = capabilityToSignal(state, Date.now(), warnMs);
        if (sig) emit(sig);
      });
    },
  };
}

function capabilityToSignal(cap: CapabilityState, now: number, warnMs: number): AttentionSignal | null {
  if (cap.status === 'revoked') {
    return {
      sourceId: 'capability',
      attachToObjectId: cap.attachToObjectId,
      synthesizesObject: cap.synthesizesObject,
      factor: {
        type: 'extension_signal',
        extensionId: 'capability',
        signal: `Capability ${cap.name} revoked`,
      },
      score: 1.0,
      expiresAt: now + 24 * 60 * 60 * 1000,
    };
  }
  if (cap.status === 'rotating') {
    return {
      sourceId: 'capability',
      attachToObjectId: cap.attachToObjectId,
      factor: {
        type: 'extension_signal',
        extensionId: 'capability',
        signal: `Capability ${cap.name} rotating`,
      },
      score: 0.5,
      expiresAt: now + 60 * 60 * 1000,
    };
  }
  if (cap.expiresAt && cap.expiresAt - now < warnMs) {
    const remainingDays = Math.max(0, Math.floor((cap.expiresAt - now) / (24 * 60 * 60 * 1000)));
    return {
      sourceId: 'capability',
      attachToObjectId: cap.attachToObjectId,
      factor: {
        type: 'extension_signal',
        extensionId: 'capability',
        signal: `Capability ${cap.name} expires in ${remainingDays}d`,
      },
      score: Math.min(1.0, 1 - (cap.expiresAt - now) / warnMs),
      expiresAt: cap.expiresAt,
    };
  }
  return null;
}

```
