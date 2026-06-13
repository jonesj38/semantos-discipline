---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/brain-rpc-cell-writer.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.148977+00:00
---

# runtime/legacy-ingest/src/__tests__/brain-rpc-cell-writer.test.ts

```ts
/**
 * BrainRpcCellWriter tests — D-DOG.1.0c Phase 2B.1.
 *
 * The writer is the TS-side `RatificationOrchestrator.writeCell`
 * implementation that POSTs SIRPrograms to brain's
 * `oddjobz.ratify_proposal` JSON-RPC verb. These tests stand a
 * Bun.serve()-backed in-process WS server that mimics the Semantos Brain wire
 * shape (Phase 2A.4 graph-shaped `cellIds`), then drive the writer
 * against it.
 *
 * Coverage:
 *   • happy path — request shape goes out correct, graph cellIds come back
 *   • payload_hint forwards the Tier 1.7 enriched fields (B.1.a)
 *   • payload_hint omits Tier 1.7 fields when absent (legacy proposals)
 *   • response parser yields the JSON-encoded cellIds graph object (B.1.b)
 *   • timeout — server never responds; writer surfaces a typed error
 *   • RPC error response — writer surfaces it as BrainRpcCellWriterError
 *   • protocol error (non-JSON, missing cellIds) — writer rejects
 *   • empty graph — writer returns the stringified empty graph (no-op SIR path)
 */

import { afterEach, describe, expect, test, spyOn } from 'bun:test';
import { BrainRpcCellWriter, BrainRpcCellWriterError, derivePayloadHint } from '../cell-writer/brain-rpc';
import type { Proposal } from '../extractor/types';
import type { SIRProgram } from '@semantos/semantos-sir';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// ── A trivial SIR + Proposal builder for the writer tests ────────

function makeProposal(overrides: Partial<Proposal> = {}): Proposal {
  const program = makeProgram('create_lead');
  return {
    proposalId: 'prop-test-001',
    confidence: 0.9,
    status: 'pending',
    provenance: {
      providerId: 'gmail',
      providerItemId: 'item-001',
      fetchedAt: 1_700_000_000_000,
      extractorVersion: 'email-rfc822-v0.3',
      promptHash: 'h0',
    },
    extractedAt: 1_700_000_001_000,
    program,
    summary: 'AcmeCorp wants a deck rebuild',
    ...overrides,
  };
}

function makeProgram(action: string): SIRProgram {
  return {
    primaryNodeId: '$s0',
    programGovernance: {} as any,
    nodes: [
      {
        id: '$s0',
        category: { lexicon: 'jural', category: 'declaration' } as any,
        taxonomy: {} as any,
        identity: {} as any,
        governance: {} as any,
        action,
        constraint: { kind: 'literal', value: 'true' } as any,
        provenance: {
          source: 'inferred',
          confidence: 0.9,
          expressedAt: '2026-05-03T00:00:00Z',
          trustAtExpression: 'cosmetic',
        } as any,
      },
    ],
  };
}

// ── In-process Bun WS stub server ─────────────────────────────────
//
// `behaviour` decides how each incoming JSON-RPC request is handled:
//   'happy'         → respond with cellIds: a one-job graph
//   'happy-empty'   → respond with cellIds: an empty graph
//   'happy-graph'   → respond with cellIds: a full site/customers/job/attachments graph
//   'rpc-error'     → respond with an error envelope (-32000)
//   'bad-protocol'  → respond with malformed JSON (no cellIds key)
//   'silent'        → never respond (forces timeout)
//
// Returns { url, stop, lastRequest }.

interface StubServer {
  url: string;
  stop: () => void;
  lastRequest: () => Record<string, unknown> | null;
}

function startStubServer(
  behaviour:
    | 'happy'
    | 'happy-empty'
    | 'happy-graph'
    | 'rpc-error'
    | 'bad-protocol'
    | 'silent',
): StubServer {
  let last: Record<string, unknown> | null = null;
  const srv = Bun.serve({
    port: 0,
    fetch(req, server) {
      if (server.upgrade(req)) return undefined;
      return new Response('not a ws upgrade', { status: 400 });
    },
    websocket: {
      open() {
        // no-op
      },
      message(ws, raw) {
        const text = typeof raw === 'string' ? raw : new TextDecoder().decode(raw as ArrayBuffer);
        let parsed: Record<string, unknown> | null = null;
        try {
          parsed = JSON.parse(text);
        } catch {
          // Forward as-is for protocol checks
        }
        last = parsed;
        if (!parsed) {
          ws.send('not even json');
          return;
        }
        const id = parsed.id;
        switch (behaviour) {
          case 'happy':
            ws.send(JSON.stringify({
              jsonrpc: '2.0',
              id,
              result: {
                proposal_id: ((parsed.params as Record<string, unknown> | undefined)?.proposal_id as string) ?? 'unknown',
                cellIds: {
                  site: null,
                  customers: [],
                  job: 'job-fresh-001',
                  attachments: [],
                },
                persistedAt: 1_700_000_002,
              },
            }));
            break;
          case 'happy-empty':
            ws.send(JSON.stringify({
              jsonrpc: '2.0',
              id,
              result: {
                proposal_id: 'p',
                cellIds: { site: null, customers: [], job: null, attachments: [] },
                persistedAt: 1_700_000_003,
              },
            }));
            break;
          case 'happy-graph':
            ws.send(JSON.stringify({
              jsonrpc: '2.0',
              id,
              result: {
                proposal_id: ((parsed.params as Record<string, unknown> | undefined)?.proposal_id as string) ?? 'unknown',
                cellIds: {
                  site: 'site-aaaa',
                  customers: ['cust-bbbb', 'cust-cccc'],
                  job: 'job-dddd',
                  attachments: ['att-eeee'],
                },
                persistedAt: 1_700_000_004,
              },
            }));
            break;
          case 'rpc-error':
            ws.send(JSON.stringify({
              jsonrpc: '2.0',
              id,
              error: { code: -32000, message: 'invalid sir_program' },
            }));
            break;
          case 'bad-protocol':
            ws.send(JSON.stringify({
              jsonrpc: '2.0',
              id,
              result: { /* no cellIds graph */ proposal_id: 'p' },
            }));
            break;
          case 'silent':
            // never respond
            break;
        }
      },
    },
  });
  const port = srv.port;
  const host = srv.hostname ?? '127.0.0.1';
  // Bun.serve returns "::1" for IPv6 default; ws://[::1]:port is fine
  // but more portable to wrap in brackets only when needed.
  const hostFmt = host.includes(':') ? `[${host}]` : host;
  return {
    url: `ws://${hostFmt}:${port}/wallet`,
    stop: () => srv.stop(true),
    lastRequest: () => last,
  };
}

