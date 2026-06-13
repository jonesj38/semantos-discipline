---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-legacy-cli/src/__tests__/serve.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.701055+00:00
---

# archive/apps-legacy-cli/src/__tests__/serve.test.ts

```ts
/**
 * D-OJ-conv-legacy-serve — serve command wiring tests.
 *
 * Tests that the `legacy serve` command composes correctly WITHOUT a live
 * network, a real Meta account, a live database, or DATABASE_URL.
 *
 * Strategy: test the pure `buildMetaServerOpts()` helper in isolation.
 * This asserts that:
 *   1. `metaFanOutSink` is wired as `onConversationTurn`.
 *   2. The `MetaWebhookServer` receives the verify token.
 *   3. The server is constructed with all required opts.
 *   4. When `llm` is null, a no-op stub is injected (server does not crash).
 *   5. The composed opts are correct regardless of DATABASE_URL.
 *
 * No real HTTP listener is started. No live Meta account required.
 */

import { describe, expect, test } from 'bun:test';
import { buildMetaServerOpts, buildLlmFromEnv, type BuildMetaServerOptsArgs } from '../serve';
import type { ConversationTurnEvent, ConversationTurnSink } from '@semantos/legacy-ingest';
import { MetaWebhookServer, MetaProvider } from '@semantos/legacy-ingest';

// ── Helper: build a mock metaFanOutSink ─────────────────────────────────────

function makeMockSink(): { sink: ConversationTurnSink; calls: ConversationTurnEvent[] } {
  const calls: ConversationTurnEvent[] = [];
  const sink: ConversationTurnSink = async (event) => {
    calls.push(event);
  };
  return { sink, calls };
}

// ── Helper: build a minimal test event ──────────────────────────────────────

function makeMetaEvent(): ConversationTurnEvent {
  return {
    providerId: 'meta',
    sessionId: 'meta:test-thread-1',
    channel: 'meta_messenger',
    recipientId: 'sender-123',
    role: 'customer',
    text: 'Hello, I need a plumber',
    timestamp: Date.now(),
  };
}

// ── Tests ────────────────────────────────────────────────────────────────────

describe('buildMetaServerOpts', () => {
  test('wires metaFanOutSink as onConversationTurn', () => {
    const { sink } = makeMockSink();

    const args: BuildMetaServerOptsArgs = {
      metaFanOutSink: sink,
      verifyToken: 'test-verify-token',
      pageAccessToken: 'test-page-token',
      llm: null,
    };

    const opts = buildMetaServerOpts(args);

    expect(opts.onConversationTurn).toBe(sink);
  });

  test('metaFanOutSink passed as onConversationTurn is callable and receives events', async () => {
    const { sink, calls } = makeMockSink();

    const args: BuildMetaServerOptsArgs = {
      metaFanOutSink: sink,
      verifyToken: 'test-verify-token',
      pageAccessToken: 'test-page-token',
      llm: null,
    };

    const opts = buildMetaServerOpts(args);

    const event = makeMetaEvent();
    await opts.onConversationTurn!(event);

    expect(calls).toHaveLength(1);
    expect(calls[0]).toBe(event);
  });

  test('constructs MetaProvider with the verify token', () => {
    const { sink } = makeMockSink();

    const args: BuildMetaServerOptsArgs = {
      metaFanOutSink: sink,
      verifyToken: 'my-secret-verify-token',
      pageAccessToken: '',
      llm: null,
    };

    const opts = buildMetaServerOpts(args);

    expect(opts.provider).toBeInstanceOf(MetaProvider);
    // Challenge verification uses the token internally — verify via handle()
    // (challenge GET with the correct token should echo back the challenge).
    const server = new MetaWebhookServer(opts);
    expect(server).toBeDefined();
  });

  test('sets pageAccessToken on opts', () => {
    const { sink } = makeMockSink();

    const opts = buildMetaServerOpts({
      metaFanOutSink: sink,
      verifyToken: 'tok',
      pageAccessToken: 'my-page-access-token',
      llm: null,
    });

    expect(opts.pageAccessToken).toBe('my-page-access-token');
  });

  test('injects no-op LLM stub when llm is null (server constructs without crash)', () => {
    const { sink } = makeMockSink();

    const opts = buildMetaServerOpts({
      metaFanOutSink: sink,
      verifyToken: '',
      pageAccessToken: '',
      llm: null,
    });

    // llm must be non-null (MetaWebhookServer requires it)
    expect(opts.llm).toBeDefined();
    expect(opts.llm).not.toBeNull();
  });

  test('no-op LLM stub returns zero-confidence extraction', async () => {
    const { sink } = makeMockSink();

    const opts = buildMetaServerOpts({
      metaFanOutSink: sink,
      verifyToken: '',
      pageAccessToken: '',
      llm: null,
    });

    const result = await opts.llm.extract({ prompt: 'extract this', schema: {} });
    expect(result.confidence).toBe(0);
    expect(result.raw).toBe('');
  });

  test('passes through a real LLM adapter when provided', () => {
    const { sink } = makeMockSink();

    const realLlm = {
      async extract<T>(_o: { prompt: string; schema: object }) {
        return { payload: {} as T, confidence: 0.9, raw: '{}' };
      },
    };

    const opts = buildMetaServerOpts({
      metaFanOutSink: sink,
      verifyToken: 'tok',
      pageAccessToken: 'pat',
      llm: realLlm,
    });

    expect(opts.llm).toBe(realLlm);
  });

  test('MetaWebhookServer can be constructed with opts from buildMetaServerOpts', () => {
    const { sink } = makeMockSink();

    const opts = buildMetaServerOpts({
      metaFanOutSink: sink,
      verifyToken: 'verify-token',
      pageAccessToken: 'page-access-token',
      llm: null,
    });

    // This should not throw — it exercises the full option pass-through.
    expect(() => new MetaWebhookServer(opts)).not.toThrow();
  });

  test('MetaWebhookServer challenge GET echoes back with correct verify token', async () => {
    const { sink } = makeMockSink();

    const opts = buildMetaServerOpts({
      metaFanOutSink: sink,
      verifyToken: 'my-verify-token',
      pageAccessToken: '',
      llm: null,
    });

    const server = new MetaWebhookServer(opts);
    const req = new Request(
      'http://localhost:3002/meta/webhook?hub.mode=subscribe&hub.verify_token=my-verify-token&hub.challenge=echo-me-back',
      { method: 'GET' },
    );
    const resp = await server.handle(req);
    expect(resp.status).toBe(200);
    expect(await resp.text()).toBe('echo-me-back');
  });

  test('MetaWebhookServer challenge GET returns 403 with wrong verify token', async () => {
    const { sink } = makeMockSink();

    const opts = buildMetaServerOpts({
      metaFanOutSink: sink,
      verifyToken: 'correct-token',
      pageAccessToken: '',
      llm: null,
    });

    const server = new MetaWebhookServer(opts);
    const req = new Request(
      'http://localhost:3002/meta/webhook?hub.mode=subscribe&hub.verify_token=wrong-token&hub.challenge=anything',
      { method: 'GET' },
    );
    const resp = await server.handle(req);
    expect(resp.status).toBe(403);
  });
});

describe('buildLlmFromEnv', () => {
  test('returns null when no LLM env vars are set', () => {
    // Unset all relevant env vars for this test
    const saved = {
      OLLAMA_BASE_URL: process.env.OLLAMA_BASE_URL,
      OLLAMA_ENABLE: process.env.OLLAMA_ENABLE,
      ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
      OPENROUTER_API_KEY: process.env.OPENROUTER_API_KEY,
    };

    delete process.env.OLLAMA_BASE_URL;
    delete process.env.OLLAMA_ENABLE;
    delete process.env.ANTHROPIC_API_KEY;
    delete process.env.OPENROUTER_API_KEY;

    try {
      const llm = buildLlmFromEnv();
      expect(llm).toBeNull();
    } finally {
      // Restore
      if (saved.OLLAMA_BASE_URL !== undefined) process.env.OLLAMA_BASE_URL = saved.OLLAMA_BASE_URL;
      if (saved.OLLAMA_ENABLE !== undefined) process.env.OLLAMA_ENABLE = saved.OLLAMA_ENABLE;
      if (saved.ANTHROPIC_API_KEY !== undefined) process.env.ANTHROPIC_API_KEY = saved.ANTHROPIC_API_KEY;
      if (saved.OPENROUTER_API_KEY !== undefined) process.env.OPENROUTER_API_KEY = saved.OPENROUTER_API_KEY;
    }
  });

  test('returns an LLMAdapter when OPENROUTER_API_KEY is set', () => {
    const saved = process.env.OPENROUTER_API_KEY;
    process.env.OPENROUTER_API_KEY = 'test-key-for-router';

    try {
      const llm = buildLlmFromEnv();
      expect(llm).not.toBeNull();
      expect(llm).toBeDefined();
    } finally {
      if (saved !== undefined) {
        process.env.OPENROUTER_API_KEY = saved;
      } else {
        delete process.env.OPENROUTER_API_KEY;
      }
    }
  });
});

describe('serve command integration: sink wiring via buildMetaServerOpts', () => {
  test('onConversationTurn passed to MetaWebhookServer is the exact metaFanOutSink', async () => {
    // This is the core contract of D-OJ-conv-legacy-serve:
    // bootstrap().metaFanOutSink MUST be passed as onConversationTurn.
    const { sink: metaFanOutSink, calls } = makeMockSink();

    const opts = buildMetaServerOpts({
      metaFanOutSink,
      verifyToken: 'tok',
      pageAccessToken: '',
      llm: null,
    });

    expect(opts.onConversationTurn).toBe(metaFanOutSink);

    // Confirm the sink is callable end-to-end through the opts
    const event = makeMetaEvent();
    await opts.onConversationTurn!(event);
    expect(calls).toHaveLength(1);
    expect(calls[0].providerId).toBe('meta');
    expect(calls[0].sessionId).toBe('meta:test-thread-1');
  });

  test('opts constructed correctly when DATABASE_URL is not set (gated no-op)', () => {
    // This test verifies the command is safe to deploy before DATABASE_URL is set.
    // The DATABASE_URL gating lives inside makeMetaFanOutSink (base branch #570),
    // not in buildMetaServerOpts — this test just ensures buildMetaServerOpts
    // completes without error.
    const savedDbUrl = process.env.DATABASE_URL;
    delete process.env.DATABASE_URL;

    try {
      const { sink } = makeMockSink();
      expect(() =>
        buildMetaServerOpts({
          metaFanOutSink: sink,
          verifyToken: '',
          pageAccessToken: '',
          llm: null,
        }),
      ).not.toThrow();
    } finally {
      if (savedDbUrl !== undefined) process.env.DATABASE_URL = savedDbUrl;
    }
  });
});

```
