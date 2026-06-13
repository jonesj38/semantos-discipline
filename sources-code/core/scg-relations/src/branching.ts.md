---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/scg-relations/src/branching.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.818125+00:00
---

# core/scg-relations/src/branching.ts

```ts
/**
 * Branching operations — RM-080.
 *
 * `forkSubgraph` and `mergeSubgraph` are graph-shape operations
 * layered on the existing relation primitives (RM-010). A FORK creates
 * an explicit branch point: a new conversation-cell parented at the
 * fork target, with a `FORKS` relation back to the original. A MERGE
 * records that two branches reconverge: a new cell with `MERGES`
 * relations to each parent branch.
 *
 * Conflict detection: `mergeSubgraph` compares the `currentStateHash`
 * of each parent. When they diverge from a known common ancestor
 * (three-way comparison), the merge is annotated with `conflicts: true`
 * in its payload's `extra` slot. The caller decides whether to refuse
 * the merge or accept the divergence.
 */
import { createObject, type Database } from '@semantos/semantic-objects';
import { createRelation } from './operations.js';
import type { RelationRow } from './types.js';

export interface ForkSubgraphInput {
  /** The cell to fork from. The new branch is parented at this point. */
  forkPointId: string;
  /** Object-kind for the new branch cell. Mirrors the kind of the
   *  original (e.g. `'scg.cell'`). */
  branchObjectKind: string;
  /** Optional payload for the new branch cell. */
  branchPayload?: Record<string, unknown>;
  /** Identity authoring the fork. */
  createdByCertId?: string;
}

export interface ForkResult {
  /** The new branch cell. */
  branchId: string;
  /** The FORKS relation row pointing from `branchId` to `forkPointId`. */
  forkRelation: RelationRow;
}

/**
 * Fork a subgraph at `forkPointId`. Creates a new cell + a FORKS
 * relation from the new cell back to the fork point.
 */
export async function forkSubgraph(
  db: Database,
  input: ForkSubgraphInput,
): Promise<ForkResult> {
  const branch = await createObject(db, {
    objectKind: input.branchObjectKind,
    payload: input.branchPayload ?? {},
    ...(input.createdByCertId !== undefined
      ? { createdByCertId: input.createdByCertId }
      : {}),
  });
  const forkRelation = await createRelation(db, {
    kind: 'FORKS',
    sourceId: branch.id,
    targetId: input.forkPointId,
    ...(input.createdByCertId !== undefined
      ? { createdByCertId: input.createdByCertId }
      : {}),
  });
  return { branchId: branch.id, forkRelation };
}

export interface MergeSubgraphInput {
  /** The branch heads being merged. At least two; ordering is the
   *  caller's convention (e.g. `[mainline, feature]`). */
  parentBranchIds: ReadonlyArray<string>;
  /** Object-kind for the new merge cell. */
  mergeObjectKind: string;
  /** Optional payload. The merge primitive will set
   *  `payload.extra.conflicts` when the parents have divergent
   *  `currentStateHash` values. */
  mergePayload?: Record<string, unknown>;
  /** Identity authoring the merge. */
  createdByCertId?: string;
}

export interface MergeResult {
  /** The new merge cell. */
  mergeId: string;
  /** One MERGES relation per parent branch, in input order. */
  mergeRelations: ReadonlyArray<RelationRow>;
  /** True iff at least two parents have non-equal `currentStateHash`
   *  values (a real divergence). False when all parents share a hash
   *  (a trivial / fast-forward merge). */
  conflicts: boolean;
}

/**
 * Merge two or more branches. Creates a new cell + one MERGES relation
 * per parent. Conflict-detection compares the parents' state hashes.
 *
 * Throws if `parentBranchIds.length < 2` or if any parent doesn't exist.
 */
export async function mergeSubgraph(
  db: Database,
  input: MergeSubgraphInput,
): Promise<MergeResult> {
  if (input.parentBranchIds.length < 2) {
    throw new Error(
      `mergeSubgraph: need at least two parent branches, got ${input.parentBranchIds.length}`,
    );
  }

  // Three-way comparison via state hashes. Parents share a hash → no
  // conflict (fast-forward). Parents diverge → conflicts=true and
  // recorded in the merge cell's payload for downstream resolution.
  const parents = await Promise.all(
    input.parentBranchIds.map((id) => fetchObject(db, id)),
  );
  parents.forEach((p, i) => {
    if (!p) {
      throw new Error(
        `mergeSubgraph: parent ${input.parentBranchIds[i]} not found`,
      );
    }
  });
  const stateHashes = parents
    .map((p) => p!.currentStateHash)
    .filter((h): h is string => h !== null);
  const distinctHashes = new Set(stateHashes);
  const conflicts = distinctHashes.size > 1;

  const payload = {
    ...(input.mergePayload ?? {}),
    ...(conflicts
      ? {
          extra: {
            ...((input.mergePayload?.extra as Record<string, unknown>) ?? {}),
            conflicts: true,
            parentStateHashes: Array.from(distinctHashes),
          },
        }
      : {}),
  };
  const merge = await createObject(db, {
    objectKind: input.mergeObjectKind,
    payload,
    ...(input.createdByCertId !== undefined
      ? { createdByCertId: input.createdByCertId }
      : {}),
  });

  const mergeRelations: RelationRow[] = [];
  for (const parentId of input.parentBranchIds) {
    const rel = await createRelation(db, {
      kind: 'MERGES',
      sourceId: merge.id,
      targetId: parentId,
      ...(input.createdByCertId !== undefined
        ? { createdByCertId: input.createdByCertId }
        : {}),
    });
    mergeRelations.push(rel);
  }
  return { mergeId: merge.id, mergeRelations, conflicts };
}

// Minimal local fetcher to keep this module decoupled from operations.ts's
// internal `fetchObject` helper. Reads only the columns we need.
import { semObjects } from '@semantos/semantic-objects';
import { eq } from 'drizzle-orm';

async function fetchObject(db: Database, id: string) {
  const rows = await db.select().from(semObjects).where(eq(semObjects.id, id)).limit(1);
  return rows[0] ?? null;
}

```
