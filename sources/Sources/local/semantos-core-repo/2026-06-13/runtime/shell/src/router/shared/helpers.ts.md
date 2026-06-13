---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/shared/helpers.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.381542+00:00
---

# runtime/shell/src/router/shared/helpers.ts

```ts
/**
 * Shared helpers used by every verb handler — moved out of router.ts /
 * router-browser.ts so the duplication between the two boot files
 * collapses to "which verbs to register".
 */

import type { LoomObject } from '@semantos/runtime-services';
import type { ObjectTypeDefinition } from '@semantos/protocol-types';
import type { ShellContext } from '../../types';

export function getActiveHat(ctx: ShellContext) {
  return ctx.identity.getActiveHat();
}

export function getCapabilities(ctx: ShellContext): number[] {
  return getActiveHat(ctx)?.capabilities ?? [];
}

export function findObjectTypeDef(
  ctx: ShellContext,
  typePath: string,
): ObjectTypeDefinition | null {
  const config = ctx.config.getConfig();
  if (!config) return null;

  const segments = typePath.split('.');
  const typeName = segments[segments.length - 1];

  for (const typeDef of config.objectTypes) {
    if (typeDef.name.toLowerCase() === typeName.toLowerCase()) return typeDef;
  }

  for (const typeDef of config.objectTypes) {
    const fullPath = typeDef.category
      ? `${typeDef.category}.${typeDef.name}`.toLowerCase()
      : typeDef.name.toLowerCase();
    if (fullPath === typePath.toLowerCase()) return typeDef;
  }

  return null;
}

export function getObject(ctx: ShellContext, objectId: string): LoomObject | null {
  return ctx.store.getState().objects.get(objectId) ?? null;
}

export function linearityName(n: number): string {
  switch (n) {
    case 1:
      return 'LINEAR';
    case 2:
      return 'AFFINE';
    case 3:
      return 'RELEVANT';
    case 4:
      return 'DEBUG';
    default:
      return `UNKNOWN(${n})`;
  }
}

export function serializeObject(obj: LoomObject): Record<string, unknown> {
  return {
    id: obj.id,
    type: obj.typeDefinition.name,
    typeHash: obj.typeDefinition.typeHash,
    linearity: linearityName(obj.header.linearity),
    visibility: obj.visibility,
    payload: obj.payload,
    patches: obj.patches.length,
    createdAt: new Date(obj.createdAt).toISOString(),
    updatedAt: new Date(obj.updatedAt).toISOString(),
  };
}

```
