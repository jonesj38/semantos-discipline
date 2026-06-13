---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/host-exec/extractor/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.396303+00:00
---

# runtime/shell/src/host-exec/extractor/types.ts

```ts
/**
 * Extractor types — NL utterance → structured ShellCommand draft.
 *
 * Phase 38F — the extractor is a pure function:
 *   (utterance, handlers) → ExtractResult
 * No side effects, no store writes, no PII logging.
 */

import type { HandlerManifest } from '../types';

/** A successfully extracted command ready for approval. */
export interface ExtractedCommand {
  verb: 'host.exec';
  handler: string;
  args: Record<string, unknown>;
  confidence: number;
  rationale?: string;
}

/** A structured extraction failure. */
export interface ExtractError {
  ok: false;
  code: 'UNPARSEABLE' | 'UNKNOWN_HANDLER' | 'INVALID_ARGS' | 'LLM_UNAVAILABLE';
  message: string;
  suggestions?: string[];
  raw?: unknown;
}

/** Discriminated result: success or structured error. */
export type ExtractResult = ({ ok: true } & ExtractedCommand) | ExtractError;

/** Minimal LLM client interface — caller provides the implementation. */
export interface LlmClient {
  complete(systemPrompt: string, userMessage: string): Promise<string | null>;
}

/** Context for the extractor — handler allowlist + optional LLM. */
export interface ExtractorContext {
  handlers: HandlerManifest[];
  llm?: LlmClient | null;
}

```
