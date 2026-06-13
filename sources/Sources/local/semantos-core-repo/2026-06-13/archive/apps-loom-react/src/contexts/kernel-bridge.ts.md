---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/contexts/kernel-bridge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.954001+00:00
---

# archive/apps-loom-react/src/contexts/kernel-bridge.ts

```ts
/**
 * Kernel Bridge — importable module version of the kernel bridge.
 *
 * Mirrors the vanilla JS kernel-bridge.ts but exports initKernel()
 * as a module function instead of attaching to window.SemantosKernel.
 */

import {
  validateExtensionConfig,
  type ExtensionConfig,
  type ObjectTypeDefinition,
  type ConversationFlow,
  type FlowStep,
  type FlowAction,
} from '../config/extensionConfig';

import navConfigRaw from '@configs/extensions/consciousness.json';

// ── Local types (governance functions use different signatures) ────

const CURRENT_KERNEL_VERSION = '0.3.0';

interface ObjectPayload {
  type: string;
  fields: Record<string, unknown>;
}

interface IdentityContext {
  capabilities: number[];
  certId: string;
}

interface ConstraintResult {
  valid: boolean;
  violations: Array<{ level: string; rule: string; message: string }>;
}

interface CompatResult {
  compatible: boolean;
  message?: string;
}

/** Simple L0 validation: type exists in config */
function enforceL0Constraints(payload: ObjectPayload, config: ExtensionConfig): ConstraintResult {
  const typeDef = config.objectTypes.find(t => t.name === payload.type);
  if (!typeDef) {
    return { valid: false, violations: [{ level: 'L0', rule: 'type-exists', message: `Unknown type: ${payload.type}` }] };
  }
  return { valid: true, violations: [] };
}

/** Simple L1 validation: identity has capability */
function enforceL1Constraints(payload: ObjectPayload, config: ExtensionConfig, identity: IdentityContext): ConstraintResult {
  // Stub: always passes for local consumer
  return { valid: true, violations: [] };
}

/** Simple version compatibility check */
function checkCompatibility(version: string, range: string): CompatResult {
  // Basic semver check: version >= range minimum
  const minVersion = range.replace(/^>=/, '');
  return { compatible: version >= minVersion };
}

// ── Types ─────────────────────────────────────────────────────────

export interface KernelObject {
  id: string;
  type: string;
  typeDef: ObjectTypeDefinition;
  fields: Record<string, unknown>;
  visibility: string;
  createdAt: number;
  updatedAt: number;
}

type ChangeListener = (objects: Map<string, KernelObject>) => void;

// ── Object Store ──────────────────────────────────────────────────

class ObjectStore {
  private objects = new Map<string, KernelObject>();
  private listeners = new Set<ChangeListener>();

  create(typeDef: ObjectTypeDefinition, fields?: Record<string, unknown>): string {
    const id = crypto.randomUUID();
    const now = Date.now();
    this.objects.set(id, {
      id,
      type: typeDef.name,
      typeDef,
      fields: fields ?? {},
      visibility: typeDef.visibility?.defaultState ?? 'draft',
      createdAt: now,
      updatedAt: now,
    });
    this.notify();
    return id;
  }

  patch(objectId: string, delta: Record<string, unknown>): boolean {
    const obj = this.objects.get(objectId);
    if (!obj) return false;
    obj.fields = { ...obj.fields, ...delta };
    obj.updatedAt = Date.now();
    this.notify();
    return true;
  }

  get(objectId: string): KernelObject | undefined {
    return this.objects.get(objectId);
  }

  list(typeFilter?: string): KernelObject[] {
    const all = Array.from(this.objects.values());
    return typeFilter ? all.filter(o => o.type === typeFilter) : all;
  }

  subscribe(listener: ChangeListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private notify(): void {
    for (const fn of this.listeners) fn(this.objects);
  }
}

// ── Flow Runner ───────────────────────────────────────────────────

class BrowserFlowRunner {
  private currentFlow: ConversationFlow | null = null;
  private stepIndex = 0;
  private collectedData: Record<string, unknown> = {};

  startFlow(flow: ConversationFlow): FlowStep | null {
    this.currentFlow = flow;
    this.stepIndex = 0;
    this.collectedData = {};
    return flow.steps[0] ?? null;
  }

  advanceFlow(response: string): FlowStep | null {
    if (!this.currentFlow) return null;
    const currentStep = this.currentFlow.steps[this.stepIndex];
    if (currentStep?.field) {
      this.collectedData[currentStep.field] = response;
    }
    this.stepIndex++;
    return this.currentFlow.steps[this.stepIndex] ?? null;
  }

  isActive(): boolean {
    return this.currentFlow !== null && this.stepIndex < (this.currentFlow?.steps.length ?? 0);
  }

  isComplete(): boolean {
    return this.currentFlow !== null && this.stepIndex >= (this.currentFlow?.steps.length ?? 0);
  }

  completeFlow(): { collectedData: Record<string, unknown>; onComplete: FlowAction } {
    const data = { ...this.collectedData };
    const onComplete = this.currentFlow!.onComplete;
    this.currentFlow = null;
    this.stepIndex = 0;
    this.collectedData = {};
    return { collectedData: data, onComplete };
  }

  getCurrentStep(): FlowStep | null {
    return this.currentFlow?.steps[this.stepIndex] ?? null;
  }
}

// ── Kernel API type ───────────────────────────────────────────────

export interface SemantosKernel {
  store: ObjectStore;
  flowRunner: BrowserFlowRunner;
  config: ExtensionConfig;
  version: string;
  identity: IdentityContext;
  createObject(typeName: string, fields?: Record<string, unknown>): string | null;
  patchObject(objectId: string, delta: Record<string, unknown>): boolean;
  listObjects(typeFilter?: string): Array<{
    id: string;
    type: string;
    fields: Record<string, unknown>;
    visibility: string;
    createdAt: number;
  }>;
  getObject(objectId: string): {
    id: string;
    type: string;
    fields: Record<string, unknown>;
    visibility: string;
    createdAt: number;
  } | null;
  startFlow(flowId: string): { stepId: string; prompt: string; field?: string } | null;
  advanceFlow(response: string): { stepId: string; prompt: string; field?: string } | null;
  completeFlow(): Record<string, unknown>;
  isFlowActive(): boolean;
  isFlowComplete(): boolean;
  getCurrentStep(): { stepId: string; prompt: string; field?: string } | null;
  validateObject(payload: ObjectPayload): ConstraintResult;
  checkVersion(version: string, range: string): CompatResult;
  subscribe(listener: () => void): () => void;
}

// ── Initialize ────────────────────────────────────────────────────

export function initKernel(): SemantosKernel {
  const config = validateExtensionConfig(navConfigRaw);

  const versionCheck = checkCompatibility(CURRENT_KERNEL_VERSION, '>=0.3.0');
  if (!versionCheck.compatible) {
    console.error('[SemantosKernel] Version incompatible:', versionCheck.message);
  }

  const store = new ObjectStore();
  const flowRunner = new BrowserFlowRunner();

  const identity: IdentityContext = {
    capabilities: [1],
    certId: 'cert:local-consumer-stub',
  };

  function createObject(typeName: string, fields?: Record<string, unknown>): string | null {
    const typeDef = config.objectTypes.find(t => t.name === typeName);
    if (!typeDef) {
      console.error(`[SemantosKernel] Unknown type: ${typeName}`);
      return null;
    }

    const payload: ObjectPayload = { type: typeName, fields: fields ?? {} };
    const l0 = enforceL0Constraints(payload, config);
    if (!l0.valid) {
      console.error('[SemantosKernel] L0 violation:', l0.violations);
      return null;
    }
    const l1 = enforceL1Constraints(payload, config, identity);
    if (!l1.valid) {
      console.error('[SemantosKernel] L1 violation:', l1.violations);
      return null;
    }

    return store.create(typeDef, fields);
  }

  function patchObject(objectId: string, delta: Record<string, unknown>): boolean {
    return store.patch(objectId, delta);
  }

  function listObjects(typeFilter?: string) {
    return store.list(typeFilter).map(o => ({
      id: o.id,
      type: o.type,
      fields: o.fields,
      visibility: o.visibility,
      createdAt: o.createdAt,
    }));
  }

  function getObject(objectId: string) {
    const obj = store.get(objectId);
    if (!obj) return null;
    return {
      id: obj.id,
      type: obj.type,
      fields: obj.fields,
      visibility: obj.visibility,
      createdAt: obj.createdAt,
    };
  }

  function startFlow(flowId: string) {
    const flow = config.flows?.find(f => f.id === flowId);
    if (!flow) return null;
    const step = flowRunner.startFlow(flow);
    return step ? { stepId: step.id, prompt: step.prompt, field: step.field } : null;
  }

  function advanceFlow(response: string) {
    const step = flowRunner.advanceFlow(response);
    return step ? { stepId: step.id, prompt: step.prompt, field: step.field } : null;
  }

  function completeFlow() {
    const result = flowRunner.completeFlow();
    if (result.onComplete.type === 'create' && result.onComplete.objectType) {
      const objectId = createObject(result.onComplete.objectType, result.collectedData);
      return { ...result.collectedData, _objectId: objectId };
    }
    return result.collectedData;
  }

  function isFlowActive(): boolean {
    return flowRunner.isActive();
  }

  function isFlowComplete(): boolean {
    return flowRunner.isComplete();
  }

  function getCurrentStep() {
    const step = flowRunner.getCurrentStep();
    return step ? { stepId: step.id, prompt: step.prompt, field: step.field } : null;
  }

  function validateObject(payload: ObjectPayload): ConstraintResult {
    const l0 = enforceL0Constraints(payload, config);
    if (!l0.valid) return l0;
    return enforceL1Constraints(payload, config, identity);
  }

  function checkVersion(version: string, range: string): CompatResult {
    return checkCompatibility(version, range);
  }

  function subscribe(listener: () => void): () => void {
    return store.subscribe(() => listener());
  }

  console.log(
    `[SemantosKernel] v${CURRENT_KERNEL_VERSION} loaded — ${config.objectTypes.length} types, ${config.flows?.length ?? 0} flows`,
  );

  return {
    store,
    flowRunner,
    config,
    version: CURRENT_KERNEL_VERSION,
    identity,
    createObject,
    patchObject,
    listObjects,
    getObject,
    startFlow,
    advanceFlow,
    completeFlow,
    isFlowActive,
    isFlowComplete,
    getCurrentStep,
    validateObject,
    checkVersion,
    subscribe,
  };
}

```
