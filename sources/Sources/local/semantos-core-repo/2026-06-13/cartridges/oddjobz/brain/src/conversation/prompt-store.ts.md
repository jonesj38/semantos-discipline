---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/prompt-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.527094+00:00
---

# cartridges/oddjobz/brain/src/conversation/prompt-store.ts

```ts
/**
 * Content-addressed, versioned prompt registry — D-OJ-conv-prompt-versioning.
 *
 * §13.3 resolution (docs/design/ODDJOBZ-CONVERSATION-ARCHITECTURE.md):
 * "every reply the AI/operator sends is generated from a versioned,
 *  schema'd prompt, and the prompt version is part of the audit trail …
 *  prompts are first-class artefacts, content-addressed and schema'd
 *  like cells; bumping a prompt = new version with the OLD version
 *  retained for the audit chain."
 *
 * This module makes the cartridge's prompts (extraction, pdf-extraction,
 * system, reply) first-class content-addressed artefacts:
 *
 *   • Each prompt is registered as an ordered list of VERSIONS. The
 *     newest entry is "latest"; older entries are retained verbatim so
 *     a reply-audit-log row can recover the EXACT prompt that produced
 *     a given reply, even after a bump.
 *   • The content hash is computed via the shared content-store
 *     primitive (`hashBytes` from @semantos/protocol-types) — the SAME
 *     SHA-256 used for cells. We do NOT roll our own hashing.
 *   • Deterministic: the same prompt text always yields the same
 *     content hash, reproducibly (the snapshot/replay DX requirement).
 *
 * Companion to `template-version.ts`: that module hashes the EXACT
 * assembled prompt the LLM saw on a given turn (drift-catching, per
 * turn). THIS module is the registry of the canonical prompt SCHEMAS
 * and their version history — the thing `resolvePrompt` reads and the
 * thing the audit log pins a turn to. See `linkTemplateDescriptor`
 * for how the two relate.
 *
 * Pure + deterministic. The only async surface is the content hash,
 * because the shared content-store primitive uses Web Crypto.
 */

import { hashBytes, makeHash, type Hash } from '@semantos/protocol-types';
import {
  buildExtractionPrompt,
  EXTRACTION_PROMPT_VERSION,
} from '../prompts/extraction-prompt.js';
import {
  buildPdfExtractionPrompt,
  PDF_EXTRACTION_PROMPT_VERSION,
} from '../prompts/pdf-extraction-prompt.js';
import {
  buildSystemPrompt,
  SYSTEM_PROMPT_VERSION,
} from '../prompts/system-prompt.js';
import { sha256hex } from './template-version.js';

// ── Prompt identifiers ───────────────────────────────────────

/**
 * Stable, cartridge-scoped prompt ids. The audit log records one of
 * these in its `(promptId, version, contentHash)` triple.
 */
export const PROMPT_IDS = {
  /** Structured-JSON extraction from a customer message. */
  extraction: 'oddjobz.prompt.extraction',
  /** PDF job-sheet extraction (real-estate-agent handoff flow). */
  pdfExtraction: 'oddjobz.prompt.pdf-extraction',
  /** Operator persona / system prompt (the chat persona). */
  system: 'oddjobz.prompt.system',
  /** Reply-generation prompt — the schema a sent reply is generated
   *  from. Currently the operator persona system prompt; split out as
   *  its own id so the reply-audit-log can pin replies independently of
   *  any future extraction-only system-prompt reuse. */
  reply: 'oddjobz.prompt.reply',
} as const;

export type PromptId = (typeof PROMPT_IDS)[keyof typeof PROMPT_IDS];

// ── Errors (typed, not crashes) ──────────────────────────────

export class UnknownPromptError extends Error {
  readonly name = 'UnknownPromptError';
  constructor(promptId: string) {
    super(`Unknown promptId: ${JSON.stringify(promptId)}`);
  }
}

export class UnknownPromptVersionError extends Error {
  readonly name = 'UnknownPromptVersionError';
  constructor(promptId: string, version: string) {
    super(
      `Unknown version ${JSON.stringify(version)} for prompt ${JSON.stringify(promptId)}`,
    );
  }
}

// ── Canonical schema text ────────────────────────────────────
//
// A prompt SCHEMA is the canonical, parameter-free template text the
// prompt is built from. Builders that take per-turn input are invoked
// here with a fixed canonical input so the schema text — and therefore
// its content hash — is deterministic and reproducible. The per-turn
// assembled prompt (which interpolates live state) is hashed
// separately by `template-version.ts`'s `promptHash`.

/** Canonical (parameter-free) extraction schema text. */
function canonicalExtractionText(): string {
  return buildExtractionPrompt({
    currentState: {},
    conversationSummary: '',
    latestMessage: '',
  });
}

/** Canonical operator persona schema text (default hat, no live
 *  history / channel / pdf context). */
function canonicalSystemText(): string {
  return buildSystemPrompt({ hatId: 'carpenter' });
}

// ── Version registry ─────────────────────────────────────────
//
// Each prompt is an ORDERED list of raw version entries. APPEND a new
// entry to bump; never edit-in-place an existing entry (that would
// rewrite history and break the audit chain). The last entry is
// "latest". Content hashes are derived, not stored, so the registry
// can't drift from its own text.

interface RawPromptVersion {
  readonly version: string;
  readonly text: string;
}

const REGISTRY: Readonly<Record<PromptId, readonly RawPromptVersion[]>> =
  Object.freeze({
    [PROMPT_IDS.extraction]: [
      { version: EXTRACTION_PROMPT_VERSION, text: canonicalExtractionText() },
    ],
    [PROMPT_IDS.pdfExtraction]: [
      {
        version: PDF_EXTRACTION_PROMPT_VERSION,
        text: buildPdfExtractionPrompt(),
      },
    ],
    [PROMPT_IDS.system]: [
      { version: SYSTEM_PROMPT_VERSION, text: canonicalSystemText() },
    ],
    [PROMPT_IDS.reply]: [
      // Reply generation currently uses the operator persona prompt.
      { version: SYSTEM_PROMPT_VERSION, text: canonicalSystemText() },
    ],
  });

// ── Resolved descriptor ──────────────────────────────────────

export interface ResolvedPrompt {
  readonly promptId: PromptId;
  readonly version: string;
  /** SHA-256 hex of the prompt text (content-store-derived). */
  readonly contentHash: string;
  readonly text: string;
}

/** The `(promptId, version, contentHash)` triple the audit log pins,
 *  without the (potentially large) text body. */
export interface PromptVersionRef {
  readonly promptId: PromptId;
  readonly version: string;
  readonly contentHash: string;
}

// ── Content hashing (shared primitive) ───────────────────────

const ENCODER = new TextEncoder();

/**
 * Content hash of a prompt's text via the SHARED content-store
 * primitive (`hashBytes`, the same SHA-256 used for cells). Returns
 * the branded 32-byte Hash. Async because Web Crypto is async.
 */
export async function promptContentHash(text: string): Promise<Hash> {
  return hashBytes(ENCODER.encode(text));
}

function hexOf(h: Hash): string {
  let s = '';
  for (let i = 0; i < h.length; i++) s += h[i]!.toString(16).padStart(2, '0');
  return s;
}

/**
 * Synchronous hex content hash. Uses the cartridge's existing
 * `sha256hex` (node:crypto) so the registry can be queried without an
 * await on a hot path. Verified byte-for-byte equal to the async
 * content-store hash in tests (`promptContentHash`), so the audit
 * log's recorded hex is interchangeable whichever path produced it.
 */
function contentHashHexSync(text: string): string {
  return sha256hex(text);
}

// ── Lookup API ───────────────────────────────────────────────

function rawVersions(promptId: string): readonly RawPromptVersion[] {
  const list = (REGISTRY as Record<string, readonly RawPromptVersion[]>)[
    promptId
  ];
  if (list === undefined || list.length === 0) {
    throw new UnknownPromptError(promptId);
  }
  return list;
}

/**
 * Resolve a prompt's text + version + content hash. Defaults to the
 * LATEST version; pass `version` to pin a historical one (the audit
 * replay path). Throws a TYPED error on unknown id/version — callers
 * branch, they don't crash.
 *
 * This is what reply generation calls; the audit log then records the
 * `(promptId, version, contentHash)` triple from the result.
 */
export function resolvePrompt(
  promptId: string,
  version?: string,
): ResolvedPrompt {
  // rawVersions throws UnknownPromptError for an unknown id; the
  // shared resolver then handles version selection + hashing.
  return resolveFromVersions(promptId, rawVersions(promptId), version);
}

/**
 * Latest version descriptor for a prompt id: `{ version, contentHash,
 * text }`. Thin wrapper over `resolvePrompt(promptId)` for the
 * `promptVersion(promptId)` shape called out in the deliverable.
 */
export function promptVersion(promptId: string): ResolvedPrompt {
  return resolvePrompt(promptId);
}

/** The pin triple (no text body) — what the audit log stores. */
export function promptVersionRef(
  promptId: string,
  version?: string,
): PromptVersionRef {
  const r = resolvePrompt(promptId, version);
  return { promptId: r.promptId, version: r.version, contentHash: r.contentHash };
}

/** All known prompt ids. */
export function listPromptIds(): PromptId[] {
  return Object.keys(REGISTRY) as PromptId[];
}

/** Every retained version of a prompt id, oldest → newest. Lets an
 *  operator enumerate the full audit chain for a culprit prompt. */
export function listPromptVersions(promptId: string): ResolvedPrompt[] {
  return rawVersions(promptId).map((entry) => ({
    promptId: promptId as PromptId,
    version: entry.version,
    contentHash: contentHashHexSync(entry.text),
    text: entry.text,
  }));
}

/**
 * Cross-check the content-store-derived hash against the synchronous
 * hex the registry serves. Used in tests to prove the two hashing
 * paths agree byte-for-byte. Returns the canonical hex.
 */
export async function verifyContentHashHex(text: string): Promise<string> {
  const h = await promptContentHash(text);
  // Round-trip the brand to exercise makeHash on the path the audit
  // log would use when re-deriving from stored bytes.
  return hexOf(makeHash(h));
}

/**
 * Resolve a `(version?, text)` selection against an ARBITRARY ordered
 * version list, using the SAME selection + hashing code path as the
 * real registry. Exposed so a bump can be exercised end-to-end against
 * a synthetic two-version list (and so a downstream consumer with its
 * own prompt set can reuse the primitive). Throws the same typed
 * errors as `resolvePrompt`.
 */
export function resolveFromVersions(
  promptId: string,
  versions: readonly RawPromptVersion[],
  version?: string,
): ResolvedPrompt {
  if (versions.length === 0) throw new UnknownPromptError(promptId);
  let entry: RawPromptVersion | undefined;
  if (version === undefined) {
    entry = versions[versions.length - 1];
  } else {
    entry = versions.find((v) => v.version === version);
    if (entry === undefined) {
      throw new UnknownPromptVersionError(promptId, version);
    }
  }
  return {
    promptId: promptId as PromptId,
    version: entry!.version,
    contentHash: contentHashHexSync(entry!.text),
    text: entry!.text,
  };
}

```
