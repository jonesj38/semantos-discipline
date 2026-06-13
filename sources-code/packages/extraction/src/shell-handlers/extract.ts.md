---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/shell-handlers/extract.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.461369+00:00
---

# packages/extraction/src/shell-handlers/extract.ts

```ts
/**
 * Shell extract command — run the semantic extraction pipeline.
 *
 * Usage:
 *   semantos extract <grammar-id>                    Run extraction
 *   semantos extract <grammar-id> --entity <name>    Extract specific entity only
 *   semantos extract <grammar-id> --dry-run          Parse + typecheck, don't commit
 *   semantos extract <grammar-id> --since <date>     Incremental extraction
 *   semantos extract status                          Show last extraction status
 *
 * Cross-references:
 *   pipeline.ts → ExtractionPipeline
 *   extension-grammar-loader.ts → loadExtensionGrammar()
 */

import { readFileSync, existsSync } from 'fs';
import { join, resolve } from 'path';
import type { ShellCommand } from '@semantos/shell/parser';
import type { ShellContext } from '@semantos/shell/types';
import type { ExtensionGrammar } from '@semantos/protocol-types';
import { validateExtensionGrammar } from '@semantos/protocol-types';
import { ExtractionPipeline } from '../index';
import { MemoryAdapter } from '@semantos/protocol-types';
import type { ConsumerBinding, ExtractionOptions } from '../index';
import { GRAMMAR_NOT_FOUND } from '@semantos/shell/error-codes';

/**
 * Route extract subcommands: run (default), status.
 */
export async function routeExtract(cmd: ShellCommand, ctx: ShellContext): Promise<unknown> {
  const subcommand = cmd.flags.subcommand as string | undefined;

  if (subcommand === 'status') {
    return handleStatus(ctx);
  }

  // Default: run extraction
  return handleRun(cmd, ctx);
}

// ── Run Extraction ─────────────────────────────────────────────

async function handleRun(cmd: ShellCommand, ctx: ShellContext): Promise<unknown> {
  const grammarId = (cmd.flags.subcommand as string) ?? (cmd.flags.path as string);
  if (!grammarId) {
    return {
      error: 'Usage: semantos extract <grammar-id> [--entity <name>] [--dry-run] [--since <date>]',
    };
  }

  // Load grammar
  const grammar = loadGrammar(grammarId);
  if (!grammar) {
    return { error: `Grammar not found: ${grammarId}`, code: GRAMMAR_NOT_FOUND };
  }

  // Validate grammar
  const validation = validateExtensionGrammar(grammar);
  if (!validation.valid) {
    const errors = validation.errors.filter(e => e.severity === 'error');
    return {
      error: 'Grammar validation failed',
      validationErrors: errors.map(e => `${e.path}: ${e.message}`),
    };
  }

  // Build binding
  const binding: ConsumerBinding = {
    consumerId: ctx.activeHatId ?? 'shell-user',
    credentials: loadCredentials(grammarId),
  };

  // Build options
  const options: ExtractionOptions = {};
  if (cmd.flags.entity) options.entityFilter = cmd.flags.entity as string;
  if (cmd.flags['dry-run']) options.dryRun = true;
  if (cmd.flags.since) options.since = new Date(cmd.flags.since as string);

  // Run pipeline
  const adapter = ctx.adapter ?? new MemoryAdapter();
  const pipeline = new ExtractionPipeline(ctx.store, adapter);

  const result = await pipeline.extract(grammar, binding, options);

  return {
    grammarId: result.grammarId,
    grammarVersion: result.grammarVersion,
    totalRecords: result.totalRecords,
    created: result.createdObjects,
    updated: result.updatedObjects,
    errors: result.errors.length,
    errorDetails: result.errors.length > 0 ? result.errors : undefined,
    duration: `${result.endTime - result.startTime}ms`,
    dryRun: options.dryRun ?? false,
  };
}

// ── Status ─────────────────────────────────────────────────────

function handleStatus(_ctx: ShellContext): unknown {
  return {
    message: 'Extraction status tracking not yet implemented. Run `semantos extract <grammar-id>` to extract.',
  };
}

// ── Helpers ─────────────────────────────────────────────────────

/** Load a grammar by ID — searches configs/extensions/<name>/grammar.json */
function loadGrammar(grammarId: string): ExtensionGrammar | null {
  // Try direct path first
  if (existsSync(grammarId)) {
    try {
      return JSON.parse(readFileSync(grammarId, 'utf-8'));
    } catch {
      return null;
    }
  }

  // Try standard locations
  const searchPaths = [
    // By grammar ID: com.semantos.propertyme → configs/extensions/propertyme/grammar.json
    join(
      process.cwd(),
      'configs/extensions',
      grammarId.split('.').pop() ?? grammarId,
      'grammar.json',
    ),
    // By short name: propertyme → configs/extensions/propertyme/grammar.json
    join(process.cwd(), 'configs/extensions', grammarId, 'grammar.json'),
  ];

  for (const path of searchPaths) {
    if (existsSync(path)) {
      try {
        return JSON.parse(readFileSync(path, 'utf-8'));
      } catch {
        continue;
      }
    }
  }

  return null;
}

/** Load credentials from a binding file or return empty credentials. */
function loadCredentials(grammarId: string): Record<string, string> {
  const shortName = grammarId.split('.').pop() ?? grammarId;
  const bindingPath = join(process.cwd(), 'configs/bindings', `${shortName}.json`);

  if (existsSync(bindingPath)) {
    try {
      return JSON.parse(readFileSync(bindingPath, 'utf-8'));
    } catch {
      return {};
    }
  }

  return {};
}

```
