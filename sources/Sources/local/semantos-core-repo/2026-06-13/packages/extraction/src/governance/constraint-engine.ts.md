---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/governance/constraint-engine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.458627+00:00
---

# packages/extraction/src/governance/constraint-engine.ts

```ts
/**
 * Constraint enforcement engine — hierarchical L0/L1 constraint validation.
 *
 * L0 validates that ExtensionManifests meet platform policy:
 *   - Meta-schema version compatibility
 *   - Required capabilities declared
 *   - Taxonomy namespace not conflicting with reservations
 *   - Marketplace listing requirements met
 *
 * L1 validates that ConsumerBindings respect manifest grammar:
 *   - Field overrides cannot remove required fields (additions only)
 *   - Taxonomy overrides within grammar's namespace
 *   - Version pin within manifest's supported range
 *
 * Enforcement points:
 *   - Manifest publication (enforceL0Constraints)
 *   - Binding creation (enforceL1Constraints)
 *   - Extraction pipeline startup (enforceL1Constraints)
 *   - Version update (enforceL1Constraints)
 *
 * Cross-references:
 *   governance.ts          → GovernancePolicy, GovernedConsumerBinding, ConstraintResult
 *   extension-manifest.ts  → ExtensionManifest
 *   extension-grammar.ts   → ExtensionGrammar
 */

import type { ExtensionManifest } from '@semantos/protocol-types';
import type {
  GovernancePolicy,
  GovernedConsumerBinding,
  ConstraintResult,
  ConstraintViolation,
} from '@semantos/protocol-types';
/**
 * Enforce L0 constraints on an ExtensionManifest.
 *
 * Checked at: manifest creation, publication (AFFINE→RELEVANT), breaking-change ballot.
 */
export function enforceL0Constraints(
  manifest: ExtensionManifest,
  policy: GovernancePolicy,
): ConstraintResult {
  const violations: ConstraintViolation[] = [];

  if (!manifest.grammar) {
    violations.push({
      level: 'L0',
      rule: 'grammar-required',
      message: 'Manifest must include a grammar.',
    });
    return { valid: false, violations };
  }

  const grammar = manifest.grammar;

  // 1. Meta-schema version check
  if (grammar.metaSchemaVersion !== policy.payload.metaSchemaVersion) {
    // Allow compatible versions (same major)
    const grammarMajor = grammar.metaSchemaVersion.split('.')[0];
    const policyMajor = policy.payload.metaSchemaVersion.split('.')[0];
    if (grammarMajor !== policyMajor) {
      violations.push({
        level: 'L0',
        rule: 'meta-schema-version-incompatible',
        message: `Grammar meta-schema version ${grammar.metaSchemaVersion} is incompatible with policy version ${policy.payload.metaSchemaVersion}.`,
      });
    }
  }

  // 2. Required capabilities check
  const declaredCapabilities = new Set(grammar.capabilities.map(c => c.capability));
  for (const required of policy.payload.requiredCapabilitiesWhitelist) {
    if (!declaredCapabilities.has(required)) {
      violations.push({
        level: 'L0',
        rule: 'required-capability-missing',
        message: `Required capability '${required}' not declared in grammar.`,
        details: { missingCapability: required },
      });
    }
  }

  // 3. Taxonomy namespace reservations check
  const grammarNamespace = grammar.taxonomyNamespace;
  for (const reservation of policy.payload.taxonomyNamespaceReservations) {
    if (grammarNamespace === reservation.namespace || grammarNamespace.startsWith(reservation.namespace + '.')) {
      violations.push({
        level: 'L0',
        rule: 'taxonomy-namespace-reserved',
        message: `Grammar namespace '${grammarNamespace}' conflicts with reserved namespace '${reservation.namespace}': ${reservation.reason}`,
        details: { reservedNamespace: reservation.namespace },
      });
    }
  }

  // 4. Check taxonomy extensions don't use reserved namespaces
  if (grammar.taxonomyExtensions) {
    for (const ext of grammar.taxonomyExtensions) {
      for (const reservation of policy.payload.taxonomyNamespaceReservations) {
        if (ext.parentPath.startsWith(reservation.namespace)) {
          violations.push({
            level: 'L0',
            rule: 'taxonomy-extension-reserved',
            message: `Taxonomy extension under '${ext.parentPath}' conflicts with reserved namespace '${reservation.namespace}'.`,
          });
        }
      }
    }
  }

  // 5. Phase 38 — trust-tier enforcement (conservative-by-default).
  //    Authoritative manifests must carry a formal proof obligation; the
  //    Lean prover hookup ships in Window 7, so until then these manifests
  //    cannot be published. 'delegated' execution authority is reserved
  //    for future federation and is likewise rejected.
  const trustClass = manifest.governanceConfig?.trustClass;
  const proofReq = manifest.governanceConfig?.proofRequirement;

  if (trustClass === 'authoritative' && proofReq !== 'formal') {
    violations.push({
      level: 'L0',
      rule: 'authoritative-requires-formal-proof',
      message:
        'Authoritative trust class requires proofRequirement "formal". ' +
        'Until Window 7 prover hookup, authoritative manifests cannot be published.',
    });
  }

  if (manifest.governanceConfig?.executionAuthority === 'delegated') {
    violations.push({
      level: 'L0',
      rule: 'delegated-execution-not-implemented',
      message:
        'Delegated execution authority is not yet implemented. ' +
        'Use "local_facet" or "hat_scoped".',
    });
  }

  return {
    valid: violations.length === 0,
    violations,
  };
}

/**
 * Enforce L1 constraints on a ConsumerBinding.
 *
 * Checked at: binding creation, version update, every extraction pipeline run.
 */
export function enforceL1Constraints(
  binding: GovernedConsumerBinding,
  manifest: ExtensionManifest,
): ConstraintResult {
  const violations: ConstraintViolation[] = [];

  if (!manifest.grammar) {
    violations.push({
      level: 'L1',
      rule: 'manifest-grammar-missing',
      message: 'Manifest has no grammar — cannot validate binding.',
    });
    return { valid: false, violations };
  }

  const grammar = manifest.grammar;
  const payload = binding.payload;

  // 1. Validate version pin
  const versionViolations = validateVersionPin(payload.grammarVersionPinned, grammar.grammarVersion);
  violations.push(...versionViolations);

  // 2. Validate field overrides — can only ADD fields, not remove/replace
  if (payload.fieldOverrides) {
    for (const override of payload.fieldOverrides) {
      const fieldViolations = validateFieldOverride(override, manifest);
      violations.push(...fieldViolations);
    }
  }

  // 3. Validate taxonomy overrides — must stay within grammar's namespace
  if (payload.taxonomyOverrides) {
    for (const override of payload.taxonomyOverrides) {
      const taxViolations = validateTaxonomyOverride(override, manifest);
      violations.push(...taxViolations);
    }
  }

  return {
    valid: violations.length === 0,
    violations,
  };
}

/**
 * Validate that a version pin is compatible with the grammar's version.
 */
function validateVersionPin(
  versionPin: string,
  grammarVersion: string,
): ConstraintViolation[] {
  const violations: ConstraintViolation[] = [];

  // Basic semver range check: if pin starts with ^ or ~, check major/minor compatibility
  if (versionPin.startsWith('^')) {
    const pinBase = versionPin.slice(1);
    const pinMajor = pinBase.split('.')[0];
    const grammarMajor = grammarVersion.split('.')[0];
    if (pinMajor !== grammarMajor) {
      violations.push({
        level: 'L1',
        rule: 'version-pin-incompatible',
        message: `Version pin '${versionPin}' is incompatible with grammar version ${grammarVersion} (major mismatch).`,
      });
    }
  } else if (versionPin.startsWith('~')) {
    const pinBase = versionPin.slice(1);
    const pinParts = pinBase.split('.');
    const grammarParts = grammarVersion.split('.');
    if (pinParts[0] !== grammarParts[0] || pinParts[1] !== grammarParts[1]) {
      violations.push({
        level: 'L1',
        rule: 'version-pin-incompatible',
        message: `Version pin '${versionPin}' is incompatible with grammar version ${grammarVersion} (minor mismatch).`,
      });
    }
  } else {
    // Exact version pin — must match
    if (versionPin !== grammarVersion) {
      // Allow if the pin could satisfy a range
      const pinParts = versionPin.split('.');
      const grammarParts = grammarVersion.split('.');
      if (pinParts.length === 3 && grammarParts.length === 3 && pinParts[0] !== grammarParts[0]) {
        violations.push({
          level: 'L1',
          rule: 'version-pin-incompatible',
          message: `Version pin '${versionPin}' is not compatible with grammar version ${grammarVersion}.`,
        });
      }
    }
  }

  return violations;
}

/**
 * Validate field overrides — only additions allowed, no removals/replacements.
 */
function validateFieldOverride(
  override: { objectType: string; localFields: Array<{ fieldName: string; sourceType: string; required: boolean; description?: string }> },
  manifest: ExtensionManifest,
): ConstraintViolation[] {
  const violations: ConstraintViolation[] = [];

  if (!manifest.grammar) return violations;

  // Find the object type in the grammar
  const objectType = manifest.grammar.objectTypes.find(
    ot => ot.typePath === override.objectType,
  );

  if (!objectType) {
    violations.push({
      level: 'L1',
      rule: 'field-override-unknown-type',
      message: `Field override references unknown object type '${override.objectType}'.`,
    });
    return violations;
  }

  // Check that local fields don't conflict with existing payload schema fields
  for (const field of override.localFields) {
    if (objectType.payloadSchema[field.fieldName]) {
      violations.push({
        level: 'L1',
        rule: 'field-override-replaces-existing',
        message: `Field override '${field.fieldName}' on '${override.objectType}' conflicts with existing field. Overrides can only add new fields.`,
      });
    }
  }

  return violations;
}

// ── Phase 3: Commerce Constraint Validation ─────────────────

/**
 * Commerce constraint rules from the ExtensionManifest's governanceConfig.
 * These are checked during extraction pipeline execution for Service/Order/Review/Payment creation.
 */
export interface CommerceConstraintRules {
  order?: {
    requiredFields?: string[];
    statusTransitions?: Record<string, string[]>;
  };
  service?: {
    requiredFields?: string[];
    maxBasePrice?: number;
    validPriceTypes?: string[];
  };
  review?: {
    requiredFields?: string[];
    ratingRange?: [number, number];
    maxOnePerCustomerPerOrg?: boolean;
    requiresVerifiedPurchase?: boolean;
  };
  payment?: {
    requiredFields?: string[];
    validMethods?: string[];
  };
}

/**
 * Validate a commerce object against the manifest's constraint rules.
 * Called from chat.ts before creating Service/Order/Review/Payment objects.
 *
 * @param objectType - The commerce object type (Service, Order, Review, Payment)
 * @param fields - The extracted fields from the LLM
 * @param rules - The constraint rules from the ExtensionManifest's governanceConfig
 * @returns ConstraintResult with any violations
 */
export function enforceCommerceConstraints(
  objectType: string,
  fields: Record<string, unknown>,
  rules: CommerceConstraintRules,
): ConstraintResult {
  const violations: ConstraintViolation[] = [];
  const typeLower = objectType.toLowerCase();

  const typeRules = (rules as Record<string, any>)[typeLower];
  if (!typeRules) {
    return { valid: true, violations: [] };
  }

  // Check required fields
  if (typeRules.requiredFields) {
    for (const reqField of typeRules.requiredFields as string[]) {
      if (fields[reqField] === undefined || fields[reqField] === null || fields[reqField] === '') {
        violations.push({
          level: 'L1',
          rule: 'commerce-required-field',
          message: `${objectType} requires field '${reqField}'.`,
        });
      }
    }
  }

  // Service-specific: maxBasePrice, validPriceTypes
  if (typeLower === 'service') {
    if (typeRules.maxBasePrice && typeof fields.basePrice === 'number' && fields.basePrice > typeRules.maxBasePrice) {
      violations.push({
        level: 'L1',
        rule: 'commerce-service-max-price',
        message: `Service basePrice ${fields.basePrice} exceeds maximum ${typeRules.maxBasePrice}.`,
      });
    }
    if (typeRules.validPriceTypes && fields.priceType && !(typeRules.validPriceTypes as string[]).includes(fields.priceType as string)) {
      violations.push({
        level: 'L1',
        rule: 'commerce-service-invalid-price-type',
        message: `Invalid priceType '${fields.priceType}'. Must be one of: ${(typeRules.validPriceTypes as string[]).join(', ')}.`,
      });
    }
  }

  // Review-specific: ratingRange
  if (typeLower === 'review') {
    if (typeRules.ratingRange && typeof fields.rating === 'number') {
      const [rMin, rMax] = typeRules.ratingRange as [number, number];
      if (fields.rating < rMin || fields.rating > rMax) {
        violations.push({
          level: 'L1',
          rule: 'commerce-review-rating-range',
          message: `Rating ${fields.rating} out of range [${rMin}, ${rMax}].`,
        });
      }
    }
  }

  // Order-specific: status transitions
  if (typeLower === 'order' && typeRules.statusTransitions && fields.status) {
    // Validate that the status is a valid state
    const allStates = Object.keys(typeRules.statusTransitions);
    if (!allStates.includes(fields.status as string)) {
      violations.push({
        level: 'L1',
        rule: 'commerce-order-invalid-status',
        message: `Invalid order status '${fields.status}'. Must be one of: ${allStates.join(', ')}.`,
      });
    }
  }

  // Payment-specific: validMethods
  if (typeLower === 'payment') {
    if (typeRules.validMethods && fields.method && !(typeRules.validMethods as string[]).includes(fields.method as string)) {
      violations.push({
        level: 'L1',
        rule: 'commerce-payment-invalid-method',
        message: `Invalid payment method '${fields.method}'. Must be one of: ${(typeRules.validMethods as string[]).join(', ')}.`,
      });
    }
  }

  return {
    valid: violations.length === 0,
    violations,
  };
}

/**
 * Validate taxonomy overrides — must stay within grammar's namespace.
 */
function validateTaxonomyOverride(
  override: { objectType: string; taxonomy: { what?: string; how?: string; why?: string; where?: string } },
  manifest: ExtensionManifest,
): ConstraintViolation[] {
  const violations: ConstraintViolation[] = [];

  if (!manifest.grammar) return violations;

  const namespace = manifest.grammar.taxonomyNamespace;

  // Taxonomy coordinate overrides must reference the grammar's namespace
  for (const [axis, value] of Object.entries(override.taxonomy)) {
    if (value && typeof value === 'string') {
      // The taxonomy value should contain the grammar's namespace
      if (!value.includes(namespace)) {
        violations.push({
          level: 'L1',
          rule: 'taxonomy-override-outside-namespace',
          message: `Taxonomy override on '${override.objectType}' axis '${axis}' value '${value}' is outside grammar namespace '${namespace}'.`,
        });
      }
    }
  }

  return violations;
}

```
