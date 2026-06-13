---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/hat-scoping.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.522991+00:00
---

# cartridges/oddjobz/brain/src/conversation/hat-scoping.ts

```ts
/**
 * D-O7 — hat-scoping (cryptographic, not filtered).
 *
 * Origin: this module is a port-with-fix of OJT's `buildOjtHat()` from
 * `oddjobtodd/src/lib/services/ojtHandleMessage.ts` (lines 222–234).
 * The OJT version was a TODO-laden stub:
 *
 *     return {
 *       hatId: `ojt-hat:${identity.facetId}`,
 *       facetId: identity.facetId,
 *       certId: identity.certId ?? null,
 *       capabilities: [],          // ← TODO
 *       extensionId: 'ojt',
 *       domainFlag: 0,             // ← TODO
 *       maxTrustClass: 'interpretive',
 *     };
 *
 * The empty `capabilities` and zero `domainFlag` are precisely the
 * reason hat-boundary leakage was a real failure mode in OJT (see
 * D-O7-OJT-SALVAGE-REPORT.md Finding 1). Filtering at the application
 * layer is structurally insufficient — a missing filter is a silent
 * leak.
 *
 * The K3 fix: the hat's `contextTag` (uint8, 0..255) is threaded
 * through to cap-mint time so each hat's cap UTXO has a different
 * BKDS-derived child key. A presenter holding the wrong hat's child
 * key cannot satisfy the cap's cryptographic spend gate, EVEN IF
 * the application layer's filter is wrong. The proof is
 * `oddjobz_cap_isolation_cryptographic` in
 * `proofs/lean/Semantos/Capabilities/Oddjobz.lean` line 283 (PR #279):
 * BKDS injectivity-in-context_tag means
 * `bkdsDerive(parent, cp, mkInvoice t1 label).2 ≠
 *  bkdsDerive(parent, cp, mkInvoice t2 label).2` whenever `t1 ≠ t2`.
 *
 * This module exposes:
 *
 *   - `OddjobzHat` — the typed hat context, carrying contextTag +
 *     declared capabilities (NOT empty by default) + extensionId.
 *   - `buildHat()` — builder that picks the right cap holder set
 *     (`OPERATOR_ROOT_CAPS` or `NODE_SERVICE_CAPS`) for the principal
 *     kind.
 *   - `assertHatScopedCap()` — verifies a presented cap UTXO's
 *     contextTag matches the hat's contextTag at the gate seam, with
 *     a doc comment pointing at the K3 theorem.
 *
 * The application layer (the conversation state-manager) consumes
 * `OddjobzHat` and threads it through to cap-presentation. The kernel
 * gate (D-O4 `kernel-gate.ts`) consumes the cap UTXO and runs
 * OP_CHECKDOMAINFLAG; the cryptographic check sits underneath that
 * (BKDS-derived child key satisfies the spend gate iff the hats match).
 *
 * The naming intentionally avoids "filter" — there is NO filter here.
 * The hat's contextTag IS the gate.
 */

import {
  OPERATOR_ROOT_CAPS,
  NODE_SERVICE_CAPS,
  type OddjobzCapability,
  type OddjobzCapName,
} from '../capabilities.js';
import type {
  PresentedCap,
  Result,
  KernelGateFailure,
  SigningPrincipal,
} from '../state-machines/kernel-gate.js';
import { ok, err, presentedFlag } from '../state-machines/kernel-gate.js';

/* ══════════════════════════════════════════════════════════════════════
 * Hat context type
 * ══════════════════════════════════════════════════════════════════════ */

/**
 * An oddjobz hat. Authoring identity for one persona of the operator.
 * The same physical operator may hold multiple hats (carpenter,
 * musician, RE-property-manager, …); each hat has a distinct
 * `contextTag` so its cap UTXOs are cryptographically isolated.
 *
 * Fields:
 *   - `hatId`        operator-readable slug (carpenter | musician).
 *   - `contextTag`   uint8 in [0, 255] — the BKDS context tag the
 *                    hat's caps are minted under. Threaded into
 *                    `mintCapabilityCell(cap, contextTag, ownerId)`.
 *   - `principal`    operator | service. Drives which cap set the
 *                    hat carries by default.
 *   - `capabilities` declared cap names this hat presents. NOT empty
 *                    by default; the OJT TODO is fixed here. The
 *                    operator-hat default is the full
 *                    OPERATOR_ROOT_CAPS set; service-hat default is
 *                    NODE_SERVICE_CAPS.
 *   - `extensionId`  "oddjobz" — for routing / audit.
 *   - `facetId`      stable cert-derived facet id (opaque).
 *   - `certId`       cert id (when known) for D-O5p child-cert flows.
 */
export interface OddjobzHat {
  readonly hatId: string;
  readonly contextTag: number;
  readonly principal: SigningPrincipal;
  readonly capabilities: readonly OddjobzCapName[];
  readonly extensionId: 'oddjobz';
  readonly facetId: string;
  readonly certId: string | null;
}

/** Input for `buildHat`. */
export interface BuildHatInput {
  readonly hatId: string;
  readonly contextTag: number;
  readonly principal: SigningPrincipal;
  readonly facetId: string;
  readonly certId?: string | null;
  /** Override the default cap set for this principal. Useful when
   *  D-O5p has constrained the hat to a strict subset of the operator
   *  caps (e.g. a phone child cert without invoice/close). */
  readonly capabilities?: readonly OddjobzCapName[];
}

/**
 * Build a `OddjobzHat`. Defaults:
 *   - `capabilities` from `OPERATOR_ROOT_CAPS` if `principal === 'operator'`,
 *      from `NODE_SERVICE_CAPS` if `principal === 'service'`.
 *   - `certId` defaults to null (no child cert).
 *
 * Throws if `contextTag` is out of the uint8 range. (BKDS context tag
 * is one byte per the protocol-v0.5 spec; out-of-range here would
 * silently truncate at the cap-mint seam, which we reject loudly.)
 */
export function buildHat(input: BuildHatInput): OddjobzHat {
  if (
    !Number.isInteger(input.contextTag) ||
    input.contextTag < 0 ||
    input.contextTag > 0xff
  ) {
    throw new Error(
      `buildHat: contextTag must be uint8 in [0,255] — got ${input.contextTag}`,
    );
  }
  const defaultCaps =
    input.principal === 'operator' ? OPERATOR_ROOT_CAPS : NODE_SERVICE_CAPS;
  const caps =
    input.capabilities !== undefined
      ? input.capabilities
      : defaultCaps.map((c) => c.name);
  return {
    hatId: input.hatId,
    contextTag: input.contextTag & 0xff,
    principal: input.principal,
    capabilities: Object.freeze([...caps]),
    extensionId: 'oddjobz',
    facetId: input.facetId,
    certId: input.certId ?? null,
  };
}

/* ══════════════════════════════════════════════════════════════════════
 * Hat-isolation gate seam
 * ══════════════════════════════════════════════════════════════════════ */

/**
 * Failure shape for a hat-scoped cap presentation. Distinguishes
 * "wrong hat" (contextTag mismatch) from the existing kernel-gate
 * `wrong_cap` failure, since the operator surface needs to render a
 * different message ("you presented carpenter's cap from the
 * musician hat" vs "wrong cap"). The kernel-gate failure remains the
 * canonical wire shape — `assertHatScopedCap` returns it on flag
 * mismatch as well, after checking the contextTag.
 */
export interface HatScopeFailure extends KernelGateFailure {
  readonly hatScope?: {
    readonly expectedContextTag: number;
    readonly presentedContextTag: number;
  };
}

/**
 * Read the contextTag from a presented cap UTXO.
 *
 * For `kind: 'cell'` presentations the contextTag is at owner_id byte
 * 0 (header offset 62 per the cap-cell layout — see
 * `cartridges/oddjobz/brain/src/capabilities.ts` line ~457). For `kind:
 * 'structural'` presentations the contextTag is supplied alongside
 * the structural shape via `presentedContextTag`; if not supplied,
 * the contextTag is taken as 0 (the default contextTag for legacy
 * single-hat operators, which matches what
 * `mintCapabilityCell(cap, 0, ownerId)` produces).
 */
export function presentedContextTag(
  cap: PresentedCap,
  hint?: number,
): number {
  if (cap.kind === 'cell') {
    // Header offset 62, byte 0 of the 16-byte owner_id field — which
    // is where mintCapabilityCell(cap, contextTag, ownerId) writes
    // the contextTag byte. This mirrors readDomainFlag's offset
    // pattern.
    if (cap.cell.length < 63) {
      // Cell too short to carry a contextTag — treat as zero.
      return 0;
    }
    return cap.cell[62] ?? 0;
  }
  // Structural presentation — caller supplies the hint.
  if (hint !== undefined) {
    return hint & 0xff;
  }
  return 0;
}

/**
 * Verify a cap presentation's contextTag matches the hat's
 * contextTag. This is the K3 cryptographic-isolation gate at the
 * application layer: the actual cryptographic check happens at the
 * cell-engine layer (BKDS-derived child key satisfying the spend
 * gate); this function is the typed predicate the conversation
 * state-manager calls before dispatching a patch.
 *
 * On structural presentations, the caller supplies the contextTag
 * via `presentedContextTagHint`. On cell presentations, the
 * contextTag is read from the cap-cell bytes.
 *
 * Returns:
 *   - `ok(true)` if the contextTags match.
 *   - `err({ kind: 'wrong_cap', hatScope: {...} })` if they differ.
 *
 * Reference: `oddjobz_cap_isolation_cryptographic` in
 * `proofs/lean/Semantos/Capabilities/Oddjobz.lean` line 283 (PR #279).
 */
export function assertHatScopedCap(
  hat: OddjobzHat,
  presented: PresentedCap,
  presentedContextTagHint?: number,
): Result<true, HatScopeFailure> {
  const present = presentedContextTag(presented, presentedContextTagHint);
  if (present !== hat.contextTag) {
    return err({
      kind: 'wrong_cap',
      message:
        `cap presented under contextTag 0x${present.toString(16).padStart(2, '0')} ` +
        `but hat ${hat.hatId} requires 0x${hat.contextTag.toString(16).padStart(2, '0')}; ` +
        'cryptographic spend gate would reject ' +
        '(see oddjobz_cap_isolation_cryptographic, PR #279).',
      presentedDomainFlag: presentedFlag(presented),
      hatScope: {
        expectedContextTag: hat.contextTag,
        presentedContextTag: present,
      },
    });
  }
  return ok(true);
}

/**
 * Gate predicate: does this hat carry the named cap in its declared
 * capability set? This is the "cap is in scope" check distinct from
 * "cap presentation is hat-scoped". Both gates must pass for a
 * transition to fire under this hat.
 */
export function hatCarriesCap(
  hat: OddjobzHat,
  capName: OddjobzCapName,
): boolean {
  return hat.capabilities.includes(capName);
}

/* ══════════════════════════════════════════════════════════════════════
 * Hat selection from cell-presented authoring identity
 * ══════════════════════════════════════════════════════════════════════ */

/**
 * Given a presented cap UTXO, infer which hat is authoring. The hat's
 * contextTag IS the cap's contextTag — there is no separate
 * registry lookup. The caller passes the set of registered hats; the
 * function picks the one whose contextTag matches. Returns null if no
 * hat in the set matches (which is a hard error at the gate seam —
 * the cap was minted under a contextTag this operator doesn't
 * recognise).
 */
export function selectHatForCap(
  hats: readonly OddjobzHat[],
  presented: PresentedCap,
  presentedContextTagHint?: number,
): OddjobzHat | null {
  const ct = presentedContextTag(presented, presentedContextTagHint);
  for (const h of hats) {
    if (h.contextTag === ct) return h;
  }
  return null;
}

/**
 * Convenience: are these two hats the SAME hat? Equality is by
 * (hatId, contextTag, facetId) tuple — sufficient to identify a hat
 * uniquely within an operator's identity. The principal kind isn't
 * compared because a single operator can in principle hold both
 * operator and service hats under different contextTags.
 */
export function sameHat(a: OddjobzHat, b: OddjobzHat): boolean {
  return (
    a.hatId === b.hatId &&
    a.contextTag === b.contextTag &&
    a.facetId === b.facetId
  );
}

/* ══════════════════════════════════════════════════════════════════════
 * Built-in hat slots
 *
 * These are the canonical contextTag assignments for the carpenter +
 * musician motivating example from BRAIN-DISPATCHER-UNIFICATION.md §2.5.
 * Operators add new hats by picking new contextTag bytes; 0x00 is the
 * default single-hat operator (the OJT-default behaviour) so it is
 * NOT taken by the carpenter assignment — carpenter gets 0x01 so the
 * default-zero-contextTag legacy still resolves to "no hat" rather
 * than masquerading as carpenter.
 * ══════════════════════════════════════════════════════════════════════ */

/** ContextTag for the legacy single-hat operator default. Caps minted
 *  with `mintCapabilityCell(cap, 0, ownerId)` (the OJT-equivalent
 *  default) all sit under this tag. Used as the fallback when no hat
 *  is named explicitly. */
export const DEFAULT_HAT_CONTEXT_TAG = 0x00;

/** ContextTag for the carpenter hat per BRAIN-DISPATCHER-UNIFICATION.md
 *  §2.5 motivating example. */
export const CARPENTER_CONTEXT_TAG = 0x01;

/** ContextTag for the musician hat per the same example. */
export const MUSICIAN_CONTEXT_TAG = 0x02;

```
