---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase36a-shell-commands.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.577506+00:00
---

# tests/gates/phase36a-shell-commands.test.ts

```ts
import { describe, test, expect } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';
import { parseCommand, KNOWN_VERBS } from '../../runtime/shell/src/parser';
import { routeGrammar } from '../../runtime/shell/src/commands/grammar';
import type { ShellContext } from '../../runtime/shell/src/types';

const ROOT = join(import.meta.dir, '../..');

// Minimal ShellContext stub for grammar commands (grammar doesn't use ctx)
const STUB_CTX = {} as ShellContext;

describe('Shell Grammar Commands', () => {
  // ── Parser Tests ──

  test('T1: parser recognizes grammar verb', () => {
    expect((KNOWN_VERBS as readonly string[]).includes('grammar')).toBe(true);
    const cmd = parseCommand(['grammar', 'validate', 'test.json']);
    expect(cmd.verb).toBe('grammar');
    expect(cmd.flags.subcommand).toBe('validate');
    expect(cmd.flags.path).toBe('test.json');
  });

  test('T2: parser extracts diff paths', () => {
    const cmd = parseCommand(['grammar', 'diff', 'old.json', 'new.json']);
    expect(cmd.verb).toBe('grammar');
    expect(cmd.flags.subcommand).toBe('diff');
    expect(cmd.flags.path).toBe('old.json');
    expect(cmd.flags.newPath).toBe('new.json');
  });

  test('T3: parser handles list subcommand with no path', () => {
    const cmd = parseCommand(['grammar', 'list']);
    expect(cmd.verb).toBe('grammar');
    expect(cmd.flags.subcommand).toBe('list');
    expect(cmd.flags.path).toBeUndefined();
  });

  // ── Command Integration Tests ──

  test('T4: validate returns valid for PropertyMe grammar', async () => {
    const grammarPath = join(ROOT, 'configs/extensions/propertyme/grammar.json');
    const cmd = parseCommand(['grammar', 'validate', grammarPath]);
    const result = await routeGrammar(cmd, STUB_CTX) as any;
    expect(result.valid).toBe(true);
    expect(result.objectTypes).toBe(6);
    expect(result.sourceEntities).toBe(6);
  });

  test('T5: validate returns errors for invalid grammar', async () => {
    // Create a temp invalid grammar reference by using a non-existent file
    const cmd = parseCommand(['grammar', 'validate', '/nonexistent/file.json']);
    const result = await routeGrammar(cmd, STUB_CTX) as any;
    expect(result.error).toBeDefined();
  });

  test('T6: inspect returns structured summary', async () => {
    const grammarPath = join(ROOT, 'configs/extensions/propertyme/grammar.json');
    const cmd = parseCommand(['grammar', 'inspect', grammarPath]);
    const result = await routeGrammar(cmd, STUB_CTX) as any;

    expect(result.grammarId).toBe('com.semantos.propertyme');
    expect(result.source).toBeDefined();
    expect(result.source.entityCount).toBe(6);
    expect(result.objectTypes.length).toBe(6);
    expect(result.entityMappings.length).toBe(6);
  });

  test('T7: diff shows no changes when comparing same file', async () => {
    const grammarPath = join(ROOT, 'configs/extensions/propertyme/grammar.json');
    const cmd = parseCommand(['grammar', 'diff', grammarPath, grammarPath]);
    const result = await routeGrammar(cmd, STUB_CTX) as any;

    expect(result.hasChanges).toBe(false);
    expect(result.sourceEntities.added.length).toBe(0);
    expect(result.sourceEntities.removed.length).toBe(0);
  });

  test('T8: list finds grammars in configs/extensions/', async () => {
    // This test depends on cwd being the repo root
    const originalCwd = process.cwd();
    try {
      process.chdir(ROOT);
      const cmd = parseCommand(['grammar', 'list']);
      const result = await routeGrammar(cmd, STUB_CTX) as any;

      expect(result.grammars).toBeDefined();
      expect(result.count).toBeGreaterThan(0);
      const propertyme = result.grammars.find((g: any) => g.directory === 'propertyme');
      expect(propertyme).toBeDefined();
      expect(propertyme.grammarId).toBe('com.semantos.propertyme');
      expect(propertyme.valid).toBe(true);
    } finally {
      process.chdir(originalCwd);
    }
  });

  test('T9: test runs full validate+bridge pipeline', async () => {
    const grammarPath = join(ROOT, 'configs/extensions/propertyme/grammar.json');
    const cmd = parseCommand(['grammar', 'test', grammarPath]);
    const result = await routeGrammar(cmd, STUB_CTX) as any;

    expect(result.success).toBe(true);
    expect(result.config).toBeDefined();
    expect(result.config.objectTypes).toBe(6);
    expect(result.config.hasTaxonomy).toBe(true);
    expect(result.message).toContain('successfully');
  });

  test('T10: no subcommand returns usage', async () => {
    const cmd = parseCommand(['grammar']);
    const result = await routeGrammar(cmd, STUB_CTX) as any;
    expect(result.error).toBeDefined();
    expect(result.available).toBeDefined();
  });

  test('T11: unknown subcommand returns error', async () => {
    const cmd = { verb: 'grammar' as const, flags: { subcommand: 'bogus' }, rawArgs: [] };
    const result = await routeGrammar(cmd, STUB_CTX) as any;
    expect(result.error).toContain('Unknown grammar subcommand');
  });
});

```
