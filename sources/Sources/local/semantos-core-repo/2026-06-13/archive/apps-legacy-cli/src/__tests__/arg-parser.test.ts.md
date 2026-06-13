---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-legacy-cli/src/__tests__/arg-parser.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.700444+00:00
---

# archive/apps-legacy-cli/src/__tests__/arg-parser.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { parseArgs } from '../arg-parser';

describe('parseArgs', () => {
  test('parses single verb with no flags', () => {
    const r = parseArgs(['providers']);
    expect(r.positional).toEqual(['providers']);
    expect(r.flags).toEqual({});
    expect(r.cliFlags).toEqual({});
  });

  test('parses verb + positional + string flag', () => {
    const r = parseArgs(['register-client', 'gmail', '--client-id', 'abc.googleusercontent.com']);
    expect(r.positional).toEqual(['register-client', 'gmail']);
    expect(r.flags).toEqual({ 'client-id': 'abc.googleusercontent.com' });
  });

  test('parses multiple flags', () => {
    const r = parseArgs([
      'register-client', 'gmail',
      '--client-id', 'abc',
      '--client-secret', 'GOCSPX-x',
      '--redirect-uri', 'https://x/cb',
    ]);
    expect(r.flags).toEqual({
      'client-id': 'abc',
      'client-secret': 'GOCSPX-x',
      'redirect-uri': 'https://x/cb',
    });
  });

  test('treats trailing --flag as boolean true', () => {
    const r = parseArgs(['register-client', 'gmail', '--pkce']);
    expect(r.flags).toEqual({ pkce: true });
  });

  test('treats --flag followed by --next-flag as boolean true', () => {
    const r = parseArgs(['ingest', 'gmail', '--max-pages', '5', '--dry-run', '--quiet']);
    expect(r.flags).toEqual({ 'max-pages': 5, 'dry-run': true });
    expect(r.cliFlags.quiet).toBe(true);
  });

  test('coerces numeric flag values to numbers', () => {
    const r = parseArgs(['ingest', 'gmail', '--max-pages', '50']);
    expect(r.flags).toEqual({ 'max-pages': 50 });
    expect(typeof r.flags['max-pages']).toBe('number');
  });

  test('keeps non-numeric flag values as strings', () => {
    const r = parseArgs(['ingest', 'gmail', '--since', '2024-01-01']);
    // 2024-01-01 is not a numeric literal — kept as string.
    expect(r.flags).toEqual({ since: '2024-01-01' });
    expect(typeof r.flags.since).toBe('string');
  });

  test('peels CLI-level flags out of the verb-flag bag', () => {
    const r = parseArgs(['--root', '/tmp/xyz', '--passphrase', 'pw', 'providers']);
    expect(r.positional).toEqual(['providers']);
    expect(r.flags).toEqual({});
    expect(r.cliFlags).toEqual({ root: '/tmp/xyz', passphrase: 'pw' });
  });

  test('handles confidence flag with operator+number unsplit', () => {
    const r = parseArgs(['review', '--confidence', '>=0.85']);
    expect(r.flags).toEqual({ confidence: '>=0.85' });
  });

  test('preserves trailing positionals after `--`', () => {
    const r = parseArgs(['ratify', '--', 'gmail:abc:def']);
    expect(r.positional).toEqual(['ratify', 'gmail:abc:def']);
  });

  test('--help with no positional sets cliFlags.help', () => {
    const r = parseArgs(['--help']);
    expect(r.cliFlags.help).toBe(true);
    expect(r.positional).toEqual([]);
  });
});

```
