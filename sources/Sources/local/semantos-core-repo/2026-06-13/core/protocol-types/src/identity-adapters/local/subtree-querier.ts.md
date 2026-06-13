---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/local/subtree-querier.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.914555+00:00
---

# core/protocol-types/src/identity-adapters/local/subtree-querier.ts

```ts
/**
 * Subtree query — recursive walk yielding `{root, children[, grandchildren]}`.
 *
 * Pure I/O wrapper over CertChainStore. Same shape as the pre-split
 * `LocalIdentityAdapter.querySubtree`.
 */

import type { CertChainStore } from './cert-chain-store-facade';

export interface SubtreeChild {
  certId: string;
  childIndex: number;
  resourceId: string;
  grandchildren?: Array<{
    certId: string;
    childIndex: number;
    resourceId: string;
  }>;
}

export interface SubtreeResult {
  root: string;
  children: SubtreeChild[];
}

export async function querySubtree(
  certStore: CertChainStore,
  rootCertId: string,
  depth: number,
): Promise<SubtreeResult> {
  await certStore.getOrThrow(rootCertId);

  const directChildren = await certStore.getChildren(rootCertId);
  const children: SubtreeChild[] = directChildren.map((c) => ({
    certId: c.certId,
    childIndex: c.childIndex ?? 0,
    resourceId: c.resourceId ?? '',
  }));

  if (depth <= 1) return { root: rootCertId, children };

  const childrenWithGrandchildren = await Promise.all(
    children.map(async (child) => {
      const subtree = await querySubtree(certStore, child.certId, depth - 1);
      return {
        ...child,
        grandchildren: subtree.children.map((gc) => ({
          certId: gc.certId,
          childIndex: gc.childIndex,
          resourceId: gc.resourceId,
        })),
      };
    }),
  );

  return { root: rootCertId, children: childrenWithGrandchildren };
}

```
