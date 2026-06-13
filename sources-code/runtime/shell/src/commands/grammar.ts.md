---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/commands/grammar.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.373336+00:00
---

# runtime/shell/src/commands/grammar.ts

```ts
/**
 * Shell grammar commands — validate, inspect, diff, list, test Extension Grammars.
 *
 * All five commands use the schema validator and config bridge.
 * Grammar files are loaded from the filesystem via readFileSync.
 *
 * Cross-references:
 *   extension-grammar-validator.ts → validateExtensionGrammar()
 *   grammar-config-bridge.ts      → grammarToExtensionConfig()
 *   parser.ts                     → grammar verb definition
 *   router.ts                     → routing to this handler
 */

import { readFileSync, readdirSync, existsSync } from 'fs';
import { join, resolve } from 'path';
import type { ShellCommand } from '../parser';
import type { ShellContext } from '../types';
import { validateExtensionGrammar } from '@semantos/protocol-types';
import { grammarToExtensionConfig } from '@semantos/protocol-types';
import type { ExtensionGrammar } from '@semantos/protocol-types';
import { INVALID_GRAMMAR_USAGE, INVALID_GRAMMAR, GRAMMAR_LOAD_FAILED, FILE_NOT_FOUND, GRAMMAR_PARSE_FAILED, EXTENSIONS_DIR_SCAN_FAILED } from '../error-codes';

/**
 * Route grammar subcommands: validate, inspect, diff, list, test.
 */
export async function routeGrammar(cmd: ShellCommand, _ctx: ShellContext): Promise<unknown> {
  const subcommand = cmd.flags.subcommand as string | undefined;

  if (!subcommand) {
    return {
      error: 'Usage: semantos grammar <validate|inspect|diff|list|test> [path] [options]',
      code: INVALID_GRAMMAR_USAGE,
      available: ['validate', 'inspect', 'diff', 'list', 'test'],
    };
  }

  switch (subcommand) {
    case 'validate':
      return handleValidate(cmd);
    case 'inspect':
      return handleInspect(cmd);
    case 'diff':
      return handleDiff(cmd);
    case 'list':
      return handleList();
    case 'test':
      return handleTest(cmd);
    default:
      return {
        error: `Unknown grammar subcommand '${subcommand}'. Use: validate, inspect, diff, list, test`,
        code: INVALID_GRAMMAR_USAGE,
      };
  }
}

// ── Validate ────────────────────────────────────────────────────

function handleValidate(cmd: ShellCommand): unknown {
  const filePath = cmd.flags.path as string | undefined;
  if (!filePath) {
    return { error: 'Usage: semantos grammar validate <path>', code: INVALID_GRAMMAR_USAGE };
  }

  const grammar = loadGrammarFile(filePath);
  if ('error' in grammar) return grammar;

  const result = validateExtensionGrammar(grammar);

  if (result.valid) {
    const g = grammar as ExtensionGrammar;
    return {
      valid: true,
      grammarId: g.grammarId,
      grammarVersion: g.grammarVersion,
      displayName: g.displayName,
      sourceEntities: g.source.entities.length,
      objectTypes: g.objectTypes.length,
      entityMappings: g.entityMappings.length,
      capabilities: g.capabilities.length,
      message: `Grammar is valid. ${g.objectTypes.length} object types, ${g.source.entities.length} source entities.`,
    };
  }

  return {
    valid: false,
    errors: result.errors,
    message: `Grammar validation failed with ${result.errors.filter(e => e.severity === 'error').length} errors.`,
  };
}

// ── Inspect ─────────────────────────────────────────────────────

function handleInspect(cmd: ShellCommand): unknown {
  const filePath = cmd.flags.path as string | undefined;
  if (!filePath) {
    return { error: 'Usage: semantos grammar inspect <path>', code: INVALID_GRAMMAR_USAGE };
  }

  const grammar = loadGrammarFile(filePath);
  if ('error' in grammar) return grammar;

  const result = validateExtensionGrammar(grammar);
  if (!result.valid) {
    return { error: 'Grammar is invalid. Run `grammar validate` first.', code: INVALID_GRAMMAR, errors: result.errors };
  }

  const g = grammar as ExtensionGrammar;

  return {
    grammarId: g.grammarId,
    grammarVersion: g.grammarVersion,
    displayName: g.displayName,
    description: g.description,
    author: g.author,
    source: {
      protocol: g.source.protocol,
      baseUrl: g.source.baseUrlTemplate,
      authType: g.source.auth.type,
      entityCount: g.source.entities.length,
      entities: g.source.entities.map(e => ({
        entityId: e.entityId,
        displayName: e.displayName,
        fieldCount: e.fields.length,
        relationships: e.relationships?.length ?? 0,
      })),
    },
    objectTypes: g.objectTypes.map(ot => ({
      typePath: ot.typePath,
      displayName: ot.displayName,
      linearity: ot.linearity,
      phases: ot.phases,
      fieldCount: Object.keys(ot.payloadSchema).length,
      transitionCount: ot.transitions?.length ?? 0,
    })),
    entityMappings: g.entityMappings.map(em => ({
      sourceEntityId: em.sourceEntityId,
      targetObjectType: em.targetObjectType,
      fieldMappingCount: em.fieldMappings.length,
    })),
    capabilities: g.capabilities.map(c => ({
      capability: c.capability,
      required: c.required,
    })),
    taxonomyNamespace: g.taxonomyNamespace,
    taxonomyExtensions: g.taxonomyExtensions?.length ?? 0,
    migrations: g.migrations?.length ?? 0,
  };
}

// ── Diff ────────────────────────────────────────────────────────

function handleDiff(cmd: ShellCommand): unknown {
  const oldPath = cmd.flags.path as string | undefined;
  const newPath = cmd.flags.newPath as string | undefined;

  if (!oldPath || !newPath) {
    return { error: 'Usage: semantos grammar diff <old-path> <new-path>', code: INVALID_GRAMMAR_USAGE };
  }

  const oldGrammar = loadGrammarFile(oldPath);
  if ('error' in oldGrammar) return { error: `Old grammar: ${(oldGrammar as any).error}` };

  const newGrammar = loadGrammarFile(newPath);
  if ('error' in newGrammar) return { error: `New grammar: ${(newGrammar as any).error}` };

  const oldG = oldGrammar as ExtensionGrammar;
  const newG = newGrammar as ExtensionGrammar;

  // Compare source entities
  const oldEntityIds = new Set(oldG.source.entities.map(e => e.entityId));
  const newEntityIds = new Set(newG.source.entities.map(e => e.entityId));
  const addedEntities = [...newEntityIds].filter(id => !oldEntityIds.has(id));
  const removedEntities = [...oldEntityIds].filter(id => !newEntityIds.has(id));

  // Compare object types
  const oldTypePaths = new Set(oldG.objectTypes.map(ot => ot.typePath));
  const newTypePaths = new Set(newG.objectTypes.map(ot => ot.typePath));
  const addedTypes = [...newTypePaths].filter(tp => !oldTypePaths.has(tp));
  const removedTypes = [...oldTypePaths].filter(tp => !newTypePaths.has(tp));

  // Compare entity mappings
  const oldMappings = new Set(oldG.entityMappings.map(em => `${em.sourceEntityId}→${em.targetObjectType}`));
  const newMappings = new Set(newG.entityMappings.map(em => `${em.sourceEntityId}→${em.targetObjectType}`));
  const addedMappings = [...newMappings].filter(m => !oldMappings.has(m));
  const removedMappings = [...oldMappings].filter(m => !newMappings.has(m));

  // Version change
  const versionChanged = oldG.grammarVersion !== newG.grammarVersion;

  return {
    versionChange: versionChanged
      ? { from: oldG.grammarVersion, to: newG.grammarVersion }
      : null,
    sourceEntities: {
      added: addedEntities,
      removed: removedEntities,
      unchanged: [...newEntityIds].filter(id => oldEntityIds.has(id)).length,
    },
    objectTypes: {
      added: addedTypes,
      removed: removedTypes,
      unchanged: [...newTypePaths].filter(tp => oldTypePaths.has(tp)).length,
    },
    entityMappings: {
      added: addedMappings,
      removed: removedMappings,
      unchanged: [...newMappings].filter(m => oldMappings.has(m)).length,
    },
    hasChanges: addedEntities.length > 0 || removedEntities.length > 0 ||
      addedTypes.length > 0 || removedTypes.length > 0 ||
      addedMappings.length > 0 || removedMappings.length > 0 ||
      versionChanged,
  };
}

// ── List ────────────────────────────────────────────────────────

function handleList(): unknown {
  // Scan configs/extensions/ for grammar.json files
  const extensionsDir = resolve(process.cwd(), 'configs/extensions');
  const grammars: unknown[] = [];

  if (!existsSync(extensionsDir)) {
    return { grammars: [], message: 'No extensions directory found' };
  }

  try {
    const entries = readdirSync(extensionsDir, { withFileTypes: true });
    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      const grammarPath = join(extensionsDir, entry.name, 'grammar.json');
      if (!existsSync(grammarPath)) continue;

      try {
        const data = JSON.parse(readFileSync(grammarPath, 'utf-8'));
        const result = validateExtensionGrammar(data);
        grammars.push({
          directory: entry.name,
          grammarId: data.grammarId ?? 'unknown',
          displayName: data.displayName ?? entry.name,
          grammarVersion: data.grammarVersion ?? 'unknown',
          valid: result.valid,
          objectTypes: Array.isArray(data.objectTypes) ? data.objectTypes.length : 0,
          sourceEntities: data.source?.entities?.length ?? 0,
        });
      } catch {
        grammars.push({
          directory: entry.name,
          grammarId: 'parse-error',
          valid: false,
        });
      }
    }
  } catch (err) {
    return { error: `Failed to scan extensions directory: ${err instanceof Error ? err.message : String(err)}`, code: EXTENSIONS_DIR_SCAN_FAILED };
  }

  return { grammars, count: grammars.length };
}

// ── Test ────────────────────────────────────────────────────────

function handleTest(cmd: ShellCommand): unknown {
  const filePath = cmd.flags.path as string | undefined;
  if (!filePath) {
    return { error: 'Usage: semantos grammar test <path>', code: INVALID_GRAMMAR_USAGE };
  }

  const grammar = loadGrammarFile(filePath);
  if ('error' in grammar) return grammar;

  // Step 1: Validate
  const validationResult = validateExtensionGrammar(grammar);
  if (!validationResult.valid) {
    return {
      step: 'validate',
      success: false,
      errors: validationResult.errors,
      message: 'Grammar validation failed.',
    };
  }

  // Step 2: Bridge to ExtensionConfig
  let config;
  try {
    config = grammarToExtensionConfig(grammar as ExtensionGrammar);
  } catch (err) {
    return {
      step: 'bridge',
      success: false,
      error: err instanceof Error ? err.message : String(err),
      code: GRAMMAR_LOAD_FAILED,
      message: 'Grammar-to-config bridge failed.',
    };
  }

  // Step 3: Verify config structure
  const issues: string[] = [];
  if (!config.id) issues.push('Config missing id');
  if (!config.name) issues.push('Config missing name');
  if (!Array.isArray(config.objectTypes) || config.objectTypes.length === 0) {
    issues.push('Config has no object types');
  }
  for (const ot of config.objectTypes) {
    if (!ot.typeHash || ot.typeHash.length !== 64) {
      issues.push(`Object type "${ot.name}" has invalid typeHash`);
    }
    if (!ot.linearity) {
      issues.push(`Object type "${ot.name}" missing linearity`);
    }
  }

  if (issues.length > 0) {
    return {
      step: 'config-verify',
      success: false,
      issues,
      message: 'Config verification found issues.',
    };
  }

  return {
    success: true,
    validation: { valid: true, errors: 0, warnings: validationResult.errors.filter(e => e.severity === 'warning').length },
    config: {
      id: config.id,
      name: config.name,
      objectTypes: config.objectTypes.length,
      capabilities: config.capabilities.length,
      flows: config.flows?.length ?? 0,
      commercePhases: config.commercePhases.length,
      hasTaxonomy: !!config.taxonomy,
    },
    message: 'Grammar valid. Config generated successfully.',
  };
}

// ── Helpers ─────────────────────────────────────────────────────

function loadGrammarFile(filePath: string): Record<string, unknown> | { error: string } {
  const resolved = resolve(process.cwd(), filePath);

  if (!existsSync(resolved)) {
    return { error: `File not found: ${resolved}`, code: FILE_NOT_FOUND };
  }

  try {
    const content = readFileSync(resolved, 'utf-8');
    return JSON.parse(content);
  } catch (err) {
    return { error: `Failed to parse ${resolved}: ${err instanceof Error ? err.message : String(err)}`, code: GRAMMAR_PARSE_FAILED };
  }
}

```
