---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/conversation-graph/src/rendering.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.006514+00:00
---

# core/conversation-graph/src/rendering.ts

```ts
/**
 * Conversation-graph rendering helpers — RM-051 (thread projection) +
 * RM-052 (stream projection).
 *
 * Renderers consume a `RetrievedContext` (or a raw set of conversation
 * cells + REPLIES_TO edges) and project it into the two canonical
 * surface shapes Wave-5 apps need:
 *
 *   - **thread**: nested ancestor/descendant tree rooted at a turn the
 *     caller cares about (Reddit-style, Hacker News–style).
 *   - **stream**: flat chronological list, optionally grouped by
 *     conversation aggregate (Slack / Discord / chat-style).
 *
 * These helpers don't render HTML / Markdown / JSX — they produce typed
 * intermediate structures the host UI consumes. The substrate's job is
 * the shape; pixel rendering is the consumer's job.
 *
 * Why this is in `conversation-graph` rather than each app: the
 * canonical "thread tree" + "stream list" shapes are reused across
 * every conversational extension. Splitting one tested implementation
 * out of N copies in N apps is the whole point of the substrate.
 */
import type { RelationEdge, RelationKind } from '@semantos/scg-relations';

// ─── Inputs ──────────────────────────────────────────────────────────

/** Minimal node shape the renderers operate on. Compatible with
 *  `RetrievedContextNode` but doesn't require it — callers can pass any
 *  `(id, createdAt, payload)` tuple. */
export interface RenderableNode {
  readonly id: string;
  readonly createdAt: Date;
  readonly payload: unknown;
  /** Optional — surfaces in `ThreadNode` / `StreamItem` unchanged. */
  readonly authorCertId?: string;
  /** Optional — used to group `stream` items. */
  readonly conversationId?: string;
}

// ─── RM-051: thread projection ────────────────────────────────────────

export interface ThreadNode {
  readonly node: RenderableNode;
  readonly hopsFromRoot: number;
  readonly children: ReadonlyArray<ThreadNode>;
}

export interface ProjectThreadInput {
  readonly rootId: string;
  readonly nodes: ReadonlyArray<RenderableNode>;
  /** Edges treated as reply links. Defaults to `kind === 'REPLIES_TO'`. */
  readonly edges: ReadonlyArray<RelationEdge>;
}

/**
 * Project a set of nodes + REPLIES_TO edges into a nested thread tree
 * rooted at `rootId`. Children are sorted by `createdAt` ascending so
 * the rendered thread reads chronologically.
 *
 * Cycles (which shouldn't occur in REPLIES_TO but might under malicious
 * input) are guarded by a visited-set; cyclic nodes are dropped at
 * second visit.
 */
export function projectThread(input: ProjectThreadInput): ThreadNode | null {
  const byId = new Map(input.nodes.map((n) => [n.id, n]));
  const root = byId.get(input.rootId);
  if (!root) return null;

  // Reply edges treat sourceId as the reply and targetId as the parent.
  const childrenOf = new Map<string, string[]>();
  for (const e of input.edges) {
    if (e.kind !== 'REPLIES_TO') continue;
    if (!childrenOf.has(e.targetId)) childrenOf.set(e.targetId, []);
    childrenOf.get(e.targetId)!.push(e.sourceId);
  }

  const visited = new Set<string>();
  const build = (id: string, hops: number): ThreadNode | null => {
    if (visited.has(id)) return null;
    visited.add(id);
    const node = byId.get(id);
    if (!node) return null;
    const childIds = childrenOf.get(id) ?? [];
    const children: ThreadNode[] = [];
    for (const cid of childIds) {
      const built = build(cid, hops + 1);
      if (built) children.push(built);
    }
    children.sort((a, b) => a.node.createdAt.getTime() - b.node.createdAt.getTime());
    return { node, hopsFromRoot: hops, children };
  };

  return build(input.rootId, 0);
}

// ─── RM-052: stream projection ────────────────────────────────────────

export interface StreamItem {
  readonly node: RenderableNode;
  /** Conversation aggregate this item belongs to. Falls back to the
   *  `node.conversationId` value when present, else `'__ungrouped__'`. */
  readonly conversationId: string;
  /** Position within the grouped stream (chronological, ascending). */
  readonly streamIndex: number;
  /** Set when the previous item in this conversation was authored by a
   *  different cert — useful for rendering author avatars + names only
   *  at conversation pivots. */
  readonly authorChange: boolean;
}

export interface ProjectStreamInput {
  readonly nodes: ReadonlyArray<RenderableNode>;
  /** When true, items are grouped by `conversationId` and indexed
   *  per-conversation. When false, all items share a single ascending
   *  index regardless of conversation. Defaults to true. */
  readonly groupByConversation?: boolean;
}

/**
 * Project a set of conversation nodes into a flat chronological stream.
 * The output is sorted by `createdAt` ascending; when
 * `groupByConversation=true`, each conversation's items get a fresh
 * `streamIndex` starting at 0 (so a renderer can chunk them by
 * conversation without re-sorting).
 */
export function projectStream(input: ProjectStreamInput): ReadonlyArray<StreamItem> {
  const groupBy = input.groupByConversation ?? true;
  const sorted = [...input.nodes].sort(
    (a, b) => a.createdAt.getTime() - b.createdAt.getTime(),
  );

  if (!groupBy) {
    let lastAuthor: string | undefined;
    return sorted.map((node, i) => {
      const authorChange = node.authorCertId !== lastAuthor;
      lastAuthor = node.authorCertId;
      return {
        node,
        conversationId: node.conversationId ?? '__ungrouped__',
        streamIndex: i,
        authorChange,
      };
    });
  }

  const perConv = new Map<string, { idx: number; lastAuthor?: string }>();
  const out: StreamItem[] = [];
  for (const node of sorted) {
    const conv = node.conversationId ?? '__ungrouped__';
    const state = perConv.get(conv) ?? { idx: 0 };
    const authorChange = node.authorCertId !== state.lastAuthor;
    out.push({
      node,
      conversationId: conv,
      streamIndex: state.idx,
      authorChange,
    });
    state.idx += 1;
    state.lastAuthor = node.authorCertId;
    perConv.set(conv, state);
  }
  return out;
}

// ─── D-SCG-persona-projection: handle/persona projection ──────────────

/**
 * Minimal identity shape the persona projector operates on. A subset of
 * `core/contact-book`'s `Contact` (certId + a few human-readable fields)
 * so this module stays free of a runtime dep on contact-book. Callers
 * resolve the Contact and pass the relevant fields.
 */
export interface PersonaIdentity {
  readonly certId: string;
  readonly displayName?: string;
  readonly email?: string;
  readonly publicKey?: string;
  readonly nodeType?: string;
}

/**
 * Flattened view of a contact-book `EdgeRecord` for the persona surface.
 * Same dependency-narrowing motivation as `PersonaIdentity` — callers
 * project from `EdgeRecord` and pass the result in.
 */
export interface PersonaEdgeView {
  readonly edgeType: string;
  readonly counterpartyCertId: string;
  readonly counterpartyDisplayName?: string;
  readonly appId?: string;
  readonly revoked: boolean;
}

/** Pub-sub group membership derived from `SUBSCRIBES_TO` edges. */
export interface PersonaGroup {
  /** `sem_objects.id` of the type-path group cell. */
  readonly groupId: string;
  /** When the SUBSCRIBES_TO edge was minted. */
  readonly subscribedAt: Date;
}

/**
 * Which face of the persona the caller wants foregrounded. The
 * projection still returns all three faces — the hat is metadata so the
 * consumer renderer knows which to highlight.
 *
 * Stranger → commercial. Peer → topical. Friend → social. Hat selection
 * is the consumer's job; this primitive just carries it through.
 */
export type PersonaFace = 'social' | 'topical' | 'commercial';

/** Relation-kind filter that defines each face. Overrideable. */
export interface PersonaFaceFilter {
  readonly social: ReadonlyArray<RelationKind>;
  readonly topical: ReadonlyArray<RelationKind>;
  readonly commercial: ReadonlyArray<RelationKind>;
}

export const DEFAULT_PERSONA_FACE_FILTER: PersonaFaceFilter = {
  social: ['REPLIES_TO'],
  topical: [
    'REPLIES_TO',
    'CITES',
    'SUPPORTS',
    'DISPUTES',
    'SUPERSEDES',
    'FORKS',
    'MERGES',
  ],
  commercial: [
    'REQUESTS_ACTION',
    'FULFILLS',
    'PAYS',
    'ATTESTS',
    'GRANTS_ACCESS',
    'APPROVES',
    'ESCROW_LOCKS',
    'ESCROW_RELEASES',
  ],
};

export interface ProjectPersonaInput {
  readonly identity: PersonaIdentity;
  readonly viewerHat: PersonaFace;
  /**
   * Cells "owned by" this persona — typically authored-by or
   * canonical identity-card cells. The caller does this filter; the
   * projector trusts the set. SUBSCRIBES_TO edges with `sourceId` in
   * this set become `groups[]`; other edges form face content.
   */
  readonly nodes: ReadonlyArray<RenderableNode>;
  /** All relations touching the persona (either endpoint). */
  readonly edges: ReadonlyArray<RelationEdge>;
  /** Contact-book edges (MESSAGING / ATTESTATION / etc.). */
  readonly contactEdges?: ReadonlyArray<PersonaEdgeView>;
  /** Override the default kind→face mapping. */
  readonly faceFilter?: Partial<PersonaFaceFilter>;
}

export interface PersonaProjection {
  readonly identity: PersonaIdentity;
  readonly viewerHat: PersonaFace;
  /** Stream of authored cells (social face is the chronological self). */
  readonly social: ReadonlyArray<StreamItem>;
  /** Thread roots the persona participated in (topical face). */
  readonly topical: ReadonlyArray<ThreadNode>;
  /** Commercial-face relations the persona is party to. */
  readonly commercial: ReadonlyArray<RelationEdge>;
  /** Pub-sub group memberships (folded from SUBSCRIBES_TO edges). */
  readonly groups: ReadonlyArray<PersonaGroup>;
  /** Identity edges from contact-book (MESSAGING / ATTESTATION / ...). */
  readonly edges: ReadonlyArray<PersonaEdgeView>;
}

/**
 * Project a persona — the federated, user-owned identity surface that
 * subsumes the Reddit-`/u/`-page / Facebook-profile / Google-business-
 * profile family. The substrate-side primitive: returns typed
 * structures, never HTML.
 *
 * Three faces fall out of one fold over the relation graph:
 *
 *   - **social**: chronological stream of authored cells.
 *   - **topical**: threads rooted at the persona's contributions, built
 *     from `REPLIES_TO`/`CITES`/`SUPPORTS`/etc. edges.
 *   - **commercial**: party-to relations under money/access/attestation
 *     kinds — the persona's business face.
 *
 * Pub-sub group membership (`SUBSCRIBES_TO` edges from persona cells)
 * folds into `groups[]` regardless of face. Identity edges from
 * contact-book (`MESSAGING`/`ATTESTATION`/…) pass through unchanged.
 *
 * `viewerHat` echoes through the projection so consumer renderers can
 * pick which face to foreground; the projector itself doesn't reduce
 * by hat (cheap to compute all three; consumer chooses).
 *
 * Discovery / aggregation consumers (bsvradar-shaped directories) call
 * this once per handle and render each row from the typed result. The
 * Reddit-thread and Discourse-stream demo apps fall out as filters
 * over `topical` and `social` respectively.
 */
export function projectPersona(input: ProjectPersonaInput): PersonaProjection {
  const filter: PersonaFaceFilter = {
    ...DEFAULT_PERSONA_FACE_FILTER,
    ...input.faceFilter,
  };
  const ownedIds = new Set(input.nodes.map((n) => n.id));

  // ── groups: SUBSCRIBES_TO edges sourced from owned cells. ────────
  const groups: PersonaGroup[] = [];
  const seenGroupTargets = new Set<string>();
  for (const e of input.edges) {
    if (e.kind !== 'SUBSCRIBES_TO') continue;
    if (!ownedIds.has(e.sourceId)) continue;
    if (seenGroupTargets.has(e.targetId)) continue;
    seenGroupTargets.add(e.targetId);
    groups.push({ groupId: e.targetId, subscribedAt: e.createdAt });
  }

  // ── social: authored-cell stream (chronological). ─────────────────
  const social = projectStream({ nodes: input.nodes, groupByConversation: false });

  // ── topical: threads rooted at each owned cell, walking ──────────
  // descendants via the topical relation-kind subset. We build one
  // tree per owned root that has children under the filter, then
  // sort by root.createdAt so callers can render in a stable order.
  const topicalKinds = new Set<RelationKind>(filter.topical);
  const topicalEdges = input.edges.filter((e) => topicalKinds.has(e.kind));
  const topicalChildrenOf = new Map<string, string[]>();
  for (const e of topicalEdges) {
    if (!topicalChildrenOf.has(e.targetId)) topicalChildrenOf.set(e.targetId, []);
    topicalChildrenOf.get(e.targetId)!.push(e.sourceId);
  }
  const allNodesById = new Map(input.nodes.map((n) => [n.id, n]));
  const visited = new Set<string>();
  const buildTopical = (id: string, hops: number): ThreadNode | null => {
    if (visited.has(id)) return null;
    visited.add(id);
    const node = allNodesById.get(id);
    if (!node) return null;
    const childIds = topicalChildrenOf.get(id) ?? [];
    const children: ThreadNode[] = [];
    for (const cid of childIds) {
      const built = buildTopical(cid, hops + 1);
      if (built) children.push(built);
    }
    children.sort(
      (a, b) => a.node.createdAt.getTime() - b.node.createdAt.getTime(),
    );
    return { node, hopsFromRoot: hops, children };
  };
  const topical: ThreadNode[] = [];
  const ownedSorted = [...input.nodes].sort(
    (a, b) => a.createdAt.getTime() - b.createdAt.getTime(),
  );
  for (const root of ownedSorted) {
    const tree = buildTopical(root.id, 0);
    if (tree && tree.children.length > 0) topical.push(tree);
  }

  // ── commercial: party-to relations under commercial kinds. ───────
  const commercialKinds = new Set<RelationKind>(filter.commercial);
  const commercial = input.edges.filter(
    (e) =>
      commercialKinds.has(e.kind) &&
      (ownedIds.has(e.sourceId) || ownedIds.has(e.targetId)),
  );

  return {
    identity: input.identity,
    viewerHat: input.viewerHat,
    social,
    topical,
    commercial,
    groups,
    edges: input.contactEdges ?? [],
  };
}

```
