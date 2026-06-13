---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/release/lib/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.559992+00:00
---

# tools/release/lib/types.ts

```ts
/**
 * Release-pipeline types. The wire-shape `SerializedCell` is sourced
 * from @semantos/cell-relay (single source of truth for the
 * cell-relay protocol). Release-specific types — `ReleaseConfig`
 * (package-author surface) and `ReleaseManifest` (what ends up as the
 * cell payload) — are defined here.
 */

export type { SerializedCell } from '../../../packages/cell-relay/src';

export interface ArtifactConfig {
  /** Filename written into the manifest, e.g. "pask.wasm". */
  name: string;
  /** Target string, e.g. "wasm32-freestanding". Free-form. */
  target: string;
  /** Path relative to the package root. */
  path: string;
}

export interface ReleaseConfig {
  /** Package name. e.g. "pask", "cell-engine", "protocol-types". */
  name: string;
  /** Cell DAG room for this package. Convention: release.<kind>.<name>. */
  room: string;
  /** Maintainer hat — placeholder until BRC-52 cert + envelope wiring. */
  hat: string;
  /** Semver. Read from build.zig.zon, package.json, or hard-coded. */
  version: string;
  /** Build artifacts to include. */
  artifacts: ArtifactConfig[];
  /** Optional machine-derived spec (e.g. pask-spec.json). */
  spec?: { schema: string; path: string };
  /** Optional hand-written primer doc (PRIMER.md). */
  primer?: { path: string };
  /** Cross-package deps. Each entry pins a release stateHash. */
  dependencies?: Array<{ name: string; release: string }>;
  /** Free-form description. Falls back to "<name> kernel/lib release". */
  description?: string;
}

/** What ends up in the cell payload. */
export interface ReleaseManifest {
  schema: 'release.kernel.v1';
  name: string;
  version: string;
  description: string;
  artifacts: Record<
    string,
    { name: string; target: string; sizeBytes: number; sha256: string }
  >;
  spec?: { schema: string; sha256: string; sizeBytes: number };
  primer?: { sha256: string; sizeBytes: number };
  build: { zigVersion: string; sourceCommit: string; builtAt: string };
  dependencies: Array<{ name: string; release: string }>;
  hat: string;
  parentReleaseHash: string;
}

export const RELEASE_OP = 'release.kernel.publish' as const;

```
