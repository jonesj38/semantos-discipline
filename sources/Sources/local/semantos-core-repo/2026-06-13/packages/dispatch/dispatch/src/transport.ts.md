---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/src/transport.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.512158+00:00
---

# packages/dispatch/dispatch/src/transport.ts

```ts
/**
 * D-O11 phase O11c — in-process bundle transport.
 *
 * For the smoke test, two `Dispatcher`-equivalent in-process brains
 * exchange dispatch envelopes over an in-memory bundle bus instead
 * of the SignedBundle mesh wire. The wire-vs-in-process abstraction
 * is what D-W1 Phase 4 was designed for: swap the implementation,
 * everything above stays.
 *
 * The smoke test uses a synchronous pass-through to keep
 * reproducibility tight (no event-loop scheduling between brains).
 *
 * Per ODDJOBZ-EXTENSION-PLAN.md §3 phase O11 (b): "for v0.1 ship as
 * an extension" if the Semantos Brain extension-loader contract is settled
 * (D-W2 Phase 2 lands the runtime); D-W2 Phase 4 just merged so the
 * runtime is settled. Ships as an extension.
 *
 * This module is the simulation seam, NOT the production transport.
 * Production is `runtime/semantos-brain/src/transport/signed_bundle.zig`. Both
 * implement the same contract: bytes flow from sender brain to
 * receiver brain; the receiver decodes via
 * `dispatchEnvelopeCellType.unpack()` and feeds into
 * `processDispatchEnvelope`.
 */

import {
  dispatchEnvelopeCellType,
  type DispatchEnvelope,
} from './cell-types/index.js';

/** A subscriber that wants envelopes addressed to a particular tenant#hat. */
export type EnvelopeSubscriber = (
  envelope: DispatchEnvelope,
  /** Canonical payload bytes (already hex-decoded). */
  payloadBytes: Uint8Array,
) => Promise<void> | void;

/**
 * In-memory bundle transport. One instance per smoke-test universe;
 * each brain registers its receiving address and a subscriber.
 *
 * Routing key: `<toTenant>#<toHat>`. An envelope addressed to a
 * non-registered key falls into a typed `unaddressed_drop` failure
 * surface that the test harness asserts on (chapter 29's K1 claim:
 * "if the receiving tenant cannot accept, creation fails at the
 * kernel gate"; in this simulation the rejection is at transport-
 * delivery time, mirroring how SignedBundle returns 401/404 when
 * recipient_unavailable).
 */
export class InMemoryBundleTransport {
  private readonly subscribers: Map<string, EnvelopeSubscriber[]> = new Map();
  private readonly auditLog: Array<{
    readonly direction: 'send' | 'deliver' | 'unaddressed';
    readonly envelopeId: string;
    readonly fromTenantHat: string;
    readonly toTenantHat: string;
  }> = [];

  registerReceiver(
    tenant: string,
    hat: string,
    subscriber: EnvelopeSubscriber,
  ): void {
    const key = this.routingKey(tenant, hat);
    const existing = this.subscribers.get(key) ?? [];
    existing.push(subscriber);
    this.subscribers.set(key, existing);
  }

  /**
   * Send an envelope. Returns the number of subscribers it was
   * delivered to. Returns 0 — and logs an `unaddressed` audit row —
   * if no subscriber is registered for the address. The K1 surface
   * claim of chapter 29 is: an envelope cannot be silently dropped.
   * The dispatch handler at the originating brain is what enforces
   * this; the transport here only reports delivery count for that
   * upstream gate to consult.
   */
  async send(envelope: DispatchEnvelope): Promise<number> {
    this.auditLog.push({
      direction: 'send',
      envelopeId: envelope.envelopeId,
      fromTenantHat: this.routingKey(envelope.fromTenant, envelope.fromHat),
      toTenantHat: this.routingKey(envelope.toTenant, envelope.toHat),
    });

    const key = this.routingKey(envelope.toTenant, envelope.toHat);
    const subs = this.subscribers.get(key);
    if (subs === undefined || subs.length === 0) {
      this.auditLog.push({
        direction: 'unaddressed',
        envelopeId: envelope.envelopeId,
        fromTenantHat: this.routingKey(envelope.fromTenant, envelope.fromHat),
        toTenantHat: key,
      });
      return 0;
    }

    const payloadBytes = hexToBytes(envelope.payload);
    for (const sub of subs) {
      this.auditLog.push({
        direction: 'deliver',
        envelopeId: envelope.envelopeId,
        fromTenantHat: this.routingKey(envelope.fromTenant, envelope.fromHat),
        toTenantHat: key,
      });
      await sub(envelope, payloadBytes);
    }
    return subs.length;
  }

  /** Snapshot of the audit log — useful for tests asserting routing flow. */
  audit(): ReadonlyArray<(typeof this.auditLog)[number]> {
    return [...this.auditLog];
  }

  /** Clear the audit log between smoke-test scenarios. */
  resetAudit(): void {
    this.auditLog.length = 0;
  }

  private routingKey(tenant: string, hat: string): string {
    return `${tenant}#${hat}`;
  }
}

/**
 * Encode a `DispatchEnvelope` into wire bytes via the cell-type's
 * canonical packer. Used by the smoke test to round-trip envelopes
 * through the transport — a real SignedBundle wraps these bytes
 * inside its bundle envelope.
 */
export function packEnvelope(envelope: DispatchEnvelope): Uint8Array {
  return dispatchEnvelopeCellType.pack(envelope);
}

/** Inverse of {@link packEnvelope}. */
export function unpackEnvelope(bytes: Uint8Array): DispatchEnvelope {
  return dispatchEnvelopeCellType.unpack(bytes);
}

export function bytesToHex(b: Uint8Array): string {
  let s = '';
  for (let i = 0; i < b.length; i++) {
    s += (b[i] as number).toString(16).padStart(2, '0');
  }
  return s;
}

export function hexToBytes(hex: string): Uint8Array {
  if (hex.length % 2 !== 0) throw new Error('hexToBytes: odd-length string');
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

```
