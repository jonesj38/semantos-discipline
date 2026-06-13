---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/release/lib/manifest.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.560532+00:00
---

# tools/release/lib/manifest.ts

```ts
/**
 * Manifest assembly — given a ReleaseConfig and a set of file bytes,
 * produce a ReleaseManifest. The CLI in bin/build.ts is a thin wrapper
 * over assembleManifest.
 */

import { execSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';

import { sha256Hex } from './contentstore';
import type { ReleaseConfig, ReleaseManifest } from './types';

function readZigVersion(): string {
  try {
    return execSync('zig version').toString().trim();
  } catch {
    return '';
  }
}

function gitRev(cwd: string): string {
  try {
    return execSync('git rev-parse HEAD', { cwd }).toString().trim();
  } catch {
    return '';
  }
}

export interface AssembleOptions {
  /** Package root — paths in the config are resolved relative to this. */
  packageRoot: string;
}

export function assembleManifest(
  cfg: ReleaseConfig,
  opts: AssembleOptions,
): ReleaseManifest {
  const root = opts.packageRoot;
  const artifacts: ReleaseManifest['artifacts'] = {};
  for (const a of cfg.artifacts) {
    const abs = path.join(root, a.path);
    if (!existsSync(abs)) {
      throw new Error(
        `artifact missing: ${abs}\n  ${cfg.name} expected ${a.name} (${a.target})`,
      );
    }
    const bytes = new Uint8Array(readFileSync(abs));
    artifacts[a.name] = {
      name: a.name,
      target: a.target,
      sizeBytes: bytes.length,
      sha256: sha256Hex(bytes),
    };
  }

  let spec: ReleaseManifest['spec'];
  if (cfg.spec) {
    const abs = path.join(root, cfg.spec.path);
    if (!existsSync(abs)) throw new Error(`spec missing: ${abs}`);
    const bytes = new Uint8Array(readFileSync(abs));
    spec = {
      schema: cfg.spec.schema,
      sha256: sha256Hex(bytes),
      sizeBytes: bytes.length,
    };
  }

  let primer: ReleaseManifest['primer'];
  if (cfg.primer) {
    const abs = path.join(root, cfg.primer.path);
    if (!existsSync(abs)) throw new Error(`primer missing: ${abs}`);
    const bytes = new Uint8Array(readFileSync(abs));
    primer = { sha256: sha256Hex(bytes), sizeBytes: bytes.length };
  }

  return {
    schema: 'release.kernel.v1',
    name: cfg.name,
    version: cfg.version,
    description: cfg.description ?? `${cfg.name} kernel/lib release`,
    artifacts,
    spec,
    primer,
    build: {
      zigVersion: readZigVersion(),
      sourceCommit: gitRev(root),
      builtAt: new Date().toISOString(),
    },
    dependencies: cfg.dependencies ?? [],
    hat: cfg.hat,
    parentReleaseHash: '',
  };
}

export interface ConfigPaths {
  /** Absolute path to the resolved config file. */
  configPath: string;
  /** Absolute path to the package root (= dirname of config). */
  packageRoot: string;
}

/** Load a release.config.ts file and resolve absolute paths. */
export async function loadConfig(configArg: string): Promise<{
  config: ReleaseConfig;
  paths: ConfigPaths;
}> {
  const configPath = path.resolve(configArg);
  if (!existsSync(configPath)) throw new Error(`config not found: ${configPath}`);
  const mod = await import(configPath);
  const config = (mod.default ?? mod) as ReleaseConfig;
  if (!config?.name || !config?.room) {
    throw new Error(`invalid release config: ${configPath} (missing name/room)`);
  }
  return {
    config,
    paths: { configPath, packageRoot: path.dirname(configPath) },
  };
}

```
