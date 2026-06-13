---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-36C-ERRATA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.682536+00:00
---

# Phase 36C Errata — Schema Inference Agent

**Date**: 2026-04-12
**Status**: Implementation complete

---

## Edge Cases Discovered

### E1: Singularize "leases" → "leas" (Fixed)

The naive singularize function treated "leases" as ending in "ses" and stripped 2 characters, producing "leas" instead of "lease". Fixed by checking for specific English plural endings (`-ches`, `-shes`, `-xes`, `-zes`, `-sses`) before applying the general `-s` strip. Standard `-es` plurals like "leases" now correctly strip only the final "s".

### E2: Over-aggressive Enum Detection (Fixed)

With small sample sizes (3 responses), string fields with 3 unique values were classified as enum (e.g., "street_address" with 3 different addresses). Fixed by requiring that the number of unique values must be **strictly less than** the total sample count — if every value is unique, the field is free-form text, not an enum. Also requires at least 2 unique values.

### E3: Context Window Trap for Large APIs

When pointing the agent at monolithic APIs (e.g., Salesforce with 300+ custom fields per entity), the TaxonomyMapper would send all fields to the LLM, overflowing the context window and wasting tokens. Addressed by implementing `selectSemanticFields()` which:
- Caps field list at 20 fields per entity (`MAX_FIELDS_IN_PROMPT`)
- Prioritizes enum, date, and named string fields over boolean flags and ID fields
- Strips generic `_id` and `id` fields from the LLM context

---

## Verification Results

### Confidence Scoring

- All StructureAnalyzer outputs include per-field `detectionConfidence` (0.0–1.0)
- TaxonomyMapper produces per-axis confidence for WHAT/HOW/WHY
- GrammarDiffEngine computes `fieldOverlapPercent` and match `confidence`
- GrammarComposer collects all sub-threshold inferences into `lowConfidenceFlags`

### Evidence Chain Completeness

Each AFFINE draft object includes:
- `schema_inferred` patch: grammarId, entity/relationship counts, sample hashes, inference parameters
- `taxonomy_mapped` patch: per-entity WHAT/HOW/WHY with confidence + LLM reasoning
- `validation_result` patch (if errors): validation errors from `validateExtensionGrammar()`
- Approval/rejection patches added by `semantos infer approve|reject`

### Safety Invariants

- No LLM calls outside `taxonomy-mapper.ts` and `llm-client.ts` (verified by grep scan)
- No auto-publish or AFFINE→RELEVANT transitions without explicit `--publish` flag
- No credentials stored in grammar objects, evidence chains, or shell history
- All inferred grammars validated via `validateExtensionGrammar()` before return

---

## Test Summary

| Test | Description | Status |
|------|-------------|--------|
| T1 | Entity boundary detection | PASS |
| T2 | Field type inference | PASS |
| T3 | ID/timestamp/relationship detection | PASS |
| T4 | TaxonomyMapper with confidence scores | PASS |
| T5 | Confidence threshold classification | PASS |
| T6 | Pre-filter fallback paths | PASS |
| T7 | Field overlap matching (>70%) | PASS |
| T8 | New entity identification | PASS |
| T9 | Type mismatch detection | PASS |
| T10 | Grammar validation pass | PASS |
| T11 | Low-confidence flag inclusion | PASS |
| T12 | Full pipeline execution | PASS |
| T13 | AFFINE object + evidence chain | PASS |
| T14 | Shell command parsing | PASS |

All 14 gate tests pass. `bun run check` and `bun run build` succeed with zero errors. No regressions in existing test suite (Phase 36A: 70/70 pass).
