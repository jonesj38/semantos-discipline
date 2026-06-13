---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/verb-registry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.088439+00:00
---

# runtime/services/src/verb-registry.ts

```ts
/**
 * Verb registry — extension-provided shell command dispatch.
 *
 * Same shape as runtime/shell/src/host-exec/registry.ts, but for the
 * shell's verb-routing layer rather than HOST_EXEC handlers. Lives
 * here in runtime-services (not in shell) so:
 *
 *   - extensions can import it to register their verbs without
 *     creating an extensions → shell dependency
 *   - shell can import it to look up handlers without creating a
 *     shell → extensions dependency
 *
 * Both ends now talk to a neutral runtime-services package, which both
 * tiers are allowed to import.
 *
 * Lifecycle:
 *
 *   At module load time, an extension's shell-handler file calls
 *
 *     registerVerb('cdm', routeCDM);             // bare form
 *
 *   or, for lexicon-aware dispatch,
 *
 *     registerVerb({
 *       name: 'acknowledge_alarm',
 *       category: { lexicon: 'control-systems', category: 'acknowledgement' },
 *       action: 'acknowledge_alarm',
 *       mutation: true,
 *       handler: routeAcknowledgeAlarm,
 *     });
 *
 *   At runtime, shell's router.ts does
 *
 *     const handler = getVerb('cdm');
 *     return handler ? handler(cmd, ctx) : null;
 *
 *   The intent pipeline's shell-to-intent adapter calls
 *
 *     const reg = getVerbRegistration('acknowledge_alarm');
 *     // reg.category is TaggedCategory, ready for Intent.category
 *
 *   The binary entry point (currently runtime/shell/src/index.ts,
 *   eventually moving to apps/) triggers extension loads via dynamic
 *   imports based on the configs/extensions/ enabled list. Dynamic
 *   imports with template-literal specifiers are deliberate: they
 *   keep static-import-graph analysis (including the import-boundary
 *   gate) clean while letting the binary actually load extensions.
 */

import type { TaggedCategory } from "@semantos/semantos-sir";

/** A verb handler is a function that takes a parsed shell command + context and returns a result. */
export type VerbHandler = (cmd: unknown, ctx: unknown) => unknown | Promise<unknown>;

/**
 * Full verb registration — carries the (lexicon, category, action)
 * triple the intent pipeline needs to build a typed Intent.
 *
 * `category` is a `TaggedCategory` — a discriminated union with one
 * branch per lexicon (jural / control-systems / cdm / bills-of-lading
 * / project-management / property-management / risk-assessment /
 * circuit-commands). Each branch keeps its strict per-lexicon
 * category enum, so TypeScript rejects mis-pairings at compile time.
 */
export interface VerbRegistration {
  /** Verb name — matches ShellCommand.verb after parsing. */
  name: string;
  /** (lexicon, category) pair. See TaggedCategory in @semantos/semantos-sir. */
  category: TaggedCategory;
  /** The Intent.action this verb produces. Often equal to `name`. */
  action: string;
  /** True if the verb mutates state (and so should route through the pipeline). */
  mutation: boolean;
  /** Dispatcher called by shell's router. */
  handler: VerbHandler;
}

const registry = new Map<string, VerbRegistration>();

/**
 * Register a verb. Two shapes are accepted:
 *
 *   1. Full: `registerVerb({ name, category, action, mutation, handler })`
 *      — preferred form; carries the metadata the intent pipeline
 *      needs to build a typed Intent without a hardcoded verb table.
 *
 *   2. Bare: `registerVerb(name, handler)` — backward-compat shim.
 *      Defaults to `{ lexicon: 'jural', category: 'declaration' }` +
 *      `mutation: true`. Existing extensions keep working; they
 *      should migrate to the full form when they touch their
 *      shell-handler next and want category-accurate intent
 *      dispatch.
 *
 * Throws on duplicate name — double-registration is a programmer bug.
 */
export function registerVerb(
  nameOrReg: string | VerbRegistration,
  maybeHandler?: VerbHandler,
): void {
  const reg: VerbRegistration =
    typeof nameOrReg === "string"
      ? {
          name: nameOrReg,
          category: { lexicon: "jural", category: "declaration" },
          action: nameOrReg,
          mutation: true,
          handler: maybeHandler as VerbHandler,
        }
      : nameOrReg;

  if (registry.has(reg.name)) {
    throw new Error(
      `Verb '${reg.name}' is already registered. ` +
        `Double-registration is a bug — check that the extension isn't being loaded twice.`,
    );
  }
  registry.set(reg.name, reg);
}

/**
 * Look up a verb handler by id. Returns null if not registered.
 *
 * Shell's router calls this after parsing the command's verb. A null
 * result means the verb is unknown (either no extension provides it,
 * or the providing extension wasn't loaded).
 */
export function getVerb(verb: string): VerbHandler | null {
  const reg = registry.get(verb);
  return reg ? reg.handler : null;
}

/**
 * Look up a verb's full registration (not just the handler). Returns
 * null if not registered. Used by the intent pipeline's shell adapter
 * (`shellCommandToIntent`) to build a typed Intent without a hardcoded
 * verb → category table.
 */
export function getVerbRegistration(verb: string): VerbRegistration | null {
  return registry.get(verb) ?? null;
}

/**
 * List all currently-registered verb ids. Useful for shell's
 * `help` and tab-completion.
 */
export function listVerbs(): string[] {
  return Array.from(registry.keys()).sort();
}

/** List full registrations — for discovery / help output / docs generation. */
export function listVerbRegistrations(): VerbRegistration[] {
  return Array.from(registry.values());
}

/**
 * Clear all registrations — for tests only.
 */
export function _clearVerbRegistry(): void {
  registry.clear();
}

```
