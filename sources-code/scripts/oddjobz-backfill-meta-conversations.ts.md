---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/oddjobz-backfill-meta-conversations.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.320274+00:00
---

# scripts/oddjobz-backfill-meta-conversations.ts

```ts
#!/usr/bin/env bun
/**
 * Backfill Meta Business Suite conversations into the unified Oddjobz graph.
 *
 * This is the direct operator path for Customer Zero testing: provide a Meta
 * access token plus one or more asset ids and every historical turn is written
 * as an `oddjobz.message.v1` patch, then routed into dispatch decisions.
 *
 * Examples:
 *   META_ACCESS_TOKEN=... bun scripts/oddjobz-backfill-meta-conversations.ts \
 *     --query "messenger=PAGE_ID instagram=IG_ID"
 *
 *   bun scripts/oddjobz-backfill-meta-conversations.ts \
 *     --token "$META_ACCESS_TOKEN" --messenger PAGE_ID --max-pages 20
 */

import {
  ConversationDispatchRouter,
  JsonlConversationDispatchDecisionSink,
  JsonlConversationTurnPatchSink,
  MetaProvider,
  OddjobzConversationGraphResolver,
  rawItemToOddjobzMessagePatch,
  type AccessToken,
  type Cursor,
} from '../runtime/legacy-ingest/src';

interface Args {
  root?: string;
  token?: string;
  query?: string;
  messenger: string[];
  instagram: string[];
  since?: number;
  maxPages?: number;
  pageSize?: number;
  apiVersion?: string;
}

const args = parseArgs(Bun.argv.slice(2));
const token = args.token ?? process.env.META_ACCESS_TOKEN;
if (!token) {
  console.error('Missing Meta access token. Pass --token or set META_ACCESS_TOKEN.');
  process.exit(1);
}

const query = buildQuery(args);
if (!query) {
  console.error('Missing Meta asset id. Pass --query "messenger=PAGE_ID instagram=IG_ID", --messenger PAGE_ID, or --instagram IG_ID.');
  process.exit(1);
}

const provider = new MetaProvider({
  verifyToken: process.env.META_WEBHOOK_VERIFY_TOKEN ?? '',
  apiVersion: args.apiVersion,
  pageSize: args.pageSize,
});

const graphResolver = new OddjobzConversationGraphResolver({ root: args.root });
const router = new ConversationDispatchRouter({
  resolveCandidates: graphResolver.resolve,
});
const dispatchSink = new JsonlConversationDispatchDecisionSink({
  root: args.root,
  router,
});
const messageSink = new JsonlConversationTurnPatchSink({
  root: args.root,
});

const accessToken: AccessToken = {
  accessToken: token,
  refreshToken: null,
  expiresAt: Date.now() + 60 * 60 * 1000,
  scopes: '',
  providerExtras: {},
};

let cursor: Cursor = null;
let pages = 0;
let rawItems = 0;
let projected = 0;
let skipped = 0;
let dispatchProjected = 0;
let errors = 0;

while (true) {
  if (args.maxPages !== undefined && pages >= args.maxPages) break;
  const page = await provider.listPage(accessToken, {
    cursor,
    query,
    since: args.since,
  });
  pages += 1;
  for (const item of page.items) {
    rawItems += 1;
    try {
      const patch = rawItemToOddjobzMessagePatch(item);
      if (!patch) {
        skipped += 1;
        continue;
      }
      const wrote = messageSink.appendRawItem(item);
      if (wrote) {
        projected += 1;
        if (dispatchSink.append(patch)) dispatchProjected += 1;
      } else {
        skipped += 1;
      }
    } catch {
      errors += 1;
    }
  }
  cursor = page.nextCursor;
  if (!cursor) break;
}

console.log(JSON.stringify({
  providerId: 'meta',
  query,
  pages,
  rawItems,
  projected,
  dispatchProjected,
  skipped,
  errors,
  completed: cursor === null,
  cursor,
}, null, 2));

if (errors > 0) process.exit(1);

function parseArgs(argv: string[]): Args {
  const out: Args = { messenger: [], instagram: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    if (arg === '--root' && next) {
      out.root = next;
      i += 1;
    } else if (arg === '--token' && next) {
      out.token = next;
      i += 1;
    } else if (arg === '--query' && next) {
      out.query = next;
      i += 1;
    } else if (arg === '--messenger' && next) {
      out.messenger.push(next);
      i += 1;
    } else if (arg === '--instagram' && next) {
      out.instagram.push(next);
      i += 1;
    } else if (arg === '--since' && next) {
      const parsed = Date.parse(next);
      if (Number.isNaN(parsed)) throw new Error(`invalid --since: ${next}`);
      out.since = parsed;
      i += 1;
    } else if (arg === '--max-pages' && next) {
      out.maxPages = parsePositiveInt(next, '--max-pages');
      i += 1;
    } else if (arg === '--page-size' && next) {
      out.pageSize = parsePositiveInt(next, '--page-size');
      i += 1;
    } else if (arg === '--api-version' && next) {
      out.apiVersion = next;
      i += 1;
    } else {
      throw new Error(`unknown argument: ${arg}`);
    }
  }
  return out;
}

function buildQuery(args: Args): string {
  const parts: string[] = [];
  if (args.query?.trim()) parts.push(args.query.trim());
  for (const id of args.messenger) parts.push(`messenger=${id}`);
  for (const id of args.instagram) parts.push(`instagram=${id}`);
  return parts.join(' ');
}

function parsePositiveInt(value: string, name: string): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) throw new Error(`invalid ${name}: ${value}`);
  return parsed;
}

```
