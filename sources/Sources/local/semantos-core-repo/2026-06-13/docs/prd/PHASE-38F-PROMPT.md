---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-38F-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.666911+00:00
---

# Phase 38F Execution Prompt — Natural-Language → ShellCommand Extractor

> Paste into a fresh session. **Parallel track** — starts as soon as 38A is on `phase-38-voice-to-execution`. Not on the hot path.

## Context

The user says "kill the process on port 9000". The mic (38E) hands us the plain string. Before we can sign, publish, and dispatch a `HostCommand` (38C), we have to turn the utterance into a structured `ShellCommand`:

```json
{ "verb": "host.exec", "args": { "handler": "process.killByPort", "port": 9000 }, "confidence": 0.94 }
```

This sub-phase builds the extractor. It uses the project's existing LLM surface (look for `chat.ts` or a provider client in `packages/shell/src/llm/` — read before writing) and a strict, schema-validated output. Hallucinated handler names are caught at extract time, not at dispatch.

---

## CRITICAL: READ THESE FILES FIRST

- `docs/prd/PHASE-38-VOICE-TO-EXECUTION.md` — epic
- `docs/prd/PHASE-38B-PROMPT.md` — the handler registry you validate against
- `packages/shell/src/commands/chat.ts` (or equivalent) — existing LLM call pattern
- `packages/shell/src/host-exec/registry.ts` — `listHandlers()` gives the allowlist
- `packages/extraction/src/` — if an extraction framework already exists, reuse it
- `packages/loom/src/services/FlowRunner.ts` — if extraction is modeled as a flow, follow that pattern

---

## ANTI-BULLSHIT RULES

1. **Grounded output only.** The system prompt includes the *current* handler manifest list. The LLM picks from that list. If the output's `handler` is not in the registry, the extractor returns `{ok: false, code: 'UNKNOWN_HANDLER', suggestions: [...]}` — it does NOT pass through.
2. **Schema-validated parse.** The LLM returns JSON. Validate it against a Zod/JSONSchema *before* anyone touches it. A parse error is a structured error, not an exception.
3. **Confidence is surfaced, not suppressed.** The extractor returns a `confidence` in [0,1]. The UI (38G) decides whether to auto-approve or prompt. The extractor never auto-dispatches.
4. **Args coerced to declared types.** If the handler's manifest says `port: number`, the extracted `"9000"` becomes `9000`. If it can't coerce, `INVALID_ARGS` with the offending field.
5. **Deterministic offline mode.** A regex/keyword fallback handles a small fixture set of utterances (the acceptance-test fixture at minimum) so CI can run without hitting a live LLM. If `LLM_PROVIDER` is unset, use the fallback. Fallback results have `confidence <= 0.5`.
6. **No side effects.** Pure function of `(utterance, registry) → ShellCommandDraft`. No network beyond the LLM call. No writes to LoomStore. No logging PII to disk.

---

## PART 0: GIT HYGIENE

```bash
git checkout phase-38-voice-to-execution
git pull --ff-only
```

---

## Step 1: Types & Public API (D38F.1)

### 1.1 Create `packages/shell/src/host-exec/extractor/types.ts`

```ts
export interface ExtractedCommand {
  verb: 'host.exec';
  handler: string;                  // must be in the registry
  args: Record<string, unknown>;    // coerced to manifest types
  confidence: number;               // [0, 1]
  rationale?: string;               // optional one-line explanation from the LLM
}

export interface ExtractError {
  ok: false;
  code: 'UNPARSEABLE' | 'UNKNOWN_HANDLER' | 'INVALID_ARGS' | 'LLM_UNAVAILABLE';
  message: string;
  suggestions?: string[];           // candidate handler ids for UNKNOWN_HANDLER
  raw?: unknown;                    // raw LLM output, for debugging (never surface to user)
}

export type ExtractResult = ({ ok: true } & ExtractedCommand) | ExtractError;

export interface ExtractorContext {
  handlers: HandlerManifest[];      // from registry.listHandlers()
  llm?: LlmClient | null;           // null ⇒ use deterministic fallback
}
```

### 1.2 Commit

```bash
git commit -m "phase-38/D38F.1: extractor types — ExtractedCommand, ExtractError, ExtractorContext"
```

---

## Step 2: LLM Extractor (D38F.2)

### 2.1 Create `packages/shell/src/host-exec/extractor/llm.ts`

