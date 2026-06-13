---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/release/bin/build.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.558330+00:00
---

# tools/release/bin/build.ts

```ts
#!/usr/bin/env bun
/**
 * release-build — assemble a manifest for any package.
 *
 *   bun run tools/release/bin/build.ts --config <path/to/release.config.ts>
 *
 * Reads the config, hashes every artifact + spec + primer, writes the
 * manifest JSON next to the artifacts (in `<packageRoot>/zig-out/release/`
 * by default, or `--out <dir>`).
 */

import { existsSync, mkdirSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';

import { assembleManifest, loadConfig } from '../lib';

const argv = process.argv.slice(2);
function arg(flag: string, dflt?: string): string {
  const i = argv.indexOf(flag);
  if (i >= 0 && argv[i + 1]) return argv[i + 1]!;
  if (dflt !== undefined) return dflt;
  throw new Error(`missing ${flag}`);
}

const { config, paths } = await loadConfig(arg('--config'));

const outDir = arg('--out', path.join(paths.packageRoot, 'zig-out/release'));
if (!existsSync(outDir)) mkdirSync(outDir, { recursive: true });

const manifest = assembleManifest(config, { packageRoot: paths.packageRoot });
const outPath = path.join(outDir, `${config.name}-${config.version}.json`);
writeFileSync(outPath, JSON.stringify(manifest, null, 2) + '\n');

console.log(`wrote ${path.relative(process.cwd(), outPath)} (${statSync(outPath).size} bytes)`);
for (const a of Object.values(manifest.artifacts)) {
  console.log(`  ${a.name.padEnd(24)} sha256=${a.sha256.slice(0, 16)}...  ${a.sizeBytes} B`);
}
if (manifest.spec) console.log(`  ${'spec'.padEnd(24)} sha256=${manifest.spec.sha256.slice(0, 16)}...  ${manifest.spec.sizeBytes} B`);
if (manifest.primer) console.log(`  ${'primer'.padEnd(24)} sha256=${manifest.primer.sha256.slice(0, 16)}...  ${manifest.primer.sizeBytes} B`);
console.log(`  zigVersion       ${manifest.build.zigVersion}`);
console.log(`  sourceCommit     ${manifest.build.sourceCommit || '(no git)'}`);

```
