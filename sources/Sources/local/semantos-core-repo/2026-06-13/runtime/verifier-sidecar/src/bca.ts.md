---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/verifier-sidecar/src/bca.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.085659+00:00
---

# runtime/verifier-sidecar/src/bca.ts

```ts
/**
 * BCA derivation — thin re-export from the canonical D-A0 library.
 *
 * This file WAS the D-V3 minimum-viable port of `core/cell-engine/src/bca.zig`.
 * It is now a thin re-export: the canonical implementation lives at
 * `core/protocol-types/src/bca.ts` (@semantos/protocol-types, D-A0 deliverable).
 *
 * The `deriveBcaFromPubkey` export is preserved verbatim so that all callers
 * in `runtime/verifier-sidecar/src/server.ts` and
 * `runtime/verifier-sidecar/src/__tests__/server.test.ts` continue to work
 * without modification — behaviour is byte-identical to the D-V3 stub.
 *
 * Spec source: docs/spec/protocol-v0.5.md §4.3 (BCA derivation).
 * Canonical home: core/protocol-types/src/bca.ts.
 * Glossary: docs/canon/glossary.yml (id: bca).
 * K invariants: not directly enforced; produces the opaque peer-identifier
 * consumed by mesh, MFP, and World Host socket assigns.
 *
 * Import note: runtime→core relative imports are allowed per the
 * import-boundary gate (ALLOWED[runtime] = ["core", "runtime"]).
 */

export {
  deriveBca,
  verifyBca,
  deriveBcaFromPubkey,
  hexToBytes,
  bytesToHex,
  BCA_COLLISION_COUNT_MAX,
  BCA_DEFAULT_SUBNET_PREFIX,
  BCA_DEFAULT_MODIFIER,
  BCA_DEFAULT_SEC,
  BCA_DATA_SIZE,
  BCA_MODIFIER_SIZE,
  BCA_SUBNET_PREFIX_SIZE,
  BCA_PUBLIC_KEY_SIZE,
  BCA_IPV6_ADDRESS_SIZE,
} from "../../../core/protocol-types/src/bca.js";
export type { BcaInput, BcaResult } from "../../../core/protocol-types/src/bca.js";

```
