---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/scg-relations/src/operations.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.817842+00:00
---

# core/scg-relations/src/operations.ts

```ts
/**
 * SCG relation operations — `createRelation`, `listRelationsFrom`,
 * `listRelationsTo`, `foldRelationGraph`.
 *
 * Thin wrapper over `@semantos/semantic-objects`: relations are
 * `sem_objects` rows of `objectKind='scg.relation'`. No new tables.
 *
 * Capability-port binding is deferred to RM-022 — `createRelation`
 * accepts an optional `capabilityCheck` thunk that RM-022 will plumb
 * through to `capabilityPort.check({ capability: RELATION_MINT, ... })`.
 */
import { and, eq, or, sql } from 'drizzle-orm';
import {
  createObject,
  semObjects,
  type Database,
  type ObjectRow,
} from '@semantos/semantic-objects';
import {
  RELATION_OBJECT_KIND,
  type RelationEdge,
  type RelationKind,
  type RelationPayload,
  type RelationRow,
} from './types.js';

// ────────────────────────────────────────────────────────────
// createRelation
// ────────────────────────────────────────────────────────────

export interface CreateRelationInput {
  kind: RelationKind;
  /** `sem_objects.id` of the source. */
  sourceId: string;
  /** `sem_objects.id` of the target. */
  targetId: string;
  /** Optional attestation signature. */
  attestation?: string;
  /** RM-060 — money-bearing relation fields. Required on `PAYS` /
   *  `ESCROW_LOCKS` / `ESCROW_RELEASES`; ignored on non-money kinds. */
  amount?: number;
  currency?: string;
  txAnchor?: string;
  /** Free-form per-kind extension fields. */
  extra?: Record<string, unknown>;
  /** Identity that authored the relation. */
  createdByCertId?: string;
  /** Optional capability check thunk. RM-022 wires this to
   *  `capabilityPort.check({ capability: RELATION_MINT, ... })`. Defaults
   *  to a no-op so Phase-1 tests pass without an identity binding. */
  capabilityCheck?: () => Promise<void> | void;
}

const MONEY_KINDS = new Set<RelationKind>([
  'PAYS',
  'ESCROW_LOCKS',
  'ESCROW_RELEASES',
]);

/** Create a typed relation between two `sem_objects` rows. */
export async function createRelation(
  db: Database,
  input: CreateRelationInput,
): Promise<RelationRow> {
  if (input.capabilityCheck) await input.capabilityCheck();

  // RM-060: money-bearing kinds must carry an amount + currency. Caller
  // can supply them via the new fields or via `extra.amount` for
  // back-compat with pre-RM-060 callers; the named fields take priority.
  if (MONEY_KINDS.has(input.kind)) {
    if (input.amount === undefined && input.extra?.['amount'] === undefined) {
      throw new Error(
        `createRelation: ${input.kind} requires an \`amount\` field`,
      );
    }
    if (input.currency === undefined && input.extra?.['currency'] === undefined) {
      throw new Error(
        `createRelation: ${input.kind} requires a \`currency\` field`,
      );
    }
  }

  const payload: RelationPayload = {
    kind: input.kind,
    sourceId: input.sourceId,
    targetId: input.targetId,
    ...(input.attestation !== undefined ? { attestation: input.attestation } : {}),
    ...(input.amount !== undefined ? { amount: input.amount } : {}),
    ...(input.currency !== undefined ? { currency: input.currency } : {}),
    ...(input.txAnchor !== undefined ? { txAnchor: input.txAnchor } : {}),
    ...(input.extra !== undefined ? { extra: input.extra } : {}),
  };

  return createObject<RelationPayload>(db, {
    objectKind: RELATION_OBJECT_KIND,
    payload,
    ...(input.createdByCertId !== undefined
      ? { createdByCertId: input.createdByCertId }
      : {}),
  });
}

// ────────────────────────────────────────────────────────────
// listRelationsFrom / listRelationsTo
// ────────────────────────────────────────────────────────────

export interface ListRelationsFilter {
  /** Restrict to a single kind, or a set of kinds. */
  kind?: RelationKind | ReadonlyArray<RelationKind>;
  /** Maximum rows to return. */
  limit?: number;
}

/** List relations whose `sourceId` matches. */
export async function listRelationsFrom(
  db: Database,
  sourceId: string,
  filter: ListRelationsFilter = {},
): Promise<RelationRow[]> {
  return queryRelations(db, { side: 'source', id: sourceId, filter });
}

/** List relations whose `targetId` matches. */
export async function listRelationsTo(
  db: Database,
  targetId: string,
  filter: ListRelationsFilter = {},
): Promise<RelationRow[]> {
  return queryRelations(db, { side: 'target', id: targetId, filter });
}

