---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-handlers/list.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.384010+00:00
---

# runtime/shell/src/router/verb-handlers/list.ts

```ts
/**
 * `list` — read-only enumeration of objects with optional --type and
 * --status filters.
 */

import type { ShellCommand } from '../../parser';
import type { ShellContext } from '../../types';
import type { VerbHandler } from '../types';

const listHandler: VerbHandler = async (cmd: ShellCommand, ctx: ShellContext) => {
  const state = ctx.store.getState();
  const objects = [...state.objects.values()];

  let filtered = objects;

  const typeFilter = cmd.flags.type;
  if (typeof typeFilter === 'string') {
    filtered = filtered.filter((obj) => {
      const name = obj.typeDefinition.name.toLowerCase();
      const category = obj.typeDefinition.category?.toLowerCase() ?? '';
      const fullPath = category ? `${category}.${name}` : name;
      return name.includes(typeFilter.toLowerCase()) || fullPath.includes(typeFilter.toLowerCase());
    });
  }

  const statusFilter = cmd.flags.status;
  if (typeof statusFilter === 'string') {
    if (['draft', 'published', 'revoked'].includes(statusFilter)) {
      filtered = filtered.filter((obj) => obj.visibility === statusFilter);
    }
  }

  return filtered.map((obj) => ({
    id: obj.id,
    type: obj.typeDefinition.name,
    visibility: obj.visibility,
    owner: obj.patches.find((p) => p.hatId)?.hatId ?? 'unknown',
    patches: obj.patches.length,
  }));
};

export const listHandlers = { list: listHandler };

```
