---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-legacy-cli/src/fs-persistence.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.697427+00:00
---

# archive/apps-legacy-cli/src/fs-persistence.ts

```ts
/**
 * Filesystem-backed GrantPersistence for the Phase 1 CLI.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI1 — "stored at
 * `~/.semantos/legacy-grants/<provider>/<grant-id>.enc`".
 *
 * Lays out every legacy-ingest store under a single root directory:
 *
 *   <root>/
 *     legacy-clients/<provider>.enc
 *     legacy-grants/<provider>/<grant-id>.enc
 *     legacy-ingest/<provider>/<provider-item-id>.enc
 *     legacy-ingest-cursor/<provider>/<grant-id>.json
 *     legacy-proposals/<provider>/<proposal-id>.enc
 *     legacy-receipts/<provider>/<receipt-id>.enc
 *     legacy-corrections/<provider>/<correction-id>.enc
 *     audit.log                                     (plaintext, JSON-line)
 *
 * Files are written with mode 0600 — operator-only read/write. Directories
 * are created on demand with mode 0700. The CLI is single-process, so
 * concurrent-writer locking is not required at this layer.
 */

import { existsSync, readFileSync, writeFileSync, unlinkSync, mkdirSync, readdirSync, statSync, chmodSync } from 'node:fs';
import { dirname, join, sep } from 'node:path';
import type { GrantPersistence } from '@semantos/legacy-ingest';

export interface FsPersistenceOpts {
  /** Root directory (defaults to `~/.semantos`). */
  root?: string;
}

export class FsPersistence implements GrantPersistence {
  private readonly root: string;

  constructor(opts: FsPersistenceOpts = {}) {
    this.root = opts.root ?? defaultRoot();
    ensureDir(this.root);
  }

  async read(key: string): Promise<Uint8Array | null> {
    const path = this.pathFor(key);
    if (!existsSync(path)) return null;
    return new Uint8Array(readFileSync(path));
  }

  async write(key: string, data: Uint8Array): Promise<void> {
    const path = this.pathFor(key);
    ensureDir(dirname(path));
    writeFileSync(path, data, { mode: 0o600 });
    chmodSync(path, 0o600);
  }

  async delete(key: string): Promise<void> {
    const path = this.pathFor(key);
    if (existsSync(path)) unlinkSync(path);
  }

  async list(prefix: string): Promise<string[]> {
    const start = this.pathFor(prefix);
    // The persistence-API prefix can be a directory ("legacy-grants/gmail/")
    // or a file-stem prefix ("legacy-grants/gmail/g-"). Walk the deepest
    // existing directory and filter by the original prefix.
    const dirToWalk = walkUpToExistingDir(start);
    if (dirToWalk === null) return [];
    const out: string[] = [];
    walk(dirToWalk, (file) => {
      const rel = relativeKey(this.root, file);
      if (rel.startsWith(prefix)) out.push(rel);
    });
    return out;
  }

  /** Resolves the key (relative path with `/` separators) to an absolute fs path. */
  private pathFor(key: string): string {
    return join(this.root, ...key.split('/'));
  }
}

// ── Helpers ──

function ensureDir(dir: string): void {
  if (existsSync(dir)) return;
  mkdirSync(dir, { recursive: true, mode: 0o700 });
}

function walkUpToExistingDir(target: string): string | null {
  let dir = target;
  // If `target` itself is a directory we're done.
  if (existsSync(dir) && statSync(dir).isDirectory()) return dir;
  // Otherwise walk up until we find one that exists.
  while (!existsSync(dir)) {
    const parent = dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
  if (statSync(dir).isDirectory()) return dir;
  return null;
}

function walk(dir: string, visit: (file: string) => void): void {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) walk(full, visit);
    else if (entry.isFile()) visit(full);
  }
}

function relativeKey(root: string, file: string): string {
  let rel = file.startsWith(root + sep) ? file.slice(root.length + 1) : file;
  // Normalise path separator to '/' so the in-API key matches what the
  // legacy-ingest stores expect (cross-platform — works on Windows in
  // theory, though the operator-side product targets POSIX).
  if (sep !== '/') rel = rel.split(sep).join('/');
  return rel;
}

function defaultRoot(): string {
  const home = process.env.HOME ?? process.env.USERPROFILE;
  if (!home) {
    throw new Error('legacy-cli: cannot determine HOME; pass --root explicitly');
  }
  return join(home, '.semantos');
}

```
