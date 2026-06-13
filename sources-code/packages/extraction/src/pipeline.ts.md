---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/pipeline.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.453678+00:00
---

# packages/extraction/src/pipeline.ts

```ts
/**
 * Extraction pipeline orchestrator — chains all five stages.
 *
 * Takes a grammar and binding, validates the grammar, selects fetch adapters,
 * runs stages sequentially with async generators, collects results.
 * Error handling per-entity: one entity failure doesn't abort the batch.
 */

import type { ExtensionGrammar, SourceEntity, StorageAdapter, ContentStore } from '@semantos/protocol-types';
import { validateExtensionGrammar, grammarToExtensionConfig } from '@semantos/protocol-types';
import type { LoomStore } from '@semantos/runtime-services';

import type {
  ConsumerBinding,
  ExtractionContext,
  ExtractionResult,
  ExtractionOptions,
  GrammarPatch,
  InferredRecord,
  ValidatedRecord,
} from './stages';
import type {
  GovernedConsumerBinding,
  GovernancePolicy,
} from '@semantos/protocol-types';
import { enforceL1Constraints } from './governance/constraint-engine';
import { checkCompatibility } from './governance/version-compat';
import { LoomExtractionContext } from './context';
import { selectFetchAdapter } from './fetch/adapter';
import type { FetchAdapter } from './fetch/adapter';
import { parseResponses } from './parse';
import { typecheckRecords } from './typecheck';
import { inferRecords } from './infer';
import { commitRecords } from './commit';

export type ProgressCallback = (event: ProgressEvent) => void;

export interface ProgressEvent {
  entity: string;
  processed: number;
  created: number;
  updated: number;
}

export interface ExtractionPipelineOptions {
  /** Optional ContentStore — when set, fetch adapters route raw documents through it. */
  contentStore?: ContentStore;
}

export class ExtractionPipeline {
  private onProgress?: ProgressCallback;
  private readonly contentStore?: ContentStore;

  constructor(
    private store: LoomStore,
    private adapter: StorageAdapter,
    options?: ExtractionPipelineOptions,
  ) {
    if (options?.contentStore) this.contentStore = options.contentStore;
  }

  /** Set a callback for progress events. */
  setProgressCallback(cb: ProgressCallback): void {
    this.onProgress = cb;
  }

  /**
   * Run the extraction pipeline for a grammar and binding.
   * Returns a summary result with counts and errors.
   */
  async extract(
    grammar: ExtensionGrammar,
    binding: ConsumerBinding,
    options?: ExtractionOptions,
  ): Promise<ExtractionResult> {
    const result: ExtractionResult = {
      grammarId: grammar.grammarId,
      grammarVersion: grammar.grammarVersion,
      totalRecords: 0,
      createdObjects: 0,
      updatedObjects: 0,
      errors: [],
      startTime: Date.now(),
      endTime: 0,
    };

    try {
      // 1. Validate grammar
      const validation = validateExtensionGrammar(grammar);
      if (!validation.valid) {
        const errorMessages = validation.errors
          .filter(e => e.severity === 'error')
          .map(e => `${e.path}: ${e.message}`);
        result.errors.push({
          error: `Grammar validation failed: ${errorMessages.join('; ')}`,
          timestamp: Date.now(),
        });
        result.endTime = Date.now();
        return result;
      }

      // 1b. Governance checks (Phase 36D) — if governed binding and manifest provided
      if (options?.governedBinding && options?.manifest) {
        // Check L1 constraints
        const l1Result = enforceL1Constraints(options.governedBinding, options.manifest);
        if (!l1Result.valid) {
          const msgs = l1Result.violations.map(v => `[${v.rule}] ${v.message}`);
          result.errors.push({
            error: `L1 constraint violations: ${msgs.join('; ')}`,
            timestamp: Date.now(),
          });
          result.endTime = Date.now();
          return result;
        }

        // Check version compatibility
        const compat = checkCompatibility(options.governedBinding, options.manifest);
        if (compat.status === 'red') {
          result.errors.push({
            error: `Binding incompatible with manifest: ${compat.message}`,
            timestamp: Date.now(),
          });
          result.endTime = Date.now();
          return result;
        }
      }

      // 2. Build extraction context
      const extensionConfig = grammarToExtensionConfig(grammar);
      const extractionStore = new LoomExtractionContext(
        this.store,
        this.adapter,
        extensionConfig,
      );

      const context: ExtractionContext = {
        grammarId: grammar.grammarId,
        grammarVersion: grammar.grammarVersion,
        consumerId: binding.consumerId,
        extractionStore,
      };

      // 3. Select fetch adapter — thread ContentStore through when present
      const fetchAdapter = selectFetchAdapter(
        grammar.source.protocol,
        this.contentStore ? { contentStore: this.contentStore } : undefined,
      );

      // 4. Process each entity
      for (const entity of grammar.source.entities) {
        // Apply entity filter
        if (options?.entityFilter && entity.entityId !== options.entityFilter) {
          continue;
        }

        try {
          await this.processEntity(
            entity,
            grammar,
            binding,
            context,
            fetchAdapter,
            result,
            options,
          );
        } catch (err) {
          result.errors.push({
            entity: entity.entityId,
            error: err instanceof Error ? err.message : String(err),
            timestamp: Date.now(),
          });
        }
      }
    } catch (err) {
      result.errors.push({
        error: err instanceof Error ? err.message : String(err),
        timestamp: Date.now(),
      });
    }

    result.endTime = Date.now();
    return result;
  }

  /** Process a single entity through all pipeline stages. */
  private async processEntity(
    entity: SourceEntity,
    grammar: ExtensionGrammar,
    binding: ConsumerBinding,
    context: ExtractionContext,
    fetchAdapter: FetchAdapter,
    result: ExtractionResult,
    options?: ExtractionOptions,
  ): Promise<void> {
    // Chain stages as async generators
    const rawResponses = fetchAdapter.fetch(entity, grammar.source, binding.credentials, context);
    const intermediateRecords = parseResponses(rawResponses, grammar, entity, context);
    const validatedRecords = typecheckRecords(intermediateRecords, grammar, context);
    const inferredRecords = inferRecords(validatedRecords, grammar, context);

    // Dry run stops before commit
    if (options?.dryRun) {
      for await (const item of inferredRecords) {
        if ('type' in item && (item as GrammarPatch).type === 'grammar-patch') continue;
        const rec = item as InferredRecord;
        result.totalRecords++;
        this.emitProgress(entity.entityId, result);
      }
      return;
    }

    // Full run: commit
    const committed = commitRecords(inferredRecords, grammar, context);

    for await (const { object, isDuplicate } of committed) {
      result.totalRecords++;
      if (isDuplicate) {
        result.updatedObjects++;
      } else {
        result.createdObjects++;
      }

      this.emitProgress(entity.entityId, result);
    }
  }

  private emitProgress(entityId: string, result: ExtractionResult): void {
    if (this.onProgress) {
      this.onProgress({
        entity: entityId,
        processed: result.totalRecords,
        created: result.createdObjects,
        updated: result.updatedObjects,
      });
    }
  }
}

```
