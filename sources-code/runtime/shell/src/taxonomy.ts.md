---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/taxonomy.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.364644+00:00
---

# runtime/shell/src/taxonomy.ts

```ts
/**
 * Taxonomy CLI commands — embed, coherence, distance, nearest, validate.
 *
 * All commands work standalone (no running loom needed). They load
 * taxonomy configs directly from disk and use the embedding service.
 */

import { readFileSync } from 'fs';
import { resolve } from 'path';
import type { ShellCommand } from './parser';
import { EmbeddingService, collectTaxonomyNodes, TaxonomyCoherence, IntentTaxonomy, treeDistance, cosineDistance } from '@semantos/runtime-services';
import type { TaxonomyConfig } from '@semantos/runtime-services';
import { NodeFsAdapter } from '@semantos/protocol-types/adapters/node-fs-adapter';
import { NO_EMBEDDING_CACHE, COHERENCE_ANALYSIS_FAILED, INVALID_TAXONOMY_USAGE, EMBEDDING_FAILED, VALIDATION_FAILED } from './error-codes';

// ── Shared setup ───────────────────────────────────────────

function loadTaxonomyFromDisk(): IntentTaxonomy {
  const taxonomy = new IntentTaxonomy();
  const configsDir = resolve(process.cwd(), 'configs/taxonomy');

  // Load core domains
  const coreRaw = readFileSync(resolve(configsDir, 'core.json'), 'utf-8');
  const core = JSON.parse(coreRaw) as { nodes: Parameters<IntentTaxonomy['loadDomains']>[0] };
  taxonomy.loadDomains(core.nodes);

  // Load and register extensions
  for (const name of ['trades', 'generic']) {
    try {
      const raw = readFileSync(resolve(configsDir, `${name}.json`), 'utf-8');
      const config = JSON.parse(raw) as TaxonomyConfig;
      taxonomy.registerExtension(config.extensionId, config.inject, []);
    } catch {
      // Extension config not found — skip
    }
  }

  return taxonomy;
}

function createEmbeddingService(taxonomy: IntentTaxonomy): EmbeddingService {
  const service = new EmbeddingService();
  const nodes = collectTaxonomyNodes(taxonomy.getDomains());

  service.setApiKeyProvider(() => process.env.OPENROUTER_API_KEY ?? null);
  service.setNodeProvider(() => nodes);
  service.setStorageAdapter(new NodeFsAdapter(resolve(process.cwd(), 'configs')));

  return service;
}

// ── Route ──────────────────────────────────────────────────

export async function routeTaxonomy(cmd: ShellCommand): Promise<unknown> {
  const subcommand = cmd.flags['subcommand'] as string | undefined;

  switch (subcommand) {
    case 'embed': return taxonomyEmbed(cmd);
    case 'coherence': return taxonomyCoherence(cmd);
    case 'distance': return taxonomyDistance(cmd);
    case 'nearest': return taxonomyNearest(cmd);
    case 'validate': return taxonomyValidate();
    default:
      return {
        error: `Unknown taxonomy subcommand: '${subcommand ?? '(none)'}'. ` +
          `Available: embed, coherence, distance, nearest, validate`,
        code: INVALID_TAXONOMY_USAGE,
      };
  }
}

// ── Subcommands ────────────────────────────────────────────

async function taxonomyEmbed(cmd: ShellCommand): Promise<unknown> {
  const force = cmd.flags['force'] === true;

  const taxonomy = loadTaxonomyFromDisk();
  const service = createEmbeddingService(taxonomy);

  const statsBefore = service.getStats();

  if (force) {
    await service.regenerate();
  } else {
    await service.initialize();
  }

  const statsAfter = service.getStats();
  const newNodes = statsAfter.cachedNodes - (force ? 0 : statsBefore.cachedNodes);
  const updated = force ? statsAfter.cachedNodes : Math.max(0, newNodes);

  return {
    message: `Embedded ${statsAfter.cachedNodes} nodes` +
      (force ? ' (forced regeneration)' : '') +
      `. Model: ${statsAfter.modelId ?? 'none'}.`,
    totalNodes: statsAfter.totalNodes,
    cachedNodes: statsAfter.cachedNodes,
    staleNodes: statsAfter.staleNodes,
    modelId: statsAfter.modelId,
  };
}

async function taxonomyCoherence(cmd: ShellCommand): Promise<unknown> {
  const format = (cmd.flags['format'] as string) ?? 'table';

  const taxonomy = loadTaxonomyFromDisk();
  const service = createEmbeddingService(taxonomy);
  await service.initialize();

  if (!service.isReady()) {
    return { error: 'No embedding cache available. Run `semantos taxonomy embed` first.', code: NO_EMBEDDING_CACHE };
  }

  const analyzer = new TaxonomyCoherence();
  analyzer.setEmbeddingService(service);
  const report = analyzer.analyze();

  if (!report) {
    return { error: 'Coherence analysis failed. Ensure embeddings are available.', code: COHERENCE_ANALYSIS_FAILED };
  }

  if (format === 'json') {
    return report;
  }

  // Table format
  const lines: string[] = [
    `Coherence Report — ${report.timestamp}`,
    `Nodes: ${report.totalNodes}  Pairs: ${report.totalPairs}`,
    `Monotonicity: ${(report.monotonicity * 100).toFixed(1)}%`,
    `Sibling Cohesion: ${(report.siblingCohesion * 100).toFixed(1)}%`,
    '',
  ];

  if (report.misalignments.length > 0) {
    lines.push(`Misalignments (${report.misalignments.length}):`);
    for (const m of report.misalignments) {
      const severity = m.severity === 'critical' ? '[CRITICAL]'
        : m.severity === 'warning' ? '[WARNING]'
        : '[INFO]';
      lines.push(`  ${severity} ${m.nodePath}: tree-nearest=${m.treeNearest}, embedding-nearest=${m.embeddingNearest}`);
    }
    lines.push('');
  }

  if (report.suggestions.length > 0) {
    lines.push(`Suggestions (${report.suggestions.length}):`);
    for (const s of report.suggestions) {
      lines.push(`  [${s.type.toUpperCase()}] ${s.nodePath}: ${s.reason}`);
    }
  }

  return { output: lines.join('\n') };
}

async function taxonomyDistance(cmd: ShellCommand): Promise<unknown> {
  const pathA = cmd.flags['pathA'] as string | undefined;
  const pathB = cmd.flags['pathB'] as string | undefined;

  if (!pathA || !pathB) {
    return { error: 'Usage: semantos taxonomy distance <pathA> <pathB>', code: INVALID_TAXONOMY_USAGE };
  }

  const segsA = pathA.split('.');
  const segsB = pathB.split('.');
  const td = treeDistance(segsA, segsB);

  // Try to get embedding distance
  const taxonomy = loadTaxonomyFromDisk();
  const service = createEmbeddingService(taxonomy);
  await service.initialize();

  let embeddingDist: number | null = null;
  let similarity: number | null = null;

  if (service.isReady()) {
    const va = service.getEmbedding(pathA);
    const vb = service.getEmbedding(pathB);
    if (va && vb) {
      embeddingDist = cosineDistance(va, vb);
      similarity = 1 - embeddingDist;
    }
  }

  const relationship = td === 0 ? 'identity'
    : td === 1 ? 'parent-child'
    : td === 2 && segsA.length === segsB.length ? 'siblings'
    : 'cross-branch';

  return {
    pathA,
    pathB,
    treeDistance: td,
    relationship,
    embeddingDistance: embeddingDist,
    cosineSimilarity: similarity,
    message: `Tree distance: ${td} (${relationship}).` +
      (embeddingDist !== null
        ? ` Embedding distance: ${embeddingDist.toFixed(4)}. Cosine similarity: ${similarity!.toFixed(4)}.`
        : ' Embedding distance: unavailable (run `semantos taxonomy embed` first).'),
  };
}

async function taxonomyNearest(cmd: ShellCommand): Promise<unknown> {
  const utterance = cmd.flags['utterance'] as string | undefined;
  const n = parseInt(cmd.flags['n'] as string ?? '5', 10);

  if (!utterance) {
    return { error: 'Usage: semantos taxonomy nearest "<utterance>" [--n 5]', code: INVALID_TAXONOMY_USAGE };
  }

  const taxonomy = loadTaxonomyFromDisk();
  const service = createEmbeddingService(taxonomy);
  await service.initialize();

  if (!service.isReady()) {
    return { error: 'No embedding cache available. Run `semantos taxonomy embed` first.', code: NO_EMBEDDING_CACHE };
  }

  const queryVector = await service.embedQuery(utterance);
  if (!queryVector) {
    return { error: 'Failed to embed query. Check OPENROUTER_API_KEY.', code: EMBEDDING_FAILED };
  }

  const results = service.nearest(queryVector, n);
  return {
    query: utterance,
    results: results.map((r, i) => ({
      rank: i + 1,
      path: r.path,
      score: parseFloat(r.score.toFixed(4)),
    })),
  };
}

async function taxonomyValidate(): Promise<unknown> {
  const taxonomy = loadTaxonomyFromDisk();
  const service = createEmbeddingService(taxonomy);
  await service.initialize();

  if (!service.isReady()) {
    return {
      error: 'No embedding cache available. Run `semantos taxonomy embed` first.',
      code: NO_EMBEDDING_CACHE,
      exitCode: 1,
    };
  }

  const analyzer = new TaxonomyCoherence();
  analyzer.setEmbeddingService(service);
  const report = analyzer.analyze();

  if (!report) {
    return { error: 'Validation failed. Ensure embeddings are available.', code: VALIDATION_FAILED, exitCode: 1 };
  }

  const passed = report.monotonicity > 0.80;

  return {
    monotonicity: parseFloat((report.monotonicity * 100).toFixed(1)),
    siblingCohesion: parseFloat((report.siblingCohesion * 100).toFixed(1)),
    misalignments: report.misalignments.length,
    criticalMisalignments: report.misalignments.filter(m => m.severity === 'critical').length,
    passed,
    exitCode: passed ? 0 : 1,
    message: passed
      ? `PASS: Monotonicity ${(report.monotonicity * 100).toFixed(1)}% (threshold: 80%)`
      : `FAIL: Monotonicity ${(report.monotonicity * 100).toFixed(1)}% (threshold: 80%)`,
  };
}

```
