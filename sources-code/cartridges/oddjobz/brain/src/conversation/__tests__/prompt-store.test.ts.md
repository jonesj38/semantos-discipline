---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/prompt-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.537131+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/prompt-store.test.ts

```ts
/**
 * Content-addressed versioned prompt registry conformance —
 * D-OJ-conv-prompt-versioning (§13.3 resolution).
 *
 * Guards the four properties the reply-audit-log consumes:
 *   • determinism — same prompt text → same content hash, reproducibly
 *     (the snapshot/replay DX requirement);
 *   • content-store integration — the registry's hex matches the
 *     SHARED `hashBytes` primitive byte-for-byte (no rolled-own hash);
 *   • bump — appending a new version yields a new hash AND the old
 *     version stays resolvable (the audit chain);
 *   • resolve — latest by default, specific version when asked;
 *   • typed errors — unknown id / version throw, not crash.
 */

import { describe, expect, test } from 'bun:test';
import {
  PROMPT_IDS,
  resolvePrompt,
  promptVersion,
  promptVersionRef,
  promptContentHash,
  resolveFromVersions,
  listPromptIds,
  listPromptVersions,
  verifyContentHashHex,
  UnknownPromptError,
  UnknownPromptVersionError,
} from '../prompt-store.js';

const HEX64 = /^[0-9a-f]{64}$/;

describe('prompt-store — determinism + content-store integration', () => {
  test('same prompt text → same content hash, reproducibly', () => {
    const a = resolvePrompt(PROMPT_IDS.extraction);
    const b = resolvePrompt(PROMPT_IDS.extraction);
    expect(a.contentHash).toBe(b.contentHash);
    expect(a.contentHash).toMatch(HEX64);
    // Different prompt id with different text → different hash.
    const sys = resolvePrompt(PROMPT_IDS.system);
    expect(sys.contentHash).not.toBe(a.contentHash);
  });

  test('registry hex equals the SHARED content-store primitive', async () => {
    // The async path uses @semantos/protocol-types `hashBytes` (the
    // same SHA-256 that addresses cells). It must agree byte-for-byte
    // with the synchronous hex the registry serves — so the audit
    // log's recorded hex is interchangeable whichever path produced it.
    for (const id of listPromptIds()) {
      const resolved = resolvePrompt(id);
      const viaContentStore = await verifyContentHashHex(resolved.text);
      expect(viaContentStore).toBe(resolved.contentHash);
    }
  });

  test('promptContentHash returns a branded 32-byte hash', async () => {
    const h = await promptContentHash('hello prompt');
    expect(h.length).toBe(32);
    // Determinism at the primitive level.
    const h2 = await promptContentHash('hello prompt');
    expect(Array.from(h2)).toEqual(Array.from(h));
  });
});

describe('prompt-store — resolve', () => {
  test('resolvePrompt returns latest by default', () => {
    const r = resolvePrompt(PROMPT_IDS.system);
    const versions = listPromptVersions(PROMPT_IDS.system);
    expect(r.version).toBe(versions[versions.length - 1]!.version);
    expect(r.text.length).toBeGreaterThan(0);
  });

  test('promptVersion(id) is the latest descriptor', () => {
    const r = promptVersion(PROMPT_IDS.reply);
    expect(r.promptId).toBe(PROMPT_IDS.reply);
    expect(r.version).toMatch(/^\d+\.\d+\.\d+$/);
    expect(r.contentHash).toMatch(HEX64);
  });

  test('promptVersionRef is the pin triple, no text body', () => {
    const ref = promptVersionRef(PROMPT_IDS.extraction);
    expect(ref).toEqual({
      promptId: PROMPT_IDS.extraction,
      version: resolvePrompt(PROMPT_IDS.extraction).version,
      contentHash: resolvePrompt(PROMPT_IDS.extraction).contentHash,
    });
    expect(Object.keys(ref)).not.toContain('text');
  });

  test('resolvePrompt(id, version) pins a specific version', () => {
    const latest = resolvePrompt(PROMPT_IDS.system);
    const pinned = resolvePrompt(PROMPT_IDS.system, latest.version);
    expect(pinned.contentHash).toBe(latest.contentHash);
  });
});

describe('prompt-store — bump retains the old version', () => {
  // Exercise the REAL selection + hashing path (`resolveFromVersions`)
  // over a synthetic two-version list, proving the audit-chain
  // property: bumping appends a new version + new hash, and the old
  // version is still resolvable by its tag.
  const v1Text = 'PROMPT BODY v1';
  const v2Text = 'PROMPT BODY v2 — tightened the tone rule';
  const versions = [
    { version: '1.0.0', text: v1Text },
    { version: '1.1.0', text: v2Text },
  ];

  test('latest resolves to the newest entry, new hash', () => {
    const latest = resolveFromVersions('test.prompt', versions);
    const v1 = resolveFromVersions('test.prompt', versions, '1.0.0');
    expect(latest.version).toBe('1.1.0');
    expect(latest.text).toBe(v2Text);
    expect(latest.contentHash).not.toBe(v1.contentHash);
  });

  test('old version is still resolvable after a bump', () => {
    const v1 = resolveFromVersions('test.prompt', versions, '1.0.0');
    expect(v1.version).toBe('1.0.0');
    expect(v1.text).toBe(v1Text);
    expect(v1.contentHash).toMatch(HEX64);
  });

  test('bumped hash is deterministic + matches content-store', async () => {
    const v2 = resolveFromVersions('test.prompt', versions, '1.1.0');
    const viaContentStore = await verifyContentHashHex(v2Text);
    expect(viaContentStore).toBe(v2.contentHash);
  });
});

describe('prompt-store — typed errors, not crashes', () => {
  test('unknown promptId → UnknownPromptError', () => {
    expect(() => resolvePrompt('oddjobz.prompt.does-not-exist')).toThrow(
      UnknownPromptError,
    );
    let caught: unknown;
    try {
      resolvePrompt('nope');
    } catch (e) {
      caught = e;
    }
    expect((caught as UnknownPromptError).name).toBe('UnknownPromptError');
  });

  test('unknown version → UnknownPromptVersionError', () => {
    expect(() => resolvePrompt(PROMPT_IDS.system, '99.99.99')).toThrow(
      UnknownPromptVersionError,
    );
    expect(() =>
      resolveFromVersions('test.prompt', [{ version: '1.0.0', text: 'x' }], '2.0.0'),
    ).toThrow(UnknownPromptVersionError);
  });

  test('empty version list → UnknownPromptError', () => {
    expect(() => resolveFromVersions('test.prompt', [])).toThrow(
      UnknownPromptError,
    );
  });

  test('all registered ids resolve cleanly', () => {
    expect(listPromptIds().sort()).toEqual(
      [
        PROMPT_IDS.extraction,
        PROMPT_IDS.pdfExtraction,
        PROMPT_IDS.system,
        PROMPT_IDS.reply,
      ].sort(),
    );
    for (const id of listPromptIds()) {
      expect(() => resolvePrompt(id)).not.toThrow();
    }
  });
});

```
