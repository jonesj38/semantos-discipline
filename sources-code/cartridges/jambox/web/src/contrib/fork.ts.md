---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/contrib/fork.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.606878+00:00
---

# cartridges/jambox/web/src/contrib/fork.ts

```ts
/**
 * D-F.5 — Fork / remix lineage.
 *
 * forkObject() creates a new object whose header.parents[0] points to
 * the original. License propagation is enforced: fork can only NARROW,
 * never widen.
 *
 * License lattice (ascending permissiveness):
 *   personal  <  remixable  <  commercial
 */

import {
  semanticObjectId,
  type JamboxObjectKind,
  type SemanticObjectHeader,
  type JamboxSemanticObject,
} from '../semantic/objects';

export type JamboxLicense = 'personal' | 'remixable' | 'commercial';

const LICENSE_LEVEL: Record<JamboxLicense, number> = {
  personal:   0,
  remixable:  1,
  commercial: 2,
};

export class LicenseViolationError extends Error {
  constructor(
    public readonly parentLicense: JamboxLicense,
    public readonly requestedLicense: JamboxLicense,
  ) {
    super(
      `Fork license violation: cannot widen license from '${parentLicense}' to '${requestedLicense}'. ` +
      `Fork can only NARROW the license lattice.`,
    );
    this.name = 'LicenseViolationError';
  }
}

export function validateForkLicense(
  parentLicense: JamboxLicense,
  childLicense: JamboxLicense,
): void {
  const parentLevel = LICENSE_LEVEL[parentLicense];
  const childLevel  = LICENSE_LEVEL[childLicense];
  if (childLevel > parentLevel) {
    throw new LicenseViolationError(parentLicense, childLicense);
  }
}

export function permittedForkLicenses(parentLicense: JamboxLicense): JamboxLicense[] {
  const maxLevel = LICENSE_LEVEL[parentLicense];
  return (Object.entries(LICENSE_LEVEL) as Array<[JamboxLicense, number]>)
    .filter(([, level]) => level <= maxLevel)
    .map(([lic]) => lic);
}

export interface ForkOptions {
  ownerIdentity: string;
  room: string;
  license?: JamboxLicense;
}

export interface ForkResult<TPayload> {
  forked: JamboxSemanticObject<TPayload>;
  appliedLicense: JamboxLicense;
}

export function forkObject<TPayload>(
  original: JamboxSemanticObject<TPayload>,
  options: ForkOptions,
): ForkResult<TPayload> {
  const parentLicense = (original.header.commercial?.license ?? 'personal') as JamboxLicense;
  const requestedLicense = options.license ?? parentLicense;

  validateForkLicense(parentLicense, requestedLicense);

  const forkedId = semanticObjectId(
    original.header.objectType as JamboxObjectKind,
    options.ownerIdentity,
    `${options.room}-fork-${slug(original.id)}-${Date.now()}`,
  );

  const now = Date.now();

  const forkedHeader: SemanticObjectHeader = {
    version: 1,
    objectType: original.header.objectType,
    semanticPath: `${original.header.semanticPath}/fork`,
    linearity: original.header.linearity,
    ownerIdentity: options.ownerIdentity,
    parents: [original.id, ...original.header.parents],
    commercial: {
      listed: false,
      license: requestedLicense,
      royaltyBps: original.header.commercial?.royaltyBps,
    },
    createdAt: now,
  };

  const forkedPayload: TPayload = JSON.parse(JSON.stringify(original.payload)) as TPayload;

  const forked: JamboxSemanticObject<TPayload> = {
    id: forkedId,
    header: forkedHeader,
    payload: forkedPayload,
  };

  return { forked, appliedLicense: requestedLicense };
}

function slug(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '') || 'object';
}

```
