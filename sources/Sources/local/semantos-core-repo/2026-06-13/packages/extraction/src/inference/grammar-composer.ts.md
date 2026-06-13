---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/inference/grammar-composer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.462833+00:00
---

# packages/extraction/src/inference/grammar-composer.ts

```ts
/**
 * D36C.4 — Grammar Composer
 *
 * Assembles a complete Extension Grammar JSON from the inference pipeline's
 * outputs (EntityGraph, TaxonomyProposal, GrammarDiff). Validates the result
 * via validateExtensionGrammar() before returning.
 *
 * All inferred grammars default to AFFINE linearity and draft/active phases.
 * Low-confidence inferences are flagged in metadata.
 */

import type {
  ExtensionGrammar,
  SourceDeclaration,
  SourceEntity,
  SourceField,
  SourceFieldType,
  ObjectTypeDeclaration,
  EntityMapping,
  FieldMapping,
} from '@semantos/protocol-types';
import { validateExtensionGrammar } from '@semantos/protocol-types';
import type {
  EntityGraph,
  TaxonomyProposal,
  GrammarDiff,
  ComposedGrammar,
  InferenceFlag,
  ConfidenceThresholds,
} from './types';
import { DEFAULT_CONFIDENCE_THRESHOLDS } from './types';

// ── Main Entry Point ───────────────────────────────────────────

/**
 * Compose a complete Extension Grammar from inference pipeline outputs.
 *
 * @param graph - EntityGraph from StructureAnalyzer
 * @param taxonomy - TaxonomyProposal from TaxonomyMapper
 * @param diff - GrammarDiff from GrammarDiffEngine
 * @param sourceConfig - Partial source configuration (protocol, auth, etc.)
 * @param options - Confidence thresholds for flagging
 */
export function composeGrammar(
  graph: EntityGraph,
  taxonomy: TaxonomyProposal,
  diff: GrammarDiff,
  sourceConfig: Partial<SourceDeclaration>,
  options?: { thresholds?: ConfidenceThresholds; grammarIdPrefix?: string },
): ComposedGrammar {
  const thresholds = options?.thresholds ?? DEFAULT_CONFIDENCE_THRESHOLDS;
  const lowConfidenceFlags: InferenceFlag[] = [];

  // Generate grammar ID from source config
  const grammarId = generateGrammarId(sourceConfig, options?.grammarIdPrefix);

  // Build source entities from EntityGraph
  const sourceEntities = buildSourceEntities(graph);

  // Build full source declaration
  const source: SourceDeclaration = {
    protocol: sourceConfig.protocol ?? 'rest',
    baseUrlTemplate: sourceConfig.baseUrlTemplate ?? 'https://api.example.com',
    auth: sourceConfig.auth ?? { type: 'none', requiredCredentials: [] },
    rateLimits: sourceConfig.rateLimits,
    pagination: sourceConfig.pagination,
    entities: sourceEntities,
  };

  // Build object type declarations
  const objectTypes: ObjectTypeDeclaration[] = [];
  for (const entity of graph.nodes) {
    const coords = taxonomy.entitySuggestions[entity.id];
    const typePath = coords?.what.path.replace(/^what\./, '') || `inferred.${entity.id}`;

    objectTypes.push(buildObjectTypeDeclaration(entity, typePath));
  }

  // Build entity mappings
  const entityMappings: EntityMapping[] = [];
  for (const entity of graph.nodes) {
    const coords = taxonomy.entitySuggestions[entity.id];
    const typePath = coords?.what.path.replace(/^what\./, '') || `inferred.${entity.id}`;

    entityMappings.push(buildEntityMapping(entity, typePath, coords));
  }

  // Flag new entities (not in any existing grammar)
  for (const entityId of diff.newEntities) {
    lowConfidenceFlags.push({
      type: 'unknown_entity',
      entity: entityId,
      message: `Entity '${entityId}' does not match any existing grammar entity. Requires manual classification.`,
    });
  }

  // Flag low-confidence taxonomy suggestions
  for (const [entityId, coords] of Object.entries(taxonomy.entitySuggestions)) {
    for (const axis of ['what', 'how', 'why'] as const) {
      const coord = coords[axis];
      if (coord.confidence < thresholds.high) {
        lowConfidenceFlags.push({
          type: 'low_confidence_taxonomy',
          entity: entityId,
          message: `${axis.toUpperCase()} coordinate '${coord.path}' has confidence ${coord.confidence.toFixed(2)} (below ${thresholds.high}).`,
          confidence: coord.confidence,
          suggestion: coord.path,
        });
      }
    }
  }

  // Flag type mismatches from diff
  for (const [entityId, mismatches] of Object.entries(diff.typeMismatches)) {
    for (const mismatch of mismatches) {
      lowConfidenceFlags.push({
        type: 'type_detection_mismatch',
        entity: entityId,
        field: mismatch.field,
        message: `Field '${mismatch.field}' inferred as '${mismatch.proposedType}' but grammar '${mismatch.grammarId}' expects '${mismatch.grammarType}'.`,
      });
    }
  }

  // Determine taxonomy namespace from grammar ID
  const namespaceParts = grammarId.split('.');
  const taxonomyNamespace = namespaceParts.slice(2).join('-') || 'inferred';

  // Assemble the grammar
  const grammar: ExtensionGrammar = {
    metaSchemaVersion: '1.0.0',
    grammarId,
    grammarVersion: '0.1.0',
    displayName: `Inferred ${sourceConfig.baseUrlTemplate ? extractDomain(sourceConfig.baseUrlTemplate) : 'API'} Connector`,
    description: `Auto-inferred grammar from API sampling on ${new Date().toISOString().split('T')[0]}.`,
    author: { certId: 'inferred', name: 'Schema Inference Agent' },
    source,
    objectTypes,
    entityMappings,
    capabilities: [
      { capability: 'network.outbound', reason: 'API access for data extraction', required: true },
      { capability: 'storage.write', reason: 'Store extracted semantic objects', required: true },
    ],
    taxonomyNamespace,
  };

  // Validate the composed grammar
  const validationResult = validateExtensionGrammar(grammar);

  // Build summary
  const summary = buildSummary(graph, diff, lowConfidenceFlags, validationResult.valid);

  return {
    grammar,
    valid: validationResult.valid,
    validationErrors: validationResult.errors.length > 0 ? validationResult.errors : undefined,
    lowConfidenceFlags,
    summary,
  };
}

// ── Source Entity Construction ──────────────────────────────────

function buildSourceEntities(graph: EntityGraph): SourceEntity[] {
  return graph.nodes.map(entity => {
    const fields: SourceField[] = entity.fields.map(f => ({
      sourceFieldName: f.name,
      sourceType: mapToSourceFieldType(f.type),
      required: f.required,
      enumValues: f.enumValues,
      description: `Inferred ${f.type} field`,
    }));

    // Build relationships from edges
    const relationships = graph.edges
      .filter(e => e.source === entity.id)
      .map(e => ({
        targetEntityId: e.target,
        type: e.type as 'has_many' | 'has_one' | 'belongs_to',
        foreignKey: e.foreignKey,
        foreignKeyLocation: 'source' as const,
      }));

    // Detect ID and timestamp fields
    const idField = entity.fields.find(f =>
      f.name === 'id' || f.name === '_id',
    );
    const timestampField = entity.fields.find(f =>
      /^updated|_at$/.test(f.name),
    );

    return {
      entityId: entity.id,
      displayName: entity.displayName,
      endpoint: {
        list: `/${entity.id}s`,
        get: `/${entity.id}s/{id}`,
      },
      responseShape: {
        dataPath: `$.data.${entity.id}s`,
        idField: idField?.name ?? 'id',
        timestampField: timestampField?.name,
      },
      fields,
      relationships: relationships.length > 0 ? relationships : undefined,
    };
  });
}

// ── Object Type Declaration ────────────────────────────────────

function buildObjectTypeDeclaration(
  entity: { id: string; displayName: string; fields: { name: string; type: string; enumValues?: string[] }[] },
  typePath: string,
): ObjectTypeDeclaration {
  const payloadSchema: Record<string, { type: string; description?: string; enum?: string[] }> = {};

  for (const field of entity.fields) {
    const schemaField: { type: string; description?: string; enum?: string[] } = {
      type: mapToPayloadType(field.type),
    };
    if (field.enumValues && field.enumValues.length > 0) {
      schemaField.enum = field.enumValues;
    }
    payloadSchema[field.name] = schemaField;
  }

  return {
    typePath,
    displayName: entity.displayName,
    description: `Inferred type for ${entity.displayName}`,
    linearity: 'AFFINE',
    phases: ['draft', 'active'],
    initialPhase: 'draft',
    payloadSchema,
    capabilities: {},
  };
}

// ── Entity Mapping ─────────────────────────────────────────────

function buildEntityMapping(
  entity: { id: string; fields: { name: string; required: boolean }[] },
  typePath: string,
  coords?: { what: { path: string }; how: { path: string }; why: { path: string } },
): EntityMapping {
  const fieldMappings: FieldMapping[] = entity.fields.map(f => ({
    sourceField: f.name,
    targetField: f.name,
    required: f.required,
  }));

  return {
    sourceEntityId: entity.id,
    targetObjectType: typePath,
    fieldMappings,
    taxonomy: {
      what: coords?.what.path ?? `what.inferred.${entity.id}`,
      how: coords?.how.path ?? 'how.technical.api.rest',
      why: coords?.why.path ?? 'why.integration.data-sync',
    },
  };
}

// ── Utilities ──────────────────────────────────────────────────

/** Generate a valid grammar ID from source config. */
function generateGrammarId(sourceConfig: Partial<SourceDeclaration>, prefix?: string): string {
  const base = prefix ?? 'com.semantos.inferred';
  if (sourceConfig.baseUrlTemplate) {
    const domain = extractDomain(sourceConfig.baseUrlTemplate);
    const sanitized = domain
      .replace(/[^a-z0-9.-]/gi, '-')
      .toLowerCase()
      .replace(/^-+|-+$/g, '')
      .replace(/-+/g, '-');
    if (sanitized) {
      return `${base}.${sanitized}`;
    }
  }
  return `${base}.unknown-api`;
}

/** Extract domain from a URL template. */
function extractDomain(url: string): string {
  try {
    const u = new URL(url);
    return u.hostname.replace(/^(api|www)\./, '');
  } catch {
    return url.replace(/[^a-z0-9]/gi, '-').toLowerCase();
  }
}

/** Map inferred type to SourceFieldType. */
function mapToSourceFieldType(type: string): SourceFieldType {
  switch (type) {
    case 'string': return 'string';
    case 'number': return 'number';
    case 'boolean': return 'boolean';
    case 'date': return 'date';
    case 'datetime': return 'datetime';
    case 'enum': return 'enum';
    case 'array': return 'array';
    case 'object': return 'object';
    default: return 'string';
  }
}

/** Map inferred type to payload schema type. */
function mapToPayloadType(type: string): string {
  switch (type) {
    case 'enum': return 'enum';
    case 'date': return 'date';
    case 'datetime': return 'datetime';
    default: return type;
  }
}

/** Build human-readable summary. */
function buildSummary(
  graph: EntityGraph,
  diff: GrammarDiff,
  flags: InferenceFlag[],
  valid: boolean,
): string {
  const parts: string[] = [];
  parts.push(`Inferred ${graph.nodes.length} entities with ${graph.edges.length} relationships.`);
  parts.push(`${diff.newEntities.length} new entities, ${Object.keys(diff.matchedEntities).length} matched to existing grammars.`);

  const lowConfTaxonomy = flags.filter(f => f.type === 'low_confidence_taxonomy').length;
  if (lowConfTaxonomy > 0) {
    parts.push(`${lowConfTaxonomy} low-confidence taxonomy suggestions flagged for review.`);
  }

  parts.push(valid ? 'Grammar validation: PASSED.' : 'Grammar validation: FAILED — review errors.');
  return parts.join(' ');
}

```
