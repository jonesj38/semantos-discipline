---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/__tests__/forbidden-tokens.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.383464+00:00
---

# scripts/__tests__/forbidden-tokens.test.ts

```ts
/**
 * Self-test for the forbidden-tokens lint script.
 *
 * CW Lift L14 (docs/canon/cw-lift-matrix.yml).
 *
 * Verifies:
 *   1. The lint reports CLEAN on the current repo state (no regressions).
 *   2. The lint correctly FLAGS an introduced violation (sanity check
 *      that the scanner actually works).
 *   3. Strict mode exits non-zero when an error-severity rule fires.
 *   4. Report mode (default) exits zero even with errors present.
 *
 * The lint itself is in `scripts/forbidden-tokens.mjs` and its rule
 * config is in `scripts/forbidden-tokens.config.json`. This test invokes
 * the script as a subprocess so the test exercises the actual CLI
 * entry point.
 */

import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'fs';
import { resolve, join } from 'path';
import { tmpdir } from 'os';

const REPO_ROOT = resolve(import.meta.dir, '..', '..');
const SCRIPT = resolve(REPO_ROOT, 'scripts/forbidden-tokens.mjs');

function runLint(args: string[] = []): { stdout: string; status: number } {
  const result = spawnSync('bun', [SCRIPT, '--no-color', ...args], {
    cwd: REPO_ROOT,
    encoding: 'utf8',
  });
  return {
    stdout: (result.stdout ?? '') + (result.stderr ?? ''),
    status: result.status ?? -1,
  };
}

describe('CW Lift L14: forbidden-tokens lint self-test', () => {
  test('repo is clean against the shipped ruleset', () => {
    const { stdout, status } = runLint();
    expect(status).toBe(0);
    expect(stdout).toContain('clean');
  });

  test('strict mode also exits 0 on a clean repo', () => {
    const { status } = runLint(['--strict']);
    expect(status).toBe(0);
  });

  test('detects an introduced violation via alternative config', () => {
    // Build a tiny temporary config that activates a rule against a
    // pattern we know exists in the repo (e.g. "verifyAnchor" — an
    // internal API name, used only for the sanity check). This proves
    // the scanner actually finds matches.
    const tmp = mkdtempSync(join(tmpdir(), 'cw-lift-l14-'));
    try {
      const configPath = join(tmp, 'config.json');
      const config = {
        comment: 'test config — flags `verifyAnchor` (an internal API name)',
        globalIgnores: ['node_modules/', 'dist/', 'worktrees/', 'archive/'],
        rules: [
          {
            id: 'test-verifyAnchor',
            pattern: 'verifyAnchor',
            severity: 'error',
            rationale: 'test rule (verifies the scanner finds matches)',
            scope: { include: ['core/anchor-attestation/**'] },
          },
        ],
      };
      writeFileSync(configPath, JSON.stringify(config));

      // Report mode: exits 0 but reports the hit
      const { stdout: reportOut, status: reportStatus } = runLint(['--config', configPath]);
      expect(reportStatus).toBe(0);
      expect(reportOut).toContain('test-verifyAnchor');
      expect(reportOut).toMatch(/error.*test-verifyAnchor|test-verifyAnchor.*error/i);

      // Strict mode: exits 1 because there's an error-severity hit
      const { status: strictStatus } = runLint(['--strict', '--config', configPath]);
      expect(strictStatus).toBe(1);
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });

  test('warn-only hits do NOT fail strict mode', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'cw-lift-l14-warn-'));
    try {
      const configPath = join(tmp, 'config.json');
      const config = {
        comment: 'test config — warn-severity hits should not fail strict',
        globalIgnores: ['node_modules/', 'dist/', 'worktrees/', 'archive/'],
        rules: [
          {
            id: 'test-warn-only',
            pattern: 'createAnchorAttestation',
            severity: 'warn',
            rationale: 'test warn rule',
            scope: { include: ['core/anchor-attestation/**'] },
          },
        ],
      };
      writeFileSync(configPath, JSON.stringify(config));

      const { stdout, status } = runLint(['--strict', '--config', configPath]);
      // warn-severity hits don't fail strict mode
      expect(status).toBe(0);
      expect(stdout).toContain('test-warn-only');
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });

  test('config exclude path-pattern actually suppresses hits', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'cw-lift-l14-excl-'));
    try {
      const configPath = join(tmp, 'config.json');
      const config = {
        comment: 'test exclude pattern',
        globalIgnores: ['node_modules/', 'dist/', 'worktrees/', 'archive/'],
        rules: [
          {
            id: 'test-excluded',
            pattern: 'verifyAnchor',
            severity: 'error',
            rationale: 'test exclude',
            scope: {
              include: ['core/anchor-attestation/**'],
              exclude: ['core/anchor-attestation/**'], // exclude everything we just included
            },
          },
        ],
      };
      writeFileSync(configPath, JSON.stringify(config));

      const { stdout, status } = runLint(['--strict', '--config', configPath]);
      expect(status).toBe(0);
      expect(stdout).toContain('clean');
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });
});

```
