---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/web/__tests__/deep-link.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.428058+00:00
---

# cartridges/chess/web/__tests__/deep-link.test.ts

```ts
import { describe, expect, it, beforeEach, vi } from 'vitest';
import { readDeepLink, clearDeepLinkHash } from '../src/core/deep-link.js';

function setLocation(href: string): void {
  const u = new URL(href);
  vi.stubGlobal('location', {
    href: u.href,
    pathname: u.pathname,
    search: u.search,
    hash: u.hash,
  });
}

describe('readDeepLink', () => {
  beforeEach(() => {
    vi.unstubAllGlobals();
    vi.stubGlobal('history', {
      replaceState: vi.fn(),
    });
  });

  it('extracts ?invite as gameId', () => {
    setLocation('https://doublemate.app/?invite=chess-mpeo0ho0');
    expect(readDeepLink()).toEqual({ gameId: 'chess-mpeo0ho0' });
  });

  it('extracts #bearer from the hash and lowercases it', () => {
    setLocation('https://doublemate.app/#bearer=ABCDEF0123456789abcdef0123456789ABCDEF0123456789abcdef0123456789');
    expect(readDeepLink().bearer).toBe(
      'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
    );
  });

  it('rejects malformed bearer (not 64 hex)', () => {
    setLocation('https://doublemate.app/#bearer=not-hex');
    expect(readDeepLink().bearer).toBeUndefined();
    setLocation('https://doublemate.app/#bearer=abcd');
    expect(readDeepLink().bearer).toBeUndefined();
  });

  it('rejects malformed invite gameId', () => {
    setLocation('https://doublemate.app/?invite=bad%20id');
    expect(readDeepLink().gameId).toBeUndefined();
  });

  it('parses combined invite + bearer + brain', () => {
    const fakeBearer = '0123456789abcdef'.repeat(4); // exactly 64 hex chars
    setLocation(
      'https://doublemate.app/?invite=chess-abc123' +
        `#bearer=${fakeBearer}` +
        '&brain=wss%3A%2F%2Fbrain.example%2Fapi%2Fv1%2Fwallet',
    );
    const dl = readDeepLink();
    expect(dl.gameId).toBe('chess-abc123');
    expect(dl.bearer).toBe(fakeBearer);
    expect(dl.brainUrl).toBe('wss://brain.example/api/v1/wallet');
  });

  it('ignores brain override unless protocol is ws/wss', () => {
    setLocation('https://doublemate.app/#brain=https%3A%2F%2Fbad.example');
    expect(readDeepLink().brainUrl).toBeUndefined();
    setLocation('https://doublemate.app/#brain=not-a-url');
    expect(readDeepLink().brainUrl).toBeUndefined();
  });
});

describe('clearDeepLinkHash', () => {
  beforeEach(() => {
    vi.unstubAllGlobals();
  });

  it('calls replaceState with a hash-stripped URL', () => {
    setLocation('https://doublemate.app/?invite=g1#bearer=abc');
    const replaceState = vi.fn();
    vi.stubGlobal('history', { replaceState });
    clearDeepLinkHash();
    expect(replaceState).toHaveBeenCalledWith(null, '', '/?invite=g1');
  });

  it('is a no-op when there is no hash', () => {
    setLocation('https://doublemate.app/?invite=g1');
    const replaceState = vi.fn();
    vi.stubGlobal('history', { replaceState });
    clearDeepLinkHash();
    expect(replaceState).not.toHaveBeenCalled();
  });
});

```
