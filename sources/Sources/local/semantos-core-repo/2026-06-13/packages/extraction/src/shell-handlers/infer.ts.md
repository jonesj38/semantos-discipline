---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/shell-handlers/infer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.461075+00:00
---

# packages/extraction/src/shell-handlers/infer.ts

```ts
/**
 * D36C.6 — Shell inference commands: infer, review, approve, reject, list.
 *
 * The `semantos infer` subcommand bootstraps Extension Grammars from
 * unfamiliar API responses. All inferred grammars are AFFINE drafts
 * pending human review. Credentials are ephemeral — never stored.
 *
 * Cross-references:
 *   structure-analyzer.ts  → analyzeStructure()
 *   taxonomy-mapper.ts     → mapTaxonomy()
 *   grammar-diff.ts        → diffGrammars()
 *   grammar-composer.ts    → composeGrammar()
 *   pipeline.ts            → InferenceAgent
 */

import { readFileSync, existsSync, readdirSync } from 'fs';
import { join, resolve } from 'path';
import type { ShellCommand } from '@semantos/shell/parser';
import type { ShellContext } from '@semantos/shell/types';
import type { ExtensionGrammar } from '@semantos/protocol-types';
import type { ObjectPatch } from '@semantos/runtime-services';
import { InferenceAgent } from '../index';
import type { RawResponse, LLMSettings } from '../index';
import { INVALID_INFER_USAGE, FILE_NOT_FOUND, JSON_PARSE_FAILED, INFERENCE_FAILED, INFERRED_GRAMMAR_NOT_FOUND, PUBLISH_FAILED, MISSING_REJECTION_REASON } from '@semantos/shell/error-codes';

// ── Main Router ────────────────────────────────────────────────

/**
 * Route infer subcommands: <path>, review, approve, reject, list.
 */
export async function routeInfer(cmd: ShellCommand, ctx: ShellContext): Promise<unknown> {
  const subcommand = cmd.flags.subcommand as string | undefined;

  if (!subcommand) {
    return {
      error: 'Usage: semantos infer <sample-file.json|api-url> [--auth <type>] | semantos infer <review|approve|reject|list> [args]',
      code: INVALID_INFER_USAGE,
      available: ['<file.json>', 'review', 'approve', 'reject', 'list'],
    };
  }

  switch (subcommand) {
    case 'review':
      return handleReview(cmd, ctx);
    case 'approve':
      return handleApprove(cmd, ctx);
    case 'reject':
      return handleReject(cmd, ctx);
    case 'list':
      return handleList(cmd, ctx);
    default:
      // Treat subcommand as a file path or URL
      return handleInfer(cmd, ctx, subcommand);
  }
}

// ── Infer from File/URL ────────────────────────────────────────

async function handleInfer(
  cmd: ShellCommand,
  ctx: ShellContext,
  pathOrUrl: string,
): Promise<unknown> {
  let sampleResponses: RawResponse[];

  // Determine if input is a file or URL
  if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
    return {
      error: 'Live API inference not yet implemented. Use a saved response file: semantos infer <sample-file.json>',
      hint: 'Save API responses to a JSON file and pass the file path instead.',
    };
  }

  // File-based inference
  const filePath = resolve(pathOrUrl);
  if (!existsSync(filePath)) {
    return { error: `File not found: ${filePath}`, code: FILE_NOT_FOUND };
  }

  try {
    const raw = readFileSync(filePath, 'utf-8');
    const parsed = JSON.parse(raw);

    // Accept either an array of RawResponse objects or a single response body
    if (Array.isArray(parsed)) {
      sampleResponses = parsed.map((item: unknown, i: number) => {
        if (isRawResponse(item)) return item as RawResponse;
        return {
          body: item,
          sampledAt: new Date().toISOString(),
          url: `file://${filePath}#${i}`,
        };
      });
    } else {
      sampleResponses = [{
        body: parsed,
        sampledAt: new Date().toISOString(),
        url: `file://${filePath}`,
      }];
    }
  } catch (e) {
    return { error: `Failed to parse ${filePath}: ${e instanceof Error ? e.message : String(e)}`, code: JSON_PARSE_FAILED };
  }

  // Build LLM settings from environment
  const settings: LLMSettings = {
    openRouterApiKey: process.env.OPENROUTER_API_KEY ?? null,
    modelId: process.env.OPENROUTER_MODEL ?? 'anthropic/claude-sonnet-4-20250514',
    temperature: 0.1,
  };

  // Load installed grammars for diff comparison
  const installedGrammars = loadInstalledGrammars();

  // Build source config from flags
  const sourceConfig: Record<string, unknown> = {};
  const protocol = cmd.flags['source-type'] as string | undefined;
  if (protocol) {
    sourceConfig.protocol = protocol;
  }

  // Run inference
  const agent = new InferenceAgent(ctx.store, settings, installedGrammars);

  try {
    const result = await agent.infer(sampleResponses, sourceConfig as any);
    return {
      grammarId: result.grammarId,
      valid: result.valid,
      objectId: result.objectId,
      reviewSummary: result.reviewSummary,
      lowConfidenceFlags: result.lowConfidenceFlags.length,
      summary: `Inferred grammar '${result.grammarId}' with ${result.reviewSummary.totalEntities} entities. ` +
        `Use 'semantos infer review ${result.objectId ?? result.grammarId}' to review.`,
    };
  } catch (e) {
    return { error: `Inference failed: ${e instanceof Error ? e.message : String(e)}`, code: INFERENCE_FAILED };
  }
}

