---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/__tests__/brain-submit-storage.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.511291+00:00
---

# cartridges/oddjobz/brain/src/__tests__/brain-submit-storage.test.ts

```ts
/**
 * P3.2 brain-submit StorageAdapter conformance.
 *
 * Pins the envelope shape (intent_cells_handler.zig parseEnvelope +
 * docs/spec/oddjobz-intent-cell-v1.md) and the /api/v1/repl request
 * contract (repl_http.zig: POST, Bearer auth, {"cmd":...}; repl.zig:
 * submit-intent-cell --envelope <base64-json>). Mock transport ⇒
 * ZERO live change; the real POST is P3.5 (operator-approved).
 */

import { describe, expect, test } from 'bun:test';
import {
  buildIntentCellEnvelope,
  submitCellReplBody,
  makeBrainSubmitStorageAdapter,
  ENVELOPE_KIND,
  type EnvelopeContext,
  type FetchLike,
} from '../conversation/brain-submit-storage.js';

const ctx: EnvelopeContext = {
  hatId: 'a'.repeat(64),
  certId: 'cert-child-1',
  correlationId: '9f3d981d-c1a4-45c5-b6da-7caa56341e65',
  kernelResult: { ok: true, opcount: 1, stackDepth: 0, gasUsed: 0, errorKind: null },
  originalIntent: {
    summary: 'accept_rom for a fence job',
    action: 'accept_rom',
    taxonomyJson: JSON.stringify({ what: 'oddjobz.lead', how: 'accept_rom', why: 'intake' }),
    targetJson: '{"costMin":40000,"costMax":60000,"currency":"AUD"}',
  },
};
const opcode = new Uint8Array([0xc3, 0x05, 0x51]);

describe('buildIntentCellEnvelope — spec conformance', () => {
  test('kind/version pinned; opcodeBytes base64; fields threaded', () => {
    const env = buildIntentCellEnvelope('cell-000003-c30551-abcd1234', opcode, ctx);
    expect(env.kind).toBe(ENVELOPE_KIND);
    expect(env.kind).toBe('oddjobz.intent_cell.v1');
    expect(env.version).toBe(1);
    expect(env.cellId).toBe('cell-000003-c30551-abcd1234');
    expect(env.opcodeBytes).toBe(Buffer.from(opcode).toString('base64'));
    expect(Buffer.from(env.opcodeBytes, 'base64')).toEqual(Buffer.from(opcode));
    expect(env.hatId).toBe('a'.repeat(64));
    expect(env.certId).toBe('cert-child-1');
    expect(env.correlationId).toBe(ctx.correlationId);
    expect(env.kernelResult).toEqual(ctx.kernelResult);
    expect(env.originalIntent.action).toBe('accept_rom');
    expect(JSON.parse(env.originalIntent.targetJson!).costMin).toBe(40000);
  });

  test('empty cellId rejected (parseEnvelope missing_or_invalid_cell_id)', () => {
    expect(() => buildIntentCellEnvelope('', opcode, ctx)).toThrow(/cellId required/);
  });
});

describe('submitCellReplBody — REPL wire contract', () => {
  test('{"cmd":"submit-intent-cell --envelope <b64>"} round-trips', () => {
    const env = buildIntentCellEnvelope('cell-x', opcode, ctx);
    const body = JSON.parse(submitCellReplBody(env)) as { cmd: string };
    const m = /^submit-intent-cell --envelope (.+)$/.exec(body.cmd);
    expect(m).not.toBeNull();
    const decoded = JSON.parse(Buffer.from(m![1]!, 'base64').toString('utf8'));
    expect(decoded.kind).toBe('oddjobz.intent_cell.v1');
    expect(decoded.cellId).toBe('cell-x');
  });
});

describe('makeBrainSubmitStorageAdapter — POST contract (mock transport)', () => {
  test('POSTs /api/v1/repl with Bearer auth + the submit cmd body', async () => {
    let seen: { url: string; init: Parameters<FetchLike>[1] } | null = null;
    const fetchFn: FetchLike = async (url, init) => {
      seen = { url, init };
      return { status: 200, text: async () => '{"ok":true,"cellId":"cell-x"}' };
    };
    const adapter = makeBrainSubmitStorageAdapter({
      replUrl: 'https://oddjobtodd.info/api/v1/repl',
      bearerToken: 'deadbeef'.repeat(8),
      envelopeFor: () => ({ ...ctx, cellId: 'cell-x' }),
      fetchFn,
    });
    await adapter.write('cells/cell-x', opcode);
    expect(seen!.url).toBe('https://oddjobtodd.info/api/v1/repl');
    expect(seen!.init.method).toBe('POST');
    expect(seen!.init.headers.Authorization).toBe(`Bearer ${'deadbeef'.repeat(8)}`);
    const cmd = (JSON.parse(seen!.init.body) as { cmd: string }).cmd;
    expect(cmd.startsWith('submit-intent-cell --envelope ')).toBe(true);
  });

  test('non-2xx ⇒ throws (pipeline routes as write failure, no silent drop)', async () => {
    const adapter = makeBrainSubmitStorageAdapter({
      replUrl: 'u',
      bearerToken: 't',
      envelopeFor: () => ({ ...ctx, cellId: 'c' }),
      fetchFn: async () => ({ status: 401, text: async () => 'unauthorized' }),
    });
    await expect(adapter.write('k', opcode)).rejects.toThrow(/HTTP 401/);
  });

  test('typed rejection envelope in 200 body ⇒ throws (not a silent success)', async () => {
    const adapter = makeBrainSubmitStorageAdapter({
      replUrl: 'u',
      bearerToken: 't',
      envelopeFor: () => ({ ...ctx, cellId: 'c' }),
      fetchFn: async () => ({
        status: 200,
        text: async () => '{"error_kind":"envelope_invalid","hint":"bad"}',
      }),
    });
    await expect(adapter.write('k', opcode)).rejects.toThrow(/rejected/);
  });
});

```
