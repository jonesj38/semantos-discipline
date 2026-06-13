---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/tests/handler/handler.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.513462+00:00
---

# packages/dispatch/dispatch/tests/handler/handler.test.ts

```ts
/**
 * D-O11 phase O11b — dispatch handler conformance tests.
 *
 * Covers the handler's per-branch routing logic in isolation
 * (without invoking real receiving extensions). The end-to-end
 * cross-vertical smoke test sits in
 * `tests/cross-vertical-smoke.test.ts`.
 *
 * Failure surfaces under test:
 *  - payload_type_unsupported (no accept-handler registered)
 *  - envelope_replay (K1)
 *  - hat_mismatch (envelope addressed to wrong hat)
 *  - cert_chain_invalid
 *  - accept_handler_threw (K4 retry-safety)
 *  - envelope_validation_failed (malformed envelope)
 */

import { describe, expect, test } from 'bun:test';
import { buildHat } from '@semantos/oddjobz';

import {
  makeAcceptHandlerRegistry,
  makeRollbackableConsumedCellSet,
  processDispatchEnvelope,
  type CertChainVerifier,
  type DispatchEnvelope,
} from '../../src/index.js';

const ENV_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const ENV_ID_2 = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff';
const NOW = '2026-05-01T09:00:00.000Z';

const ACCEPTING_VERIFIER: CertChainVerifier = () => ({ ok: true });
const REJECTING_VERIFIER: CertChainVerifier = () => ({
  ok: false,
  reason: 'leaf cert unknown to brain trust store',
});

function makeEnvelope(overrides: Partial<DispatchEnvelope> = {}): DispatchEnvelope {
  return {
    envelopeId: ENV_ID,
    fromTenant: 'acme-pm.com.au',
    fromHat: 'pm-alice',
    toTenant: 'oddjobtodd.info',
    toHat: 'tradie-todd',
    payloadType: 're-desk.maintenance-request.v1',
    payload: 'deadbeef',
    signedBy: 'cert-id-of-pm-alice-1234567890abcdef',
    createdAt: NOW,
    ...overrides,
  };
}

function makeReceivingHat(hatId = 'tradie-todd') {
  return buildHat({
    hatId,
    contextTag: 0x10,
    principal: 'operator',
    facetId: 'facet-id-tradie-todd',
  });
}

describe('dispatch handler — happy path', () => {
  test('routes payload to registered accept-handler and returns dispatch.accepted.v1', async () => {
    const registry = makeAcceptHandlerRegistry();
    let captured: { envelopeId?: string; payloadHex?: string } = {};
    registry.register('re-desk.maintenance-request.v1', (ctx) => {
      captured.envelopeId = ctx.envelope.envelopeId;
      captured.payloadHex = Buffer.from(ctx.payloadBytes).toString('hex');
      return {
        localCellId: 'local-job-id-123',
        localCellType: 'oddjobz.job.v1',
        acceptedByHat: ctx.receivingHat.hatId,
        acceptedAt: NOW,
      };
    });
    const consumed = makeRollbackableConsumedCellSet();
    const envelope = makeEnvelope();

    const r = await processDispatchEnvelope({
      envelope,
      payloadBytes: new Uint8Array([0xde, 0xad, 0xbe, 0xef]),
      receivingHat: makeReceivingHat(),
      verifyCertChain: ACCEPTING_VERIFIER,
      registry,
      consumed,
      nowIso: NOW,
    });

    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.accepted.envelopeId).toBe(ENV_ID);
      expect(r.accepted.localCellId).toBe('local-job-id-123');
      expect(r.accepted.localCellType).toBe('oddjobz.job.v1');
      expect(r.accepted.acceptedByHat).toBe('tradie-todd');
    }
    expect(captured.envelopeId).toBe(ENV_ID);
    expect(captured.payloadHex).toBe('deadbeef');
    expect(consumed.has(`dispatch.envelope:${ENV_ID}`)).toBe(true);
  });
});

describe('dispatch handler — failure modes', () => {
  test('payload_type_unsupported when no handler is registered', async () => {
    const registry = makeAcceptHandlerRegistry();
    const consumed = makeRollbackableConsumedCellSet();

    const r = await processDispatchEnvelope({
      envelope: makeEnvelope(),
      payloadBytes: new Uint8Array([0xde, 0xad]),
      receivingHat: makeReceivingHat(),
      verifyCertChain: ACCEPTING_VERIFIER,
      registry,
      consumed,
      nowIso: NOW,
    });

    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.error.kind).toBe('payload_type_unsupported');
      expect(r.error.payloadType).toBe('re-desk.maintenance-request.v1');
    }
    // K1 surface: the envelopeId was NOT consumed — the originator
    // can retry once a handler is registered, OR the originator's
    // FSM stays in `draft` until the receiving brain recovers. The
    // envelope can't be silently dropped.
    expect(consumed.has(`dispatch.envelope:${ENV_ID}`)).toBe(false);
  });

  test('envelope_replay when same envelopeId arrives twice', async () => {
    const registry = makeAcceptHandlerRegistry();
    registry.register('re-desk.maintenance-request.v1', () => ({
      localCellId: 'job-id',
      localCellType: 'oddjobz.job.v1',
      acceptedByHat: 'tradie-todd',
      acceptedAt: NOW,
    }));
    const consumed = makeRollbackableConsumedCellSet();
    const env = makeEnvelope();

    const r1 = await processDispatchEnvelope({
      envelope: env,
      payloadBytes: new Uint8Array([0xde, 0xad]),
      receivingHat: makeReceivingHat(),
      verifyCertChain: ACCEPTING_VERIFIER,
      registry,
      consumed,
      nowIso: NOW,
    });
    expect(r1.ok).toBe(true);

    const r2 = await processDispatchEnvelope({
      envelope: env,
      payloadBytes: new Uint8Array([0xde, 0xad]),
      receivingHat: makeReceivingHat(),
      verifyCertChain: ACCEPTING_VERIFIER,
      registry,
      consumed,
      nowIso: NOW,
    });
    expect(r2.ok).toBe(false);
    if (!r2.ok) expect(r2.error.kind).toBe('envelope_replay');
  });

  test('hat_mismatch when envelope.toHat ≠ receivingHat.hatId', async () => {
    const registry = makeAcceptHandlerRegistry();
    registry.register('re-desk.maintenance-request.v1', () => ({
      localCellId: 'job-id',
      localCellType: 'oddjobz.job.v1',
      acceptedByHat: 'tradie-todd',
      acceptedAt: NOW,
    }));
    const consumed = makeRollbackableConsumedCellSet();

    const r = await processDispatchEnvelope({
      envelope: makeEnvelope({ toHat: 'tradie-bob' }),
      payloadBytes: new Uint8Array([0xde, 0xad]),
      receivingHat: makeReceivingHat('tradie-todd'),
      verifyCertChain: ACCEPTING_VERIFIER,
      registry,
      consumed,
      nowIso: NOW,
    });

    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('hat_mismatch');
  });

  test('cert_chain_invalid when transport-layer verifier rejects', async () => {
    const registry = makeAcceptHandlerRegistry();
    registry.register('re-desk.maintenance-request.v1', () => ({
      localCellId: 'job-id',
      localCellType: 'oddjobz.job.v1',
      acceptedByHat: 'tradie-todd',
      acceptedAt: NOW,
    }));
    const consumed = makeRollbackableConsumedCellSet();

    const r = await processDispatchEnvelope({
      envelope: makeEnvelope(),
      payloadBytes: new Uint8Array([0xde, 0xad]),
      receivingHat: makeReceivingHat(),
      verifyCertChain: REJECTING_VERIFIER,
      registry,
      consumed,
      nowIso: NOW,
    });

    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.error.kind).toBe('cert_chain_invalid');
      expect(r.error.message).toContain('leaf cert unknown');
    }
    expect(consumed.has(`dispatch.envelope:${ENV_ID}`)).toBe(false);
  });

  test('[K4] accept_handler_threw rolls back consumed-set so retry succeeds', async () => {
    const registry = makeAcceptHandlerRegistry();
    let firstCall = true;
    registry.register('re-desk.maintenance-request.v1', () => {
      if (firstCall) {
        firstCall = false;
        throw new Error('upstream substrate transient unavailable');
      }
      return {
        localCellId: 'job-id',
        localCellType: 'oddjobz.job.v1',
        acceptedByHat: 'tradie-todd',
        acceptedAt: NOW,
      };
    });
    const consumed = makeRollbackableConsumedCellSet();
    const env = makeEnvelope();

    const r1 = await processDispatchEnvelope({
      envelope: env,
      payloadBytes: new Uint8Array([0xde, 0xad]),
      receivingHat: makeReceivingHat(),
      verifyCertChain: ACCEPTING_VERIFIER,
      registry,
      consumed,
      nowIso: NOW,
    });
    expect(r1.ok).toBe(false);
    if (!r1.ok) expect(r1.error.kind).toBe('accept_handler_threw');
    // K4 — the envelopeId was rolled back so the retry can land.
    expect(consumed.has(`dispatch.envelope:${ENV_ID}`)).toBe(false);

    const r2 = await processDispatchEnvelope({
      envelope: env,
      payloadBytes: new Uint8Array([0xde, 0xad]),
      receivingHat: makeReceivingHat(),
      verifyCertChain: ACCEPTING_VERIFIER,
      registry,
      consumed,
      nowIso: NOW,
    });
    expect(r2.ok).toBe(true);
    expect(consumed.has(`dispatch.envelope:${ENV_ID}`)).toBe(true);
  });

  test('envelope_validation_failed on malformed envelope (uppercase tenant)', async () => {
    const registry = makeAcceptHandlerRegistry();
    registry.register('re-desk.maintenance-request.v1', () => ({
      localCellId: 'job-id',
      localCellType: 'oddjobz.job.v1',
      acceptedByHat: 'tradie-todd',
      acceptedAt: NOW,
    }));
    const consumed = makeRollbackableConsumedCellSet();

    const r = await processDispatchEnvelope({
      envelope: makeEnvelope({ fromTenant: 'AcmePM.com' }),
      payloadBytes: new Uint8Array([0xde, 0xad]),
      receivingHat: makeReceivingHat(),
      verifyCertChain: ACCEPTING_VERIFIER,
      registry,
      consumed,
      nowIso: NOW,
    });

    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('envelope_validation_failed');
  });

  test('different envelopeIds do not collide on the consumed-set', async () => {
    const registry = makeAcceptHandlerRegistry();
    registry.register('re-desk.maintenance-request.v1', () => ({
      localCellId: 'job-id',
      localCellType: 'oddjobz.job.v1',
      acceptedByHat: 'tradie-todd',
      acceptedAt: NOW,
    }));
    const consumed = makeRollbackableConsumedCellSet();

    const r1 = await processDispatchEnvelope({
      envelope: makeEnvelope({ envelopeId: ENV_ID }),
      payloadBytes: new Uint8Array([0xde, 0xad]),
      receivingHat: makeReceivingHat(),
      verifyCertChain: ACCEPTING_VERIFIER,
      registry,
      consumed,
      nowIso: NOW,
    });
    const r2 = await processDispatchEnvelope({
      envelope: makeEnvelope({ envelopeId: ENV_ID_2 }),
      payloadBytes: new Uint8Array([0xde, 0xad]),
      receivingHat: makeReceivingHat(),
      verifyCertChain: ACCEPTING_VERIFIER,
      registry,
      consumed,
      nowIso: NOW,
    });
    expect(r1.ok).toBe(true);
    expect(r2.ok).toBe(true);
  });
});

describe('accept-handler registry', () => {
  test('lists registered types in sorted order', () => {
    const reg = makeAcceptHandlerRegistry();
    const noop = () => ({
      localCellId: 'x',
      localCellType: 'y',
      acceptedByHat: 'z',
      acceptedAt: NOW,
    });
    reg.register('zebra', noop);
    reg.register('apple', noop);
    expect(reg.registeredTypes()).toEqual(['apple', 'zebra']);
  });

  test('rejects double-registration', () => {
    const reg = makeAcceptHandlerRegistry();
    const noop = () => ({
      localCellId: 'x',
      localCellType: 'y',
      acceptedByHat: 'z',
      acceptedAt: NOW,
    });
    reg.register('apple', noop);
    expect(() => reg.register('apple', noop)).toThrow(/already has a registered handler/);
  });
});

```