// ── Review ─────────────────────────────────────────────────────

function handleReview(cmd: ShellCommand, ctx: ShellContext): unknown {
  const targetId = cmd.flags.path as string | undefined;
  if (!targetId) {
    return { error: 'Usage: semantos infer review <grammar-id|object-id>', code: INVALID_INFER_USAGE };
  }

  // Find the inferred grammar object in LoomStore
  const obj = findInferredGrammar(ctx, targetId);
  if (!obj) {
    return { error: `Inferred grammar not found: ${targetId}`, code: INFERRED_GRAMMAR_NOT_FOUND };
  }

  return {
    objectId: obj.id,
    type: obj.typeDefinition.name,
    visibility: obj.visibility,
    payload: obj.payload,
    evidence: obj.patches.map(p => ({
      id: p.id,
      kind: p.kind,
      action: (p.delta as Record<string, unknown>).action,
      timestamp: new Date(p.timestamp).toISOString(),
    })),
  };
}

// ── Approve ────────────────────────────────────────────────────

function handleApprove(cmd: ShellCommand, ctx: ShellContext): unknown {
  const targetId = cmd.flags.path as string | undefined;
  if (!targetId) {
    return { error: 'Usage: semantos infer approve <grammar-id|object-id> [--publish]', code: INVALID_INFER_USAGE };
  }

  const obj = findInferredGrammar(ctx, targetId);
  if (!obj) {
    return { error: `Inferred grammar not found: ${targetId}`, code: INFERRED_GRAMMAR_NOT_FOUND };
  }

  const shouldPublish = cmd.flags.publish === true;

  // Add approval patch to evidence chain
  const hat = ctx.identity.getActiveHat();
  const approvalPatch: ObjectPatch = {
    id: `patch-${Date.now()}-approval`,
    kind: 'action',
    timestamp: Date.now(),
    delta: {
      action: 'grammar_approved',
      approvedBy: hat?.id ?? 'anonymous',
      approvedAt: new Date().toISOString(),
      publish: shouldPublish,
    },
    hatId: hat?.id,
    hatCapabilities: hat?.capabilities,
  };
  ctx.store.dispatch({ type: 'ADD_PATCH', objectId: obj.id, patch: approvalPatch });

  // Transition to published if --publish flag
  if (shouldPublish) {
    try {
      const hatCaps = hat?.capabilities ?? [];
      ctx.store.transitionVisibility(obj.id, 'published', hatCaps);
    } catch (e) {
      return { error: `Approval recorded but publish failed: ${e instanceof Error ? e.message : String(e)}`, code: PUBLISH_FAILED };
    }
  }

  // Update status in payload
  ctx.store.dispatch({
    type: 'UPDATE_PAYLOAD',
    objectId: obj.id,
    field: 'status',
    value: shouldPublish ? 'published' : 'approved',
  });

  return {
    objectId: obj.id,
    status: shouldPublish ? 'published' : 'approved',
    message: shouldPublish
      ? `Grammar approved and published (AFFINE → RELEVANT). ID: ${obj.id}`
      : `Grammar approved but not published. Use --publish to publish. ID: ${obj.id}`,
  };
}

