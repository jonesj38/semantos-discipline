---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-contracts/src/recovery.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.821470+00:00
---

# core/plexus-contracts/src/recovery.ts

```ts
/**
 * Plexus recovery types.
 *
 * Based on Plexus Technical Requirements v1.3 — Recovery Service (component 11),
 * Challenge Set Record (component 16).
 */

/** A single challenge question (prompt only — answer is never stored in plaintext). */
export interface ChallengeSpec {
  /** Unique challenge identifier within the set. */
  id: string;
  /** Human-readable prompt displayed to the user. */
  prompt: string;
}

/** A submitted answer to a challenge (normalized + hashed before comparison). */
export interface ChallengeAnswer {
  /** Challenge ID being answered. */
  challengeId: string;
  /** Raw answer text (will be normalized, salted, and SHA-256 hashed). */
  answer: string;
}

/** Recovery session state. */
export type RecoveryStatus = 'pending' | 'verified' | 'failed';

/** A disaster recovery session. */
export interface RecoverySession {
  /** Unique session identifier (SHA-256 derived). */
  sessionId: string;
  /** Email of the identity being recovered. */
  email: string;
  /** Challenge questions for this session. */
  challenges: ChallengeSpec[];
  /** Stored SHA-256 hashes of normalized, salted answers. */
  answerHashes: string[];
  /** Current session status. */
  status: RecoveryStatus;
}

```
