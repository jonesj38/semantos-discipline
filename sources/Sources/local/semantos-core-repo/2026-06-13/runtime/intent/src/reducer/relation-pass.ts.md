---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/reducer/relation-pass.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.348695+00:00
---

# runtime/intent/src/reducer/relation-pass.ts

```ts
/**
 * RM-030 — SCG typed-relation reducer pass.
 *
 * Sits between `rhetoric` (which classifies the speech act) and
 * `analogical_prefilter` (which retrieves analogous past intents). The
 * relation pass detects NL phrases that signal an SCG conversation-graph
 * relation between the current turn and a prior turn or object — e.g.
 * "reply to that", "+1 on the previous", "this contradicts what X
 * said", "see also: Y", "that fulfills my request".
 *
 * When a relation phrase fires, the pass contributes a
 * `SIRConstraint { kind: 'relation', relationKind }` to the
 * accumulated Intent. Phase-1 lowering (RM-020) turns that into a
 * capability + typeHash composite at the IR layer.
 *
 * `sourceId` and `targetId` resolution is deferred — pinning a relation
 * to specific objectIds requires conversation-context state that lives
 * one layer above the reducer (in `handle-message.ts`'s pending-proposal
 * registry). For now the pass emits the kind only; the resolver attaches
 * IDs later if it can find them.
 *
 * Confidence model: the highest-confidence matched phrase wins; if
 * nothing matches the pass returns `confidence: 1.0` with
 * `skipInComposite: true` (no relation phrase = vacuously satisfied;
 * doesn't drag down the geometric mean).
 */

import type { SIRConstraint } from '@semantos/semantos-sir';
import type { RelationKind } from '@semantos/scg-relations';
import type { PassAlternative, PassFn, PassResult } from './types';
import { MAX_PASS_ALTERNATIVES } from './types';

// ── Phrase patterns ─────────────────────────────────────────────────

interface RelationPattern {
  kind: RelationKind;
  /** Regex that matches an exemplar phrase. Anchored loosely; we OR
   *  multiple patterns per kind. */
  pattern: RegExp;
  /** Per-pattern confidence in the [0,1] range. Tuned by hand for now;
   *  consumers can override via a future reducer option. */
  confidence: number;
}

const PATTERNS: ReadonlyArray<RelationPattern> = [
  // REPLIES_TO
  { kind: 'REPLIES_TO', pattern: /\breply(?:ing)?\s+to\b/i, confidence: 0.9 },
  { kind: 'REPLIES_TO', pattern: /\bin\s+(?:response|reply)\s+to\b/i, confidence: 0.85 },
  { kind: 'REPLIES_TO', pattern: /\bre:\s+/i, confidence: 0.7 },

  // SUPPORTS
  { kind: 'SUPPORTS', pattern: /\+1\b/, confidence: 0.95 },
  { kind: 'SUPPORTS', pattern: /\b(?:i\s+)?(?:agree|second(?:ed)?|endorse|support)\b/i, confidence: 0.8 },
  { kind: 'SUPPORTS', pattern: /\bup(?:vote|voting)\b/i, confidence: 0.9 },

  // DISPUTES
  { kind: 'DISPUTES', pattern: /\bdisagree\b/i, confidence: 0.85 },
  { kind: 'DISPUTES', pattern: /\bcontradict(?:s|ing)?\b/i, confidence: 0.9 },
  { kind: 'DISPUTES', pattern: /\bobject(?:s|ion)?\s+to\b/i, confidence: 0.8 },
  { kind: 'DISPUTES', pattern: /\bdown(?:vote|voting)\b/i, confidence: 0.9 },
  { kind: 'DISPUTES', pattern: /-1\b/, confidence: 0.85 },

  // SUPERSEDES
  { kind: 'SUPERSEDES', pattern: /\bsupersed(?:e|es|ed|ing)\b/i, confidence: 0.95 },
  { kind: 'SUPERSEDES', pattern: /\breplaces?\s+(?:the\s+)?(?:previous|earlier|prior)\b/i, confidence: 0.85 },

  // CITES
  { kind: 'CITES', pattern: /\bsee\s+also\b/i, confidence: 0.85 },
  { kind: 'CITES', pattern: /\bcf\.\s+/i, confidence: 0.85 },
  { kind: 'CITES', pattern: /\bcit(?:e|es|ing|ation)\b/i, confidence: 0.8 },
  { kind: 'CITES', pattern: /\breferenc(?:e|es|ing)\b/i, confidence: 0.7 },

  // FORKS
  { kind: 'FORKS', pattern: /\bfork(?:s|ing|ed)?\s+(?:from|of)\b/i, confidence: 0.9 },
  { kind: 'FORKS', pattern: /\bbranch(?:ing)?\s+from\b/i, confidence: 0.85 },

  // REQUESTS_ACTION
  { kind: 'REQUESTS_ACTION', pattern: /\bplease\s+(?:do|action|handle|fix)\b/i, confidence: 0.8 },
  { kind: 'REQUESTS_ACTION', pattern: /\bcan\s+you\s+(?:do|action|handle)\b/i, confidence: 0.75 },
  { kind: 'REQUESTS_ACTION', pattern: /\brequest(?:s|ing)?\s+(?:action|that)\b/i, confidence: 0.8 },

  // FULFILLS
  { kind: 'FULFILLS', pattern: /\bfulfill?s?\b/i, confidence: 0.9 },
  { kind: 'FULFILLS', pattern: /\bcomplet(?:e|es|ed|ing)\s+(?:the\s+)?(?:request|task)\b/i, confidence: 0.85 },
  { kind: 'FULFILLS', pattern: /\bdone\s+with\s+(?:the\s+)?(?:request|task)\b/i, confidence: 0.75 },

  // PAYS
  { kind: 'PAYS', pattern: /\bpay(?:s|ing|ment)\b/i, confidence: 0.85 },
  { kind: 'PAYS', pattern: /\btransfer\s+(?:\$|\d+|funds|payment)\b/i, confidence: 0.9 },
  { kind: 'PAYS', pattern: /\bsettle\s+the\s+(?:invoice|bill|account)\b/i, confidence: 0.85 },

  // ATTESTS
  { kind: 'ATTESTS', pattern: /\battest(?:s|ing|ation)?\b/i, confidence: 0.9 },
  { kind: 'ATTESTS', pattern: /\bi\s+witness(?:ed)?\b/i, confidence: 0.85 },
  { kind: 'ATTESTS', pattern: /\b(?:i\s+)?confirm\s+that\b/i, confidence: 0.7 },

  // GRANTS_ACCESS
  { kind: 'GRANTS_ACCESS', pattern: /\bgrant(?:s|ing)?\s+access\b/i, confidence: 0.95 },
  { kind: 'GRANTS_ACCESS', pattern: /\bauthor(?:ise|ize|ising|izing)\s+access\b/i, confidence: 0.9 },

  // APPROVES
  { kind: 'APPROVES', pattern: /\bapprov(?:e|es|ed|ing)\b/i, confidence: 0.85 },
  { kind: 'APPROVES', pattern: /\b(?:i\s+)?accept\b/i, confidence: 0.65 },
  { kind: 'APPROVES', pattern: /\bsigned\s+off\b/i, confidence: 0.85 },
];

// ── Pass implementation ────────────────────────────────────────────

export const relationPass: PassFn = async (_accumulated, ctx): Promise<PassResult> => {
  const { state } = ctx;
  const flags: string[] = [];

  // Source corpus: anything textual the reducer has at this stage.
  const haystack = [
    state.conversationSummary ?? '',
    state.scopeDescription ?? '',
    ...state.taggedFacts.map((f) => f.fact),
  ]
    .filter(Boolean)
    .join(' \n ');

  if (haystack.trim().length === 0) {
    return {
      pass: 'relation',
      contribution: {},
      confidence: 1,
      flags: ['relation: no input text to scan'],
      skipInComposite: true,
    };
  }

  // Collect every matching pattern.
  const matches: Array<{ kind: RelationKind; confidence: number; matchText: string }> = [];
  for (const pat of PATTERNS) {
    const m = pat.pattern.exec(haystack);
    if (m) matches.push({ kind: pat.kind, confidence: pat.confidence, matchText: m[0] });
  }

  if (matches.length === 0) {
    return {
      pass: 'relation',
      contribution: {},
      confidence: 1,
      flags: [],
      skipInComposite: true,
    };
  }

  // Highest-confidence match wins. Ties broken by pattern order
  // (REPLIES_TO before SUPPORTS, etc — list order is canonical).
  matches.sort((a, b) => b.confidence - a.confidence);
  const winner = matches[0]!;

  if (matches.length > 1) {
    const others = matches
      .slice(1)
      .map((m) => `${m.kind}(${m.confidence.toFixed(2)})`)
      .join(', ');
    flags.push(
      `relation: multiple matches; selected ${winner.kind} ` +
        `(${winner.confidence.toFixed(2)}); also matched ${others}`,
    );
  }

  const constraint: SIRConstraint = {
    kind: 'relation',
    relationKind: winner.kind,
  };

  // RM-092 — surface the losing candidates so trace consumers can see
  // *what else the pass considered*. Bound to MAX_PASS_ALTERNATIVES;
  // the underlying ranking is unbounded but the trace stays compact.
  const alternatives: PassAlternative[] = matches
    .slice(1, 1 + MAX_PASS_ALTERNATIVES)
    .map((m) => ({
      candidate: { kind: m.kind, matchText: m.matchText },
      confidence: m.confidence,
      reason:
        `matched ${m.kind} (${m.confidence.toFixed(2)}) but ${winner.kind} ` +
        `(${winner.confidence.toFixed(2)}) ranked higher`,
    }));

  return {
    pass: 'relation',
    contribution: {
      constraints: [constraint],
    },
    confidence: winner.confidence,
    flags,
    ...(alternatives.length > 0 ? { alternatives } : {}),
  };
};

```
