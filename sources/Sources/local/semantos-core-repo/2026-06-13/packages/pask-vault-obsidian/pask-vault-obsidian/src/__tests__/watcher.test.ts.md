---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/pask-vault-obsidian/pask-vault-obsidian/src/__tests__/watcher.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.490683+00:00
---

# packages/pask-vault-obsidian/pask-vault-obsidian/src/__tests__/watcher.test.ts

```ts
import { describe, test, expect } from 'bun:test';
import { parseWikilinks, parseTags, ObsidianWatcher } from '../watcher';

describe('parseWikilinks', () => {
  test('extracts basic links', () => {
    expect(parseWikilinks('see [[Projects/SemantOS]] and [[People/Damian]]')).toEqual([
      'Projects/SemantOS',
      'People/Damian',
    ]);
  });

  test('strips alias portion', () => {
    expect(parseWikilinks('[[Real Note|Display Text]]')).toEqual(['Real Note']);
  });

  test('strips heading fragment', () => {
    expect(parseWikilinks('[[Note#Section]]')).toEqual(['Note']);
  });

  test('returns empty for no links', () => {
    expect(parseWikilinks('plain text here')).toEqual([]);
  });
});

describe('parseTags', () => {
  test('extracts inline tags', () => {
    expect(parseTags('hello #fencing world #sport/climbing')).toEqual([
      'fencing',
      'sport/climbing',
    ]);
  });

  test('extracts frontmatter-style tags', () => {
    expect(parseTags('#project #todo')).toEqual(['project', 'todo']);
  });

  test('ignores URLs', () => {
    // https://example.com should not produce a tag
    const tags = parseTags('see https://example.com/#anchor');
    expect(tags).not.toContain('anchor');
  });
});

describe('ObsidianWatcher.onFileOpen', () => {
  test('feeds obs:note cell to paskGraph', () => {
    const calls: unknown[] = [];
    const fakePask = {
      interact: (args: unknown) => { calls.push(args); },
      stableThreads: () => [],
      distance: () => Infinity,
      ready: true,
    };

    const w = new ObsidianWatcher({
      vaultPath: '/vault/My Vault',
      vaultId: 'my-vault',
      paskGraph: fakePask as never,
    });

    w.onFileOpen('Projects/SemantOS.md', 1000);

    expect(calls).toHaveLength(1);
    const call0 = calls[0] as Record<string, unknown>;
    expect(call0).toMatchObject({
      cellId: 'obs:note:my-vault/Projects/SemantOS',
      kind: 'open',
      strength: 0.5,
      nowMs: 1000,
    });
    expect(call0['relatedCells'] as string[]).toContain('obs:folder:my-vault/Projects');
  });
});

describe('ObsidianWatcher.onLinkTraverse', () => {
  test('emits bidirectional interactions', () => {
    const calls: unknown[] = [];
    const fakePask = {
      interact: (args: unknown) => calls.push(args),
      stableThreads: () => [],
      distance: () => Infinity,
      ready: true,
    };

    const w = new ObsidianWatcher({
      vaultPath: '/vault/My Vault',
      vaultId: 'my-vault',
      paskGraph: fakePask as never,
    });

    w.onLinkTraverse('NoteA.md', 'NoteB.md', 2000);

    expect(calls).toHaveLength(2);
    expect(calls[0]).toMatchObject({ cellId: 'obs:note:my-vault/NoteA', kind: 'link-traverse', strength: 1.0 });
    expect(calls[1]).toMatchObject({ cellId: 'obs:note:my-vault/NoteB', kind: 'link-traverse', strength: 1.0 });
  });
});

```
