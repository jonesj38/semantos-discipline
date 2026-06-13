---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/commands/doc.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.373908+00:00
---

# runtime/shell/src/commands/doc.ts

```ts
/**
 * Document operation commands — share, export, merge, diff.
 *
 * These verbs operate on Document-type objects in the LoomStore,
 * producing/consuming portable DocumentBundle JSON files.
 *
 *   semantos share <object-id> --to <hat-name>
 *   semantos export <object-id> [--output <path>]
 *   semantos merge <object-id> --from <bundle-path> [--cherry-pick <patch-ids>]
 *   semantos diff <object-id> --from <bundle-path>
 */

import type { ShellCommand } from '../parser';
import type { ShellContext } from '../types';
import type { LoomObject, ObjectPatch } from '@semantos/runtime-services';

interface BundleData {
  version: 1;
  exportedAt: number;
  exportedBy: string;
  documentId: string;
  typeHash: string;
  typeName: string;
  payload: Record<string, unknown>;
  patches: ObjectPatch[];
  visibility: string;
  linearity: number;
  createdAt: number;
  updatedAt: number;
}

function getObject(ctx: ShellContext, id: string): LoomObject | null {
  return ctx.store.getState().objects.get(id) ?? null;
}

function createBundle(obj: LoomObject, exportedBy: string): BundleData {
  return {
    version: 1,
    exportedAt: Date.now(),
    exportedBy,
    documentId: obj.id,
    typeHash: obj.typeDefinition.typeHash,
    typeName: obj.typeDefinition.name,
    payload: { ...obj.payload },
    patches: obj.patches.map(p => ({ ...p })),
    visibility: obj.visibility,
    linearity: obj.header.linearity,
    createdAt: obj.createdAt,
    updatedAt: obj.updatedAt,
  };
}

/** semantos export <object-id> */
export async function routeExport(cmd: ShellCommand, ctx: ShellContext): Promise<unknown> {
  const objectId = cmd.objectId;
  if (!objectId) return { error: "Usage: semantos export <object-id>" };

  const obj = getObject(ctx, objectId);
  if (!obj) return { error: `Object not found: ${objectId}` };

  const hat = ctx.identity.getActiveHat();
  const bundle = createBundle(obj, hat?.id ?? 'anonymous');

  const outputPath = cmd.flags.output as string | undefined;
  if (outputPath && ctx.adapter) {
    const data = new TextEncoder().encode(JSON.stringify(bundle, null, 2));
    await ctx.adapter.write(outputPath, data);
    return {
      exported: true,
      path: outputPath,
      documentId: obj.id,
      patches: obj.patches.length,
    };
  }

  // Return bundle as JSON output
  return bundle;
}

/** semantos share <object-id> --to <hat-name> */
export async function routeShare(cmd: ShellCommand, ctx: ShellContext): Promise<unknown> {
  const objectId = cmd.objectId;
  if (!objectId) return { error: "Usage: semantos share <object-id> --to <hat-name>" };

  const toName = cmd.flags.to as string | undefined;
  if (!toName) return { error: "Missing --to flag. Usage: semantos share <object-id> --to <hat-name>" };

  const obj = getObject(ctx, objectId);
  if (!obj) return { error: `Object not found: ${objectId}` };

  const identity = ctx.identity.getIdentity();
  if (!identity) return { error: 'No identity. Create one first.' };

  const fromFacet = ctx.identity.getActiveHat();
  if (!fromFacet) return { error: 'No active hat. Switch to one first.' };

  const toFacet = identity.hats.find(
    f => f.name.toLowerCase() === toName.toLowerCase()
  );
  if (!toFacet) {
    const available = identity.hats.map(f => f.name).join(', ');
    return { error: `Hat '${toName}' not found. Available: ${available}` };
  }

  const bundle = createBundle(obj, fromFacet.id);

  return {
    shared: true,
    from: fromFacet.name,
    to: toFacet.name,
    documentId: obj.id,
    title: obj.payload.title,
    patches: obj.patches.length,
    bundle, // Included so caller can persist or transmit
  };
}

/** semantos diff <object-id> --from <bundle-json> */
export async function routeDiff(cmd: ShellCommand, ctx: ShellContext): Promise<unknown> {
  const objectId = cmd.objectId;
  if (!objectId) return { error: "Usage: semantos diff <object-id> --from <bundle-path>" };

  const fromPath = cmd.flags.from as string | undefined;
  if (!fromPath) return { error: "Missing --from flag with path to bundle JSON." };

  const obj = getObject(ctx, objectId);
  if (!obj) return { error: `Object not found: ${objectId}` };

  let bundleData: BundleData;
  try {
    if (ctx.adapter) {
      const bytes = await ctx.adapter.read(fromPath);
      if (!bytes) return { error: `File not found: ${fromPath}` };
      bundleData = JSON.parse(new TextDecoder().decode(bytes));
    } else {
      return { error: 'No storage adapter available for reading files.' };
    }
  } catch (e) {
    return { error: `Failed to read bundle: ${(e as Error).message}` };
  }

  const localIds = new Set(obj.patches.map(p => p.id));
  const newPatches = bundleData.patches.filter(p => !localIds.has(p.id));
  const commonCount = bundleData.patches.length - newPatches.length;

  return {
    documentId: objectId,
    localPatches: obj.patches.length,
    incomingPatches: bundleData.patches.length,
    commonPatches: commonCount,
    newPatches: newPatches.length,
    diff: newPatches.map(p => ({
      id: p.id,
      kind: p.kind,
      timestamp: new Date(p.timestamp).toISOString(),
      delta: p.delta,
      hatId: p.hatId,
    })),
  };
}

/** semantos merge <object-id> --from <bundle-path> [--cherry-pick p1,p2,...] */
export async function routeMerge(cmd: ShellCommand, ctx: ShellContext): Promise<unknown> {
  const objectId = cmd.objectId;
  if (!objectId) return { error: "Usage: semantos merge <object-id> --from <bundle-path>" };

  const fromPath = cmd.flags.from as string | undefined;
  if (!fromPath) return { error: "Missing --from flag." };

  const obj = getObject(ctx, objectId);
  if (!obj) return { error: `Object not found: ${objectId}` };

  let bundleData: BundleData;
  try {
    if (ctx.adapter) {
      const bytes = await ctx.adapter.read(fromPath);
      if (!bytes) return { error: `File not found: ${fromPath}` };
      bundleData = JSON.parse(new TextDecoder().decode(bytes));
    } else {
      return { error: 'No storage adapter available.' };
    }
  } catch (e) {
    return { error: `Failed to read bundle: ${(e as Error).message}` };
  }

  const localIds = new Set(obj.patches.map(p => p.id));
  let newPatches = bundleData.patches.filter(p => !localIds.has(p.id));

  // Cherry-pick filter
  const cherryPick = cmd.flags['cherry-pick'] as string | undefined;
  if (cherryPick) {
    const pickIds = new Set(cherryPick.split(',').map(s => s.trim()));
    newPatches = newPatches.filter(p => pickIds.has(p.id));
  }

  if (newPatches.length === 0) {
    return { merged: false, reason: 'No new patches to merge.' };
  }

  // Apply patches
  for (const patch of newPatches) {
    ctx.store.dispatch({ type: 'ADD_PATCH', objectId, patch });
  }

  // Apply payload from bundle for edited fields
  for (const patch of newPatches) {
    const field = patch.delta.field as string | undefined;
    if (field && bundleData.payload[field] !== undefined) {
      ctx.store.dispatch({
        type: 'UPDATE_PAYLOAD',
        objectId,
        field,
        value: bundleData.payload[field],
      });
    }
  }

  // Record merge provenance
  const hat = ctx.identity.getActiveHat();
  const mergePatch: ObjectPatch = {
    id: `patch-${Date.now()}-merge`,
    kind: 'evidence_merge',
    timestamp: Date.now(),
    delta: {
      action: 'merged',
      sourceExportedBy: bundleData.exportedBy,
      patchesMerged: newPatches.length,
      fromPath,
    },
    hatId: hat?.id,
  };
  ctx.store.dispatch({ type: 'ADD_PATCH', objectId, patch: mergePatch });

  return {
    merged: true,
    documentId: objectId,
    patchesMerged: newPatches.length,
    totalPatches: obj.patches.length + newPatches.length + 1,
  };
}

```
