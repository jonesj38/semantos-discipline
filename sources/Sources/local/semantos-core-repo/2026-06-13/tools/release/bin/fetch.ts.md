---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/release/bin/fetch.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.558865+00:00
---

# tools/release/bin/fetch.ts

```ts
#!/usr/bin/env bun
/**
 * release-fetch — walk the cell chain from a pinned stateHash, verify
 * every artifact's sha256, write the verified bytes out.
 *
 *   bun run tools/release/bin/fetch.ts <stateHash>
 *     [--room <room>]      default: derived by scanning all release.*.jsonl
 *     [--blobs <path>]     default: apps/demo-collab-versioning/data/blobs
 *     [--jsonl <path>]     when --room given
 *     [--out <dir>]        default: ./fetched/<name>-<version>/
 *
 * Tamper detection is unconditional. Signature verification (BRC-52
 * cert + BRC-100 envelope) is a follow-up — for now, the chain's
 * blob-hash integrity is what's enforced.
 */

import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';

import {
  LocalContentStore,
  jsonlPathFor,
  loadAllCells,
  walkChain,
  type ReleaseManifest,
  type SerializedCell,
} from '../lib';

const argv = process.argv.slice(2);
const positional = argv.filter(
  (a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1]!.startsWith('--')),
);
const stateHash = positional[0];
if (!stateHash) {
  console.error('usage: fetch.ts <stateHash> [--room ...] [--blobs ...] [--jsonl ...] [--out ...]');
  process.exit(1);
}

function arg(flag: string, dflt: string): string {
  const i = argv.indexOf(flag);
  if (i >= 0 && argv[i + 1]) return argv[i + 1]!;
  return dflt;
}

const REPO_ROOT = path.resolve(import.meta.dir, '../../..');
const DEFAULT_RELAY_DATA = path.join(REPO_ROOT, 'apps/demo-collab-versioning/data');
const blobsRoot = arg('--blobs', path.join(DEFAULT_RELAY_DATA, 'blobs'));
const explicitRoom = arg('--room', '');
const explicitJsonl = arg('--jsonl', '');

// If no room given, scan all release.*.jsonl until we find the stateHash.
function findCellAcrossRooms(): { cells: Map<string, SerializedCell>; jsonlPath: string } {
  if (explicitJsonl || explicitRoom) {
    const jsonlPath = explicitJsonl || jsonlPathFor(DEFAULT_RELAY_DATA, explicitRoom);
    const all = loadAllCells(jsonlPath);
    const byHash = new Map<string, SerializedCell>(all.map((c) => [c.stateHashHex, c]));
    return { cells: byHash, jsonlPath };
  }
  if (!existsSync(DEFAULT_RELAY_DATA)) {
    throw new Error(`relay data not found: ${DEFAULT_RELAY_DATA}`);
  }
  for (const f of readdirSync(DEFAULT_RELAY_DATA)) {
    if (!f.startsWith('release.') || !f.endsWith('.jsonl')) continue;
    const jsonlPath = path.join(DEFAULT_RELAY_DATA, f);
    const all = loadAllCells(jsonlPath);
    if (all.some((c) => c.stateHashHex === stateHash)) {
      const byHash = new Map<string, SerializedCell>(all.map((c) => [c.stateHashHex, c]));
      return { cells: byHash, jsonlPath };
    }
  }
  throw new Error(`stateHash ${stateHash} not found in any release.*.jsonl under ${DEFAULT_RELAY_DATA}`);
}

const { cells, jsonlPath } = findCellAcrossRooms();
console.log(`loaded ${cells.size} cells from ${path.relative(process.cwd(), jsonlPath)}`);

const chain = walkChain(cells, stateHash);
console.log(`chain: ${chain.length} cell(s) from root → pin`);
for (const c of chain) {
  const v = (c.patch.payload as { version?: string }).version ?? '?';
  console.log(`  depth=${c.depth} v=${v} state=${c.stateHashHex.slice(0, 16)}... hat=${c.hat}`);
}

const head = chain[chain.length - 1]!;
const manifest = head.patch.payload as unknown as ReleaseManifest;

const outDir = arg('--out', path.join(process.cwd(), `fetched/${manifest.name}-${manifest.version}`));
mkdirSync(outDir, { recursive: true });

const store = new LocalContentStore(blobsRoot);
console.log(`\nfetching ${manifest.name}@${manifest.version} → ${path.relative(process.cwd(), outDir)}`);

for (const [name, info] of Object.entries(manifest.artifacts)) {
  const bytes = store.get(info.sha256);
  if (bytes.length !== info.sizeBytes) {
    throw new Error(`size mismatch for ${name}: expected ${info.sizeBytes}, got ${bytes.length}`);
  }
  writeFileSync(path.join(outDir, name), bytes);
  console.log(`  ✓ ${name.padEnd(24)} ${info.sizeBytes} B  sha256=${info.sha256.slice(0, 16)}...`);
}

if (manifest.spec) {
  const bytes = store.get(manifest.spec.sha256);
  writeFileSync(path.join(outDir, 'spec.json'), bytes);
  console.log(`  ✓ ${'spec.json'.padEnd(24)} ${manifest.spec.sizeBytes} B  sha256=${manifest.spec.sha256.slice(0, 16)}...`);
}
if (manifest.primer) {
  const bytes = store.get(manifest.primer.sha256);
  writeFileSync(path.join(outDir, 'PRIMER.md'), bytes);
  console.log(`  ✓ ${'PRIMER.md'.padEnd(24)} ${manifest.primer.sizeBytes} B  sha256=${manifest.primer.sha256.slice(0, 16)}...`);
}

console.log(`\nverified release at ${path.relative(process.cwd(), outDir)}`);

```
