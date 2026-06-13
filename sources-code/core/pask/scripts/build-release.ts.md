---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/scripts/build-release.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.928023+00:00
---

# core/pask/scripts/build-release.ts

```ts
#!/usr/bin/env bun
/**
 * Thin wrapper — delegates to tools/release/bin/build.ts using
 * core/pask/release.config.ts. The shared release pipeline lives at
 * tools/release/; this wrapper exists so `bun run scripts/build-release.ts`
 * from core/pask/ keeps working.
 */
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const PASK_ROOT = path.resolve(HERE, '..');
const REPO_ROOT = path.resolve(PASK_ROOT, '../..');

const result = spawnSync(
  'bun',
  [
    'run',
    path.join(REPO_ROOT, 'tools/release/bin/build.ts'),
    '--config',
    path.join(PASK_ROOT, 'release.config.ts'),
    ...process.argv.slice(2),
  ],
  { stdio: 'inherit' },
);
process.exit(result.status ?? 1);

```
