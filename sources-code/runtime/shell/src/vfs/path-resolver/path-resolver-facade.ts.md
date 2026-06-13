---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/vfs/path-resolver/path-resolver-facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.389800+00:00
---

# runtime/shell/src/vfs/path-resolver/path-resolver-facade.ts

```ts
/**
 * VfsPathResolver facade — orchestrates the per-prefix resolvers,
 * with optional SemanticFS-backed async fallback for `objects/*`.
 *
 * Public API matches the pre-split class so `mount.ts` and the
 * shell index re-export compile unchanged.
 */

import type {
  ConfigStore,
  IdentityStore,
  LoomStore,
} from '@semantos/runtime-services';
import type { SemanticFS } from '@semantos/protocol-types';

import {
  getattrAsyncForObjects,
  readAsyncForObjects,
  readdirAsyncForObjects,
} from './async-resolver';
import { getattrFlow, readFlow, readdirFlows } from './flow-resolver';
import {
  getattrGovernance,
  readGovernance,
  readdirGovernance,
} from './governance-index';
import { getattrIdentity, readIdentity, readdirIdentities } from './identity-resolver';
import {
  getattrObject,
  readObject,
  readdirObjects,
} from './object-resolver';
import { parseVfsPath } from './path-parser';
import {
  getattrTaxonomy,
  readTaxonomy,
  readdirTaxonomy,
} from './taxonomy-resolver';
import type { VfsEntry, VfsFileContent } from './types';

const ROOT_ENTRIES = ['objects', 'identities', 'taxonomy', 'governance', 'flows'];

export class VfsPathResolver {
  private readonly semanticFs?: SemanticFS;

  constructor(
    private readonly store: LoomStore,
    private readonly identity: IdentityStore,
    private readonly config: ConfigStore,
    semanticFs?: SemanticFS,
  ) {
    if (semanticFs) this.semanticFs = semanticFs;
  }

  readdir(path: string): string[] | null {
    const { segments, prefix, tail } = parseVfsPath(path);
    if (segments.length === 0) return [...ROOT_ENTRIES];
    if (!prefix) return null;
    switch (prefix) {
      case 'objects':
        return readdirObjects(this.store, tail);
      case 'identities':
        return readdirIdentities(this.identity, tail);
      case 'taxonomy':
        return readdirTaxonomy(this.config, tail);
      case 'governance':
        return readdirGovernance(this.store, tail);
      case 'flows':
        return readdirFlows(this.config, tail);
    }
  }

  read(path: string): VfsFileContent | null {
    const { segments, prefix, tail } = parseVfsPath(path);
    if (segments.length < 2 || !prefix) return null;
    switch (prefix) {
      case 'objects':
        return readObject(this.store, tail);
      case 'identities':
        return readIdentity(this.identity, tail);
      case 'taxonomy':
        return readTaxonomy(this.config, tail);
      case 'governance':
        return readGovernance(this.store, tail);
      case 'flows':
        return readFlow(this.config, tail);
    }
  }

  getattr(path: string): VfsEntry | null {
    const { segments, prefix, tail } = parseVfsPath(path);
    if (segments.length === 0) return { type: 'directory', name: '', size: 0 };
    if (segments.length === 1) {
      if (prefix) return { type: 'directory', name: prefix, size: 0 };
      return null;
    }
    if (!prefix) return null;
    switch (prefix) {
      case 'objects':
        return getattrObject(this.store, tail);
      case 'identities':
        return getattrIdentity(this.identity, tail);
      case 'taxonomy':
        return getattrTaxonomy(this.config, tail);
      case 'governance':
        return getattrGovernance(this.store, tail);
      case 'flows':
        return getattrFlow(this.config, tail);
    }
  }

  // ── Async variants ────────────────────────────────────────

  async readdirAsync(path: string): Promise<string[] | null> {
    if (this.semanticFs) {
      const out = await readdirAsyncForObjects(this.semanticFs, path);
      if (out !== null) return out;
    }
    return this.readdir(path);
  }

  async readAsync(path: string): Promise<VfsFileContent | null> {
    if (this.semanticFs) {
      const out = await readAsyncForObjects(this.semanticFs, path);
      if (out !== null) return out;
    }
    return this.read(path);
  }

  async getattrAsync(path: string): Promise<VfsEntry | null> {
    if (this.semanticFs) {
      const out = await getattrAsyncForObjects(this.semanticFs, path);
      if (out !== null) return out;
    }
    return this.getattr(path);
  }
}

```
