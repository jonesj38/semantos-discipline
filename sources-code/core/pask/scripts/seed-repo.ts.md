---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/scripts/seed-repo.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.927490+00:00
---

# core/pask/scripts/seed-repo.ts

```ts
#!/usr/bin/env bun
/**
 * seed-repo.ts — manufacture plausible release cells across multiple
 * rooms so we can prove the repo-analytics loop works without first
 * lifting the real release pipeline to every package in the repo.
 *
 * Generates:
 *   release.kernel.cell-engine: 0.1.0 → 0.1.1 → 0.2.0
 *   release.lib.protocol-types: 0.1.0 → 0.2.0
 *   release.kernel.pask: extends the existing real chain with
 *                        0.2.0 (deps on cell-engine 0.1.0)
 *                        0.3.0 (deps on cell-engine 0.2.0)
 *
 * The wasm/spec/primer artifacts for the faux entries are made up —
 * we hash random bytes so each release has a distinct sha256, but
 * the bytes go into the ContentStore at their content-addressed
 * paths, so a fetch would still pass verification.
 *
 * This is a one-shot dev tool. After repo-analytics proves out, the
 * real lift is to give cell-engine and protocol-types their own
 * `release.config.ts` and run them through the real pipeline.
 */

import { createHash, randomBytes } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync, mkdirSync, appendFileSync } from 'node:fs';
import path from 'node:path';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const PASK_ROOT = path.resolve(HERE, '..');
const REPO_ROOT = path.resolve(PASK_ROOT, '../..');
const RELAY_DATA = path.join(REPO_ROOT, 'apps/demo-collab-versioning/data');
const BLOBS_ROOT = path.join(RELAY_DATA, 'blobs');

function sha256Hex(bytes: Uint8Array): string {
  return createHash('sha256').update(bytes).digest('hex');
}

function blobPath(hashHex: string): string {
  return path.join(BLOBS_ROOT, hashHex.slice(0, 2), hashHex);
}

function putBlob(bytes: Uint8Array): { sha256: string; sizeBytes: number } {
  const sha256 = sha256Hex(bytes);
  const file = blobPath(sha256);
  const dir = path.dirname(file);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  if (!existsSync(file)) writeFileSync(file, bytes);
  return { sha256, sizeBytes: bytes.length };
}

function canonicalJson(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(canonicalJson).join(',') + ']';
  const obj = value as Record<string, unknown>;
  const keys = Object.keys(obj).sort();
  return '{' + keys.map((k) => JSON.stringify(k) + ':' + canonicalJson(obj[k])).join(',') + '}';
}

interface SerializedCell {
  id: string;
  stateHashHex: string;
  parentHashes: string[];
  patch: { op: string; payload: Record<string, unknown> };
  hat: string;
  depth: number;
  branch: string;
  cherryPickedFromHash: string | null;
  tampered: boolean;
  author?: string;
}

function loadAllCells(jsonl: string): SerializedCell[] {
  if (!existsSync(jsonl)) return [];
  return readFileSync(jsonl, 'utf8')
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line) as SerializedCell);
}

function lastReleaseCell(cells: SerializedCell[]): SerializedCell | null {
  for (let i = cells.length - 1; i >= 0; i--) {
    if (cells[i]!.patch.op === 'release.kernel.publish') return cells[i]!;
  }
  return null;
}

function appendCell(room: string, cell: SerializedCell) {
  const file = path.join(RELAY_DATA, `${room}.jsonl`);
  if (!existsSync(RELAY_DATA)) mkdirSync(RELAY_DATA, { recursive: true });
  appendFileSync(file, JSON.stringify(cell) + '\n');
}

interface ReleaseSpec {
  name: string;
  version: string;
  hat: string;
  /** Cross-package deps. Each is { name, release: stateHashOfTheirCell } */
  dependencies?: Array<{ name: string; release: string }>;
  /** Pretend builtAt — a faux timestamp for deterministic ordering. */
  builtAtMs: number;
}

function publishRelease(room: string, spec: ReleaseSpec): string {
  // Make up artifacts: random bytes hashed, stored in ContentStore.
  const wasm = randomBytes(8192);
  const wasmRef = putBlob(wasm);
  const specBlob = new TextEncoder().encode(JSON.stringify({
    name: spec.name,
    version: spec.version,
    fauxArtifact: true,
  }, null, 2));
  const specRef = putBlob(specBlob);

  const existing = loadAllCells(path.join(RELAY_DATA, `${room}.jsonl`));
  const parent = lastReleaseCell(existing);

  const payload = {
    schema: 'release.kernel.v1',
    name: spec.name,
    version: spec.version,
    description: `${spec.name} (faux seed for repo-analytics test)`,
    artifacts: {
      [`${spec.name}.wasm`]: {
        name: `${spec.name}.wasm`,
        target: 'wasm32-freestanding',
        sizeBytes: wasm.length,
        sha256: wasmRef.sha256,
      },
    },
    spec: { schema: '1', sha256: specRef.sha256, sizeBytes: specBlob.length },
    build: {
      zigVersion: '0.15.2',
      sourceCommit: 'faux',
      builtAt: new Date(spec.builtAtMs).toISOString(),
    },
    dependencies: spec.dependencies ?? [],
    parentReleaseHash: parent ? parent.stateHashHex : '',
    hat: spec.hat,
  };
  const cellCore = {
    parentHashes: parent ? [parent.stateHashHex] : [],
    patch: { op: 'release.kernel.publish', payload },
    hat: spec.hat,
    depth: parent ? parent.depth + 1 : 0,
    branch: 'main',
    cherryPickedFromHash: null,
    tampered: false,
  };
  const stateHashHex = sha256Hex(new TextEncoder().encode(canonicalJson(cellCore)));
  const cell: SerializedCell = {
    id: stateHashHex.slice(0, 16),
    stateHashHex,
    ...cellCore,
    author: spec.hat,
  };
  appendCell(room, cell);
  console.log(`  ${room}  ${spec.name}@${spec.version}  state=${stateHashHex.slice(0, 16)}  depth=${cell.depth}`);
  return stateHashHex;
}

// ── Build the seed ──────────────────────────────────────────────────────

console.log('seeding faux releases ...');

// Cell-engine line.
const ce010 = publishRelease('release.kernel.cell-engine', {
  name: 'cell-engine', version: '0.1.0', hat: 'cell-engine-maintainer@semantos',
  builtAtMs: Date.now() - 14 * 24 * 60 * 60 * 1000, // 14 days ago
});
const ce011 = publishRelease('release.kernel.cell-engine', {
  name: 'cell-engine', version: '0.1.1', hat: 'cell-engine-maintainer@semantos',
  builtAtMs: Date.now() - 10 * 24 * 60 * 60 * 1000,
});
const ce020 = publishRelease('release.kernel.cell-engine', {
  name: 'cell-engine', version: '0.2.0', hat: 'cell-engine-maintainer@semantos',
  builtAtMs: Date.now() - 5 * 24 * 60 * 60 * 1000,
});

// Protocol-types line — older release pinning cell-engine 0.1.0,
// newer release pinning cell-engine 0.2.0.
const pt010 = publishRelease('release.lib.protocol-types', {
  name: 'protocol-types', version: '0.1.0', hat: 'protocol-types-maintainer@semantos',
  builtAtMs: Date.now() - 12 * 24 * 60 * 60 * 1000,
  dependencies: [{ name: 'cell-engine', release: ce010 }],
});
const pt020 = publishRelease('release.lib.protocol-types', {
  name: 'protocol-types', version: '0.2.0', hat: 'protocol-types-maintainer@semantos',
  builtAtMs: Date.now() - 4 * 24 * 60 * 60 * 1000,
  dependencies: [{ name: 'cell-engine', release: ce020 }],
});

// Pask line — already has 0.1.0 from the real submitter; we add 0.2.0
// (pinning cell-engine 0.1.0) and 0.3.0 (pinning cell-engine 0.2.0).
publishRelease('release.kernel.pask', {
  name: 'pask', version: '0.2.0', hat: 'pask-maintainer@semantos',
  builtAtMs: Date.now() - 7 * 24 * 60 * 60 * 1000,
  dependencies: [{ name: 'cell-engine', release: ce010 }],
});
publishRelease('release.kernel.pask', {
  name: 'pask', version: '0.3.0', hat: 'pask-maintainer@semantos',
  builtAtMs: Date.now() - 2 * 24 * 60 * 60 * 1000,
  dependencies: [
    { name: 'cell-engine', release: ce020 },
    { name: 'protocol-types', release: pt020 },
  ],
});

console.log('\nseed complete.');
console.log('next: bun run scripts/repo-analytics.ts');

```
