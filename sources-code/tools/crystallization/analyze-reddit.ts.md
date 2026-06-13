---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/crystallization/analyze-reddit.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.545563+00:00
---

# tools/crystallization/analyze-reddit.ts

```ts
#!/usr/bin/env bun
/**
 * Reddit crystallization analyzer.
 *
 * Usage:
 *   bun tools/crystallization/analyze-reddit.ts <config.json> [--output <prefix>]
 *
 * Config format: same as analyze.ts but epochs have source="reddit" and
 * Reddit-specific fields (subreddit, sort, timeFilter, limit, etc.).
 *
 * Social engineering detection:
 *   Pair epochs: hot-<period> vs controversial-<period>.
 *   Concepts that are CRYSTALLIZED in hot but TRANSITION_ONLY or absent in
 *   controversial are candidates for manufactured consensus.
 *   Concepts with high Pask score in hot + low in controversial suggest
 *   scripted co-occurrence (talking points) rather than organic discussion.
 */

import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import type { AnalysisConfig, AnalysisResult, ConceptDef, CorpusDoc } from './types';
import type { RedditEpochConfig } from './lib/sources/reddit';
import { loadRedditCorpus } from './lib/sources/reddit';
import { extractAutoVocab } from './lib/corpus';
import { buildPask } from './lib/pask';
import { buildEpochStats, classifyLifecycles } from './lib/lifecycle';
import { buildWeeklyTimeline, detectBursts, detectCrossovers } from './lib/temporal';
import { printReport, writeMarkdownReport } from './lib/report';

// ── CLI ───────────────────────────────────────────────────────────────────────

const args = process.argv.slice(2);
if (args.length === 0 || args[0] === '--help') {
  console.log([
    'Usage: bun tools/crystallization/analyze-reddit.ts <config.json> [options]',
    '',
    'Options:',
    '  --output <prefix>   Output file prefix (default: reddit-<project>)',
    '  --no-report         Skip writing .md/.json output files',
    '  --quiet             Suppress console output',
    '',
    'Social engineering detection:',
    '  Pair epochs with sort=top and sort=controversial for the same period.',
    '  Lifecycle divergence between the two exposes manipulation patterns.',
  ].join('\n'));
  process.exit(0);
}

const configPath = resolve(args[0]);
let outputPrefix: string | null = null;
let writeFiles = true;
let quiet = false;

for (let i = 1; i < args.length; i++) {
  if (args[i] === '--output' && args[i + 1]) { outputPrefix = args[++i]; }
  else if (args[i] === '--no-report') { writeFiles = false; }
  else if (args[i] === '--quiet') { quiet = true; }
}

// ── Config ────────────────────────────────────────────────────────────────────

interface RedditAnalysisConfig extends Omit<AnalysisConfig, 'epochs'> {
  epochs: RedditEpochConfig[];
  cacheDir?: string;
}

let config: RedditAnalysisConfig;
try {
  config = JSON.parse(readFileSync(configPath, 'utf8'));
} catch (e) {
  console.error(`Failed to read config: ${configPath}\n${e}`);
  process.exit(1);
}

const configDir = dirname(configPath);

// Propagate top-level cacheDir to epochs that don't specify their own
if (config.cacheDir) {
  for (const epoch of config.epochs) {
    epoch.cacheDir ??= resolve(configDir, config.cacheDir);
  }
}

// ── Vocabulary ────────────────────────────────────────────────────────────────

let concepts: ConceptDef[] = [];

if (config.vocabularyFile) {
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

// ── Fetch all epochs ──────────────────────────────────────────────────────────

if (!quiet) console.log(`\nFetching ${config.epochs.length} Reddit epoch(s)...`);

const docs: CorpusDoc[] = [];

for (let ei = 0; ei < config.epochs.length; ei++) {
  const epoch = config.epochs[ei];
  if (!quiet) console.log(`\n[${ei + 1}/${config.epochs.length}] ${epoch.name} — r/${epoch.subreddit} sort=${epoch.sort}`);

  const epochDocs = await loadRedditCorpus(epoch, ei, concepts, !quiet);
  docs.push(...epochDocs);
  if (ei < config.epochs.length - 1) {
    if (!quiet) process.stdout.write('  [reddit] cooling down 30s before next epoch...\n');
    await new Promise(r => setTimeout(r, 30000));
  }
}

if (docs.length === 0) {
  console.error('No documents found with concept mentions. Check vocabulary and subreddit config.');
  process.exit(1);
}

if (!quiet) console.log(`\nTotal: ${docs.length} docs across ${config.epochs.length} epochs`);

// ── Auto-vocab supplement ─────────────────────────────────────────────────────

if ((config.autoVocabSize ?? 0) > 0 && docs.length > 0) {
  const texts = docs.map(d => {
    // We don't have the raw text at this point, so auto-vocab is skipped for Reddit
    return '';
  }).filter(Boolean);
  if (texts.length > 0) {
    const extra = extractAutoVocab(texts, config.autoVocabSize!);
    const existing = new Set(concepts.map(c => c.name));
    const added = extra.filter(c => !existing.has(c.name));
    concepts = [...concepts, ...added];
    if (!quiet) console.log(`Auto-vocab added ${added.length} terms`);
  }
}

// ── Analysis (identical to analyze.ts from here) ─────────────────────────────

const analysisConfig: AnalysisConfig = {
  ...config,
  epochs: config.epochs.map(e => ({ name: e.name, path: `reddit://r/${e.subreddit}/${e.sort}` })),
};

if (!quiet) console.log('Building Pask co-occurrence network...');
const pask = buildPask(docs);

if (!quiet) console.log('Computing epoch statistics...');
const epochStats = buildEpochStats(docs, concepts, analysisConfig);

if (!quiet) console.log('Classifying concept lifecycles...');
const lifecycles = classifyLifecycles(epochStats, concepts, analysisConfig, pask);

if (!quiet) console.log('Building weekly timeline...');
const weekly = buildWeeklyTimeline(docs, concepts);

const bursts = detectBursts(weekly, config.burstFactor ?? 3);
const crossovers = detectCrossovers(weekly);
const paskEdges = pask.topEdges(config.paskMinCoocs ?? 2);

const result: AnalysisResult = { config: analysisConfig, docs, concepts, lifecycles, paskEdges, bursts, crossovers };

if (!quiet) printReport(result);

if (writeFiles) {
  const prefix = outputPrefix ?? `reddit-${config.project.replace(/\s+/g, '-').toLowerCase()}`;
  writeMarkdownReport(result, prefix);
  if (!quiet) {
    console.log(`\nWrote ${prefix}.md and ${prefix}.json`);
    console.log('\n── Social engineering signals to look for:');
    console.log('  CRYSTALLIZED in hot/* + TRANSITION_ONLY in controversial/* → manufactured consensus');
    console.log('  LATE_EMERGENCE in hot/* → sudden narrative push with no prior community roots');
    console.log('  High Pask score (hot) + low Pask score (controversial) → scripted talking points');
    console.log('  Burst event in controversial before hot → astroturf started, community pushed back first');
  }
}

```
