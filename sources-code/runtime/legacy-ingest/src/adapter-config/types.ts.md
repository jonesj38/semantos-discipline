---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/adapter-config/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.155888+00:00
---

# runtime/legacy-ingest/src/adapter-config/types.ts

```ts
/**
 * CC6.3a — Adapter-config metadata interface.
 *
 * The runtime shape of the per-source/per-operator data that CC6.3a
 * retires from hardcoded constants + per-agency rules inside the email
 * extractor. The DATA structure mirrors what CC6.2 carries in an
 * adapter-config cell's `metadata` field (`platform.adapter_config`
 * cell, `TAG_ADAPTER_CONFIG = 0x10`); once a brain-side read seam
 * exists, the same struct is what gets deserialized out of the cell
 * payload.
 *
 * For CC6.3a the data still lives in the legacy-ingest tree
 * (`runtime/legacy-ingest/src/adapter-config/default-oddjobz-config.ts`)
 * — the seam this file establishes is the dependency-injection point
 * that future work hooks into. The extractor consumes this interface,
 * not the constants, so adding a new operator/agency is a config
 * change with **zero** `extractor/` code edits (the CC6.3 acceptance
 * criterion).
 *
 * See:
 *   - `docs/design/CC6-SOURCE-ADAPTER-IMPL-SPEC.md` §5 + §6 row CC6.3
 *   - `runtime/semantos-brain/src/substrate_entity.zig`
 *     `SPEC_ADAPTER_CONFIG` (the cell-side counterpart from CC6.2)
 */

/**
 * Outcome of a matched billing rule. Drives `normaliseBillingParty()`'s
 * decision about which `ProposalBillingParty` shape to emit.
 *
 *   - `always_agency`               — emit `{type:'agency', name}` unconditionally.
 *   - `owner_if_named_else_agency`  — when the LLM extracted an `ownerName`,
 *                                     emit `{type:'owner', name: ownerName}`;
 *                                     otherwise fall back to agency.
 *   - `trust_llm_or_fallback_agency`— trust the LLM's billing_party if it
 *                                     emitted a non-empty agency name;
 *                                     otherwise emit `{type:'agency', name}`.
 */
export type BillingRuleOutcome =
  | { kind: 'always_agency'; agency_name: string }
  | { kind: 'owner_if_named_else_agency'; agency_name: string }
  | { kind: 'trust_llm_or_fallback_agency'; agency_name: string };

/**
 * How a billing-rule's source-domain match is expressed. `ends_with` is
 * the common case (a domain suffix like `cleverproperty.com.au`).
 * `regex` is for domains with structural variance the suffix form can't
 * capture (e.g. `robertjamesrealty.*`).
 */
export type DomainMatch =
  | { kind: 'ends_with'; suffix: string }
  | { kind: 'regex'; pattern: string };

/**
 * Optional per-agency LLM-prompt fragments (CC6.3b).
 *
 *   - `rules_section_text` — text shown after the colon in the
 *                            BILLING-rules section for this agency.
 *                            Free-form; replaces the prompt builder's
 *                            auto-generated outcome description.
 *   - `heuristic_text`     — text shown in the Phase-2
 *                            point-of-contact heuristics block for
 *                            this agency. Optional; agencies without a
 *                            specific routing pattern leave this
 *                            undefined.
 *
 * Both fields are LLM pedagogy — they SHOW the LLM the conventions of
 * the agency. They do not change the runtime normalisation logic in
 * `normaliseBillingParty()`; that is governed by `outcome` +
 * `domain_match` + `body_substrings`.
 *
 * When a `BillingRule` has no `prompt_fragments`, the prompt builder
 * synthesises a minimal rule-section entry from `agency_name` +
 * `domain_match` + `outcome` so the LLM still sees the rule, just
 * without operator-specific wording.
 */
export interface PromptFragments {
  readonly rules_section_text?: string;
  readonly heuristic_text?: string;
}

/**
 * One per-agency billing rule.
 *
 *   - `agency_name`      — human-readable; used in diagnostics + as the
 *                          `agency_name` in the `*_agency` outcomes.
 *   - `domain_match`     — primary trigger: match the lower-cased sender
 *                          domain. Tested in `Phase 1` of
 *                          `normaliseBillingParty()`.
 *   - `body_substrings`  — secondary trigger for bundle-fan-out emails
 *                          where the From-header is the operator's own
 *                          address. Lower-cased substring match against
 *                          `parsed.body`. Tested in `Phase 2`. Optional —
 *                          agencies without a body-text fingerprint
 *                          (e.g. Bricks + Agent) leave this undefined.
 *   - `outcome`          — what to emit when the rule fires.
 *   - `prompt_fragments` — CC6.3b: optional LLM-prompt pedagogy. See
 *                          `PromptFragments`. Absent → minimal
 *                          synthesised entry.
 */
export interface BillingRule {
  readonly agency_name: string;
  readonly domain_match: DomainMatch;
  readonly body_substrings?: readonly string[];
  readonly outcome: BillingRuleOutcome;
  readonly prompt_fragments?: PromptFragments;
}

/**
 * Top-level adapter-config metadata.
 *
 *   - `fallback_operator_emails` — supplementary to the `OPERATOR_EMAIL`
 *                                  env var; lower-cased addresses that,
 *                                  when present on the From-header of a
 *                                  bundle (≥2 PDFs) email, trigger
 *                                  fan-out.
 *   - `billing_rules`            — ordered. First match wins, in both the
 *                                  domain phase and the body-substring
 *                                  phase. Each phase iterates the rules
 *                                  once independently; an earlier rule
 *                                  matching by body-substring takes
 *                                  precedence over a later rule's
 *                                  domain match (Phase 1 is consulted
 *                                  before Phase 2, but within each
 *                                  phase the order is the rules' order).
 */
export interface AdapterConfigMetadata {
  readonly fallback_operator_emails: readonly string[];
  readonly billing_rules: readonly BillingRule[];
}

```
