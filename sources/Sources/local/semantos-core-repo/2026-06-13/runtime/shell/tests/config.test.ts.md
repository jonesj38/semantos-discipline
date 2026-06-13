---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/tests/config.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.362411+00:00
---

# runtime/shell/tests/config.test.ts

```ts
import { describe, test, expect, beforeEach, afterEach } from 'bun:test';
import { loadConfig } from '../src/config';

// ── Environment variable tests ───────────────────────────────

// Save and restore env vars around each test
const ENV_KEYS = [
  'SEMANTOS_MODE', 'SEMANTOS_HAT', 'SEMANTOS_EXTENSION',
  'SEMANTOS_FORMAT', 'SEMANTOS_ENDPOINT', 'PLEXUS_MODE', 'PLEXUS_ENDPOINT',
];

let savedEnv: Record<string, string | undefined>;

beforeEach(() => {
  savedEnv = {};
  for (const key of ENV_KEYS) {
    savedEnv[key] = process.env[key];
    delete process.env[key];
  }
});

afterEach(() => {
  for (const key of ENV_KEYS) {
    if (savedEnv[key] === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = savedEnv[key];
    }
  }
});

describe('loadConfig — defaults', () => {
  test('returns correct defaults with no config files or env vars', () => {
    const config = loadConfig();
    expect(config.adapterMode).toBe('stub');
    expect(config.activeHatId).toBeNull();
    expect(config.activeHatCertId).toBeNull();
    expect(config.defaultExtension).toBe('core');
    expect(config.defaultFormat).toBe('json');
    expect(config.plexusMode).toBe('stub');
    expect(config.plexusEndpoint).toBe('http://localhost:9000');
  });
});

describe('loadConfig — env var overrides', () => {
  test('SEMANTOS_MODE overrides adapter mode', () => {
    process.env.SEMANTOS_MODE = 'local';
    const config = loadConfig();
    expect(config.adapterMode).toBe('local');
  });

  test('SEMANTOS_MODE ignores invalid values', () => {
    process.env.SEMANTOS_MODE = 'bogus';
    const config = loadConfig();
    expect(config.adapterMode).toBe('stub'); // default preserved
  });

  test('SEMANTOS_HAT overrides active facet', () => {
    process.env.SEMANTOS_HAT = 'alice-facet';
    const config = loadConfig();
    expect(config.activeHatId).toBe('alice-facet');
  });

  test('SEMANTOS_EXTENSION overrides default extension', () => {
    process.env.SEMANTOS_EXTENSION = 'trades';
    const config = loadConfig();
    expect(config.defaultExtension).toBe('trades');
  });

  test('SEMANTOS_FORMAT overrides default format', () => {
    process.env.SEMANTOS_FORMAT = 'table';
    const config = loadConfig();
    expect(config.defaultFormat).toBe('table');
  });

  test('SEMANTOS_FORMAT ignores invalid values', () => {
    process.env.SEMANTOS_FORMAT = 'yaml';
    const config = loadConfig();
    expect(config.defaultFormat).toBe('json'); // default preserved
  });

  test('SEMANTOS_ENDPOINT overrides API endpoint', () => {
    process.env.SEMANTOS_ENDPOINT = 'https://api.example.com';
    const config = loadConfig();
    expect(config.apiEndpoint).toBe('https://api.example.com');
  });

  test('PLEXUS_MODE overrides plexus mode', () => {
    process.env.PLEXUS_MODE = 'real';
    const config = loadConfig();
    expect(config.plexusMode).toBe('real');
  });

  test('PLEXUS_ENDPOINT overrides plexus endpoint', () => {
    process.env.PLEXUS_ENDPOINT = 'https://plexus.example.com';
    const config = loadConfig();
    expect(config.plexusEndpoint).toBe('https://plexus.example.com');
  });

  test('multiple env vars override simultaneously', () => {
    process.env.SEMANTOS_MODE = 'cloud';
    process.env.SEMANTOS_HAT = 'bob';
    process.env.PLEXUS_MODE = 'cloud';
    const config = loadConfig();
    expect(config.adapterMode).toBe('cloud');
    expect(config.activeHatId).toBe('bob');
    expect(config.plexusMode).toBe('cloud');
  });
});

```
