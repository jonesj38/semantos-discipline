---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/session_fsm.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.563208+00:00
---

# cartridges/betterment/brain/src/session_fsm.ts

```ts
/**
 * Betterment session FSM — pure state machine definition.
 *
 * Models a complete betterment-practice session as an explicit FSM so the
 * Flutter conductor (and eventually the conversation substrate) can
 * route the practitioner through the correct attending step at each
 * moment, rather than offering a free-choice menu of flows.
 *
 * Design principles:
 *   - PURE: no I/O, no imports from rest of the cartridge.  Only
 *     types + a transition function + gate predicates.
 *   - CONVERSATION NATIVE: the attending states (ARRIVE, GROUND,
 *     RECEIVE, RESISTANCE_INQUIRY, DISCERN, HARVEST) are conversation
 *     turns, not form steps.  The structured states (SCAN, SEAL,
 *     VACUUM, INTENTION) keep the existing FlowRunner widget.
 *   - PASK INFORMED: the SCAN state is primed by `pask_sweep.ts`
 *     output (primedThemes), not manual sliders.
 *
 * Psychological grounding for each state:
 *   ARRIVE          — orienting response; body settles; no input yet
 *   GROUND          — somatic anchoring; establishes witness position
 *   SCAN            — pask-informed inventory; what is still live?
 *   SHORT_PULSE     — low-charge days still close; pulse + intention
 *   RECEIVE         — open attending; what is most alive right now?
 *   RESISTANCE_INQUIRY — attention hits resistance; wall becomes inquiry target (IFS)
 *   CONNECTION      — deliberate widening; receive from named intelligence
 *   RELEASE         — expressive completion; material moves outward
 *   DISCERN         — "is this complete? does it still have charge?"
 *   VACUUM          — QSE clearing for residue that expressed but didn't fully leave
 *   SEAL            — completion visualization; Zeigarnik loop closure
 *   HARVEST         — post-release clarity; insight + pattern emerge
 *   SET_INTENTION   — intention set from cleared field (more potent)
 *   CLOSE           — session record; temporal container sealed
 */

// ─── States ──────────────────────────────────────────────────────────────────

export type SessionState =
  | 'ARRIVE'
  | 'GROUND'
  | 'SCAN'
  | 'SHORT_PULSE'
  | 'RECEIVE'
  | 'RESISTANCE_INQUIRY'
  | 'CONNECTION'
  | 'RELEASE'
  | 'DISCERN'
  | 'VACUUM'
  | 'SEAL'
  | 'HARVEST'
  | 'SET_INTENTION'
  | 'CLOSE'

// ─── Events ──────────────────────────────────────────────────────────────────

export type SessionEvent =
  /** User has settled — body check complete, witness position established. */
  | { readonly kind: 'GROUNDED' }

  /** Scan complete — elevation average and pask-primed themes confirmed. */
  | { readonly kind: 'SCAN_COMPLETE'; readonly elevationAvg: number; readonly primedThemes: readonly string[] }

  /** Attending opened — the practitioner directs attention inward. */
  | { readonly kind: 'RECEIVE_OPENED' }

  /** Resistance noticed — attention has hit a protective wall. */
  | { readonly kind: 'RESISTANCE_FLAGGED' }

  /** Resistance inquiry complete — source understood, now clear to proceed. */
  | { readonly kind: 'RESISTANCE_CLEARED' }

  /** Practitioner wants to receive from a named intelligence rather than attend to self. */
  | { readonly kind: 'CONNECTION_WANTED' }

  /** Connection complete — received intelligence documented. */
  | { readonly kind: 'CONNECTION_RECEIVED' }

  /** Something is ready to move outward — practitioner proceeds to expression. */
  | { readonly kind: 'READY_TO_EXPRESS' }

  /** What arose is clarity/recognition with no charge to release — routes to harvest. */
  | { readonly kind: 'PURE_INSIGHT_AROSE' }

  /** Release writing/voice/photo submitted — cell minted, tracking ID captured. */
  | { readonly kind: 'RELEASE_SUBMITTED'; readonly localReleaseId: string }

  /** Discernment check — practitioner has attended to whether the release is complete. */
  | { readonly kind: 'DISCERN_COMPLETE'; readonly residuePresent: boolean }

  /** Vacuum session submitted — paired release + integrate intentions minted. */
  | { readonly kind: 'VACUUM_SUBMITTED'; readonly localVacuumId: string }

  /** Seal visualization submitted — completion cell minted. */
  | { readonly kind: 'SEAL_SUBMITTED'; readonly localSealId: string }

  /** Harvest complete — insight and/or pattern captured (or nothing arose). */
  | { readonly kind: 'HARVEST_CAPTURED' }

  /** Intention set from cleared field. */
  | { readonly kind: 'INTENTION_SET' }

  /** Skip optional state — moves to the natural next state. */
  | { readonly kind: 'SKIP' }

// ─── Session context ──────────────────────────────────────────────────────────

/**
 * Context carried through the FSM.  Immutable; each transition
 * produces a new context object.
 */
export interface SessionContext {
  readonly sessionId: string
  readonly startedAt: number               // epoch ms
  readonly elevationAvg: number | undefined
  readonly primedThemes: readonly string[] // from pask sweep
  readonly pendingReleaseIds: readonly string[]  // minted but not yet sealed
  readonly pendingVacuumId: string | undefined
  readonly localSealId: string | undefined
  readonly insightIds: readonly string[]
  readonly patternIds: readonly string[]
}

export function initialContext(sessionId: string): SessionContext {
  return {
    sessionId,
    startedAt: Date.now(),
    elevationAvg: undefined,
    primedThemes: [],
    pendingReleaseIds: [],
    pendingVacuumId: undefined,
    localSealId: undefined,
    insightIds: [],
    patternIds: [],
  }
}

// ─── Gate functions ───────────────────────────────────────────────────────────

/**
 * Pure predicates that inform routing decisions.  Extracted as an
 * interface so tests can inject controlled thresholds.
 */
export interface GateFunctions {
  /** A low-elevation day routes to the lighter SHORT_PULSE path. */
  isLowElevation(elevationAvg: number): boolean
  /** After release, is there unvacuumed residue? */
  hasResidueAfterRelease(ctx: SessionContext): boolean
  /** Are there pending release IDs ready to seal? */
  hasReleasesToSeal(ctx: SessionContext): boolean
}

export const defaultGates: GateFunctions = {
  isLowElevation: (avg) => avg < 3.0,
  hasResidueAfterRelease: (ctx) => ctx.pendingReleaseIds.length > 0,
  hasReleasesToSeal: (ctx) => ctx.pendingReleaseIds.length > 0,
}

// ─── Transition function ──────────────────────────────────────────────────────

/**
 * Pure transition function.  Returns [nextState, nextContext] or null
 * if the event is invalid for the current state.
 *
 * Caller is responsible for side effects (cell minting, analytics).
 * The FSM only computes state + context updates.
 */
export function transition(
  state: SessionState,
  event: SessionEvent,
  ctx: SessionContext,
  gates: GateFunctions = defaultGates,
): readonly [SessionState, SessionContext] | null {
  switch (state) {
    case 'ARRIVE':
      if (event.kind === 'GROUNDED') {
        return ['GROUND', ctx]
      }
      return null

    case 'GROUND':
      if (event.kind === 'GROUNDED') {
        return ['SCAN', ctx]
      }
      return null

    case 'SCAN':
      if (event.kind === 'SCAN_COMPLETE') {
        const nextCtx: SessionContext = {
          ...ctx,
          elevationAvg: event.elevationAvg,
          primedThemes: event.primedThemes,
        }
        if (gates.isLowElevation(event.elevationAvg)) {
          return ['SHORT_PULSE', nextCtx]
        }
        return ['RECEIVE', nextCtx]
      }
      return null

    case 'SHORT_PULSE':
      if (event.kind === 'INTENTION_SET' || event.kind === 'SKIP') {
        return ['CLOSE', ctx]
      }
      return null

    case 'RECEIVE':
      if (event.kind === 'RESISTANCE_FLAGGED') {
        return ['RESISTANCE_INQUIRY', ctx]
      }
      if (event.kind === 'CONNECTION_WANTED') {
        return ['CONNECTION', ctx]
      }
      if (event.kind === 'READY_TO_EXPRESS') {
        return ['RELEASE', ctx]
      }
      if (event.kind === 'PURE_INSIGHT_AROSE') {
        return ['HARVEST', ctx]
      }
      // Practitioner aborts attending — close cleanly
      if (event.kind === 'SKIP') {
        return ['CLOSE', ctx]
      }
      return null

    case 'RESISTANCE_INQUIRY':
      if (event.kind === 'RESISTANCE_CLEARED') {
        return ['RECEIVE', ctx]
      }
      // Resistance inquiry itself becomes the release
      if (event.kind === 'READY_TO_EXPRESS') {
        return ['RELEASE', ctx]
      }
      if (event.kind === 'SKIP') {
        return ['RECEIVE', ctx]
      }
      return null

    case 'CONNECTION':
      if (event.kind === 'CONNECTION_RECEIVED') {
        return ['RECEIVE', ctx]
      }
      if (event.kind === 'SKIP') {
        return ['RECEIVE', ctx]
      }
      return null

    case 'RELEASE':
      if (event.kind === 'RELEASE_SUBMITTED') {
        const nextCtx: SessionContext = {
          ...ctx,
          pendingReleaseIds: [...ctx.pendingReleaseIds, event.localReleaseId],
        }
        return ['DISCERN', nextCtx]
      }
      return null

    case 'DISCERN':
      if (event.kind === 'DISCERN_COMPLETE') {
        if (event.residuePresent) {
          return ['VACUUM', ctx]
        }
        // No residue — proceed to seal if we have releases, else harvest
        if (gates.hasReleasesToSeal(ctx)) {
          return ['SEAL', ctx]
        }
        return ['HARVEST', ctx]
      }
      // Practitioner notices there's more to express — allow another release pass
      if (event.kind === 'READY_TO_EXPRESS') {
        return ['RELEASE', ctx]
      }
      return null

    case 'VACUUM':
      if (event.kind === 'VACUUM_SUBMITTED') {
        const nextCtx: SessionContext = {
          ...ctx,
          pendingVacuumId: event.localVacuumId,
        }
        return ['SEAL', nextCtx]
      }
      if (event.kind === 'SKIP') {
        return ['SEAL', ctx]
      }
      return null

    case 'SEAL':
      if (event.kind === 'SEAL_SUBMITTED') {
        const nextCtx: SessionContext = {
          ...ctx,
          localSealId: event.localSealId,
          pendingReleaseIds: [], // cleared by seal
        }
        return ['HARVEST', nextCtx]
      }
      return null

    case 'HARVEST':
      if (event.kind === 'HARVEST_CAPTURED') {
        return ['SET_INTENTION', ctx]
      }
      if (event.kind === 'SKIP') {
        return ['CLOSE', ctx]
      }
      return null

    case 'SET_INTENTION':
      if (event.kind === 'INTENTION_SET' || event.kind === 'SKIP') {
        return ['CLOSE', ctx]
      }
      return null

    case 'CLOSE':
      // Terminal — no further transitions
      return null
  }
}

// ─── State classification helpers ────────────────────────────────────────────

/** Terminal state — no further transitions are valid. */
export function isTerminal(state: SessionState): boolean {
  return state === 'CLOSE'
}

/**
 * Conversation-native states — these are attended/dialogue turns, not
 * form steps.  The Flutter conductor renders a ConversationTurnScreen
 * for these rather than a FlowRunner widget.
 */
export function isConversationNative(state: SessionState): boolean {
  return (
    state === 'ARRIVE' ||
    state === 'GROUND' ||
    state === 'RECEIVE' ||
    state === 'RESISTANCE_INQUIRY' ||
    state === 'DISCERN' ||
    state === 'HARVEST'
  )
}

/**
 * Display label for each state — shown in the progress indicator.
 */
export const SESSION_STATE_LABELS: Readonly<Record<SessionState, string>> = {
  ARRIVE: 'Arriving',
  GROUND: 'Grounding',
  SCAN: 'Scanning',
  SHORT_PULSE: 'Pulse',
  RECEIVE: 'Attending',
  RESISTANCE_INQUIRY: 'Inquiry',
  CONNECTION: 'Connecting',
  RELEASE: 'Releasing',
  DISCERN: 'Discerning',
  VACUUM: 'Clearing',
  SEAL: 'Sealing',
  HARVEST: 'Harvesting',
  SET_INTENTION: 'Intention',
  CLOSE: 'Complete',
}

/**
 * Approximate session progress (0–1) for each state — drives the
 * top progress bar in the betterment session view.
 */
export const SESSION_STATE_PROGRESS: Readonly<Record<SessionState, number>> = {
  ARRIVE: 0.02,
  GROUND: 0.08,
  SCAN: 0.15,
  SHORT_PULSE: 0.5,
  RECEIVE: 0.3,
  RESISTANCE_INQUIRY: 0.35,
  CONNECTION: 0.4,
  RELEASE: 0.5,
  DISCERN: 0.62,
  VACUUM: 0.72,
  SEAL: 0.82,
  HARVEST: 0.9,
  SET_INTENTION: 0.95,
  CLOSE: 1.0,
}

```
