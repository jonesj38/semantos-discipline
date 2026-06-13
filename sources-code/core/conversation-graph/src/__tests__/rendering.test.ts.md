---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/conversation-graph/src/__tests__/rendering.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.008380+00:00
---

# core/conversation-graph/src/__tests__/rendering.test.ts

```ts
/**
 * RM-051 (thread) + RM-052 (stream) rendering helpers.
 *
 * Pure-functional projection tests — no DB. The renderers only need
 * `(id, createdAt, payload)` tuples + a flat edge list, so we hand-roll
 * fixtures here for fast determinism.
 */
import { describe, expect, test } from 'bun:test';
import type { RelationEdge } from '@semantos/scg-relations';
import {
  projectStream,
  projectThread,
  type RenderableNode,
} from '../rendering.js';

function n(
  id: string,
  ms: number,
  extras: Partial<RenderableNode> = {},
): RenderableNode {
  return { id, createdAt: new Date(ms), payload: { body: id }, ...extras };
}

function reply(id: string, sourceId: string, targetId: string): RelationEdge {
  return {
    id,
    kind: 'REPLIES_TO',
    sourceId,
    targetId,
    createdAt: new Date(),
  };
}

describe('projectThread (RM-051)', () => {
  test('T1 builds a nested tree with children sorted by createdAt', () => {
    const tree = projectThread({
      rootId: 'root',
      nodes: [
        n('root', 100),
        n('a', 200),
        n('b', 300),
        n('c', 400),
      ],
      edges: [reply('e1', 'b', 'root'), reply('e2', 'a', 'root'), reply('e3', 'c', 'a')],
    });
    expect(tree).not.toBeNull();
    expect(tree!.node.id).toBe('root');
    expect(tree!.hopsFromRoot).toBe(0);
    expect(tree!.children.map((c) => c.node.id)).toEqual(['a', 'b']);
    expect(tree!.children[0]!.hopsFromRoot).toBe(1);
    expect(tree!.children[0]!.children[0]!.node.id).toBe('c');
    expect(tree!.children[0]!.children[0]!.hopsFromRoot).toBe(2);
  });

  test('T2 returns null when rootId is not in the node set', () => {
    expect(
      projectThread({ rootId: 'missing', nodes: [n('a', 1)], edges: [] }),
    ).toBeNull();
  });

  test('T3 ignores non-REPLIES_TO edges', () => {
    const tree = projectThread({
      rootId: 'root',
      nodes: [n('root', 1), n('a', 2)],
      edges: [{ id: 'x', kind: 'CITES', sourceId: 'a', targetId: 'root', createdAt: new Date() }],
    });
    expect(tree!.children).toEqual([]);
  });

  test('T4 cycles are dropped on second visit', () => {
    const tree = projectThread({
      rootId: 'a',
      nodes: [n('a', 1), n('b', 2)],
      edges: [reply('e1', 'b', 'a'), reply('e2', 'a', 'b')],
    });
    expect(tree!.node.id).toBe('a');
    expect(tree!.children.map((c) => c.node.id)).toEqual(['b']);
    expect(tree!.children[0]!.children).toEqual([]);
  });
});

describe('projectStream (RM-052)', () => {
  test('S1 default groups by conversationId; each gets its own streamIndex', () => {
    const items = projectStream({
      nodes: [
        n('a', 100, { conversationId: 'conv1' }),
        n('b', 200, { conversationId: 'conv1' }),
        n('c', 150, { conversationId: 'conv2' }),
      ],
    });
    const byId = Object.fromEntries(items.map((i) => [i.node.id, i]));
    expect(byId.a!.streamIndex).toBe(0);
    expect(byId.b!.streamIndex).toBe(1);
    expect(byId.c!.streamIndex).toBe(0);
  });

  test('S2 ordered chronologically within and across conversations', () => {
    const items = projectStream({
      nodes: [
        n('late', 300),
        n('mid', 200),
        n('early', 100),
      ],
    });
    expect(items.map((i) => i.node.id)).toEqual(['early', 'mid', 'late']);
  });

  test('S3 groupByConversation=false uses one shared index sequence', () => {
    const items = projectStream({
      groupByConversation: false,
      nodes: [
        n('a', 100, { conversationId: 'conv1' }),
        n('b', 200, { conversationId: 'conv2' }),
        n('c', 300, { conversationId: 'conv1' }),
      ],
    });
    expect(items.map((i) => i.streamIndex)).toEqual([0, 1, 2]);
  });

  test('S4 authorChange flips correctly within a conversation', () => {
    const items = projectStream({
      nodes: [
        n('a', 100, { conversationId: 'c1', authorCertId: 'cert-A' }),
        n('b', 200, { conversationId: 'c1', authorCertId: 'cert-A' }),
        n('c', 300, { conversationId: 'c1', authorCertId: 'cert-B' }),
      ],
    });
    expect(items[0]!.authorChange).toBe(true); // first item — no prior author
    expect(items[1]!.authorChange).toBe(false);
    expect(items[2]!.authorChange).toBe(true);
  });

  test('S5 unconversed nodes fall back to __ungrouped__', () => {
    const items = projectStream({
      nodes: [n('a', 100), n('b', 200)],
    });
    expect(items.every((i) => i.conversationId === '__ungrouped__')).toBe(true);
    expect(items.map((i) => i.streamIndex)).toEqual([0, 1]);
  });
});

// ─── D-SCG-persona-projection tests ──────────────────────────────────

import type { RelationKind } from '@semantos/scg-relations';
import { projectPersona } from '../rendering.js';

function edge(
  id: string,
  kind: RelationKind,
  sourceId: string,
  targetId: string,
  createdMs = 0,
): RelationEdge {
  return { id, kind, sourceId, targetId, createdAt: new Date(createdMs) };
}

describe('projectPersona (D-SCG-persona-projection)', () => {
  const identity = { certId: 'cert-todd', displayName: 'Todd' };

  test('P1 echoes identity + viewerHat unchanged', () => {
    const out = projectPersona({
      identity,
      viewerHat: 'topical',
      nodes: [],
      edges: [],
    });
    expect(out.identity).toEqual(identity);
    expect(out.viewerHat).toBe('topical');
  });

  test('P2 social face is chronological stream of owned cells', () => {
    const out = projectPersona({
      identity,
      viewerHat: 'social',
      nodes: [n('p2', 200), n('p1', 100), n('p3', 300)],
      edges: [],
    });
    expect(out.social.map((i) => i.node.id)).toEqual(['p1', 'p2', 'p3']);
    expect(out.social.every((i) => i.conversationId === '__ungrouped__')).toBe(true);
  });

  test('P3 topical face folds REPLIES_TO/CITES into trees under owned roots', () => {
    const out = projectPersona({
      identity,
      viewerHat: 'topical',
      nodes: [n('root', 100), n('reply', 200), n('cite', 300), n('orphan', 400)],
      edges: [
        edge('e1', 'REPLIES_TO', 'reply', 'root'),
        edge('e2', 'CITES', 'cite', 'root'),
      ],
    });
    // One root has children under topical kinds — only it appears.
    expect(out.topical).toHaveLength(1);
    expect(out.topical[0]!.node.id).toBe('root');
    const childIds = out.topical[0]!.children.map((c) => c.node.id).sort();
    expect(childIds).toEqual(['cite', 'reply']);
  });

  test('P4 commercial face surfaces money/access edges party-to identity', () => {
    const out = projectPersona({
      identity,
      viewerHat: 'commercial',
      nodes: [n('me', 0)],
      edges: [
        edge('p1', 'PAYS', 'me', 'them', 100),
        edge('a1', 'ATTESTS', 'them', 'me', 200),
        // Off-persona edge — excluded.
        edge('off', 'PAYS', 'someone', 'else', 300),
        // Non-commercial kind — excluded.
        edge('r1', 'REPLIES_TO', 'me', 'them', 400),
      ],
    });
    expect(out.commercial.map((e) => e.id).sort()).toEqual(['a1', 'p1']);
  });

  test('P5 groups fold from SUBSCRIBES_TO edges sourced from owned cells', () => {
    const out = projectPersona({
      identity,
      viewerHat: 'topical',
      nodes: [n('me', 0)],
      edges: [
        edge('s1', 'SUBSCRIBES_TO', 'me', 'group-alpha', 500),
        edge('s2', 'SUBSCRIBES_TO', 'me', 'group-beta', 600),
        // Duplicate target — deduped.
        edge('s3', 'SUBSCRIBES_TO', 'me', 'group-alpha', 700),
        // Sourced from a cell we don't own — excluded.
        edge('s4', 'SUBSCRIBES_TO', 'stranger', 'group-gamma', 800),
      ],
    });
    expect(out.groups.map((g) => g.groupId).sort()).toEqual([
      'group-alpha',
      'group-beta',
    ]);
    // Earliest subscription wins (s1, not s3).
    const alpha = out.groups.find((g) => g.groupId === 'group-alpha')!;
    expect(alpha.subscribedAt.getTime()).toBe(500);
  });

  test('P6 contact-book edges pass through unchanged', () => {
    const out = projectPersona({
      identity,
      viewerHat: 'social',
      nodes: [],
      edges: [],
      contactEdges: [
        {
          edgeType: 'MESSAGING',
          counterpartyCertId: 'cert-alice',
          counterpartyDisplayName: 'Alice',
          revoked: false,
        },
      ],
    });
    expect(out.edges).toHaveLength(1);
    expect(out.edges[0]!.edgeType).toBe('MESSAGING');
  });

  test('P7 faceFilter override changes which kinds count as topical', () => {
    const out = projectPersona({
      identity,
      viewerHat: 'topical',
      nodes: [n('root', 100), n('child', 200)],
      edges: [edge('e1', 'APPROVES', 'child', 'root')],
      faceFilter: { topical: ['APPROVES'] },
    });
    expect(out.topical).toHaveLength(1);
    expect(out.topical[0]!.children.map((c) => c.node.id)).toEqual(['child']);
  });

  test('P8 roots with no topical children are omitted from topical', () => {
    const out = projectPersona({
      identity,
      viewerHat: 'topical',
      nodes: [n('lonely', 100)],
      edges: [],
    });
    expect(out.topical).toEqual([]);
  });
});

```
