---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/state-machines/kernel-gate.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.530598+00:00
---

# cartridges/oddjobz/brain/src/state-machines/kernel-gate.ts

```ts
/**
 * D-O4 — kernel-gate verifier stub used by the four FSM modules.
 *
 * The "real" K1/K2/K3/K4 enforcement happens in the cell-engine kernel
 * (`core/cell-engine/src/opcodes/plexus.zig` — OP_ASSERTLINEAR `0xC5`,
 * OP_CHECKDOMAINFLAG `0xC6`). At the TypeScript-FSM altitude we
 * **simulate** those gates so D-O4 can land in advance of D-O7's
 * substrate-truth cutover. Each FSM transition function calls the
 * helpers in this module which:
 *
 *   1. simulate `OP_ASSERTLINEAR` by tracking consumed cell ids in an
 *      in-memory `ConsumedCellSet` (K1 — a LINEAR cell may be consumed
 *      at most once);
 *   2. simulate `OP_CHECKDOMAINFLAG` by reading the cap-UTXO's domain
 *      flag (the same byte the kernel reads at header offset 24) and
 *      comparing against the transition's required cap (K2 / K3a —
 *      auth + cap soundness, domain isolation);
 *   3. surface failure-atomicity (K4) by returning a typed
 *      `KernelGateFailure` BEFORE any state mutation; on K4-induced
 *      external-call failure (the FSM transition calls a side effect
 *      that throws), the caller MUST roll back to the input cell — the
 *      `runWithFailureAtomic` helper enforces this contract for tests.
 *
 * The Lean side carries the substrate-level guarantees: `LinearityK1`
 * for (1), `AuthSoundnessK2` for (2), `FailureAtomicK4` for (3). Per-
 * FSM Lean files (`proofs/lean/Semantos/Extensions/Oddjobz/StateMachines
 * /*.lean`) specialise these into theorems whose statements mirror the
 * TS function returns line-for-line, so the TS layer is a thin
 * decision-table over a substrate that already enforces the invariants
 * cryptographically.
 *
 * Reference:
 *  - docs/design/ODDJOBZ-EXTENSION-PLAN.md §O4
 *  - core/cell-engine/src/opcodes/plexus.zig (`opAssertLinear`,
 *    `opCheckDomainFlag`)
 *  - proofs/lean/Semantos/Theorems/{LinearityK1,AuthSoundnessK2,
 *    FailureAtomicK4}.lean
 */

import {
  capabilityByName,
  readDomainFlag,
  type OddjobzCapName,
  type OddjobzCapability,
} from '../capabilities.js';

/* ══════════════════════════════════════════════════════════════════════
 * Result + failure types
 * ══════════════════════════════════════════════════════════════════════ */

/** Discriminated-union result type — the FSM transition functions
 *  never throw on policy violations; they return a typed `Result`. */
export type Result<T, E> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly error: E };

/** Convenience constructors. */
export function ok<T>(value: T): Result<T, never> {
  return { ok: true, value };
}
export function err<E>(error: E): Result<never, E> {
  return { ok: false, error };
}

/**
 * The signing principal kinds the §O4 transition table calls out.
 *
 *   - `operator` — a presented BRC-52 cert under the operator's root
 *     (or a child cert delegated under it via D-O5p). The transition
 *     table's "operator hat" rows accept either.
 *   - `service` — the node-daemon principal. Only the public-chat
 *     handler and the auto / clock-tick transitions use this.
 */
export type SigningPrincipal = 'operator' | 'service';

/**
 * Typed failure modes for a kernel-gated FSM transition. Each maps
 * to a kernel-gate predicate the substrate enforces:
 *
 *  - `cap_required`         — the transition needs a cap-UTXO and none was presented.
 *  - `wrong_cap`            — a cap was presented but its domain flag does not match the required cap (OP_CHECKDOMAINFLAG / K3a).
 *  - `cell_already_consumed` — the input cell-id has been consumed in a prior transition (OP_ASSERTLINEAR / K1).
 *  - `bad_signing_principal` — the transition was signed by the wrong principal kind (operator vs service mismatch per the §O4 table).
 *  - `invalid_state_transition` — the (from, to) pair is not in the FSM's transition table.
 *  - `from_state_mismatch`  — the input cell's current state ≠ the transition's `from` state.
 *  - `induced_io_failure`   — an external call (Stripe, Xero, SMS) threw mid-transition; cell unchanged (K4 surface).
 */
