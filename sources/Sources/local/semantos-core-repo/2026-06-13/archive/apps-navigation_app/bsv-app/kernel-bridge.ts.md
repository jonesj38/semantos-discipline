---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/bsv-app/kernel-bridge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.724348+00:00
---

# archive/apps-navigation_app/bsv-app/kernel-bridge.ts

```ts
/**
 * Kernel Bridge — connects vanilla JS navigator app to TypeScript kernel packages.
 *
 * Built via: bun build kernel-bridge.ts --outfile kernel-bridge.js --target=browser
 * Loaded via <script> tag in index.html, exposes window.SemantosKernel.
 *
 * Self-contained: implements a lightweight object store and flow runner
 * that mirrors LoomStore/FlowRunner APIs without pulling in
 * bun:sqlite or other Node-only dependencies.
 */

import {
  validateExtensionConfig,
  type ExtensionConfig,
  type ObjectTypeDefinition,
  type ConversationFlow,
  type FlowStep,
  type FlowAction,
} from '../../workbench/src/config/extensionConfig';
import {
  enforceL0Constraints,
  enforceL1Constraints,
  type ObjectPayload,
  type IdentityContext,
  type ConstraintResult,
} from '../../extraction/src/governance/constraint-engine';
import {
  checkCompatibility,
  CURRENT_KERNEL_VERSION,
  type CompatResult,
} from '../../extraction/src/governance/version-compat';

// Embedded at build time — loads extension configs
import navigatorConfigRaw from '../../../configs/packages/navigator.json';
import consciousnessConfigRaw from '../../../configs/extensions/consciousness.json';

// ── Lightweight Object Store (browser-safe, no bun:sqlite) ─────

interface KernelObject {
  id: string;
  type: string;
  typeDef: ObjectTypeDefinition;
  fields: Record<string, unknown>;
  visibility: string;
  createdAt: number;
  updatedAt: number;
}

type ChangeListener = (objects: Map<string, KernelObject>) => void;

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

// ── Lightweight Flow Runner (browser-safe) ─────────────────────

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

// ── Initialize Kernel ──────────────────────────────────────────

interface LoadedExtension {
  id: string;
  name: string;
  config: ExtensionConfig;
}

function initKernel() {
  // Load all extension configs
  const extensions: LoadedExtension[] = [];
  for (const raw of [navigatorConfigRaw, consciousnessConfigRaw]) {
    const config = validateExtensionConfig(raw);
    extensions.push({ id: config.id, name: config.name ?? config.id, config });
  }

  // Primary config for object creation (consciousness has the domain types)
  const config = extensions.find(e => e.id === 'consciousness-process')!.config;

  const versionCheck = checkCompatibility(CURRENT_KERNEL_VERSION, '>=0.3.0');
  if (!versionCheck.compatible) {
    console.error('[SemantosKernel] Version incompatible:', versionCheck.message);
  }

  const store = new ObjectStore();
  const flowRunner = new BrowserFlowRunner();

  // Stub identity with SELF_INQUIRY capability
  const identity: IdentityContext = {
    capabilities: [1],
    certId: 'cert:local-consumer-stub',
  };

  // ── High-level API ──────────────────────────────────────────

  /** Find a type definition across all loaded extensions */
  function findTypeDef(typeName: string): { typeDef: ObjectTypeDefinition; extConfig: ExtensionConfig } | null {
    for (const ext of extensions) {
      const typeDef = ext.config.objectTypes.find(t => t.name === typeName);
      if (typeDef) return { typeDef, extConfig: ext.config };
    }
    return null;
  }

  function createObject(typeName: string, fields?: Record<string, unknown>): string | null {
    const found = findTypeDef(typeName);
    if (!found) {
      console.error(`[SemantosKernel] Unknown type: ${typeName}`);
      return null;
    }

    const payload: ObjectPayload = { type: typeName, fields: fields ?? {} };
    const l0 = enforceL0Constraints(payload, found.extConfig);
    if (!l0.valid) {
      console.error('[SemantosKernel] L0 violation:', l0.violations);
      return null;
    }
    const l1 = enforceL1Constraints(payload, found.extConfig, identity);
    if (!l1.valid) {
      console.error('[SemantosKernel] L1 violation:', l1.violations);
      return null;
    }

    return store.create(found.typeDef, fields);
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

  // ── Flow API ────────────────────────────────────────────────

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
    // Auto-create the object defined in onComplete
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

  // ── Governance API ──────────────────────────────────────────

  function validateObject(payload: ObjectPayload): ConstraintResult {
    const l0 = enforceL0Constraints(payload, config);
    if (!l0.valid) return l0;
    return enforceL1Constraints(payload, config, identity);
  }

  function checkVersion(version: string, range: string): CompatResult {
    return checkCompatibility(version, range);
  }

  // ── Store subscription ──────────────────────────────────────

  function subscribe(listener: () => void): () => void {
    return store.subscribe(() => listener());
  }

  // ── Multi-extension discovery API ────────────────────────────

  function listExtensions() {
    return extensions.map(ext => ({
      id: ext.config.id,
      name: ext.config.name ?? ext.config.id,
      types: ext.config.objectTypes.map(t => t.name),
      flowCount: ext.config.flows?.length ?? 0,
      theme: ext.config.theme,
    }));
  }

  function listTypes() {
    const types: string[] = [];
    for (const ext of extensions) {
      for (const t of ext.config.objectTypes) {
        types.push(t.name);
      }
    }
    return types;
  }

  function getExtension(extensionId: string) {
    const ext = extensions.find(e => e.config.id === extensionId);
    if (!ext) return null;
    return {
      id: ext.config.id,
      name: ext.config.name ?? ext.config.id,
      types: ext.config.objectTypes.map(t => t.name),
      flowCount: ext.config.flows?.length ?? 0,
      theme: ext.config.theme,
    };
  }

  return {
    store,
    flowRunner,
    extensions: listExtensions(),
    version: CURRENT_KERNEL_VERSION,
    identity,
    createObject,
    patchObject,
    listObjects,
    getObject,
    listExtensions,
    listTypes,
    getExtension,
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

// ── Expose on window ────────────────────────────────────────────

const kernel = initKernel();
(window as any).SemantosKernel = kernel;

console.log(
  `[SemantosKernel] v${kernel.version} loaded — ${kernel.extensions.length} extensions, ${kernel.listTypes().length} types`,
);

```
