---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/xmpp/__tests__/jid.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.904411+00:00
---

# core/protocol-types/src/xmpp/__tests__/jid.test.ts

```ts
/**
 * D-XMPP-jid-binding tests — JID grammar `certId@[BCA]/hat`.
 *
 *   1. node-JID round-trip (build → parse is identity, incl. hat hex)
 *   2. bare-JID round-trip + bare/full relationship
 *   3. context-tag <-> resource encoding (root=00, carpenter=10, musician=11)
 *   4. validation / error paths (bad certId, bracketed BCA, out-of-range hat)
 *   5. IPv6 case-normalisation on parse
 *   6. pubsubAddressForType mapping
 */

import { describe, it, expect } from '@jest/globals';
import {
  jidForNode,
  parseJid,
  bareJidForNode,
  parseBareJid,
  contextTagToResource,
  resourceToContextTag,
  pubsubAddressForType,
} from '../jid';

const CERT = 'a2a3ea741153fabb83c1cf0ef1c00707';
const BCA = '2602:f9f8::a3f8:b2c1';

describe('contextTag <-> resource', () => {
  it('encodes the canonical hats as 2-char lowercase hex', () => {
    expect(contextTagToResource(0)).toBe('00'); // root
    expect(contextTagToResource(0x10)).toBe('10'); // carpenter
    expect(contextTagToResource(0x11)).toBe('11'); // musician
    expect(contextTagToResource(255)).toBe('ff');
  });

  it('round-trips every byte value', () => {
    for (let t = 0; t <= 255; t++) {
      expect(resourceToContextTag(contextTagToResource(t))).toBe(t);
    }
  });

  it('rejects out-of-range or non-integer tags', () => {
    expect(() => contextTagToResource(-1)).toThrow();
    expect(() => contextTagToResource(256)).toThrow();
    expect(() => contextTagToResource(1.5)).toThrow();
  });

  it('rejects malformed resources', () => {
    expect(() => resourceToContextTag('1')).toThrow();
    expect(() => resourceToContextTag('GG')).toThrow();
    expect(() => resourceToContextTag('100')).toThrow();
  });
});

describe('node JID round-trip', () => {
  it('builds and parses back to identity', () => {
    const jid = jidForNode({ certId: CERT, bcaIPv6: BCA, contextTag: 0x10 });
    expect(jid).toBe(`${CERT}@[${BCA}]/10`);
    const parts = parseJid(jid);
    expect(parts).toEqual({ certId: CERT, bcaIPv6: BCA, contextTag: 0x10 });
  });

  it('round-trips the root hat (00)', () => {
    const jid = jidForNode({ certId: CERT, bcaIPv6: BCA, contextTag: 0 });
    expect(parseJid(jid).contextTag).toBe(0);
  });

  it('lowercases an upper-case IPv6 literal on parse', () => {
    const parts = parseJid(`${CERT}@[2602:F9F8::A3F8:B2C1]/11`);
    expect(parts.bcaIPv6).toBe('2602:f9f8::a3f8:b2c1');
    expect(parts.contextTag).toBe(0x11);
  });
});

describe('bare JID', () => {
  it('round-trips certId@[BCA]', () => {
    const bare = bareJidForNode({ certId: CERT, bcaIPv6: BCA });
    expect(bare).toBe(`${CERT}@[${BCA}]`);
    expect(parseBareJid(bare)).toEqual({ certId: CERT, bcaIPv6: BCA });
  });

  it('is the node JID with the resource stripped', () => {
    const full = jidForNode({ certId: CERT, bcaIPv6: BCA, contextTag: 0x10 });
    const bare = bareJidForNode({ certId: CERT, bcaIPv6: BCA });
    expect(full.startsWith(bare + '/')).toBe(true);
  });
});

describe('validation / error paths', () => {
  it('rejects a non-32-hex certId', () => {
    expect(() => jidForNode({ certId: 'TOOSHORT', bcaIPv6: BCA, contextTag: 0 })).toThrow();
    expect(() => jidForNode({ certId: CERT.toUpperCase(), bcaIPv6: BCA, contextTag: 0 })).toThrow();
  });

  it('rejects an already-bracketed BCA (caller passes the unbracketed form)', () => {
    expect(() => jidForNode({ certId: CERT, bcaIPv6: `[${BCA}]`, contextTag: 0 })).toThrow();
    expect(() => bareJidForNode({ certId: CERT, bcaIPv6: `[${BCA}]` })).toThrow();
  });

  it('rejects unparseable JIDs', () => {
    expect(() => parseJid('not-a-jid')).toThrow();
    expect(() => parseJid(`${CERT}@[${BCA}]`)).toThrow(); // bare, missing resource
    expect(() => parseBareJid(`${CERT}@[${BCA}]/10`)).toThrow(); // full, has resource
  });
});

describe('pubsubAddressForType', () => {
  it('maps a multicast group + service into a pubsub address', () => {
    const addr = pubsubAddressForType({
      multicastIPv6: 'ff15:4ed1:aabd:873d:e970:0000:0000:0000',
      serviceJid: 'pubsub.home',
    });
    expect(addr).toEqual({ service: 'pubsub.home', node: 'ff15:4ed1:aabd:873d:e970:0000:0000:0000' });
  });
});

```