export type KernelGateFailureKind =
  | 'cap_required'
  | 'wrong_cap'
  | 'cell_already_consumed'
  | 'bad_signing_principal'
  | 'invalid_state_transition'
  | 'from_state_mismatch'
  | 'induced_io_failure';

export interface KernelGateFailure {
  readonly kind: KernelGateFailureKind;
  /** Human-readable summary for tests + audit logs. */
  readonly message: string;
  /** When `kind === 'cap_required'` or `'wrong_cap'`, the cap that
   *  the transition expected. */
  readonly expectedCap?: OddjobzCapName;
  /** When `kind === 'wrong_cap'`, the domain flag actually presented. */
  readonly presentedDomainFlag?: number;
  /** When `kind === 'bad_signing_principal'`, the principal expected. */
  readonly expectedPrincipal?: SigningPrincipal;
  /** When `kind === 'cell_already_consumed'`, the cell-id whose
   *  successor was already minted. */
  readonly consumedCellId?: string;
  /** When `kind === 'invalid_state_transition'` or
   *  `'from_state_mismatch'`, the (from, to) attempt. */
  readonly attempted?: { readonly from: string; readonly to: string };
}

/* ══════════════════════════════════════════════════════════════════════
 * ConsumedCellSet — in-memory K1 substrate stub
 * ══════════════════════════════════════════════════════════════════════ */

/**
 * The set of cell-ids that have already been consumed in a prior
 * transition. Each FSM call passes in (or threads through) one of
 * these to simulate `OP_ASSERTLINEAR`. In production this is replaced
 * by the cell-engine's UTXO-set lookup; the TS-layer FSM doesn't care
 * which backing the substrate uses — it only asks "is this cell-id
 * already consumed?" and surfaces `cell_already_consumed` if so.
 *
 * The set is **mutated** by the transition functions: a successful
 * transition records the input cell-id as consumed BEFORE returning
 * the successor cell. This is the same shape as the cell-engine's
 * own behaviour — OP_ASSERTLINEAR consumes the cell on the same
 * opcode that asserts linearity.
 */
export interface ConsumedCellSet {
  readonly has: (cellId: string) => boolean;
  readonly add: (cellId: string) => void;
  readonly snapshot: () => ReadonlySet<string>;
}

/** Build a fresh empty `ConsumedCellSet`. */
export function makeConsumedCellSet(): ConsumedCellSet {
  const s = new Set<string>();
  return Object.freeze({
    has: (cellId: string) => s.has(cellId),
    add: (cellId: string) => {
      s.add(cellId);
    },
    snapshot: () => new Set(s),
  });
}

/* ══════════════════════════════════════════════════════════════════════
 * Capability presentation + check
 * ══════════════════════════════════════════════════════════════════════ */

/**
 * The shape of a presented cap UTXO. Either a 1024-byte minted cell
 * (the production shape; `mintCapabilityCell` output) — in which case
 * the kernel-gate stub reads the domain flag from header offset 24
 * via `readDomainFlag` — or a structural object the test fixtures
 * use to skip the bytes round-trip. Both are accepted; the structural
 * shape is what most tests use.
 */
export type PresentedCap =
  | { readonly kind: 'cell'; readonly cell: Uint8Array }
  | { readonly kind: 'structural'; readonly domainFlag: number };

/** Read the presented domain flag, regardless of presentation kind. */
export function presentedFlag(cap: PresentedCap): number {
  if (cap.kind === 'cell') return readDomainFlag(cap.cell);
  return cap.domainFlag >>> 0;
}

/**
 * Simulate `OP_CHECKDOMAINFLAG` for a transition that requires `capName`.
 *
 *   - if `presented` is `null` AND the transition required a cap,
 *     return `cap_required` (kernel gate would have aborted earlier
 *     when the operator omitted the UTXO from the spend bundle);
 *   - otherwise compare `presentedFlag(presented)` against the
 *     declared `domainFlag` of `capName`. Mismatch returns `wrong_cap`
 *     with the offending flag attached. Match returns `ok`.
 *
 * The "cap-not-required and presented" case is benign per the kernel-
 * gate semantics — the gate checks only that the required cap is
 * present, not that no extra caps were presented. The tests assert
 * this lenient policy.
 */
