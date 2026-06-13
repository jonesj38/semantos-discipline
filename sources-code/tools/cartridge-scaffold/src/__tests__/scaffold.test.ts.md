---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/cartridge-scaffold/src/__tests__/scaffold.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.561895+00:00
---

# tools/cartridge-scaffold/src/__tests__/scaffold.test.ts

```ts
/**
 * RM-097 — cartridge-scaffold acceptance.
 *
 * The dogfood loop's first half: scaffolded cartridge has the expected
 * files, the typed cell entry compiles, and the regression test would
 * run against a fresh reducer pass if the user supplied a captured
 * trace.
 *
 * Filesystem-write path is covered by S5 — uses Bun.file to verify the
 * scaffold actually lands on disk.
 */
import { afterEach, describe, expect, test } from 'bun:test';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { planScaffold, writeScaffold } from '../scaffold';

let tmpRoots: string[] = [];
afterEach(() => {
  for (const r of tmpRoots) rmSync(r, { recursive: true, force: true });
  tmpRoots = [];
});

function mkTmp(): string {
  const dir = mkdtempSync(join(tmpdir(), 'cartridge-scaffold-'));
  tmpRoots.push(dir);
  return dir;
}

describe('planScaffold (RM-097)', () => {
  test('S1 produces the 4 expected files', () => {
    const files = planScaffold({ name: 'my-cartridge', targetDir: '/tmp' });
    const paths = files.map((f) => f.path).sort();
    expect(paths).toEqual([
      'package.json',
      'src/__fixtures__/intent-fixture.ts',
      'src/__tests__/cartridge.test.ts',
      'src/cells.ts',
    ]);
  });

  test('S2 rejects non-kebab-case names', () => {
    expect(() => planScaffold({ name: 'MyCartridge', targetDir: '/tmp' })).toThrow(/kebab-case/);
    expect(() => planScaffold({ name: 'my_cartridge', targetDir: '/tmp' })).toThrow();
    expect(() => planScaffold({ name: '123-bad', targetDir: '/tmp' })).toThrow();
  });

  test('S3 package.json names the cartridge under @cartridges/', () => {
    const files = planScaffold({ name: 'demo', targetDir: '/tmp' });
    const pkg = JSON.parse(files.find((f) => f.path === 'package.json')!.contents);
    expect(pkg.name).toBe('@cartridges/demo');
    expect(pkg.dependencies).toMatchObject({
      '@semantos/cell-ops': 'workspace:*',
      '@semantos/intent': 'workspace:*',
    });
  });

  test('S4 cells.ts uses RM-096 typed signatures via defineCell + compose', () => {
    const files = planScaffold({ name: 'my-demo', targetDir: '/tmp' });
    const cells = files.find((f) => f.path === 'src/cells.ts')!.contents;
    expect(cells).toContain("import { defineCell, compose } from '@semantos/cell-ops'");
    expect(cells).toContain('myDemoEntry'); // camelCased entry export
    expect(cells).toContain("pre: [] as const");
    expect(cells).toContain("post: [] as const");
  });

  test('S5 fixture embeds the captured fingerprint when a trace is supplied', () => {
    const jsonl = [
      JSON.stringify({
        ts: '0',
        correlationId: 'corr-x',
        intentId: null,
        stage: 'reducer_pass_completed',
        durationMs: 1,
        hatId: null,
        source: 'nl',
        data: {
          pass: 'grammar',
          confidence: 0.85,
          flags: [],
          contributionKeys: ['taxonomy'],
          skipInComposite: false,
          alternativesCount: 0,
        },
      }),
    ].join('\n');
    const files = planScaffold({
      name: 'with-trace',
      targetDir: '/tmp',
      traceJsonl: jsonl,
    });
    const fixture = files.find((f) => f.path === 'src/__fixtures__/intent-fixture.ts')!.contents;
    expect(fixture).toContain('"pass": "grammar"');
    expect(fixture).toContain('"contributionKeys"');
    // Volatile fields stripped (RM-094 fingerprint contract).
    expect(fixture).not.toContain('corr-x');
    expect(fixture).not.toContain('durationMs');
  });

  test('S6 fixture is the empty array when no trace supplied', () => {
    const files = planScaffold({ name: 'empty', targetDir: '/tmp' });
    const fixture = files.find((f) => f.path === 'src/__fixtures__/intent-fixture.ts')!.contents;
    expect(fixture).toContain('CAPTURED_FINGERPRINT: FixtureEvent[] = []');
  });

  test('S7 regression test imports the requested input fixture by name', () => {
    const files = planScaffold({
      name: 'pick-input',
      targetDir: '/tmp',
      inputFixtureName: 'T2_LANDLORD_APPROVES_QUOTE',
    });
    const testFile = files.find((f) => f.path === 'src/__tests__/cartridge.test.ts')!.contents;
    expect(testFile).toContain('T2_LANDLORD_APPROVES_QUOTE');
    expect(testFile).not.toContain('T1_REPORT_DRIPPING_TAP');
  });
});

describe('writeScaffold (RM-097)', () => {
  test('S8 writes files to disk under <targetDir>/<name>/', async () => {
    const target = mkTmp();
    const { root, files } = await writeScaffold({ name: 'disk-demo', targetDir: target });
    expect(root).toBe(`${target}/disk-demo`);
    for (const f of files) {
      const onDisk = await Bun.file(`${root}/${f.path}`).text();
      expect(onDisk).toBe(f.contents);
    }
  });
});

```
