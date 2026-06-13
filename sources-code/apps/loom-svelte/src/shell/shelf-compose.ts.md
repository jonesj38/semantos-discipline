---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/shell/shelf-compose.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.085300+00:00
---

# apps/loom-svelte/src/shell/shelf-compose.ts

```ts
/**
 * shelf-compose.ts — SH2-B (svelte-helm matrix; DECISION D11).
 *
 * Composes the DO|TALK|FIND verb shelf for a modal from two layers:
 *
 *   1. DEFAULT — the kernel CSD 1-3-5-3-1 pyramid: the 5 contexts under
 *      the modal (DO_CONTEXTS / TALK_CONTEXTS / FIND_CONTEXTS). Always the
 *      shell baseline; an operator with no active cartridge sees only this.
 *   2. OVERLAY — the ACTIVE cartridge's ui.verbs[] for this modal (from the
 *      ManifestStore / extensions-api). A cartridge MAY keep the default
 *      (declare no verbs) or overlay its own per modal.
 *
 * Pure (no I/O, no Svelte) so the composition is unit-testable without a
 * live brain or a rendered Dock. Hat-gating (operator vs admin) is a
 * SEPARATE filter applied to the overlay verbs — see SH14 / filterByHat.
 */

import type { UiVerb, HatRole } from '../lib/extensions-api';
import {
  DO_CONTEXTS,
  TALK_CONTEXTS,
  FIND_CONTEXTS,
  type IntentId,
  type ContextDef,
} from './context-weights';

/**
 * SH14-B / D12 — hat-gate the overlay verbs. An operator hat sees only
 * operator-role verbs (the base set); an admin hat sees operator + admin
 * (the managerial verbs too). A verb with no role counts as "operator"
 * (fail-safe — already coerced by normalizeVerb, belt-and-suspenders here).
 */
export function filterVerbsByHatRole(verbs: UiVerb[], hatRole: HatRole): UiVerb[] {
  if (hatRole === 'admin') return verbs; // admin sees everything
  return verbs.filter((v) => (v.role ?? 'operator') !== 'admin');
}

/** The kernel pyramid contexts for a modal (the default tier-2 surface). */
export function contextsForModal(modal: IntentId): ContextDef<string>[] {
  switch (modal) {
    case 'do':
      return DO_CONTEXTS;
    case 'talk':
      return TALK_CONTEXTS;
    case 'find':
      return FIND_CONTEXTS;
  }
}

/** A composed shelf for one modal: kernel contexts + cartridge overlay verbs. */
export interface ShelfModal {
  modal: IntentId;
  /** Kernel CSD-pyramid contexts — the default shell surface. */
  contexts: ContextDef<string>[];
  /** Active-cartridge overlay verbs for this modal (direct-dispatch tiles). */
  cartridgeVerbs: UiVerb[];
}

/**
 * Compose the shelf for a single modal. `activeVerbs` is the active
 * cartridge's full ui.verbs[] (any modal); we keep only this modal's. When
 * no cartridge is active (or it declares no verbs for this modal),
 * cartridgeVerbs is empty and the shelf is the pure kernel default.
 */
export function composeShelfModal(
  modal: IntentId,
  activeVerbs: UiVerb[] | undefined | null,
): ShelfModal {
  const cartridgeVerbs = (activeVerbs ?? []).filter((v) => v.modal === modal);
  return { modal, contexts: contextsForModal(modal), cartridgeVerbs };
}

/** Compose all three modals at once. */
export function composeShelf(activeVerbs: UiVerb[] | undefined | null): Record<IntentId, ShelfModal> {
  return {
    do: composeShelfModal('do', activeVerbs),
    talk: composeShelfModal('talk', activeVerbs),
    find: composeShelfModal('find', activeVerbs),
  };
}

```
