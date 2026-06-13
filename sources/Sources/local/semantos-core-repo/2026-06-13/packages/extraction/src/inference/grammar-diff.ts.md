---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/inference/grammar-diff.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.461997+00:00
---

# packages/extraction/src/inference/grammar-diff.ts

```ts
/**
 * D36C.3 — Grammar Diff Engine
 *
 * Compares an inferred EntityGraph against installed Extension Grammars
 * to identify new entities, existing matches, unmapped fields, and type
 * mismatches. Deterministic — no LLM calls.
 */

import type { ExtensionGrammar } from '@semantos/protocol-types';
import type {
  EntityGraph,
  InferredField,
  GrammarDiff,
  GrammarMatch,
  TypeMismatch,
} from './types';

// ── Constants ──────────────────────────────────────────────────

/** Minimum field overlap percentage to consider a match. */
const MATCH_THRESHOLD = 0.70;

/** Maximum Levenshtein distance (normalized) to consider name similarity. */
const NAME_SIMILARITY_THRESHOLD = 0.80;

// ── Main Entry Point ───────────────────────────────────────────

/**
 * Compare proposed entities against installed grammars.
 *
 * @param proposed - EntityGraph from StructureAnalyzer
 * @param known - Installed Extension Grammars to compare against
 */
export function diffGrammars(
  proposed: EntityGraph,
  known: ExtensionGrammar[],
): GrammarDiff {
  const newEntities: string[] = [];
  const matchedEntities: Record<string, GrammarMatch> = {};
  const unmappedFields: Record<string, InferredField[]> = {};
  const typeMismatches: Record<string, TypeMismatch[]> = {};

  for (const entity of proposed.nodes) {
    const bestMatch = findBestMatch(entity, known);

    if (bestMatch) {
      matchedEntities[entity.id] = bestMatch.match;

      // Collect unmapped fields
      const grammarFieldNames = new Set(bestMatch.grammarFieldNames);
      const unmapped = entity.fields.filter(f => !grammarFieldNames.has(f.name));
      if (unmapped.length > 0) {
        unmappedFields[entity.id] = unmapped;
      }

      // Collect type mismatches
      const mismatches = findTypeMismatches(entity, bestMatch.grammarFields, bestMatch.match.grammarId);
      if (mismatches.length > 0) {
        typeMismatches[entity.id] = mismatches;
      }
    } else {
      newEntities.push(entity.id);
    }
  }

  return { newEntities, matchedEntities, unmappedFields, typeMismatches };
}

// ── Matching Logic ─────────────────────────────────────────────

interface MatchCandidate {
  match: GrammarMatch;
  grammarFieldNames: string[];
  grammarFields: Map<string, string>; // fieldName → sourceType
}

function findBestMatch(
  entity: { id: string; fields: InferredField[] },
  grammars: ExtensionGrammar[],
): MatchCandidate | null {
  let best: MatchCandidate | null = null;
  let bestScore = 0;

  const proposedFieldNames = new Set(entity.fields.map(f => f.name));

  for (const grammar of grammars) {
    for (const sourceEntity of grammar.source.entities) {
      const grammarFieldNames = sourceEntity.fields.map(f => f.sourceFieldName);
      const grammarFieldSet = new Set(grammarFieldNames);

      // Compute field overlap
      let overlap = 0;
      for (const name of proposedFieldNames) {
        if (grammarFieldSet.has(name)) overlap++;
      }
      const overlapPercent = proposedFieldNames.size > 0
        ? overlap / proposedFieldNames.size
        : 0;

      // Compute name similarity
      const nameSim = normalizedSimilarity(entity.id, sourceEntity.entityId);

      // Consider it a match if field overlap > threshold OR name similarity > threshold with decent overlap
      const isFieldMatch = overlapPercent >= MATCH_THRESHOLD;
      const isNameMatch = nameSim >= NAME_SIMILARITY_THRESHOLD && overlapPercent >= 0.5;

      if (isFieldMatch || isNameMatch) {
        const score = overlapPercent * 0.7 + nameSim * 0.3;
        if (score > bestScore) {
          bestScore = score;

          const grammarFields = new Map<string, string>();
          for (const f of sourceEntity.fields) {
            grammarFields.set(f.sourceFieldName, f.sourceType);
          }

          best = {
            match: {
              grammarId: grammar.grammarId,
              grammarEntityId: sourceEntity.entityId,
              fieldOverlapPercent: Math.round(overlapPercent * 100) / 100,
              confidence: Math.round(score * 100) / 100,
            },
            grammarFieldNames,
            grammarFields,
          };
        }
      }
    }
  }

  return best;
}

// ── Type Mismatch Detection ────────────────────────────────────

function findTypeMismatches(
  entity: { fields: InferredField[] },
  grammarFields: Map<string, string>,
  grammarId: string,
): TypeMismatch[] {
  const mismatches: TypeMismatch[] = [];

  for (const field of entity.fields) {
    const grammarType = grammarFields.get(field.name);
    if (grammarType && grammarType !== field.type) {
      // Allow compatible type differences (e.g., datetime includes date)
      if (isCompatibleType(field.type, grammarType)) continue;

      mismatches.push({
        field: field.name,
        proposedType: field.type,
        grammarType,
        grammarId,
      });
    }
  }

  return mismatches;
}

/** Check if two types are compatible (not a real mismatch). */
function isCompatibleType(proposed: string, grammar: string): boolean {
  // date and datetime are compatible
  if ((proposed === 'date' && grammar === 'datetime') ||
      (proposed === 'datetime' && grammar === 'date')) {
    return true;
  }
  // enum is a subtype of string
  if ((proposed === 'enum' && grammar === 'string') ||
      (proposed === 'string' && grammar === 'enum')) {
    return true;
  }
  return false;
}

// ── String Similarity ──────────────────────────────────────────

/** Compute Levenshtein distance. */
function levenshteinDistance(a: string, b: string): number {
  const m = a.length;
  const n = b.length;
  const dp: number[][] = Array.from({ length: m + 1 }, () => Array(n + 1).fill(0));
  for (let i = 0; i <= m; i++) dp[i][0] = i;
  for (let j = 0; j <= n; j++) dp[0][j] = j;
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      dp[i][j] = a[i - 1] === b[j - 1]
        ? dp[i - 1][j - 1]
        : 1 + Math.min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]);
    }
  }
  return dp[m][n];
}

/** Normalized similarity score (0.0–1.0). Handles case and underscore normalization. */
function normalizedSimilarity(a: string, b: string): number {
  const na = a.toLowerCase().replace(/[_-]/g, '');
  const nb = b.toLowerCase().replace(/[_-]/g, '');
  if (na === nb) return 1.0;
  const maxLen = Math.max(na.length, nb.length);
  if (maxLen === 0) return 1.0;
  return 1.0 - levenshteinDistance(na, nb) / maxLen;
}

```
