---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-36A-EXTENSION-GRAMMAR-SCHEMA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.665080+00:00
---

# Phase 36A — Extension Grammar JSON Schema

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 2 weeks (with 3-day buffer)
**Prerequisites**: Phase 26H complete (extension rename). Phase 30F.2 (CAS storage adapter). Extension loading infrastructure (ExtensionManifest, ExtensionLoader, ExtensionRegistry) operational.
**Master document**: `PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md`
**Branch**: `phase-36a-extension-grammar-schema`

---

## Context

Every Semantos extension that connects to an external system needs to declare three things: what data it can fetch, how that data maps onto semantic objects, and what capabilities it requires. Currently, each domain-specific phase (28 ISDA, 29 SCADA, 32 Bills of Lading, 35 Music Production) hand-crafts its own type definitions and extraction logic. This works for vertical PRDs but doesn't scale to a marketplace where third-party developers build connectors.

This phase defines the **Extension Grammar JSON schema** — the declarative contract every connector must implement. The grammar is a JSON document that describes:

1. **Source Entities** — what the external system exposes (e.g., PropertyMe's `Property`, `Lease`, `MaintenanceRequest`)
2. **Field Mappings** — how source fields map to semantic object payloads (with type coercion, defaults, transforms)
3. **Taxonomy Coordinates** — WHAT/HOW/WHY assignments for each entity type
4. **Object Type Definitions** — the Semantos object types the connector produces (linearity, phases, capabilities)
5. **Fetch Configuration** — API protocol, authentication scheme, pagination, rate limits
6. **Capability Requirements** — what the connector needs from the host node
7. **Version Contract** — semver with migration rules

The grammar is itself a semantic object (AFFINE in draft, RELEVANT when published), governed by the hierarchical model defined in Phase 36D.

### Design Principles

**Declarative, not imperative.** The grammar describes mappings. It does not contain code. An agent can read a grammar. An agent can write a grammar. The extraction pipeline interprets the grammar at runtime.

**Composable.** A grammar can extend another grammar. The PropertyMe connector might extend a base `property-management` grammar that defines common object types (Property, Lease, Tenant). Specific APIs add their own fields and entity mappings on top.

**Versionable.** Grammars carry semantic versions. The pipeline validates that the grammar version is compatible with the meta-schema version. Major version bumps require governance approval (Phase 36D).

**Self-describing.** The grammar contains enough information for the Extension Manager UI (Phase 36E) to render a human-readable description of what the connector does, what it needs, and what it produces.

---

## Source Files / References

| Alias | Path | What to read |
|-------|------|--------------|
| `EXT:MANIFEST` | `packages/protocol-types/src/extension-manifest.ts` | ExtensionManifest — the grammar extends this |
| `EXT:LOADER` | `packages/protocol-types/src/extension-loader.ts` | ExtensionLoader — grammar loading mechanics |
| `EXT:CONFIG` | `packages/loom/src/config/extensionConfig.ts` | ExtensionConfig — existing config interface (232 lines) |
| `TYPES:PROTO` | `packages/protocol-types/src/index.ts` | Cell header types, linearity, semantic objects |
| `TYPES:STORAGE` | `packages/protocol-types/src/storage.ts` | StorageAdapter interface |
| `CFG:CORE` | `configs/extensions/core.json` | Core extension config — object types, flows, FSM |
| `CFG:TRADES` | `configs/extensions/trades-services.json` | Trades extension — reference for field definitions |
| `TAXONOMY:SEED` | `docs/TAXONOMY-SEED-DESIGN.md` | WHAT/HOW/WHY axis definitions |
| `SHELL:PARSER` | `packages/shell/src/parser.ts` | Shell parser — grammar consumption model |
| `PLATFORM` | `docs/PLATFORM-ARCHITECTURE.md` | Property management vertical — PropertyMe mapping context |

---

## Extension Grammar JSON Schema

### Top-Level Structure

```typescript
interface ExtensionGrammar {
  /** Meta-schema version this grammar targets */
  metaSchemaVersion: string;               // e.g., "1.0.0"
  
  /** Grammar identity */
  grammarId: string;                       // e.g., "com.semantos.propertyme"
  grammarVersion: string;                  // semver e.g., "1.2.0"
  displayName: string;                     // "PropertyMe Connector"
  description: string;                     // Human-readable description
  author: {
    certId: string;                        // Plexus cert ID of the author
    name: string;                          // Display name
    contact?: string;                      // Optional contact URI
  };
  
  /** Optional base grammar to extend */
  extends?: {
    grammarId: string;                     // e.g., "com.semantos.property-management-base"
    versionRange: string;                  // semver range e.g., "^1.0.0"
  };
  
  /** What this grammar connects to */
  source: SourceDeclaration;
  
  /** What semantic objects this grammar produces */
  objectTypes: ObjectTypeDeclaration[];
  
  /** How source entities map to semantic objects */
  entityMappings: EntityMapping[];
  
  /** What the connector needs from the host node */
  capabilities: CapabilityRequirement[];
  
  /** Taxonomy namespace this grammar operates in */
  taxonomyNamespace: string;               // e.g., "property-management"
  
  /** Additional taxonomy nodes this grammar introduces */
  taxonomyExtensions?: TaxonomyExtension[];
  
  /** Migration rules for version upgrades */
  migrations?: MigrationRule[];
}
```

### Source Declaration

```typescript
interface SourceDeclaration {
  /** API protocol */
  protocol: 'rest' | 'graphql' | 'grpc' | 'file' | 'event-stream' | 'database';
  
  /** Base URL template (consumer provides actual credentials via binding) */
  baseUrlTemplate: string;                 // e.g., "https://api.propertyme.com/v2"
  
  /** Authentication scheme */
  auth: {
    type: 'oauth2' | 'api-key' | 'bearer' | 'basic' | 'certificate' | 'none';
    /** Fields the consumer must provide in their binding */
    requiredCredentials: string[];         // e.g., ["client_id", "client_secret", "tenant_id"]
    /** OAuth2-specific config */
    oauth2Config?: {
      authorizationUrl: string;
      tokenUrl: string;
      scopes: string[];
    };
  };
  
  /** Rate limiting declaration */
  rateLimits?: {
    requestsPerSecond?: number;
    requestsPerMinute?: number;
    requestsPerDay?: number;
    concurrentRequests?: number;
  };
  
  /** Pagination strategy */
  pagination?: {
    type: 'cursor' | 'offset' | 'page-number' | 'link-header' | 'none';
    pageSize: number;
    cursorField?: string;                  // e.g., "next_cursor"
    totalField?: string;                   // e.g., "total_count"
  };
  
  /** Source entities available from this API */
  entities: SourceEntity[];
}

interface SourceEntity {
  /** Entity identifier within the grammar */
  entityId: string;                        // e.g., "property"
  
  /** Human-readable name */
  displayName: string;                     // e.g., "Property"
  
  /** API endpoint for listing/fetching */
  endpoint: {
    list: string;                          // e.g., "/properties"
    get: string;                           // e.g., "/properties/{id}"
    webhookEvent?: string;                 // e.g., "property.updated"
  };
  
  /** HTTP method (REST) or operation name (GraphQL) */
  method?: 'GET' | 'POST' | 'PUT';
  
  /** Response shape — where the entity array lives in the API response */
  responseShape: {
    dataPath: string;                      // JSONPath e.g., "$.data.properties"
    idField: string;                       // e.g., "id"
    timestampField?: string;               // e.g., "updated_at"
  };
  
  /** Fields available on this entity */
  fields: SourceField[];
  
  /** Relationships to other source entities */
  relationships?: SourceRelationship[];
}

interface SourceField {
  /** Field name in the source API */
  sourceFieldName: string;                 // e.g., "street_address"
  
  /** Source data type */
  sourceType: 'string' | 'number' | 'boolean' | 'date' | 'datetime' | 'object' | 'array' | 'enum';
  
  /** Whether the field is always present */
  required: boolean;
  
  /** Enum values if sourceType is 'enum' */
  enumValues?: string[];
  
  /** Description for documentation */
  description?: string;
}

interface SourceRelationship {
  /** Related entity ID */
  targetEntityId: string;                  // e.g., "lease"
  
  /** Relationship type */
  type: 'has_many' | 'has_one' | 'belongs_to' | 'many_to_many';
  
  /** Foreign key field on this entity or the target */
  foreignKey: string;                      // e.g., "property_id"
  
  /** Which side holds the foreign key */
  foreignKeyLocation: 'source' | 'target';
}
```

### Entity Mapping

```typescript
interface EntityMapping {
  /** Source entity this mapping applies to */
  sourceEntityId: string;                  // e.g., "maintenance_request"
  
  /** Target Semantos object type */
  targetObjectType: string;                // e.g., "property.maintenance-request"
  
  /** Field-level mappings */
  fieldMappings: FieldMapping[];
  
  /** Taxonomy coordinate assignment */
  taxonomy: {
    what: string | TaxonomyExpression;     // e.g., "what.service.property.maintenance"
    how: string | TaxonomyExpression;      // e.g., computed from source field
    why: string | TaxonomyExpression;      // e.g., "why.maintenance.repair"
    where?: string | TaxonomyExpression;
  };
  
  /** Linearity override (defaults to object type's linearity) */
  linearityOverride?: 'LINEAR' | 'AFFINE' | 'RELEVANT' | 'FUNGIBLE';
  
  /** Initial commerce phase */
  initialPhase?: string;
  
  /** Phase mapping — map source status values to commerce phases */
  phaseMapping?: Record<string, string>;   // e.g., { "open": "SOURCE", "in_progress": "ACTION", "closed": "OUTCOME" }
  
  /** Conditions under which this mapping applies (for polymorphic entities) */
  condition?: MappingCondition;
}

interface FieldMapping {
  /** Source field name (dot-notation for nested) */
  sourceField: string;                     // e.g., "property.street_address"
  
  /** Target payload field name */
  targetField: string;                     // e.g., "address"
  
  /** Type coercion if needed */
  coerce?: {
    from: string;                          // source type
    to: string;                            // target type
    format?: string;                       // e.g., date format "YYYY-MM-DD"
  };
  
  /** Default value if source field is absent */
  default?: unknown;
  
  /** Transform expression (simple, declarative) */
  transform?: FieldTransform;
  
  /** Field visibility for dispatch envelope pattern */
  visibility?: 'visible' | 'hidden' | 'redacted_value' | 'approval_required';
  
  /** Whether this field is required on the target object */
  required: boolean;
}

interface FieldTransform {
  type: 'concat' | 'split' | 'lookup' | 'template' | 'lowercase' | 'uppercase' | 'trim' | 'map_enum' | 'compute';
  
  /** For concat: array of source fields or literals */
  parts?: (string | { literal: string })[];
  
  /** For split: delimiter */
  delimiter?: string;
  
  /** For lookup: mapping table */
  lookupTable?: Record<string, string>;
  
  /** For template: mustache-style template */
  template?: string;
  
  /** For map_enum: source value → target value mapping */
  enumMap?: Record<string, string>;
  
  /** For compute: a safe expression (no arbitrary code) */
  expression?: string;                     // e.g., "source.bedrooms + source.bathrooms"
}

interface MappingCondition {
  field: string;                           // source field to check
  operator: 'eq' | 'neq' | 'in' | 'not_in' | 'exists' | 'not_exists';
  value?: unknown;
}
```

### Object Type Declaration

```typescript
interface ObjectTypeDeclaration {
  /** Type path in the taxonomy */
  typePath: string;                        // e.g., "property.maintenance-request"
  
  /** Human-readable name */
  displayName: string;
  
  /** Description */
  description: string;
  
  /** Linearity */
  linearity: 'LINEAR' | 'AFFINE' | 'RELEVANT' | 'FUNGIBLE';
  
  /** Commerce phases (FSM states) */
  phases: string[];
  
  /** Initial phase */
  initialPhase: string;
  
  /** Payload schema — JSON Schema for the object's payload */
  payloadSchema: Record<string, { type: string; description?: string; enum?: string[] }>;
  
  /** Capability requirements per operation */
  capabilities: Record<string, number[]>;
  
  /** FSM transitions (optional — can reference a flow definition instead) */
  transitions?: {
    fromPhase: string;
    toPhase: string;
    guard?: {
      type: 'capability' | 'value' | 'time' | 'relationship' | 'contextual';
      field: string;
      operator: string;
      value: unknown;
    };
  }[];
}
```

### Capability Requirement

```typescript
interface CapabilityRequirement {
  /** Capability identifier */
  capability: 'network.outbound' | 'storage.write' | 'storage.read' | 'identity.read' | 'metering.consume' | 'taxonomy.extend' | 'governance.propose';
  
  /** Why this capability is needed */
  reason: string;
  
  /** Whether the extension can function without this capability */
  required: boolean;
}
```

### Taxonomy Extension

```typescript
interface TaxonomyExtension {
  /** Which axis */
  axis: 'what' | 'how' | 'why' | 'where';
  
  /** Parent path to attach under */
  parentPath: string;                      // e.g., "what.service.property"
  
  /** New nodes to add */
  nodes: {
    segment: string;                       // e.g., "maintenance"
    displayName: string;
    description: string;
    children?: TaxonomyExtension['nodes'];
  }[];
}
```

### Migration Rule

```typescript
interface MigrationRule {
  /** From version */
  fromVersion: string;                     // e.g., "1.0.0"
  
  /** To version */
  toVersion: string;                       // e.g., "2.0.0"
  
  /** Field renames */
  fieldRenames?: Record<string, string>;   // old → new
  
  /** Fields removed (data preserved in evidence chain) */
  fieldsRemoved?: string[];
  
  /** Fields added with defaults */
  fieldsAdded?: Record<string, unknown>;
  
  /** Object type renames */
  typeRenames?: Record<string, string>;
  
  /** Phase renames */
  phaseRenames?: Record<string, string>;
  
  /** Description of breaking changes */
  breakingChanges?: string;
}
```

---

## Deliverables

### D36A.1 — Meta-Schema Type Definitions

**File**: `packages/protocol-types/src/extension-grammar.ts`

TypeScript interfaces for the complete Extension Grammar schema as specified above. Export from the protocol-types barrel.

Includes:
- `ExtensionGrammar` — top-level interface
- `SourceDeclaration`, `SourceEntity`, `SourceField`, `SourceRelationship`
- `EntityMapping`, `FieldMapping`, `FieldTransform`, `MappingCondition`
- `ObjectTypeDeclaration`
- `CapabilityRequirement`
- `TaxonomyExtension`
- `MigrationRule`

### D36A.2 — Grammar Validator

**File**: `packages/protocol-types/src/extension-grammar-validator.ts`

`validateExtensionGrammar(grammar: unknown): ValidationResult` — validates a JSON document against the meta-schema.

Validation rules:
- All required fields present with correct types
- `grammarVersion` is valid semver
- `metaSchemaVersion` is compatible with current meta-schema version
- All `sourceEntityId` references in `entityMappings` resolve to declared source entities
- All `targetObjectType` references resolve to declared object types
- All `sourceField` references in field mappings resolve to declared source fields
- Taxonomy paths in coordinates are syntactically valid (dot-separated segments)
- No circular `extends` references
- Capability requirements use known capability identifiers
- Migration rules reference valid version pairs
- Field transforms use valid transform types

Returns `{ valid: boolean; errors: ValidationError[] }` with specific error messages per violation.

### D36A.3 — Grammar Loader Integration

**File**: Update `packages/protocol-types/src/extension-loader.ts`

Extend `ExtensionLoader` to load Extension Grammar JSON files alongside existing extension configs:

- `loadExtensionGrammar(grammarPath: string): ExtensionGrammar` — loads and validates a grammar file
- `resolveGrammarExtends(grammar: ExtensionGrammar): ExtensionGrammar` — resolves `extends` chain, merging base grammars
- Integration with existing `loadExtension()` — if an extension directory contains a `grammar.json`, load it as part of the extension

### D36A.4 — Grammar-to-ExtensionConfig Bridge

**File**: `packages/protocol-types/src/grammar-config-bridge.ts`

`grammarToExtensionConfig(grammar: ExtensionGrammar): ExtensionConfig` — converts an Extension Grammar into the existing ExtensionConfig format.

This is the bridge that lets grammars work with the existing loom without rewriting ConfigStore, IntentTaxonomy, or FlowRunner. The grammar is the source of truth; ExtensionConfig is the runtime representation.

Mapping:
- `grammar.objectTypes` → `extensionConfig.objectTypes` (ObjectTypeDefinition[])
- `grammar.taxonomyNamespace` → `extensionConfig.taxonomyNamespace`
- `grammar.taxonomyExtensions` → taxonomy nodes in extensionConfig
- `grammar.objectTypes[].transitions` → flow definitions

### D36A.5 — Shell Command: `semantos grammar`

**File**: Update `packages/shell/src/` (parser, router, subcommands)

New shell subcommand for grammar operations:

```bash
semantos grammar validate <path>         # Validate a grammar JSON file
semantos grammar inspect <grammar-id>    # Show grammar details (entities, mappings, types)
semantos grammar diff <v1> <v2>          # Show differences between two grammar versions
semantos grammar list                    # List installed grammars
semantos grammar test <path> --sample    # Dry-run grammar against sample API data
```

### D36A.6 — Reference Grammar: PropertyMe Stub

**File**: `configs/extensions/propertyme/grammar.json`

A complete Extension Grammar JSON for PropertyMe as a reference implementation. Uses realistic entity definitions (Property, Lease, Tenant, MaintenanceRequest, Inspection, Owner) but with stubbed endpoint URLs. This grammar is the template for Phase 36F's full implementation.

---

## Gate Tests

**File**: `packages/__tests__/phase36a-extension-grammar.test.ts`

### Schema Tests (T1–T6)

```typescript
describe("Extension Grammar schema", () => {
  // T1: validateExtensionGrammar() accepts a valid grammar JSON
  // T2: validateExtensionGrammar() rejects grammar with missing required fields
  // T3: validateExtensionGrammar() rejects grammar with invalid semver
  // T4: validateExtensionGrammar() rejects grammar with unresolved entity references
  // T5: validateExtensionGrammar() rejects grammar with unresolved field references
  // T6: validateExtensionGrammar() rejects grammar with circular extends
});
```

### Loader Tests (T7–T10)

```typescript
describe("Grammar loading", () => {
  // T7: loadExtensionGrammar() loads valid grammar.json from filesystem
  // T8: resolveGrammarExtends() merges base grammar + child grammar
  // T9: resolveGrammarExtends() child fields override base fields
  // T10: loadExtension() discovers and loads grammar.json from extension directory
});
```

### Bridge Tests (T11–T14)

```typescript
describe("Grammar-to-ExtensionConfig bridge", () => {
  // T11: grammarToExtensionConfig() produces valid ExtensionConfig
  // T12: Object types from grammar appear in ExtensionConfig.objectTypes
  // T13: Taxonomy extensions from grammar appear in ExtensionConfig taxonomy
  // T14: FSM transitions from grammar produce flow definitions
});
```

### Shell Tests (T15–T18)

```typescript
describe("Grammar shell commands", () => {
  // T15: `semantos grammar validate` reports valid for PropertyMe stub grammar
  // T16: `semantos grammar validate` reports errors for invalid grammar
  // T17: `semantos grammar inspect` displays entity list, mapping count, type count
  // T18: `semantos grammar list` shows installed grammars
});
```

### Reference Grammar Tests (T19–T22)

```typescript
describe("PropertyMe stub grammar", () => {
  // T19: PropertyMe grammar passes validateExtensionGrammar()
  // T20: PropertyMe grammar declares at least 6 source entities
  // T21: PropertyMe grammar declares at least 6 object types
  // T22: Every source entity has at least one entity mapping
});
```

---

## Completion Criteria

- [ ] `ExtensionGrammar` and all sub-interfaces exported from `packages/protocol-types/src/index.ts`
- [ ] `validateExtensionGrammar()` validates all schema rules specified above
- [ ] `loadExtensionGrammar()` loads grammar JSON from filesystem
- [ ] `resolveGrammarExtends()` resolves grammar inheritance chains
- [ ] `grammarToExtensionConfig()` produces valid ExtensionConfig from grammar
- [ ] `semantos grammar` shell subcommand operational (validate, inspect, diff, list, test)
- [ ] PropertyMe stub grammar at `configs/extensions/propertyme/grammar.json` passes validation
- [ ] Tests T1–T22 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] All existing gate tests still pass
- [ ] All commits follow `phase-36a/D36A.N:` naming convention
- [ ] Branch is `phase-36a-extension-grammar-schema`

---

## What NOT to Do

- **Don't put extraction logic in the grammar.** The grammar declares mappings. The extraction pipeline (Phase 36B) interprets them. No `fetch()` calls, no async operations, no imperative code in the grammar JSON.
- **Don't reinvent JSON Schema.** The `payloadSchema` field in ObjectTypeDeclaration uses JSON Schema syntax. Don't invent a new schema language.
- **Don't make transforms Turing-complete.** Field transforms are declarative (concat, split, lookup, template, enum map, simple arithmetic). No arbitrary code execution. If a transform can't be expressed declaratively, it belongs in a host function (Phase 25.5).
- **Don't skip the bridge.** The grammar-to-ExtensionConfig bridge is critical. The loom already consumes ExtensionConfig. The grammar adds a new source of truth; the bridge keeps backward compatibility.
- **Don't hardcode PropertyMe specifics in the schema.** The meta-schema must be generic enough for any API. PropertyMe is a reference instance, not a special case.

---

## Next Phase

Phase 36B builds the semantic extraction pipeline that reads Extension Grammar JSON and executes the five-stage fetch → parse → typecheck → infer → commit flow.
