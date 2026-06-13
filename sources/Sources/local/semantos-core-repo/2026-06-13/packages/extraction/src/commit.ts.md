---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/commit.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.453401+00:00
---

# packages/extraction/src/commit.ts

```ts
/**
 * Commit engine — creates semantic objects with idempotency and evidence chains.
 *
 * Pure async generator: ValidatedRecord | InferredRecord stream → { object, isDuplicate } stream.
 * Uses ExtractionStorageContext for object creation and dedup.
 * Bounded in-batch dedup map (max 10,000 entries) to prevent memory leaks.
 */

import type { ExtensionGrammar } from '@semantos/protocol-types';
import type {
  ValidatedRecord,
  InferredRecord,
  ExtractedSemanticObject,
  ExtractionContext,
  GrammarPatch,
} from './stages';
import type { LoomExtractionContext } from './context';

const BATCH_DEDUP_MAX = 10_000;

/**
 * Commit validated/inferred records as semantic objects.
 * Handles idempotency via source key dedup (within batch + cross-run).
 */
export async function* commitRecords(
  records: AsyncIterable<ValidatedRecord | InferredRecord | GrammarPatch>,
  grammar: ExtensionGrammar,
  context: ExtractionContext,
): AsyncGenerator<{ object: ExtractedSemanticObject; isDuplicate: boolean }, void, void> {
  const store = context.extractionStore as LoomExtractionContext;
  const batchSeen = new Map<string, string>(); // sourceKey → objectId

  for await (const record of records) {
    // Skip GrammarPatch entries — they're not records to commit
    if ('type' in record && (record as GrammarPatch).type === 'grammar-patch') {
      continue;
    }

    const rec = record as ValidatedRecord | InferredRecord;

    // Skip records that failed validation
    if (!rec.validationPassed) continue;

    const sourceKey = buildSourceKey(grammar.grammarId, rec.sourceId);
    let objectId: string;
    let isDuplicate = false;

    // 1. Check within-batch dedup
    if (batchSeen.has(sourceKey)) {
      objectId = batchSeen.get(sourceKey)!;
      isDuplicate = true;
    } else {
      // 2. Check cross-run dedup via StorageAdapter
      const existing = await store.lookupSourceKey(sourceKey);
      if (existing) {
        objectId = existing;
        isDuplicate = true;
      } else {
        // 3. Create new object
        const typeDef = store.resolveTypeDef(rec.targetObjectType);
        if (!typeDef) {
          continue; // Skip if type not found
        }

        objectId = store.createObject(
          typeDef,
          rec.mappedFields,
          rec.taxonomy,
          rec.phase,
          context.consumerId,
        );

        // Register for dedup
        await store.registerSourceKey(sourceKey, objectId);
        batchSeen.set(sourceKey, objectId);

        // Evict oldest if batch map is full
        if (batchSeen.size > BATCH_DEDUP_MAX) {
          const firstKey = batchSeen.keys().next().value;
          if (firstKey !== undefined) batchSeen.delete(firstKey);
        }
      }
    }

    // Patch if duplicate
    if (isDuplicate) {
      store.patchObject(
        objectId,
        rec.mappedFields,
        rec.evidence.toArray(),
        context.consumerId,
      );
    }

    // Add commit evidence
    rec.evidence.addCommit({
      objectId,
      storageAdapter: 'workbench',
      isNewObject: !isDuplicate,
      facetProvenance: {
        author: context.consumerId,
        timestamp: Date.now(),
      },
    });

    // Persist evidence chain
    await store.writeEvidence(objectId, rec.evidence.toArray());

    yield {
      object: {
        objectId,
        objectType: rec.targetObjectType,
        payload: rec.mappedFields,
        taxonomy: rec.taxonomy,
        phase: rec.phase,
        evidenceChain: rec.evidence.toArray(),
      },
      isDuplicate,
    };
  }
}

/** Build a source key for dedup: grammarId:sourceId. */
export function buildSourceKey(grammarId: string, sourceId: unknown): string {
  return `${grammarId}:${String(sourceId)}`;
}

```
