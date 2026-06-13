---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/__tests__/hat-context.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.355275+00:00
---

# runtime/intent/src/__tests__/hat-context.test.ts

```ts
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import {
  buildHatContext,
  defaultTrustCeiling,
  isDevIdentityStub,
  MissingCertError,
  NoActiveHatError,
  type HatLike,
  type IdentityLike,
  type IdentityServiceLike,
} from '../hat-context';

const mkService = (identity: IdentityLike | null): IdentityServiceLike => ({
  getIdentity: () => identity,
  getActiveHat: () =>
    identity ? identity.hats.find(f => f.id === identity.activeHatId) ?? null : null,
});

const mkHat = (over: Partial<HatLike> = {}): HatLike => ({
  id: 'hat-1',
  certId: 'cert-1',
  capabilities: [1, 2, 3],
  ...over,
});

describe('buildHatContext', () => {
  test('throws NoActiveHatError when identity is null', () => {
    expect(() =>
      buildHatContext({
        identity: mkService(null),
        extension: { extensionId: 'ext-demo', domainFlag: 7 },
        resolveMaxTrustClass: defaultTrustCeiling,
        requireCert: false,
      }),
    ).toThrow(NoActiveHatError);
  });

  test('throws when active hat cannot be resolved', () => {
    const identity: IdentityLike = {
      id: 'id-1',
      activeHatId: 'hat-missing',
      hats: [mkHat({ id: 'hat-other' })],
    };
    expect(() =>
      buildHatContext({
        identity: mkService(identity),
        extension: { extensionId: 'ext-demo', domainFlag: 7 },
        resolveMaxTrustClass: defaultTrustCeiling,
        requireCert: false,
      }),
    ).toThrow(NoActiveHatError);
  });

  test('builds a HatContext from the active hat', () => {
    const hat = mkHat();
    const identity: IdentityLike = {
      id: 'id-1',
      activeHatId: hat.id,
      hats: [hat],
    };

    const ctx = buildHatContext({
      identity: mkService(identity),
      extension: { extensionId: 'ext-demo', domainFlag: 7 },
      resolveMaxTrustClass: defaultTrustCeiling,
    });

    expect(ctx).toEqual({
      hatId: 'hat-1',
      certId: 'cert-1',
      capabilities: [1, 2, 3],
      extensionId: 'ext-demo',
      domainFlag: 7,
      maxTrustClass: 'interpretive',
    });
  });

  test('capabilities array is defensively copied (no aliasing)', () => {
    const hat = mkHat({ capabilities: [9] });
    const identity: IdentityLike = {
      id: 'id-1',
      activeHatId: hat.id,
      hats: [hat],
    };

    const ctx = buildHatContext({
      identity: mkService(identity),
      extension: { extensionId: 'ext-demo', domainFlag: 1 },
      resolveMaxTrustClass: defaultTrustCeiling,
    });
    ctx.capabilities.push(42);
    expect(hat.capabilities).toEqual([9]);
  });
});

describe('defaultTrustCeiling', () => {
  test('unpublished hat caps at cosmetic', () => {
    const hat = mkHat({ certId: null });
    const identity: IdentityLike = {
      id: 'id-1',
      activeHatId: hat.id,
      hats: [hat],
    };
    expect(defaultTrustCeiling(hat, identity)).toBe('cosmetic');
  });

  test('published hat caps at interpretive', () => {
    const hat = mkHat({ certId: 'cert-real' });
    const identity: IdentityLike = {
      id: 'id-1',
      activeHatId: hat.id,
      hats: [hat],
    };
    expect(defaultTrustCeiling(hat, identity)).toBe('interpretive');
  });
});

// ── D-A3: production cert-required gate ────────────────────────
//
// The production path requires a real cert on the active hat. The
// dev escape hatch is `SEMANTOS_DEV_IDENTITY=stub`. These tests pin
// both halves of that contract.

describe('buildHatContext — D-A3 cert-required gate', () => {
  const ORIG_FLAG = process.env.SEMANTOS_DEV_IDENTITY;
  beforeEach(() => {
    delete process.env.SEMANTOS_DEV_IDENTITY;
  });
  afterEach(() => {
    if (ORIG_FLAG === undefined) {
      delete process.env.SEMANTOS_DEV_IDENTITY;
    } else {
      process.env.SEMANTOS_DEV_IDENTITY = ORIG_FLAG;
    }
  });

  test('production: cert-less hat throws MissingCertError', () => {
    const hat = mkHat({ certId: null });
    const identity: IdentityLike = {
      id: 'id-1',
      activeHatId: hat.id,
      hats: [hat],
    };
    expect(() =>
      buildHatContext({
        identity: mkService(identity),
        extension: { extensionId: 'ext-demo', domainFlag: 7 },
        resolveMaxTrustClass: defaultTrustCeiling,
      }),
    ).toThrow(MissingCertError);
  });

  test('production: missing certId (undefined) throws MissingCertError', () => {
    const hat: HatLike = { id: 'hat-1', capabilities: [1] };
    const identity: IdentityLike = {
      id: 'id-1',
      activeHatId: hat.id,
      hats: [hat],
    };
    expect(() =>
      buildHatContext({
        identity: mkService(identity),
        extension: { extensionId: 'ext-demo', domainFlag: 7 },
        resolveMaxTrustClass: defaultTrustCeiling,
      }),
    ).toThrow(MissingCertError);
  });

  test('MissingCertError message names the env flag', () => {
    const hat = mkHat({ certId: null });
    const identity: IdentityLike = {
      id: 'id-1',
      activeHatId: hat.id,
      hats: [hat],
    };
    let caught: unknown;
    try {
      buildHatContext({
        identity: mkService(identity),
        extension: { extensionId: 'ext-demo', domainFlag: 7 },
        resolveMaxTrustClass: defaultTrustCeiling,
      });
    } catch (err) {
      caught = err;
    }
    expect(caught).toBeInstanceOf(MissingCertError);
    expect((caught as Error).message).toContain('SEMANTOS_DEV_IDENTITY=stub');
  });

  test('production: hat with cert succeeds', () => {
    const hat = mkHat({ certId: 'cert-real' });
    const identity: IdentityLike = {
      id: 'id-1',
      activeHatId: hat.id,
      hats: [hat],
    };
    const ctx = buildHatContext({
      identity: mkService(identity),
      extension: { extensionId: 'ext-demo', domainFlag: 7 },
      resolveMaxTrustClass: defaultTrustCeiling,
    });
    expect(ctx.certId).toBe('cert-real');
  });

  test('dev stub flag relaxes the cert requirement', () => {
    process.env.SEMANTOS_DEV_IDENTITY = 'stub';
    const hat = mkHat({ certId: null });
    const identity: IdentityLike = {
      id: 'id-1',
      activeHatId: hat.id,
      hats: [hat],
    };
    const ctx = buildHatContext({
      identity: mkService(identity),
      extension: { extensionId: 'ext-demo', domainFlag: 7 },
      resolveMaxTrustClass: defaultTrustCeiling,
    });
    expect(ctx.certId).toBeNull();
  });

  test('explicit requireCert=false overrides env (test fixture pattern)', () => {
    // SEMANTOS_DEV_IDENTITY unset, but the call opts out of the gate.
    const hat = mkHat({ certId: null });
    const identity: IdentityLike = {
      id: 'id-1',
      activeHatId: hat.id,
      hats: [hat],
    };
    expect(() =>
      buildHatContext({
        identity: mkService(identity),
        extension: { extensionId: 'ext-demo', domainFlag: 7 },
        resolveMaxTrustClass: defaultTrustCeiling,
        requireCert: false,
      }),
    ).not.toThrow();
  });

  test('explicit requireCert=true overrides dev stub flag', () => {
    process.env.SEMANTOS_DEV_IDENTITY = 'stub';
    const hat = mkHat({ certId: null });
    const identity: IdentityLike = {
      id: 'id-1',
      activeHatId: hat.id,
      hats: [hat],
    };
    expect(() =>
      buildHatContext({
        identity: mkService(identity),
        extension: { extensionId: 'ext-demo', domainFlag: 7 },
        resolveMaxTrustClass: defaultTrustCeiling,
        requireCert: true,
      }),
    ).toThrow(MissingCertError);
  });

  test('any value other than "stub" leaves the gate active', () => {
    process.env.SEMANTOS_DEV_IDENTITY = 'real';
    const hat = mkHat({ certId: null });
    const identity: IdentityLike = {
      id: 'id-1',
      activeHatId: hat.id,
      hats: [hat],
    };
    expect(() =>
      buildHatContext({
        identity: mkService(identity),
        extension: { extensionId: 'ext-demo', domainFlag: 7 },
        resolveMaxTrustClass: defaultTrustCeiling,
      }),
    ).toThrow(MissingCertError);
  });
});

describe('isDevIdentityStub', () => {
  const ORIG_FLAG = process.env.SEMANTOS_DEV_IDENTITY;
  afterEach(() => {
    if (ORIG_FLAG === undefined) {
      delete process.env.SEMANTOS_DEV_IDENTITY;
    } else {
      process.env.SEMANTOS_DEV_IDENTITY = ORIG_FLAG;
    }
  });

  test('returns true only for the literal "stub"', () => {
    delete process.env.SEMANTOS_DEV_IDENTITY;
    expect(isDevIdentityStub()).toBe(false);
    process.env.SEMANTOS_DEV_IDENTITY = '';
    expect(isDevIdentityStub()).toBe(false);
    process.env.SEMANTOS_DEV_IDENTITY = 'stub';
    expect(isDevIdentityStub()).toBe(true);
    process.env.SEMANTOS_DEV_IDENTITY = 'STUB';
    expect(isDevIdentityStub()).toBe(false);
  });
});

```
