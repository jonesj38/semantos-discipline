---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/persona.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.083385+00:00
---

# apps/loom-svelte/src/lib/persona.ts

```ts
/**
 * persona.ts — local projection types and projectPersona() for the shell.
 *
 * Types are mirrored from:
 *   core/conversation-graph/src/rendering.ts  (PersonaIdentity, PersonaFace, etc.)
 *   core/scg-relations/src/types.ts           (RelationKind, RelationEdge)
 *
 * We inline instead of aliasing the workspace packages because the full
 * index exports of those packages pull in drizzle-orm / node-only deps that
 * can't be bundled for the browser.  rendering.ts is a pure computation
 * module; this file is a browser-safe copy of exactly what the shell needs.
 *
 * Keep in sync with core/conversation-graph/src/rendering.ts on projectPersona
 * signature changes.
 */

// ── Relation kinds (subset from scg-relations/src/types.ts) ──────────────────

export type RelationKind =
  | 'REPLIES_TO'
  | 'CITES'
  | 'SUPPORTS'
  | 'DISPUTES'
  | 'SUPERSEDES'
  | 'FORKS'
  | 'MERGES'
  | 'SUBSCRIBES_TO'
  | 'REQUESTS_ACTION'
  | 'FULFILLS'
  | 'PAYS'
  | 'ATTESTS'
  | 'GRANTS_ACCESS'
  | 'APPROVES'
  | 'ESCROW_LOCKS'
  | 'ESCROW_RELEASES';

export interface RelationEdge {
  readonly kind: RelationKind;
  readonly sourceId: string;
  readonly targetId: string;
  readonly createdAt: Date;
}

// ── Node / stream types (from rendering.ts) ───────────────────────────────────

export interface RenderableNode {
  readonly id: string;
  readonly createdAt: Date;
  readonly payload: unknown;
  readonly authorCertId?: string;
  readonly conversationId?: string;
}

export interface ThreadNode {
  readonly node: RenderableNode;
  readonly hopsFromRoot: number;
  readonly children: ReadonlyArray<ThreadNode>;
}

export interface StreamItem {
  readonly node: RenderableNode;
  readonly conversationId: string;
  readonly streamIndex: number;
  readonly authorChange: boolean;
}

// ── Persona types (from rendering.ts) ────────────────────────────────────────

export interface PersonaIdentity {
  readonly certId: string;
  readonly displayName?: string;
  readonly email?: string;
  readonly publicKey?: string;
  readonly nodeType?: string;
}

export interface PersonaEdgeView {
  readonly edgeType: string;
  readonly counterpartyCertId: string;
  readonly counterpartyDisplayName?: string;
  readonly appId?: string;
  readonly revoked: boolean;
}

export interface PersonaGroup {
  readonly groupId: string;
  readonly subscribedAt: Date;
}

export type PersonaFace = 'social' | 'topical' | 'commercial';

export interface PersonaFaceFilter {
  readonly social: ReadonlyArray<RelationKind>;
  readonly topical: ReadonlyArray<RelationKind>;
  readonly commercial: ReadonlyArray<RelationKind>;
}

export const DEFAULT_PERSONA_FACE_FILTER: PersonaFaceFilter = {
  social: ['REPLIES_TO'],
  topical: ['REPLIES_TO', 'CITES', 'SUPPORTS', 'DISPUTES', 'SUPERSEDES', 'FORKS', 'MERGES'],
  commercial: [
    'REQUESTS_ACTION', 'FULFILLS', 'PAYS', 'ATTESTS',
    'GRANTS_ACCESS', 'APPROVES', 'ESCROW_LOCKS', 'ESCROW_RELEASES',
  ],
};

export interface ProjectPersonaInput {
  readonly identity: PersonaIdentity;
  readonly viewerHat: PersonaFace;
  readonly nodes: ReadonlyArray<RenderableNode>;
  readonly edges: ReadonlyArray<RelationEdge>;
  readonly contactEdges?: ReadonlyArray<PersonaEdgeView>;
  readonly faceFilter?: Partial<PersonaFaceFilter>;
}

export interface PersonaProjection {
  readonly identity: PersonaIdentity;
  readonly viewerHat: PersonaFace;
  readonly social: ReadonlyArray<StreamItem>;
  readonly topical: ReadonlyArray<ThreadNode>;
  readonly commercial: ReadonlyArray<RelationEdge>;
  readonly groups: ReadonlyArray<PersonaGroup>;
  readonly edges: ReadonlyArray<PersonaEdgeView>;
}

// ── projectStream helper (used by projectPersona) ─────────────────────────────

function projectStream(input: {
  nodes: ReadonlyArray<RenderableNode>;
  groupByConversation?: boolean;
}): ReadonlyArray<StreamItem> {
  const groupBy = input.groupByConversation ?? true;
  const sorted = [...input.nodes].sort(
    (a, b) => a.createdAt.getTime() - b.createdAt.getTime(),
  );
  if (!groupBy) {
    let lastAuthor: string | undefined;
    return sorted.map((node, i) => {
      const authorChange = node.authorCertId !== lastAuthor;
      lastAuthor = node.authorCertId;
      return { node, conversationId: node.conversationId ?? '__ungrouped__', streamIndex: i, authorChange };
    });
  }
  const perConv = new Map<string, { idx: number; lastAuthor?: string }>();
  const out: StreamItem[] = [];
  for (const node of sorted) {
    const conv = node.conversationId ?? '__ungrouped__';
    const state = perConv.get(conv) ?? { idx: 0 };
    const authorChange = node.authorCertId !== state.lastAuthor;
    out.push({ node, conversationId: conv, streamIndex: state.idx, authorChange });
    state.idx += 1;
    state.lastAuthor = node.authorCertId;
    perConv.set(conv, state);
  }
  return out;
}

// ── projectPersona (copied verbatim from core/conversation-graph/src/rendering.ts) ──

export function projectPersona(input: ProjectPersonaInput): PersonaProjection {
  const filter: PersonaFaceFilter = {
    ...DEFAULT_PERSONA_FACE_FILTER,
    ...input.faceFilter,
  };
  const ownedIds = new Set(input.nodes.map((n) => n.id));

  // groups: SUBSCRIBES_TO edges sourced from owned cells.
  const groups: PersonaGroup[] = [];
  const seenGroupTargets = new Set<string>();
  for (const e of input.edges) {
    if (e.kind !== 'SUBSCRIBES_TO') continue;
    if (!ownedIds.has(e.sourceId)) continue;
    if (seenGroupTargets.has(e.targetId)) continue;
    seenGroupTargets.add(e.targetId);
    groups.push({ groupId: e.targetId, subscribedAt: e.createdAt });
  }

  // social: authored-cell stream (chronological).
  const social = projectStream({ nodes: input.nodes, groupByConversation: false });

  // topical: threads rooted at each owned cell.
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
    children.sort((a, b) => a.node.createdAt.getTime() - b.node.createdAt.getTime());
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

  // commercial: party-to relations under commercial kinds.
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
