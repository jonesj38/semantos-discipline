---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/conversation/hat-scoping.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.488482+00:00
---

# cartridges/oddjobz/brain/tests/conversation/hat-scoping.test.ts

```ts
/**
 * D-O7 — hat-scoping tests.
 *
 * Acceptance:
 *  - buildHat enforces uint8 contextTag.
 *  - Operator hat carries OPERATOR_ROOT_CAPS by default; service hat
 *    carries NODE_SERVICE_CAPS.
 *  - assertHatScopedCap accepts matching contextTags + rejects
 *    mismatched ones (Finding 1's K3 fix).
 *  - selectHatForCap picks the right hat by contextTag.
 *  - Cell-presented contextTag is read from header offset 62.
 */

import { describe, expect, test } from 'bun:test';
import {
  buildHat,
  assertHatScopedCap,
  presentedContextTag,
  selectHatForCap,
  hatCarriesCap,
  sameHat,
  CARPENTER_CONTEXT_TAG,
  MUSICIAN_CONTEXT_TAG,
  DEFAULT_HAT_CONTEXT_TAG,
} from '../../src/conversation/hat-scoping.js';
import type { PresentedCap } from '../../src/state-machines/kernel-gate.js';
import {
  capWriteCustomer,
  capPublicChatServe,
  mintCapabilityCell,
  OPERATOR_ROOT_CAPS,
  NODE_SERVICE_CAPS,
} from '../../src/capabilities.js';

const STUB_OWNER = new Uint8Array(16); // all-zeros owner_id stub

describe('D-O7 — hat-scoping — buildHat', () => {
  test('operator hat carries the full OPERATOR_ROOT_CAPS set', () => {
    const hat = buildHat({
      hatId: 'carpenter',
      contextTag: CARPENTER_CONTEXT_TAG,
      principal: 'operator',
      facetId: 'facet-todd',
    });
    expect(hat.capabilities.length).toBe(OPERATOR_ROOT_CAPS.length);
    for (const c of OPERATOR_ROOT_CAPS) {
      expect(hat.capabilities).toContain(c.name);
    }
  });

  test('service hat carries NODE_SERVICE_CAPS', () => {
    const hat = buildHat({
      hatId: 'public-chat',
      contextTag: DEFAULT_HAT_CONTEXT_TAG,
      principal: 'service',
      facetId: 'facet-svc',
    });
    expect(hat.capabilities).toEqual(
      Object.freeze(NODE_SERVICE_CAPS.map((c) => c.name)),
    );
  });

  test('rejects out-of-range contextTag (uint8 contract)', () => {
    expect(() =>
      buildHat({
        hatId: 'bad',
        contextTag: 256,
        principal: 'operator',
        facetId: 'f',
      }),
    ).toThrow(/uint8/);
    expect(() =>
      buildHat({
        hatId: 'bad',
        contextTag: -1,
        principal: 'operator',
        facetId: 'f',
      }),
    ).toThrow(/uint8/);
  });

  test('explicit capabilities override the default set', () => {
    const hat = buildHat({
      hatId: 'phone-child',
      contextTag: 0x42,
      principal: 'operator',
      facetId: 'f',
      capabilities: ['cap.oddjobz.write_customer', 'cap.oddjobz.quote'],
    });
    expect(hat.capabilities).toEqual([
      'cap.oddjobz.write_customer',
      'cap.oddjobz.quote',
    ]);
  });

  test('hatCarriesCap reads the declared set', () => {
    const hat = buildHat({
      hatId: 'carpenter',
      contextTag: 0x01,
      principal: 'operator',
      facetId: 'f',
    });
    expect(hatCarriesCap(hat, 'cap.oddjobz.write_customer')).toBe(true);
    // service-only cap is NOT in the operator-root set.
    expect(hatCarriesCap(hat, 'cap.oddjobz.public_chat_serve')).toBe(false);
  });

  test('sameHat compares (hatId, contextTag, facetId) tuple', () => {
    const a = buildHat({
      hatId: 'carpenter',
      contextTag: 0x01,
      principal: 'operator',
      facetId: 'f',
    });
    const b = buildHat({
      hatId: 'carpenter',
      contextTag: 0x01,
      principal: 'operator',
      facetId: 'f',
    });
    const c = buildHat({
      hatId: 'carpenter',
      contextTag: 0x02,
      principal: 'operator',
      facetId: 'f',
    });
    expect(sameHat(a, b)).toBe(true);
    expect(sameHat(a, c)).toBe(false);
  });
});

describe('D-O7 — hat-scoping — assertHatScopedCap (Finding 1: K3 gate)', () => {
  const carpenterHat = buildHat({
    hatId: 'carpenter',
    contextTag: CARPENTER_CONTEXT_TAG,
    principal: 'operator',
    facetId: 'f-todd',
  });

  test('accepts a structural cap presented under matching contextTag', () => {
    const cap: PresentedCap = {
      kind: 'structural',
      domainFlag: capWriteCustomer.domainFlag,
    };
    const result = assertHatScopedCap(
      carpenterHat,
      cap,
      CARPENTER_CONTEXT_TAG,
    );
    expect(result.ok).toBe(true);
  });

  test('rejects a structural cap presented under a different contextTag', () => {
    const cap: PresentedCap = {
      kind: 'structural',
      domainFlag: capWriteCustomer.domainFlag,
    };
    // Caller hints musician's contextTag — but we are presenting on
    // carpenter's hat. Should fail.
    const result = assertHatScopedCap(
      carpenterHat,
      cap,
      MUSICIAN_CONTEXT_TAG,
    );
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.kind).toBe('wrong_cap');
      expect(result.error.message).toMatch(/oddjobz_cap_isolation_cryptographic/);
      expect(result.error.hatScope?.expectedContextTag).toBe(
        CARPENTER_CONTEXT_TAG,
      );
      expect(result.error.hatScope?.presentedContextTag).toBe(
        MUSICIAN_CONTEXT_TAG,
      );
    }
  });

  test('reads contextTag from a cell-presented cap (header offset 62)', () => {
    const cell = mintCapabilityCell(
      capPublicChatServe,
      CARPENTER_CONTEXT_TAG,
      STUB_OWNER,
    );
    const cap: PresentedCap = { kind: 'cell', cell };
    expect(presentedContextTag(cap)).toBe(CARPENTER_CONTEXT_TAG);
  });

  test('cell-presented carpenter cap fails for the musician hat', () => {
    const musicianHat = buildHat({
      hatId: 'musician',
      contextTag: MUSICIAN_CONTEXT_TAG,
      principal: 'operator',
      facetId: 'f-todd',
    });
    const cell = mintCapabilityCell(
      capWriteCustomer,
      CARPENTER_CONTEXT_TAG,
      STUB_OWNER,
    );
    const cap: PresentedCap = { kind: 'cell', cell };
    const result = assertHatScopedCap(musicianHat, cap);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.kind).toBe('wrong_cap');
      expect(result.error.hatScope?.expectedContextTag).toBe(
        MUSICIAN_CONTEXT_TAG,
      );
      expect(result.error.hatScope?.presentedContextTag).toBe(
        CARPENTER_CONTEXT_TAG,
      );
    }
  });

  test('legacy default-zero-contextTag matches DEFAULT_HAT_CONTEXT_TAG', () => {
    const cell = mintCapabilityCell(capWriteCustomer, 0, STUB_OWNER);
    const cap: PresentedCap = { kind: 'cell', cell };
    const defaultHat = buildHat({
      hatId: 'legacy',
      contextTag: DEFAULT_HAT_CONTEXT_TAG,
      principal: 'operator',
      facetId: 'f-legacy',
    });
    expect(assertHatScopedCap(defaultHat, cap).ok).toBe(true);
  });
});

describe('D-O7 — hat-scoping — selectHatForCap', () => {
  const carpenterHat = buildHat({
    hatId: 'carpenter',
    contextTag: CARPENTER_CONTEXT_TAG,
    principal: 'operator',
    facetId: 'f',
  });
  const musicianHat = buildHat({
    hatId: 'musician',
    contextTag: MUSICIAN_CONTEXT_TAG,
    principal: 'operator',
    facetId: 'f',
  });

  test('picks the carpenter hat for a carpenter-tagged cap', () => {
    const cell = mintCapabilityCell(
      capWriteCustomer,
      CARPENTER_CONTEXT_TAG,
      STUB_OWNER,
    );
    const cap: PresentedCap = { kind: 'cell', cell };
    const picked = selectHatForCap([carpenterHat, musicianHat], cap);
    expect(picked).toBe(carpenterHat);
  });

  test('picks the musician hat for a musician-tagged cap', () => {
    const cell = mintCapabilityCell(
      capWriteCustomer,
      MUSICIAN_CONTEXT_TAG,
      STUB_OWNER,
    );
    const cap: PresentedCap = { kind: 'cell', cell };
    const picked = selectHatForCap([carpenterHat, musicianHat], cap);
    expect(picked).toBe(musicianHat);
  });

  test('returns null when no hat matches the cap contextTag', () => {
    const cell = mintCapabilityCell(capWriteCustomer, 0xee, STUB_OWNER);
    const cap: PresentedCap = { kind: 'cell', cell };
    expect(selectHatForCap([carpenterHat, musicianHat], cap)).toBeNull();
  });
});

```
