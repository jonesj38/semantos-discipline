---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/oddjobz-backfill-dispatch-decisions.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.322394+00:00
---

# scripts/oddjobz-backfill-dispatch-decisions.ts

```ts
#!/usr/bin/env bun
/**
 * Backfill oddjobz.dispatch.v1 rows from existing oddjobz.message.v1 rows.
 *
 * This is safe to re-run: dispatch decisions are deduplicated by source
 * message patch + lane + primary target.
 */

import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import {
  ConversationDispatchRouter,
  JsonlConversationDispatchDecisionSink,
  OddjobzConversationGraphResolver,
  defaultConversationTurnPatchPath,
  type OddjobzMessagePatch,
} from '../runtime/legacy-ingest/src';

const root = process.env.SEMANTOS_ROOT ?? join(homedir(), '.semantos');
const providerId = argValue('--provider');
const messagesPath = argValue('--messages') ?? defaultConversationTurnPatchPath(root);

if (!existsSync(messagesPath)) {
  console.error(`[dispatch] messages file not found: ${messagesPath}`);
  process.exit(1);
}

const graphResolver = new OddjobzConversationGraphResolver({ root });
const router = new ConversationDispatchRouter({
  resolveCandidates: graphResolver.resolve,
});
const sink = new JsonlConversationDispatchDecisionSink({ root, router });

let rawRows = 0;
let projected = 0;
let skipped = 0;
let errors = 0;

for (const line of readFileSync(messagesPath, 'utf8').split(/\n/)) {
  if (!line.trim()) continue;
  rawRows += 1;
  try {
    const patch = JSON.parse(line) as OddjobzMessagePatch;
    if (providerId && patch.providerId !== providerId) {
      skipped += 1;
      continue;
    }
    if (await sink.append(patch)) projected += 1;
    else skipped += 1;
  } catch (err) {
    errors += 1;
    console.error(`[dispatch] row ${rawRows}: ${err instanceof Error ? err.message : String(err)}`);
  }
}

console.log(JSON.stringify({
  providerId: providerId ?? 'all',
  messagesPath,
  rawRows,
  projected,
  skipped,
  errors,
}, null, 2));

function argValue(name: string): string | null {
  const exact = process.argv.indexOf(name);
  if (exact >= 0) return process.argv[exact + 1] ?? null;
  const prefixed = process.argv.find((arg) => arg.startsWith(`${name}=`));
  return prefixed ? prefixed.slice(name.length + 1) : null;
}

```
