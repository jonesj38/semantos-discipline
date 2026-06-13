---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/FlowRunner.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.098785+00:00
---

# runtime/services/src/services/FlowRunner.ts

```ts
/**
 * FlowRunner — step-by-step conversation flow state machine.
 *
 * Passive: collects user responses and reports what actions should happen.
 * The integrating component (ConversationPanel, TerminalPanel) dispatches actions.
 */

import { TypedEventEmitter } from './TypedEventEmitter';
import type { ConversationFlow, FlowStep, FlowAction } from '../config/extensionConfig';

/** A guard on a channel lifecycle phase transition. */
export interface FlowStepGuard {
  type: 'capability' | 'value' | 'time' | 'relationship' | 'contextual';
  field: string;
  operator: 'eq' | 'gte' | 'gt' | 'lt' | 'lte' | 'includes_all' | 'in';
  value: unknown;
}

/** A transition in a channel lifecycle phase. */
export interface PhaseTransition {
  targetPhase: string;
  displayName: string;
  guard: FlowStepGuard;
}

/** A phase in a channel lifecycle flow. */
export interface LifecyclePhase {
  phaseId: string;
  displayName: string;
  transitions: PhaseTransition[];
}

/** A channel lifecycle flow definition (from core.json channelLifecycle). */
export interface ChannelLifecycleFlow {
  flowId: string;
  displayName: string;
  initialPhase: string;
  phases: LifecyclePhase[];
}

/** Result of a phase transition attempt. */
export interface PhaseTransitionResult {
  ok: boolean;
  fromPhase?: string;
  toPhase?: string;
  reason?: string;
}

/** Context for evaluating guards. */
export interface GuardContext {
  identity?: {
    certId?: string;
    capabilities?: number[];
  };
  object?: Record<string, unknown>;
  policy?: Record<string, unknown>;
  settlement?: Record<string, unknown>;
  ballot?: Record<string, unknown>;
  [key: string]: unknown;
}

/**
 * Evaluate a guard against a context.
 * Returns true if the guard condition is satisfied.
 */
export function evaluateGuard(guard: FlowStepGuard, context: GuardContext): boolean {
  const resolvedValue = resolveFieldValue(guard.field, context);
  const compareValue = resolveGuardValue(guard.value, context);

  switch (guard.operator) {
    case 'eq':
      return resolvedValue === compareValue;
    case 'gte':
      return typeof resolvedValue === 'number' && typeof compareValue === 'number' && resolvedValue >= compareValue;
    case 'gt':
      return typeof resolvedValue === 'number' && typeof compareValue === 'number' && resolvedValue > compareValue;
    case 'lt':
      return typeof resolvedValue === 'number' && typeof compareValue === 'number' && resolvedValue < compareValue;
    case 'lte':
      return typeof resolvedValue === 'number' && typeof compareValue === 'number' && resolvedValue <= compareValue;
    case 'includes_all': {
      if (!Array.isArray(resolvedValue) || !Array.isArray(compareValue)) return false;
      return compareValue.every(v => resolvedValue.includes(v));
    }
    case 'in': {
      if (!Array.isArray(compareValue)) return false;
      return compareValue.includes(resolvedValue);
    }
    default:
      return false;
  }
}

/** Resolve a dotted field path against a context object. */
function resolveFieldValue(field: string, context: GuardContext): unknown {
  const parts = field.split('.');
  let current: unknown = context;
  for (const part of parts) {
    if (current == null || typeof current !== 'object') return undefined;
    current = (current as Record<string, unknown>)[part];
  }
  return current;
}

/** Resolve a guard value — may be a literal or a context reference (string starting with known prefix). */
function resolveGuardValue(value: unknown, context: GuardContext): unknown {
  if (typeof value === 'string') {
    if (value === 'now()') return Date.now();
    if (value.includes('.')) {
      const resolved = resolveFieldValue(value, context);
      if (resolved !== undefined) return resolved;
    }
  }
  return value;
}

export interface FlowRunState {
  flowId: string;
  flowName: string;
  currentStepIndex: number;
  totalSteps: number;
  collectedData: Record<string, unknown>;
  objectId?: string;
  status: 'idle' | 'running' | 'complete' | 'cancelled';
  onComplete: FlowAction;
}

type FlowEvents = {
  step: [FlowStep, FlowRunState];
  complete: [FlowRunState];
  cancel: [FlowRunState];
  /** Emitted when a step has a stepAction that should be executed before advancing. */
  stepAction: [FlowAction, FlowRunState];
};

export class FlowRunner extends TypedEventEmitter<FlowEvents> {
  private state: FlowRunState = {
    flowId: '',
    flowName: '',
    currentStepIndex: 0,
    totalSteps: 0,
    collectedData: {},
    status: 'idle',
    onComplete: { type: 'create' },
  };
  private flow: ConversationFlow | null = null;

  getState(): FlowRunState {
    return this.state;
  }

  isActive(): boolean {
    return this.state.status === 'running';
  }

  /** Start a new flow. Emits the first step. */
  startFlow(flow: ConversationFlow, objectId?: string): FlowStep {
    this.flow = flow;
    this.state = {
      flowId: flow.id,
      flowName: flow.name,
      currentStepIndex: 0,
      totalSteps: flow.steps.length,
      collectedData: {},
      objectId,
      status: 'running',
      onComplete: flow.onComplete,
    };

    const firstStep = flow.steps[0];
    this.emit('step', firstStep, this.state);
    return firstStep;
  }

  /** Get the current step, or null if flow is not running or complete. */
  getCurrentStep(): FlowStep | null {
    if (!this.flow || this.state.status !== 'running') return null;
    return this.flow.steps[this.state.currentStepIndex] ?? null;
  }

  /**
   * Advance the flow with a user response.
   * Stores the response in collectedData (keyed by step.field if present).
   * Returns the next step, or null if the flow is complete.
   */
  advanceFlow(userResponse: string, extractedFields?: Record<string, unknown>): FlowStep | null {
    if (!this.flow || this.state.status !== 'running') return null;

    const currentStep = this.flow.steps[this.state.currentStepIndex];

    // Build new collected data (immutable)
    const newData = { ...this.state.collectedData };
    if (currentStep.field) {
      // If LLM extracted a value for this field, prefer it; otherwise use raw response
      const extractedValue = extractedFields?.[currentStep.field];
      newData[currentStep.field] = extractedValue ?? userResponse;
    }
    if (extractedFields) {
      for (const [key, value] of Object.entries(extractedFields)) {
        if (key !== currentStep.field) {
          newData[key] = value;
        }
      }
    }

    const nextIndex = this.state.currentStepIndex + 1;

    // Execute stepAction if the completing step has one
    if (currentStep.stepAction) {
      this.state = { ...this.state, collectedData: newData };
      this.emit('stepAction', currentStep.stepAction, this.state);
    }

    if (nextIndex >= this.flow.steps.length) {
      this.state = { ...this.state, currentStepIndex: nextIndex, collectedData: newData, status: 'complete' };
      this.emit('complete', this.state);
      return null;
    }

    this.state = { ...this.state, currentStepIndex: nextIndex, collectedData: newData };
    const nextStep = this.flow.steps[nextIndex];
    this.emit('step', nextStep, this.state);
    return nextStep;
  }

  /** Check if all required steps have been answered. */
  isFlowComplete(): boolean {
    return this.state.status === 'complete';
  }

  /** Get the completed flow state with collected data and the onComplete action. */
  completeFlow(): FlowRunState {
    return { ...this.state };
  }

  /** Cancel the active flow. */
  cancelFlow(): void {
    if (this.state.status === 'running') {
      this.state = { ...this.state, status: 'cancelled' };
      this.emit('cancel', this.state);
    }
    this.flow = null;
  }

  /** Reset to idle state. */
  reset(): void {
    this.flow = null;
    this.state = {
      flowId: '',
      flowName: '',
      currentStepIndex: 0,
      totalSteps: 0,
      collectedData: {},
      status: 'idle',
      onComplete: { type: 'create' },
    };
  }

  /**
   * Attempt a phase transition in a channel lifecycle flow.
   * Evaluates the guard for the requested transition and returns the result.
   */
  transitionPhase(
    lifecycle: ChannelLifecycleFlow,
    currentPhaseId: string,
    targetPhaseId: string,
    context: GuardContext,
  ): PhaseTransitionResult {
    const currentPhase = lifecycle.phases.find(p => p.phaseId === currentPhaseId);
    if (!currentPhase) {
      return { ok: false, reason: `Current phase '${currentPhaseId}' not found in lifecycle` };
    }

    const transition = currentPhase.transitions.find(t => t.targetPhase === targetPhaseId);
    if (!transition) {
      return {
        ok: false,
        reason: `No transition from '${currentPhaseId}' to '${targetPhaseId}'`,
      };
    }

    const guardPasses = evaluateGuard(transition.guard, context);
    if (!guardPasses) {
      return {
        ok: false,
        reason: `Guard failed for transition '${currentPhaseId}' → '${targetPhaseId}': ${transition.guard.type} check on '${transition.guard.field}'`,
      };
    }

    return {
      ok: true,
      fromPhase: currentPhaseId,
      toPhase: targetPhaseId,
    };
  }

  /**
   * Get valid transitions from a phase given the current context.
   * Returns transitions whose guards pass.
   */
  getValidTransitions(
    lifecycle: ChannelLifecycleFlow,
    currentPhaseId: string,
    context: GuardContext,
  ): PhaseTransition[] {
    const currentPhase = lifecycle.phases.find(p => p.phaseId === currentPhaseId);
    if (!currentPhase) return [];

    return currentPhase.transitions.filter(t => evaluateGuard(t.guard, context));
  }
}

```
