---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/config/verticalConfig.d.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.089630+00:00
---

# runtime/services/src/config/verticalConfig.d.ts

```ts
/** Vertical configuration — drives all loom rendering. */
export interface VerticalConfig {
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
    /** Path to intent taxonomy JSON for this vertical (e.g. "trades" → configs/taxonomy/trades.json). */
    taxonomyPath?: string;
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
    weight?: {
        activity: number;
        relevance: number;
        lastUpdated: number;
    };
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
/** A multi-step conversation flow defined in a vertical config. */
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
/** Validate a vertical config JSON object. Throws on invalid. */
export declare function validateVerticalConfig(data: unknown): VerticalConfig;
//# sourceMappingURL=verticalConfig.d.ts.map
```
