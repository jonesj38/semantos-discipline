---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/shell/verb-intent.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.085869+00:00
---

# apps/loom-svelte/src/shell/verb-intent.ts

```ts
/**
 * verb-intent.ts — SH2-H (svelte-helm matrix; DECISION D14).
 *
 * A cartridge verb's `intentType` is a dotted triple
 * `<cartridgeId>.<entity>.<action>` (e.g. "oddjobz.job.create",
 * "oddjobz.customer.find"). Under D14 a verb does not mint a cell — it
 * NAVIGATES into the active cartridge's surface at the relevant flow. This
 * pure parser splits the intentType so App.handleDockInvoke can route to the
 * cartridge surface + pass the entity as an entry hint. Returns null for
 * anything that isn't a cartridge verb triple (e.g. view:* commands), so the
 * caller can fall through.
 */

export interface VerbIntent {
  cartridgeId: string;
  entity: string;
  action: string;
}

export function parseVerbIntent(intentType: string | null | undefined): VerbIntent | null {
  if (!intentType) return null;
  // Reject view:* and other non-dotted commands fast.
  if (intentType.includes(':')) return null;
  const parts = intentType.split('.');
  if (parts.length < 3) return null;
  const [cartridgeId, entity, ...rest] = parts;
  if (!cartridgeId || !entity) return null;
  return { cartridgeId, entity, action: rest.join('.') };
}

```
