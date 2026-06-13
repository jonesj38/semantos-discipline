---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/authorization/capability-evaluator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.473364+00:00
---

# packages/scada/scada/src/authorization/capability-evaluator.ts

```ts
/**
 * Capability evaluator — pure: does a SCADA capability token grant the
 * required capability number for a given command type?
 *
 * Decisions are split out from the orchestrator so the rule table can be
 * unit-tested in isolation and replayed for the byte-identical-decisions
 * differential test (see spec 28).
 *
 * Two flavours:
 *
 *   - `getRequiredCapabilityForCommand(commandType)` — numeric
 *     capability the command requires (or `null` if the command type
 *     is unrecognised, preserving legacy fall-through semantics).
 *   - `evaluateCapability(token, commandType)` — `{ ok: true } | { ok:
 *     false, reason: 'INSUFFICIENT_ROLE' | 'CONSUMED_CAPABILITY' |
 *     'EXPIRED_CAPABILITY' }`.
 *
 * Pure: no IO, no clock, no globals. Caller passes `nowMs` so tests can
 * pin time deterministically.
 */

import type { SCADACapabilityToken, SCADACommandType } from '../types';

export type CapabilityRejectReason =
  | 'CONSUMED_CAPABILITY'
  | 'EXPIRED_CAPABILITY'
  | 'INSUFFICIENT_ROLE';

export type CapabilityDecision =
  | { ok: true; required: number | null }
  | { ok: false; reason: CapabilityRejectReason; detail: string };

/**
 * Map command types to required capability numbers.
 *
 * Returns `null` for unrecognised types so the legacy
 * `if (requiredCap !== null && !token.capabilities.includes(...))`
 * branch keeps the same semantics: unknown commands skip the role check
 * (they will still fail elsewhere if no equipment matches).
 */
export function getRequiredCapabilityForCommand(
  commandType: SCADACommandType,
): number | null {
  switch (commandType) {
    case 'valve.open':
    case 'valve.close':
    case 'valve.set-position':
      return 3; // operate valves
    case 'motor.start':
    case 'motor.stop':
    case 'motor.set-speed':
      return 4; // motor operation
    case 'setpoint.change':
      return 4; // change setpoints
    case 'mode.change':
      return 6; // mode changes
    case 'alarm.acknowledge':
    case 'alarm.silence':
      return 2; // acknowledge alarms
    case 'emergency.shutdown':
      return 8; // emergency shutdown
  }
  return null;
}

/**
 * Decide whether a capability token may issue a command of the given
 * type at the given wall-clock time.
 *
 * Caller is responsible for separately tracking
 * `consumedTokens` set (the LINEAR ledger) — `evaluateCapability` only
 * sees per-token state and the requested command. The orchestrator
 * combines both checks.
 */
export function evaluateCapability(
  token: SCADACapabilityToken,
  commandType: SCADACommandType,
  nowMs: number,
  consumedTokenIds?: ReadonlySet<string>,
): CapabilityDecision {
  if (token.consumed || (consumedTokenIds?.has(token.tokenId) ?? false)) {
    return {
      ok: false,
      reason: 'CONSUMED_CAPABILITY',
      detail: `Capability token ${token.tokenId} already consumed (LINEAR — no replay)`,
    };
  }

  const tokenExpiry = new Date(token.shiftEnd).getTime();
  if (tokenExpiry < nowMs) {
    return {
      ok: false,
      reason: 'EXPIRED_CAPABILITY',
      detail: `Capability token expired at ${token.shiftEnd}`,
    };
  }

  const required = getRequiredCapabilityForCommand(commandType);
  if (required !== null && !token.capabilities.includes(required)) {
    return {
      ok: false,
      reason: 'INSUFFICIENT_ROLE',
      detail: `Role ${token.role} lacks capability ${required} for ${commandType}`,
    };
  }

  return { ok: true, required };
}

/**
 * Pure helper: does the token carry the given capability number? Used
 * for ad-hoc checks (e.g. CRITICAL alarm acknowledgement requires cap
 * 5+).
 */
export function tokenHasCapability(
  token: SCADACapabilityToken,
  capabilityNumber: number,
): boolean {
  return token.capabilities.includes(capabilityNumber);
}

```
