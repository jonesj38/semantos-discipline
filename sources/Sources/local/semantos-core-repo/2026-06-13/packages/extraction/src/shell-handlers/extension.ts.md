---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/shell-handlers/extension.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.460772+00:00
---

# packages/extraction/src/shell-handlers/extension.ts

```ts
/**
 * Shell extension commands — list, status, detail for installed extensions.
 *
 * Reads from ShellContext (store, config, identity).
 * Shows grammar info, extraction status, version compatibility.
 *
 * Phase 36E: New shell verb 'extension' with subcommands.
 */

import type { ShellCommand } from '@semantos/shell/parser';
import type { ShellContext } from '@semantos/shell/types';
import type { GovernedConsumerBindingPayload, ExtensionManifest } from '@semantos/protocol-types';
import { checkCompatibility } from '../index';
import { INVALID_EXTENSION_USAGE, EXTENSION_NOT_FOUND } from '@semantos/shell/error-codes';

/**
 * Route extension subcommands: list, status, detail.
 */
export async function routeExtension(cmd: ShellCommand, ctx: ShellContext): Promise<unknown> {
  const subcommand = cmd.flags.subcommand as string | undefined;

  if (!subcommand) {
    return {
      error: 'Usage: semantos extension <list|status|detail> [options]',
      code: INVALID_EXTENSION_USAGE,
      available: ['list', 'status', 'detail'],
    };
  }

  switch (subcommand) {
    case 'list':
      return handleList(cmd, ctx);
    case 'status':
      return handleStatus(cmd, ctx);
    case 'detail':
      return handleDetail(cmd, ctx);
    default:
      return {
        error: `Unknown extension subcommand '${subcommand}'. Use: list, status, detail`,
        code: INVALID_EXTENSION_USAGE,
      };
  }
}

// ── List ─────────────────────────────────────────────────────────

function handleList(cmd: ShellCommand, ctx: ShellContext): unknown {
  const state = ctx.store.getState();
  const jsonMode = cmd.flags.json === true;

  // Find ConsumerBinding objects in the store
  const bindings: Array<{
    id: string;
    extensionId: string;
    version: string;
    status: string;
    objectCount: number;
    lastRun: string | null;
    grammarInfo: {
      objectTypes?: number;
      entities?: number;
      capabilities?: number;
    };
  }> = [];

  for (const obj of state.objects.values()) {
    const p = obj.payload as Record<string, unknown>;
    if (p.extensionManifestId && p.grammarVersionPinned) {
      const payload = p as unknown as GovernedConsumerBindingPayload;

      // Count objects created by this extension (via extraction patches)
      let objectCount = 0;
      for (const o of state.objects.values()) {
        if (o.patches.some(patch => patch.kind === 'extraction')) {
          objectCount++;
        }
      }

      bindings.push({
        id: obj.id,
        extensionId: payload.extensionManifestId,
        version: payload.grammarVersionPinned,
        status: payload.status,
        objectCount,
        lastRun: payload.lastExtractionTimestamp ?? null,
        grammarInfo: {},
      });
    }
  }

  // Also list the active extension from config
  const config = ctx.config.getConfig();
  if (config) {
    bindings.push({
      id: 'active',
      extensionId: config.id ?? ctx.activeExtension,
      version: config.version ?? '1.0.0',
      status: 'active',
      objectCount: state.objects.size,
      lastRun: null,
      grammarInfo: {
        objectTypes: config.objectTypes?.length ?? 0,
      },
    });
  }

  if (jsonMode) {
    return bindings;
  }

  if (bindings.length === 0) {
    return { message: 'No extensions installed.' };
  }

  return {
    header: 'Installed Extensions',
    extensions: bindings.map(b => ({
      name: b.extensionId,
      version: b.version,
      status: b.status,
      objects: b.objectCount,
      lastRun: b.lastRun ?? 'never',
      ...(b.grammarInfo.objectTypes !== undefined ? { objectTypes: b.grammarInfo.objectTypes } : {}),
    })),
  };
}

// ── Status ──────────────────────────────────────────────────────

function handleStatus(cmd: ShellCommand, ctx: ShellContext): unknown {
  const state = ctx.store.getState();
  const config = ctx.config.getConfig();

  const statuses: Array<{
    extension: string;
    version: string;
    status: string;
    compatibility: string;
    lastExtraction: string;
    objectCount: number;
    governance: string;
  }> = [];

  // Check active extension
  if (config) {
    statuses.push({
      extension: `${config.id ?? ctx.activeExtension}`,
      version: config.version ?? '1.0.0',
      status: 'active',
      compatibility: 'green',
      lastExtraction: 'N/A',
      objectCount: state.objects.size,
      governance: 'no active disputes',
    });
  }

  // Check consumer bindings
  for (const obj of state.objects.values()) {
    const p = obj.payload as Record<string, unknown>;
    if (p.extensionManifestId && p.grammarVersionPinned) {
      const payload = p as unknown as GovernedConsumerBindingPayload;
      statuses.push({
        extension: payload.extensionManifestId,
        version: payload.grammarVersionPinned,
        status: payload.status,
        compatibility: payload.status === 'deprecated' ? 'red' : 'green',
        lastExtraction: payload.lastExtractionTimestamp ?? 'never',
        objectCount: 0,
        governance: 'no active disputes',
      });
    }
  }

  if (statuses.length === 0) {
    return { message: 'No extensions to report status for.' };
  }

  return { statuses };
}

// ── Detail ──────────────────────────────────────────────────────

function handleDetail(cmd: ShellCommand, ctx: ShellContext): unknown {
  const extensionId = cmd.objectId ?? (cmd.flags.id as string | undefined);
  const showGrammar = cmd.flags.grammar === true;
  const showEntities = cmd.flags.entities === true;
  const showHistory = cmd.flags.history === true;

  if (!extensionId) {
    return { error: 'Usage: semantos extension detail <id> [--grammar] [--entities] [--history]', code: INVALID_EXTENSION_USAGE };
  }

  const config = ctx.config.getConfig();
  const state = ctx.store.getState();

  // Check if it's the active extension
  if (config && (config.id === extensionId || ctx.activeExtension === extensionId)) {
    const detail: Record<string, unknown> = {
      id: extensionId,
      name: config.name ?? extensionId,
      version: config.version ?? '1.0.0',
      objectTypes: config.objectTypes?.length ?? 0,
      capabilities: config.capabilities?.length ?? 0,
    };

    if (showGrammar && config.objectTypes) {
      detail.objectTypeList = config.objectTypes.map(ot => ({
        name: ot.name,
        category: ot.category,
        fields: ot.fields?.length ?? 0,
      }));
    }

    if (showHistory) {
      // Count extraction patches
      let extractionRuns = 0;
      for (const obj of state.objects.values()) {
        if (obj.patches.some(p => p.kind === 'extraction')) extractionRuns++;
      }
      detail.extractionHistory = { runs: extractionRuns, totalObjects: state.objects.size };
    }

    return detail;
  }

  // Check consumer bindings
  for (const obj of state.objects.values()) {
    const p = obj.payload as Record<string, unknown>;
    if (p.extensionManifestId === extensionId) {
      const payload = p as unknown as GovernedConsumerBindingPayload;
      return {
        id: extensionId,
        bindingId: obj.id,
        version: payload.grammarVersionPinned,
        status: payload.status,
        autoUpdate: payload.autoUpdateGrammar,
        credentials: payload.credentialsEncrypted?.credentialFieldNames ?? [],
        fieldOverrides: payload.fieldOverrides?.length ?? 0,
        taxonomyOverrides: payload.taxonomyOverrides?.length ?? 0,
        lastExtraction: payload.lastExtractionTimestamp ?? 'never',
      };
    }
  }

  return { error: `Extension not found: ${extensionId}`, code: EXTENSION_NOT_FOUND };
}

```
