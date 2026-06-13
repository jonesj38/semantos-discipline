---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/agent-cert-provider.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.518698+00:00
---

# cartridges/oddjobz/brain/src/conversation/agent-cert-provider.ts

```ts
/**
 * P3.4 — agent-cert provider (DECISION-P4C / Phase-3; identity model
 * §"3 principals", operator-chosen option 2).
 *
 * The chat-widget AI agent is its OWN least-privilege child cert under
 * the operator root. It is provisioned via the EXISTING shipped D-O5p
 * pairing endpoint — `POST /api/v1/device-pair`
 * (`device_pair_http.zig`, live on the deployed brain) — NOT a
 * net-new brain surface. This module orchestrates the shipped
 * `device-pair-client.ts` primitives (decode → BRC-42 child derive →
 * accept-body → POST → parse) into a single `provision()` that yields
 * the `(hatId, certId)` the P3.2 brain-submit envelope needs:
 *
 *   hatId  = response.brain_cert_id   (operator-root cert, 32 hex)
 *   certId = response.cert_id         (the newly-issued agent child)
 *
 * The operator signs the pairing token out-of-band with the operator
 * ROOT key (granting the agent's narrow cap allowlist, e.g.
 * cap.oddjobz.write_customer) — NO edge crypto, NO key on the edge.
 * The actual live pairing call mints a real cert in the live brain
 * cert store, so it is a one-time provisioning step gated with P3.5
 * (operator-approved); here it is fully deps-injected so the
 * orchestration is unit-tested with a mock transport (ZERO live).
 *
 * BRC-42 derivation correctness is the SHIPPED device-pair-client's
 * responsibility (proven by tests/device-pair-roundtrip.test.ts +
 * the Zig device_pair_http conformance). This module only wires it.
 */

import type {
  DecodedPairingPayload,
  DerivedChild,
} from '../device-pair-client.js';
import type {
  EnvelopeContext,
  KernelResultClaim,
} from './brain-submit-storage.js';
import { acceptRomTargetJson } from './accept-rom-target.js';

// device-pair-client statically pulls @bsv/sdk. Loaded LAZILY (only
// when the real shipped primitives are actually needed — i.e. real
// pairing, never in mock-injected unit tests) so this module stays in
// the pure/worktree-verified/zero-live tier; tests inject `primitives`
// and never trigger the @bsv import.
async function loadShippedPrimitives(): Promise<PairingPrimitives> {
  const m = await import('../device-pair-client.js');
  return {
    decode: m.decodePairingToken,
    genDevicePriv: m.generateDevicePriv,
    derive: m.deriveChildKeyMaterial,
    buildBody: m.buildAcceptRequestBody,
  };
}

/** The cert identifiers the P3.2 EnvelopeContext needs. */
export interface AgentCert {
  /** Operator-root cert id (32 hex) — envelope.hatId. */
  readonly hatId: string;
  /** Newly-issued agent child cert id (32 hex) — envelope.certId. */
  readonly certId: string;
}

export type FetchLike = (
  url: string,
  init: { method: string; headers: Record<string, string>; body: string },
) => Promise<{ status: number; text: () => Promise<string> }>;

/** Seam over the shipped device-pair-client primitives so the
 *  orchestration is unit-testable without re-running BRC-42 here
 *  (that path is proven by the client's own conformance suite). */
export interface PairingPrimitives {
  decode(token: string): DecodedPairingPayload;
  genDevicePriv(): { privHex: string; pubHex: string };
  derive(
    devicePrivHex: string,
    operatorRootPubHex: string,
    contextTag: number,
    label: string,
  ): DerivedChild;
  buildBody(
    token: string,
    derived: DerivedChild,
  ): { token: string; derivation_pubkey: string; derivation_proof: string };
}

export interface AgentCertProviderInput {
  /** Operator-signed base64url pairing token granting the agent's
   *  narrow capability allowlist (operator-root-signed, out-of-band). */
  readonly pairingToken: string;
  /** Injected transport; defaults to global fetch. */
  readonly fetchFn?: FetchLike;
  /** Override device priv (tests/deterministic); default = CSPRNG. */
  readonly devicePrivHex?: string;
  /** Override the shipped pairing primitives (tests). */
  readonly primitives?: PairingPrimitives;
}

export interface AgentCertProvider {
  /** Pair (once) and return the agent cert. Cached: pairing is a
   *  one-time provisioning step; repeat calls return the cached cert. */
  provision(): Promise<AgentCert>;
}

function isHex32(s: unknown): s is string {
  return typeof s === 'string' && /^[0-9a-f]{32}$/.test(s);
}

export function makeAgentCertProvider(
  input: AgentCertProviderInput,
): AgentCertProvider {
  const fetchFn =
    input.fetchFn ??
    ((url, init) => (globalThis.fetch as unknown as FetchLike)(url, init));
  let cached: AgentCert | null = null;
  let inflight: Promise<AgentCert> | null = null;

  async function pair(): Promise<AgentCert> {
    const P = input.primitives ?? (await loadShippedPrimitives());
    const decoded = P.decode(input.pairingToken);
    const devicePrivHex =
      input.devicePrivHex ?? P.genDevicePriv().privHex;
    const derived = P.derive(
      devicePrivHex,
      decoded.operatorRootPub,
      decoded.contextTag,
      decoded.label,
    );
    const body = P.buildBody(input.pairingToken, derived);
    const res = await fetchFn(decoded.brainPairEndpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const text = await res.text();
    if (res.status < 200 || res.status >= 300) {
      throw new Error(
        `device-pair HTTP ${res.status}: ${text.slice(0, 300)}`,
      );
    }
    let parsed: { status?: string; cert_id?: string; brain_cert_id?: string };
    try {
      parsed = JSON.parse(text);
    } catch {
      throw new Error(`device-pair: non-JSON response: ${text.slice(0, 200)}`);
    }
    if (parsed.status !== 'registered') {
      throw new Error(
        `device-pair: status=${parsed.status ?? '<none>'} (expected "registered"): ${text.slice(0, 300)}`,
      );
    }
    if (!isHex32(parsed.cert_id) || !isHex32(parsed.brain_cert_id)) {
      throw new Error(
        `device-pair: cert_id/brain_cert_id must be 32-hex; got ${parsed.cert_id}/${parsed.brain_cert_id}`,
      );
    }
    return { hatId: parsed.brain_cert_id, certId: parsed.cert_id };
  }

  return {
    provision(): Promise<AgentCert> {
      if (cached) return Promise.resolve(cached);
      if (inflight) return inflight;
      inflight = pair().then(
        (c) => {
          cached = c;
          inflight = null;
          return c;
        },
        (e) => {
          inflight = null;
          throw e;
        },
      );
      return inflight;
    },
  };
}

// ─────────────────────────────────────────────────────────────────────
// P3.4 glue — assemble the P3.2 EnvelopeContext for an oddjobz
// accept_rom intent-cell, from: the provisioned agent cert + the
// pipeline's kernelResult + the intake's ROM range. The brain's
// intent_action_router, on an accept_rom-class action WITH a
// parseable targetJson, mints an accepted auto_rom Estimate from the
// {costMin,costMax} range + flips lead→qualified (intent-cell-v1
// spec). oddjobz.lead.v1 lands via that shipped ratify path (SD2).
// Pure; the oddjobz-correct taxonomy/action lives here (no longer the
// P3.1 spike's golden jural placeholder).
// ─────────────────────────────────────────────────────────────────────

export interface AcceptRomEnvelopeArgs {
  readonly agentCert: AgentCert;
  readonly correlationId: string;
  readonly kernelResult: KernelResultClaim;
  /** ROM range, smallest currency unit (cents). */
  readonly costMin: number;
  readonly costMax: number;
  readonly currency?: string;
  /** Resolved entity refs when known (omitted pre-resolution). */
  readonly jobId?: string;
  readonly customerId?: string;
  /** Operator-readable summary for the AttentionFeed. */
  readonly summary: string;
}

/** Build the EnvelopeContext for an oddjobz `accept_rom` cell. */
export function assembleAcceptRomEnvelopeContext(
  a: AcceptRomEnvelopeArgs,
): EnvelopeContext {
  return {
    hatId: a.agentCert.hatId,
    certId: a.agentCert.certId,
    correlationId: a.correlationId,
    kernelResult: a.kernelResult,
    originalIntent: {
      summary: a.summary,
      action: 'accept_rom',
      taxonomyJson: JSON.stringify({
        what: 'oddjobz.lead.v1',
        how: 'oddjobz.accept_rom',
        why: 'chat-intake',
      }),
      targetJson: acceptRomTargetJson({
        ...(a.jobId !== undefined ? { jobId: a.jobId } : {}),
        ...(a.customerId !== undefined ? { customerId: a.customerId } : {}),
        costMin: a.costMin,
        costMax: a.costMax,
        ...(a.currency !== undefined ? { currency: a.currency } : {}),
      }),
    },
  };
}

```
