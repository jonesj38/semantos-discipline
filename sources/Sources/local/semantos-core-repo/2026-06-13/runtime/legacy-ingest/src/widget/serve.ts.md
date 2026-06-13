---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/widget/serve.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.164548+00:00
---

# runtime/legacy-ingest/src/widget/serve.ts

```ts
/**
 * Widget server entry point — run with `bun run widget/serve.ts`
 *
 * Configuration via environment variables:
 *   WIDGET_PORT          — HTTP port (default: 3001)
 *   WIDGET_ALLOWED_ORIGINS — comma-separated allowed CORS origins
 *                            e.g. "https://oddjobtodd.info,https://www.oddjobtodd.info"
 *   OPENROUTER_API_KEY   — OpenRouter API key for the LLM
 *
 * In production, sit behind a reverse proxy (nginx/Caddy) that handles
 * TLS and rate-limiting.
 */

import { WidgetServer } from './server';
import { OpenRouterAdapter } from '../extractor/openrouter';
import { JsonlConversationTurnPatchSink } from '../conversation/turn-patch-store';
import { ConversationDispatchRouter } from '../conversation/dispatch-router';
import { OddjobzConversationGraphResolver } from '../conversation/graph-resolver';
import { JsonlConversationDispatchDecisionSink } from '../conversation/dispatch-decision-store';

const port = parseInt(process.env.WIDGET_PORT ?? '3001', 10);
const originsRaw = process.env.WIDGET_ALLOWED_ORIGINS ?? '';
const allowedOrigins = originsRaw
  ? originsRaw.split(',').map(o => o.trim()).filter(Boolean)
  : ['https://oddjobtodd.info', 'https://www.oddjobtodd.info'];

const apiKey = process.env.OPENROUTER_API_KEY ?? '';
if (!apiKey) {
  console.error('[widget] OPENROUTER_API_KEY is not set — exiting');
  process.exit(1);
}

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

const server = new WidgetServer({
  llm,
  allowedOrigins,
  onConversationTurn: (event) => { turnPatchSink.append(event); },
  onProposal: async (proposal) => {
    // TODO: wire to ProposalStore once the full stack is wired in production
    console.log('[widget] proposal extracted:', proposal.proposalId, proposal.summary);
  },
});

Bun.serve({
  port,
  fetch: (req: Request) => server.handle(req),
});

console.log(`[widget] listening on :${port}  origins: ${allowedOrigins.join(', ')}`);

```
