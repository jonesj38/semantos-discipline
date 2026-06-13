---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/chess-brain-proxy.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.671305+00:00
---

# cartridges/wallet-headers/brain/test/chess-brain-proxy.spec.ts

```ts
// Wallet-side chess.dispatch proxy — param validation + a fake-WebSocket
// roundtrip that exercises the JSON-RPC plumbing without touching a real
// brain.

import { describe, expect, test } from 'bun:test';
import {
  validateDispatchParams,
  dispatchChessVerb,
  type ChessDispatchParams,
} from '../src/chess-brain-proxy';

const FAKE_BEARER = '0123456789abcdef'.repeat(4); // 64 hex chars
const FAKE_BRAIN_URL = 'wss://brain.example/api/v1/wallet';

describe('validateDispatchParams', () => {
  test('accepts a well-formed request', () => {
    expect(validateDispatchParams({
      verb: 'create_game',
      params: { gameId: 'g1' },
      bearer: FAKE_BEARER,
      brainUrl: FAKE_BRAIN_URL,
    })).toBeNull();
  });

  test('rejects missing verb', () => {
    expect(validateDispatchParams({ params: {}, bearer: FAKE_BEARER, brainUrl: FAKE_BRAIN_URL }))
      .toMatch(/verb/);
  });

  test('rejects non-hex bearer', () => {
    expect(validateDispatchParams({
      verb: 'create_game',
      params: {},
      bearer: 'not-hex',
      brainUrl: FAKE_BRAIN_URL,
    })).toMatch(/bearer/);
  });

  test('rejects bearer wrong length', () => {
    expect(validateDispatchParams({
      verb: 'create_game',
      params: {},
      bearer: 'abcd',
      brainUrl: FAKE_BRAIN_URL,
    })).toMatch(/bearer/);
  });

  test('rejects http(s) brain URL', () => {
    expect(validateDispatchParams({
      verb: 'create_game',
      params: {},
      bearer: FAKE_BEARER,
      brainUrl: 'https://brain.example/api/v1/wallet',
    })).toMatch(/brainUrl/);
  });

  test('rejects params: null', () => {
    expect(validateDispatchParams({
      verb: 'create_game',
      params: null as unknown as Record<string, unknown>,
      bearer: FAKE_BEARER,
      brainUrl: FAKE_BRAIN_URL,
    })).toMatch(/params/);
  });

  test('rejects malformed verb', () => {
    expect(validateDispatchParams({
      verb: 'has spaces',
      params: {},
      bearer: FAKE_BEARER,
      brainUrl: FAKE_BRAIN_URL,
    })).toMatch(/verb/);
  });
});

describe('dispatchChessVerb', () => {
  // Minimal in-memory WebSocket fake — enough surface to satisfy the
  // proxy's addEventListener / send / close calls.
  function makeFakeSocket(opts: {
    /** Server-side handler: receives the sent payload, returns the reply. */
    onSend: (payload: { jsonrpc: string; id: number; method: string; params: unknown }) => unknown;
    /** Optional delay before reply (ms). */
    delayMs?: number;
  }) {
    interface Handler { (ev: unknown): void }
    const listeners: Record<string, Handler[]> = { open: [], message: [], error: [], close: [] };
    const ws = {
      readyState: 1,
      addEventListener(name: string, cb: Handler) { (listeners[name] ??= []).push(cb); },
      send(text: string) {
        const sent = JSON.parse(text);
        setTimeout(() => {
          const reply = opts.onSend(sent);
          for (const cb of listeners.message ?? []) cb({ data: JSON.stringify(reply) });
        }, opts.delayMs ?? 0);
      },
      close() { for (const cb of listeners.close ?? []) cb({}); },
    } as unknown as WebSocket;
    setTimeout(() => {
      for (const cb of listeners.open ?? []) cb({});
    }, 0);
    return ws;
  }

  test('roundtrips a create_game call', async () => {
    let captured: { method?: string; params?: Record<string, unknown> } = {};
    const url = 'wss://brain.example/api/v1/wallet';
    const params: ChessDispatchParams = {
      verb: 'create_game',
      params: { gameId: 'g1', creator: 'alice', color: 'white', stakeSats: 100, clockMs: 600_000 },
      brainUrl: url,
      bearer: FAKE_BEARER,
      timeoutMs: 1_000,
    };
    const factoryUrl: string[] = [];
    const out = await dispatchChessVerb(params, (u) => {
      factoryUrl.push(u);
      return makeFakeSocket({
        onSend(sent) {
          captured = { method: sent.method, params: sent.params as Record<string, unknown> };
          return { jsonrpc: '2.0', id: sent.id, result: { ok: true, gameId: 'g1', status: 'waiting' } };
        },
      });
    });
    expect(out.error).toBeUndefined();
    expect((out.result as { gameId?: string }).gameId).toBe('g1');
    expect(captured.method).toBe('verb.dispatch');
    expect(captured.params).toMatchObject({
      extensionId: 'chess',
      verb: 'create_game',
      params: { gameId: 'g1' },
    });
    // Bearer rides on the URL via ?bearer=
    expect(factoryUrl[0]).toContain('bearer=' + FAKE_BEARER);
  });

  test('surfaces brain JSON-RPC errors', async () => {
    const out = await dispatchChessVerb(
      {
        verb: 'submit_move',
        params: { gameId: 'g1', player: 'alice', uci: 'e2e5' },
        brainUrl: FAKE_BRAIN_URL,
        bearer: FAKE_BEARER,
        timeoutMs: 1_000,
      },
      () => makeFakeSocket({
        onSend(sent) {
          return { jsonrpc: '2.0', id: sent.id, error: { code: -32602, message: 'walker rejected params' } };
        },
      }),
    );
    expect(out.result).toBeUndefined();
    expect(out.error).toEqual({ code: -32602, message: 'walker rejected params' });
  });

  test('times out if the socket never replies', async () => {
    const out = await dispatchChessVerb(
      {
        verb: 'get_game',
        params: { gameId: 'g1' },
        brainUrl: FAKE_BRAIN_URL,
        bearer: FAKE_BEARER,
        timeoutMs: 50,
      },
      () => makeFakeSocket({ onSend: () => ({}), delayMs: 500 }),
    );
    expect(out.error?.message).toMatch(/timeout/);
  });

  test('appends bearer with & when the brain URL already has a query', async () => {
    const url = 'wss://brain.example/api/v1/wallet?debug=1';
    const factoryUrl: string[] = [];
    await dispatchChessVerb(
      {
        verb: 'get_game',
        params: { gameId: 'g1' },
        brainUrl: url,
        bearer: FAKE_BEARER,
        timeoutMs: 1_000,
      },
      (u) => {
        factoryUrl.push(u);
        return makeFakeSocket({ onSend: (s) => ({ jsonrpc: '2.0', id: s.id, result: { ok: true } }) });
      },
    );
    expect(factoryUrl[0]).toContain('?debug=1&bearer=');
  });
});

```
