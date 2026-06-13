---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/release/bump_beam_version.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.547765+00:00
---

# tools/release/bump_beam_version.js

```js
#!/usr/bin/env node
/**
 * bump_beam_version.js <version>
 *
 * Rewrites the `version:` field in every mix.exs file under
 * runtime/world-beam/ to match the changeset-bumped version.
 *
 * Called automatically by the `version` script in
 * runtime/world-beam/package.json during `pnpm changeset version`.
 *
 * Usage:
 *   node tools/release/bump_beam_version.js 0.7.0
 */

import { readFileSync, writeFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, '../..');

const version = process.argv[2];
if (!version || !/^\d+\.\d+\.\d+/.test(version)) {
  console.error(`bump_beam_version: invalid version "${version}"`);
  process.exit(1);
}

const targets = [
  'runtime/world-beam/mix.exs',
  'runtime/world-beam/apps/world_host/mix.exs',
  'runtime/world-beam/apps/cell_relay/mix.exs',
];

for (const rel of targets) {
  const path = resolve(repoRoot, rel);
  const original = readFileSync(path, 'utf8');
  // Match `version: "x.y.z"` — both standalone and inside a keyword list.
  const updated = original.replace(
    /(\bversion:\s*")[^"]+(")/,
    `$1${version}$2`,
  );
  if (updated === original) {
    console.warn(`bump_beam_version: no version field found in ${rel}`);
    continue;
  }
  writeFileSync(path, updated);
  console.log(`bump_beam_version: ${rel} → ${version}`);
}

```
