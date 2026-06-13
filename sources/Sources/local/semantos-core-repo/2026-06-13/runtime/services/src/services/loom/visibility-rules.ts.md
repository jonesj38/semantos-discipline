---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/visibility-rules.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.104528+00:00
---

# runtime/services/src/services/loom/visibility-rules.ts

```ts
/**
 * Pure visibility-transition rules for loom objects.
 *
 * `validateVisibilityTransition` decides whether an object may move from
 * its current `visibility` to `newVisibility`, given the actor's
 * capabilities and the object's type definition. It returns either a
 * machine-friendly OK result (with any cascade transitions the caller
 * must dispatch — e.g. AFFINE → RELEVANT linearity bump on publish) or a
 * failure result with a human-readable reason.
 *
 * Pure: no `this`, no I/O, no service calls — same input always yields
 * the same result.
 */

import type { LoomObject } from '../../types/loom';

export type VisibilityState = 'draft' | 'published' | 'revoked';

/** Linearity tier (matches CellHeader.linearity). */
export const LINEARITY_LINEAR = 1;
export const LINEARITY_AFFINE = 2;
export const LINEARITY_RELEVANT = 3;

/** Result of validating a visibility transition. */
export type VisibilityTransitionResult =
  | { ok: true; transitions: { newLinearity?: number } }
  | { ok: false; reason: string };

/**
 * Check whether `obj` may transition from its current visibility to
 * `newVisibility`, returning any cascade transitions the caller must
 * dispatch alongside `TRANSITION_VISIBILITY` itself.
 */
export function validateVisibilityTransition(
  obj: LoomObject,
  newVisibility: VisibilityState,
  hatCapabilities?: number[],
): VisibilityTransitionResult {
  const visConfig = obj.typeDefinition.visibility;

  if (!visConfig) {
    return {
      ok: false,
      reason: `Type "${obj.typeDefinition.name}" does not support visibility transitions`,
    };
  }

  if (!visConfig.states.includes(newVisibility)) {
    return {
      ok: false,
      reason: `Visibility state "${newVisibility}" not allowed for type "${obj.typeDefinition.name}"`,
    };
  }

  const currentVis = obj.visibility;
  const linearity = obj.header.linearity;

  if (newVisibility === 'published') {
    if (currentVis !== 'draft') {
      return {
        ok: false,
        reason: `Can only publish from draft state (current: ${currentVis})`,
      };
    }
    if (linearity === LINEARITY_LINEAR) {
      return { ok: false, reason: 'LINEAR objects cannot be published' };
    }
    if (visConfig.publishTransition) {
      if (linearity !== LINEARITY_AFFINE) {
        return {
          ok: false,
          reason: `Publish requires AFFINE linearity (current linearity: ${linearity})`,
        };
      }
      const required = visConfig.publishTransition.requiredCapabilities ?? [];
      if (required.length > 0) {
        if (!hatCapabilities) {
          return {
            ok: false,
            reason: 'Capabilities required for publish but none provided',
          };
        }
        const missing = required.filter(c => !hatCapabilities.includes(c));
        if (missing.length > 0) {
          return {
            ok: false,
            reason: `Missing required capabilities for publish: ${missing.join(', ')}`,
          };
        }
      }
      return { ok: true, transitions: { newLinearity: LINEARITY_RELEVANT } };
    }
    return { ok: true, transitions: {} };
  }

  if (newVisibility === 'revoked') {
    if (currentVis !== 'published') {
      return {
        ok: false,
        reason: `Can only revoke from published state (current: ${currentVis})`,
      };
    }
    return { ok: true, transitions: {} };
  }

  // newVisibility === 'draft'
  if (currentVis !== 'draft') {
    return { ok: false, reason: 'Cannot transition back to draft' };
  }
  return { ok: true, transitions: {} };
}

```
