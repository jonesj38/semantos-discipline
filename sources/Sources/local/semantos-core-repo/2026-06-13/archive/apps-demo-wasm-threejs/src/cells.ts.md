---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-demo-wasm-threejs/src/cells.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.760480+00:00
---

# archive/apps-demo-wasm-threejs/src/cells.ts

```ts
/**
 * Cube recipes — each cube is a cell with a substructural linearity class
 * plus one operation its click attempts.
 *
 * The kernel's linearity gate (see core/cell-engine/src/pda.zig sdup_enforced,
 * sdrop_enforced) decides legal vs illegal:
 *
 *   LINEAR   — no DUP, no DROP (must be consumed exactly once)
 *   AFFINE   — no DUP         (at most once; DROP ok)
 *   RELEVANT — no DROP        (at least once; DUP ok)
 *
 * This catalog covers the full 3×3 decision table plus a host-composition
 * "conductor" cube to show OP_CALLHOST driving scene effects.
 *
 * Scripts are *built at runtime* in main.ts from `(linearity, op)`, not
 * baked into this file — the recipes are declarative.
 */
import type { LinearityClass } from './cell-engine';

export type Operation = 'dup' | 'drop' | 'merge';
export type Expected = 'legal' | 'illegal';

export interface CellRecipe {
  id: string;
  label: string;
  description: string;
  linearity: LinearityClass;
  op: Operation;
  expected: Expected;
  /**
   * For `op: 'merge'` — id of the partner cube whose cell gets pushed
   * as the second arg to host.merge. The merge script becomes:
   *   pushCell(self) pushCell(partner) OP_CALLHOST "host.merge"
   */
  mergeWith?: string;
}

export const CELL_RECIPES: CellRecipe[] = [
  // ── LINEAR row ──────────────────────────────────────────────────
  {
    id: 'linear-dup',
    label: 'LINEAR · DUP',
    description: 'Duplicating a LINEAR cell is rejected — K1a.',
    linearity: 'linear',
    op: 'dup',
    expected: 'illegal',
  },
  {
    id: 'linear-drop',
    label: 'LINEAR · DROP',
    description: 'Discarding a LINEAR cell is rejected — K1b.',
    linearity: 'linear',
    op: 'drop',
    expected: 'illegal',
  },

  // ── AFFINE row ──────────────────────────────────────────────────
  {
    id: 'affine-dup',
    label: 'AFFINE · DUP',
    description: 'AFFINE still forbids duplication — cannot_duplicate_affine.',
    linearity: 'affine',
    op: 'dup',
    expected: 'illegal',
  },
  {
    id: 'affine-drop',
    label: 'AFFINE · DROP',
    description: 'AFFINE may be silently dropped — the defining legal move.',
    linearity: 'affine',
    op: 'drop',
    expected: 'legal',
  },

  // ── RELEVANT row ────────────────────────────────────────────────
  {
    id: 'relevant-dup',
    label: 'RELEVANT · DUP',
    description: 'RELEVANT may be duplicated — mitosis.',
    linearity: 'relevant',
    op: 'dup',
    expected: 'legal',
  },
  {
    id: 'relevant-drop',
    label: 'RELEVANT · DROP',
    description: 'RELEVANT must be consumed — cannot_discard_relevant.',
    linearity: 'relevant',
    op: 'drop',
    expected: 'illegal',
  },

  // ── Conductor: composes via OP_CALLHOST ─────────────────────────
  {
    id: 'conductor-merge',
    label: 'MERGE via host',
    description: 'One click pushes two cells and calls host.merge — compound story.',
    linearity: 'relevant',
    op: 'merge',
    expected: 'legal',
    mergeWith: 'relevant-dup',
  },
];

```
