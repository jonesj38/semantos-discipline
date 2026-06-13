---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/policy-runtime/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.491339+00:00
---

# packages/policy-runtime/src/index.ts

```ts
/**
 * @semantos/policy-runtime — shared policy evaluation for extension grammars.
 *
 * Every extension grammar (CDM, SCADA, BoL, ...) routes compiled policy
 * bytecode through PolicyRuntime.evaluate(), which invokes the WASM 2-PDA
 * kernel with OP_CALLHOST dispatching to domain-specific host functions.
 *
 * Phase 29.5 / D29.5.1
 */

export { PolicyRuntime } from './runtime';
export type { PolicyRuntimeOptions } from './runtime';
export type { PolicyContext, PolicyResult, HostCallRecord, HostFunctionProvider } from './types';
export { DevModeAnchorEmitter } from './anchor-emitter';
export type { AnchorEmitter, AnchorOptions, AnchorResult } from './anchor-emitter';

// Lexicon authority gate — D-A6 (matrix cell A7×A). Extensions that
// mint capabilities or define lexicons must declare a BRC-52-anchored
// authority cert + grammar signature; the runtime refuses to register
// an extension whose authority cert fails verification.
export {
  ExtensionAuthorityError,
  StubAuthorityVerifier,
  RejectAuthorityVerifier,
} from './authority';
export type {
  Brc52CertRef,
  LexiconAuthority,
  AuthorityVerifier,
  AuthorityVerificationResult,
  AuthorityErrorCode,
  LoadedExtensionAuthority,
} from './authority';

```
