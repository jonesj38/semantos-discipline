---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/transport.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.670415+00:00
---

# cartridges/wallet-headers/brain/test/transport.spec.ts

```ts
// WT-Transport tests (v0.4).
//
// Exercises the three Day-1 transports:
//   • WebShareTransport  — `navigator.share({ files })` happy path + cancel
//   • DownloadTransport  — Blob/URL.createObjectURL + invisible <a download>
//   • ClipboardTransport — `navigator.clipboard.writeText(base64)`
//
// Plus the registry filter (`defaultTransports()` returns only available)
// and the `serializeEnvelope` shape (filename, json, base64, bytes).

import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import {
  ClipboardTransport,
  DownloadTransport,
  WebShareTransport,
  defaultTransports,
  serializeEnvelope,
  type SerializedEnvelope,
} from '../src/transport';
import type { PlexusRecoveryEnvelope } from '../src/plexus/envelope';

// ──────────────────────────────────────────────────────────────────────
// Test fixtures
// ──────────────────────────────────────────────────────────────────────

function makeEnvelope(): PlexusRecoveryEnvelope {
  return {
    envelopeVersion: 1,
    identityKey: '02' + 'aa'.repeat(32),
    certId: 'bb'.repeat(32),
    contactEmail: 'user@example.com',
    challengeBundle: {
      questions: ['q1', 'q2', 'q3'],
      salt: 'cc'.repeat(32),
      answerHashes: ['dd'.repeat(32), 'ee'.repeat(32), 'ff'.repeat(32)],
      kdfIterations: 100_000,
    },
    encryptedRecoverySeed: {
      ciphertext: '00'.repeat(64),
      nonce: '11'.repeat(12),
      tag: '22'.repeat(16),
      aad: '33'.repeat(34),
    },
    derivationContexts: [],
    edgeRecipes: [],
    derivationStateSnapshot: { records: [], snapshotTimestamp: '2026-04-27T00:00:00.000Z' },
    algorithmVersion: 1,
  };
}

function fixedSerialized(): SerializedEnvelope {
  return serializeEnvelope(makeEnvelope(), new Date(Date.UTC(2026, 3, 27)));
}

// ──────────────────────────────────────────────────────────────────────
// Stubs
// ──────────────────────────────────────────────────────────────────────

interface NavStubState {
  shareCalls: Array<{ files?: File[]; title?: string; text?: string }>;
  shareImpl?: (data: { files?: File[]; title?: string; text?: string }) => Promise<void>;
  canShare?: (data: { files?: File[] }) => boolean;
  clipboardWrites: string[];
  clipboardImpl?: (text: string) => Promise<void>;
}

function installNavigatorStub(state: NavStubState, opts: { withShare?: boolean; withCanShare?: boolean; withClipboard?: boolean }) {
  const stubNav: Record<string, unknown> = {};
  if (opts.withShare) {
    stubNav.share = async (data: { files?: File[]; title?: string; text?: string }) => {
      state.shareCalls.push(data);
      if (state.shareImpl) await state.shareImpl(data);
    };
  }
  if (opts.withCanShare) {
    stubNav.canShare = (data: { files?: File[] }) =>
      state.canShare ? state.canShare(data) : true;
  }
  if (opts.withClipboard) {
    stubNav.clipboard = {
      writeText: async (text: string) => {
        state.clipboardWrites.push(text);
        if (state.clipboardImpl) await state.clipboardImpl(text);
      },
    };
  }
  (globalThis as Record<string, unknown>).navigator = stubNav;
}

function clearNavigator() {
  delete (globalThis as Record<string, unknown>).navigator;
}

// Save/restore the original navigator (bun provides a real one).
let originalNavigatorDescriptor: PropertyDescriptor | undefined;
beforeEach(() => {
  originalNavigatorDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'navigator');
});
afterEach(() => {
  if (originalNavigatorDescriptor) {
    Object.defineProperty(globalThis, 'navigator', originalNavigatorDescriptor);
  } else {
    delete (globalThis as Record<string, unknown>).navigator;
  }
});

// ──────────────────────────────────────────────────────────────────────
// serializeEnvelope
// ──────────────────────────────────────────────────────────────────────

describe('serializeEnvelope', () => {
  test('produces json, base64, bytes, and dated filename', () => {
    const s = fixedSerialized();
    expect(s.json.length).toBeGreaterThan(0);
    expect(JSON.parse(s.json).envelopeVersion).toBe(1);
    expect(s.bytes).toBeInstanceOf(Uint8Array);
    expect(new TextDecoder().decode(s.bytes)).toBe(s.json);
    // base64 decodes back to the same bytes
    const decoded = atob(s.base64);
    expect(decoded.length).toBe(s.bytes.length);
    expect(s.suggestedFilename).toBe('semantos-wallet-recovery-2026-04-27.envelope');
  });
});

// ──────────────────────────────────────────────────────────────────────
// DownloadTransport
// ──────────────────────────────────────────────────────────────────────

describe('DownloadTransport', () => {
  test('builds a Blob from the serialized bytes and clicks an <a download>', async () => {
    // bun's test runner doesn't ship a DOM by default, but it does expose
    // Blob + URL.createObjectURL + URL.revokeObjectURL as globals. We
    // install a tiny `document` stub that captures the synthesized anchor.
    const blobs: Blob[] = [];
    const anchors: Array<{ href: string; download: string; clicked: boolean }> = [];

    const origDoc = (globalThis as Record<string, unknown>).document;
    const origURL = (globalThis as { URL?: typeof URL }).URL;

    // Capture every Blob the transport constructs by replacing the global
    // constructor with a thin wrapper. Restore after the test.
    const RealBlob = globalThis.Blob;
    (globalThis as { Blob: typeof Blob }).Blob = class extends RealBlob {
      constructor(parts?: BlobPart[], opts?: BlobPropertyBag) {
        super(parts, opts);
        blobs.push(this as unknown as Blob);
      }
    } as unknown as typeof Blob;

    (globalThis as { URL: typeof URL }).URL = {
      ...origURL,
      createObjectURL: (_b: Blob) => 'blob:fake-id',
      revokeObjectURL: (_u: string) => undefined,
    } as unknown as typeof URL;

    (globalThis as { document: unknown }).document = {
      createElement: (_tag: string) => {
        const a = { href: '', download: '', style: {} as Record<string, string>, clicked: false, click() { this.clicked = true; } } as {
          href: string;
          download: string;
          style: Record<string, string>;
          clicked: boolean;
          click(): void;
        };
        anchors.push(a);
        return a;
      },
      body: { appendChild: (_a: unknown) => undefined, removeChild: (_a: unknown) => undefined },
    };

    try {
      const t = new DownloadTransport();
      expect(t.isAvailable()).toBe(true);
      const r = await t.send(fixedSerialized());
      expect(r.ok).toBe(true);
      if (r.ok) expect(r.receipt).toBe('semantos-wallet-recovery-2026-04-27.envelope');

      // Exactly one anchor synthesized, clicked, with the expected name.
      expect(anchors.length).toBe(1);
      expect(anchors[0]!.clicked).toBe(true);
      expect(anchors[0]!.download).toBe('semantos-wallet-recovery-2026-04-27.envelope');
      expect(anchors[0]!.href).toBe('blob:fake-id');

      // The Blob carries the serialized bytes (size matches).
      expect(blobs.length).toBe(1);
      expect(blobs[0]!.size).toBe(fixedSerialized().bytes.length);
    } finally {
      (globalThis as { Blob: typeof Blob }).Blob = RealBlob;
      (globalThis as { URL: typeof URL }).URL = origURL as typeof URL;
      if (origDoc === undefined) {
        delete (globalThis as Record<string, unknown>).document;
      } else {
        (globalThis as { document: unknown }).document = origDoc;
      }
    }
  });

  test('isAvailable() returns false when document is absent', () => {
    const origDoc = (globalThis as Record<string, unknown>).document;
    delete (globalThis as Record<string, unknown>).document;
    try {
      expect(new DownloadTransport().isAvailable()).toBe(false);
    } finally {
      if (origDoc !== undefined) (globalThis as Record<string, unknown>).document = origDoc;
    }
  });
});

// ──────────────────────────────────────────────────────────────────────
// ClipboardTransport
// ──────────────────────────────────────────────────────────────────────

describe('ClipboardTransport', () => {
  test('writes base64 to a stub clipboard', async () => {
    const state: NavStubState = { shareCalls: [], clipboardWrites: [] };
    installNavigatorStub(state, { withClipboard: true });

    const t = new ClipboardTransport();
    expect(t.isAvailable()).toBe(true);
    const env = fixedSerialized();
    const r = await t.send(env);
    expect(r.ok).toBe(true);
    expect(state.clipboardWrites).toEqual([env.base64]);
  });

  test('isAvailable() false when clipboard.writeText is absent', () => {
    const state: NavStubState = { shareCalls: [], clipboardWrites: [] };
    installNavigatorStub(state, {});
    expect(new ClipboardTransport().isAvailable()).toBe(false);
  });

  test('failed write surfaces failed result with detail', async () => {
    const state: NavStubState = {
      shareCalls: [],
      clipboardWrites: [],
      clipboardImpl: async () => {
        throw new Error('clipboard not focused');
      },
    };
    installNavigatorStub(state, { withClipboard: true });
    const r = await new ClipboardTransport().send(fixedSerialized());
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.reason).toBe('failed');
      expect(r.detail).toContain('not focused');
    }
  });
});

// ──────────────────────────────────────────────────────────────────────
// WebShareTransport
// ──────────────────────────────────────────────────────────────────────

describe('WebShareTransport', () => {
  test('calls navigator.share with the file payload', async () => {
    const state: NavStubState = { shareCalls: [], clipboardWrites: [] };
    installNavigatorStub(state, { withShare: true, withCanShare: true });

    const t = new WebShareTransport();
    expect(t.isAvailable()).toBe(true);
    const env = fixedSerialized();
    const r = await t.send(env);
    expect(r.ok).toBe(true);

    expect(state.shareCalls.length).toBe(1);
    const call = state.shareCalls[0]!;
    expect(call.files?.length).toBe(1);
    const f = call.files![0]!;
    expect(f.name).toBe(env.suggestedFilename);
    expect(f.size).toBe(env.bytes.length);
  });

  test('isAvailable() false when navigator.share is absent', () => {
    const state: NavStubState = { shareCalls: [], clipboardWrites: [] };
    installNavigatorStub(state, {});
    expect(new WebShareTransport().isAvailable()).toBe(false);
  });

  test('isAvailable() false when canShare({files}) returns false (desktop)', () => {
    const state: NavStubState = {
      shareCalls: [],
      clipboardWrites: [],
      canShare: () => false,
    };
    installNavigatorStub(state, { withShare: true, withCanShare: true });
    expect(new WebShareTransport().isAvailable()).toBe(false);
  });

  test('AbortError → cancelled (user dismissed share sheet)', async () => {
    const state: NavStubState = {
      shareCalls: [],
      clipboardWrites: [],
      shareImpl: async () => {
        const e = new Error('Share canceled');
        e.name = 'AbortError';
        throw e;
      },
    };
    installNavigatorStub(state, { withShare: true, withCanShare: true });
    const r = await new WebShareTransport().send(fixedSerialized());
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.reason).toBe('cancelled');
  });
});

// ──────────────────────────────────────────────────────────────────────
// defaultTransports() registry
// ──────────────────────────────────────────────────────────────────────

describe('defaultTransports()', () => {
  test('returns only transports that report isAvailable()', () => {
    // Install a navigator with no share + no clipboard + no document so
    // only Download could be available. We additionally need to clobber
    // document so DownloadTransport reports unavailable.
    const origDoc = (globalThis as Record<string, unknown>).document;
    delete (globalThis as Record<string, unknown>).document;
    clearNavigator();
    try {
      const ts = defaultTransports();
      // None should be available with neither navigator nor document.
      expect(ts.length).toBe(0);
    } finally {
      if (origDoc !== undefined) (globalThis as Record<string, unknown>).document = origDoc;
    }
  });

  test('includes Clipboard when navigator.clipboard.writeText is available', () => {
    const state: NavStubState = { shareCalls: [], clipboardWrites: [] };
    installNavigatorStub(state, { withClipboard: true });
    const ts = defaultTransports();
    const ids = ts.map((t) => t.id);
    expect(ids).toContain('clipboard');
    // No share, no document → only clipboard expected here.
    expect(ids).not.toContain('web-share');
  });
});

```