// ── Reject ─────────────────────────────────────────────────────

function handleReject(cmd: ShellCommand, ctx: ShellContext): unknown {
  const targetId = cmd.flags.path as string | undefined;
  if (!targetId) {
    return { error: 'Usage: semantos infer reject <grammar-id|object-id> --reason "reason text"', code: INVALID_INFER_USAGE };
  }

  const reason = cmd.flags.reason as string | undefined;
  if (!reason) {
    return { error: 'Rejection requires --reason "reason text"', code: MISSING_REJECTION_REASON };
  }

  const obj = findInferredGrammar(ctx, targetId);
  if (!obj) {
    return { error: `Inferred grammar not found: ${targetId}`, code: INFERRED_GRAMMAR_NOT_FOUND };
  }

  // Add rejection patch to evidence chain
  const hat = ctx.identity.getActiveHat();
  const rejectPatch: ObjectPatch = {
    id: `patch-${Date.now()}-rejection`,
    kind: 'action',
    timestamp: Date.now(),
    delta: {
      action: 'grammar_rejected',
      rejectedBy: hat?.id ?? 'anonymous',
      rejectedAt: new Date().toISOString(),
      reason,
    },
    hatId: hat?.id,
    hatCapabilities: hat?.capabilities,
  };
  ctx.store.dispatch({ type: 'ADD_PATCH', objectId: obj.id, patch: rejectPatch });

  // Update status
  ctx.store.dispatch({
    type: 'UPDATE_PAYLOAD',
    objectId: obj.id,
    field: 'status',
    value: 'rejected',
  });

  return {
    objectId: obj.id,
    status: 'rejected',
    reason,
    message: `Grammar rejected. Reason: ${reason}. ID: ${obj.id}`,
  };
}

// ── List ───────────────────────────────────────────────────────

function handleList(cmd: ShellCommand, ctx: ShellContext): unknown {
  const statusFilter = cmd.flags.status as string | undefined;
  const state = ctx.store.getState();
  const objects = [...state.objects.values()];

  let filtered = objects.filter(obj =>
    obj.typeDefinition.name === 'InferredGrammar' ||
    obj.typeDefinition.category === 'platform.extension',
  );

  if (statusFilter) {
    filtered = filtered.filter(obj => {
      const payload = obj.payload as Record<string, unknown> | undefined;
      return payload?.status === statusFilter;
    });
  }

  return filtered.map(obj => ({
    id: obj.id,
    grammarId: (obj.payload as Record<string, unknown>)?.grammarId ?? 'unknown',
    status: (obj.payload as Record<string, unknown>)?.status ?? obj.visibility,
    summary: (obj.payload as Record<string, unknown>)?.summary ?? '',
    patches: obj.patches.length,
  }));
}

// ── Helpers ────────────────────────────────────────────────────

function findInferredGrammar(ctx: ShellContext, targetId: string) {
  const state = ctx.store.getState();

  // Try direct object ID lookup
  const direct = state.objects.get(targetId);
  if (direct) return direct;

  // Search by grammarId in payload
  for (const obj of state.objects.values()) {
    const payload = obj.payload as Record<string, unknown> | undefined;
    if (payload?.grammarId === targetId) return obj;
  }

  return null;
}

function isRawResponse(item: unknown): boolean {
  if (typeof item !== 'object' || item === null) return false;
  const obj = item as Record<string, unknown>;
  return 'body' in obj && 'sampledAt' in obj;
}

/** Load all installed grammars from configs/extensions/. */
function loadInstalledGrammars(): ExtensionGrammar[] {
  const grammars: ExtensionGrammar[] = [];
  const extensionsDir = resolve(process.cwd(), 'configs/extensions');

  if (!existsSync(extensionsDir)) return grammars;

  try {
    const dirs = readdirSync(extensionsDir, { withFileTypes: true });
    for (const dir of dirs) {
      if (!dir.isDirectory()) continue;
      const grammarPath = join(extensionsDir, dir.name, 'grammar.json');
      if (existsSync(grammarPath)) {
        try {
          const raw = readFileSync(grammarPath, 'utf-8');
          grammars.push(JSON.parse(raw) as ExtensionGrammar);
        } catch {
          // Skip invalid grammar files
        }
      }
    }
  } catch {
    // Skip if directory listing fails
  }

  return grammars;
}

```
