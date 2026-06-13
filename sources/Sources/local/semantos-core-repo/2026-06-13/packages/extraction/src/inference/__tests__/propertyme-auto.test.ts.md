---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/inference/__tests__/propertyme-auto.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.466891+00:00
---

# packages/extraction/src/inference/__tests__/propertyme-auto.test.ts

```ts
/**
 * G-8 — Integration test: PropertyMe Swagger → ExtensionGrammar roundtrip.
 *
 * Uses a representative subset of the PropertyMe OpenAPI spec (synthetically
 * constructed — no network calls). Verifies that the full five-stage
 * autoGrammar pipeline produces a valid AFFINE draft grammar and that the
 * manifest wrapper yields a serialisable config.json.
 *
 * What this test does NOT assert:
 *   - Specific taxonomy paths (those are heuristic and may shift with corpus)
 *   - Promotion to RELEVANT (requires human review + gate + ballot)
 */

import { describe, test, expect, beforeAll } from 'bun:test';
import { autoGrammar } from '../../auto-grammar';
import { wrapInManifest, serialiseManifest } from '../../manifest-wrapper';
import { createSeededAdapter } from '../pask-taxonomy-mapper';
import type { PaskAdapter } from '../../../../../core/pask/bindings/ts/src';
import type { OpenAPIObject } from '../swagger-ingester';

// ---------------------------------------------------------------------------
// Synthetic PropertyMe-style OpenAPI spec
// ---------------------------------------------------------------------------

const PROPERTYME_SPEC: OpenAPIObject = {
  openapi: '3.0.3',
  info: { title: 'PropertyMe API', version: '1.0.0' },
  paths: {
    '/properties': {
      get: {
        operationId: 'listProperties',
        summary: 'List all properties',
        tags: ['properties'],
        responses: {
          '200': {
            description: 'OK',
            content: {
              'application/json': {
                schema: {
                  type: 'array',
                  items: { $ref: '#/components/schemas/Property' },
                },
              },
            },
          },
        },
      },
    },
    '/tenancies': {
      get: {
        operationId: 'listTenancies',
        summary: 'List tenancies',
        tags: ['tenancies'],
        responses: {
          '200': {
            description: 'OK',
            content: {
              'application/json': {
                schema: {
                  type: 'array',
                  items: { $ref: '#/components/schemas/Tenancy' },
                },
              },
            },
          },
        },
      },
    },
    '/owners': {
      get: {
        operationId: 'listOwners',
        summary: 'List property owners',
        tags: ['owners'],
        responses: {
          '200': {
            description: 'OK',
            content: {
              'application/json': {
                schema: {
                  type: 'array',
                  items: { $ref: '#/components/schemas/Owner' },
                },
              },
            },
          },
        },
      },
    },
    '/invoices': {
      get: {
        operationId: 'listInvoices',
        summary: 'List invoices',
        tags: ['invoices'],
        responses: {
          '200': {
            description: 'OK',
            content: {
              'application/json': {
                schema: {
                  type: 'array',
                  items: { $ref: '#/components/schemas/Invoice' },
                },
              },
            },
          },
        },
      },
    },
  },
  components: {
    schemas: {
      Property: {
        type: 'object',
        properties: {
          id: { type: 'string', format: 'uuid' },
          address: { type: 'string', example: '42 King St' },
          suburb: { type: 'string', example: 'Newtown' },
          state: { type: 'string', example: 'NSW' },
          postcode: { type: 'string', example: '2042' },
          bedrooms: { type: 'integer', example: 3 },
          bathrooms: { type: 'integer', example: 1 },
          status: {
            type: 'string',
            enum: ['available', 'tenanted', 'maintenance', 'listed'],
          },
          created_at: { type: 'string', format: 'date-time' },
          updated_at: { type: 'string', format: 'date-time' },
        },
        required: ['id', 'address'],
      },
      Tenancy: {
        type: 'object',
        properties: {
          id: { type: 'string', format: 'uuid' },
          property_id: { type: 'string', format: 'uuid' },
          tenant_name: { type: 'string', example: 'Jane Smith' },
          weekly_rent: { type: 'number', example: 550 },
          start_date: { type: 'string', format: 'date' },
          end_date: { type: 'string', format: 'date' },
          status: {
            type: 'string',
            enum: ['active', 'expired', 'terminated'],
          },
          created_at: { type: 'string', format: 'date-time' },
        },
        required: ['id', 'property_id'],
      },
      Owner: {
        type: 'object',
        properties: {
          id: { type: 'string', format: 'uuid' },
          name: { type: 'string', example: 'John Owner' },
          email: { type: 'string', example: 'owner@example.com' },
          phone: { type: 'string', example: '+61400000000' },
          created_at: { type: 'string', format: 'date-time' },
        },
        required: ['id', 'name'],
      },
      Invoice: {
        type: 'object',
        properties: {
          id: { type: 'string', format: 'uuid' },
          property_id: { type: 'string', format: 'uuid' },
          amount: { type: 'number', example: 1200.0 },
          due_date: { type: 'string', format: 'date' },
          paid_at: { type: 'string', format: 'date-time', nullable: true },
          status: {
            type: 'string',
            enum: ['pending', 'paid', 'overdue', 'cancelled'],
          },
          description: { type: 'string', example: 'Monthly management fee' },
          created_at: { type: 'string', format: 'date-time' },
        },
        required: ['id', 'amount'],
      },
    },
  },
};

// ---------------------------------------------------------------------------
// Shared adapter (expensive — load once)
// ---------------------------------------------------------------------------

let adapter: PaskAdapter;

beforeAll(async () => {
  adapter = await createSeededAdapter();
});

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('autoGrammar: PropertyMe Swagger → ExtensionGrammar', () => {
  test('produces a non-null grammar', async () => {
    const result = await autoGrammar({
      swaggerDoc: PROPERTYME_SPEC,
      domainFlag: 99,
      grammarIdPrefix: 'com.semantos.test',
      adapter,
    });

    expect(result.grammar).not.toBeNull();
  });

  test('detects all four entity types', async () => {
    const result = await autoGrammar({
      swaggerDoc: PROPERTYME_SPEC,
      domainFlag: 99,
      grammarIdPrefix: 'com.semantos.test',
      adapter,
    });

    expect(result.entityGraph.nodes.length).toBe(4);
    const nodeIds = result.entityGraph.nodes.map(n => n.id.toLowerCase());
    expect(nodeIds.some(id => id.includes('propert'))).toBe(true);
    expect(nodeIds.some(id => id.includes('tenanc'))).toBe(true);
    expect(nodeIds.some(id => id.includes('owner'))).toBe(true);
    expect(nodeIds.some(id => id.includes('invoice'))).toBe(true);
  });

  test('grammar has objectTypes for each entity', async () => {
    const result = await autoGrammar({
      swaggerDoc: PROPERTYME_SPEC,
      domainFlag: 99,
      grammarIdPrefix: 'com.semantos.test',
      adapter,
    });

    expect(result.grammar!.objectTypes.length).toBeGreaterThanOrEqual(4);
  });

  test('grammar grammarId uses prefix', async () => {
    const result = await autoGrammar({
      swaggerDoc: PROPERTYME_SPEC,
      domainFlag: 99,
      grammarIdPrefix: 'com.acme',
      adapter,
    });

    expect(result.grammar!.grammarId).toContain('com.acme');
  });

  test('summary string is non-empty', async () => {
    const result = await autoGrammar({
      swaggerDoc: PROPERTYME_SPEC,
      domainFlag: 99,
      adapter,
    });

    expect(result.summary).toContain('Entities: 4');
  });

  test('wrapInManifest yields valid AFFINE manifest', async () => {
    const result = await autoGrammar({
      swaggerDoc: PROPERTYME_SPEC,
      domainFlag: 99,
      adapter,
    });

    const manifest = wrapInManifest(result.grammar!, { authorHat: 'test-hat' });

    expect(manifest.manifestLinearity).toBe('AFFINE');
    expect(manifest.governanceConfig?.trustClass).toBe('cosmetic');
    expect(manifest.governanceConfig?.patchAcceptancePolicy).toBe('author_only');
    expect(manifest.governanceConfig?.executionAuthority).toBe('local_facet');
    expect(manifest.metadata?.author).toBe('test-hat');
  });

  test('serialiseManifest produces valid JSON', async () => {
    const result = await autoGrammar({
      swaggerDoc: PROPERTYME_SPEC,
      domainFlag: 99,
      adapter,
    });

    const manifest = wrapInManifest(result.grammar!);
    const json = serialiseManifest(manifest);
    const parsed = JSON.parse(json);

    expect(parsed.manifestLinearity).toBe('AFFINE');
    expect(parsed.grammar).toBeDefined();
    expect(typeof parsed.id).toBe('string');
    expect(typeof parsed.version).toBe('string');
  });
});

```
