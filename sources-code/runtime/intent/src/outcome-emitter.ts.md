---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/outcome-emitter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.344119+00:00
---

# runtime/intent/src/outcome-emitter.ts

```ts
/**
 * WI-A2 — NatsEmitter interface for intent_outcome events.
 *
 * Thin transport boundary: the pipeline serialises the lowered IRProgram
 * bindings into JSON and hands the already-flat payload to the emitter.
 * The concrete implementation routes to `nats_event_producer.zig`'s
 * `emitIntentOutcome` via the host bridge; tests substitute RecordingNatsEmitter.
 *
 * See research/cognition-implementation-plan.md §WI-A2.
 */

// ── Payload ────────────────────────────────────────────────────────────────

/**
 * Flat payload for the NATS `intent_outcome` event.
 * Field names match the Zig producer's JSON output
 * (nats_event_producer.zig `emitIntentOutcome`).
 */
export interface IntentOutcomePayload {
  intentId: string;
  domainFlag: number;
  lexicon: string;
  juralCategory: string;
  /** JSON-serialised `IRBinding[]` from the lowered IRProgram. */
  anfBindingsJson: string;
  compositeConfidence: number;
  /** Cell id from the written Cell artifact — serves as the outcome hash. */
  cellOutcomeHash: string;
  tsMs: number;
  hatId: string;
}

// ── Interface ──────────────────────────────────────────────────────────────

/** Emitter interface — inject in PipelineDeps; substitute in tests. */
export interface NatsEmitter {
  emitIntentOutcome(payload: IntentOutcomePayload): Promise<void>;
}

// ── Test double ────────────────────────────────────────────────────────────

/** Records every emitIntentOutcome call. Use in unit tests. */
export class RecordingNatsEmitter implements NatsEmitter {
  readonly calls: IntentOutcomePayload[] = [];

  async emitIntentOutcome(payload: IntentOutcomePayload): Promise<void> {
    this.calls.push(payload);
  }
}

```
