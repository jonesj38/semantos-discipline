---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/experience-cartridge/src/manifest-loader.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.951147+00:00
---

# core/experience-cartridge/src/manifest-loader.ts

```ts
/**
 * Manifest-driven cartridge loader (T2.a).
 *
 * Reads a cartridge's `cartridge.json` from disk, validates its
 * `cellTypes[]` array against the unified shape (D11), computes the
 * canonical 32-byte typeHash for each entry via the kernel
 * `buildTypeHash` primitive, and returns a `LoadedCartridge` with the
 * cell types fully resolved.
 *
 * The typeHash is **never** present in the manifest — it is always
 * derived from the triple at load time.  This prevents drift between
 * declared triple and serialised hash; see decision record §3.2.
 *
 * Spec:    docs/design/STRUCTURED-TYPEHASH-CANONICAL.md
 * Tracker: docs/STRUCTURED-TYPEHASH-TRACKER.md  (T2.a)
 */

import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { buildTypeHash, typeHashToHex } from '@semantos/protocol-types';
import { loadCartridge } from './loader.js';
import {
  CartridgeRegistrationError,
  type CartridgeManifestShape,
  type CellTypeManifestEntry,
  type CellTypeManifestTriple,
  type CellTypeRegistryEntry,
  type LoadedCartridge,
  type ManifestLinearity,
} from './types.js';

/** Valid linearity strings — mirrors `LinearityType` in the kernel. */
const VALID_LINEARITIES: ReadonlySet<ManifestLinearity> = new Set([
  'LINEAR',
  'AFFINE',
  'PERSISTENT',
  'RELEVANT',
  'DEBUG',
]);

/**
 * Read a cartridge's manifest file from disk and produce a
 * `LoadedCartridge` with `cellTypes` fully resolved.
 *
 * @param cartridgePath — absolute or process-relative path to the
 *   cartridge directory (the one containing `cartridge.json`).
 *   Example: `/abs/path/to/cartridges/oddjobz`.
 */
export async function loadCartridgeFromManifest(
  cartridgePath: string,
): Promise<LoadedCartridge> {
  const manifestPath = join(cartridgePath, 'cartridge.json');
  const raw = await readFile(manifestPath, 'utf-8');
  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch (err) {
    throw new CartridgeRegistrationError({
      code: 'INVALID_MANIFEST',
      cartridgeId: '<unknown>',
      attempted: manifestPath,
      message: `cartridge.json at ${manifestPath} is not valid JSON: ${err instanceof Error ? err.message : String(err)}`,
    });
  }

  const manifest = validateManifestHeader(json, manifestPath);
  const cellTypesRaw = (json as { cellTypes?: unknown }).cellTypes;
  const cellTypes = resolveCellTypes(cellTypesRaw, manifest.id, manifestPath);

  return loadCartridge({
    manifest,
    cellTypes,
  });
}

/** Pluck and validate the {id, version, description} header. */
function validateManifestHeader(
  json: unknown,
  manifestPath: string,
): CartridgeManifestShape {
  if (typeof json !== 'object' || json === null) {
    throw new CartridgeRegistrationError({
      code: 'INVALID_MANIFEST',
      cartridgeId: '<unknown>',
      attempted: manifestPath,
      message: `cartridge.json at ${manifestPath} is not a JSON object`,
    });
  }
  const obj = json as Record<string, unknown>;
  const id = obj.id;
  const version = obj.version;
  const description = obj.description;
  if (typeof id !== 'string' || id.length === 0) {
    throw new CartridgeRegistrationError({
      code: 'INVALID_MANIFEST',
      cartridgeId: typeof id === 'string' ? id : '<unknown>',
      attempted: manifestPath,
      message: `cartridge.json at ${manifestPath} is missing a non-empty 'id' string`,
    });
  }
  if (typeof version !== 'string' || version.length === 0) {
    throw new CartridgeRegistrationError({
      code: 'INVALID_MANIFEST',
      cartridgeId: id,
      attempted: manifestPath,
      message: `cartridge.json at ${manifestPath} is missing a non-empty 'version' string`,
    });
  }
  if (typeof description !== 'string') {
    throw new CartridgeRegistrationError({
      code: 'INVALID_MANIFEST',
      cartridgeId: id,
      attempted: manifestPath,
      message: `cartridge.json at ${manifestPath} is missing a 'description' string`,
    });
  }
  return { id, version, description };
}

/**
 * Validate the `cellTypes[]` array and compute typeHashes.
 * Throws `DUPLICATE_TYPE_HASH` per Q3 design if two entries produce the
 * same hash within one cartridge.
 */
function resolveCellTypes(
  raw: unknown,
  cartridgeId: string,
  manifestPath: string,
): ReadonlyArray<CellTypeRegistryEntry> {
  if (raw === undefined || raw === null) return [];
  if (!Array.isArray(raw)) {
    throw new CartridgeRegistrationError({
      code: 'INVALID_MANIFEST',
      cartridgeId,
      attempted: manifestPath,
      message: `cartridge.json '${cartridgeId}' has non-array 'cellTypes' field`,
    });
  }

  const seen = new Map<string, string>(); // typeHashHex → name (first wins)
  const out: CellTypeRegistryEntry[] = [];

  for (let i = 0; i < raw.length; i++) {
    const entry = validateCellTypeEntry(raw[i], i, cartridgeId, manifestPath);
    const typeHash = buildTypeHash(
      entry.triple.segment1,
      entry.triple.segment2,
      entry.triple.segment3,
      entry.triple.segment4,
    );
    const typeHashHex = typeHashToHex(typeHash);
    const existingName = seen.get(typeHashHex);
    if (existingName !== undefined) {
      throw new CartridgeRegistrationError({
        code: 'DUPLICATE_TYPE_HASH',
        cartridgeId,
        existing: existingName,
        attempted: entry.name,
        message:
          `Cartridge '${cartridgeId}' cellTypes['${entry.name}'] produces typeHash ` +
          `${typeHashHex} which is already claimed by cellTypes['${existingName}']. ` +
          `Pick a different triple — typeHashes must be unique within a cartridge.`,
      });
    }
    seen.set(typeHashHex, entry.name);
    out.push({ manifest: entry, typeHash, typeHashHex });
  }

  return out;
}

function validateCellTypeEntry(
  raw: unknown,
  index: number,
  cartridgeId: string,
  manifestPath: string,
): CellTypeManifestEntry {
  if (typeof raw !== 'object' || raw === null) {
    throw new CartridgeRegistrationError({
      code: 'INVALID_MANIFEST',
      cartridgeId,
      attempted: `${manifestPath}#/cellTypes/${index}`,
      message: `Cartridge '${cartridgeId}' cellTypes[${index}] is not a JSON object`,
    });
  }
  const obj = raw as Record<string, unknown>;

  const name = obj.name;
  if (typeof name !== 'string' || name.length === 0) {
    throw new CartridgeRegistrationError({
      code: 'INVALID_MANIFEST',
      cartridgeId,
      attempted: `${manifestPath}#/cellTypes/${index}/name`,
      message: `Cartridge '${cartridgeId}' cellTypes[${index}] is missing a non-empty 'name' string`,
    });
  }

  const triple = validateTriple(obj.triple, name, cartridgeId, manifestPath, index);

  const linearity = obj.linearity;
  if (typeof linearity !== 'string' || !VALID_LINEARITIES.has(linearity as ManifestLinearity)) {
    throw new CartridgeRegistrationError({
      code: 'INVALID_MANIFEST',
      cartridgeId,
      attempted: `${manifestPath}#/cellTypes/${index}/linearity`,
      message:
        `Cartridge '${cartridgeId}' cellTypes['${name}'] has invalid linearity ` +
        `${JSON.stringify(linearity)} (expected one of ${[...VALID_LINEARITIES].join(', ')})`,
    });
  }

  // Optional UI fields — typed-loose pass-through; renderer validates
  // payloadSchema shape on its own terms.
  const entry: CellTypeManifestEntry = {
    name,
    triple,
    linearity: linearity as ManifestLinearity,
    ...(typeof obj.displayName === 'string' ? { displayName: obj.displayName } : {}),
    ...(typeof obj.primaryAnchor === 'boolean' ? { primaryAnchor: obj.primaryAnchor } : {}),
    ...(typeof obj.description === 'string' ? { description: obj.description } : {}),
    ...(obj.payloadSchema !== undefined && typeof obj.payloadSchema === 'object' && obj.payloadSchema !== null
      ? { payloadSchema: obj.payloadSchema as Record<string, unknown> }
      : {}),
    ...(Array.isArray(obj.phases) ? { phases: obj.phases.map(String) } : {}),
    ...(typeof obj.initialPhase === 'string' ? { initialPhase: obj.initialPhase } : {}),
  };
  return entry;
}