export function checkDomainFlag(
  capName: OddjobzCapName,
  presented: PresentedCap | null,
): Result<true, KernelGateFailure> {
  const cap = capabilityByName[capName];
  if (cap === undefined) {
    return err({
      kind: 'wrong_cap',
      message: `unknown cap name: ${capName}`,
    });
  }
  if (presented === null) {
    return err({
      kind: 'cap_required',
      message: `transition requires ${capName} but no cap was presented`,
      expectedCap: capName,
    });
  }
  const flag = presentedFlag(presented);
  if ((flag >>> 0) !== (cap.domainFlag >>> 0)) {
    return err({
      kind: 'wrong_cap',
      message: `presented domain flag 0x${flag.toString(16).padStart(8, '0')} ≠ expected 0x${cap.domainFlag.toString(16).padStart(8, '0')} for ${capName}`,
      expectedCap: capName,
      presentedDomainFlag: flag,
    });
  }
  return ok(true);
}

/* ══════════════════════════════════════════════════════════════════════
 * OP_ASSERTLINEAR stub — K1 enforcement at the TS layer
 * ══════════════════════════════════════════════════════════════════════ */

/**
 * Simulate `OP_ASSERTLINEAR` for the input cell-id. If the cell has
 * already been consumed, return `cell_already_consumed`. Otherwise
 * `ok(true)` — does **not** itself add the cell to the consumed set;
 * the caller does that AFTER the transition is otherwise valid (so
 * a failed cap-check on a valid cell doesn't permanently retire it).
 */
export function assertLinear(
  consumed: ConsumedCellSet,
  cellId: string,
): Result<true, KernelGateFailure> {
  if (consumed.has(cellId)) {
    return err({
      kind: 'cell_already_consumed',
      message: `cell ${cellId} already consumed in a prior transition`,
      consumedCellId: cellId,
    });
  }
  return ok(true);
}

/* ══════════════════════════════════════════════════════════════════════
 * Failure-atomic side-effect runner — K4 surface at the TS layer
 * ══════════════════════════════════════════════════════════════════════ */

/**
 * Run a side-effect-bearing transition body atomically with respect
 * to the input cell. If the body throws (induced HTTP failure, etc.)
 * the function returns `induced_io_failure` AND the caller must
 * surface the input cell unchanged — the transition NEVER adds the
 * input cell-id to the consumed set if the body fails.
 *
 * This is the K4 (`FailureAtomicK4.lean`) contract at the TS altitude:
 * a failed external call leaves the cell byte-for-byte unchanged.
 * The Lean theorem proves the substrate enforces this; the helper
 * here surfaces it correctly so a retry succeeds.
 *
 * `body` is called ONLY if all the kernel-gate checks (state, cap,
 * linearity, principal) pass. The caller is responsible for those
 * checks first; this helper just wraps the I/O.
 */
export function runFailureAtomic<T>(
  body: () => T,
  describe = 'side effect',
): Result<T, KernelGateFailure> {
  try {
    return ok(body());
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return err({
      kind: 'induced_io_failure',
      message: `${describe} failed: ${msg}`,
    });
  }
}

/* ══════════════════════════════════════════════════════════════════════
 * Pretty-printers used by tests + audit logs
 * ══════════════════════════════════════════════════════════════════════ */

export function describeFailure(f: KernelGateFailure): string {
  switch (f.kind) {
    case 'cap_required':
      return `K2: required cap ${f.expectedCap ?? '?'} not presented`;
    case 'wrong_cap':
      return `K3a: wrong cap presented for ${f.expectedCap ?? '?'} (flag 0x${(f.presentedDomainFlag ?? 0).toString(16).padStart(8, '0')})`;
    case 'cell_already_consumed':
      return `K1: cell ${f.consumedCellId ?? '?'} already consumed`;
    case 'bad_signing_principal':
      return `K2: bad signing principal (expected ${f.expectedPrincipal ?? '?'})`;
    case 'invalid_state_transition':
      return `invalid transition ${f.attempted?.from ?? '?'} → ${f.attempted?.to ?? '?'}`;
    case 'from_state_mismatch':
      return `from-state mismatch: expected ${f.attempted?.from ?? '?'}, cell at ${f.attempted?.to ?? '?'}`;
    case 'induced_io_failure':
      return `K4: induced I/O failure — cell unchanged, retry-safe`;
  }
}

/** Re-export the cap registry shape so FSM modules use the same source. */
export { capabilityByName, type OddjobzCapability, type OddjobzCapName };

```
