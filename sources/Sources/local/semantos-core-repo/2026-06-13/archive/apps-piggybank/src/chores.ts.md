---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-piggybank/src/chores.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.719744+00:00
---

# archive/apps-piggybank/src/chores.ts

```ts
/**
 * Chore & Reward Types
 *
 * The chore system models tasks as semantic objects:
 *   - ChoreTemplate  (RELEVANT) — a reusable chore definition owned by a parent
 *   - ChoreClaim     (LINEAR)   — a one-time claim that a kid did the chore
 *   - ChoreApproval  (LINEAR)   — parent's one-time approval triggering payment
 *   - BonusQuest     (AFFINE)   — a one-off challenge that can expire unclaimed
 *
 * The LINEAR/AFFINE enforcement means double-claims and double-approvals are
 * impossible at the protocol level, not just the app level.
 */

import {
  SemanticType,
  type SemanticObject,
  type LinearObject,
  type AffineObject,
  type RelevantObject,
  type ConsumptionProof,
} from '@semantos/core/types/semantic-objects.js';

// ── Chore Schedule ──────────────────────────────────────────────────────────

export enum ChoreFrequency {
  /** Must be completed once — never repeats */
  ONCE = 'ONCE',
  /** Resets every day */
  DAILY = 'DAILY',
  /** Resets every week (on a configured day) */
  WEEKLY = 'WEEKLY',
  /** Resets on the 1st of each month */
  MONTHLY = 'MONTHLY',
}

export interface ChoreSchedule {
  /** How often this chore repeats */
  frequency: ChoreFrequency;
  /** Day of week for WEEKLY chores (0=Sun, 6=Sat). null for others. */
  dayOfWeek: number | null;
  /** Hour of day (0-23) when the chore window opens. null = midnight. */
  windowOpenHour: number | null;
  /** Hour of day (0-23) when the chore window closes. null = end of day. */
  windowCloseHour: number | null;
}

// ── Streak Rules ────────────────────────────────────────────────────────────

export interface StreakBonus {
  /** Number of consecutive completions to trigger the bonus */
  threshold: number;
  /** Multiplier applied to base reward (1.5 = 50% bonus) */
  multiplier: number;
  /** Duration in days the multiplier lasts after hitting the streak */
  durationDays: number;
}

// ── Spending Limits ─────────────────────────────────────────────────────────

export interface SpendingLimits {
  /** Max satoshis the kid can spend per day without parent approval */
  dailyMaxSats: number;
  /** Max satoshis per single transaction without parent approval */
  perTxMaxSats: number;
  /** If true, ALL outbound spending requires parent co-signature */
  requireParentApproval: boolean;
}

// ── Chore Template (RELEVANT) ───────────────────────────────────────────────

/**
 * A reusable chore definition. Owned by a parent, synced to kid devices.
 *
 * RELEVANT type: always accessible, can be revoked by the parent.
 * Revoking a chore template removes it from all devices on next sync.
 */
export interface ChoreTemplate extends RelevantObject {
  semanticType: SemanticType.RELEVANT;

  /** Human-readable chore name ("Make your bed", "Empty dishwasher") */
  name: string;

  /** Optional description / instructions for the kid */
  description: string;

  /** Icon identifier (mapped to display assets on each platform) */
  icon: string;

  /** Base reward in satoshis for completing this chore */
  rewardSats: number;

  /** Hex cert ID of the parent who created this chore */
  issuerCertId: string;

  /** Which kids this chore applies to (cert IDs). Empty = all kids. */
  assignedKids: string[];

  /** When and how often this chore repeats */
  schedule: ChoreSchedule;

  /** Streak bonus rules. Empty array = no streaks. */
  streakBonuses: StreakBonus[];

  /** If true, parent must manually approve each claim. If false, auto-approve. */
  requiresApproval: boolean;

  /** Category tag for grouping in the UI ("hygiene", "kitchen", "outdoor") */
  category: string;
}

// ── Chore Claim (LINEAR) ────────────────────────────────────────────────────

export enum ClaimStatus {
  /** Submitted by kid, awaiting parent review */
  PENDING = 'PENDING',
  /** Parent approved — payment queued */
  APPROVED = 'APPROVED',
  /** Parent rejected — no payment */
  REJECTED = 'REJECTED',
  /** Auto-approved (chore.requiresApproval = false) */
  AUTO_APPROVED = 'AUTO_APPROVED',
}

/**
 * Proof that a chore claim was resolved (approved/rejected).
 */
export interface ClaimResolutionProof extends ConsumptionProof {
  /** The resolution status */
  resolution: ClaimStatus.APPROVED | ClaimStatus.REJECTED | ClaimStatus.AUTO_APPROVED;
  /** Optional parent comment ("Great job!" or "The bins weren't actually empty") */
  comment: string;
}

/**
 * A one-time claim that a kid completed a chore.
 *
 * LINEAR type: consumed exactly once when the parent approves or rejects.
 * The kid's device mints this, signs it with CHORE_SIGNING domain key,
 * and queues it for sync to the parent app.
 */
export interface ChoreClaim extends LinearObject<ClaimResolutionProof> {
  semanticType: SemanticType.LINEAR;

  /** Resource ID of the ChoreTemplate this claim is for */
  choreTemplateId: string;

  /** Hex cert ID of the kid claiming completion */
  kidCertId: string;

  /** Hex cert ID of the device that minted this claim */
  deviceCertId: string;

  /** Unix timestamp (ms) when the kid pressed "done" */
  claimedAt: number;

  /** Current status of the claim */
  status: ClaimStatus;

  /** Hex signature from the kid's CHORE_SIGNING key */
  kidSignature: string;

  /** Optional photo hash (SHA-256 of proof photo, if the chore requires it) */
  proofHash: string | null;

  /** Streak count at time of claim (how many consecutive completions) */
  currentStreak: number;

  /** Effective reward in sats (base × streak multiplier if applicable) */
  effectiveRewardSats: number;
}

// ── Bonus Quest (AFFINE) ────────────────────────────────────────────────────

/**
 * A one-off challenge from a parent. Can be claimed or can expire.
 *
 * AFFINE type: consumed (acknowledged) if completed, discarded if it expires.
 * "Mow the lawn this Saturday = 5000 sats" — if Saturday passes without
 * a claim, the quest is discarded. No penalty, just a missed opportunity.
 */
export interface BonusQuest extends AffineObject<BonusQuestMeta> {
  semanticType: SemanticType.AFFINE;

  /** Human-readable quest name */
  name: string;

  /** Description / instructions */
  description: string;

  /** Reward in satoshis */
  rewardSats: number;

  /** Hex cert ID of the parent who posted this quest */
  issuerCertId: string;

  /** Which kids can claim this (cert IDs). Empty = any kid. */
  eligibleKids: string[];

  /** Unix timestamp (ms) when this quest expires and auto-discards */
  expiresAt: number;
}

export interface BonusQuestMeta {
  /** Hex cert ID of the kid who claimed it (if acknowledged) */
  claimedBy: string | null;
  /** Unix timestamp (ms) of the claim */
  claimedAt: number | null;
}

// ── Savings Goal ────────────────────────────────────────────────────────────

/**
 * A savings target set by the kid (with optional parent guidance).
 * Not a semantic object — this is local device state, persisted in NVS.
 */
export interface SavingsGoal {
  /** Unique goal ID (device-local) */
  goalId: string;
  /** What they're saving for ("Nintendo Switch", "New bike") */
  name: string;
  /** Target amount in satoshis */
  targetSats: number;
  /** Amount currently earmarked toward this goal */
  savedSats: number;
  /** Unix timestamp (ms) when goal was created */
  createdAt: number;
  /** Unix timestamp (ms) when goal was reached (null if not yet) */
  reachedAt: number | null;
  /** Optional icon identifier */
  icon: string;
}

// ── Factory Functions ───────────────────────────────────────────────────────

let _idCounter = 0;
function generateId(): string {
  return (++_idCounter).toString(16).padStart(4, '0') + '-' + Date.now().toString(16);
}

/**
 * Create a new chore template.
 */
export function createChoreTemplate(
  opts: Pick<ChoreTemplate, 'name' | 'rewardSats' | 'issuerCertId'> &
    Partial<Omit<ChoreTemplate, 'semanticType' | 'resourceId' | 'createdAt' | 'schemaVersion' | 'revocation' | 'lastValidatedAt'>>
): ChoreTemplate {
  return {
    semanticType: SemanticType.RELEVANT,
    resourceId: generateId(),
    createdAt: Date.now(),
    schemaVersion: 1,
    revocation: null,
    lastValidatedAt: Date.now(),
    name: opts.name,
    description: opts.description ?? '',
    icon: opts.icon ?? 'default',
    rewardSats: opts.rewardSats,
    issuerCertId: opts.issuerCertId,
    assignedKids: opts.assignedKids ?? [],
    schedule: opts.schedule ?? { frequency: ChoreFrequency.DAILY, dayOfWeek: null, windowOpenHour: null, windowCloseHour: null },
    streakBonuses: opts.streakBonuses ?? [],
    requiresApproval: opts.requiresApproval ?? true,
    category: opts.category ?? 'general',
  };
}

/**
 * Create a new chore claim (minted on kid's device).
 */
export function createChoreClaim(
  choreTemplateId: string,
  kidCertId: string,
  deviceCertId: string,
  rewardSats: number,
  currentStreak: number,
  streakMultiplier: number,
  kidSignature: string,
): ChoreClaim {
  return {
    semanticType: SemanticType.LINEAR,
    resourceId: generateId(),
    createdAt: Date.now(),
    schemaVersion: 1,
    consumed: false,
    consumedBy: null,
    consumptionTxId: null,
    choreTemplateId,
    kidCertId,
    deviceCertId,
    claimedAt: Date.now(),
    status: ClaimStatus.PENDING,
    kidSignature,
    proofHash: null,
    currentStreak,
    effectiveRewardSats: Math.floor(rewardSats * streakMultiplier),
  };
}

/**
 * Create a bonus quest.
 */
export function createBonusQuest(
  opts: Pick<BonusQuest, 'name' | 'rewardSats' | 'issuerCertId' | 'expiresAt'> &
    Partial<Pick<BonusQuest, 'description' | 'eligibleKids'>>
): BonusQuest {
  return {
    semanticType: SemanticType.AFFINE,
    resourceId: generateId(),
    createdAt: Date.now(),
    schemaVersion: 1,
    acknowledged: false,
    discarded: false,
    metadata: { claimedBy: null, claimedAt: null },
    name: opts.name,
    description: opts.description ?? '',
    rewardSats: opts.rewardSats,
    issuerCertId: opts.issuerCertId,
    eligibleKids: opts.eligibleKids ?? [],
    expiresAt: opts.expiresAt,
  };
}

```
