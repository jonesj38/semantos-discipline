---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/atoms.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.765621+00:00
---

# archive/apps-poker-agent/src/payment-channel/atoms.ts

```ts
/**
 * Payment-channel atoms — observable state surface for the facade.
 *
 * Three atoms + one event bus per the prompt-15 spec:
 *
 *   channelStateAtom   — current `ChannelState` (UNFUNDED → CLOSED).
 *   artifactsAtom      — frozen funding artifacts once FUNDED.
 *   channelEventsBus   — every `ChannelEvent` accepted by the reducer.
 *
 * Atoms are scoped per-channel via `getChannelAtoms(channelId)`. This
 * keeps the runtime simple (no global "currently active channel" hack)
 * while still letting effects subscribe to a single channel by id.
 *
 * The reducer (prompt 13) is pure and returns commands; the facade
 * (this prompt) writes those commands into atoms + the effect bus, and
 * effect atoms (`effects/*.ts`) translate them into side-effects via the
 * prompt-14 ports.
 */

import { atom, eventBus, type Atom, type EventBus } from '@semantos/state';

import {
  initialChannelState,
  type ChannelArtifacts,
  type ChannelEvent,
  type ChannelRole,
  type ChannelState,
  type ChannelStateValue,
} from './fsm';

export interface ChannelAtoms {
  /** Channel id this bundle is scoped to. */
  channelId: string;
  /** The full reducer state value (state + artifacts + spv + keyIds). */
  stateAtom: Atom<ChannelStateValue>;
  /** Convenience projection — just the state name. */
  channelStateAtom: Atom<ChannelState>;
  /** Frozen artifacts once FUNDED. Null until then. */
  artifactsAtom: Atom<ChannelArtifacts | null>;
  /** Bus of every accepted event (for log/observers). */
  channelEventsBus: EventBus<ChannelEvent>;
}

const registry = new Map<string, ChannelAtoms>();

/**
 * Get (or create) the atom bundle for a channel id. Idempotent — repeat
 * calls return the same bundle so subscribers see the same instance.
 */
export function getChannelAtoms(
  channelId: string,
  role: ChannelRole = 'consumer',
): ChannelAtoms {
  const existing = registry.get(channelId);
  if (existing) return existing;

  const initial = initialChannelState(channelId, role);
  const bundle: ChannelAtoms = {
    channelId,
    stateAtom: atom<ChannelStateValue>(initial),
    channelStateAtom: atom<ChannelState>(initial.state),
    artifactsAtom: atom<ChannelArtifacts | null>(null),
    channelEventsBus: eventBus<ChannelEvent>(),
  };
  registry.set(channelId, bundle);
  return bundle;
}

/** Test helper — wipes the registry between cases. */
export function resetChannelAtoms(): void {
  registry.clear();
}

/** Read-only listing of currently registered channel ids. */
export function listChannelIds(): string[] {
  return Array.from(registry.keys());
}

```
