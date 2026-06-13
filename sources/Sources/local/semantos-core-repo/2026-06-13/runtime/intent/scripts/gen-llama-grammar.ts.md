---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/scripts/gen-llama-grammar.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.339988+00:00
---

# runtime/intent/scripts/gen-llama-grammar.ts

```ts
#!/usr/bin/env bun
/**
 * D-O5m.followup-3 Phase 2 -- emit a GBNF grammar for the on-device
 * llama.cpp producer.
 *
 * Reference: runtime/intent/src/types.ts (the canonical Intent type
 *            this grammar reflects);
 *            core/semantos-sir/src/lexicons.ts (TaggedCategory branches --
 *            the small surface this Phase 2 producer targets);
 *            apps/oddjobz-mobile/lib/src/voice/sir_extractor.dart
 *            (the consumer -- bundles `intent.gbnf` as a Dart asset and
 *            passes it to LlamaService.complete());
 *            extensions/oddjobz/tools/voice-extract.ts
 *            (--sir-candidate path; the brain side runs the same
 *            structural validation against the grammar's JSON shape).
 *
 * Why a grammar?  GBNF is llama.cpp's native constrained-decoding
 * syntax -- every token the model samples is filtered by the grammar
 * automaton, so the model literally cannot emit a non-matching string.
 * The Intent JSON shape is enforced at the token level; field names,
 * nesting, and primitive types come out structurally valid by
 * construction.  Self-confidence and field-population checks happen
 * on the host side (sir_extractor.dart) where the grammar's "valid
 * JSON" guarantee meets domain-level "this Intent is plausible".
 *
 * Phase 2 stance:
 *   - The grammar covers the oddjobz `trades` lexicon explicitly.
 *     Other lexicons are reachable via the wider grammar in Phase 3
 *     once a pleb model can handle a larger vocab without losing
 *     accuracy.
 *   - Scope is the Intent shape pre-`processIntent`: id, summary,
 *     category, taxonomy, action, constraints, target, confidence,
 *     source.  `correlationId`, `companionOf`, `producerMeta`,
 *     `transferTo`, `fulfillment` are reachable via optional grammar
 *     branches (the Phase 2 producer rarely populates them).
 *
 * Usage:
 *
 *     bun runtime/intent/scripts/gen-llama-grammar.ts
 *
 * Writes the grammar to the runtime-owned canonical asset. Mobile/app bundles should copy or package this file rather than owning the source:
 *
 *     runtime/intent/assets/intent.gbnf
 */

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// GBNF grammar -- reads bottom-up.  Each rule is a llama.cpp grammar
// production matching part of the Intent JSON shape.  The grammar is
// intentionally narrow: trades-lexicon categories only, no nested
// composite constraints, single target.  Phase 3 widens it.
//
// NOTE: GBNF uses [a-z] character classes, ::= for productions,
// "literal" for terminals, and (a | b)+ for alternation/repetition.
const GRAMMAR = String.raw`# Intent -- top-level production.  Object with the keys produce_intent
# can populate; missing optional keys appear as omitted properties.
root ::= "{" ws
  "\"id\":" ws string ws "," ws
  "\"summary\":" ws string ws "," ws
  "\"category\":" ws category ws "," ws
  "\"taxonomy\":" ws taxonomy ws "," ws
  "\"action\":" ws string ws "," ws
  "\"constraints\":" ws constraints ws "," ws
  ("\"target\":" ws target ws "," ws)?
  "\"confidence\":" ws number ws "," ws
  "\"source\":" ws "\"voice\""
  ws "}"

# TaggedCategory -- Phase 2 surfaces the trades lexicon explicitly.
# The other lexicons land in Phase 3 once the producer copes with a
# wider vocabulary without losing accuracy.
category ::= "{" ws
  "\"lexicon\":" ws "\"trades\"" ws "," ws
  "\"category\":" ws trades-cat
  ws "}"

trades-cat ::= "\"lead\""
             | "\"estimate\""
             | "\"quote\""
             | "\"dispatch\""
             | "\"visit\""
             | "\"invoice\""
             | "\"settle\""
             | "\"message\""

# TaxonomyCoordinates -- what / how / why / (where).  All fields are
# strings; the where coordinate is optional.
taxonomy ::= "{" ws
  "\"what\":" ws string ws "," ws
  "\"how\":" ws string ws "," ws
  "\"why\":" ws string
  (ws "," ws "\"where\":" ws string)?
  ws "}"

# SIRConstraint[] -- Phase 2 supports a flat list of capability /
# domain / state / value / temporal constraints.  No composites.
constraints ::= "[" ws (constraint (ws "," ws constraint)*)? ws "]"

constraint ::= cap-constraint
             | dom-constraint
             | state-constraint
             | value-constraint
             | temporal-constraint
             | identity-constraint

cap-constraint ::= "{" ws
  "\"kind\":" ws "\"capability\"" ws "," ws
  "\"required\":" ws integer ws "," ws
  "\"name\":" ws string
  ws "}"

dom-constraint ::= "{" ws
  "\"kind\":" ws "\"domain\"" ws "," ws
  "\"flag\":" ws (integer | string)
  ws "}"

state-constraint ::= "{" ws
  "\"kind\":" ws "\"state\"" ws "," ws
  "\"requiredPhase\":" ws string
  ws "}"

value-constraint ::= "{" ws
  "\"kind\":" ws "\"value\"" ws "," ws
  "\"field\":" ws string ws "," ws
  "\"op\":" ws compare-op ws "," ws
  "\"value\":" ws (number | string)
  ws "}"

compare-op ::= "\"==\""
             | "\"!=\""
             | "\"<\""
             | "\">\""
             | "\"<=\""
             | "\">=\""

temporal-constraint ::= "{" ws
  "\"kind\":" ws "\"temporal\"" ws "," ws
  "\"op\":" ws ("\"before\"" | "\"after\"") ws "," ws
  "\"iso\":" ws string
  ws "}"

identity-constraint ::= "{" ws
  "\"kind\":" ws "\"identity\"" ws "," ws
  "\"ref\":" ws identity-ref
  ws "}"

identity-ref ::= "{" ws
  "\"type\":" ws ("\"role\"" | "\"hat\"" | "\"cert\"") ws "," ws
  "\"name\":" ws string
  ws "}"

# SIRTarget -- narrow shape for Phase 2 producer.
target ::= "{" ws
  ("\"objectId\":" ws string)?
  (ws "," ws "\"typePath\":" ws string)?
  (ws "," ws "\"equipmentId\":" ws string)?
  ws "}"

# Primitives.  The string rule mirrors RFC-8259 string content
# without escape-sequence variety beyond the basics -- keeps the
# automaton small.  Numbers are strict JSON numbers.
string ::= "\"" char* "\""
char ::= [^"\\\x00-\x1f] | "\\" escape
escape ::= ["\\/bfnrt] | "u" hex hex hex hex
hex ::= [0-9a-fA-F]

number ::= integer ("." [0-9]+)? ([eE] [-+]? [0-9]+)?
integer ::= "-"? ("0" | [1-9] [0-9]*)

ws ::= [ \t\n]*
`;

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const targets = [
  resolve(__dirname, '../assets/intent.gbnf'),
];

for (const target of targets) {
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, GRAMMAR);
  console.log(`wrote ${target}`);
}

```
