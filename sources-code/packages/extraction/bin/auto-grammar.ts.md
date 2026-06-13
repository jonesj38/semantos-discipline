---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/bin/auto-grammar.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.451429+00:00
---

# packages/extraction/bin/auto-grammar.ts

```ts
#!/usr/bin/env bun
/**
 * G-7 — auto-grammar CLI
 *
 * Runs the full grammar inference pipeline against a Swagger file or live
 * endpoint and writes the draft ExtensionManifest (config.json) to stdout
 * or --out-dir.
 *
 * Usage:
 *   bun run packages/extraction/bin/auto-grammar.ts \
 *     --swagger <path-or-url>   # OpenAPI JSON file or URL
 *     --lexicon <name>          # e.g. jural, control-systems
 *     --domain-flag <number>    # unique per deployment (required)
 *     [--id-prefix <string>]    # grammar ID prefix, e.g. com.acme
 *     [--out-dir <path>]        # write config.json here (default: stdout)
 *     [--author <hat-id>]       # author hat ID (default: auto)
 *     [--installed <path>]      # JSON file with installed grammars for diff
 *
 * Exit codes:
 *   0 — grammar produced (valid or with low-confidence flags)
 *   1 — inference failed (no entities, bad spec, missing args)
 */

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { autoGrammar } from '../src/auto-grammar';
import { wrapInManifest, serialiseManifest } from '../src/manifest-wrapper';
import type { ExtensionGrammar } from '@semantos/protocol-types';

// ---------------------------------------------------------------------------
// Arg parsing
// ---------------------------------------------------------------------------

const args = process.argv.slice(2);

function flag(name: string): string | undefined {
  const i = args.indexOf(name);
  return i !== -1 ? args[i + 1] : undefined;
}

function requireFlag(name: string): string {
  const v = flag(name);
  if (v === undefined) {
    console.error(`Error: ${name} is required`);
    process.exit(1);
  }
  return v;
}

const swaggerArg  = flag('--swagger');
const liveArg     = flag('--live');
const lexiconName = flag('--lexicon');
const domainFlagS = requireFlag('--domain-flag');
const idPrefix    = flag('--id-prefix');
const outDir      = flag('--out-dir');
const authorHat   = flag('--author') ?? 'auto';
const installedP  = flag('--installed');

if (!swaggerArg && !liveArg) {
  console.error('Error: one of --swagger or --live is required');
  process.exit(1);
}

const domainFlag = parseInt(domainFlagS, 10);
if (isNaN(domainFlag)) {
  console.error('Error: --domain-flag must be an integer');
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Load installed grammars for diff (optional)
// ---------------------------------------------------------------------------

let installedGrammars: ExtensionGrammar[] = [];
if (installedP) {
  try {
    installedGrammars = JSON.parse(readFileSync(resolve(installedP), 'utf-8')) as ExtensionGrammar[];
  } catch (e) {
    console.error(`Warning: could not load installed grammars from ${installedP}: ${e}`);
  }
}

// ---------------------------------------------------------------------------
// Run inference
// ---------------------------------------------------------------------------

console.error('[auto-grammar] Stage 1: building EntityGraph…');

let swaggerDoc: unknown;
if (swaggerArg && !swaggerArg.startsWith('http')) {
  // Local file
  swaggerDoc = JSON.parse(readFileSync(resolve(swaggerArg), 'utf-8'));
}

const result = await autoGrammar({
  swaggerDoc: swaggerDoc as never,
  apiSpecUrl: swaggerArg?.startsWith('http') ? swaggerArg : undefined,
  liveEndpoint: liveArg,
  lexiconName: lexiconName as never,
  domainFlag,
  grammarIdPrefix: idPrefix,
  installedGrammars,
});

console.error(`[auto-grammar] ${result.summary}`);

if (!result.grammar) {
  console.error('[auto-grammar] Error: inference produced no grammar.');
  console.error(result.summary);
  process.exit(1);
}

if (result.lowConfidenceFlags.length > 0) {
  console.error(`[auto-grammar] Low-confidence flags (${result.lowConfidenceFlags.length}):`);
  for (const flag of result.lowConfidenceFlags) {
    console.error(`  • [${flag.pass}] ${flag.field ?? flag.entityId}: ${flag.reason} (confidence=${flag.confidence.toFixed(2)})`);
  }
}

// ---------------------------------------------------------------------------
// Wrap in AFFINE manifest
// ---------------------------------------------------------------------------

const manifest = wrapInManifest(result.grammar, { authorHat });
const json = serialiseManifest(manifest);

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

if (outDir) {
  mkdirSync(outDir, { recursive: true });
  const outPath = join(outDir, 'config.json');
  writeFileSync(outPath, json, 'utf-8');
  console.error(`[auto-grammar] Written to ${outPath}`);
} else {
  process.stdout.write(json + '\n');
}

if (!result.valid) {
  console.error('[auto-grammar] Warning: grammar has validation errors:');
  for (const err of result.validationErrors ?? []) {
    console.error(`  • ${err.message}`);
  }
  process.exit(1);
}

```
