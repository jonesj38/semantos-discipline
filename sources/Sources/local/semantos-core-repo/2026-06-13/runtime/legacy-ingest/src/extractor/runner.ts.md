---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/extractor/runner.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.156523+00:00
---

# runtime/legacy-ingest/src/extractor/runner.ts

```ts
/**
 * Extraction runner — LI3 orchestrator.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI3 deliverables 1 + 5.
 *
 * Walks the raw-blob store for a provider, looks up the per-content-type
 * extractor, runs it, and persists the resulting proposals. Re-extraction
 * (`legacy reextract`) is the same loop with `force = true` so it
 * supersedes existing proposals whose extractorVersion / promptHash differ.
 */

import { audit } from '../audit';
import type { LegacyBlobStore } from '../blob-store';
import type { ProviderId, RawItem } from '../types';
import type { ExtractorRegistry } from './registry';
import type { ExtractionOutcome, LLMAdapter, Proposal } from './types';
import { collapseThreads } from './thread';
import type { ProposalStore } from '../proposal-store';
import type { IngestPaskBridge } from '../pask-bridge';

/**
 * Hard per-item extraction backstop. Each LLM/vision HTTP call is bounded by the
 * adapter's own timeout, but this guards against any unforeseen stall outside
 * that (a bundle fanning out to many calls, a hung body read, etc.) so one bad
 * source item can never freeze the whole sequential backfill — it's skipped
 * (counted as an error) and the run continues. Generous enough for legitimate
 * large PDF bundles at haiku speed; override via ExtractionRunnerOpts.itemTimeoutMs.
 */
const DEFAULT_ITEM_DEADLINE_MS = 900_000; // 15 min
function withItemDeadline<T>(p: Promise<T>, ms: number, itemId: string): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<T>((_resolve, reject) => {
    timer = setTimeout(
      () => reject(new Error(`item ${itemId} exceeded ${ms}ms extraction deadline`)),
      ms,
    );
  });
  return Promise.race([p, deadline]).finally(() => {
    if (timer !== undefined) clearTimeout(timer);
  }) as Promise<T>;
}

export interface ExtractionRunnerOpts {
  blobStore: LegacyBlobStore;
  proposalStore: ProposalStore;
  registry: ExtractorRegistry;
  llm: LLMAdapter;
  /** Optional Pask bridge — when present, new proposals seed the constraint graph. */
  paskBridge?: IngestPaskBridge;
  /** Hard per-item extraction deadline (ms). Default 15 min. Skips a stalled item. */
  itemTimeoutMs?: number;
}

export interface ExtractionRunSummary {
  readonly providerId: ProviderId;
  readonly itemsExamined: number;
  readonly extracted: number;
  readonly preFiltered: number;
  readonly lowConfidence: number;
  readonly noExtractor: number;
  readonly errors: number;
  readonly threadFolds: number;
}

export interface RunOpts {
  /** Re-extract even if a proposal already exists for the item. */
  force?: boolean;
  /** Cap on items processed in this pass — useful for tests. */
  maxItems?: number;
  /** Skip items whose existing proposal matches this `extractorVersion`. */
  skipIfMatchesVersion?: string;
}

export class ExtractionRunner {
  private readonly opts: ExtractionRunnerOpts;

  constructor(opts: ExtractionRunnerOpts) {
    this.opts = opts;
  }

  async runForProvider(providerId: ProviderId, runOpts: RunOpts = {}): Promise<ExtractionRunSummary> {
    const ids = await this.opts.blobStore.listIds(providerId);
    let examined = 0;
    let extracted = 0;
    let preFiltered = 0;
    let lowConfidence = 0;
    let noExtractor = 0;
    let errors = 0;
    const newProposals: Proposal[] = [];

    for (const itemId of ids) {
      if (runOpts.maxItems !== undefined && examined >= runOpts.maxItems) break;
      examined += 1;

      const item = await this.opts.blobStore.get(providerId, itemId);
      if (!item) continue;
      const extractor = this.opts.registry.get(item.contentType);
      if (!extractor) {
        noExtractor += 1;
        continue;
      }

      const existing = await this.opts.proposalStore.list({
        providerId,
        // Conservative — re-extraction passes also consider rejected ones
        // because the operator may want to re-evaluate after a prompt
        // upgrade. The runner deduplicates by providerItemId below.
      });
      const priorForThisItem = existing.filter(
        p => p.provenance.providerItemId === itemId,
      );

      if (!runOpts.force && priorForThisItem.length > 0) continue;
      if (runOpts.skipIfMatchesVersion && priorForThisItem.some(p =>
        p.provenance.extractorVersion === runOpts.skipIfMatchesVersion
      )) continue;

      let outcomes: ExtractionOutcome[];
      try {
        outcomes = await withItemDeadline(
          extractor.extract(item, this.opts.llm),
          this.opts.itemTimeoutMs ?? DEFAULT_ITEM_DEADLINE_MS,
          itemId,
        );
      } catch (err) {
        errors += 1;
        await audit('extract.error', 'error', {
          providerId,
          detail: `${itemId}: ${err instanceof Error ? err.message : String(err)}`,
        });
        continue;
      }

      // Tier 1.7 — extractors return an array of outcomes so a single
      // raw item can fan out into multiple proposals (e.g. bundle email
      // with N PDF work-orders attached). One-item-one-outcome flows
      // still arrive here as a single-element array; loop iteration
      // handles both shapes uniformly. A bundle that produces ≥1
      // `extracted` outcome supersedes any prior proposals for the
      // source item exactly once — not once per fan-out.
      let supersedeApplied = false;
      for (const outcome of outcomes) {
        switch (outcome.kind) {
          case 'pre-filtered':
            preFiltered += 1;
            await audit('extract.pre-filter', 'denied', {
              providerId,
              detail: `${itemId}: ${outcome.reason}`,
            });
            break;
          case 'low-confidence':
            lowConfidence += 1;
            await audit('extract.low-confidence', 'denied', {
              providerId,
              detail: `${itemId}: ${outcome.reason}`,
            });
            break;
          case 'extracted':
            newProposals.push(outcome.proposal);
            this.opts.paskBridge?.onProposalCreated(outcome.proposal);
            extracted += 1;
            // Mark prior proposals for this item as superseded — but
            // only on the first `extracted` outcome of the fan-out so a
            // bundle with N PDFs doesn't loop the supersede write.
            if (!supersedeApplied && priorForThisItem.length > 0) {
              await this.opts.proposalStore.updateStatus(priorForThisItem, 'superseded');
              supersedeApplied = true;
            }
            break;
        }
      }
    }

    const collapse = collapseThreads(newProposals);
    for (const p of collapse.proposals) {
      await this.opts.proposalStore.put(p);
    }
    // Folded sibling proposals are kept as standalone records so the
    // operator can drill into individual messages, but their status
    // stays `pending` — the primary's ratification cascades.

    await audit('extract.run.complete', 'ok', {
      providerId,
      detail: `examined=${examined} extracted=${extracted} pre-filtered=${preFiltered} ` +
              `low-conf=${lowConfidence} no-extractor=${noExtractor} errors=${errors} ` +
              `thread-folds=${collapse.foldedProposalIds.length}`,
    });

    return {
      providerId,
      itemsExamined: examined,
      extracted,
      preFiltered,
      lowConfidence,
      noExtractor,
      errors,
      threadFolds: collapse.foldedProposalIds.length,
    };
  }
}

```
