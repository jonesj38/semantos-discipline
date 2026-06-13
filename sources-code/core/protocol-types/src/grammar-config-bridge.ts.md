---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar-config-bridge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.844713+00:00
---

# core/protocol-types/src/grammar-config-bridge.ts

```ts
/**
 * Grammar-to-ExtensionConfig Bridge — converts Extension Grammar to ExtensionConfig.
 *
 * This is the contract between declarative grammars and the runtime type system.
 * The grammar is the source of truth; ExtensionConfig is the runtime representation
 * consumed by ConfigStore, IntentTaxonomy, and FlowRunner.
 *
 * Cross-references:
 *   extension-grammar.ts          → ExtensionGrammar (input)
 *   extensionConfig.ts            → ExtensionConfig (output)
 */

import type { ExtensionGrammar, ObjectTypeDeclaration, PayloadSchemaField, CapabilityRequirement } from './extension-grammar';
import type {
  ExtensionConfig,
  ExtensionTier,
  CoordinationModeBinding,
  ObjectTypeDefinition,
  FieldDefinition,
  CapabilityDefinition,
  TaxonomyTree,
  TaxonomyDimensionDef,
  TaxonomyNode,
  ConversationFlow,
  FlowStep,
} from './extension-config-types';

/**
 * Convert an Extension Grammar into an ExtensionConfig.
 *
 * If this function succeeds, the grammar is loadable by the loom.
 * Every schema field maps to an ExtensionConfig field.
 */
export function grammarToExtensionConfig(grammar: ExtensionGrammar): ExtensionConfig {
  const objectTypes = grammar.objectTypes.map(ot => mapObjectType(ot));
  const capabilities = mapCapabilities(grammar.capabilities);
  const taxonomy = mapTaxonomy(grammar);
  const flows = mapFlows(grammar);
  const commercePhases = collectCommercePhases(grammar.objectTypes);

  const extensionTier = inferExtensionTier(grammar);
  const coordinationModes = inferCoordinationModes(grammar, objectTypes);

  return {
    id: grammar.grammarId,
    name: grammar.displayName,
    objectTypes,
    capabilities,
    scripts: [],
    commercePhases,
    taxonomy,
    flows: flows.length > 0 ? flows : undefined,
    extensionTier,
    coordinationModes: coordinationModes.length > 0 ? coordinationModes : undefined,
  };
}

// ── Object Type Mapping ─────────────────────────────────────────

function mapObjectType(ot: ObjectTypeDeclaration): ObjectTypeDefinition {
  const typeHash = computeTypeHash(ot.typePath);
  const fields = mapPayloadSchema(ot.payloadSchema);
  const defaultCapabilities = collectDefaultCapabilities(ot.capabilities);

  const mapped: ObjectTypeDefinition = {
    typeHash,
    name: ot.displayName,
    icon: 'box', // Grammar doesn't specify icons; default to 'box'
    linearity: ot.linearity === 'FUNGIBLE' ? 'RELEVANT' : ot.linearity as 'LINEAR' | 'AFFINE' | 'RELEVANT',
    defaultCapabilities,
    fields,
    category: ot.typePath,
  };

  // Map transitions to linearityTransitions if applicable
  if (ot.transitions && ot.transitions.length > 0) {
    // Only include phase-related transitions, not linearity transitions
    // Linearity transitions are rare in grammar context
  }

  return mapped;
}

function mapPayloadSchema(schema: Record<string, PayloadSchemaField>): FieldDefinition[] {
  return Object.entries(schema).map(([name, field]) => {
    const mapped: FieldDefinition = {
      name,
      type: mapFieldType(field.type),
    };

    if (field.type === 'enum' && field.enum) {
      mapped.values = field.enum;
    }

    // CC5: carry tier/carrier through ONLY when present — a carrier-less /
    // tier-less field maps byte-identically to pre-CC5 behaviour.
    if (field.tier !== undefined) {
      mapped.tier = field.tier;
    }
    if (field.carrier !== undefined) {
      mapped.carrier = field.carrier;
    }

    return mapped;
  });
}

function mapFieldType(grammarType: string): 'string' | 'number' | 'boolean' | 'enum' | 'datetime' {
  switch (grammarType) {
    case 'string': return 'string';
    case 'number': return 'number';
    case 'boolean': return 'boolean';
    case 'enum': return 'enum';
    case 'date':
    case 'datetime': return 'datetime';
    case 'object':
    case 'array': return 'string'; // Complex types serialized as JSON strings in ExtensionConfig
    default: return 'string';
  }
}

function collectDefaultCapabilities(caps: Record<string, number[]>): number[] {
  const set = new Set<number>();
  for (const arr of Object.values(caps)) {
    for (const n of arr) set.add(n);
  }
  return [...set].sort((a, b) => a - b);
}

// ── Capability Mapping ──────────────────────────────────────────

/** Map string capability IDs to numeric capability definitions. */
const CAPABILITY_ID_MAP: Record<string, number> = {
  'network.outbound': 11,
  'storage.write': 12,
  'storage.read': 13,
  'identity.read': 14,
  'metering.consume': 10,
  'taxonomy.extend': 15,
  'governance.propose': 5,
};

function mapCapabilities(caps: CapabilityRequirement[]): CapabilityDefinition[] {
  return caps.map(cap => ({
    id: CAPABILITY_ID_MAP[cap.capability] ?? 0,
    name: cap.capability.toUpperCase().replace(/\./g, '_'),
    description: cap.reason,
  }));
}

// ── Taxonomy Mapping ────────────────────────────────────────────

function mapTaxonomy(grammar: ExtensionGrammar): TaxonomyTree | undefined {
  if (!grammar.taxonomyExtensions || grammar.taxonomyExtensions.length === 0) {
    return undefined;
  }

  const dimensionMap = new Map<string, TaxonomyDimensionDef>();

  for (const ext of grammar.taxonomyExtensions) {
    const dimId = ext.axis;
    if (!dimensionMap.has(dimId)) {
      dimensionMap.set(dimId, {
        id: dimId,
        name: dimId.charAt(0).toUpperCase() + dimId.slice(1),
        rootPath: dimId,
        nodes: [],
      });
    }

    const dim = dimensionMap.get(dimId)!;
    for (const node of ext.nodes) {
      const taxonomyNode = mapTaxonomyExtensionNode(node, ext.parentPath);
      dim.nodes.push(taxonomyNode);
    }
  }

  return { dimensions: [...dimensionMap.values()] };
}

function mapTaxonomyExtensionNode(
  node: { segment: string; displayName: string; description: string; children?: any[] },
  parentPath: string,
): TaxonomyNode {
  const path = `${parentPath}.${node.segment}`;
  const mapped: TaxonomyNode = {
    path,
    name: node.displayName,
  };

  if (node.children && node.children.length > 0) {
    mapped.children = node.children.map((child: any) =>
      mapTaxonomyExtensionNode(child, path),
    );
  }

  return mapped;
}

// ── Flow Mapping ────────────────────────────────────────────────

function mapFlows(grammar: ExtensionGrammar): ConversationFlow[] {
  const flows: ConversationFlow[] = [];

  // Generate flows from object type transitions
  for (const ot of grammar.objectTypes) {
    if (!ot.transitions || ot.transitions.length === 0) continue;

    // Group transitions by fromPhase to create phase-specific flows
    const transitionsByFrom = new Map<string, typeof ot.transitions>();
    for (const tr of ot.transitions) {
      if (!transitionsByFrom.has(tr.fromPhase)) {
        transitionsByFrom.set(tr.fromPhase, []);
      }
      transitionsByFrom.get(tr.fromPhase)!.push(tr);
    }

    // Create a lifecycle flow for this object type
    const flowId = `${ot.typePath.replace(/\./g, '-')}-lifecycle`;
    const steps: FlowStep[] = [];

    let stepIdx = 0;
    for (const [fromPhase, transitions] of transitionsByFrom) {
      const targets = transitions.map(t => t.toPhase).join(', ');
      steps.push({
        id: `step-${stepIdx++}`,
        prompt: `Transition from ${fromPhase}? Available: ${targets}`,
        field: 'targetPhase',
        extractionSchema: { targetPhase: 'string' },
        validation: 'required',
      });
    }

    if (steps.length > 0) {
      flows.push({
        id: flowId,
        name: `${ot.displayName} Lifecycle`,
        triggerIntents: [`transition.${ot.typePath}`, `manage.${ot.typePath}`],
        steps,
        onComplete: {
          type: 'transition',
          objectType: ot.typePath,
        },
      });
    }
  }

  return flows;
}

// ── Commerce Phases ─────────────────────────────────────────────

function collectCommercePhases(objectTypes: ObjectTypeDeclaration[]): string[] {
  const phases = new Set<string>();
  for (const ot of objectTypes) {
    for (const phase of ot.phases) {
      phases.add(phase);
    }
  }
  return [...phases];
}

// ── Extension Tier Inference (Phase 39) ─────────────────────────

function inferExtensionTier(grammar: ExtensionGrammar): ExtensionTier {
  // If grammar has source declarations with endpoints → connector
  if (grammar.source?.entities && grammar.source.entities.length > 0) {
    return 'connector';
  }
  // If grammar only has taxonomy extensions → schema
  if (grammar.taxonomyExtensions && grammar.taxonomyExtensions.length > 0 &&
      (!grammar.objectTypes || grammar.objectTypes.length === 0)) {
    return 'schema';
  }
  // Default: grammar (declarative types only)
  return 'grammar';
}

// ── Coordination Mode Inference (Phase 39) ──────────────────────

function inferCoordinationModes(grammar: ExtensionGrammar, objectTypes: ObjectTypeDefinition[]): CoordinationModeBinding[] {
  const modes: CoordinationModeBinding[] = [];
  const doTypes: string[] = [];
  const talkTypes: string[] = [];
  const findTypes: string[] = [];

  for (const ot of objectTypes) {
    // Conversation-enabled types go to talk
    const grammarOt = grammar.objectTypes.find(g => g.typePath === ot.category);
    if (grammarOt && (grammarOt as any).conversationEnabled) {
      talkTypes.push(ot.typeHash);
      continue;
    }

    // RELEVANT types (published/immutable) lean toward find
    if (ot.linearity === 'RELEVANT') {
      findTypes.push(ot.typeHash);
      continue;
    }

    // Everything else → do (actionable items)
    doTypes.push(ot.typeHash);
  }

  if (doTypes.length > 0) {
    modes.push({ mode: 'do', objectTypes: doTypes, label: grammar.displayName });
  }
  if (talkTypes.length > 0) {
    modes.push({ mode: 'talk', objectTypes: talkTypes, label: grammar.displayName });
  }
  if (findTypes.length > 0) {
    modes.push({ mode: 'find', objectTypes: findTypes, label: grammar.displayName });
  }

  return modes;
}

// ── Type Hash ───────────────────────────────────────────────────

/**
 * Compute a deterministic 64-char hex SHA-256 hash from a type path.
 * This matches the existing typeHash format in ExtensionConfig.
 */
function computeTypeHash(typePath: string): string {
  // Use Node's crypto for SHA-256 (works in Bun too via node:crypto shim)
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { createHash } = require('crypto') as typeof import('crypto');
  return createHash('sha256').update(typePath).digest('hex');
}

```
