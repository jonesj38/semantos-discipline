---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/__tests__/agent-cert-provider.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.510690+00:00
---

# cartridges/oddjobz/brain/src/__tests__/agent-cert-provider.test.ts

```ts
/**
 * P3.4 agent-cert provider + accept_rom EnvelopeContext conformance.
 *
 * Pins the option-2 wiring: orchestrate the shipped device-pair-client
 * primitives → POST the EXISTING /api/v1/device-pair → map
 * {brain_cert_id,cert_id} → {hatId,certId}; and assemble the P3.2
 * EnvelopeContext for an oddjobz accept_rom cell. Mock primitives +
 * mock transport ⇒ ZERO live, no BRC-42/@bsv re-run here (that path is
 * proven by device-pair-client's own conformance). The real pairing +
 * submit are P3.5 (operator-approved).
 */

import { describe, expect, test } from 'bun:test';
import {
  makeAgentCertProvider,
  assembleAcceptRomEnvelopeContext,
  type PairingPrimitives,
  type FetchLike,
} from '../conversation/agent-cert-provider.js';

const decoded = {
  domain: 'brain-device-pair-v2',
  operatorRootCertId: 'f'.repeat(32),
  operatorRootPub: '02' + 'a'.repeat(64),
  contextTag: 16,
  label: 'oddjobz-agent',
  capabilities: ['cap.oddjobz.write_customer'],
  nonce: '0'.repeat(32),
  brainPairEndpoint: 'https://oddjobtodd.info/api/v1/device-pair',
  brainWssEndpoint: 'wss://oddjobtodd.info/api/v1/events',
  brainPinCertId: 'e'.repeat(32),
  brainPinPubkey: '02' + 'b'.repeat(64),
  signature: 'de',
} as unknown as ReturnType<PairingPrimitives['decode']>;

const stubPrimitives: PairingPrimitives = {
  decode: () => decoded,
  genDevicePriv: () => ({ privHex: '11'.repeat(32), pubHex: '02' + 'c'.repeat(64) }),
  derive: () => ({ childPubKeyHex: '02' + 'd'.repeat(64), devicePubKeyHex: '02' + 'e'.repeat(64) }),
  buildBody: (token, d) => ({
    token,
    derivation_pubkey: d.childPubKeyHex,
    derivation_proof: d.devicePubKeyHex,
  }),
};

const ok200: FetchLike = async (url, init) => {
  // assert it POSTs the decoded brainPairEndpoint with the accept body
  expect(url).toBe('https://oddjobtodd.info/api/v1/device-pair');
  expect(init.method).toBe('POST');
  const b = JSON.parse(init.body) as Record<string, unknown>;
  expect(b.token).toBe('tok');
  expect(typeof b.derivation_pubkey).toBe('string');
  return {
    status: 200,
    text: async () =>
      JSON.stringify({ status: 'registered', cert_id: 'a'.repeat(32), brain_cert_id: 'b'.repeat(32) }),
  };
};

describe('makeAgentCertProvider — option-2 device-pair orchestration', () => {
  test('maps {brain_cert_id,cert_id} → {hatId,certId}', async () => {
    const p = makeAgentCertProvider({
      pairingToken: 'tok',
      primitives: stubPrimitives,
      fetchFn: ok200,
    });
    const cert = await p.provision();
    expect(cert).toEqual({ hatId: 'b'.repeat(32), certId: 'a'.repeat(32) });
  });

  test('caches — pairing runs once across repeat provision()', async () => {
    let calls = 0;
    const p = makeAgentCertProvider({
      pairingToken: 'tok',
      primitives: stubPrimitives,
      fetchFn: async (u, i) => {
        calls++;
        return ok200(u, i);
      },
    });
    const [a, b] = await Promise.all([p.provision(), p.provision()]);
    await p.provision();
    expect(calls).toBe(1);
    expect(a).toEqual(b);
  });

  test('non-2xx ⇒ throws (no silent unprovisioned cert)', async () => {
    const p = makeAgentCertProvider({
      pairingToken: 'tok',
      primitives: stubPrimitives,
      fetchFn: async () => ({ status: 401, text: async () => 'pairing_payload_invalid_signature' }),
    });
    await expect(p.provision()).rejects.toThrow(/HTTP 401/);
  });

  test('status!=registered ⇒ throws; non-32hex ids ⇒ throws', async () => {
    const notReg = makeAgentCertProvider({
      pairingToken: 'tok',
      primitives: stubPrimitives,
      fetchFn: async () => ({ status: 200, text: async () => '{"status":"pending"}' }),
    });
    await expect(notReg.provision()).rejects.toThrow(/expected "registered"/);
    const badId = makeAgentCertProvider({
      pairingToken: 'tok',
      primitives: stubPrimitives,
      fetchFn: async () => ({
        status: 200,
        text: async () => '{"status":"registered","cert_id":"short","brain_cert_id":"x"}',
      }),
    });
    await expect(badId.provision()).rejects.toThrow(/32-hex/);
  });
});

describe('assembleAcceptRomEnvelopeContext — oddjobz accept_rom shape', () => {
  test('agent-cert + ROM range → P3.2 EnvelopeContext (action accept_rom, money channel)', () => {
    const ctx = assembleAcceptRomEnvelopeContext({
      agentCert: { hatId: 'b'.repeat(32), certId: 'a'.repeat(32) },
      correlationId: 'corr-1',
      kernelResult: { ok: true, opcount: 1, stackDepth: 0, gasUsed: 0, errorKind: null },
      costMin: 40000,
      costMax: 60000,
      summary: 'fence repair, 16m, rotten posts',
    });
    expect(ctx.hatId).toBe('b'.repeat(32));
    expect(ctx.certId).toBe('a'.repeat(32));
    expect(ctx.originalIntent.action).toBe('accept_rom');
    expect(JSON.parse(ctx.originalIntent.taxonomyJson).what).toBe('oddjobz.lead.v1');
    const t = JSON.parse(ctx.originalIntent.targetJson!);
    expect(t.costMin).toBe(40000);
    expect(t.costMax).toBe(60000);
    expect(t.currency).toBe('AUD');
    expect('jobId' in t).toBe(false); // omitted when unresolved
  });

  test('resolved entity refs are threaded into targetJson', () => {
    const ctx = assembleAcceptRomEnvelopeContext({
      agentCert: { hatId: 'b'.repeat(32), certId: 'a'.repeat(32) },
      correlationId: 'c',
      kernelResult: { ok: true, opcount: 1, stackDepth: 0, gasUsed: 0, errorKind: null },
      costMin: 1, costMax: 2, jobId: 'job-9', customerId: 'cust-9', currency: 'USD',
      summary: 's',
    });
    const t = JSON.parse(ctx.originalIntent.targetJson!);
    expect(t.jobId).toBe('job-9');
    expect(t.customerId).toBe('cust-9');
    expect(t.currency).toBe('USD');
  });
});

```
