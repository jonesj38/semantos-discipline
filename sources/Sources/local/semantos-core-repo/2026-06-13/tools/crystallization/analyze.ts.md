---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/crystallization/analyze.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.545828+00:00
---

# tools/crystallization/analyze.ts

```ts
#!/usr/bin/env bun
/**
 * Architectural Crystallization Analyzer
 *
 * Usage:
 *   bun tools/crystallization/analyze.ts <config.json> [--output <prefix>] [--auto-vocab <N>]
 *
 * The config file specifies epochs (paths + optional date ranges) and vocabulary.
 * Pass --auto-vocab N to supplement or replace the vocabulary with top-N TF-IDF terms.
 */

import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import type { AnalysisConfig, AnalysisResult, ConceptDef } from './types';
import { loadCorpus, extractAutoVocab } from './lib/corpus';
import { buildPask } from './lib/pask';
import { buildEpochStats, classifyLifecycles } from './lib/lifecycle';
import { buildWeeklyTimeline, detectBursts, detectCrossovers } from './lib/temporal';
import { printReport, writeMarkdownReport } from './lib/report';

// ── CLI arg parsing ───────────────────────────────────────────────────────────

const args = process.argv.slice(2);
if (args.length === 0 || args[0] === '--help') {
  console.log([
    'Usage: bun tools/crystallization/analyze.ts <config.json> [options]',
    '',
    'Options:',
    '  --output <prefix>    Output file prefix (default: crystallization-<project>)',
    '  --auto-vocab <N>     Extract top-N TF-IDF terms from corpus (supplements vocabulary file)',
    '  --auto-vocab-only    Use ONLY auto-extracted vocabulary (ignore vocabularyFile)',
    '  --no-report          Skip writing .md/.json output files',
    '  --quiet              Suppress console output',
  ].join('\n'));
  process.exit(0);
}

const configPath = resolve(args[0]);
let outputPrefix: string | null = null;
let autoVocabN = 0;
let autoVocabOnly = false;
let writeFiles = true;
let quiet = false;

for (let i = 1; i < args.length; i++) {
  if (args[i] === '--output' && args[i + 1]) { outputPrefix = args[++i]; }
  else if (args[i] === '--auto-vocab' && args[i + 1]) { autoVocabN = parseInt(args[++i], 10); }
  else if (args[i] === '--auto-vocab-only') { autoVocabOnly = true; }
  else if (args[i] === '--no-report') { writeFiles = false; }
  else if (args[i] === '--quiet') { quiet = true; }
}

// ── Load config ───────────────────────────────────────────────────────────────

let config: AnalysisConfig;
try {
  config = JSON.parse(readFileSync(configPath, 'utf8'));
} catch (e) {
  console.error(`Failed to read config: ${configPath}\n${e}`);
  process.exit(1);
}

// Resolve epoch paths relative to the config file's directory
const configDir = dirname(configPath);
for (const epoch of config.epochs) {
  if (!epoch.path.startsWith('/')) {
    epoch.path = resolve(configDir, epoch.path);
  }
}

// ── Load vocabulary ───────────────────────────────────────────────────────────

let concepts: ConceptDef[] = [];

if (!autoVocabOnly && config.vocabularyFile) {
  const vocabPath = config.vocabularyFile.startsWith('/')
    ? config.vocabularyFile
    : resolve(configDir, config.vocabularyFile);
  try {
    concepts = JSON.parse(readFileSync(vocabPath, 'utf8'));
    if (!quiet) console.log(`Loaded ${concepts.length} concepts from ${vocabPath}`);
  } catch (e) {
    console.error(`Failed to load vocabulary: ${vocabPath}\n${e}`);
    process.exit(1);
  }
}

// ── First pass: load corpus for auto-vocab extraction ────────────────────────

// We need the raw text for TF-IDF. Do a minimal first pass if auto-vocab is on.
let autoVocabConcepts: ConceptDef[] = [];
if (autoVocabN > 0 || autoVocabOnly) {
  if (!quiet) console.log('Extracting auto-vocabulary from corpus texts...');
  const { readFileSync: rfs, readdirSync, statSync } = await import('fs');
  const { join } = await import('path');

  const texts: string[] = [];
  function gatherTexts(dir: string) {
    try {
      for (const e of readdirSync(dir, { withFileTypes: true })) {
        if (e.name.startsWith('.') || e.name === 'node_modules') continue;
        const full = join(dir, e.name);
        if (e.isDirectory()) gatherTexts(full);
        else if (e.isFile() && e.name.endsWith('.md')) {
          try { texts.push(rfs(full, 'utf8')); } catch {}
        }
      }
    } catch {}
  }
  for (const epoch of config.epochs) gatherTexts(epoch.path);

  const n = autoVocabN > 0 ? autoVocabN : 100;
  autoVocabConcepts = extractAutoVocab(texts, n);
  if (!quiet) console.log(`Auto-extracted ${autoVocabConcepts.length} vocabulary terms`);

  // Merge: auto-vocab fills in any concepts not already named
  const existingNames = new Set(concepts.map(c => c.name));
  const newTerms = autoVocabConcepts.filter(c => !existingNames.has(c.name));
  concepts = [...concepts, ...newTerms];
  if (!quiet && newTerms.length > 0) console.log(`Added ${newTerms.length} new terms from auto-vocab`);
}

if (concepts.length === 0) {
  console.error('No vocabulary defined. Provide a vocabularyFile in config or use --auto-vocab N.');
  process.exit(1);
}

// ── Main analysis ─────────────────────────────────────────────────────────────

if (!quiet) console.log(`\nLoading corpus across ${config.epochs.length} epochs...`);
const docs = loadCorpus(config, concepts);
if (!quiet) console.log(`  ${docs.length} documents with concept mentions`);

if (docs.length === 0) {
  console.error('No documents found. Check epoch paths and vocabulary.');
  process.exit(1);
}

if (!quiet) console.log('Building Pask co-occurrence network...');
const pask = buildPask(docs);

if (!quiet) console.log('Computing epoch statistics...');
const epochStats = buildEpochStats(docs, concepts, config);

if (!quiet) console.log('Classifying concept lifecycles...');
const lifecycles = classifyLifecycles(epochStats, concepts, config, pask);

if (!quiet) console.log('Building weekly timeline...');
const weekly = buildWeeklyTimeline(docs, concepts);

const burstFactor = config.burstFactor ?? 3;
const paskMinCoocs = config.paskMinCoocs ?? 3;

if (!quiet) console.log('Detecting bursts and crossovers...');
const bursts = detectBursts(weekly, burstFactor);
const crossovers = detectCrossovers(weekly);
const paskEdges = pask.topEdges(paskMinCoocs);

const result: AnalysisResult = { config, docs, concepts, lifecycles, paskEdges, bursts, crossovers };


// ── Output ────────────────────────────────────────────────────────────────────

if (!quiet) printReport(result);

if (writeFiles) {
  const prefix = outputPrefix ?? `crystallization-${config.project.replace(/\s+/g, '-').toLowerCase()}`;
  writeMarkdownReport(result, prefix);
  if (!quiet) console.log(`\nWrote ${prefix}.md and ${prefix}.json`);
}

```
