---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/produce-intent.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.345463+00:00
---

# runtime/intent/src/produce-intent.ts

```ts
/**
 * RM-091 — producer-boundary helper.
 *
 * Wraps `reduceToIntent` with the three things every intent producer
 * must do at the producer boundary:
 *
 *   1. Mint a `correlationId` once. From this point forward every
 *      `StageEvent` (producer-side, reducer-side, pipeline-side) carries
 *      the same id, so a turn is one grep.
 *   2. Emit a single `intent_produced` event with the input digest and
 *      source — the trace's first line.
 *   3. Stamp the same `correlationId` onto the returned `Intent` so
 *      `processIntent` does not mint a new one downstream.
 *
 * Producers (voice-session, shell-to-intent, oddjobz's chat-service,
 * any future cartridge that emits an intent) call this helper instead
 * of `reduceToIntent` directly. The reducer's per-pass events (RM-090)
 * land under the same correlationId, and `processIntent`'s pipeline
 * events follow because `intent.correlationId` is set.
 *
 * No LLM in here — the substrate's no-AI rule extends to its tooling.
 * `rawInput` is a string/bytes the producer already has; the helper
 * digests it deterministically for the trace.
 */
import type {
  CorrelationId,
  Intent,
  IntentSource,
  Logger,
  StageEvent,
} from './types.js';
import { reduceToIntent } from './reducer/index.js';
import type {
  GrammarSpec,
  ReducerInputState,
  ReducerOptions,
  ReducerResult,
} from './reducer/types.js';

export interface ProduceIntentInput {
  /** Free-form raw input the producer received (NL utterance, shell
   *  command string, JSON body, etc.). Digested into a 16-hex-char
   *  fingerprint that flows into the `intent_produced` event. The full
   *  raw input never enters the trace — only the digest. */
  rawInput: string;
  /** Producer source tag — propagated onto the returned Intent and
   *  every emitted StageEvent. */
  source: IntentSource;
  /** Reducer input — same shape `reduceToIntent` consumes. */
  reducerInput: ReducerInputState;
  /** Grammar spec — same shape `reduceToIntent` consumes. */
  grammar: GrammarSpec;
  /** Optional reducer options (thresholds, prior rejection, etc.).
   *  This helper layers its own `logger` + `correlationId` on top, so
   *  the caller does NOT need to set those — they would be ignored. */
  reducerOptions?: Omit<ReducerOptions, 'logger' | 'correlationId' | 'intentId'>;
  /** Pre-existing correlation id (e.g. from a parent turn). When set,
   *  the helper threads it through instead of minting a new one — the
   *  caller is responsible for ensuring it's unique enough. */
  correlationId?: CorrelationId;
  /** Producer-side logger. When supplied:
   *   - `intent_produced` is emitted on entry
   *   - the reducer also writes `reducer_pass_completed` to the same sink
   *   - downstream `processIntent` runs reuse the same correlationId
   *  When omitted the helper stays silent and just runs the reducer. */
  logger?: Logger;
  /** Wall-clock + uuid injection (deterministic tests). */
  deps?: ProduceIntentDeps;
}

export interface ProduceIntentDeps {
  uuid(): string;
  now(): Date;
}

export interface ProduceIntentResult extends ReducerResult {
  /** Same `correlationId` stamped on `intent.correlationId` and every
   *  emitted event. Returned so the caller can thread it onto further
   *  downstream calls (`processIntent`, retries, follow-up turns). */
  correlationId: CorrelationId;
}

const DEFAULT_DEPS: ProduceIntentDeps = {
  uuid: () => crypto.randomUUID(),
  now: () => new Date(),
};

export async function produceIntent(
  input: ProduceIntentInput,
): Promise<ProduceIntentResult> {
  const deps = input.deps ?? DEFAULT_DEPS;
  const correlationId =
    input.correlationId ?? (deps.uuid() as CorrelationId);
  const rawInputDigest = digestRawInput(input.rawInput);

  // 1. `intent_produced` — the trace's first line. Always emitted when a
  //    logger is supplied; never when it isn't (silent producers are
  //    allowed for batch / replay paths).
  if (input.logger) {
    const event: StageEvent = {
      ts: deps.now().toISOString(),
      correlationId,
      intentId: null, // No Intent yet — the reducer is about to mint one.
      stage: 'intent_produced',
      durationMs: 0,
      hatId: null,
      source: input.source,
      data: {
        rawInputDigest,
        rawInputLength: input.rawInput.length,
      },
    };
    input.logger.emit(event);
  }

  // 2. Reducer runs under the same correlationId. RM-090's per-pass
  //    events land on the same logger sink.
  const reducerResult = await reduceToIntent(input.reducerInput, input.grammar, {
    ...(input.reducerOptions ?? {}),
    logger: input.logger,
    correlationId,
  });

  // 3. Stamp the correlationId onto the returned Intent so
  //    `processIntent` reuses it instead of minting a fresh one.
  const intent: Intent = {
    ...reducerResult.intent,
    correlationId,
    source: input.source,
  };

  return {
    ...reducerResult,
    intent,
    correlationId,
  };
}

/**
 * Deterministic 16-hex-char digest of the raw input. Uses a simple
 * FNV-1a-style fold so we don't pull in a hashing dependency; the
 * digest is for trace grep-ability, not cryptographic identity.
 */
function digestRawInput(s: string): string {
  let h1 = 0xcbf29ce4n;
  let h2 = 0x84222325n;
  for (let i = 0; i < s.length; i++) {
    h1 ^= BigInt(s.charCodeAt(i));
    h1 = (h1 * 0x100000001b3n) & 0xffffffffffffffffn;
    h2 ^= BigInt(s.charCodeAt(i) * 31);
    h2 = (h2 * 0x100000001b3n) & 0xffffffffffffffffn;
  }
  return `${h1.toString(16).padStart(16, '0')}${h2.toString(16).padStart(16, '0')}`;
}

```
