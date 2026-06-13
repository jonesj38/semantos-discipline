---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/grid/intent-reducer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.605272+00:00
---

# cartridges/jambox/web/src/grid/intent-reducer.ts

```ts
/**
 * Intent Reducer — Layer 3½ of the mapping pipeline.
 *
 * Sits between Mode (Layer 3) and Semantic (Layer 4) in MappingRouter.
 * Formalises the three overlay primitives that the Novation/Push
 * design research identifies as the irreducible vocabulary:
 *
 *   Momentary  — modifier held; surface re-maps; release reverts.
 *   Latched    — tap-toggle; overlay persists until superseded.
 *   Compound   — two simultaneous inputs; resolves to a named intent.
 *
 * Built-in overlays (step-clear, step-duplicate, mute, rec-arm, capture)
 * are registered here. Third-party extensions plug into the same registry
 * as JamExtensionReducer entries. The only difference is provenance:
 * built-ins have ownerIdentity = 'jam.system'; extensions are user-owned
 * JamboxSemanticObjects with commercial.royaltyBps set.
 *
 * Accounting: every extension-handled event emits a jam.extension.fire
 * accounting event. The contribution pipeline uses these to attribute
 * the extension owner's royaltyBps cut at session close.
 *
 * Hard rules:
 *   - Reducers are pure functions: (context, event) → reduction | null.
 *   - Reducers may not mutate context or emit events directly.
 *   - Priority is integers: lower = runs first. Built-ins use 0..99.
 *     Extensions must use ≥ 100 to avoid stomping built-ins.
 *   - A reducer returning null passes through to the next in priority order.
 *   - If no reducer claims an event, it passes to Semantic unchanged.
 */

import type { SurfaceEvent } from '../mappings/router';
import type { JamEvent } from '../semantic/events';

// ── Overlay state ─────────────────────────────────────────────────────────────

/**
 * Mutable overlay state tracked by IntentReducer across events.
 * Immutable snapshot passed into each reducer call via IntentContext.
 */
export interface OverlayState {
  /** Pads currently held (not yet released). key = selector string. */
  held: Map<string, { selector: string | number; ts: number; surfaceId: string }>;
  /**
   * Currently latched overlay id, or null.
   * Only one overlay can be latched at a time; a new latch supersedes the old.
   */
  latched: string | null;
  /**
   * Stack of momentary overlays currently active (deepest-first).
   * Releasing a momentary pops it and restores the previous state.
   */
  momentaryStack: string[];
}

/** Immutable snapshot passed to reducers — they read but never mutate. */
export interface IntentContext {
  readonly overlay: Readonly<{
    held: ReadonlyMap<string, { selector: string | number; ts: number; surfaceId: string }>;
    latched: string | null;
    momentaryStack: readonly string[];
  }>;
  readonly mode: string;
  readonly surfaceId: string;
  readonly scale: { root: number; degrees: ReadonlySet<number> };
  /** Wall-clock ms — used for hold-duration thresholds. */
  readonly nowMs: number;
}

// ── Reduction result ──────────────────────────────────────────────────────────

/**
 * What a reducer returns when it claims an event.
 *
 * kind:
 *   'pass'      — reducer explicitly passes; next reducer in chain is tried.
 *   'momentary' — enter a momentary overlay; release event will revert.
 *   'latch'     — toggle a latched overlay on/off.
 *   'compound'  — resolved a two-input compound; produces semantic events.
 *   'emit'      — reducer produces semantic events directly (most common).
 *   'suppress'  — swallow the event entirely (e.g. first half of a compound).
 */
export type IntentReductionKind =
  | 'pass'
  | 'momentary'
  | 'latch'
  | 'compound'
  | 'emit'
  | 'suppress';

export interface IntentReduction {
  kind: IntentReductionKind;
  /** Overlay id to enter/exit (for 'momentary' and 'latch'). */
  overlayId?: string;
  /**
   * Semantic events to forward to Layer 4.
   * For 'compound' and 'emit' kinds.
   */
  events?: JamEvent[];
  /**
   * Human-readable intent label (used in HintStrip and accounting).
   * e.g. 'step.clear', 'step.chain', 'mute.toggle'
   */
  intent?: string;
}

// ── Extension reducer interface ───────────────────────────────────────────────

/**
 * A single reducer entry in the intent reducer registry.
 *
 * Built-ins (shipped with the app) have ownerIdentity = 'jam.system'
 * and priority 0–99. User extensions must use priority ≥ 100.
 */
export interface JamExtensionReducer {
  /** Stable id matching JamboxSemanticObject.id for marketplace extensions. */
  extensionId: string;
  /** Display name shown in HintStrip and session credits. */
  name: string;
  /** jam.system for built-ins; owner identity hash for marketplace items. */
  ownerIdentity: string;
  /**
   * Lower runs first. Built-ins: 0–99. User extensions: ≥ 100.
   * Two reducers at the same priority run in registration order.
   */
  priority: number;
  /**
   * Which overlay primitive(s) this reducer implements.
   * Declares intent so the UI can show affordance hints.
   */
  primitives: Array<'momentary' | 'latched' | 'compound' | 'emit'>;
  /**
   * Keyboard/touch shortcut hints to show in HintStrip when this
   * extension is active.
   */
  hints?: Array<{ gesture: string; label: string }>;
  /**
   * Pure reducer function. MUST NOT mutate context or call audio.
   * Return null to pass through to the next reducer.
   */
  reduce(context: IntentContext, event: SurfaceEvent): IntentReduction | null;
}

// ── Hold-duration threshold (for touch surfaces) ──────────────────────────────

/** A pad held longer than this is treated as a momentary modifier. */
export const HOLD_MOMENTARY_MS = 350;
/** A pad held longer than this is a long-hold (used for compound entry). */
export const HOLD_COMPOUND_MS = 150;

// ── Accounting callback ────────────────────────────────────────────────────────

export interface ExtensionFireEvent {
  extensionId: string;
  ownerIdentity: string;
  intent: string;
  surfaceId: string;
  ts: number;
}

export type OnExtensionFire = (ev: ExtensionFireEvent) => void;

// ── IntentReducer ─────────────────────────────────────────────────────────────

/**
 * The intent reducer registry and dispatch engine.
 *
 * Instantiate once and share across the jam-room (singleton at bottom of file).
 * Register extensions via install() / uninstall().
 * Call reduce() from MappingRouter's Layer 3→4 boundary.
 */
export class IntentReducer {
  private reducers: JamExtensionReducer[] = [];
  private readonly overlayState: OverlayState = {
    held: new Map(),
    latched: null,
    momentaryStack: [],
  };
  private onFire: OnExtensionFire | null = null;

  // ── Registry ────────────────────────────────────────────────────────────────

  install(reducer: JamExtensionReducer): void {
    if (this.reducers.some((r) => r.extensionId === reducer.extensionId)) {
      throw new Error(`IntentReducer: extension '${reducer.extensionId}' already installed`);
    }
    this.reducers = [...this.reducers, reducer].sort((a, b) => a.priority - b.priority);
  }

  uninstall(extensionId: string): void {
    this.reducers = this.reducers.filter((r) => r.extensionId !== extensionId);
  }

  setFireCallback(cb: OnExtensionFire): void {
    this.onFire = cb;
  }

  /** All installed reducers in priority order (read-only). */
  get installed(): readonly JamExtensionReducer[] {
    return this.reducers;
  }

  // ── Held-pad tracking ───────────────────────────────────────────────────────

  /** Called by MappingRouter on pad.on / pad.off to maintain hold state. */
  trackHold(event: SurfaceEvent, isPress: boolean): void {
    const key = `${event.selector}`;
    if (isPress) {
      this.overlayState.held.set(key, {
        selector: event.selector,
        ts: event.ts,
        surfaceId: '', // filled in by router
      });
    } else {
      this.overlayState.held.delete(key);
      // Pop momentary overlay if the releasing pad started it
      // (handled by the built-in momentary reducer)
    }
  }

  // ── Main dispatch ────────────────────────────────────────────────────────────

  /**
   * Reduce a SurfaceEvent through the registered chain.
   *
   * Returns the final IntentReduction. If no reducer claims the event,
   * returns { kind: 'pass' } so the router forwards it unchanged to Layer 4.
   */
  reduce(
    event: SurfaceEvent,
    mode: string,
    surfaceId: string,
    scale: { root: number; degrees: Set<number> },
  ): IntentReduction {
    const context: IntentContext = {
      overlay: {
        held: this.overlayState.held,
        latched: this.overlayState.latched,
        momentaryStack: this.overlayState.momentaryStack,
      },
      mode,
      surfaceId,
      scale: { root: scale.root, degrees: scale.degrees },
      nowMs: Date.now(),
    };

    for (const reducer of this.reducers) {
      const result = reducer.reduce(context, event);
      if (result === null || result.kind === 'pass') continue;

      // Apply overlay state mutations
      this._applyOverlayMutation(result);

      // Fire accounting event for non-system extensions
      if (reducer.ownerIdentity !== 'jam.system' && result.intent) {
        this.onFire?.({
          extensionId: reducer.extensionId,
          ownerIdentity: reducer.ownerIdentity,
          intent: result.intent,
          surfaceId,
          ts: event.ts,
        });
      }

      return result;
    }

    return { kind: 'pass' };
  }

  private _applyOverlayMutation(reduction: IntentReduction): void {
    if (reduction.kind === 'momentary' && reduction.overlayId) {
      this.overlayState.momentaryStack.push(reduction.overlayId);
    }
    if (reduction.kind === 'latch' && reduction.overlayId) {
      if (this.overlayState.latched === reduction.overlayId) {
        this.overlayState.latched = null; // toggle off
      } else {
        this.overlayState.latched = reduction.overlayId;
      }
    }
  }

  /** Reset all overlay state (e.g. on transport stop or mode switch). */
  reset(): void {
    this.overlayState.held.clear();
    this.overlayState.latched = null;
    this.overlayState.momentaryStack.length = 0;
  }

  /** Snapshot of current overlay for UI rendering (HintStrip, pad colour). */
  getOverlayState(): Readonly<OverlayState> {
    return this.overlayState;
  }
}

// ── Built-in reducers ─────────────────────────────────────────────────────────

/**
 * Step-clear: hold any active step pad > HOLD_MOMENTARY_MS → suppress & clear it.
 * Momentary: no overlay id needed — the hold itself is the modifier.
 */
export const stepClearReducer: JamExtensionReducer = {
  extensionId: 'jam.system.step-clear',
  name: 'Step Clear',
  ownerIdentity: 'jam.system',
  priority: 10,
  primitives: ['momentary'],
  hints: [{ gesture: 'hold step', label: 'CLEAR' }],
  reduce(ctx, ev): IntentReduction | null {
    if (ctx.mode !== 'rhythm') return null;
    const heldEntry = ctx.overlay.held.get(`${ev.selector}`);
    if (!heldEntry) return null;
    const holdMs = ctx.nowMs - heldEntry.ts;
    if (holdMs < HOLD_MOMENTARY_MS) return null;
    // Suppress the normal toggle; the caller must handle the clear via intent
    return { kind: 'emit', intent: 'step.clear', events: [] };
  },
};

/**
 * Step-chain: hold two step pads simultaneously → set loop start/end.
 * Compound: two simultaneous inputs resolve to a chain intent.
 */
export const stepChainReducer: JamExtensionReducer = {
  extensionId: 'jam.system.step-chain',
  name: 'Step Chain',
  ownerIdentity: 'jam.system',
  priority: 20,
  primitives: ['compound'],
  hints: [{ gesture: 'hold step A + tap step B', label: 'CHAIN' }],
  reduce(ctx, ev): IntentReduction | null {
    if (ctx.mode !== 'rhythm') return null;
    if (ctx.overlay.held.size !== 1) return null;
    const [held] = ctx.overlay.held.values();
    if (!held || held.selector === ev.selector) return null;
    const holdMs = ctx.nowMs - held.ts;
    if (holdMs < HOLD_COMPOUND_MS) return null;
    return {
      kind: 'compound',
      intent: 'step.chain',
      events: [], // router fills in the actual jam.pattern.* events
    };
  },
};

/**
 * Mute-latch: tap the mute control pad → latch mute overlay to bottom strip.
 */
export const muteLatchReducer: JamExtensionReducer = {
  extensionId: 'jam.system.mute-latch',
  name: 'Mute Latch',
  ownerIdentity: 'jam.system',
  priority: 30,
  primitives: ['latched'],
  hints: [{ gesture: 'tap MUTE', label: 'MUTE' }],
  reduce(_ctx, ev): IntentReduction | null {
    // Control pads live at y=7 (bottom row), selector includes 'ctrl.'
    if (typeof ev.selector !== 'string' || !ev.selector.startsWith('ctrl.mute')) return null;
    return { kind: 'latch', overlayId: 'mute', intent: 'mute.toggle' };
  },
};

/**
 * Capture-momentary: hold CAP button → momentary capture overlay.
 * While held, the next pad press records a performance take.
 */
export const captureMomentaryReducer: JamExtensionReducer = {
  extensionId: 'jam.system.capture-momentary',
  name: 'Capture',
  ownerIdentity: 'jam.system',
  priority: 40,
  primitives: ['momentary'],
  hints: [{ gesture: 'hold CAP', label: 'CAPTURE' }],
  reduce(_ctx, ev): IntentReduction | null {
    if (typeof ev.selector !== 'string' || ev.selector !== 'ctrl.cap') return null;
    return { kind: 'momentary', overlayId: 'capture', intent: 'capture.arm' };
  },
};

// ── Register built-ins on the singleton ───────────────────────────────────────

/** Singleton — imported by MappingRouter and Svelte App.svelte. */
export const intentReducer = new IntentReducer();

intentReducer.install(stepClearReducer);
intentReducer.install(stepChainReducer);
intentReducer.install(muteLatchReducer);
intentReducer.install(captureMomentaryReducer);

```
