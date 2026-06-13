---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar/validators/capabilities.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.923299+00:00
---

# core/protocol-types/src/grammar/validators/capabilities.ts

```ts
/**
 * Capability section validator.
 *
 * Validates `grammar.capabilities[]` — the list of system capabilities
 * the extension declares it needs (network.outbound, storage.write, …).
 * Each capability entry has an id, a human-readable reason, and a
 * `required` flag.
 *
 * Pure: takes a grammar object + collector, pushes errors, returns.
 */

import type { CapabilityId } from '../../extension-grammar';
import { VALID_CAPABILITY_IDS } from '../constants';
import {
  ValidationErrorCollector,
  requireString,
} from '../error-collector';

/** Top-level dispatcher for the capabilities section. */
export function validateCapabilitiesSection(
  g: Record<string, unknown>,
  errors: ValidationErrorCollector,
): void {
  if (!Array.isArray(g.capabilities)) {
    errors.push({ field: 'capabilities', message: 'capabilities must be an array' });
    return;
  }
  for (let i = 0; i < g.capabilities.length; i++) {
    validateCapability(
      g.capabilities[i] as Record<string, unknown>,
      errors.withPath('capabilities').withPath(i),
    );
  }
}

function validateCapability(
  cap: Record<string, unknown>,
  errors: ValidationErrorCollector,
): void {
  if (!cap || typeof cap !== 'object') {
    errors.push({ message: 'capability must be an object' });
    return;
  }

  if (
    typeof cap.capability !== 'string' ||
    !VALID_CAPABILITY_IDS.has(cap.capability as CapabilityId)
  ) {
    errors.push({
      field: 'capability',
      message: `Invalid capability "${cap.capability}". Must be one of: ${[...VALID_CAPABILITY_IDS].join(', ')}`,
    });
  }

  requireString(cap, 'reason', errors);

  if (typeof cap.required !== 'boolean') {
    errors.push({ field: 'required', message: 'required must be a boolean' });
  }
}

```
