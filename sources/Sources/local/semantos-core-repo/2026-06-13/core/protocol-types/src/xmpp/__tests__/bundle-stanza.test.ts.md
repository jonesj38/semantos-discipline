---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/xmpp/__tests__/bundle-stanza.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.904126+00:00
---

# core/protocol-types/src/xmpp/__tests__/bundle-stanza.test.ts

```ts
/**
 * D-XMPP-bundle-stanza tests — SignedBundle <-> <message> stanza.
 *
 *   1. round-trip identity (encode → decode preserves the bundle + envelope)
 *   2. ADVERSARIAL payload — &, <, >, ", ', and literal "</bundle>"/"</message>"
 *      in the opaque payload survive XML escaping byte-for-byte
 *   3. the body is JSON, not canonical — JSON.parse round-trip is sig-safe
 *   4. shape validation rejects wrong version / missing chain / bad signature
 *   5. decode error paths (no <bundle> child, missing to/from)
 *   6. optional id + type attributes
 */

import { describe, it, expect } from '@jest/globals';
import {
  encodeBundleStanza,
  decodeBundleStanza,
  bundleChildXml,
  bundleFromText,
  validateBundle,
  parseBundleJson,
  BUNDLE_NS,
} from '../bundle-stanza';
import { ENVELOPE_VERSION, type SignedBundle } from '../../signed-bundle/types';

const SIG = 'ab'.repeat(64); // 128 hex chars

function bundle(payload: string): SignedBundle {
  return {
    v: ENVELOPE_VERSION,
    sender_cert_chain: [
      {
        cert_id: 'a2a3ea741153fabb83c1cf0ef1c00707',
        pubkey: '02' + 'cd'.repeat(32),
        context_tag: 0x10,
        parent_cert_id: null,
      },
    ],
    recipient_cert_id: 'b1b2c3d4e5f60718293a4b5c6d7e8f90',
    payload_type: 'dispatch.request',
    payload,
    signature: SIG,
    signature_metadata: {
      algorithm: 'ecdsa-secp256k1-sha256',
      nonce_hex: 'ef'.repeat(32),
      timestamp_unix: 1_750_000_000,
    },
  };
}

const FROM = 'a2a3ea741153fabb83c1cf0ef1c00707@[2602:f9f8::1]/10';
const TO = 'b1b2c3d4e5f60718293a4b5c6d7e8f90@[2602:f9f8::2]/00';

describe('round-trip', () => {
  it('preserves the bundle and stanza envelope', () => {
    const stanza = { to: TO, from: FROM, type: 'normal' as const, id: 'msg-1', bundle: bundle('{"x":1}') };
    const decoded = decodeBundleStanza(encodeBundleStanza(stanza));
    expect(decoded.to).toBe(TO);
    expect(decoded.from).toBe(FROM);
    expect(decoded.type).toBe('normal');
    expect(decoded.id).toBe('msg-1');
    expect(decoded.bundle).toEqual(stanza.bundle);
  });

  it('defaults type to "normal" and omits id when absent', () => {
    const decoded = decodeBundleStanza(encodeBundleStanza({ to: TO, from: FROM, bundle: bundle('{}') }));
    expect(decoded.type).toBe('normal');
    expect(decoded.id).toBeUndefined();
  });
});

describe('adversarial payload', () => {
  const nasty =
    'amps & <tags> "quotes" \'apos\' </bundle></message> ]]> é\u{1F4A1} {"k":"<v>&amp;"}';

  it('survives XML escaping byte-for-byte through a full round-trip', () => {
    const b = bundle(nasty);
    const decoded = decodeBundleStanza(encodeBundleStanza({ to: TO, from: FROM, bundle: b }));
    expect(decoded.bundle.payload).toBe(nasty);
    expect(decoded.bundle).toEqual(b);
  });

  it('does not let a literal </bundle> in the payload truncate the element', () => {
    // If escaping were wrong, the regex decoder would stop at the injected tag
    // and corrupt the payload. Assert the FULL string came back.
    const decoded = decodeBundleStanza(
      encodeBundleStanza({ to: TO, from: FROM, bundle: bundle('pre</bundle>post') }),
    );
    expect(decoded.bundle.payload).toBe('pre</bundle>post');
  });

  it('escapes the to/from attributes too', () => {
    // Hypothetical attribute injection — the encoder must escape attrs.
    const xml = encodeBundleStanza({ to: 'a&b"<c', from: FROM, bundle: bundle('{}') });
    expect(xml).toContain('a&amp;b&quot;&lt;c');
    expect(decodeBundleStanza(xml).to).toBe('a&b"<c');
  });
});

describe('bundleChildXml / bundleFromText (library-builder seam)', () => {
  it('round-trips through the inner element text', () => {
    const b = bundle('{"hat":"<musician>"}');
    const childXml = bundleChildXml(b);
    expect(childXml).toContain(`xmlns="${BUNDLE_NS}"`);
    // Pull the inner (escaped) text out the way a real XML lib's .text() would.
    const inner = /<bundle[^>]*>([\s\S]*?)<\/bundle>/.exec(childXml)![1]!;
    expect(bundleFromText(inner)).toEqual(b);
  });
});

describe('shape validation', () => {
  it('accepts a well-formed bundle and returns it for chaining', () => {
    const b = bundle('{}');
    expect(validateBundle(b)).toBe(b);
    expect(parseBundleJson(JSON.stringify(b))).toEqual(b);
  });

  it('rejects an unsupported envelope version', () => {
    expect(() => validateBundle({ ...bundle('{}'), v: 2 as unknown as typeof ENVELOPE_VERSION })).toThrow(
      /version/,
    );
  });

  it('rejects a missing/empty sender_cert_chain', () => {
    expect(() => validateBundle({ ...bundle('{}'), sender_cert_chain: [] })).toThrow(/sender_cert_chain/);
  });

  it('rejects a signature that is not 128 hex chars', () => {
    expect(() => validateBundle({ ...bundle('{}'), signature: 'deadbeef' })).toThrow(/signature/);
  });
});

describe('decode error paths', () => {
  it('throws when there is no <bundle> child', () => {
    expect(() => decodeBundleStanza(`<message to="${TO}" from="${FROM}" type="normal"></message>`)).toThrow(
      /no <bundle/,
    );
  });

  it('throws when to/from is missing', () => {
    const child = bundleChildXml(bundle('{}'));
    expect(() => decodeBundleStanza(`<message type="normal">${child}</message>`)).toThrow(/to\/from/);
  });
});

```
