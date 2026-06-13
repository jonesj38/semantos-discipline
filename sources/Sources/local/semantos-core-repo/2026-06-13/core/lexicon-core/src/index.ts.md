---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/lexicon-core/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.819903+00:00
---

# core/lexicon-core/src/index.ts

```ts
/**
 * @semantos/lexicon-core — the foundational lexicon interface.
 *
 * Lifted out of `@semantos/semantos-sir` so downstream domain packages
 * (`@semantos/scg-relations`, and any future lexicon-authoring extension)
 * can depend on the interface and its runtime injectivity check without
 * pulling in the full SIR lowering stack. This breaks what would
 * otherwise be a `semantos-sir ↔ scg-relations` package cycle.
 *
 * The specific lexicons (`JuralLexicon`, `TradesLexicon`, `relationLexicon`,
 * etc.) continue to live in their owning packages. `@semantos/semantos-sir`
 * re-exports `Lexicon`, `verifyLexiconInjective`, and `isCategoryOf` from
 * here for backwards compatibility — existing consumers don't have to
 * migrate their imports.
 *
 * Formal correspondence (Lean 4):
 *   proofs/lean/Semantos/Substrate/Lexicon.lean
 *     — defines the `Lexicon` typeclass with the injectivity obligation
 */

/**
 * A lexicon: a named, finite category enum plus a header-rendering
 * function that MUST be injective on distinct categories. The
 * injectivity obligation is discharged formally in the Lean files for
 * each registered lexicon; `verifyLexiconInjective` is the runtime
 * dual, useful when constructing a lexicon dynamically (e.g. from a
 * plugin manifest).
 */
export interface Lexicon<Cat extends string = string> {
  /** Unique lexicon identifier. */
  readonly name: string;
  /** The complete, ordered set of categories in this lexicon. */
  readonly categories: ReadonlyArray<Cat>;
  /** Render a category to its canonical display header. Must be injective. */
  header(c: Cat): string;
}

/**
 * Runtime check that a lexicon's `header` function is injective on its
 * declared `categories`.
 *
 * Returns `{ injective: true }` on success, or `{ injective: false,
 * collisions: [...] }` listing the category pairs that share a header.
 */
export function verifyLexiconInjective<C extends string>(
  lex: Lexicon<C>,
): { injective: true } | { injective: false; collisions: Array<[C, C]> } {
  const seen = new Map<string, C>();
  const collisions: Array<[C, C]> = [];
  for (const c of lex.categories) {
    const h = lex.header(c);
    const prev = seen.get(h);
    if (prev !== undefined) collisions.push([prev, c]);
    else seen.set(h, c);
  }
  return collisions.length === 0
    ? { injective: true }
    : { injective: false, collisions };
}

/** Typeguard: is a category a member of a given lexicon? Useful when
    routing a `TaggedCategory` to the right render template. */
export function isCategoryOf<C extends string>(
  lex: Lexicon<C>,
  candidate: string,
): candidate is C {
  return (lex.categories as ReadonlyArray<string>).includes(candidate);
}

```
