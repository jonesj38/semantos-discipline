---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/reply-generator-assembled-prompt.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.534540+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/reply-generator-assembled-prompt.test.ts

```ts
/**
 * generateReply.assembledPrompt fidelity (Increment 3, pure surface).
 *
 * The conversation-turn patch hashes `assembledPrompt` for versioned
 * prompt provenance — so it MUST be byte-identical to what the LLM
 * actually saw, not an approximation. This test captures the exact
 * `systemPrompt` the injected llm receives and asserts the surfaced
 * `result.assembledPrompt` equals it (and is BASE_SYSTEM-rooted).
 *
 * reply-generator.ts imports only ./state-manager (pure) + types —
 * no @semantos/intent — so this runs in this worktree (unlike the
 * turn-handler/intake-handler seam, which is code-read-verified).
 */

import { describe, expect, test } from 'bun:test';
import { generateReply } from '../reply-generator.js';
import { emptyJobState } from '../accumulated-job-state.js';

describe('generateReply — assembledPrompt fidelity', () => {
  test('surfaced assembledPrompt is exactly the prompt the LLM saw', async () => {
    let sawSystemPrompt: string | null = null;
    const r = await generateReply({
      state: emptyJobState(),
      history: [],
      latestMessage: 'hi, I might need some work done',
      operatorName: 'Todd',
      // present_estimate is gated by the state-manager cascade; an
      // empty state won't trip it, so this is never invoked — but
      // pass a stub so the contract is satisfied either way.
      estimatorFn: () => '$0–$0',
      llm: async ({ systemPrompt }) => {
        sawSystemPrompt = systemPrompt;
        return 'ok, tell me more about the job';
      },
    });

    expect(typeof r.assembledPrompt).toBe('string');
    expect(r.assembledPrompt.length).toBeGreaterThan(0);
    // Byte-identical to what the LLM received — the hash provenance
    // would be meaningless otherwise.
    expect(sawSystemPrompt).not.toBeNull();
    expect(r.assembledPrompt).toBe(sawSystemPrompt as unknown as string);
    // BASE_SYSTEM is always the root of the assembled prompt.
    expect(r.assembledPrompt.startsWith('You are')).toBe(true);
    expect(r.replyText).toBe('ok, tell me more about the job');
  });
});

```