- Build a system prompt that includes the full handler manifest, inline:

  ```
  You turn a user utterance into a structured shell command.
  Allowed handlers (pick exactly one id from this list, or refuse):
  - process.killByPort — args: {port: integer 1..65535, signal?: 'SIGTERM'|'SIGKILL'}
  - …
  Return JSON: {"handler": "<id>", "args": {...}, "confidence": 0..1, "rationale": "<1 sentence>"}
  If no handler matches, return: {"handler": null, "args": {}, "confidence": 0, "rationale": "<why>"}
  ```

- Call the LLM with `temperature: 0`, `max_tokens: 200`.
- Parse the response as JSON with a tolerant extractor (strip code fences, trim whitespace).
- Validate with Zod against the manifest. `UNPARSEABLE` if JSON fails. `UNKNOWN_HANDLER` if the id isn't in `handlers`. `INVALID_ARGS` if required args are missing or uncoercible.
- Coerce args to manifest types (`Number(v)` for number fields, `String(v)` for string, accept booleans literal).

### 2.2 Create `packages/shell/src/host-exec/extractor/fallback.ts`

Deterministic rule-based extractor. Minimum coverage:

- `"kill the process on port <N>"` → `{handler: 'process.killByPort', args: {port: N}, confidence: 0.5}`
- `"force kill port <N>"` → `{handler: 'process.killByPort', args: {port: N, signal: 'SIGKILL'}, confidence: 0.4}`
- Unmatched utterance → `{ok: false, code: 'UNPARSEABLE', message: 'No rule matched'}`

This is a few regexes. It is **not** a full NL parser. Its job is: (a) CI works offline, (b) the acceptance-test fixture is deterministic.

### 2.3 Create `packages/shell/src/host-exec/extractor/index.ts`

Unified entry point:

```ts
export async function extractShellCommand(
  utterance: string,
  ctx: ExtractorContext,
): Promise<ExtractResult> {
  const trimmed = utterance.trim();
  if (!trimmed) return { ok: false, code: 'UNPARSEABLE', message: 'Empty utterance' };
  if (ctx.llm) {
    try { return await extractViaLlm(trimmed, ctx); }
    catch (err) {
      // fall through to deterministic fallback if the LLM fails
    }
  }
  return extractViaFallback(trimmed, ctx);
}
```

### 2.4 Commit

```bash
git add packages/shell/src/host-exec/extractor/
git commit -m "phase-38/D38F.2: NL → ShellCommand extractor — LLM path + deterministic fallback"
```

---

## Step 3: Gate Tests (D38F.3)

Add to `packages/__tests__/phase38-gate.test.ts`:

1. Fallback: `"kill the process on port 9000"` → `{ok: true, handler: 'process.killByPort', args: {port: 9000}, confidence <= 0.5}`.
2. Fallback: empty string → `{ok: false, code: 'UNPARSEABLE'}`.
3. Fallback: `"please delete all my files"` (no matching handler) → `{ok: false, code: 'UNPARSEABLE'}` (no coincidental match on unsafe verbs).
4. LLM mocked to return `{"handler": "fs.deleteEverything", ...}` (not in registry) → `{ok: false, code: 'UNKNOWN_HANDLER', suggestions: [...]}`.
5. LLM mocked to return `{"handler": "process.killByPort", "args": {"port": "9000"}, "confidence": 0.9}` → args coerced to `{port: 9000}` (number).
6. LLM mocked to return malformed JSON → `{ok: false, code: 'UNPARSEABLE'}`.
7. No network call on fallback path (assert the LLM client is not invoked when `ctx.llm === null`).

Commit:

```bash
git commit -m "phase-38/D38F.3: gate tests for extractor — fallback, LLM mock, coercion, grounding"
```

---

## Step 4: Expose to Shell & Helm (D38F.4)

### 4.1 Re-export from `packages/shell/src/index.ts` and `packages/shell/src/browser.ts`

```ts
export { extractShellCommand } from './host-exec/extractor';
export type { ExtractResult, ExtractedCommand, ExtractError } from './host-exec/extractor/types';
```

### 4.2 Commit

```bash
git commit -m "phase-38/D38F.4: export extractShellCommand from shell public API"
```

---

## Exit Criteria

- [ ] `extractShellCommand(utterance, ctx)` returns a validated, type-coerced `ExtractedCommand` or a structured error.
- [ ] Handler grounding: unknown handlers never leak through.
- [ ] Deterministic fallback covers the acceptance fixture; CI can run without an LLM provider.
- [ ] All gate tests pass.

Hand off to 38G.
