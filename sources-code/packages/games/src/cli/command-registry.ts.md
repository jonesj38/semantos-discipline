---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/command-registry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.401167+00:00
---

# packages/games/src/cli/command-registry.ts

```ts
/**
 * CLI command registry for `semantos game …`.
 *
 * One entry per `(gameType, action)` pair. Each handler is a pure function
 * that takes a parsed ShellCommand + the game session and returns the
 * response payload (any JSON-serialisable value, including `{ error }`).
 *
 * Mirrors the cluster-3 policy-services pattern: register at boot, resolve
 * at call sites. The `routeGame` dispatcher in `commands/index.ts` looks
 * up `(gameType, action)` and invokes the handler.
 */

import type { ShellCommand } from '@semantos/shell/parser';

/** Argument descriptor used by the help renderer. */
export interface ArgSpec {
  /** Flag name without the leading `--` (e.g. `move`, `players`). */
  name: string;
  /** Short human-readable description. */
  description: string;
  /** Whether the arg is required. */
  required?: boolean;
}

/** A single CLI command (one `gameType` + one `action`). */
export interface CommandSpec {
  /** Game type — `chess`, `life`, `risk`, `dungeon`, `poker`. */
  game: string;
  /** Action / sub-command name — `new`, `move`, `status`, … */
  action: string;
  /** One-line summary used by the help renderer. */
  summary: string;
  /** Argument descriptors used by the help renderer. */
  args?: ArgSpec[];
  /** Handler — receives the parsed ShellCommand, returns the response. */
  handler: (cmd: ShellCommand) => Promise<unknown> | unknown;
}

/**
 * Internal map keyed by `${game}:${action}`. Module-private so callers
 * can only mutate via `registerCommand`.
 */
const REGISTRY = new Map<string, CommandSpec>();

function key(game: string, action: string): string {
  return `${game}:${action}`;
}

/** Register a single command. Last-write-wins (handy for tests). */
export function registerCommand(spec: CommandSpec): void {
  REGISTRY.set(key(spec.game, spec.action), spec);
}

/** Register many commands at once. */
export function registerCommands(specs: readonly CommandSpec[]): void {
  for (const spec of specs) registerCommand(spec);
}

/** Look up a command. Returns undefined if no matching entry exists. */
export function getCommand(game: string, action: string): CommandSpec | undefined {
  return REGISTRY.get(key(game, action));
}

/** List all registered commands in registration order (insertion order). */
export function listCommands(): CommandSpec[] {
  return [...REGISTRY.values()];
}

/** List the actions available for a game, in registration order. */
export function listActions(game: string): string[] {
  return listCommands()
    .filter((s) => s.game === game)
    .map((s) => s.action);
}

/** Test-only — wipe the registry. */
export function _resetRegistry(): void {
  REGISTRY.clear();
}

```
