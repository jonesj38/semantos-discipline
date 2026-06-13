---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/mfp/__tests__/iframe-wallet-port.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.908137+00:00
---

# core/protocol-types/src/mfp/__tests__/iframe-wallet-port.test.ts

```ts
import { describe, it, expect } from 'bun:test';
import { Hash, PrivateKey } from '@bsv/sdk';
import {
  IframeWalletPort,
  MessagePortBrc100Transport,
  Brc100Error,
  keyIdToDerivationIndex,
  type Brc100Transport,
  type PortLike,
} from '../iframe-wallet-port.js';
import { MfpFlowAdapter, type MfpFlowConfig } from '../flow-adapter.js';
import { mfpProtocolID, mfpKeyID } from '../protocol-id.js';

// ── helpers ──────────────────────────────────────────────────────────

function hexToBytes(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out;
}

/** A recording mock transport with canned per-method responses/errors. */
function mockTransport(handlers: {
  createAction?: (p: Record<string, unknown>) => Record<string, unknown>;
  createSignature?: (p: Record<string, unknown>) => Record<string, unknown>;
}) {
  const calls: Array<{ method: string; params: Record<string, unknown> }> = [];
  const transport: Brc100Transport = {
    async request(method, params) {
      calls.push({ method, params });
      const h = (handlers as Record<string, ((p: Record<string, unknown>) => Record<string, unknown>) | undefined>)[method];
      if (!h) throw new Brc100Error(404, `no handler for ${method}`);
      return h(params);
    },
  };
  return { transport, calls };
}

// A real DER signature over an arbitrary digest, for round-trip tests.
const SIGNER = PrivateKey.fromRandom();
function derSigHex(): string {
  const der = SIGNER.sign([1, 2, 3, 4]).toDER() as number[];
  return der.map((b) => b.toString(16).padStart(2, '0')).join('');
}

const PROVIDER_PUB = PrivateKey.fromRandom().toPublicKey().toString();

// ── createAction mapping ─────────────────────────────────────────────

describe('IframeWalletPort — createAction → iframe dialect', () => {
  it('maps amountSats to a single funding output and reports committedSats', async () => {
    const { transport, calls } = mockTransport({
      createAction: () => ({ txid: 'abc123', rawTxHex: 'deadbeef' }),
    });
    const port = new IframeWalletPort(transport);
    const res = await port.createAction({
      protocolID: mfpProtocolID('energy.wh'),
      keyID: mfpKeyID('flow1'),
      counterparty: PROVIDER_PUB,
      amountSats: 10n,
      description: 'mfp refill',
    });
    expect(res.ok).toBe(true);
    if (!res.ok) throw new Error('unreachable');
    expect(res.txid).toBe('abc123');
    expect(res.committedSats).toBe(10n);

    const sent = calls[0].params as { outputs: Array<{ scriptHex: string; satoshis: string }>; amountSats: string };
    expect(sent.outputs).toHaveLength(1);
    expect(sent.outputs[0].satoshis).toBe('10'); // decimal string, not bigint
    expect(sent.amountSats).toBe('10');
    // Default funding script is a 25-byte P2PKH.
    expect(sent.outputs[0].scriptHex).toMatch(/^76a914[0-9a-f]{40}88ac$/);
  });

  it('classifies insufficient funds as cap_exceeded (exhaustion)', async () => {
    const { transport } = mockTransport({
      createAction: () => {
        throw new Brc100Error(400, 'insufficient funds', { needed: '10', available: '3' });
      },
    });
    const port = new IframeWalletPort(transport);
    const res = await port.createAction({
      protocolID: mfpProtocolID('energy.wh'),
      keyID: mfpKeyID('f'),
      counterparty: PROVIDER_PUB,
      amountSats: 10n,
      description: 'x',
    });
    expect(res).toEqual({ ok: false, reason: 'cap_exceeded' });
  });

  it('classifies factor-cancel (401) and tier-lock (403) as tier_locked', async () => {
    for (const err of [new Brc100Error(401, 'createAction: factor prompt cancelled', { tier: 1 }), new Brc100Error(403, 'tier locked', { tier: 2 })]) {
      const { transport } = mockTransport({
        createAction: () => {
          throw err;
        },
      });
      const port = new IframeWalletPort(transport);
      const res = await port.createAction({
        protocolID: mfpProtocolID('energy.wh'),
        keyID: mfpKeyID('f'),
        counterparty: PROVIDER_PUB,
        amountSats: 5_000_000n,
        description: 'x',
      });
      expect(res).toEqual({ ok: false, reason: 'tier_locked' });
    }
  });

  it('forwards arcUrl and a custom funding script builder', async () => {
    const { transport, calls } = mockTransport({ createAction: () => ({ txid: 't' }) });
    const port = new IframeWalletPort(transport, {
      arcUrl: 'https://arc.example',
      buildFundingScriptHex: () => '52ae', // a stand-in "channel" script (OP_2 OP_CHECKMULTISIG-ish)
    });
    await port.createAction({
      protocolID: mfpProtocolID('bandwidth.mb'),
      keyID: mfpKeyID('f'),
      counterparty: PROVIDER_PUB,
      amountSats: 7n,
      description: 'x',
    });
    const sent = calls[0].params as { outputs: Array<{ scriptHex: string }>; arcUrl: string };
    expect(sent.outputs[0].scriptHex).toBe('52ae');
    expect(sent.arcUrl).toBe('https://arc.example');
  });
});

// ── createSignature mapping ──────────────────────────────────────────

describe('IframeWalletPort — createSignature → iframe dialect', () => {
  it('sends sha256(data) as digestHex, protocolID string, and a derivationIndex', async () => {
    const { transport, calls } = mockTransport({
      createSignature: () => ({ signatureDer: derSigHex(), tier: 0 }),
    });
    const port = new IframeWalletPort(transport);
    const data = new Uint8Array([9, 8, 7, 6, 5]);
    const res = await port.createSignature({
      protocolID: mfpProtocolID('energy.wh'),
      keyID: mfpKeyID('flowZ'),
      counterparty: PROVIDER_PUB,
      data,
    });
    expect(res.ok).toBe(true);

    const sent = calls[0].params as { digestHex: string; protocolID: string; counterparty: string; derivationIndex: string; amountSats: string };
    const expectDigest = Hash.sha256(Array.from(data)).map((b) => b.toString(16).padStart(2, '0')).join('');
    expect(sent.digestHex).toBe(expectDigest);
    expect(sent.protocolID).toBe('mfp metering energy wh'); // BRC-43 string (commodity dots→spaces, not the [level,string] tuple)
    expect(sent.counterparty).toBe(PROVIDER_PUB);
    expect(sent.amountSats).toBe('0'); // commitment is not a spend → Tier-0
    expect(sent.derivationIndex).toBe(keyIdToDerivationIndex(mfpKeyID('flowZ')).toString());
  });

  it("returns DER bytes by default, 64-byte r||s when signatureFormat='raw'", async () => {
    const der = derSigHex();
    const make = (fmt?: 'der' | 'raw') =>
      new IframeWalletPort(mockTransport({ createSignature: () => ({ signatureDer: der }) }).transport, fmt ? { signatureFormat: fmt } : {});
    const args = {
      protocolID: mfpProtocolID('energy.wh'),
      keyID: mfpKeyID('f'),
      counterparty: PROVIDER_PUB,
      data: new Uint8Array([1]),
    };
    const dres = await make('der').createSignature(args);
    const rres = await make('raw').createSignature(args);
    expect(dres.ok && rres.ok).toBe(true);
    if (!dres.ok || !rres.ok) throw new Error('unreachable');
    expect(Array.from(dres.signature)).toEqual(Array.from(hexToBytes(der))); // unchanged DER
    expect(rres.signature.length).toBe(64); // raw r||s
  });

  it('reports an empty signature as not-ok', async () => {
    const { transport } = mockTransport({ createSignature: () => ({ signatureDer: '' }) });
    const port = new IframeWalletPort(transport);
    const res = await port.createSignature({
      protocolID: mfpProtocolID('energy.wh'),
      keyID: mfpKeyID('f'),
      counterparty: PROVIDER_PUB,
      data: new Uint8Array([1]),
    });
    expect(res.ok).toBe(false);
  });
});

describe('keyIdToDerivationIndex', () => {
  it('is deterministic, non-negative, and within 31 bits', () => {
    const a = keyIdToDerivationIndex('flow abc');
    const b = keyIdToDerivationIndex('flow abc');
    const c = keyIdToDerivationIndex('flow xyz');
    expect(a).toBe(b);
    expect(a).not.toBe(c);
    expect(a).toBeGreaterThanOrEqual(0);
    expect(a).toBeLessThanOrEqual(0x7fffffff);
  });
});

// ── MessagePort transport over a real MessageChannel ─────────────────

/**
 * A fake bridge attached to the other end of a MessageChannel. It echoes
 * the wallet-headers wire: { id, type:'ok', body:{ method, result } } or
 * { id, type:'error', error }.
 */
type FakePort = { onmessage: ((ev: { data: unknown }) => void) | null; postMessage: (m: unknown) => void; start: () => void };
function attachFakeBridge(port: FakePort, respond: (method: string, params: Record<string, unknown>) =>
  | { ok: true; result: Record<string, unknown> }
  | { ok: false; error: { code: number; message: string } }
  | null) {
  port.onmessage = (ev: { data: unknown }) => {
    const data = ev.data as { id: string; type: string; envelope: { body: { method: string; params: Record<string, unknown> } } };
    if (data.type !== 'request') return;
    const { method, params } = data.envelope.body;
    const r = respond(method, params);
    if (r === null) return; // simulate a dropped message (timeout path)
    if (r.ok) port.postMessage({ id: data.id, type: 'ok', body: { method, result: r.result } });
    else port.postMessage({ id: data.id, type: 'error', error: r.error });
  };
  port.start();
}

describe('MessagePortBrc100Transport — wire compat over MessageChannel', () => {
  it('correlates concurrent requests by id and unwraps body.result', async () => {
    const ch = new MessageChannel();
    attachFakeBridge(ch.port2 as unknown as FakePort, (method, params) => ({
      ok: true,
      result: { method, echo: params.tag },
    }));
    const transport = new MessagePortBrc100Transport(ch.port1 as unknown as PortLike, {
      // envelope just carries the body so the fake bridge can read it
      buildEnvelope: (body) => ({ body }),
    });
    const [a, b] = await Promise.all([
      transport.request('createAction', { tag: 'A' }),
      transport.request('createSignature', { tag: 'B' }),
    ]);
    expect(a.echo).toBe('A');
    expect(b.echo).toBe('B');
  });

  it('rejects with a Brc100Error carrying the dispatcher code', async () => {
    const ch = new MessageChannel();
    attachFakeBridge(ch.port2 as unknown as FakePort, () => ({ ok: false, error: { code: 400, message: 'insufficient funds' } }));
    const transport = new MessagePortBrc100Transport(ch.port1 as unknown as PortLike, {
      buildEnvelope: (body) => ({ body }),
    });
    await expect(transport.request('createAction', {})).rejects.toMatchObject({
      name: 'Brc100Error',
      code: 400,
      message: 'insufficient funds',
    });
  });

  it('times out when the bridge never replies', async () => {
    const ch = new MessageChannel();
    attachFakeBridge(ch.port2 as unknown as FakePort, () => null); // drop everything
    const transport = new MessagePortBrc100Transport(ch.port1 as unknown as PortLike, {
      buildEnvelope: (body) => ({ body }),
      timeoutMs: 30,
    });
    await expect(transport.request('createAction', {})).rejects.toMatchObject({ code: 504 });
  });
});

// ── end-to-end: MfpFlowAdapter drains through the iframe port ────────

describe('MfpFlowAdapter on IframeWalletPort (metered drain, end-to-end)', () => {
  it('drains a prepaid channel through the port and exhausts at the cap', async () => {
    // A fake bridge that always funds and always signs — the cap is
    // enforced by the adapter, not the wallet, in this scenario.
    const ch = new MessageChannel();
    let actions = 0;
    let signatures = 0;
    attachFakeBridge(ch.port2 as unknown as FakePort, (method, params) => {
      if (method === 'createAction') {
        actions++;
        return { ok: true, result: { txid: `tx${actions}`, rawTxHex: '00' } };
      }
      // createSignature
      signatures++;
      const der = SIGNER.sign([signatures]).toDER() as number[];
      return { ok: true, result: { signatureDer: der.map((b) => b.toString(16).padStart(2, '0')).join(''), tier: 0 } };
    });
    const port = createPortFromChannel(ch.port1);

    const cfg: MfpFlowConfig = {
      commodityId: 'energy.wh',
      ratePerUnitSats: 360 / 3600, // 10W bulb @ 360 sats/Wh → 1 sat/sec
      counterparty: PROVIDER_PUB,
      flowId: 'e2e-flow',
      fundMode: 'metered',
      vaultCapSats: 30n,
      channelChunkSats: 10n,
      refillThresholdSats: 3n,
    };
    const adapter = new MfpFlowAdapter(cfg, port);
    const opened = await adapter.open();
    expect('kind' in opened && opened.kind === 'opened').toBe(true);

    // Tick once per simulated second of the bulb being on. At 0.1 sat/sec
    // a 30-sat cap covers ~300s; run past that so the drain reaches empty.
    let exhausted = false;
    for (let sec = 1; sec <= 400 && !exhausted; sec++) {
      const step = await adapter.onConsumptionReport(sec);
      if (step.kind === 'exhausted') exhausted = true;
    }
    expect(exhausted).toBe(true);
    const st = adapter.getState();
    expect(st.status).toBe('exhausted');
    // The real invariant: drained EXACTLY the Tier-0 cap, no more.
    expect(st.vaultDrawnSats).toBe(30n);
    expect(actions).toBeGreaterThanOrEqual(3); // 30 / 10-sat chunks
  });
});

// Small helper to keep the e2e test readable.
import { createIframeWalletPort } from '../iframe-wallet-port.js';
function createPortFromChannel(p: unknown): IframeWalletPort {
  return createIframeWalletPort(p as PortLike, { buildEnvelope: (body) => ({ body }) });
}

```
