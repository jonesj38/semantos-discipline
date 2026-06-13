---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/recovery/recovery/src/challenge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.451059+00:00
---

# packages/recovery/recovery/src/challenge.ts

```ts
/**
 * Challenge-response validation for the recovery flow.
 * Handles secure answer hashing and validation.
 *
 * @deprecated This module is a placeholder. Challenge-response auth, including
 * answer normalization, salted hashing, and rate-limited validation, is owned
 * by the Plexus Identity Domain (see Plexus Technical Requirements §9).
 * Once the Plexus Vendor SDK ships, this file should be removed and all
 * challenge operations should flow through the PlexusAdapter boundary.
 */

import { Hash } from '@bsv/sdk';

/**
 * A stored challenge question with its salted hash.
 */
export interface StoredChallenge {
  questionId: string;
  questionText: string;
  answerHash: string; // hex, SHA256(normalize(answer) + salt)
  salt: string; // hex, 16 bytes
  derivationDepth: number; // which level of the DAG this challenge gates
}

/**
 * A user's answer submission.
 */
export interface ChallengeAnswer {
  questionId: string;
  plainTextAnswer: string;
}

/**
 * Result of challenge validation.
 */
export interface ChallengeValidationResult {
  allCorrect: boolean;
  results: Array<{
    questionId: string;
    correct: boolean;
  }>;
  grantedDepth: number; // max derivation depth the user has access to
}

/**
 * Normalizes an answer for consistent hashing.
 * Lowercases, trims, collapses whitespace, strips punctuation.
 *
 * @param answer - Raw user answer
 * @returns Normalized answer string
 */
export function normalizeAnswer(answer: string): string {
  return answer
    .toLowerCase()
    .trim()
    .replace(/\s+/g, ' ')
    .replace(/[^\w\s]/g, '');
}

/**
 * Converts a hex string to Uint8Array.
 */
function hexToUint8Array(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substr(i, 2), 16);
  }
  return bytes;
}

/**
 * Converts Uint8Array to hex string.
 */
function uint8ArrayToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Hashes a normalized answer with a salt using SHA256.
 *
 * @param normalized - Normalized answer string
 * @param salt - Salt bytes (typically 16 bytes)
 * @returns Hex-encoded SHA256 hash
 */
export async function hashAnswer(
  normalized: string,
  salt: Uint8Array
): Promise<string> {
  const message = new TextEncoder().encode(normalized);
  const combined = new Uint8Array(message.length + salt.length);
  combined.set(message);
  combined.set(salt, message.length);

  const hash = Hash.sha256(combined);
  return uint8ArrayToHex(new Uint8Array(hash));
}

/**
 * Constant-time comparison of two hex strings.
 * Prevents timing attacks.
 */
function constantTimeCompare(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }

  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

/**
 * Validates user answers against stored challenges.
 * Returns which were correct and the maximum derivation depth granted.
 *
 * @param stored - Array of stored challenges
 * @param answers - User-submitted answers
 * @returns Validation result with per-question status and granted depth
 */
export async function validateChallenges(
  stored: StoredChallenge[],
  answers: ChallengeAnswer[]
): Promise<ChallengeValidationResult> {
  const answerMap = new Map(answers.map((a) => [a.questionId, a]));

  const results: Array<{ questionId: string; correct: boolean }> = [];
  let minGrantedDepth = Infinity;
  let allCorrect = true;

  for (const challenge of stored) {
    const answer = answerMap.get(challenge.questionId);

    if (!answer) {
      results.push({ questionId: challenge.questionId, correct: false });
      allCorrect = false;
      continue;
    }

    const normalized = normalizeAnswer(answer.plainTextAnswer);
    const salt = hexToUint8Array(challenge.salt);
    const computed = await hashAnswer(normalized, salt);

    const correct = constantTimeCompare(computed, challenge.answerHash);
    results.push({ questionId: challenge.questionId, correct });

    if (!correct) {
      allCorrect = false;
    } else {
      minGrantedDepth = Math.min(minGrantedDepth, challenge.derivationDepth);
    }
  }

  return {
    allCorrect,
    results,
    grantedDepth: allCorrect && minGrantedDepth !== Infinity ? minGrantedDepth : 0,
  };
}

/**
 * Creates and stores a new challenge with hashed answer.
 * Generates a random salt and computes the salted hash.
 *
 * @param questionId - Unique identifier for the question
 * @param questionText - The question to present to the user
 * @param plainAnswer - The correct answer (in plain text)
 * @param derivationDepth - Which DAG level this challenge gates
 * @returns StoredChallenge ready to persist
 */
export async function createStoredChallenge(
  questionId: string,
  questionText: string,
  plainAnswer: string,
  derivationDepth: number
): Promise<StoredChallenge> {
  // Generate 16-byte random salt
  const salt = new Uint8Array(16);
  for (let i = 0; i < 16; i++) {
    salt[i] = Math.floor(Math.random() * 256);
  }

  const normalized = normalizeAnswer(plainAnswer);
  const answerHash = await hashAnswer(normalized, salt);

  return {
    questionId,
    questionText,
    answerHash,
    salt: uint8ArrayToHex(salt),
    derivationDepth,
  };
}

```
