---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/browser.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.367316+00:00
---

# runtime/shell/src/browser.ts

```ts
/**
 * Browser-safe entry point for @semantos/shell.
 *
 * Re-exports only the parser, router, capability helpers, and types —
 * no Node.js dependencies (readline, net, process.argv, FUSE, tmux).
 * Import as '@semantos/shell/browser' from browser code.
 */

export { parseCommand, KNOWN_VERBS } from './parser';
export type { ShellCommand, ShellVerb } from './parser';
export { route } from './router-browser';
export { CAPABILITY_MAP, getRequiredCapability, getCapabilityName, MUTATION_VERBS } from './capabilities';
export type { ShellContext } from './types';
export { extractShellCommand } from './host-exec/extractor';
export type { ExtractResult, ExtractedCommand, ExtractError, ExtractorContext, LlmClient } from './host-exec/extractor/types';
export { listHandlers } from './host-exec/registry';
export type { HandlerManifest } from './host-exec/types';

// Side-effect import: populates the host-exec registry with handler
// manifests (pure data, no node:* imports) so the LLM and fallback
// extractor see the allowlist. Server tier pulls in
// `./host-exec/handlers` instead to also attach the impl fns.
import './host-exec/handlers/manifests';

```
