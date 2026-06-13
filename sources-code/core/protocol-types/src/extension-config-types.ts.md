---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/extension-config-types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.837351+00:00
---

# core/protocol-types/src/extension-config-types.ts

```ts
/**
 * Extension configuration types — protocol-level definitions consumed by
 * protocol-types, extraction, shell, and workbench (loom).
 *
 * Moved from packages/loom/src/config/extensionConfig.ts to break
 * circular cross-package dependencies. The workbench (loom) re-exports these types.
 */

import type { ManifestGovernanceConfig } from './governance';

export interface ExtensionConfig {
  id: string;
  name: string;
  objectTypes: ObjectTypeDefinition[];
  capabilities: CapabilityDefinition[];
  scripts: ScriptTemplate[];
  commercePhases: string[];
  taxonomy?: TaxonomyTree;
  policies?: PolicyDefinition[];
  theme?: ThemeOverride;
  flows?: ConversationFlow[];
  overlays?: ConfigOverlay[];
  /** Path to intent taxonomy JSON for this extension (e.g. "trades" → configs/taxonomy/trades.json). */
  taxonomyPath?: string;
  /** Filesystem path to the extension's config.json manifest. Set by ExtensionLoader during loading. */
  manifestPath?: string;
  /** Phase 39: Coordination mode bindings — declares which modes this extension contributes to. */
  coordinationModes?: CoordinationModeBinding[];
  /** Phase 39: Extension tier classification for governance gating and marketplace sorting. */
  extensionTier?: ExtensionTier;
  /**
   * Phase 38: Optional governance configuration for extensions that declare
   * their own trust posture (e.g. host-ops.json). When the config is loaded
   * into an ExtensionManifest, this becomes the manifest's governanceConfig.
   */
  governanceConfig?: ManifestGovernanceConfig;
}

export type Archetype = 'identity' | 'thing' | 'action' | 'instrument';

export interface VisibilityConfig {
  states: ('draft' | 'published' | 'revoked')[];
  defaultState: 'draft' | 'published';
  publishTransition?: {
    fromLinearity: 'AFFINE';
    toLinearity: 'RELEVANT';
    requiredCapabilities?: number[];
  };
  revokePreservesEvidence: boolean;
}

export interface AccessPolicy {
  default: 'public' | 'private' | 'hat-scoped';
  overridable: boolean;
}

export interface ObjectTypeDefinition {
  typeHash: string;
  name: string;
  icon: string;
  linearity: 'LINEAR' | 'AFFINE' | 'RELEVANT' | 'DEBUG';
  linearityTransitions?: LinearityTransition[];
  defaultCapabilities: number[];
  fields: FieldDefinition[];
  category?: string;
  maxCells?: number;
  archetype?: Archetype;
  conversationEnabled?: boolean;
  visibility?: VisibilityConfig;
  accessPolicy?: AccessPolicy;
  /** Compiled Lisp policy bindings for this object type (Phase 21). */
  policies?: PolicyBinding[];
}

/** A compiled Lisp policy bound to an object type. */
export interface PolicyBinding {
  name: string;
  /** File path to the .cell file containing the compiled policy. */
  path?: string;
  /** Base64-encoded cell bytes (alternative to path). */
  inlinePayload?: string;
  description?: string;
  /** ISO timestamp of when this binding was applied. */
  appliedAt?: string;
}

export interface LinearityTransition {
  from: 'AFFINE' | 'LINEAR' | 'RELEVANT';
  to: 'LINEAR' | 'RELEVANT';
  trigger: string;
}

export interface CapabilityDefinition {
  id: number;
  name: string;
  description: string;
}

export interface ScriptTemplate {
  id: string;
  name: string;
  description: string;
  requiredCapabilities?: number[];
}

export interface FieldDefinition {
  name: string;
  type: 'string' | 'number' | 'boolean' | 'enum' | 'datetime';
  values?: string[];
  min?: number;
  max?: number;
  requiredCapabilities?: number[];
  /** CC5: carried through from PayloadSchemaField.tier (absent ⇒ 'core'). */
  tier?: 'core' | 'operator-extensible';
  /** CC5: carried through from PayloadSchemaField.carrier (octave-1 render hint). */
  carrier?: { octave: 1 };
}

export interface TaxonomyTree {
  dimensions: TaxonomyDimensionDef[];
}

export interface TaxonomyDimensionDef {
  id: string;
  name: string;
  rootPath: string;
  nodes: TaxonomyNode[];
}

export interface TaxonomyNode {
  path: string;
  name: string;
  axis?: 'what' | 'how' | 'why';
  weight?: { activity: number; relevance: number; lastUpdated: number };
  metadata?: Record<string, unknown>;
  children?: TaxonomyNode[];
}

/** An immutable config extension applied via governance ballot or admin override. */
export interface ConfigOverlay {
  id: string;
  source: 'ballot' | 'admin';
  ballotId?: string;
  appliedAt: number;
  taxonomyNodes?: TaxonomyNode[];
}

export interface PolicyDefinition {
  id: string;
  name: string;
  version: number;
  weights: Record<string, number>;
  thresholds: Record<string, number>;
  activatedAt: string;
  reputationWeights?: Record<string, number>;
}

export interface ThemeOverride {
  colors?: Record<string, string>;
  icons?: Record<string, string>;
}

/** A multi-step conversation flow defined in an extension config. */
export interface ConversationFlow {
  id: string;
  name: string;
  triggerIntents: string[];
  requiredCapabilities?: number[];
  steps: FlowStep[];
  onComplete: FlowAction;
}

/** A single step in a conversation flow. */
export interface FlowStep {
  id: string;
  prompt: string;
  field?: string;
  extractionSchema?: Record<string, string>;
  validation?: 'required' | 'optional';
  /** Optional action to execute when this step completes (before advancing to next step). */
  stepAction?: FlowAction;
}

/** The action to execute when a flow completes (or mid-step via stepAction). */
export interface FlowAction {
  type: 'create' | 'transition' | 'patch' | 'navigate' | 'consume' | 'inspect';
  objectType?: string;
  patchFields?: string[];
  targetPath?: string;
  linearityTransition?: string;
}

// ── Phase 39: Coordination Modes & Extension Tiers ──

/** Context subtypes under each intent mode (1-3-5 pyramid). */
export type DoContext = 'transact' | 'manage' | 'create' | 'play' | 'offer';
export type TalkContext = 'self' | 'direct' | 'squad' | 'agent' | 'broadcast';
export type FindContext = 'memory' | 'market' | 'network' | 'value' | 'truth';
export type IntentContext = DoContext | TalkContext | FindContext;

/** Maps each mode to its valid context subtypes. */
export type ContextForMode<M extends 'do' | 'talk' | 'find'> =
  M extends 'do' ? DoContext :
  M extends 'talk' ? TalkContext :
  M extends 'find' ? FindContext :
  never;

export interface CoordinationModeBinding {
  /** Which mode this extension contributes to. */
  mode: 'do' | 'talk' | 'find';
  /** Which context within the mode (e.g., 'transact' under 'do'). */
  context?: IntentContext;
  /** Object types from this extension that surface in this mode. */
  objectTypes: string[];  // typeHash references
  /** Flows available in this mode. */
  flows?: string[];       // flow ID references
  /** Label shown in the mode's extension selector. */
  label: string;
}

export type ExtensionTier =
  | 'grammar'
  | 'vernacular'
  | 'schema'
  | 'compiler'
  | 'governance'
  | 'connector'
  | 'cosmetic'
  | 'application'
  | 'agent';

/** Validate an extension config JSON object. Throws on invalid. */
export function validateExtensionConfig(data: unknown): ExtensionConfig {
  const config = data as ExtensionConfig;
  if (!config.id || typeof config.id !== 'string') throw new Error('Missing extension config id');
  if (!config.name || typeof config.name !== 'string') throw new Error('Missing extension config name');
  if (!Array.isArray(config.objectTypes) || config.objectTypes.length === 0) throw new Error('Missing objectTypes');
  if (!Array.isArray(config.capabilities)) throw new Error('Missing capabilities');
  if (!Array.isArray(config.scripts)) throw new Error('Missing scripts');
  if (!Array.isArray(config.commercePhases) || config.commercePhases.length === 0) throw new Error('Missing commercePhases');
  for (const ot of config.objectTypes) {
    if (!ot.name || !ot.linearity || !Array.isArray(ot.fields)) {
      throw new Error(`Invalid objectType: ${ot.name ?? 'unnamed'}`);
    }
    if (!ot.typeHash || typeof ot.typeHash !== 'string' || ot.typeHash.length !== 64) {
      throw new Error(`Missing or invalid typeHash on objectType: ${ot.name} (expected 64-char hex SHA256)`);
    }
    if (ot.visibility) {
      const v = ot.visibility;
      if (!Array.isArray(v.states) || v.states.length === 0) {
        throw new Error(`Invalid visibility.states on objectType: ${ot.name}`);
      }
      const validStates = ['draft', 'published', 'revoked'];
      for (const s of v.states) {
        if (!validStates.includes(s)) throw new Error(`Invalid visibility state "${s}" on ${ot.name}`);
      }
      if (!v.states.includes(v.defaultState)) {
        throw new Error(`visibility.defaultState "${v.defaultState}" not in states on ${ot.name}`);
      }
      if (typeof v.revokePreservesEvidence !== 'boolean') {
        throw new Error(`visibility.revokePreservesEvidence must be boolean on ${ot.name}`);
      }
      if (v.publishTransition) {
        if (v.publishTransition.fromLinearity !== 'AFFINE' || v.publishTransition.toLinearity !== 'RELEVANT') {
          throw new Error(`publishTransition must be AFFINE→RELEVANT on ${ot.name}`);
        }
      }
    }
    if (ot.policies) {
      if (!Array.isArray(ot.policies)) {
        throw new Error(`policies must be an array on objectType: ${ot.name}`);
      }
      for (const pb of ot.policies) {
        if (!pb.name || typeof pb.name !== 'string') {
          throw new Error(`PolicyBinding missing name on objectType: ${ot.name}`);
        }
        if (!pb.path && !pb.inlinePayload) {
          throw new Error(`PolicyBinding '${pb.name}' on ${ot.name} must have either path or inlinePayload`);
        }
      }
    }
  }
  if (config.flows !== undefined && !Array.isArray(config.flows)) {
    throw new Error('flows must be an array if provided');
  }
  if (config.flows) {
    for (const flow of config.flows) {
      if (!flow.id || !Array.isArray(flow.triggerIntents) || !Array.isArray(flow.steps) || !flow.onComplete) {
        throw new Error(`Invalid flow: ${flow.id ?? 'unnamed'}`);
      }
    }
  }
  return config;
}

```
