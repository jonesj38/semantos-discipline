---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase36c-schema-inference-agent.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.584143+00:00
---

# tests/gates/phase36c-schema-inference-agent.test.ts

```ts
/**
 * Phase 36C Gate Tests — Schema Inference Agent
 *
 * T1–T3:   Structure Analyzer
 * T4–T6:   Taxonomy Mapper
 * T7–T9:   Grammar Diff Engine
 * T10–T11: Grammar Composer
 * T12–T13: Inference Pipeline
 * T14:     Shell Command
 */

import { describe, test, expect } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';

const ROOT = join(import.meta.dir, '../..');

// ── Imports ────────────────────────────────────────────────────

import { analyzeStructure } from '../../packages/extraction/src/inference/structure-analyzer';
import { mapTaxonomy } from '../../packages/extraction/src/inference/taxonomy-mapper';
import { diffGrammars } from '../../packages/extraction/src/inference/grammar-diff';
import { composeGrammar } from '../../packages/extraction/src/inference/grammar-composer';
import { InferenceAgent } from '../../packages/extraction/src/inference/pipeline';
import { validateExtensionGrammar } from '../../core/protocol-types/src/extension-grammar-validator';
import { parseCommand } from '../../runtime/shell/src/parser';
import { LoomStore } from '../../runtime/services/src/services/LoomStore';
import type { RawResponse, LLMSettings, EntityGraph, TaxonomyProposal, GrammarDiff } from '../../packages/extraction/src/inference/types';
import type { ExtensionGrammar } from '../../core/protocol-types/src/extension-grammar';

// ── Fixtures ───────────────────────────────────────────────────

const fixtureData = JSON.parse(
  readFileSync(join(ROOT, 'packages/__tests__/fixtures/propertyme-sample-responses.json'), 'utf-8'),
) as RawResponse[];

const propertyMeGrammar = JSON.parse(
  readFileSync(join(ROOT, 'configs/extensions/propertyme/grammar.json'), 'utf-8'),
) as ExtensionGrammar;

/** LLM settings with no API key — taxonomy mapper returns zero-confidence fallbacks. */
const stubSettings: LLMSettings = {
  openRouterApiKey: null,
  modelId: 'test-model',
  temperature: 0.1,
};

// ── Structure Analyzer (T1–T3) ─────────────────────────────────

describe('StructureAnalyzer', () => {
  test('T1: analyzeStructure() detects entity boundaries from array of objects', () => {
    const graph = analyzeStructure(fixtureData);

    expect(graph.nodes.length).toBeGreaterThanOrEqual(2);

    const entityIds = graph.nodes.map(n => n.id);
    expect(entityIds).toContain('property');
    expect(entityIds).toContain('lease');
  });

  test('T2: analyzeStructure() infers field types (string, number, boolean, date, enum, array)', () => {
    const graph = analyzeStructure(fixtureData);

    const propertyEntity = graph.nodes.find(n => n.id === 'property');
    expect(propertyEntity).toBeDefined();

    const fields = propertyEntity!.fields;
    const fieldMap = new Map(fields.map(f => [f.name, f]));

    // String fields
    expect(fieldMap.get('street_address')?.type).toBe('string');
    expect(fieldMap.get('city')?.type).toBe('string');

    // Number fields
    expect(fieldMap.get('bedrooms')?.type).toBe('number');
    expect(fieldMap.get('bathrooms')?.type).toBe('number');

    // Enum field (property_type has <= 10 unique values)
    expect(fieldMap.get('property_type')?.type).toBe('enum');
    expect(fieldMap.get('property_type')?.enumValues).toBeDefined();
    expect(fieldMap.get('property_type')?.enumValues!.length).toBeGreaterThan(0);

    // Datetime field (ISO 8601 with time component)
    expect(fieldMap.get('updated_at')?.type).toBe('datetime');

    // Confidence scores present
    for (const field of fields) {
      expect(field.detectionConfidence).toBeGreaterThanOrEqual(0);
      expect(field.detectionConfidence).toBeLessThanOrEqual(1);
    }
  });

  test('T3: analyzeStructure() detects ID fields, timestamp fields, and relationships', () => {
    const graph = analyzeStructure(fixtureData);

    // ID field detection
    const propertyEntity = graph.nodes.find(n => n.id === 'property');
    const idField = propertyEntity?.fields.find(f => f.name === 'id');
    expect(idField).toBeDefined();

    // Timestamp field detection
    const timestampField = propertyEntity?.fields.find(f => f.name === 'updated_at');
    expect(timestampField).toBeDefined();
    expect(timestampField?.type).toBe('datetime');

    // Relationship detection
    const leaseEntity = graph.nodes.find(n => n.id === 'lease');
    expect(leaseEntity).toBeDefined();

    // lease has property_id and tenant_id → belongs_to relationships
    const leaseEdges = graph.edges.filter(e => e.source === 'lease');
    expect(leaseEdges.length).toBeGreaterThanOrEqual(1);

    const propertyRelation = leaseEdges.find(e => e.target === 'property');
    expect(propertyRelation).toBeDefined();
    expect(propertyRelation?.type).toBe('belongs_to');
    expect(propertyRelation?.foreignKey).toBe('property_id');
    expect(propertyRelation?.confidence).toBeGreaterThan(0);
  });
});

// ── Taxonomy Mapper (T4–T6) ────────────────────────────────────

describe('TaxonomyMapper', () => {
  test('T4: mapTaxonomy() returns TaxonomyProposal with confidence scores for each entity', async () => {
    const graph = analyzeStructure(fixtureData);
    const proposal = await mapTaxonomy(graph, stubSettings);

    expect(proposal.entitySuggestions).toBeDefined();

    // Should have suggestions for each entity
    for (const entity of graph.nodes) {
      const coords = proposal.entitySuggestions[entity.id];
      expect(coords).toBeDefined();
      expect(coords.what).toBeDefined();
      expect(coords.how).toBeDefined();
      expect(coords.why).toBeDefined();

      // Each coordinate has a path and confidence
      expect(typeof coords.what.path).toBe('string');
      expect(typeof coords.what.confidence).toBe('number');
      expect(typeof coords.how.path).toBe('string');
      expect(typeof coords.how.confidence).toBe('number');
      expect(typeof coords.why.path).toBe('string');
      expect(typeof coords.why.confidence).toBe('number');
    }
  });

  test('T5: Confidence thresholds correctly classify high/medium/low', async () => {
    const graph = analyzeStructure(fixtureData);
    const proposal = await mapTaxonomy(graph, stubSettings);

    // With no API key, all confidences should be 0.0 (LLM unavailable)
    for (const coords of Object.values(proposal.entitySuggestions)) {
      expect(coords.what.confidence).toBe(0.0);
      expect(coords.how.confidence).toBe(0.0);
      expect(coords.why.confidence).toBe(0.0);
    }

    // With medium thresholds, all should be classified as low
    const lowCount = Object.values(proposal.entitySuggestions)
      .flatMap(c => [c.what.confidence, c.how.confidence, c.why.confidence])
      .filter(c => c < 0.5).length;

    expect(lowCount).toBe(
      Object.keys(proposal.entitySuggestions).length * 3,
    );
  });

  test('T6: mapTaxonomy() uses pre-filter to suggest fallback paths when LLM is unavailable', async () => {
    const graph = analyzeStructure(fixtureData);
    const proposal = await mapTaxonomy(graph, stubSettings);

    // With no LLM, should fall back to similarity-based suggestions
    const propertyCoords = proposal.entitySuggestions['property'];
    expect(propertyCoords).toBeDefined();

    // The pre-filter should find "what.object.property" or similar path containing "property"
    expect(propertyCoords.what.path).toMatch(/property/);

    // LLM reasoning should indicate unavailability
    expect(propertyCoords.llmReasoning).toContain('unavailable');
  });
});

// ── Grammar Diff Engine (T7–T9) ───────────────────────────────

describe('GrammarDiffEngine', () => {
  test('T7: diffGrammars() matches entities with >70% field overlap to existing grammar entities', () => {
    const graph = analyzeStructure(fixtureData);
    const diff = diffGrammars(graph, [propertyMeGrammar]);

    // property and lease should match the PropertyMe grammar
    const matchedIds = Object.keys(diff.matchedEntities);
    expect(matchedIds.length).toBeGreaterThanOrEqual(1);

    // Check that at least one match has >70% field overlap
    const hasHighOverlap = Object.values(diff.matchedEntities).some(
      m => m.fieldOverlapPercent >= 0.70,
    );
    expect(hasHighOverlap).toBe(true);
  });

  test('T8: diffGrammars() identifies new entities (no match found)', () => {
    // Create a graph with a completely new entity
    const graph = analyzeStructure(fixtureData);
    graph.nodes.push({
      id: 'inspectionSchedule',
      displayName: 'Inspection Schedule',
      fields: [
        { name: 'schedule_id', type: 'string', required: true, sampleValues: ['sched-1'], detectionConfidence: 1.0 },
        { name: 'inspector_name', type: 'string', required: true, sampleValues: ['John'], detectionConfidence: 1.0 },
        { name: 'scheduled_date', type: 'date', required: true, sampleValues: ['2026-05-01'], detectionConfidence: 1.0 },
        { name: 'frequency', type: 'enum', required: true, sampleValues: ['weekly'], enumValues: ['weekly', 'monthly', 'quarterly'], detectionConfidence: 0.9 },
      ],
      nestingLevel: 0,
      sampleCount: 1,
    });

    const diff = diffGrammars(graph, [propertyMeGrammar]);

    // inspectionSchedule should be new (no match in PropertyMe grammar)
    expect(diff.newEntities).toContain('inspectionSchedule');
  });

  test('T9: diffGrammars() detects type mismatches (proposed vs. existing grammar types)', () => {
    // Create a graph where a field has a different type than the grammar
    const graph: EntityGraph = {
      nodes: [{
        id: 'property',
        displayName: 'Property',
        fields: [
          { name: 'id', type: 'number', required: true, sampleValues: [1], detectionConfidence: 1.0 },
          { name: 'street_address', type: 'string', required: true, sampleValues: ['123 Main'], detectionConfidence: 1.0 },
          { name: 'city', type: 'string', required: true, sampleValues: ['Sydney'], detectionConfidence: 1.0 },
          { name: 'state', type: 'string', required: true, sampleValues: ['NSW'], detectionConfidence: 1.0 },
          { name: 'zip', type: 'string', required: true, sampleValues: ['2000'], detectionConfidence: 1.0 },
          { name: 'country', type: 'string', required: true, sampleValues: ['AU'], detectionConfidence: 1.0 },
          { name: 'bedrooms', type: 'number', required: true, sampleValues: [3], detectionConfidence: 1.0 },
          { name: 'bathrooms', type: 'number', required: true, sampleValues: [2], detectionConfidence: 1.0 },
          { name: 'square_footage', type: 'number', required: true, sampleValues: [1800], detectionConfidence: 1.0 },
          { name: 'property_type', type: 'string', required: true, sampleValues: ['house'], detectionConfidence: 1.0 },
          { name: 'owner_id', type: 'string', required: true, sampleValues: ['owner-1'], detectionConfidence: 1.0 },
          { name: 'updated_at', type: 'datetime', required: true, sampleValues: ['2026-04-10T08:30:00Z'], detectionConfidence: 1.0 },
        ],
        nestingLevel: 0,
        sampleCount: 1,
      }],
      edges: [],
      nestedPaths: {},
    };

    const diff = diffGrammars(graph, [propertyMeGrammar]);

    // property should match with high overlap
    expect(diff.matchedEntities['property']).toBeDefined();

    // id field: proposed as 'number' but grammar says 'string'
    const mismatches = diff.typeMismatches['property'] ?? [];
    const idMismatch = mismatches.find(m => m.field === 'id');
    expect(idMismatch).toBeDefined();
    expect(idMismatch?.proposedType).toBe('number');
    expect(idMismatch?.grammarType).toBe('string');
  });
});

// ── Grammar Composer (T10–T11) ─────────────────────────────────

describe('GrammarComposer', () => {
  test('T10: composeGrammar() produces valid ExtensionGrammar that passes validateExtensionGrammar()', () => {
    const graph = analyzeStructure(fixtureData);

    // Build a minimal taxonomy proposal
    const taxonomyProposal: TaxonomyProposal = {
      entitySuggestions: {},
    };
    for (const entity of graph.nodes) {
      taxonomyProposal.entitySuggestions[entity.id] = {
        what: { path: `what.inferred.${entity.id}`, confidence: 0.9 },
        how: { path: 'how.technical.api.rest', confidence: 0.9 },
        why: { path: 'why.integration.data-sync', confidence: 0.9 },
      };
    }

    // Empty diff (no existing grammars)
    const grammarDiff: GrammarDiff = {
      newEntities: graph.nodes.map(n => n.id),
      matchedEntities: {},
      unmappedFields: {},
      typeMismatches: {},
    };

    const result = composeGrammar(graph, taxonomyProposal, grammarDiff, {
      protocol: 'rest',
      baseUrlTemplate: 'https://api.propertyme.com/v2',
      auth: { type: 'oauth2', requiredCredentials: ['client_id', 'client_secret'] },
    });

    // The composed grammar should pass validation
    expect(result.valid).toBe(true);
    expect(result.validationErrors).toBeUndefined();

    // Verify structure
    expect(result.grammar.grammarId).toMatch(/^[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*)+$/);
    expect(result.grammar.grammarVersion).toBe('0.1.0');
    expect(result.grammar.metaSchemaVersion).toBe('1.0.0');
    expect(result.grammar.author.name).toBe('Schema Inference Agent');
    expect(result.grammar.objectTypes.length).toBe(graph.nodes.length);
    expect(result.grammar.entityMappings.length).toBe(graph.nodes.length);

    // All object types should be AFFINE
    for (const ot of result.grammar.objectTypes) {
      expect(ot.linearity).toBe('AFFINE');
    }

    // Double-check with direct validation
    const validationResult = validateExtensionGrammar(result.grammar);
    expect(validationResult.valid).toBe(true);
  });

  test('T11: composeGrammar() includes low-confidence flags in metadata', () => {
    const graph = analyzeStructure(fixtureData);

    // Build taxonomy proposal with mixed confidence
    const taxonomyProposal: TaxonomyProposal = {
      entitySuggestions: {},
    };
    for (const entity of graph.nodes) {
      taxonomyProposal.entitySuggestions[entity.id] = {
        what: { path: `what.inferred.${entity.id}`, confidence: 0.3 }, // Low
        how: { path: 'how.technical.api.rest', confidence: 0.6 },      // Medium
        why: { path: 'why.integration.data-sync', confidence: 0.9 },    // High
      };
    }

    const grammarDiff: GrammarDiff = {
      newEntities: graph.nodes.map(n => n.id),
      matchedEntities: {},
      unmappedFields: {},
      typeMismatches: {},
    };

    const result = composeGrammar(graph, taxonomyProposal, grammarDiff, {
      protocol: 'rest',
      baseUrlTemplate: 'https://api.example.com',
      auth: { type: 'none', requiredCredentials: [] },
    });

    // Should have low-confidence flags
    expect(result.lowConfidenceFlags.length).toBeGreaterThan(0);

    // Should have taxonomy flags for low and medium confidence
    const taxonomyFlags = result.lowConfidenceFlags.filter(f => f.type === 'low_confidence_taxonomy');
    expect(taxonomyFlags.length).toBeGreaterThan(0);

    // Should also have unknown_entity flags for new entities
    const unknownFlags = result.lowConfidenceFlags.filter(f => f.type === 'unknown_entity');
    expect(unknownFlags.length).toBe(graph.nodes.length);
  });
});

// ── Inference Pipeline (T12–T13) ──────────────────────────────

describe('InferenceAgent pipeline', () => {
  test('T12: infer() runs all stages and returns InferenceResult', async () => {
    const store = new LoomStore();
    const agent = new InferenceAgent(store, stubSettings, [propertyMeGrammar]);

    const result = await agent.infer(fixtureData, {
      protocol: 'rest',
      baseUrlTemplate: 'https://api.propertyme.com/v2',
      auth: { type: 'oauth2', requiredCredentials: ['client_id', 'client_secret'] },
    });

    // All pipeline outputs present
    expect(result.grammarId).toBeDefined();
    expect(result.grammar).toBeDefined();
    expect(typeof result.valid).toBe('boolean');
    expect(result.entityGraph).toBeDefined();
    expect(result.entityGraph.nodes.length).toBeGreaterThan(0);
    expect(result.taxonomyProposal).toBeDefined();
    expect(result.grammarDiff).toBeDefined();
    expect(result.lowConfidenceFlags).toBeDefined();

    // Review summary
    expect(result.reviewSummary.totalEntities).toBeGreaterThan(0);

    // Visualization data
    expect(result.entityGraphVisualization.nodes.length).toBe(result.entityGraph.nodes.length);
  });

  test('T13: infer() creates AFFINE semantic object in LoomStore with evidence chain', async () => {
    const store = new LoomStore();
    const agent = new InferenceAgent(store, stubSettings, []);

    const result = await agent.infer(fixtureData, {
      protocol: 'rest',
      baseUrlTemplate: 'https://api.example.com',
      auth: { type: 'none', requiredCredentials: [] },
    });

    // AFFINE object should have been created
    expect(result.objectId).toBeDefined();

    const state = store.getState();
    const obj = state.objects.get(result.objectId!);
    expect(obj).toBeDefined();

    // Check it's an InferredGrammar
    expect(obj!.typeDefinition.name).toBe('InferredGrammar');
    expect(obj!.typeDefinition.linearity).toBe('AFFINE');

    // Check evidence chain — should have at least inference and taxonomy patches
    expect(obj!.patches.length).toBeGreaterThanOrEqual(2);

    // First non-creation patch should be schema_inferred
    const inferencePatch = obj!.patches.find(
      p => (p.delta as Record<string, unknown>).action === 'schema_inferred',
    );
    expect(inferencePatch).toBeDefined();
    expect((inferencePatch!.delta as Record<string, unknown>).grammarId).toBe(result.grammarId);

    // Taxonomy patch should be present
    const taxonomyPatch = obj!.patches.find(
      p => (p.delta as Record<string, unknown>).action === 'taxonomy_mapped',
    );
    expect(taxonomyPatch).toBeDefined();
  });
});

// ── Shell Command (T14) ───────────────────────────────────────

describe('semantos infer shell command', () => {
  test('T14: parser recognizes infer verb and subcommands', () => {
    // infer review
    const reviewCmd = parseCommand(['infer', 'review', 'grammar-123']);
    expect(reviewCmd.verb).toBe('infer');
    expect(reviewCmd.flags.subcommand).toBe('review');
    expect(reviewCmd.flags.path).toBe('grammar-123');

    // infer approve with --publish
    const approveCmd = parseCommand(['infer', 'approve', 'grammar-123', '--publish']);
    expect(approveCmd.verb).toBe('infer');
    expect(approveCmd.flags.subcommand).toBe('approve');
    expect(approveCmd.flags.path).toBe('grammar-123');
    expect(approveCmd.flags.publish).toBe(true);

    // infer reject with --reason
    const rejectCmd = parseCommand(['infer', 'reject', 'grammar-123', '--reason', 'wrong taxonomy']);
    expect(rejectCmd.verb).toBe('infer');
    expect(rejectCmd.flags.subcommand).toBe('reject');
    expect(rejectCmd.flags.reason).toBe('wrong taxonomy');

    // infer list with --status
    const listCmd = parseCommand(['infer', 'list', '--status', 'draft']);
    expect(listCmd.verb).toBe('infer');
    expect(listCmd.flags.subcommand).toBe('list');
    expect(listCmd.flags.status).toBe('draft');

    // infer with file path
    const fileCmd = parseCommand(['infer', './sample.json']);
    expect(fileCmd.verb).toBe('infer');
    expect(fileCmd.flags.subcommand).toBe('./sample.json');
  });
});

```
