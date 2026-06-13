---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/governance/dispute-escalator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.458342+00:00
---

# packages/extraction/src/governance/dispute-escalator.ts

```ts
/**
 * Dispute escalation flow — L2→L1→L0 using existing Ballot objects.
 *
 * Disputes are Ballot objects from core.json. No custom dispute engine.
 * An L2→L1 dispute is a Ballot linked to an ExtensionManifest.
 * An L1→L0 dispute is a Ballot linked to a GovernancePolicy.
 *
 * Escalation: if a dispute remains unresolved after disputeWindowSeconds,
 * it auto-escalates to the next level by creating a new Ballot.
 *
 * Emergency deprecation: L0 can force-deprecate an extension by creating
 * a Ballot with auto-approval.
 *
 * Cross-references:
 *   governance.ts           → GovernanceBallot, DisputeEscalationRule, GovernancePolicy
 *   extension-manifest.ts   → ExtensionManifest
 *   configs/extensions/core.json → Ballot, Dispute object types
 */

import type { ExtensionManifest } from '@semantos/protocol-types';
import type {
  GovernancePolicy,
  GovernedConsumerBinding,
  GovernanceBallot,
  DisputeEscalationRule,
} from '@semantos/protocol-types';

/**
 * Create an L2→L1 dispute ballot (consumer disputes author decision).
 *
 * @param binding - The consumer's governed binding
 * @param manifest - The extension manifest being disputed
 * @param reason - Human-readable dispute reason
 * @param disputeWindowSeconds - Window before auto-escalation (default 7 days)
 * @returns GovernanceBallot descriptor for creating a Ballot object
 */
export function createDisputeL2toL1(
  binding: GovernedConsumerBinding,
  manifest: ExtensionManifest,
  reason: string,
  disputeWindowSeconds: number = 604800, // 7 days
): GovernanceBallot {
  const now = new Date();
  const escalationDeadline = new Date(now.getTime() + disputeWindowSeconds * 1000);

  return {
    motion: `L2→L1 Dispute: ${reason}`,
    quorum: 1, // Author must respond
    relatedObjectId: manifest.id,
    initiatorHatId: binding.payload.extensionManifestId, // consumer's binding ID as hat ref
    reason,
    disputeLevel: 'L2_to_L1',
    createdAt: now.toISOString(),
    escalationDeadline: escalationDeadline.toISOString(),
  };
}

/**
 * Create an L1→L0 dispute ballot (author disputes platform policy).
 *
 * @param manifest - The extension manifest whose author is disputing
 * @param policy - The governance policy being disputed
 * @param reason - Human-readable dispute reason
 * @returns GovernanceBallot descriptor for creating a Ballot object
 */
export function createDisputeL1toL0(
  manifest: ExtensionManifest,
  policy: GovernancePolicy,
  reason: string,
): GovernanceBallot {
  return {
    motion: `L1→L0 Dispute: ${reason}`,
    quorum: Math.ceil(policy.payload.breakingChangeBallotQuorum / 100 * 3), // L0 uses platform quorum
    relatedObjectId: policy.payload.governedByHatId, // link to policy's governing hat
    initiatorHatId: manifest.id,
    reason,
    disputeLevel: 'L1_to_L0',
    createdAt: new Date().toISOString(),
  };
}

/**
 * Escalate a dispute to the next governance level.
 *
 * L2→L1 escalates to L0 by creating a new Ballot on the GovernancePolicy.
 *
 * @param originalBallot - The unresolved ballot
 * @param policy - The L0 governance policy
 * @returns New GovernanceBallot at the escalated level
 */
export function escalateDispute(
  originalBallot: GovernanceBallot,
  policy: GovernancePolicy,
): GovernanceBallot {
  if (originalBallot.disputeLevel === 'L2_to_L1') {
    return {
      motion: `Escalated from L2→L1: ${originalBallot.reason}`,
      quorum: Math.ceil(policy.payload.breakingChangeBallotQuorum / 100 * 3),
      relatedObjectId: policy.payload.governedByHatId,
      initiatorHatId: originalBallot.initiatorHatId,
      reason: `Auto-escalated: ${originalBallot.reason}`,
      disputeLevel: 'L1_to_L0',
      createdAt: new Date().toISOString(),
    };
  }

  // L1→L0 cannot escalate further — L0 decision is binding
  throw new Error('L1→L0 disputes cannot be escalated further. L0 decision is binding.');
}

/**
 * Check if a dispute should auto-escalate based on the escalation rule.
 *
 * @param ballot - The dispute ballot to check
 * @param rule - Escalation rule to evaluate
 * @returns true if the dispute should be escalated
 */
export function checkEscalationDue(
  ballot: GovernanceBallot,
  rule: DisputeEscalationRule,
): boolean {
  if (rule.triggerCondition === 'unresolved_after_window') {
    if (!ballot.escalationDeadline) return false;
    const deadline = new Date(ballot.escalationDeadline).getTime();
    return Date.now() >= deadline;
  }

  if (rule.triggerCondition === 'critical_security') {
    return ballot.reason.includes('security') || ballot.reason.includes('vulnerability');
  }

  if (rule.triggerCondition === 'manifest_deprecation') {
    return ballot.reason.includes('deprecation') || ballot.reason.includes('deprecated');
  }

  return false;
}

/**
 * Create an emergency deprecation ballot (L0 force-deprecation).
 *
 * L0 can force-deprecate an extension for platform safety:
 * - Creates a ballot that auto-approves
 * - Marks manifest as deprecated with sunset date
 *
 * @param manifest - The manifest to deprecate
 * @param policy - The L0 governance policy
 * @param reason - Reason for emergency deprecation
 * @param sunsetDays - Days until removal (from policy or override)
 * @returns Object with the ballot and manifest deprecation updates
 */
export function createEmergencyDeprecation(
  manifest: ExtensionManifest,
  policy: GovernancePolicy,
  reason: string,
  sunsetDays?: number,
): { ballot: GovernanceBallot; deprecationStatus: ExtensionManifest['deprecationStatus'] } {
  const days = sunsetDays ?? policy.payload.emergencyDeprecationPolicy.minDaysNotice;
  const sunsetDate = new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();

  const ballot: GovernanceBallot = {
    motion: `Emergency deprecation: ${reason}`,
    quorum: 1, // L0 vote is binding
    relatedObjectId: manifest.id,
    initiatorHatId: policy.payload.governedByHatId,
    reason: `emergency-deprecation: ${reason}`,
    disputeLevel: 'L1_to_L0',
    createdAt: new Date().toISOString(),
  };

  const deprecationStatus: ExtensionManifest['deprecationStatus'] = {
    isDeprecated: true,
    deprecatedDate: new Date().toISOString(),
    sunsetDate,
    migrationNotes: `Emergency deprecation: ${reason}`,
  };

  return { ballot, deprecationStatus };
}

```
