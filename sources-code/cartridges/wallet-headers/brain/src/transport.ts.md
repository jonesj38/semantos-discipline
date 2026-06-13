---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/transport.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.653095+00:00
---

# cartridges/wallet-headers/brain/src/transport.ts

```ts
// WT-Transport — multi-target envelope share (v0.4).
//
// The recovery envelope produced by `plexus/envelope.ts::buildEnvelope` is
// safe to publish (per WALLET-TIER-CUSTODY.md §4.0 + §8.2): only the user's
// challenge answers — never persisted in the envelope, only in the user's
// head — can decrypt it. So the user can mirror it to whatever channel they
// trust (email, Drive, Telegram, IPFS, QR, OP_RETURN, …) on the same threat
// model as Plexus storage, just without Plexus's live rate-limiting.
//
// For this v0.4 wallet — pitched as identity + ~$10 of micropayment budget,
// NOT a vault — that trade-off is acceptable. Larger amounts go in a future
// composable "vault" with stronger challenges + hardware keys.
//
// This module is the abstraction layer. Each transport is an object that
// implements `EnvelopeTransport`; the popup-create flow calls
// `defaultTransports()` to enumerate which channels are usable in the
// current environment, then renders a multi-select-friendly picker.
//
// Day-1 transports: WebShare (OS share sheet — iOS/Android), Download
// (universal fallback), Clipboard (paste-anywhere base64). Future transports
// (QR code, mailto, Drive/IPFS/1Password OAuth, Plexus refactor) are noted
// in the design doc and implemented in follow-up PRs.
//
// No new npm/bun deps — Web APIs only.

import type { PlexusRecoveryEnvelope } from './plexus/envelope';

// ──────────────────────────────────────────────────────────────────────
// Public types
// ──────────────────────────────────────────────────────────────────────

export type TransportResult =
  | { ok: true; receipt?: string }
  | { ok: false; reason: 'cancelled' | 'unavailable' | 'failed'; detail?: string };

export interface SerializedEnvelope {
  /** UTF-8 JSON of the full PlexusRecoveryEnvelope. */
  json: string;
  /** Convenience: the same JSON as base64. */
  base64: string;
  /** Raw bytes — for transports that prefer Uint8Array (downloads,
   *  Web Share files). */
  bytes: Uint8Array;
  /** A safe filename hint, e.g. "semantos-wallet-recovery-2026-04-27.envelope". */
  suggestedFilename: string;
}

export interface EnvelopeTransport {
  /** Stable id used for routing + telemetry. */
  id: string;
  /** Human-readable name shown in the share picker. */
  name: string;
  /** Optional inline-SVG icon path or emoji. */
  icon?: string;
  /** Capability check — return false if this transport isn't usable
   *  in the current environment (e.g., no Web Share API on desktop). */
  isAvailable(): boolean;
  /** One-shot send. Resolves to a structured Result so the UI can
   *  render success / failure / cancellation distinctly. */
  send(envelope: SerializedEnvelope): Promise<TransportResult>;
}

// ──────────────────────────────────────────────────────────────────────
// Serialization helpers
// ──────────────────────────────────────────────────────────────────────

/**
 * Serialize a PlexusRecoveryEnvelope into the four shapes transports may want:
 * UTF-8 JSON string, base64 of that JSON, raw bytes, and a suggested
 * filename including today's date.
 *
 * The filename uses ISO-8601 date (`YYYY-MM-DD`) and the `.envelope`
 * extension — distinct from `.json` so the user can spot it in a picker
 * without learning the schema.
 */
export function serializeEnvelope(envelope: PlexusRecoveryEnvelope, now: Date = new Date()): SerializedEnvelope {
  const json = JSON.stringify(envelope);
  const bytes = new TextEncoder().encode(json);
  const base64 = bytesToBase64(bytes);
  const yyyy = now.getUTCFullYear().toString().padStart(4, '0');
  const mm = (now.getUTCMonth() + 1).toString().padStart(2, '0');
  const dd = now.getUTCDate().toString().padStart(2, '0');
  const suggestedFilename = `semantos-wallet-recovery-${yyyy}-${mm}-${dd}.envelope`;
  return { json, base64, bytes, suggestedFilename };
}

function bytesToBase64(bytes: Uint8Array): string {
  // btoa is available in browser + bun. The environment-agnostic route is
  // to build the binary string manually so we don't depend on Buffer.
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]!);
  // btoa is defined in DOM lib + bun-types' globals.
  return btoa(s);
}

// ──────────────────────────────────────────────────────────────────────
// WebShareTransport — iOS/Android OS share sheet (Telegram/Mail/Drive/Files…)
// ──────────────────────────────────────────────────────────────────────

/**
 * Uses `navigator.share({ files: [...] })` so mobile platforms hand the
 * envelope to the user's preferred app via the OS share sheet. Desktop
 * Chrome/Edge implement `navigator.share` for text/URL but typically not
 * for files — we gate on `navigator.canShare({ files: [...] })`.
 */
export class WebShareTransport implements EnvelopeTransport {
  readonly id = 'web-share';
  readonly name = 'Share…';
  readonly icon = '↗';

  isAvailable(): boolean {
    if (typeof navigator === 'undefined') return false;
    if (typeof navigator.share !== 'function') return false;
    // canShare is optional in the spec; if absent, fall back to "share is
    // present, hope for the best" — but a stub File is required to ask.
    if (typeof navigator.canShare !== 'function') return true;
    try {
      // A 1-byte placeholder file is enough for the capability probe.
      const probe = new File([new Uint8Array(1)], 'probe.envelope', { type: 'application/octet-stream' });
      return navigator.canShare({ files: [probe] });
    } catch {
      return false;
    }
  }

  async send(envelope: SerializedEnvelope): Promise<TransportResult> {
    if (!this.isAvailable()) {
      return { ok: false, reason: 'unavailable' };
    }
    try {
      const file = new File([envelope.bytes], envelope.suggestedFilename, {
        type: 'application/octet-stream',
      });
      await (navigator as Navigator & {
        share: (data: { files?: File[]; title?: string; text?: string }) => Promise<void>;
      }).share({
        files: [file],
        title: 'Semantos wallet recovery envelope',
        text: 'My wallet recovery envelope — keep this somewhere I can find it later.',
      });
      return { ok: true };
    } catch (e) {
      const msg = (e as Error).message ?? '';
      // Web Share rejects with AbortError on user cancel.
      if ((e as Error).name === 'AbortError' || /abort|cancel/i.test(msg)) {
        return { ok: false, reason: 'cancelled' };
      }
      return { ok: false, reason: 'failed', detail: msg };
    }
  }
}

// ──────────────────────────────────────────────────────────────────────
// DownloadTransport — universal fallback (anchor + object URL)
// ──────────────────────────────────────────────────────────────────────

/**
 * `URL.createObjectURL(new Blob([bytes]))` + invisible `<a download>`. The
 * one transport guaranteed to work on every platform with a DOM. Side-
 * effect: triggers the browser's download UI.
 */
export class DownloadTransport implements EnvelopeTransport {
  readonly id = 'download';
  readonly name = 'Download';
  readonly icon = '⬇';

  isAvailable(): boolean {
    return typeof document !== 'undefined' && typeof URL !== 'undefined' && typeof URL.createObjectURL === 'function';
  }

  async send(envelope: SerializedEnvelope): Promise<TransportResult> {
    if (!this.isAvailable()) {
      return { ok: false, reason: 'unavailable' };
    }
    try {
      const blob = new Blob([envelope.bytes], { type: 'application/octet-stream' });
      const url = URL.createObjectURL(blob);
      try {
        const a = document.createElement('a');
        a.href = url;
        a.download = envelope.suggestedFilename;
        a.style.display = 'none';
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
      } finally {
        // Revoke on the next macrotask so the browser has time to start the
        // download. Some engines drop the URL synchronously if revoked too
        // soon; setTimeout(0) is the canonical fix.
        setTimeout(() => URL.revokeObjectURL(url), 0);
      }
      return { ok: true, receipt: envelope.suggestedFilename };
    } catch (e) {
      return { ok: false, reason: 'failed', detail: (e as Error).message };
    }
  }
}

// ──────────────────────────────────────────────────────────────────────
// ClipboardTransport — base64 → clipboard (paste anywhere)
// ──────────────────────────────────────────────────────────────────────

/**
 * `navigator.clipboard.writeText(serialized.base64)` so the user can paste
 * the envelope into a notes app, password manager, encrypted chat, etc.
 * Base64 (not raw JSON) so the result is one line and survives transport
 * across systems that mangle whitespace.
 */
export class ClipboardTransport implements EnvelopeTransport {
  readonly id = 'clipboard';
  readonly name = 'Copy';
  readonly icon = '⧉';

  isAvailable(): boolean {
    return (
      typeof navigator !== 'undefined' &&
      !!navigator.clipboard &&
      typeof navigator.clipboard.writeText === 'function'
    );
  }

  async send(envelope: SerializedEnvelope): Promise<TransportResult> {
    if (!this.isAvailable()) {
      return { ok: false, reason: 'unavailable' };
    }
    try {
      await navigator.clipboard.writeText(envelope.base64);
      return { ok: true, receipt: 'copied to clipboard' };
    } catch (e) {
      const msg = (e as Error).message ?? '';
      if (/permiss|denied/i.test(msg)) {
        return { ok: false, reason: 'unavailable', detail: msg };
      }
      return { ok: false, reason: 'failed', detail: msg };
    }
  }
}

// ──────────────────────────────────────────────────────────────────────
// Registry
// ──────────────────────────────────────────────────────────────────────

/**
 * The Day-1 transport set, filtered to those that report `isAvailable()`
 * in the current environment. Order is the priority the popup picker
 * surfaces them in: WebShare first (best UX on mobile), Download (universal
 * fallback), Clipboard (paste-anywhere).
 *
 * Future transports (QR, mailto, Drive/IPFS/1Password OAuth, refactored
 * Plexus) plug into the same registry — see the design doc §6.5 / §7.6.
 */
export function defaultTransports(): EnvelopeTransport[] {
  return [new WebShareTransport(), new DownloadTransport(), new ClipboardTransport()].filter((t) =>
    t.isAvailable(),
  );
}

```