function validateTriple(
  raw: unknown,
  cellTypeName: string,
  cartridgeId: string,
  manifestPath: string,
  index: number,
): CellTypeManifestTriple {
  if (typeof raw !== 'object' || raw === null) {
    throw new CartridgeRegistrationError({
      code: 'INVALID_MANIFEST',
      cartridgeId,
      attempted: `${manifestPath}#/cellTypes/${index}/triple`,
      message: `Cartridge '${cartridgeId}' cellTypes['${cellTypeName}'] is missing 'triple' object`,
    });
  }
  const t = raw as Record<string, unknown>;
  const segs: (keyof CellTypeManifestTriple)[] = ['segment1', 'segment2', 'segment3', 'segment4'];
  for (const seg of segs) {
    if (typeof t[seg] !== 'string') {
      throw new CartridgeRegistrationError({
        code: 'INVALID_MANIFEST',
        cartridgeId,
        attempted: `${manifestPath}#/cellTypes/${index}/triple/${seg}`,
        message:
          `Cartridge '${cartridgeId}' cellTypes['${cellTypeName}'] triple.${seg} ` +
          `must be a string (got ${typeof t[seg]}). Use empty string "" for unused segments.`,
      });
    }
  }
  return {
    segment1: t.segment1 as string,
    segment2: t.segment2 as string,
    segment3: t.segment3 as string,
    segment4: t.segment4 as string,
  };
}

```
