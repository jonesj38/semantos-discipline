---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/intent-adapters/sizing-prompt.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.457155+00:00
---

# packages/extraction/src/intent-adapters/sizing-prompt.ts

```ts
/**
 * Sizing-questions + extraction-field-rules prompt addendum — CANONICAL.
 *
 * Cherry-picked from runtime/shell/src/chat/prompt-builders.ts during
 * the REPL-canonicalisation pass (graft-before-cut). The shell relic
 * carried two pieces of extraction richness with NO canonical
 * equivalent in system-prompt.ts:
 *
 *   1. `buildSizingQuestionsPrompt` — renders a per-category sizing
 *      block (required/optional questions, prompts, and the
 *      sizing→effortBand `effortMap`) so the LLM asks the right
 *      sizing questions and sets a ROM-computable `effortBand`.
 *   2. `ODDJOBZ_EXTRACTION_FIELD_RULES` — the enum/taxonomy coercion
 *      constraints (categoryPath→taxonomy, effortBand enum, urgency
 *      enum, estimateType enum, cost numerics) that keep extracted
 *      fields aligned with what extensions/oddjobz/src/rom.ts
 *      (calculateROM) and the Estimate cell consume.
 *
 * Deliberately a SEPARATE composable addendum — it is NOT folded into
 * `buildClassifierSystemPrompt`, which must stay byte-stable per
 * grammar for the call-site's ephemeral prompt cache (see
 * system-prompt.ts header). An oddjobz Intent producer appends this
 * block to the classifier call; the generic triage prompt is
 * unchanged. Keep in lock-step with the shell copy until the shell
 * chat/ subtree is deprecated, then the shell copy is deleted.
 *
 * Pure. No I/O. Verbatim logic from the shell `buildSizingQuestionsPrompt`.
 */

/** Enum/taxonomy coercion rules that keep extracted fields aligned
 *  with the ROM calculator + Estimate cell. Append to a producer's
 *  system prompt; do not interpolate into the cached classifier
 *  prompt. */
export const ODDJOBZ_EXTRACTION_FIELD_RULES = `IMPORTANT EXTRACTION RULES:
- categoryPath MUST map to the taxonomy: services.trades.plumbing, services.trades.carpentry, etc.
- urgency MUST be one of: emergency, urgent, next_week, next_2_weeks, flexible, when_convenient
- effortBand MUST be one of: quick, short, quarter_day, half_day, full_day, multi_day
- estimateType MUST be one of: auto_rom, operator_rom, formal_quote
- costMin and costMax are numbers (dollars)
- Extract everything you can from a single message. Don't make the user repeat themselves.`;

/**
 * Render the per-category sizing-questions block. Verbatim port of
 * the shell `buildSizingQuestionsPrompt` (pure: takes the pricing
 * policy's `sizingQuestions` map, returns prompt text). `_`-prefixed
 * keys are skipped except `_default`, which is rendered as the
 * fallback "For any other category" block.
 */
export function buildSizingQuestionsPrompt(
  sizingQuestions: Record<string, unknown>,
): string {
  const lines: string[] = [
    '\nSIZING QUESTIONS (ask BEFORE creating a Job):',
    'Each category has required questions to determine the effort band accurately.',
    "Ask these conversationally — weave 2-3 into a natural reply. Don't interrogate.",
    'Once answered, use the effortMap to set the right effortBand on the Job.',
    '',
  ];

  for (const [category, config] of Object.entries(sizingQuestions)) {
    if (category.startsWith('_')) continue;
    const cfg = config as Record<string, unknown>;
    const required = cfg.required as string[] | undefined;
    if (!required) continue;

    lines.push(`${category}:`);
    lines.push(`  Required: ${required.join(', ')}`);
    const optional = cfg.optional as string[] | undefined;
    if (optional?.length) lines.push(`  Optional: ${optional.join(', ')}`);
    const prompts = cfg.prompts as Record<string, string> | undefined;
    if (prompts) {
      for (const [field, prompt] of Object.entries(prompts)) {
        lines.push(`    ${field}: "${prompt}"`);
      }
    }
    const effortMap = cfg.effortMap as Record<string, string> | undefined;
    if (effortMap) {
      lines.push(`  Effort mapping:`);
      for (const [key, band] of Object.entries(effortMap)) {
        lines.push(`    ${key} → ${band}`);
      }
    }
    lines.push('');
  }

  const defaultCfg = sizingQuestions['_default'] as Record<string, unknown> | undefined;
  if (defaultCfg) {
    const required = defaultCfg.required as string[] | undefined;
    if (required) {
      lines.push('For any other category:');
      lines.push(`  Required: ${required.join(', ')}`);
      const prompts = defaultCfg.prompts as Record<string, string> | undefined;
      if (prompts) {
        for (const [field, prompt] of Object.entries(prompts)) {
          lines.push(`    ${field}: "${prompt}"`);
        }
      }
      lines.push('');
    }
  }

  lines.push(
    'IMPORTANT: Do NOT create a Job until you have answers to the REQUIRED sizing questions for the category.',
  );
  lines.push(
    "Extract what you can from the first message. Only ask about what's still missing.",
  );
  lines.push(
    'If the homeowner provides enough info in one message (e.g. "3 bed single story"), go ahead and create the Job immediately.',
  );
  lines.push('');

  return lines.join('\n');
}

```
