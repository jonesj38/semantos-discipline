---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/intent-classifier/prompt-builders.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.107001+00:00
---

# runtime/services/src/services/intent-classifier/prompt-builders.ts

```ts
/**
 * Prompt templates — the only place in the codebase that owns
 * intent-classifier prompt strings. Every prompt is a parameterized
 * function so callers don't string-template inline.
 *
 * Behavioural copy preserved verbatim from the pre-split monolith.
 */

import type { ClassificationContext } from '../intent-types';
import type { FastPathEntry, IntentTaxonomyNode } from '../IntentTaxonomy';
import { buildScoreMap, scoreOptionsForLevel } from './embedding-ranker';
import type { UtteranceEmbeddingResult } from './utterance-embedding-cache';

/**
 * Fast-path prompt with embedding similarity scores.
 */
export function buildEmbeddingRankedFastPathPrompt(
  intents: FastPathEntry[],
  embResult: UtteranceEmbeddingResult,
): string {
  const scoreMap = buildScoreMap(embResult);
  const parts: string[] = [
    'You are an intent classifier. Classify the user message into one of the following intents.',
    'Only select an intent if you are very confident (>0.90). If uncertain, select "unknown".',
    '',
    'Options (ranked by relevance):',
  ];
  for (const entry of intents) {
    const score = scoreMap.get(entry.nodeId);
    const scoreStr = score !== undefined ? ` (${score.toFixed(2)})` : '';
    let line = `- "${entry.intent}"${scoreStr}: flow=${entry.flowId}`;
    if (entry.examples.length > 0) {
      line += ` (examples: ${entry.examples.slice(0, 2).map((e) => `"${e}"`).join(', ')})`;
    }
    parts.push(line);
  }
  parts.push('');
  parts.push(
    'Respond with valid JSON only: { "intent": "<intent_string>", "confidence": <0.0-1.0>, "flowId": "<flow_id>" }',
  );
  parts.push(
    'If none match confidently, respond with: { "intent": "unknown", "confidence": 0.0 }',
  );
  return parts.join('\n');
}

/**
 * Hierarchical-level prompt with embedding similarity scores.
 */
export function buildEmbeddingRankedLevelPrompt(
  currentPath: string[],
  options: IntentTaxonomyNode[],
  embResult: UtteranceEmbeddingResult,
): string {
  const levelLabel =
    currentPath.length === 0
      ? 'domain'
      : currentPath.length === 1
        ? 'category'
        : 'type';

  const scored = scoreOptionsForLevel(currentPath, options, embResult);

  const parts: string[] = [
    `You are an intent classifier. Classify the user message into one of the following ${levelLabel} options.`,
    '',
    'Options (ranked by relevance):',
  ];

  for (const { opt, score } of scored) {
    const scoreStr = score !== undefined ? ` (${score.toFixed(2)})` : '';
    let line = `- "${opt.id}"${scoreStr}: ${opt.label} — ${opt.description}`;
    if (opt.examples && opt.examples.length > 0) {
      line += ` (examples: ${opt.examples.slice(0, 3).map((e) => `"${e}"`).join(', ')})`;
    }
    parts.push(line);
  }

  parts.push('');
  parts.push(
    'Respond with valid JSON only: { "selected": "<option_id>", "confidence": <0.0-1.0> }',
  );
  parts.push(
    'If none of the options match, respond with: { "selected": "unknown", "confidence": 0.0 }',
  );
  return parts.join('\n');
}

/**
 * Flat-fallback prompt — used when no taxonomy is registered.
 * Mirrors the pre-split text exactly.
 */
export function buildFlatSystemPrompt(context: ClassificationContext): string {
  const parts: string[] = [
    `You are an intent classifier for the "${context.extensionName}" workbench.`,
    '',
    'Available object types: ' + context.objectTypes.join(', '),
  ];

  if (context.taxonomyPaths.length > 0) {
    parts.push('Taxonomy paths: ' + context.taxonomyPaths.join(', '));
  }
  if (context.flowIds.length > 0) {
    parts.push('Available flows: ' + context.flowIds.join(', '));
  }
  if (context.currentObjectType) {
    parts.push(`Currently working on: ${context.currentObjectType}`);
  }
  if (context.activeHatName) {
    parts.push(`Active identity hat: ${context.activeHatName}`);
  }

  parts.push('');
  parts.push('Classify the user message into an intent. Respond with valid JSON only.');
  parts.push('');
  parts.push('Intent naming conventions:');
  parts.push('- "create.<type>" — user wants to create a new object (e.g., "create.job", "create.project")');
  parts.push('- "need.service" / "request.quote" — user describes a need (maps to create flow)');
  parts.push('- "navigate.<path>" — user wants to view or filter by taxonomy path');
  parts.push('- "transition.<status>" — user wants to change object status');
  parts.push('- "converse" — general conversation about the current object');
  parts.push('- "unknown" — cannot classify');
  parts.push('');
  parts.push('Response format:');
  parts.push('{');
  parts.push('  "intent": "create.job",');
  parts.push('  "confidence": 0.92,');
  parts.push('  "objectType": "Job",');
  parts.push('  "typePath": "services.trades.plumbing",');
  parts.push('  "flowId": "create-job",');
  parts.push('  "extractedFields": { "categoryPath": "services.trades.plumbing", "urgency": "next_week" }');
  parts.push('}');

  return parts.join('\n');
}

```