// ── tests ──────────────────────────────────────────────────────────

describe('BrainRpcCellWriter', () => {
  test('happy path: posts the SIRProgram and returns the cellIds graph as a JSON-encoded string', async () => {
    const stub = startStubServer('happy');
    try {
      const writer = new BrainRpcCellWriter({ wsRpcUrl: stub.url, timeoutMs: 5000 });
      const proposal = makeProposal();
      const cellId = await writer.write({ program: proposal.program, proposal });
      // D-DOG.1.0c Phase 2B.1 — the receipt's `cellId` field carries
      // the JSON-encoded `cellIds` graph object, not a flat array.
      const decoded = JSON.parse(cellId) as Record<string, unknown>;
      expect(decoded.site).toBeNull();
      expect(decoded.job).toBe('job-fresh-001');
      expect(decoded.customers).toEqual([]);
      expect(decoded.attachments).toEqual([]);
      const req = stub.lastRequest();
      expect(req).not.toBeNull();
      expect(req!.method).toBe('ratify.submit');
      const params = req!.params as Record<string, unknown>;
      expect(params.namespace).toBe('oddjobz');
      expect(params.proposal_id).toBe('prop-test-001');
      expect(params.sir_program).toBeDefined();
      const hint = params.payload_hint as Record<string, unknown>;
      expect(hint.customer_name).toBe('AcmeCorp wants a deck rebuild');
      expect(hint.source_provider_id).toBe('gmail');
      // point_of_contact is always present in the hint envelope; '' when
      // the proposal didn't carry one (older proposals pre-2026-05-04).
      expect(hint.point_of_contact).toBe('');
    } finally {
      stub.stop();
    }
  });

  test('happy path: parses a full graph response (site + customers + job + attachments)', async () => {
    const stub = startStubServer('happy-graph');
    try {
      const writer = new BrainRpcCellWriter({ wsRpcUrl: stub.url, timeoutMs: 5000 });
      const proposal = makeProposal();
      const cellId = await writer.write({ program: proposal.program, proposal });
      const decoded = JSON.parse(cellId) as Record<string, unknown>;
      expect(decoded).toEqual({
        site: 'site-aaaa',
        customers: ['cust-bbbb', 'cust-cccc'],
        job: 'job-dddd',
        attachments: ['att-eeee'],
      });
    } finally {
      stub.stop();
    }
  });

  test('happy path: forwards proposal.pointOfContact through payload_hint.point_of_contact', async () => {
    const stub = startStubServer('happy');
    try {
      const writer = new BrainRpcCellWriter({ wsRpcUrl: stub.url, timeoutMs: 5000 });
      const proposal = makeProposal({ pointOfContact: 'Robert James Realty' });
      await writer.write({ program: proposal.program, proposal });
      const req = stub.lastRequest();
      const hint = (req!.params as Record<string, unknown>).payload_hint as Record<string, unknown>;
      expect(hint.point_of_contact).toBe('Robert James Realty');
      // legacy customer_name (summary first-line) is still emitted in
      // the same envelope so older brain handlers (or the FS fallback)
      // can fall through when the new field is empty.
      expect(hint.customer_name).toBe('AcmeCorp wants a deck rebuild');
    } finally {
      stub.stop();
    }
  });

  test('returns the stringified empty graph when brain handler responds with no cells (no-op SIR)', async () => {
    const stub = startStubServer('happy-empty');
    try {
      const writer = new BrainRpcCellWriter({ wsRpcUrl: stub.url, timeoutMs: 5000 });
      const proposal = makeProposal({ program: makeProgram('noop') });
      const cellId = await writer.write({ program: proposal.program, proposal });
      const decoded = JSON.parse(cellId) as Record<string, unknown>;
      expect(decoded).toEqual({ site: null, customers: [], job: null, attachments: [] });
    } finally {
      stub.stop();
    }
  });

  test('surfaces brain-side RPC errors as BrainRpcCellWriterError', async () => {
    const stub = startStubServer('rpc-error');
    try {
      const writer = new BrainRpcCellWriter({ wsRpcUrl: stub.url, timeoutMs: 5000 });
      const proposal = makeProposal();
      let caught: unknown = null;
      try {
        await writer.write({ program: proposal.program, proposal });
      } catch (err) {
        caught = err;
      }
      expect(caught).toBeInstanceOf(BrainRpcCellWriterError);
      const err = caught as BrainRpcCellWriterError;
      expect(err.code).toBe('rpc_error');
      expect(err.message).toContain('invalid sir_program');
    } finally {
      stub.stop();
    }
  });

  test('surfaces missing cellIds as a protocol error', async () => {
    const stub = startStubServer('bad-protocol');
    try {
      const writer = new BrainRpcCellWriter({ wsRpcUrl: stub.url, timeoutMs: 5000 });
      const proposal = makeProposal();
      let caught: unknown = null;
      try {
        await writer.write({ program: proposal.program, proposal });
      } catch (err) {
        caught = err;
      }
      expect(caught).toBeInstanceOf(BrainRpcCellWriterError);
      const err = caught as BrainRpcCellWriterError;
      expect(err.code).toBe('protocol_error');
    } finally {
      stub.stop();
    }
  });

  test('times out cleanly when brain never responds', async () => {
    const stub = startStubServer('silent');
    try {
      const writer = new BrainRpcCellWriter({ wsRpcUrl: stub.url, timeoutMs: 200 });
      const proposal = makeProposal();
      let caught: unknown = null;
      try {
        await writer.write({ program: proposal.program, proposal });
      } catch (err) {
        caught = err;
      }
      expect(caught).toBeInstanceOf(BrainRpcCellWriterError);
      const err = caught as BrainRpcCellWriterError;
      expect(err.code).toBe('timeout');
    } finally {
      stub.stop();
    }
  });
});

// ── FS fallback tests (Bug B unblock) ────────────────────────────────
//
// When `fsFallbackDataDir` is set on BrainRpcCellWriterOpts, ANY WSS-path
// failure (construct error, transport error, server-side 503 surfacing
// as ws_closed) routes the write through a direct JSONL append to
// `<fsFallbackDataDir>/oddjobz/jobs.jsonl`. Same on-disk shape as
// brain's `JobsStore.appendCreated`, idempotent on proposal_id via a
// sidecar `legacy-ratifications.jsonl` index.

