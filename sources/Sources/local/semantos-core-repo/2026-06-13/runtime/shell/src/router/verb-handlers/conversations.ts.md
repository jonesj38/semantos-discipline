---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-handlers/conversations.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.385990+00:00
---

# runtime/shell/src/router/verb-handlers/conversations.ts

```ts
import type { ShellCommand } from '../../parser';
import type { ShellContext } from '../../types';
import type { VerbHandler } from '../types';

function initialsFor(title: string): string {
  const parts = title.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  if (parts.length === 1) return parts[0][0].toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

const conversationCreateHandler: VerbHandler = async (cmd: ShellCommand, ctx: ShellContext) => {
  const title = typeof cmd.flags.title === 'string' ? cmd.flags.title : 'New conversation';
  const mode = typeof cmd.flags.mode === 'string' ? cmd.flags.mode : 'direct';
  const participantsRaw = typeof cmd.flags.participants === 'string' ? cmd.flags.participants : '';
  const participants = participantsRaw
    .split(',')
    .map((p) => p.trim())
    .filter(Boolean);

  const id = `conv-${mode}-${Date.now()}`;
  const now = new Date().toISOString();

  const cell = {
    id,
    title,
    avatar: initialsFor(title),
    mode,
    participants,
    turns: [] as unknown[],
    context: {} as Record<string, unknown>,
    phase: 'open',
  };

  const adapter = ctx.adapter;
  if (adapter) {
    const hatKey = ctx.activeHatCertId ?? ctx.activeHatId ?? 'default';
    const key = `conversations/${hatKey}/${id}`;
    const encoded = new TextEncoder().encode(JSON.stringify(cell));
    await adapter.write(key, encoded);
  }

  return { ...cell, updatedAt: now };
};

const conversationsFindHandler: VerbHandler = async (cmd: ShellCommand, ctx: ShellContext) => {
  const adapter = ctx.adapter;
  if (!adapter) return [];

  const query = typeof cmd.flags.query === 'string' ? cmd.flags.query.toLowerCase() : '';
  const modeFilter = typeof cmd.flags.mode === 'string' ? cmd.flags.mode : undefined;

  const hatKey = ctx.activeHatCertId ?? ctx.activeHatId ?? 'default';
  const prefix = `conversations/${hatKey}/`;
  const relativeKeys = await adapter.list(prefix);

  const cells = await Promise.all(
    relativeKeys.map(async (relKey) => {
      const key = `${prefix}${relKey}`;
      const data = await adapter.read(key);
      if (!data) return null;
      try {
        return JSON.parse(new TextDecoder().decode(data)) as Record<string, unknown>;
      } catch {
        return null;
      }
    }),
  );

  let result = cells.filter((c): c is Record<string, unknown> => c !== null);

  if (modeFilter) {
    result = result.filter((c) => c['mode'] === modeFilter);
  }

  if (query) {
    result = result.filter((c) => {
      const titleMatch = typeof c['title'] === 'string' && c['title'].toLowerCase().includes(query);
      const turnsMatch = Array.isArray(c['turns']) &&
        (c['turns'] as Array<Record<string, unknown>>).some(
          (t) => typeof t['body'] === 'string' && t['body'].toLowerCase().includes(query),
        );
      return titleMatch || turnsMatch;
    });
  }

  return result.sort((a, b) => {
    const aAt = typeof a['updatedAt'] === 'string' ? a['updatedAt'] : '';
    const bAt = typeof b['updatedAt'] === 'string' ? b['updatedAt'] : '';
    return bAt.localeCompare(aAt);
  });
};

export const conversationsHandlers = {
  'conversation.create': conversationCreateHandler,
  'conversations.find': conversationsFindHandler,
};

```
