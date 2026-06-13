---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/lisp/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.370628+00:00
---

# runtime/shell/src/lisp/index.ts

```ts
/**
 * Lisp axiom compiler — barrel export.
 *
 * Provides the s-expression parser, policy type system,
 * Lisp-to-script compiler, and capability cell packer.
 */

export { parseExpression, parseProgram, ParseError } from './parser';
export type { SExpression, Atom, List } from './parser';

export { LispCompiler } from './compiler';

export {
  interpretConstraint,
  interpretPolicy,
  validateConstraintFields,
} from './types';
export type {
  PolicyForm,
  IdentityRef,
  ConstraintExpr,
  ComparisonExpr,
  LogicalExpr,
  CapabilityExpr,
  DomainCheckExpr,
  TimeConstraintExpr,
  ScriptOutput,
  LinearityMode,
} from './types';

export { packCapabilityCell, unpackCapabilityCell } from './packer';
export type { PackOptions } from './packer';

```
