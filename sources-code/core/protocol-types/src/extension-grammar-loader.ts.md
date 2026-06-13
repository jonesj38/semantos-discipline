---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/extension-grammar-loader.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.838911+00:00
---

# core/protocol-types/src/extension-grammar-loader.ts

```ts
/**
 * Extension Grammar Loader — loads and resolves grammar JSON files.
 *
 * Reads grammar files via StorageAdapter, validates them, and resolves
 * extends chains by merging base grammars with child overrides.
 *
 * Cross-references:
 *   extension-grammar.ts           → type definitions
 *   extension-grammar-validator.ts → validateExtensionGrammar()
 *   extension-loader.ts            → ExtensionLoader integration
 */

import type { StorageAdapter } from './storage';
import type { ExtensionGrammar } from './extension-grammar';
import { validateExtensionGrammar } from './extension-grammar-validator';

/**
 * Load and validate an Extension Grammar JSON file from storage.
 *
 * @param storage — StorageAdapter for filesystem access
 * @param grammarPath — storage key for the grammar JSON file
 * @returns validated ExtensionGrammar
 * @throws Error if file not found, parse failure, or validation failure
 */
export async function loadExtensionGrammar(
  storage: StorageAdapter,
  grammarPath: string,
): Promise<ExtensionGrammar> {
  const data = await storage.read(grammarPath);
  if (!data) {
    throw new Error(`Grammar file not found at ${grammarPath}`);
  }

  let parsed: unknown;
  try {
    const json = new TextDecoder().decode(data);
    parsed = JSON.parse(json);
  } catch (err) {
    throw new Error(
      `Failed to parse grammar JSON at ${grammarPath}: ${err instanceof Error ? err.message : String(err)}`,
    );
  }

  const result = validateExtensionGrammar(parsed);
  if (!result.valid) {
    const errorMessages = result.errors
      .filter(e => e.severity === 'error')
      .map(e => `  ${e.path}: ${e.message}`)
      .join('\n');
    throw new Error(`Grammar validation failed for ${grammarPath}:\n${errorMessages}`);
  }

  return parsed as ExtensionGrammar;
}

/**
 * Resolve grammar extends by merging a base grammar into a child grammar.
 *
 * Merging rules:
 * - Child scalar fields override base scalar fields
 * - source.entities: child entities added to base entities (child wins on duplicate entityId)
 * - objectTypes: child types added to base types (child wins on duplicate typePath)
 * - entityMappings: child mappings added to base mappings (child wins on duplicate sourceEntityId)
 * - capabilities: union (child wins on duplicate capability)
 * - taxonomyExtensions: concatenated
 * - migrations: concatenated
 *
 * @param child — the child grammar (has extends field)
 * @param base — the base grammar being extended
 * @returns merged grammar with extends field removed
 */
export function resolveGrammarExtends(
  child: ExtensionGrammar,
  base: ExtensionGrammar,
): ExtensionGrammar {
  // Start with child as the base, then fill in from parent where child doesn't override
  const merged: ExtensionGrammar = {
    ...child,
    extends: undefined, // Remove extends after resolution
  };

  // Merge source entities (child entities override base by entityId)
  const childEntityIds = new Set(child.source.entities.map(e => e.entityId));
  const mergedEntities = [...child.source.entities];
  for (const baseEntity of base.source.entities) {
    if (!childEntityIds.has(baseEntity.entityId)) {
      mergedEntities.push(baseEntity);
    }
  }
  merged.source = { ...child.source, entities: mergedEntities };

  // Merge object types (child overrides base by typePath)
  const childTypePaths = new Set(child.objectTypes.map(ot => ot.typePath));
  merged.objectTypes = [...child.objectTypes];
  for (const baseType of base.objectTypes) {
    if (!childTypePaths.has(baseType.typePath)) {
      merged.objectTypes.push(baseType);
    }
  }

  // Merge entity mappings (child overrides base by sourceEntityId)
  const childMappingIds = new Set(child.entityMappings.map(em => em.sourceEntityId));
  merged.entityMappings = [...child.entityMappings];
  for (const baseMapping of base.entityMappings) {
    if (!childMappingIds.has(baseMapping.sourceEntityId)) {
      merged.entityMappings.push(baseMapping);
    }
  }

  // Merge capabilities (child wins on duplicate capability id)
  const childCapIds = new Set(child.capabilities.map(c => c.capability));
  merged.capabilities = [...child.capabilities];
  for (const baseCap of base.capabilities) {
    if (!childCapIds.has(baseCap.capability)) {
      merged.capabilities.push(baseCap);
    }
  }

  // Concatenate taxonomy extensions
  merged.taxonomyExtensions = [
    ...(base.taxonomyExtensions ?? []),
    ...(child.taxonomyExtensions ?? []),
  ];
  if (merged.taxonomyExtensions.length === 0) {
    merged.taxonomyExtensions = undefined;
  }

  // Concatenate migrations
  merged.migrations = [
    ...(base.migrations ?? []),
    ...(child.migrations ?? []),
  ];
  if (merged.migrations.length === 0) {
    merged.migrations = undefined;
  }

  return merged;
}

```
