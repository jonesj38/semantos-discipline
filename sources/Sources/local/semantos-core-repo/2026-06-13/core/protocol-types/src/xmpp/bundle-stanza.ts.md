---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/xmpp/bundle-stanza.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.862908+00:00
---

# core/protocol-types/src/xmpp/bundle-stanza.ts

```ts
/**
 * D-XMPP-bundle-stanza — SignedBundle ⇄ XMPP <message> stanza.
 *
 * Carries an unchanged SignedBundle (the brain-to-brain wire shape) as the
 * body of an XMPP <message>.  XMPP is dumb transport here: it provides
 * routing, presence, and offline queueing (MAM); the SignedBundle keeps
 * owning identity (cert chain), auth (ECDSA), and anti-replay (nonce +
 * timestamp).  Adopting XMPP therefore never forks the wire format — a
 * `POST /api/v1/bundle` body and this stanza body carry the identical bundle.
 *
 * Transport serialization note: the stanza body uses ordinary JSON
 * (JSON.stringify), NOT the canonical encoder.  Canonical ordering only
 * matters for the SIGNATURE PREIMAGE, which the receiver re-derives from the
 * parsed struct via `canonicalSignaturePreimage` before verifying.  So a
 * round-trip through JSON.parse is signature-safe.
 *
 * This module has zero crypto dependencies — it imports only the wire TYPES.
 * Signing/verifying stays in send-bundle.ts (TS) + signed_bundle.zig (Zig).
 *
 * Cross-reference: docs/design/SRS-XMPP-IDENTITY-TRANSPORT.md §3.
 */

import type { SignedBundle } from '../signed-bundle/types';
import { ENVELOPE_VERSION } from '../signed-bundle/types';

/** XML namespace for the embedded bundle element. */
export const BUNDLE_NS = 'urn:semantos:signed-bundle:1';

export interface BundleStanza {
  /** Recipient JID (certId@[BCA]/hat). */
  to: string;
  /** Sender JID (certId@[BCA]/hat). */
  from: string;
  /** XMPP stanza type; brain dispatch is fire-and-collect, so "normal". */
  type?: 'chat' | 'normal';
  /** Optional stanza id for tracking. */
  id?: string;
  /** The unchanged SignedBundle. */
  bundle: SignedBundle;
}

// ─────────────────────────────────────────────────────────────────────
// XML escaping — escape the five predefined entities so the JSON body
// (which may contain &, <, >, ", ' in the opaque payload) survives as XML
// text/attribute content.
// ─────────────────────────────────────────────────────────────────────

function xmlEscape(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function xmlUnescape(s: string): string {
  // &amp; must be undone LAST so "&amp;lt;" → "&lt;" (not "<").
  return s
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&');
}

/**
 * Encode a SignedBundle into an XMPP <message> stanza (string form).
 *
 * Integration note: at wiring time, prefer building the element with your
 * XMPP library's element builder (e.g. @xmpp/xml `xml(...)`) and inserting
 * `bundleChildXml()` as a raw child — that gives you proper stream framing.
 * This string form is self-contained for tests and non-library transports.
 */
export function encodeBundleStanza(s: BundleStanza): string {
  const type = s.type ?? 'normal';
  const idAttr = s.id ? ` id="${xmlEscape(s.id)}"` : '';
  return (
    `<message to="${xmlEscape(s.to)}" from="${xmlEscape(s.from)}" type="${type}"${idAttr}>` +
    bundleChildXml(s.bundle) +
    `</message>`
  );
}

/** The inner `<bundle>` child element, for callers using a real XML builder. */
export function bundleChildXml(bundle: SignedBundle): string {
  return `<bundle xmlns="${BUNDLE_NS}">${xmlEscape(JSON.stringify(bundle))}</bundle>`;
}

// ─────────────────────────────────────────────────────────────────────
// Decode.  v0.1 self-parser scoped to the well-formed output of
// `encodeBundleStanza`.  At integration, replace with the XMPP library's
// parsed element + `bundleFromText(element.getChild('bundle', BUNDLE_NS).text())`.
// ─────────────────────────────────────────────────────────────────────

const ATTR_RE = (name: string) => new RegExp(`\\b${name}="([^"]*)"`);
const BUNDLE_EL_RE = new RegExp(
  `<bundle\\s+xmlns="${BUNDLE_NS}"\\s*>([\\s\\S]*?)</bundle>`,
);

/**
 * Shape-validate a decoded bundle (NOT signature verification — that stays in
 * send-bundle.ts / signed_bundle.zig).  Returns the same object for chaining.
 */
export function validateBundle(bundle: SignedBundle): SignedBundle {
  if (bundle.v !== ENVELOPE_VERSION) {
    throw new Error(`unsupported bundle version: ${bundle.v} (expected ${ENVELOPE_VERSION})`);
  }
  if (!Array.isArray(bundle.sender_cert_chain) || bundle.sender_cert_chain.length < 1) {
    throw new Error('bundle missing sender_cert_chain');
  }
  if (typeof bundle.signature !== 'string' || bundle.signature.length !== 128) {
    throw new Error('bundle signature must be 128 hex chars');
  }
  return bundle;
}

/** Parse + shape-validate a bundle from raw (un-escaped) JSON. */
export function parseBundleJson(json: string): SignedBundle {
  return validateBundle(JSON.parse(json) as SignedBundle);
}

/** Parse a bundle out of the inner element's (XML-escaped) text content. */
export function bundleFromText(text: string): SignedBundle {
  return parseBundleJson(xmlUnescape(text));
}

/** Decode an XMPP <message> stanza (string form) back into a BundleStanza. */
export function decodeBundleStanza(xml: string): BundleStanza {
  const el = BUNDLE_EL_RE.exec(xml);
  if (!el) {
    throw new Error(`no <bundle xmlns="${BUNDLE_NS}"> child found in stanza`);
  }
  const to = ATTR_RE('to').exec(xml);
  const from = ATTR_RE('from').exec(xml);
  if (!to || !from) {
    throw new Error('stanza missing to/from attribute');
  }
  const typeM = ATTR_RE('type').exec(xml);
  const idM = ATTR_RE('id').exec(xml);
  const type = typeM ? (xmlUnescape(typeM[1]!) as 'chat' | 'normal') : undefined;
  return {
    to: xmlUnescape(to[1]!),
    from: xmlUnescape(from[1]!),
    ...(type ? { type } : {}),
    ...(idM ? { id: xmlUnescape(idM[1]!) } : {}),
    bundle: bundleFromText(el[1]!),
  };
}

```
