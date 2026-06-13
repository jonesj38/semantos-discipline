---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/webhook/serve.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.137791+00:00
---

# runtime/legacy-ingest/src/webhook/serve.ts

```ts
/**
 * Meta webhook server entry point — run with `bun run webhook/serve.ts`
 *
 * Configuration via environment variables:
 *   WEBHOOK_PORT           — HTTP port (default: 3002)
 *   META_VERIFY_TOKEN      — the token you set in the Meta developer portal
 *   META_PAGE_ACCESS_TOKEN — your page's long-lived access token
 *   OPENROUTER_API_KEY     — OpenRouter API key for the LLM
 *
 * Meta requires the endpoint to be HTTPS-reachable. In development use ngrok
 * or Cloudflare Tunnel. In production, sit behind nginx/Caddy.
 */

import { MetaWebhookServer } from './meta-server';
import { MetaProvider } from '../providers/meta';
import { OpenRouterAdapter } from '../extractor/openrouter';
import { JsonlConversationTurnPatchSink } from '../conversation/turn-patch-store';
import { ConversationDispatchRouter } from '../conversation/dispatch-router';
import { OddjobzConversationGraphResolver } from '../conversation/graph-resolver';
import { JsonlConversationDispatchDecisionSink } from '../conversation/dispatch-decision-store';

const port = parseInt(process.env.WEBHOOK_PORT ?? '3002', 10);
const verifyToken = process.env.META_VERIFY_TOKEN ?? '';
const pageAccessToken = process.env.META_PAGE_ACCESS_TOKEN ?? '';
const apiKey = process.env.OPENROUTER_API_KEY ?? '';

for (const [name, val] of [
  ['META_VERIFY_TOKEN', verifyToken],
  ['META_PAGE_ACCESS_TOKEN', pageAccessToken],
  ['OPENROUTER_API_KEY', apiKey],
]) {
  if (!val) {
    console.error(`[webhook] ${name} is not set — exiting`);
    process.exit(1);
  }
}

const provider = new MetaProvider({ verifyToken });
const llm = new OpenRouterAdapter({ apiKey });
const graphResolver = new OddjobzConversationGraphResolver();
const dispatchRouter = new ConversationDispatchRouter({
  resolveCandidates: graphResolver.resolve,
});
const dispatchDecisionSink = new JsonlConversationDispatchDecisionSink({
  router: dispatchRouter,
});
const turnPatchSink = new JsonlConversationTurnPatchSink({
  onPatch: dispatchDecisionSink.append,
});

// ── D-OJ-conv-legacy-ingest-bridge INJECTION POINT ──────────────────────────
// When the canonical sink from the cartridge (`makeCanonicalTurnSink` from
// `@semantos/oddjobz`) should be wired here, compose it alongside the legacy
// sink. This CANNOT be done directly from this file because the dependency
// direction is cartridge → runtime (not runtime → cartridge) — wiring it here
// would create a circular dependency.
//
// CUTOVER FOLLOW-UP: The brain reactor boundary (the brain process that imports
// BOTH `@semantos/oddjobz` and `@semantos/legacy-ingest`) is the right place
// to instantiate the canonical sink and compose the two sinks. Pattern:
//
//   import { makeCanonicalTurnSink } from '@semantos/oddjobz/conversation/legacy-ingest-bridge';
//   import { getDatabaseOrNull } from '@semantos/oddjobz/conversation/db';
//   const db = getDatabaseOrNull();
//   const canonicalSink = db ? makeCanonicalTurnSink(db) : undefined;
//   const composedSink: ConversationTurnSink = (event) => {
//     turnPatchSink.append(event);           // legacy JSONL (always)
//     void canonicalSink?.(event);           // canonical sem_objects (best-effort)
//   };
//   // Then pass composedSink to onConversationTurn below.
// ── END INJECTION POINT ──────────────────────────────────────────────────────

const webhookServer = new MetaWebhookServer({
  provider,
  pageAccessToken,
  llm,
  onConversationTurn: (event) => { turnPatchSink.append(event); },
  onProposal: async (proposal) => {
    // TODO: wire to ProposalStore once the full stack is wired in production
    console.log('[webhook] proposal extracted:', proposal.proposalId, proposal.summary);
  },
});

Bun.serve({
  port,
  fetch: (req: Request) => webhookServer.handle(req),
});

console.log(`[webhook] Meta webhook listening on :${port}`);

```