/**
 * WebSocket constructor stub that throws synchronously from `new ...`.
 * Mirrors the failure mode you get when the WSS URL is malformed or
 * the host can't even start a connect attempt.
 */
class ThrowingWebSocket {
  constructor() {
    throw new Error('mock construct failure');
  }
}

/**
 * WebSocket constructor stub that fires `onerror` then `onclose`
 * asynchronously, mirroring what the runtime does on a 503 upgrade
 * failure (server returns HTTP 503 instead of `101 Switching
 * Protocols`, ws layer surfaces it as an error + close with code 1002).
 */
class ErroringWebSocket {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  onopen: ((this: any, ev: Event) => any) | null = null;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  onmessage: ((this: any, ev: MessageEvent) => any) | null = null;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  onerror: ((this: any, ev: Event) => any) | null = null;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  onclose: ((this: any, ev: CloseEvent) => any) | null = null;
  constructor(_url: string) {
    queueMicrotask(() => {
      // Fire onerror first — the writer's `ws.onerror` clears the
      // timeout and rejects with code `ws_error`. The fallback then
      // catches the throw and routes to FS.
      this.onerror?.(new Event('error'));
    });
  }
  send(_data: string): void { /* never reached */ }
  close(): void { /* swallow */ }
}

describe('BrainRpcCellWriter — FS fallback', () => {
  let tmpDirs: string[] = [];

  function makeTmpDir(): string {
    const dir = mkdtempSync(join(tmpdir(), 'brain-rpc-fallback-'));
    tmpDirs.push(dir);
    return dir;
  }

  afterEach(() => {
    for (const dir of tmpDirs) {
      try { rmSync(dir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
    tmpDirs = [];
  });

  test('FS fallback fires on WS construct error and writes the full graph (site + customer + job)', async () => {
    // D-DOG.1.0c Phase 2B.2 — the FS fallback now writes a graph of
    // cells to four typed JSONL files, mirroring what the Zig
    // oddjobz_ratify_handler.zig handler produces over WSS.
    const dir = makeTmpDir();
    const warnSpy = spyOn(console, 'warn').mockImplementation(() => {});
    try {
      const writer = new BrainRpcCellWriter({
        wsRpcUrl: 'ws://localhost:1/never',
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        webSocketCtor: ThrowingWebSocket as any,
        fsFallbackDataDir: dir,
        fsFallbackHatId: 'hat-fallback-1',
      });
      const proposal = makeProposal({ proposalId: 'prop-fb-construct' });
      const cellId = await writer.write({ program: proposal.program, proposal });
      const decoded = JSON.parse(cellId) as Record<string, unknown>;
      // Site + (synthesised) customer + job all minted; no attachment
      // because the proposal carries no sourceAttachmentPath.
      expect(typeof decoded.site).toBe('string');
      expect((decoded.site as string).length).toBe(64);
      expect(Array.isArray(decoded.customers)).toBe(true);
      expect((decoded.customers as string[]).length).toBe(1);
      expect(typeof decoded.job).toBe('string');
      expect((decoded.job as string).length).toBe(64);
      expect(decoded.attachments).toEqual([]);

      // The jobs.jsonl line should match the v2 shape (siteRef +
      // customerRefs + the v1-prefix carry).
      const jobsPath = join(dir, 'oddjobz', 'jobs.jsonl');
      expect(existsSync(jobsPath)).toBe(true);
      const jobsLines = readFileSync(jobsPath, 'utf8').split('\n').filter(l => l.length > 0);
      expect(jobsLines.length).toBe(1);
      const jobRow = JSON.parse(jobsLines[0]) as Record<string, unknown>;
      expect(jobRow.kind).toBe('created');
      expect(jobRow.state).toBe('lead');
      expect(typeof jobRow.id).toBe('string');
      expect(jobRow.customer_name).toBe('AcmeCorp wants a deck rebuild');
      expect(typeof jobRow.created_at).toBe('string');
      expect(jobRow.scheduled_at).toBe('');
      expect(typeof jobRow.ts).toBe('number');
      expect(typeof jobRow.typeHash).toBe('string');
      expect((jobRow.typeHash as string).length).toBe(64);
      expect(typeof jobRow.siteRef).toBe('string');
      expect((jobRow.siteRef as string).length).toBe(64);
      expect(jobRow.siteRef).toBe(decoded.site);
      expect(Array.isArray(jobRow.customerRefs)).toBe(true);
      expect((jobRow.customerRefs as unknown[]).length).toBe(1);
      const cref0 = (jobRow.customerRefs as Array<Record<string, unknown>>)[0]!;
      expect(typeof cref0.cellId).toBe('string');
      expect(typeof cref0.role).toBe('string');
      expect(cref0.primary).toBe(true);
      expect(jobRow.attachmentRefs).toEqual([]);
      expect(jobRow.signedBy).toBeNull();

      // sites.jsonl populates with the v2 site row shape.
      const sitesPath = join(dir, 'oddjobz', 'sites.jsonl');
      expect(existsSync(sitesPath)).toBe(true);
      const sitesLines = readFileSync(sitesPath, 'utf8').split('\n').filter(l => l.length > 0);
      expect(sitesLines.length).toBe(1);
      const siteRow = JSON.parse(sitesLines[0]) as Record<string, unknown>;
      expect(siteRow.kind).toBe('created');
      expect(typeof siteRow.cellId).toBe('string');
      expect((siteRow.cellId as string).length).toBe(64);
      expect(siteRow.cellId).toBe(decoded.site);
      expect(typeof siteRow.normalisedAddress).toBe('string');
      expect(typeof siteRow.lookupKey).toBe('string');
      expect(typeof siteRow.fullAddress).toBe('string');
      expect(siteRow.signedBy).toBeNull();

      // customers.jsonl populates with the v2 customer row shape.
      const customersPath = join(dir, 'oddjobz', 'customers.jsonl');
      expect(existsSync(customersPath)).toBe(true);
      const customersLines = readFileSync(customersPath, 'utf8').split('\n').filter(l => l.length > 0);
      expect(customersLines.length).toBe(1);
      const custRow = JSON.parse(customersLines[0]) as Record<string, unknown>;
      expect(custRow.kind).toBe('created');
      expect(typeof custRow.id).toBe('string');
      expect((custRow.id as string).length).toBe(32); // UUID hex (no dashes)
      expect(typeof custRow.cellId).toBe('string');
      expect((custRow.cellId as string).length).toBe(64);
      expect(typeof custRow.role).toBe('string');
      expect(typeof custRow.siteRef).toBe('string');
      expect(custRow.siteRef).toBe(decoded.site);

      expect(warnSpy).toHaveBeenCalled();
      const warnArg = String(warnSpy.mock.calls[0][0]);
      expect(warnArg).toContain('[brain-rpc] WSS unavailable');
    } finally {
      warnSpy.mockRestore();
    }
  });

  test('FS fallback fires on WS error / 503-style upgrade failure', async () => {
    const dir = makeTmpDir();
    const warnSpy = spyOn(console, 'warn').mockImplementation(() => {});
    try {
      const writer = new BrainRpcCellWriter({
        wsRpcUrl: 'ws://localhost:1/never',
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        webSocketCtor: ErroringWebSocket as any,
        fsFallbackDataDir: dir,
        timeoutMs: 1000,
      });
      const proposal = makeProposal({ proposalId: 'prop-fb-503' });
      const cellId = await writer.write({ program: proposal.program, proposal });
      const decoded = JSON.parse(cellId) as Record<string, unknown>;
      expect(typeof decoded.job).toBe('string');

      const jobsPath = join(dir, 'oddjobz', 'jobs.jsonl');
      const lines = readFileSync(jobsPath, 'utf8').split('\n').filter(l => l.length > 0);
      expect(lines.length).toBe(1);
      const row = JSON.parse(lines[0]) as Record<string, unknown>;
      expect(row.state).toBe('lead');
      expect(row.kind).toBe('created');

      expect(warnSpy).toHaveBeenCalled();
    } finally {
      warnSpy.mockRestore();
    }
  });

  test('does NOT fall back when fsFallbackDataDir is unset — surfaces BrainRpcCellWriterError', async () => {
    const writer = new BrainRpcCellWriter({
      wsRpcUrl: 'ws://localhost:1/never',
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      webSocketCtor: ErroringWebSocket as any,
      timeoutMs: 1000,
    });
    const proposal = makeProposal({ proposalId: 'prop-fb-throw' });
    let caught: unknown = null;
    try {
      await writer.write({ program: proposal.program, proposal });
    } catch (err) {
      caught = err;
    }
    expect(caught).toBeInstanceOf(BrainRpcCellWriterError);
  });

  test('FS fallback prefers proposal.pointOfContact over the summary-derived customer_name', async () => {
    const dir = makeTmpDir();
    const warnSpy = spyOn(console, 'warn').mockImplementation(() => {});
    try {
      const writer = new BrainRpcCellWriter({
        wsRpcUrl: 'ws://localhost:1/never',
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        webSocketCtor: ThrowingWebSocket as any,
        fsFallbackDataDir: dir,
      });
      const proposal = makeProposal({
        proposalId: 'prop-fb-poc',
        pointOfContact: 'Bricks + Agent',
      });
      await writer.write({ program: proposal.program, proposal });

      const jobsPath = join(dir, 'oddjobz', 'jobs.jsonl');
      const lines = readFileSync(jobsPath, 'utf8').split('\n').filter(l => l.length > 0);
      expect(lines.length).toBe(1);
      const row = JSON.parse(lines[0]) as Record<string, unknown>;
      // The new field wins over the legacy summary-first-line name.
      expect(row.customer_name).toBe('Bricks + Agent');
    } finally {
      warnSpy.mockRestore();
    }
  });

  test('FS fallback falls back to the summary-derived customer_name when pointOfContact is absent', async () => {
    // Older proposals (extracted before 2026-05-04) and LLM misses
    // both arrive with pointOfContact = undefined. The fallback must
    // still produce a non-empty display name from the summary.
    const dir = makeTmpDir();
    const warnSpy = spyOn(console, 'warn').mockImplementation(() => {});
    try {
      const writer = new BrainRpcCellWriter({
        wsRpcUrl: 'ws://localhost:1/never',
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        webSocketCtor: ThrowingWebSocket as any,
        fsFallbackDataDir: dir,
      });
      const proposal = makeProposal({ proposalId: 'prop-fb-legacy' });
      await writer.write({ program: proposal.program, proposal });

      const jobsPath = join(dir, 'oddjobz', 'jobs.jsonl');
      const lines = readFileSync(jobsPath, 'utf8').split('\n').filter(l => l.length > 0);
      const row = JSON.parse(lines[0]) as Record<string, unknown>;
      expect(row.customer_name).toBe('AcmeCorp wants a deck rebuild');
    } finally {
      warnSpy.mockRestore();
    }
  });

  test('FS fallback ignores empty / whitespace pointOfContact and falls through', async () => {
    // The extractor's normaliser already strips empty strings, but the
    // cell-writer must remain robust to an upstream that sets it to
    // '' or whitespace directly (e.g. a hand-built test proposal).
    const dir = makeTmpDir();
    const warnSpy = spyOn(console, 'warn').mockImplementation(() => {});
    try {
      const writer = new BrainRpcCellWriter({
        wsRpcUrl: 'ws://localhost:1/never',
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        webSocketCtor: ThrowingWebSocket as any,
        fsFallbackDataDir: dir,
      });
      const proposal = makeProposal({
        proposalId: 'prop-fb-empty-poc',
        pointOfContact: '   ',
      });
      await writer.write({ program: proposal.program, proposal });
      const jobsPath = join(dir, 'oddjobz', 'jobs.jsonl');
      const lines = readFileSync(jobsPath, 'utf8').split('\n').filter(l => l.length > 0);
      const row = JSON.parse(lines[0]) as Record<string, unknown>;
      expect(row.customer_name).toBe('AcmeCorp wants a deck rebuild');
    } finally {
      warnSpy.mockRestore();
    }
  });

  test('FS fallback is idempotent on proposal_id — second call returns same cellIds, no double-append to any of the four JSONLs', async () => {
    const dir = makeTmpDir();
    const warnSpy = spyOn(console, 'warn').mockImplementation(() => {});
    try {
      const writer = new BrainRpcCellWriter({
        wsRpcUrl: 'ws://localhost:1/never',
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        webSocketCtor: ThrowingWebSocket as any,
        fsFallbackDataDir: dir,
      });
      const proposal = makeProposal({
        proposalId: 'prop-fb-dup',
        sourceAttachmentPath: 'gmail:msg-001#attachment-1',
      });
      const first = JSON.parse(
        await writer.write({ program: proposal.program, proposal }),
      ) as Record<string, unknown>;
      const second = JSON.parse(
        await writer.write({ program: proposal.program, proposal }),
      ) as Record<string, unknown>;
      expect(second).toEqual(first);

      // None of the four view-store JSONLs should have a second
      // append: the per-proposal idempotency cache short-circuits
      // before the graph-walk runs at all.
      for (const fname of ['sites.jsonl', 'customers.jsonl', 'jobs.jsonl', 'attachments.jsonl']) {
        const lines = readFileSync(join(dir, 'oddjobz', fname), 'utf8').split('\n').filter(l => l.length > 0);
        expect(lines.length).toBe(1);
      }
      const indexPath = join(dir, 'oddjobz', 'legacy-ratifications.jsonl');
      const indexLines = readFileSync(indexPath, 'utf8').split('\n').filter(l => l.length > 0);
      expect(indexLines.length).toBe(1);
    } finally {
      warnSpy.mockRestore();
    }
  });

  // ── D-DOG.1.0c Phase 2B.2 — graph-walk fallback tests ────────────────

  test('FS fallback writes all four JSONL files when proposal carries the full Tier 1.7 envelope', async () => {
    const dir = makeTmpDir();
    const warnSpy = spyOn(console, 'warn').mockImplementation(() => {});
    try {
      const writer = new BrainRpcCellWriter({
        wsRpcUrl: 'ws://localhost:1/never',
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        webSocketCtor: ThrowingWebSocket as any,
        fsFallbackDataDir: dir,
      });
      const proposal = makeProposal({
        proposalId: 'prop-2b2-full',
        propertyAddress: '29 Foedera Cres, Tewantin QLD 4565',
        propertyKey: 'key #177',
        primaryContact: {
          name: 'Sarah Tenant',
          role: 'tenant',
          phone: '+61400111222',
          email: 'sarah@example.com',
        },
        secondaryContacts: [
          { name: 'Tracy Pickering', role: 'agent', phone: null, email: 'tracy@cleverproperty.au' },
        ],
        billingParty: { type: 'agency', name: 'Clever Property' },
        workOrderNumber: 'WO-07487',
        issuanceDate: '2026-04-22',
        dueDate: '2026-05-06',
        hasPhotos: true,
        photoCount: 4,
        sourceAttachmentPath: 'gmail:msg-001#attachment-2',
      });
      const cellId = await writer.write({ program: proposal.program, proposal });
      const decoded = JSON.parse(cellId) as Record<string, unknown>;
      expect(typeof decoded.site).toBe('string');
      expect((decoded.customers as string[]).length).toBe(2); // primary + secondary
      expect(typeof decoded.job).toBe('string');
      expect((decoded.attachments as string[]).length).toBe(1);

      // Each of the four JSONL files exists and has exactly one row
      // matching the corresponding cellId.
      for (const fname of ['sites.jsonl', 'jobs.jsonl', 'attachments.jsonl']) {
        const path = join(dir, 'oddjobz', fname);
        expect(existsSync(path)).toBe(true);
        const lines = readFileSync(path, 'utf8').split('\n').filter(l => l.length > 0);
        expect(lines.length).toBe(1);
      }
      const customersLines = readFileSync(join(dir, 'oddjobz', 'customers.jsonl'), 'utf8')
        .split('\n').filter(l => l.length > 0);
      expect(customersLines.length).toBe(2); // primary + secondary

      // Job row carries Tier 1.7 v2 fields.
      const jobRow = JSON.parse(
        readFileSync(join(dir, 'oddjobz', 'jobs.jsonl'), 'utf8').split('\n')[0]!,
      ) as Record<string, unknown>;
      expect(jobRow.workOrderNumber).toBe('WO-07487');
      expect(jobRow.issuanceDate).toBe('2026-04-22');
      expect(jobRow.dueDate).toBe('2026-05-06');
      expect(jobRow.propertyKey).toBe('key #177');
      expect(jobRow.hasPhotos).toBe(true);
      expect(jobRow.photoCount).toBe(4);
      expect(jobRow.billingParty).toEqual({ type: 'agency', name: 'Clever Property' });
      expect((jobRow.customerRefs as unknown[]).length).toBe(2);

      // Attachment row carries jobRef + sourceBlobKey + photo metadata.
      const attRow = JSON.parse(
        readFileSync(join(dir, 'oddjobz', 'attachments.jsonl'), 'utf8').split('\n')[0]!,
      ) as Record<string, unknown>;
      expect(attRow.jobRef).toBe(decoded.job);
      expect(attRow.sourceBlobKey).toBe('gmail:msg-001#attachment-2');
      expect(attRow.mime_type).toBe('application/pdf');
      expect(attRow.hasPhotos).toBe(true);
      expect(attRow.photoCount).toBe(4);

      // Site row's lookupKey derives from normalisedAddress + key #177.
      const siteRow = JSON.parse(
        readFileSync(join(dir, 'oddjobz', 'sites.jsonl'), 'utf8').split('\n')[0]!,
      ) as Record<string, unknown>;
      expect(siteRow.fullAddress).toBe('29 Foedera Cres, Tewantin QLD 4565');
      expect(siteRow.normalisedAddress).toBe('29 foedera cres, tewantin qld 4565');
      expect(siteRow.keyNumber).toBe('key #177');
      expect(siteRow.lookupKey).toBe('29 foedera cres, tewantin qld 4565|key #177');
    } finally {
      warnSpy.mockRestore();
    }
  });

  test('FS fallback dedupes site by lookupKey across two proposals with the same address', async () => {
    const dir = makeTmpDir();
    const warnSpy = spyOn(console, 'warn').mockImplementation(() => {});
    try {
      const writer = new BrainRpcCellWriter({
        wsRpcUrl: 'ws://localhost:1/never',
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        webSocketCtor: ThrowingWebSocket as any,
        fsFallbackDataDir: dir,
      });
      // Two proposals, same physical address but different formatting
      // (case + whitespace). The normaliser folds them onto one site.
      const p1 = makeProposal({
        proposalId: 'prop-site-dedupe-1',
        propertyAddress: '29 Foedera Cres, Tewantin QLD 4565',
        propertyKey: 'key #177',
      });
      const p2 = makeProposal({
        proposalId: 'prop-site-dedupe-2',
        propertyAddress: '29  FOEDERA CRES, Tewantin QLD 4565   ',
        propertyKey: 'key #177',
      });
      const c1 = JSON.parse(
        await writer.write({ program: p1.program, proposal: p1 }),
      ) as Record<string, unknown>;
      const c2 = JSON.parse(
        await writer.write({ program: p2.program, proposal: p2 }),
      ) as Record<string, unknown>;
      expect(c1.site).toBe(c2.site);

      // sites.jsonl should have only one row.
      const sitesLines = readFileSync(join(dir, 'oddjobz', 'sites.jsonl'), 'utf8')
        .split('\n').filter(l => l.length > 0);
      expect(sitesLines.length).toBe(1);

      // jobs.jsonl has two rows (job is always fresh per ratify) but
      // both share the same siteRef.
      const jobsLines = readFileSync(join(dir, 'oddjobz', 'jobs.jsonl'), 'utf8')
        .split('\n').filter(l => l.length > 0);
      expect(jobsLines.length).toBe(2);
      const j1 = JSON.parse(jobsLines[0]!) as Record<string, unknown>;
      const j2 = JSON.parse(jobsLines[1]!) as Record<string, unknown>;
      expect(j1.siteRef).toBe(j2.siteRef);
    } finally {
      warnSpy.mockRestore();
    }
  });

  test('FS fallback dedupes customer by phone exact match across two proposals', async () => {
    const dir = makeTmpDir();
    const warnSpy = spyOn(console, 'warn').mockImplementation(() => {});
    try {
      const writer = new BrainRpcCellWriter({
        wsRpcUrl: 'ws://localhost:1/never',
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        webSocketCtor: ThrowingWebSocket as any,
        fsFallbackDataDir: dir,
      });
      // Two proposals, same property + same primary phone, but
      // different name spelling. Phone takes precedence in the dedupe
      // ladder.
      const p1 = makeProposal({
        proposalId: 'prop-cust-dedupe-1',
        propertyAddress: '12 Acme Street',
        primaryContact: {
          name: 'Robert Owner',
          role: 'owner',
          phone: '+61400111222',
          email: null,
        },
      });
      const p2 = makeProposal({
        proposalId: 'prop-cust-dedupe-2',
        propertyAddress: '12 Acme Street',
        primaryContact: {
          name: 'Bob Owner',
          role: 'owner',
          phone: '+61400111222',
          email: null,
        },
      });
      const c1 = JSON.parse(
        await writer.write({ program: p1.program, proposal: p1 }),
      ) as Record<string, unknown>;
      const c2 = JSON.parse(
        await writer.write({ program: p2.program, proposal: p2 }),
      ) as Record<string, unknown>;
      expect((c1.customers as string[])[0]).toBe((c2.customers as string[])[0]);

      const customersLines = readFileSync(join(dir, 'oddjobz', 'customers.jsonl'), 'utf8')
        .split('\n').filter(l => l.length > 0);
      expect(customersLines.length).toBe(1);
    } finally {
      warnSpy.mockRestore();
    }
  });

  test('FS fallback dedupes customer by email when phones differ but email matches', async () => {
    const dir = makeTmpDir();
    const warnSpy = spyOn(console, 'warn').mockImplementation(() => {});
    try {
      const writer = new BrainRpcCellWriter({
        wsRpcUrl: 'ws://localhost:1/never',
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        webSocketCtor: ThrowingWebSocket as any,
        fsFallbackDataDir: dir,
      });
      const p1 = makeProposal({
        proposalId: 'prop-email-1',
        propertyAddress: '5 Email Lane',
        primaryContact: {
          name: 'Tracy Pickering',
          role: 'agent',
          phone: '0412 999 000',
          email: 'tracy@cleverproperty.au',
        },
      });
      const p2 = makeProposal({
        proposalId: 'prop-email-2',
        propertyAddress: '5 Email Lane',
        primaryContact: {
          name: 'Tracy Pickering',
          role: 'agent',
          phone: '0412 111 222', // different phone
          email: 'tracy@cleverproperty.au', // same email
        },
      });
      const c1 = JSON.parse(
        await writer.write({ program: p1.program, proposal: p1 }),
      ) as Record<string, unknown>;
      const c2 = JSON.parse(
        await writer.write({ program: p2.program, proposal: p2 }),
      ) as Record<string, unknown>;
      expect((c1.customers as string[])[0]).toBe((c2.customers as string[])[0]);

      const customersLines = readFileSync(join(dir, 'oddjobz', 'customers.jsonl'), 'utf8')
        .split('\n').filter(l => l.length > 0);
      expect(customersLines.length).toBe(1);
    } finally {
      warnSpy.mockRestore();
    }
  });

  test('FS fallback v2 row shape mirrors the Zig view-store JSONL shape (sites + customers + jobs + attachments)', async () => {
    // Phase 2B.4 lands a parity oracle that asserts byte-equality
    // across implementations; this test asserts the per-row field
    // SET matches the Zig store's appendV2/appendCreatedV2Line.
    const dir = makeTmpDir();
    const warnSpy = spyOn(console, 'warn').mockImplementation(() => {});
    try {
      const writer = new BrainRpcCellWriter({
        wsRpcUrl: 'ws://localhost:1/never',
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        webSocketCtor: ThrowingWebSocket as any,
        fsFallbackDataDir: dir,
      });
      const proposal = makeProposal({
        proposalId: 'prop-shape-parity',
        propertyAddress: '1 Shape Parity Lane',
        primaryContact: {
          name: 'Quinn',
          role: 'tenant',
          phone: '+61400222333',
          email: 'quinn@example.com',
        },
        sourceAttachmentPath: 'blob:abc123#attachment-1',
        hasPhotos: true,
        photoCount: 2,
      });
      await writer.write({ program: proposal.program, proposal });

      // sites.jsonl line shape — all keys the Zig appendCreatedLine emits.
      const siteRow = JSON.parse(
        readFileSync(join(dir, 'oddjobz', 'sites.jsonl'), 'utf8').split('\n')[0]!,
      ) as Record<string, unknown>;
      for (const k of [
        'ts', 'kind', 'cellId', 'typeHash',
        'normalisedAddress', 'keyNumber', 'lookupKey', 'fullAddress',
        'suburb', 'postcode', 'state',
        'signedBy', 'signature', 'createdAt',
      ]) {
        expect(k in siteRow).toBe(true);
      }

      // customers.jsonl line shape.
      const custRow = JSON.parse(
        readFileSync(join(dir, 'oddjobz', 'customers.jsonl'), 'utf8').split('\n')[0]!,
      ) as Record<string, unknown>;
      for (const k of [
        'ts', 'kind', 'id', 'display_name', 'phone', 'email',
        'address', 'notes', 'created_at',
        'cellId', 'typeHash', 'role',
        'normalisedPhone', 'sourceProvenance', 'siteRef',
      ]) {
        expect(k in custRow).toBe(true);
      }
      const sourceProv = custRow.sourceProvenance as Record<string, unknown>;
      expect('providerId' in sourceProv).toBe(true);
      expect('providerItemId' in sourceProv).toBe(true);
      expect('extractedAt' in sourceProv).toBe(true);

      // jobs.jsonl v2 line shape.
      const jobRow = JSON.parse(
        readFileSync(join(dir, 'oddjobz', 'jobs.jsonl'), 'utf8').split('\n')[0]!,
      ) as Record<string, unknown>;
      for (const k of [
        'ts', 'kind', 'id', 'typeHash',
        'customer_name', 'state', 'scheduled_at', 'created_at',
        'workOrderNumber', 'issuanceDate', 'dueDate',
        'billingParty', 'hasPhotos', 'photoCount', 'propertyKey',
        'siteRef', 'customerRefs', 'attachmentRefs',
        'signedBy', 'signature',
      ]) {
        expect(k in jobRow).toBe(true);
      }

      // attachments.jsonl v2 line shape.
      const attRow = JSON.parse(
        readFileSync(join(dir, 'oddjobz', 'attachments.jsonl'), 'utf8').split('\n')[0]!,
      ) as Record<string, unknown>;
      for (const k of [
        'ts', 'kind', 'id', 'visit_id', 'kind_field',
        'content_hash', 'content_size', 'mime_type',
        'captured_at', 'captured_by_cert_id', 'caption', 'created_at',
        'cellId', 'typeHash',
        'jobRef', 'sourceBlobKey', 'pageCount', 'photoCount', 'hasPhotos',
      ]) {
        expect(k in attRow).toBe(true);
      }
    } finally {
      warnSpy.mockRestore();
    }
  });

  test('FS fallback no-op SIR (no ratifiable action) writes nothing but records the empty graph in the index', async () => {
    const dir = makeTmpDir();
    const warnSpy = spyOn(console, 'warn').mockImplementation(() => {});
    try {
      const writer = new BrainRpcCellWriter({
        wsRpcUrl: 'ws://localhost:1/never',
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        webSocketCtor: ThrowingWebSocket as any,
        fsFallbackDataDir: dir,
      });
      const proposal = makeProposal({
        proposalId: 'prop-noop',
        program: makeProgram('noop'),
      });
      const cellId = await writer.write({ program: proposal.program, proposal });
      const decoded = JSON.parse(cellId) as Record<string, unknown>;
      expect(decoded).toEqual({ site: null, customers: [], job: null, attachments: [] });

      // None of the four view-store files exist — buildGraphAndAppend
      // never ran.
      for (const fname of ['sites.jsonl', 'customers.jsonl', 'jobs.jsonl', 'attachments.jsonl']) {
        expect(existsSync(join(dir, 'oddjobz', fname))).toBe(false);
      }
      // But the index DOES record the empty graph so a re-ratify is
      // idempotent.
      const indexLines = readFileSync(join(dir, 'oddjobz', 'legacy-ratifications.jsonl'), 'utf8')
        .split('\n').filter(l => l.length > 0);
      expect(indexLines.length).toBe(1);
    } finally {
      warnSpy.mockRestore();
    }
  });

  test('FS fallback re-ratify preserves graph cellIds across all four files', async () => {
    // Re-running the SAME proposal should return identical cellIds
    // for site/customers/job/attachments without re-walking.
    const dir = makeTmpDir();
    const warnSpy = spyOn(console, 'warn').mockImplementation(() => {});
    try {
      const writer = new BrainRpcCellWriter({
        wsRpcUrl: 'ws://localhost:1/never',
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        webSocketCtor: ThrowingWebSocket as any,
        fsFallbackDataDir: dir,
      });
      const proposal = makeProposal({
        proposalId: 'prop-graph-idem',
        propertyAddress: '99 Idempotency Way',
        primaryContact: {
          name: 'Adam',
          role: 'tenant',
          phone: '+61400000001',
          email: null,
        },
        sourceAttachmentPath: 'blob:idem#1',
      });
      const first = JSON.parse(
        await writer.write({ program: proposal.program, proposal }),
      ) as Record<string, unknown>;
      const second = JSON.parse(
        await writer.write({ program: proposal.program, proposal }),
      ) as Record<string, unknown>;
      expect(second).toEqual(first);

      // No double-append to any of the four files.
      for (const fname of ['sites.jsonl', 'customers.jsonl', 'jobs.jsonl', 'attachments.jsonl']) {
        const lines = readFileSync(join(dir, 'oddjobz', fname), 'utf8').split('\n').filter(l => l.length > 0);
        expect(lines.length).toBe(1);
      }
    } finally {
      warnSpy.mockRestore();
    }
  });
});

// ── derivePayloadHint tests (D-DOG.1.0c Phase 2B.1.a) ────────────────
//
// The cell-writer's payload_hint envelope is the side-channel
// `oddjobz_ratify_handler.zig::parsePayloadHint` reads to fill cell
// fields the SIRProgram doesn't carry today. Phase 2B.1 extends it
// from the legacy 5-field shape to forward Tier 1.7 enriched fields
// (primaryContact / secondaryContacts / propertyAddress / propertyKey /
// ownerName / billingParty / workOrderNumber / issuanceDate / dueDate
// / hasPhotos / photoCount / sourceAttachmentPath).
//
// Field naming is the contract surface: legacy 5 stay snake_case; the
// new fields use camelCase (matching `parsePayloadHint`'s `optString`
// keys exactly). Mismatches here would land empty graphs in operator
// ratifications, so these tests are load-bearing.

describe('derivePayloadHint — Tier 1.7 forwarding', () => {
  test('legacy proposal (no Tier 1.7 fields) emits envelope identical to pre-2B.1 shape', () => {
    const proposal = makeProposal();
    const hint = derivePayloadHint(proposal);
    // Legacy 5 are always present.
    expect(hint.customer_name).toBe('AcmeCorp wants a deck rebuild');
    expect(hint.point_of_contact).toBe('');
    expect(hint.summary).toBe('AcmeCorp wants a deck rebuild');
    expect(hint.reference_number).toBe('');
    expect(hint.source_provider_id).toBe('gmail');
    // Tier 1.7 fields must be absent (not `null`, not `''`) so the Zig
    // handler's `obj.get(...)` branches default to their zero values.
    expect('primaryContact' in hint).toBe(false);
    expect('secondaryContacts' in hint).toBe(false);
    expect('ownerName' in hint).toBe(false);
    expect('billingParty' in hint).toBe(false);
    expect('propertyAddress' in hint).toBe(false);
    expect('propertyKey' in hint).toBe(false);
    expect('workOrderNumber' in hint).toBe(false);
    expect('issuanceDate' in hint).toBe(false);
    expect('dueDate' in hint).toBe(false);
    expect('hasPhotos' in hint).toBe(false);
    expect('photoCount' in hint).toBe(false);
    expect('sourceAttachmentPath' in hint).toBe(false);
  });

  test('Tier 1.7 fields forward to camelCase keys on the wire', () => {
    const proposal = makeProposal({
      pointOfContact: 'Tracy Pickering (agent)',
      referenceNumber: 'WO-07487',
      primaryContact: {
        name: 'Sarah Tenant',
        role: 'tenant',
        phone: '0411 222 333',
        email: 'sarah@example.com',
      },
      secondaryContacts: [
        { name: 'Tracy Pickering', role: 'agent', phone: null, email: 'tracy@cleverproperty.au' },
      ],
      ownerName: 'A & J Holdings Pty Ltd',
      billingParty: { type: 'agency', name: 'Clever Property' },
      propertyAddress: '29 Foedera Cres, Tewantin QLD 4565',
      propertyKey: 'key #177',
      workOrderNumber: 'WO-07487',
      issuanceDate: '2026-04-22',
      dueDate: '2026-05-06',
      hasPhotos: true,
      photoCount: 4,
      sourceAttachmentPath: 'gmail:msg-001#attachment-2',
    });
    const hint = derivePayloadHint(proposal);
    // Legacy fields still populated.
    expect(hint.point_of_contact).toBe('Tracy Pickering (agent)');
    expect(hint.reference_number).toBe('WO-07487');
    // Tier 1.7 fields forwarded with the exact camelCase keys the Zig
    // handler reads (parsePayloadHint).
    expect(hint.primaryContact).toEqual({
      name: 'Sarah Tenant',
      role: 'tenant',
      phone: '0411 222 333',
      email: 'sarah@example.com',
    });
    expect(hint.secondaryContacts).toEqual([
      { name: 'Tracy Pickering', role: 'agent', phone: null, email: 'tracy@cleverproperty.au' },
    ]);
    expect(hint.ownerName).toBe('A & J Holdings Pty Ltd');
    expect(hint.billingParty).toEqual({ type: 'agency', name: 'Clever Property' });
    expect(hint.propertyAddress).toBe('29 Foedera Cres, Tewantin QLD 4565');
    expect(hint.propertyKey).toBe('key #177');
    expect(hint.workOrderNumber).toBe('WO-07487');
    expect(hint.issuanceDate).toBe('2026-04-22');
    expect(hint.dueDate).toBe('2026-05-06');
    expect(hint.hasPhotos).toBe(true);
    expect(hint.photoCount).toBe(4);
    expect(hint.sourceAttachmentPath).toBe('gmail:msg-001#attachment-2');
  });

  test('partial Tier 1.7 (e.g. owner-only billing) only forwards present fields', () => {
    const proposal = makeProposal({
      ownerName: 'Joe Owner',
      billingParty: { type: 'owner', name: 'Joe Owner' },
      // Other Tier 1.7 fields absent.
    });
    const hint = derivePayloadHint(proposal);
    expect(hint.ownerName).toBe('Joe Owner');
    expect(hint.billingParty).toEqual({ type: 'owner', name: 'Joe Owner' });
    expect('primaryContact' in hint).toBe(false);
    expect('propertyAddress' in hint).toBe(false);
    expect('hasPhotos' in hint).toBe(false);
  });

  test('drops invalid contacts (no name) and forwards empty arrays as omitted', () => {
    const proposal = makeProposal({
      // primaryContact with empty name should be dropped.
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      primaryContact: { name: '', role: 'tenant', phone: null, email: null } as any,
      secondaryContacts: [],
    });
    const hint = derivePayloadHint(proposal);
    expect('primaryContact' in hint).toBe(false);
    expect('secondaryContacts' in hint).toBe(false);
  });

  test('omits empty-string Tier 1.7 fields rather than emitting empty values', () => {
    const proposal = makeProposal({
      ownerName: '',
      propertyAddress: '',
      workOrderNumber: '',
      issuanceDate: '',
      dueDate: '',
      sourceAttachmentPath: '',
    });
    const hint = derivePayloadHint(proposal);
    expect('ownerName' in hint).toBe(false);
    expect('propertyAddress' in hint).toBe(false);
    expect('workOrderNumber' in hint).toBe(false);
    expect('issuanceDate' in hint).toBe(false);
    expect('dueDate' in hint).toBe(false);
    expect('sourceAttachmentPath' in hint).toBe(false);
  });

  test('forwards hasPhotos=false explicitly (boolean is meaningful, not just presence)', () => {
    const proposal = makeProposal({ hasPhotos: false });
    const hint = derivePayloadHint(proposal);
    expect(hint.hasPhotos).toBe(false);
  });

  test('photoCount=0 forwards (zero is a meaningful count)', () => {
    const proposal = makeProposal({ photoCount: 0 });
    const hint = derivePayloadHint(proposal);
    expect(hint.photoCount).toBe(0);
  });

  test('Tier 1.7 fields propagate over the wire to the Semantos Brain stub', async () => {
    const stub = startStubServer('happy');
    try {
      const writer = new BrainRpcCellWriter({ wsRpcUrl: stub.url, timeoutMs: 5000 });
      const proposal = makeProposal({
        propertyAddress: '29 Foedera Cres, Tewantin QLD 4565',
        propertyKey: 'key #177',
        primaryContact: {
          name: 'Sarah Tenant',
          role: 'tenant',
          phone: '0411',
          email: null,
        },
        billingParty: { type: 'agency', name: 'Clever Property' },
        hasPhotos: true,
        photoCount: 3,
      });
      await writer.write({ program: proposal.program, proposal });
      const req = stub.lastRequest();
      const hint = (req!.params as Record<string, unknown>).payload_hint as Record<string, unknown>;
      expect(hint.propertyAddress).toBe('29 Foedera Cres, Tewantin QLD 4565');
      expect(hint.propertyKey).toBe('key #177');
      expect(hint.primaryContact).toEqual({
        name: 'Sarah Tenant',
        role: 'tenant',
        phone: '0411',
        email: null,
      });
      expect(hint.billingParty).toEqual({ type: 'agency', name: 'Clever Property' });
      expect(hint.hasPhotos).toBe(true);
      expect(hint.photoCount).toBe(3);
    } finally {
      stub.stop();
    }
  });
});

```
