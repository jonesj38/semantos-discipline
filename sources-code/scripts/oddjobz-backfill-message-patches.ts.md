---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/oddjobz-backfill-message-patches.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.318508+00:00
---

# scripts/oddjobz-backfill-message-patches.ts

```ts
#!/usr/bin/env bun
/**
 * Backfill oddjobz.message.v1 rows from existing encrypted legacy-ingest
 * raw blobs. Useful after introducing the unified message trail: future
 * `legacy ingest gmail` runs write rows automatically, but old Gmail blobs
 * need one local replay pass.
 */

import { join } from 'node:path';
import { homedir } from 'node:os';
import { FsPersistence } from '../apps/legacy-cli/src/fs-persistence';
import { unlockWithPassphrase } from '../apps/legacy-cli/src/kek-from-passphrase';
import {
  ConversationDispatchRouter,
  JsonlConversationDispatchDecisionSink,
  JsonlConversationTurnPatchSink,
  LegacyBlobStore,
  OddjobzConversationGraphResolver,
} from '../runtime/legacy-ingest/src';

const root = process.env.SEMANTOS_ROOT ?? join(homedir(), '.semantos');
const providerId = argValue('--provider') ?? 'gmail';
const passphrase = process.env.ODDJOBZ_LEGACY_PASSPHRASE?.trim();

if (!passphrase) {
  console.error('Set ODDJOBZ_LEGACY_PASSPHRASE in the environment; do not pass it as a command-line arg.');
  process.exit(1);
}

const kek = await unlockWithPassphrase(passphrase);
const blobStore = new LegacyBlobStore({
  persistence: new FsPersistence({ root }),
  kekProvider: async () => kek,
});
const graphResolver = new OddjobzConversationGraphResolver({ root });
const dispatchRouter = new ConversationDispatchRouter({
  resolveCandidates: graphResolver.resolve,
});
const dispatchSink = new JsonlConversationDispatchDecisionSink({
  root,
  router: dispatchRouter,
});
const sink = new JsonlConversationTurnPatchSink({
  root,
  onPatch: dispatchSink.append,
});

const ids = await blobStore.listIds(providerId);
let projected = 0;
let skipped = 0;
let errors = 0;

for (const id of ids) {
  try {
    const item = await blobStore.get(providerId, id);
    if (!item) {
      skipped += 1;
      continue;
    }
    if (sink.appendRawItem(item)) projected += 1;
    else skipped += 1;
  } catch (err) {
    errors += 1;
    console.error(`[messages] ${providerId}/${id}: ${err instanceof Error ? err.message : String(err)}`);
  }
}

console.log(JSON.stringify({
  providerId,
  rawItems: ids.length,
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