async function queryRelations(
  db: Database,
  q: { side: 'source' | 'target'; id: string; filter: ListRelationsFilter },
): Promise<RelationRow[]> {
  const idKey = q.side === 'source' ? 'sourceId' : 'targetId';
  const conds = [
    eq(semObjects.objectKind, RELATION_OBJECT_KIND),
    sql`${semObjects.payload}->>${idKey} = ${q.id}`,
  ];
  if (q.filter.kind !== undefined) {
    const kinds = Array.isArray(q.filter.kind) ? q.filter.kind : [q.filter.kind];
    const kindMatches = kinds.map(
      (k) => sql`${semObjects.payload}->>'kind' = ${k}`,
    );
    const kindOr = or(...kindMatches);
    if (kindOr) conds.push(kindOr);
  }

  let select = db
    .select()
    .from(semObjects)
    .where(and(...conds));
  if (q.filter.limit !== undefined) select = select.limit(q.filter.limit) as typeof select;

  const rows = await select;
  return rows.map(toRelationRow);
}

function toRelationRow(r: typeof semObjects.$inferSelect): RelationRow {
  return {
    id: r.id,
    objectKind: r.objectKind,
    parentId: r.parentId,
    payload: (r.payload ?? {}) as RelationPayload,
    createdByCertId: r.createdByCertId,
    currentStateHash: r.currentStateHash,
    currentVersion: r.currentVersion,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  };
}

// ────────────────────────────────────────────────────────────
// foldRelationGraph
// ────────────────────────────────────────────────────────────

export interface FoldRelationGraphOpts {
  /** Maximum walk depth from `rootId`. Default 3 per SCG §8.2. */
  depth?: number;
  /** Optional kind filter; restricts which edges are traversed. */
  kinds?: ReadonlyArray<RelationKind>;
  /** Direction of traversal. 'outgoing' = follow sourceId→targetId edges
   *  (default), 'incoming' = follow targetId→sourceId, 'both' = either. */
  direction?: 'outgoing' | 'incoming' | 'both';
}

export interface RelationGraph {
  /** Nodes visited during the walk, keyed by `sem_objects.id`. */
  nodes: Map<string, ObjectRow<unknown>>;
  /** Edges traversed, as denormalised views. */
  edges: RelationEdge[];
}

/**
 * Walk the relation graph from `rootId`, returning visited nodes + traversed
 * edges. BFS with depth cap. Cycles guarded by the visited-set; safe to call
 * on arbitrary graphs.
 */
export async function foldRelationGraph(
  db: Database,
  rootId: string,
  opts: FoldRelationGraphOpts = {},
): Promise<RelationGraph> {
  const maxDepth = opts.depth ?? 3;
  const direction = opts.direction ?? 'outgoing';
  const kindFilter = opts.kinds ? { kind: opts.kinds } : {};

  const nodes = new Map<string, ObjectRow<unknown>>();
  const edges: RelationEdge[] = [];
  const visited = new Set<string>();

  const rootNode = await fetchObject(db, rootId);
  if (rootNode) nodes.set(rootId, rootNode);

  let frontier: string[] = [rootId];
  visited.add(rootId);

  for (let depth = 0; depth < maxDepth && frontier.length > 0; depth++) {
    const nextFrontier: string[] = [];
    for (const nodeId of frontier) {
      const outgoing =
        direction === 'incoming'
          ? []
          : await listRelationsFrom(db, nodeId, kindFilter);
      const incoming =
        direction === 'outgoing'
          ? []
          : await listRelationsTo(db, nodeId, kindFilter);

      for (const rel of [...outgoing, ...incoming]) {
        edges.push(toRelationEdge(rel));
        const neighbourId =
          rel.payload.sourceId === nodeId ? rel.payload.targetId : rel.payload.sourceId;
        if (!visited.has(neighbourId)) {
          visited.add(neighbourId);
          nextFrontier.push(neighbourId);
          const neighbour = await fetchObject(db, neighbourId);
          if (neighbour) nodes.set(neighbourId, neighbour);
        }
      }
    }
    frontier = nextFrontier;
  }

  return { nodes, edges };
}

async function fetchObject(
  db: Database,
  id: string,
): Promise<ObjectRow<unknown> | null> {
  const rows = await db.select().from(semObjects).where(eq(semObjects.id, id)).limit(1);
  const r = rows[0];
  if (!r) return null;
  return {
    id: r.id,
    objectKind: r.objectKind,
    parentId: r.parentId,
    payload: r.payload as unknown,
    createdByCertId: r.createdByCertId,
    currentStateHash: r.currentStateHash,
    currentVersion: r.currentVersion,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  };
}

function toRelationEdge(row: RelationRow): RelationEdge {
  return {
    id: row.id,
    kind: row.payload.kind,
    sourceId: row.payload.sourceId,
    targetId: row.payload.targetId,
    createdAt: row.createdAt,
    attestation: row.payload.attestation,
  };
}

```
