---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-handlers/transfer-content.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.385435+00:00
---

# runtime/shell/src/router/verb-handlers/transfer-content.ts

```ts
/**
 * Metered Content Transfer shell verbs — the user/PWA/cartridge surface over
 * the shell-owned TransferService (ctx.transfer). Distinct from the bare
 * `transfer` verb (object→hat handoff): these are dotted `transfer.*` content
 * verbs, mirroring the brain's `transfer.*` namespace.
 *
 *   transfer.share  --path <file> [--name <n>]      → { magnet, name, bytes }
 *   transfer.fetch  --magnet <hex> [--out <file>]   → { magnet, bytes, out? }
 *   transfer.list                                    → { transfers: [...] }
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { basename } from 'node:path';
import type { ShellCommand } from '../../parser';
import type { ShellContext } from '../../types';
import type { VerbHandler } from '../types';

const UNAVAILABLE = { error: 'transfer service not available in this shell', code: 'TRANSFER_UNAVAILABLE' };

function str(v: unknown): string | undefined {
  return typeof v === 'string' && v.length > 0 ? v : undefined;
}

const shareHandler: VerbHandler = async (cmd: ShellCommand, ctx: ShellContext) => {
  if (!ctx.transfer) return UNAVAILABLE;
  const path = str(cmd.flags.path) ?? str(cmd.objectId);
  if (!path) return { error: 'transfer.share requires --path <file>', code: 'MISSING_PATH' };
  const bytes = new Uint8Array(readFileSync(path));
  const name = str(cmd.flags.name) ?? basename(path);
  const magnet = await ctx.transfer.share(bytes, name);
  return { magnet, name, bytes: bytes.length };
};

const fetchHandler: VerbHandler = async (cmd: ShellCommand, ctx: ShellContext) => {
  if (!ctx.transfer) return UNAVAILABLE;
  const magnet = str(cmd.flags.magnet) ?? str(cmd.objectId);
  if (!magnet) return { error: 'transfer.fetch requires --magnet <hex>', code: 'MISSING_MAGNET' };
  const timeoutMs = typeof cmd.flags.timeout === 'number' ? cmd.flags.timeout : undefined;
  const data = await ctx.transfer.fetch(magnet, timeoutMs ? { timeoutMs } : undefined);
  const out = str(cmd.flags.out);
  if (out) writeFileSync(out, data);
  return { magnet, bytes: data.length, ...(out ? { out } : {}) };
};

const listHandler: VerbHandler = async (_cmd: ShellCommand, ctx: ShellContext) => {
  if (!ctx.transfer) return UNAVAILABLE;
  return { transfers: ctx.transfer.list() };
};

export const transferContentHandlers = {
  'transfer.share': shareHandler,
  'transfer.fetch': fetchHandler,
  'transfer.list': listHandler,
};

```
