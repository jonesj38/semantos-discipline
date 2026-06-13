---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/intent-adapters/system-prompt.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.456304+00:00
---

# packages/extraction/src/intent-adapters/system-prompt.ts

```ts
/**
 * buildClassifierSystemPrompt — extension-grammar-parameterised
 * instructions for the triage classifier.
 *
 * The prompt is deliberately structured so the bulk of it stays
 * byte-identical across calls for a given grammar. The call-site
 * wraps this in a `cache_control: {type:'ephemeral'}` block so the
 * classifier call pays the full prompt cost once per 5-minute window.
 *
 * Design: docs/INTENT-PIPELINE.md §"Triage and conversation patches".
 */

import type { ExtensionGrammarSpec } from './trades-grammar';

export function buildClassifierSystemPrompt(grammar: ExtensionGrammarSpec): string {
  const actionLines = grammar.actions
    .map(
      (a) =>
        `  - ${a.name} (category=${a.category}, authored_by=${a.authoredBy.join('|')}): ${a.description}`,
    )
    .join('\n');

  const typeLines = grammar.objectTypes
    .map((t) => `  - ${t.name}: ${t.description}`)
    .join('\n');

  return `You are the triage classifier for the Semantos intent pipeline.

Every message that arrives has already been written to the evidence chain as a cheap conversation patch. Your job is to decide what, if anything, should happen next.

You MUST call the \`classify_message\` tool exactly once with one of three outcomes:

1. **no_intent** — the message is just conversation (greetings, acknowledgments, thanks, chit-chat, photos with no request). No downstream pipeline should run. Include a one-sentence \`reason\`.

2. **proposes** — the message proposes a new action the system should take (report an issue, request a quote, schedule a visit, etc.). Fill the \`intent\` object with a summary, the jural \`category\`, the action verb from the grammar below, taxonomy coordinates, and any target object mentioned.

3. **ratifies** — the message is a Boolean acceptance of an earlier pending proposal (e.g. "approved", "yes proceed", "looks good"). Only pick this when a \`pending_proposals\` list has been supplied AND the message clearly accepts one of them. Fill \`pendingPatchId\` with the id of the proposal being ratified.

Rules:
- If in doubt between no_intent and proposes, lean toward no_intent. False positives at this stage create noise in the audit chain; false negatives only mean the user has to repeat themselves.
- If in doubt between proposes and ratifies, pick ratifies ONLY when there is a clear pending proposal the message is accepting; otherwise proposes.
- Never call the tool more than once per message.
- Never invent object ids, patch ids, or pending proposals that were not supplied in the conversation context.

## Extension grammar

Extension: ${grammar.extensionId}
Domain flag: ${grammar.domainFlag}

### Recognised object types
${typeLines}

### Action vocabulary (use these exact \`action\` names in proposed intents)
${actionLines}

### Taxonomy coordinates
- \`what\` — one of the object type names above (or "${grammar.defaultTaxonomyWhat}" as a default)
- \`how\` — the lifecycle stage, e.g. "lifecycle.report", "lifecycle.quote", "lifecycle.schedule"
- \`why\` — the motivation, e.g. "maintenance-request", "procurement", "compliance"
`;
}

```
