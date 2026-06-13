---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/governance/version-compat.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.457769+00:00
---

# packages/extraction/src/governance/version-compat.ts

```ts
/**
 * Version compatibility matrix — checks if a ConsumerBinding is compatible
 * with its ExtensionManifest.
 *
 * Called before extraction pipeline starts. Red status blocks extraction.
 *
 * Status codes:
 *   green  — compatible, latest available
 *   yellow — compatible but update available
 *   red    — incompatible or deprecated; extraction blocked (incompatible) or warned (deprecated)
 *
 * Cross-references:
 *   governance.ts          → GovernedConsumerBinding, CompatibilityResult
 *   extension-manifest.ts  → ExtensionManifest
 *   extension-grammar.ts   → MigrationRule
 */

import type { ExtensionManifest } from '@semantos/protocol-types';
import type {
  GovernedConsumerBinding,
  CompatibilityResult,
} from '@semantos/protocol-types';

/**
 * Check if a ConsumerBinding is compatible with its ExtensionManifest.
 *
 * @param binding - The governed consumer binding
 * @param manifest - The extension manifest to check against
 * @returns CompatibilityResult with status and migration info
 */
export function checkCompatibility(
  binding: GovernedConsumerBinding,
  manifest: ExtensionManifest,
): CompatibilityResult {
  const consumerPin = binding.payload.grammarVersionPinned;
  const manifestVersion = manifest.grammar?.grammarVersion ?? manifest.version;
  const availableVersions = [manifestVersion]; // In practice, manifest tracks all published versions

  // 1. Check if manifest is deprecated
  if (manifest.deprecationStatus?.isDeprecated) {
    return {
      compatible: false,
      status: 'red',
      manifestVersion,
      consumerVersionPin: consumerPin,
      availableVersions,
      message: `Extension is deprecated${manifest.deprecationStatus.sunsetDate ? ` (sunset: ${manifest.deprecationStatus.sunsetDate})` : ''}. ${manifest.deprecationStatus.migrationNotes ?? 'No migration notes available.'}`,
    };
  }

  // 2. Check if the pinned version is compatible with the manifest version
  const pinCompatible = isVersionCompatible(consumerPin, manifestVersion);

  if (!pinCompatible) {
    // Check for migration path
    const migrationRules = manifest.grammar?.migrations ?? [];
    const migrationPath = findMigrationPath(consumerPin, manifestVersion, migrationRules);

    if (migrationPath) {
      return {
        compatible: false,
        status: 'red',
        manifestVersion,
        consumerVersionPin: consumerPin,
        availableVersions,
        migrationPath: {
          fromVersion: consumerPin.replace(/^[\^~]/, ''),
          toVersion: manifestVersion,
          migrationRules: migrationPath,
        },
        message: `Version '${consumerPin}' is incompatible with manifest version ${manifestVersion}. Migration path available.`,
      };
    }

    return {
      compatible: false,
      status: 'red',
      manifestVersion,
      consumerVersionPin: consumerPin,
      availableVersions,
      message: `Version '${consumerPin}' is no longer available or supported. Update to ${manifestVersion}.`,
    };
  }

  // 3. Check if there's an update available
  const exactPin = consumerPin.replace(/^[\^~]/, '');
  if (exactPin !== manifestVersion && isOlderVersion(exactPin, manifestVersion)) {
    return {
      compatible: true,
      status: 'yellow',
      manifestVersion,
      consumerVersionPin: consumerPin,
      availableVersions,
      message: `Update available: ${exactPin} → ${manifestVersion}. Your binding is stable.`,
    };
  }

  // 4. Fully compatible
  return {
    compatible: true,
    status: 'green',
    manifestVersion,
    consumerVersionPin: consumerPin,
    availableVersions,
    message: `Compatible. Running version ${manifestVersion}.`,
  };
}

/**
 * Check if a version pin is compatible with a target version.
 * Supports ^, ~, and exact version pins.
 */
function isVersionCompatible(pin: string, target: string): boolean {
  if (pin.startsWith('^')) {
    // Caret range: same major version
    const pinBase = pin.slice(1);
    return parseMajor(pinBase) === parseMajor(target);
  }

  if (pin.startsWith('~')) {
    // Tilde range: same major.minor
    const pinBase = pin.slice(1);
    return (
      parseMajor(pinBase) === parseMajor(target) &&
      parseMinor(pinBase) === parseMinor(target)
    );
  }

  // Exact version: must match or be satisfied by the target
  return parseMajor(pin) === parseMajor(target);
}

/**
 * Check if version A is older than version B.
 */
function isOlderVersion(a: string, b: string): boolean {
  const aParts = a.split('.').map(Number);
  const bParts = b.split('.').map(Number);

  for (let i = 0; i < 3; i++) {
    const av = aParts[i] ?? 0;
    const bv = bParts[i] ?? 0;
    if (av < bv) return true;
    if (av > bv) return false;
  }
  return false;
}

/**
 * Find migration rules between two versions.
 */
function findMigrationPath(
  from: string,
  to: string,
  rules: Array<{ fromVersion: string; toVersion: string } & Record<string, unknown>>,
): typeof rules | null {
  const fromClean = from.replace(/^[\^~]/, '');
  const applicable = rules.filter(
    r => r.fromVersion === fromClean && r.toVersion === to,
  );
  return applicable.length > 0 ? applicable : null;
}

function parseMajor(v: string): number {
  return parseInt(v.split('.')[0] ?? '0', 10);
}

function parseMinor(v: string): number {
  return parseInt(v.split('.')[1] ?? '0', 10);
}

```
