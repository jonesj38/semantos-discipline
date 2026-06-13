---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar/validator-registry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.895953+00:00
---

# core/protocol-types/src/grammar/validator-registry.ts

```ts
/**
 * Per-section validator registry.
 *
 * The orchestrator dispatches each known grammar section through this
 * registry. Each entry is a pure `(grammar, errors, ctx) → ctx'` step
 * — sections that produce information needed by downstream sections
 * (verbs → declared entityIds, schemas → declared objectTypes) thread
 * that data through `ctx`.
 *
 * Adding a new section is a single-file change: implement it, add it
 * to `DEFAULT_SECTIONS`. The orchestrator stays unchanged.
 */

import { ValidationErrorCollector } from './error-collector';
import { validateBindingsSection } from './validators/bindings';
import { validateCapabilitiesSection } from './validators/capabilities';
import {
  validateManifest,
  validateMigrations,
} from './validators/manifest';
import { validatePolicySection } from './validators/policy';
import { validateSchemasSection } from './validators/schemas';
import { validateVerbsSection } from './validators/verbs';

/**
 * Cross-section context carried between dispatcher steps.
 * Sections may read or write any field; the orchestrator initialises
 * with empty defaults.
 */
export interface SectionContext {
  declaredEntityIds: Set<string>;
  declaredSourceFields: Map<string, Set<string>>;
  declaredObjectTypes: Set<string>;
}

export interface ValidatorSection {
  /** Stable identifier — also used as the test fixture key. */
  readonly name: string;
  /** Pure step. Mutates only `ctx` and `errors`. */
  run: (
    grammar: Record<string, unknown>,
    errors: ValidationErrorCollector,
    ctx: SectionContext,
  ) => void;
}

export function makeEmptyContext(): SectionContext {
  return {
    declaredEntityIds: new Set<string>(),
    declaredSourceFields: new Map<string, Set<string>>(),
    declaredObjectTypes: new Set<string>(),
  };
}

/**
 * Default section list, in dispatch order.
 *
 * Order matters because later sections reference data collected by
 * earlier ones: bindings needs declared entityIds + objectTypes.
 */
export const DEFAULT_SECTIONS: readonly ValidatorSection[] = [
  {
    name: 'manifest',
    run: (g, errors) => {
      validateManifest(g, errors);
    },
  },
  {
    name: 'verbs',
    run: (g, errors, ctx) => {
      const collected = validateVerbsSection(g, errors);
      ctx.declaredEntityIds = collected.declaredEntityIds;
      ctx.declaredSourceFields = collected.declaredSourceFields;
    },
  },
  {
    name: 'schemas',
    run: (g, errors, ctx) => {
      ctx.declaredObjectTypes = validateSchemasSection(g, errors);
    },
  },
  {
    name: 'bindings',
    run: (g, errors, ctx) => {
      validateBindingsSection(
        g,
        {
          declaredEntityIds: ctx.declaredEntityIds,
          declaredObjectTypes: ctx.declaredObjectTypes,
          declaredSourceFields: ctx.declaredSourceFields,
        },
        errors,
      );
    },
  },
  {
    name: 'capabilities',
    run: (g, errors) => {
      validateCapabilitiesSection(g, errors);
    },
  },
  {
    name: 'policy',
    run: (g, errors) => {
      validatePolicySection(g, errors);
    },
  },
  {
    name: 'migrations',
    run: (g, errors) => {
      validateMigrations(g, errors);
    },
  },
];

/** Run a section list against a grammar. Used by the orchestrator. */
export function runSections(
  grammar: Record<string, unknown>,
  sections: readonly ValidatorSection[],
  errors: ValidationErrorCollector,
): void {
  const ctx = makeEmptyContext();
  for (const section of sections) {
    section.run(grammar, errors, ctx);
  }
}

```
