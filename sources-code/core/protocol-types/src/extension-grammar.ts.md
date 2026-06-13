---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/extension-grammar.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.838280+00:00
---

# core/protocol-types/src/extension-grammar.ts

```ts
/**
 * Extension Grammar — declarative JSON schema for Semantos connectors.
 *
 * Every extension that connects to an external system declares its data shapes,
 * field mappings, taxonomy coordinates, and capability requirements in this format.
 * The grammar is validated at load time, bridged to ExtensionConfig for the loom,
 * and interpreted by the extraction pipeline (Phase 36B) at runtime.
 *
 * Cross-references:
 *   extension-grammar-validator.ts → validateExtensionGrammar()
 *   grammar-config-bridge.ts      → grammarToExtensionConfig()
 *   extension-grammar-loader.ts   → loadExtensionGrammar(), resolveGrammarExtends()
 *   extensionConfig.ts            → ExtensionConfig (runtime representation)
 */

// ── Top-Level Grammar ───────────────────────────────────────────

export interface ExtensionGrammar {
  /** Meta-schema version this grammar targets (e.g., "1.0.0"). */
  metaSchemaVersion: string;

  /** Unique grammar identifier (dot-separated, e.g., "com.semantos.propertyme"). */
  grammarId: string;

  /** Grammar version (semver, e.g., "1.2.0"). */
  grammarVersion: string;

  /** Human-readable display name. */
  displayName: string;

  /** Description of what this grammar connects to and produces. */
  description: string;

  /** Author identity. */
  author: GrammarAuthor;

  /** Optional base grammar to extend. */
  extends?: GrammarExtends;

  /** What external system this grammar connects to. */
  source: SourceDeclaration;

  /** Semantos object types this grammar produces. */
  objectTypes: ObjectTypeDeclaration[];

  /** How source entities map to semantic objects. */
  entityMappings: EntityMapping[];

  /** Capability requirements from the host node. */
  capabilities: CapabilityRequirement[];

  /** Taxonomy namespace this grammar operates in (e.g., "property-management"). */
  taxonomyNamespace: string;

  /** Additional taxonomy nodes this grammar introduces. */
  taxonomyExtensions?: TaxonomyExtension[];

  /** Migration rules for version upgrades. */
  migrations?: MigrationRule[];
}

export interface GrammarAuthor {
  /** Plexus cert ID of the author. */
  certId: string;
  /** Display name. */
  name: string;
  /** Optional contact URI. */
  contact?: string;
}

export interface GrammarExtends {
  /** Base grammar to extend (e.g., "com.semantos.property-management-base"). */
  grammarId: string;
  /** Semver range for compatibility (e.g., "^1.0.0"). */
  versionRange: string;
}

// ── Source Declaration ───────────────────────────────────────────

export type SourceProtocol = 'rest' | 'graphql' | 'grpc' | 'file' | 'event-stream' | 'database';

export type AuthType = 'oauth2' | 'api-key' | 'bearer' | 'basic' | 'certificate' | 'none';

export interface SourceDeclaration {
  /** API protocol. */
  protocol: SourceProtocol;

  /** Base URL template (consumer provides credentials via binding). */
  baseUrlTemplate: string;

  /** Authentication scheme. */
  auth: SourceAuth;

  /** Rate limiting declaration. */
  rateLimits?: RateLimits;

  /** Pagination strategy. */
  pagination?: PaginationConfig;

  /** Source entities available from this API. */
  entities: SourceEntity[];
}

export interface SourceAuth {
  type: AuthType;
  /** Fields the consumer must provide in their binding. */
  requiredCredentials: string[];
  /** OAuth2-specific configuration. */
  oauth2Config?: {
    authorizationUrl: string;
    tokenUrl: string;
    scopes: string[];
  };
}

export interface RateLimits {
  requestsPerSecond?: number;
  requestsPerMinute?: number;
  requestsPerDay?: number;
  concurrentRequests?: number;
}

export type PaginationType = 'cursor' | 'offset' | 'page-number' | 'link-header' | 'none';

export interface PaginationConfig {
  type: PaginationType;
  pageSize: number;
  cursorField?: string;
  totalField?: string;
}

// ── Source Entity ────────────────────────────────────────────────

export interface SourceEntity {
  /** Entity identifier within the grammar (e.g., "property"). */
  entityId: string;

  /** Human-readable name (e.g., "Property"). */
  displayName: string;

  /** API endpoints for this entity. */
  endpoint: SourceEndpoint;

  /** HTTP method (REST) or operation name (GraphQL). */
  method?: 'GET' | 'POST' | 'PUT';

  /** Response shape — where the entity array lives in the API response. */
  responseShape: ResponseShape;

  /** Fields available on this entity. */
  fields: SourceField[];

  /** Relationships to other source entities. */
  relationships?: SourceRelationship[];
}

export interface SourceEndpoint {
  /** List endpoint (e.g., "/properties"). */
  list: string;
  /** Single-entity endpoint (e.g., "/properties/{id}"). */
  get: string;
  /** Webhook event name (e.g., "property.updated"). */
  webhookEvent?: string;
}

export interface ResponseShape {
  /** JSONPath to the data array (e.g., "$.data.properties"). */
  dataPath: string;
  /** Field name used as the entity ID (e.g., "id"). */
  idField: string;
  /** Timestamp field for incremental sync (e.g., "updated_at"). */
  timestampField?: string;
}

export type SourceFieldType =
  | 'string' | 'number' | 'boolean' | 'date' | 'datetime'
  | 'object' | 'array' | 'enum';

export interface SourceField {
  /** Field name in the source API (e.g., "street_address"). */
  sourceFieldName: string;

  /** Source data type. */
  sourceType: SourceFieldType;

  /** Whether the field is always present. */
  required: boolean;

  /** Enum values if sourceType is 'enum'. */
  enumValues?: string[];

  /** Description for documentation. */
  description?: string;
}

export type RelationshipType = 'has_many' | 'has_one' | 'belongs_to' | 'many_to_many';

export interface SourceRelationship {
  /** Related entity ID. */
  targetEntityId: string;

  /** Relationship type. */
  type: RelationshipType;

  /** Foreign key field name. */
  foreignKey: string;

  /** Which side holds the foreign key. */
  foreignKeyLocation: 'source' | 'target';
}

// ── Object Type Declaration ─────────────────────────────────────

export type ObjectLinearity = 'LINEAR' | 'AFFINE' | 'RELEVANT' | 'FUNGIBLE';

export interface ObjectTypeDeclaration {
  /** Type path in the taxonomy (e.g., "property.maintenance-request"). */
  typePath: string;

  /** Human-readable name. */
  displayName: string;

  /** Description. */
  description: string;

  /** Linearity constraint. */
  linearity: ObjectLinearity;

  /** Commerce phases (FSM states). */
  phases: string[];

  /** Initial phase. */
  initialPhase: string;

  /** Payload schema — JSON Schema for the object's payload. */
  payloadSchema: Record<string, PayloadSchemaField>;

  /** Capability requirements per operation. */
  capabilities: Record<string, number[]>;

  /** FSM transitions. */
  transitions?: TransitionDeclaration[];
}

export interface PayloadSchemaField {
  /** Field type. */
  type: 'string' | 'number' | 'boolean' | 'date' | 'datetime' | 'object' | 'array' | 'enum';
  /** Field description. */
  description?: string;
  /** Enum values if type is 'enum'. */
  enum?: string[];
  /**
   * CC5: provenance/ownership tier. Absent ⇒ treated as 'core' (back-compat).
   * 'operator-extensible' marks a field that is a *source adapter's* mapping
   * (e.g. PropertyMe work-order fields), not part of the cartridge's core
   * cross-trade schema — a different trade simply omits it.
   */
  tier?: 'core' | 'operator-extensible';
  /**
   * CC5: render hint — this field's encoded value may exceed the octave-0
   * budget and is transparently stored/deref'd via the brain's octave-1
   * escalation (the mechanism is already the default; this annotation only
   * tells the renderer to treat the field as large/expandable). Absent ⇒
   * field is expected to fit octave-0. No client-side __o1 handling.
   */
  carrier?: { octave: 1 };
}

export interface TransitionDeclaration {
  fromPhase: string;
  toPhase: string;
  guard?: TransitionGuard;
}

export interface TransitionGuard {
  type: 'capability' | 'value' | 'time' | 'relationship' | 'contextual';
  field: string;
  operator: string;
  value: unknown;
}

// ── Entity Mapping ──────────────────────────────────────────────

export type TaxonomyExpression = string;

export interface EntityMapping {
  /** Source entity this mapping applies to. */
  sourceEntityId: string;

  /** Target Semantos object type (must match an ObjectTypeDeclaration.typePath). */
  targetObjectType: string;

  /** Field-level mappings. */
  fieldMappings: FieldMapping[];

  /** Taxonomy coordinate assignment. */
  taxonomy: EntityTaxonomy;

  /** Linearity override (defaults to object type's linearity). */
  linearityOverride?: ObjectLinearity;

  /** Initial commerce phase. */
  initialPhase?: string;

  /** Map source status values to commerce phases. */
  phaseMapping?: Record<string, string>;

  /** Conditions under which this mapping applies (for polymorphic entities). */
  condition?: MappingCondition;
}

export interface EntityTaxonomy {
  what: string | TaxonomyExpression;
  how: string | TaxonomyExpression;
  why: string | TaxonomyExpression;
  where?: string | TaxonomyExpression;
}

export interface FieldMapping {
  /** Source field name (dot-notation for nested). */
  sourceField: string;

  /** Target payload field name. */
  targetField: string;

  /** Type coercion if needed. */
  coerce?: FieldCoercion;

  /** Default value if source field is absent. */
  default?: unknown;

  /** Transform expression (declarative only). */
  transform?: FieldTransform;

  /** Field visibility for dispatch envelope pattern. */
  visibility?: 'visible' | 'hidden' | 'redacted_value' | 'approval_required';

  /** Whether this field is required on the target object. */
  required: boolean;
}

export interface FieldCoercion {
  from: string;
  to: string;
  format?: string;
}

/**
 * Field transform types — strictly declarative, no arbitrary code.
 *
 * The 'compute' type is constrained to basic arithmetic expressions
 * on source field lookups (e.g., "source.bedrooms + source.bathrooms").
 * Only operators +, -, *, / and source.<field> references are allowed.
 */
export type FieldTransformType =
  | 'concat' | 'split' | 'lookup' | 'template'
  | 'lowercase' | 'uppercase' | 'trim'
  | 'map_enum' | 'compute';

export interface FieldTransform {
  type: FieldTransformType;

  /** For concat: array of source fields or literals. */
  parts?: (string | { literal: string })[];

  /** For split: delimiter. */
  delimiter?: string;

  /** For lookup: mapping table. */
  lookupTable?: Record<string, string>;

  /** For template: mustache-style template. */
  template?: string;

  /** For map_enum: source value to target value mapping. */
  enumMap?: Record<string, string>;

  /**
   * For compute: a constrained arithmetic expression.
   * Only allows: source.<field> references, numeric literals, and +, -, *, / operators.
   * No function calls, no string operations, no arbitrary code.
   */
  expression?: string;
}

export interface MappingCondition {
  field: string;
  operator: 'eq' | 'neq' | 'in' | 'not_in' | 'exists' | 'not_exists';
  value?: unknown;
}

// ── Capability Requirement ──────────────────────────────────────

export type CapabilityId =
  | 'network.outbound'
  | 'storage.write'
  | 'storage.read'
  | 'identity.read'
  | 'metering.consume'
  | 'taxonomy.extend'
  | 'governance.propose';

export interface CapabilityRequirement {
  /** Capability identifier. */
  capability: CapabilityId;

  /** Why this capability is needed. */
  reason: string;

  /** Whether the extension can function without this capability. */
  required: boolean;
}

// ── Taxonomy Extension ──────────────────────────────────────────

export type TaxonomyAxis = 'what' | 'how' | 'why' | 'where';

export interface TaxonomyExtension {
  /** Which taxonomy axis. */
  axis: TaxonomyAxis;

  /** Parent path to attach under (e.g., "what.service.property"). */
  parentPath: string;

  /** New nodes to add. */
  nodes: TaxonomyExtensionNode[];
}

export interface TaxonomyExtensionNode {
  /** Path segment (e.g., "maintenance"). */
  segment: string;
  /** Display name. */
  displayName: string;
  /** Description. */
  description: string;
  /** Child nodes. */
  children?: TaxonomyExtensionNode[];
}

// ── Migration Rule ──────────────────────────────────────────────

export interface MigrationRule {
  /** From version (e.g., "1.0.0"). */
  fromVersion: string;

  /** To version (e.g., "2.0.0"). */
  toVersion: string;

  /** Field renames (old → new). */
  fieldRenames?: Record<string, string>;

  /** Fields removed (data preserved in evidence chain). */
  fieldsRemoved?: string[];

  /** Fields added with defaults. */
  fieldsAdded?: Record<string, unknown>;

  /** Object type renames. */
  typeRenames?: Record<string, string>;

  /** Phase renames. */
  phaseRenames?: Record<string, string>;

  /** Description of breaking changes. */
  breakingChanges?: string;
}

// ── Validation Result ───────────────────────────────────────────

export interface GrammarValidationError {
  /** JSONPath-style path to the error (e.g., "objectTypes[0].payloadSchema.foo.type"). */
  path: string;
  /** Human-readable error message. */
  message: string;
  /** Error severity. */
  severity: 'error' | 'warning';
}

export interface GrammarValidationResult {
  /** Whether the grammar is valid (no errors; warnings are acceptable). */
  valid: boolean;
  /** All validation errors and warnings collected. */
  errors: GrammarValidationError[];
}

```
