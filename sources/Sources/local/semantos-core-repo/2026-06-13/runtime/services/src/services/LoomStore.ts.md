---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/LoomStore.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.094781+00:00
---

# runtime/services/src/services/LoomStore.ts

```ts
/**
 * LoomStore — renderer-agnostic state facade. @deprecated prefer
 * `loomStateAtom` + `dispatch` from `./loom/loom-atoms.ts`. Each method
 * is a thin wrapper over a handler from `./loom/handlers/*` operating
 * on a state atom; `new LoomStore()` gets a fresh per-instance atom
 * (shell sessions), while the singleton in `services/index.ts` opts
 * into the shared `loomStateAtom` so panels share state.
 */
import { atom, get, subscribe, type Atom } from '@semantos/state';
import { TypedEventEmitter } from './TypedEventEmitter';
import {
  freshInitialState, loomStateAtom, dispatchTo,
  type LoomState, type LoomAction,
} from './loom/loom-atoms';
import type {
  ChannelLifecycleFlow, GuardContext, PhaseTransitionResult,
} from './FlowRunner';
import type { ObjectTypeDefinition, ExtensionConfig } from '../config/extensionConfig';
import type { LoomObject } from '../types/loom';
import * as ol from './loom/handlers/object-lifecycle';
import { resolveDisputeReclassification as resolveDisputeReclassificationHandler } from './loom/handlers/dispute-resolution';
import * as cm from './loom/handlers/channel-metering';
import { getLivePorts } from './loom/live-ports';

type StoreEvents = { change: [LoomState] };

export interface LoomStoreOptions {
  stateAtom?: Atom<LoomState>;
  bridgeEventsToAtom?: boolean;
}

export class LoomStore extends TypedEventEmitter<StoreEvents> {
  private readonly stateAtom: Atom<LoomState>;
  private readonly counter: ol.CardCounter = ol.makeCardCounter();

  constructor(opts: LoomStoreOptions = {}) {
    super();
    this.stateAtom = opts.stateAtom ?? atom<LoomState>(freshInitialState());
    if (opts.bridgeEventsToAtom !== false) {
      subscribe(this.stateAtom, (next) => this.emit('change', next));
    }
  }

  getState(): LoomState { return get(this.stateAtom); }
  getSnapshot = (): LoomState => get(this.stateAtom);
  stableSubscribe = (listener: () => void): (() => void) =>
    this.on('change', () => listener());
  dispatch(action: LoomAction): void { dispatchTo(this.stateAtom, action); }

  createObjectFromType(
    typeDef: ObjectTypeDefinition,
    ownerIdBytes?: Uint8Array,
    hatId?: string,
    hatCapabilities?: number[],
    openAsCardOpt = true,
  ): string {
    return ol.createObjectFromType(
      this.stateAtom, typeDef, ownerIdBytes, hatId, hatCapabilities, openAsCardOpt,
    );
  }

  openAsCard(objectId: string): void {
    ol.openAsCard(this.stateAtom, this.counter, objectId);
  }

  getSelectedObject(): LoomObject | null {
    return ol.getSelectedObject(this.stateAtom);
  }

  transitionVisibility(
    objectId: string,
    newVisibility: 'draft' | 'published' | 'revoked',
    hatCapabilities?: number[],
  ): void {
    ol.transitionVisibility(this.stateAtom, objectId, newVisibility, hatCapabilities);
  }

  consumeObject(objectId: string, hatId: string, hatCapabilities?: number[]): void {
    ol.consumeObject(this.stateAtom, objectId, hatId, hatCapabilities);
  }

  resolveDisputeReclassification(
    disputeObjectId: string,
    hatId: string,
    hatCapabilities?: number[],
  ): boolean {
    return resolveDisputeReclassificationHandler(
      this.stateAtom, disputeObjectId, hatId, hatCapabilities,
    );
  }

  async createPaymentChannel(
    typeDef: ObjectTypeDefinition,
    counterpartyCertId: string,
    fundingSatoshis: number,
    policyObjectId: string,
    meterUnit: string,
    hatId: string,
    hatCapabilities?: number[],
  ): Promise<string> {
    return cm.createPaymentChannel(this.stateAtom, getLivePorts(), {
      typeDef, counterpartyCertId, fundingSatoshis, policyObjectId, meterUnit, hatId,
      ...(hatCapabilities !== undefined ? { hatCapabilities } : {}),
    });
  }

  async advanceChannelPhase(
    objectId: string,
    lifecycle: ChannelLifecycleFlow,
    targetPhase: string,
    context: GuardContext,
    config?: ExtensionConfig,
    hatId?: string,
    hatCapabilities?: number[],
  ): Promise<PhaseTransitionResult> {
    return cm.advanceChannelPhase(this.stateAtom, getLivePorts(), {
      objectId, lifecycle, targetPhase, context,
      ...(config !== undefined ? { config } : {}),
      ...(hatId !== undefined ? { hatId } : {}),
      ...(hatCapabilities !== undefined ? { hatCapabilities } : {}),
    });
  }

  async recordChannelTransaction(
    objectId: string,
    from: string,
    to: string,
    amount: number,
    meterUnit: string,
    hatId?: string,
    hatCapabilities?: number[],
  ): Promise<void> {
    return cm.recordChannelTransaction(this.stateAtom, getLivePorts(), {
      objectId, from, to, amount, meterUnit,
      ...(hatId !== undefined ? { hatId } : {}),
      ...(hatCapabilities !== undefined ? { hatCapabilities } : {}),
    });
  }
}

/** A LoomStore wired to the singleton `loomStateAtom`. */
export function singletonLoomStore(): LoomStore {
  return new LoomStore({ stateAtom: loomStateAtom });
}

```
