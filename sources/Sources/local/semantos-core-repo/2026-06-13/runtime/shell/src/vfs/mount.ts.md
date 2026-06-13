---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/vfs/mount.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.379906+00:00
---

# runtime/shell/src/vfs/mount.ts

```ts
/**
 * SemanticVFS — FUSE mount exposing semantic objects as files.
 *
 * Read-only filesystem. All reads go through VfsPathResolver → store services.
 * Write operations return EROFS (read-only filesystem).
 *
 * Requires FUSE support on the host (macFUSE on macOS, libfuse on Linux).
 * Falls back gracefully if fuse-native is not available.
 */

import { mkdirSync, existsSync } from 'fs';
import { VfsPathResolver } from './pathResolver';
import type { LoomStore, IdentityStore, ConfigStore } from '@semantos/runtime-services';
import type { SemanticFS } from '@semantos/protocol-types';

// FUSE error codes
const ENOENT = -2;   // No such file or directory
const EACCES = -13;  // Permission denied
const EROFS = -30;   // Read-only filesystem
const ENOTDIR = -20; // Not a directory
const EISDIR = -21;  // Is a directory

// File mode constants
const S_IFDIR = 0o40000;
const S_IFREG = 0o100000;
const DIR_MODE = S_IFDIR | 0o555;
const FILE_MODE = S_IFREG | 0o444;

export class SemanticVFS {
  private resolver: VfsPathResolver;
  private fuse: unknown = null;
  private mounted = false;

  constructor(
    store: LoomStore,
    identity: IdentityStore,
    config: ConfigStore,
    private mountPoint: string = '/semantos',
    semanticFs?: SemanticFS,
  ) {
    this.resolver = new VfsPathResolver(store, identity, config, semanticFs);
  }

  /** Get the path resolver (for testing / direct access). */
  getResolver(): VfsPathResolver {
    return this.resolver;
  }

  /** Mount the VFS. Requires fuse-native to be installed. */
  async mount(): Promise<void> {
    // Ensure mount point exists
    if (!existsSync(this.mountPoint)) {
      mkdirSync(this.mountPoint, { recursive: true });
    }

    let Fuse: any;
    try {
      Fuse = (await import('fuse-native')).default;
    } catch {
      throw new Error(
        'fuse-native is not installed or FUSE is not available on this system. ' +
        'Install with: npm install fuse-native (requires macFUSE on macOS or libfuse on Linux)'
      );
    }

    const resolver = this.resolver;

    const ops = {
      readdir(path: string, cb: (err: number, names?: string[]) => void) {
        resolver.readdirAsync(path).then(entries => {
          if (entries === null) return cb(ENOENT);
          cb(0, entries);
        }).catch(() => cb(ENOENT));
      },

      getattr(path: string, cb: (err: number, stat?: unknown) => void) {
        // Root path
        if (path === '/') {
          return cb(0, {
            mtime: new Date(),
            atime: new Date(),
            ctime: new Date(),
            nlink: 1,
            size: 0,
            mode: DIR_MODE,
            uid: process.getuid?.() ?? 0,
            gid: process.getgid?.() ?? 0,
          });
        }

        resolver.getattrAsync(path).then(entry => {
          if (!entry) return cb(ENOENT);
          cb(0, {
            mtime: new Date(),
            atime: new Date(),
            ctime: new Date(),
            nlink: 1,
            size: entry.size,
            mode: entry.type === 'directory' ? DIR_MODE : FILE_MODE,
            uid: process.getuid?.() ?? 0,
            gid: process.getgid?.() ?? 0,
          });
        }).catch(() => cb(ENOENT));
      },

      open(path: string, flags: number, cb: (err: number, fd?: number) => void) {
        resolver.getattrAsync(path).then(entry => {
          if (!entry) return cb(ENOENT);
          if (entry.type === 'directory') return cb(EISDIR);
          if ((flags & 3) !== 0) return cb(EROFS);
          cb(0, 0);
        }).catch(() => cb(ENOENT));
      },

      read(
        path: string,
        fd: number,
        buf: Buffer,
        len: number,
        pos: number,
        cb: (bytesRead: number) => void,
      ) {
        resolver.readAsync(path).then(content => {
          if (!content) return cb(0);
          const slice = content.data.subarray(pos, pos + len);
          slice.copy(buf);
          cb(slice.length);
        }).catch(() => cb(0));
      },

      // ── Write operations — all return EROFS ──────────────

      write(_path: string, _fd: number, _buf: Buffer, _len: number, _pos: number, cb: (err: number) => void) {
        cb(EROFS);
      },

      create(_path: string, _mode: number, cb: (err: number) => void) {
        cb(EROFS);
      },

      unlink(_path: string, cb: (err: number) => void) {
        cb(EROFS);
      },

      rename(_src: string, _dst: string, cb: (err: number) => void) {
        cb(EROFS);
      },

      mkdir(_path: string, _mode: number, cb: (err: number) => void) {
        cb(EROFS);
      },

      rmdir(_path: string, cb: (err: number) => void) {
        cb(EROFS);
      },

      truncate(_path: string, _size: number, cb: (err: number) => void) {
        cb(EROFS);
      },

      chmod(_path: string, _mode: number, cb: (err: number) => void) {
        cb(EROFS);
      },

      chown(_path: string, _uid: number, _gid: number, cb: (err: number) => void) {
        cb(EROFS);
      },
    };

    this.fuse = new Fuse(this.mountPoint, ops, { force: true, displayFolder: true });

    return new Promise<void>((resolve, reject) => {
      (this.fuse as any).mount((err: Error | null) => {
        if (err) return reject(err);
        this.mounted = true;
        resolve();
      });
    });
  }

  /** Unmount the VFS. */
  async unmount(): Promise<void> {
    if (!this.fuse || !this.mounted) return;

    return new Promise<void>((resolve, reject) => {
      (this.fuse as any).unmount((err: Error | null) => {
        if (err) return reject(err);
        this.mounted = false;
        resolve();
      });
    });
  }

  /** Check if VFS is currently mounted. */
  isMounted(): boolean {
    return this.mounted;
  }
}

```
