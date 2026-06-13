---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-legacy-cli/src/serve.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.698797+00:00
---

# archive/apps-legacy-cli/src/serve.ts

```ts
/**
 * D-OJ-conv-legacy-serve — `legacy serve` sub-command implementation.
 *
 * Starts a `MetaWebhookServer` wired with the `metaFanOutSink` from
 * `bootstrap()` as its `onConversationTurn`, so inbound Meta DMs flow:
 *
 *   Meta webhook POST
 *     → MetaWebhookServer
 *     → ConversationTurnEvent
 *     → metaFanOutSink
 *       ├── legacy JSONL (always, ALL providers via messagePatchSink.append)
 *       └── canonical Postgres turn sink (META-only, no-op when DATABASE_URL unset)
 *
 * ## Additive + gated + dormant-until-enabled
 *
 * The command runs without crashing when:
 *   - `DATABASE_URL` is unset — canonical side is a no-op (getDatabaseOrNull() → null).
 *   - No live Meta account / no incoming traffic — the server is idle.
 *
 * Go-live: set DATABASE_URL on rbs + unrestrict the Meta account in the
 * developer portal. Traffic then flows automatically.
 *
 * ## Env vars consumed
 *
 *   WEBHOOK_PORT                  — HTTP listen port (default: 3002)
 *   META_WEBHOOK_VERIFY_TOKEN     — Meta challenge verify token (REQUIRED for
 *                                   Meta to register the webhook endpoint;
 *                                   absent → server starts but all challenge
 *                                   requests return 403)
 *   META_PAGE_ACCESS_TOKEN        — Page long-lived access token (REQUIRED for
 *                                   outbound replies; absent → no ack messages)
 *   OLLAMA_BASE_URL / OLLAMA_ENABLE=1  — local Ollama LLM backend
 *   ANTHROPIC_API_KEY                  — BYOK Claude (vision + high-stakes)
 *   OPENROUTER_API_KEY                 — hosted OpenRouter fallback
 *
 * ## Graceful shutdown
 *
 * Handles SIGINT + SIGTERM. Calls `shutdown()` from `bootstrap()` to flush
 * deferred state (refresh worker, continuous-ingest handles) before exit.
 *
 * ## No self-call deadlock
 *
 * The legacy-cli serve process is its OWN process (not the brain reactor).
 * Postgres writes go directly to the database. Per project memory
 * `semantos_brain_single_threaded_reactor`, no sync-call back into the
 * brain HTTP/REPL is made here.
 */

import {
  MetaWebhookServer,
  MetaProvider,
  LlmRouter,
  OllamaAdapter,
  AnthropicAdapter,
  OpenRouterAdapter,
} from '@semantos/legacy-ingest';
import type { MetaWebhookServerOpts, LLMAdapter, ConversationTurnSink } from '@semantos/legacy-ingest';

// ── Public option type for the helper function ──────────────────────────────

export interface BuildMetaServerOptsArgs {
  /** Fan-out sink from bootstrap(). Passed as `onConversationTurn`. */
  readonly metaFanOutSink: ConversationTurnSink;
  /** Meta challenge/verify token (META_WEBHOOK_VERIFY_TOKEN). */
  readonly verifyToken: string;
  /** Page access token for outbound replies (META_PAGE_ACCESS_TOKEN). */
  readonly pageAccessToken: string;
  /**
   * LLM adapter for message extraction + conversation engine.
   * When null, a no-op stub is used so the server starts without crashing.
   * Messages will be pre-filtered (zero extraction confidence) until a real
   * LLM backend is configured.
   */
  readonly llm: LLMAdapter | null;
}

/**
 * Pure option-assembly helper — testable without a live socket.
 *
 * Converts the args into a `MetaWebhookServerOpts` ready to pass to
 * `new MetaWebhookServer(opts)`. Extracted so tests can assert the
 * wiring without starting a real HTTP listener.
 */
export function buildMetaServerOpts(args: BuildMetaServerOptsArgs): MetaWebhookServerOpts {
  const provider = new MetaProvider({ verifyToken: args.verifyToken });

  return {
    provider,
    pageAccessToken: args.pageAccessToken,
    // MetaWebhookServer requires a non-null LLMAdapter. When no LLM backend
    // is configured we supply a no-op stub so the server starts. Messages
    // will have zero extraction confidence until a real backend is wired.
    llm: args.llm ?? makeNoOpLlm(),
    onConversationTurn: args.metaFanOutSink,
  };
}

// ── LLM builder (mirrors bootstrap.ts env-var resolution) ───────────────────

/**
 * Builds an LLMAdapter from env vars, mirroring the bootstrap.ts logic.
 * Returns null when no backend is configured (server starts in no-op mode).
 */
export function buildLlmFromEnv(): LLMAdapter | null {
  const ollamaConfigured =
    (process.env.OLLAMA_BASE_URL && process.env.OLLAMA_BASE_URL.length > 0) ||
    process.env.OLLAMA_ENABLE === '1';
  const anthropicKey = process.env.ANTHROPIC_API_KEY;
  const anthropicConfigured = !!anthropicKey && anthropicKey.length > 0;
  const openrouterKey = process.env.OPENROUTER_API_KEY;
  const openrouterConfigured = !!openrouterKey && openrouterKey.length > 0;

  if (!ollamaConfigured && !anthropicConfigured && !openrouterConfigured) {
    return null;
  }

  return new LlmRouter({
    adapters: {
      ollama: ollamaConfigured
        ? new OllamaAdapter({
            baseUrl: process.env.OLLAMA_BASE_URL || undefined,
            model: process.env.OLLAMA_MODEL || undefined,
          })
        : null,
      anthropic: anthropicConfigured
        ? new AnthropicAdapter({
            apiKey: () => process.env.ANTHROPIC_API_KEY ?? null,
          })
        : null,
      openrouter: openrouterConfigured
        ? new OpenRouterAdapter({
            apiKey: () => process.env.OPENROUTER_API_KEY ?? null,
          })
        : null,
    },
  });
}

// ── Main serve entrypoint ────────────────────────────────────────────────────

export interface ServeMetaOpts {
  /** Fan-out sink from bootstrap(). */
  readonly metaFanOutSink: ConversationTurnSink;
  /** Optional shutdown callback from bootstrap(). Called on SIGINT/SIGTERM. */
  readonly shutdown?: () => Promise<void>;
}

/**
 * Start the Meta webhook server and attach graceful-shutdown handlers.
 *
 * Reads WEBHOOK_PORT, META_WEBHOOK_VERIFY_TOKEN, META_PAGE_ACCESS_TOKEN,
 * and LLM env vars at call time. Logs readiness and blocks until SIGINT/SIGTERM.
 */
export async function serveMeta(opts: ServeMetaOpts): Promise<void> {
  const port = parseInt(process.env.WEBHOOK_PORT ?? '3002', 10);
  const verifyToken = process.env.META_WEBHOOK_VERIFY_TOKEN ?? '';
  const pageAccessToken = process.env.META_PAGE_ACCESS_TOKEN ?? '';

  if (!verifyToken) {
    process.stderr.write(
      '[legacy serve] WARNING: META_WEBHOOK_VERIFY_TOKEN is not set — ' +
        'Meta challenge verification will always return 403. ' +
        'Set the token to register the webhook in the developer portal.\n',
    );
  }

  if (!pageAccessToken) {
    process.stderr.write(
      '[legacy serve] WARNING: META_PAGE_ACCESS_TOKEN is not set — ' +
        'outbound reply messages will not be sent.\n',
    );
  }

  const llm = buildLlmFromEnv();
  if (!llm) {
    process.stderr.write(
      '[legacy serve] WARNING: No LLM backend configured. ' +
        'Set OLLAMA_BASE_URL, ANTHROPIC_API_KEY, or OPENROUTER_API_KEY for extraction. ' +
        'Server will start but messages will not be extracted until a backend is set.\n',
    );
  }

  const serverOpts = buildMetaServerOpts({
    metaFanOutSink: opts.metaFanOutSink,
    verifyToken,
    pageAccessToken,
    llm,
  });

  const webhookServer = new MetaWebhookServer(serverOpts);

  const server = Bun.serve({
    port,
    fetch: (req: Request) => webhookServer.handle(req),
  });

  const pathPrefix = serverOpts.pathPrefix ?? '/meta';
  process.stdout.write(
    `[legacy serve] Meta webhook listening on :${port}\n` +
      `[legacy serve] Routes: GET/POST ${pathPrefix}/webhook\n` +
      `[legacy serve] Canonical sink: ${
        process.env.DATABASE_URL
          ? 'active (DATABASE_URL set)'
          : 'dormant (DATABASE_URL unset — activates once set)'
      }\n` +
      `[legacy serve] Meta account: dormant until account is unrestricted in developer portal\n`,
  );

  // Block until SIGINT or SIGTERM.
  await new Promise<void>((resolve) => {
    const stop = async () => {
      process.stdout.write('\n[legacy serve] Shutting down...\n');
      server.stop(true);
      await opts.shutdown?.();
      resolve();
    };
    process.once('SIGINT', stop);
    process.once('SIGTERM', stop);
  });
}

// ── Fallback no-op LLM adapter ──────────────────────────────────────────────

/**
 * A minimal no-op LLMAdapter that satisfies the interface contract without
 * making any network calls. Used when no LLM backend is configured so the
 * serve command can start without crashing.
 *
 * All extractions return zero confidence, so messages are pre-filtered
 * rather than starting conversations.
 */
function makeNoOpLlm(): LLMAdapter {
  return {
    async extract<T>(_opts: { prompt: string; schema: object }) {
      return { payload: {} as T, confidence: 0, raw: '' };
    },
  };
}

```
