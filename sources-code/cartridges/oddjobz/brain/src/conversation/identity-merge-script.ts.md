---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/identity-merge-script.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.521983+00:00
---

# cartridges/oddjobz/brain/src/conversation/identity-merge-script.ts

```ts
/**
 * D-OJ-conv-identity-merge-endpoint — bun subprocess: execute an identity merge.
 *
 * Wire protocol (from identity_merge_http.zig):
 *   stdin:  { sourceParticipantId: string, targetParticipantId: string,
 *             challengeQuestion: string, challengeAnswer: string,
 *             operatorConfirmed: boolean }
 *   stdout: { ok: true,  mergeId: string, chain: string[] }
 *         | { ok: false, error: 'not_confirmed' }
 *         | { ok: false, error: 'same_identity' }
 *         | { ok: false, error: 'db_error' }
 *
 * The `already_merged` case is handled idempotently: we call followMerges to
 * reconstruct the chain from the existing MERGES relation and return ok:true
 * so callers can treat a duplicate merge as a success (safe re-try).
 *
 * Architecture constraints (project memories):
 *   - No self-calls back into the brain HTTP/REPL
 *     (semantos_brain_single_threaded_reactor). This script connects
 *     directly to Postgres via DATABASE_URL — external IO, safe.
 *   - No AI calls (semantos_no_ai_in_substrate).
 *   - ESM imports use .js extensions for relative paths.
 *   - process.exit(0) at end is MANDATORY — postgres.js pool keeps the
 *     event loop alive otherwise (pool-linger bug).
 */

import { getDatabaseOrNull } from './db.js';
import { processIdentityMerge, followMerges } from './identity-merge.js';
import type { IdentityMergeRequest } from './identity-merge.js';

// ── Read stdin ────────────────────────────────────────────────────────────────

const stdinChunks: Buffer[] = [];
for await (const chunk of process.stdin) stdinChunks.push(chunk as Buffer);
const input = JSON.parse(Buffer.concat(stdinChunks).toString()) as {
  sourceParticipantId: string;
  targetParticipantId: string;
  challengeQuestion: string;
  challengeAnswer: string;
  operatorConfirmed: boolean;
};

// ── Connect to DB ─────────────────────────────────────────────────────────────

const db = getDatabaseOrNull();
if (!db) {
  process.stdout.write(JSON.stringify({ ok: false, error: 'db_error' }) + '\n');
  process.exit(0);
}

// ── Build request ─────────────────────────────────────────────────────────────

const mergeReq: IdentityMergeRequest = {
  sourceParticipantId: input.sourceParticipantId,
  targetParticipantId: input.targetParticipantId,
  challengeQuestion: input.challengeQuestion,
  challengeAnswer: input.challengeAnswer,
  operatorConfirmed: input.operatorConfirmed,
};

// ── Execute merge ─────────────────────────────────────────────────────────────

try {
  const result = await processIdentityMerge(db, mergeReq);

  if (!result.ok) {
    switch (result.reason) {
      case 'challenge_not_confirmed':
        process.stdout.write(JSON.stringify({ ok: false, error: 'not_confirmed' }) + '\n');
        break;

      case 'same_identity':
        process.stdout.write(JSON.stringify({ ok: false, error: 'same_identity' }) + '\n');
        break;

      case 'already_merged': {
        // Idempotent: reconstruct the chain from the existing MERGES
        // edges and return ok:true so callers can treat duplicate
        // merges as successes (safe re-try semantics).
        const chain = await followMerges(db, input.sourceParticipantId);
        process.stdout.write(
          JSON.stringify({ ok: true, mergeId: 'existing', chain }) + '\n',
        );
        break;
      }

      default:
        process.stdout.write(JSON.stringify({ ok: false, error: 'db_error' }) + '\n');
    }
  } else {
    // Merge succeeded — follow the chain from source to build the
    // complete merge chain for the caller.
    const chain = await followMerges(db, input.sourceParticipantId);
    process.stdout.write(
      JSON.stringify({ ok: true, mergeId: result.relationId, chain }) + '\n',
    );
  }
} catch (err) {
  process.stderr.write(
    `[identity-merge-script] Unexpected error: ${err instanceof Error ? err.message : String(err)}\n`,
  );
  process.stdout.write(JSON.stringify({ ok: false, error: 'db_error' }) + '\n');
}

// Force exit: postgres.js holds the connection pool open (active socket) after
// all work is done, which prevents bun's event loop from draining naturally.
// Since this is a one-shot subprocess, a hard exit is correct — no cleanup needed.
process.exit(0);

```
