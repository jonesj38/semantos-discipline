---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/vfs/path-resolver/identity-resolver.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.390664+00:00
---

# runtime/shell/src/vfs/path-resolver/identity-resolver.ts

```ts
/**
 * Per-identity-hat VFS view. Same files the legacy resolver emitted:
 * `cert.json`, `capabilities.json`, `glowweight.json`, `derivation.json`.
 */

import type { IdentityStore } from '@semantos/runtime-services';

import { jsonContent } from './path-parser';
import type { VfsEntry, VfsFileContent } from './types';

const FILES = ['cert.json', 'capabilities.json', 'glowweight.json', 'derivation.json'];

export function readdirIdentities(
  identity: IdentityStore,
  segments: string[],
): string[] | null {
  const id = identity.getIdentity();
  if (!id) return segments.length === 0 ? [] : null;

  if (segments.length === 0) {
    return id.hats.filter((f) => f.certId).map((f) => f.certId as string);
  }

  const certId = segments[0] as string;
  const hat = id.hats.find((f) => f.certId === certId);
  if (!hat) return null;
  if (segments.length === 1) return [...FILES];
  return null;
}

export function readIdentity(
  identity: IdentityStore,
  segments: string[],
): VfsFileContent | null {
  if (segments.length < 2) return null;
  const id = identity.getIdentity();
  if (!id) return null;

  const hat = id.hats.find((f) => f.certId === segments[0]);
  if (!hat) return null;

  switch (segments[1]) {
    case 'cert.json':
      return jsonContent({
        certId: hat.certId,
        name: hat.name,
        displayName: hat.displayName,
        publicKey: hat.publicKey,
      });
    case 'capabilities.json':
      return jsonContent(hat.capabilities);
    case 'glowweight.json':
      return jsonContent({
        base: 50,
        activity: 0,
        disputeOutcomes: 0,
        contributions: 0,
        total: 50,
      });
    case 'derivation.json':
      return jsonContent({
        parentCertId: id.certId,
        derivationPath: hat.derivationPath,
        domainFlags: [],
      });
    default:
      return null;
  }
}

export function getattrIdentity(
  identity: IdentityStore,
  segments: string[],
): VfsEntry | null {
  const id = identity.getIdentity();
  if (!id) return null;

  if (segments.length === 1) {
    const hat = id.hats.find((f) => f.certId === segments[0]);
    if (hat) return { type: 'directory', name: segments[0] as string, size: 0 };
    return null;
  }

  if (segments.length === 2) {
    const content = readIdentity(identity, segments);
    if (content) return { type: 'file', name: segments[1] as string, size: content.size };
  }

  return null;
}

```
