---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-contracts/src/identity.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.820929+00:00
---

# core/plexus-contracts/src/identity.ts

```ts
/**
 * Plexus identity and certificate types — re-export shim.
 *
 * W1.5C-1: The canonical home for these types has been promoted to
 * `@semantos/protocol-types` (core/protocol-types/src/identity.ts).
 *
 * This file re-exports all symbols from the canonical location so that
 * existing callers importing from `@plexus/contracts` continue to work
 * without code changes.
 *
 * Spec source: docs/spec/protocol-v0.5.md §4.2 (BRC-52 cert format),
 *              §4.4 (identity DAG), §12.1 (SignedBundle envelope).
 * Canon discipline: aliases per docs/canon/glossary.yml; cert_id
 *   (snake_case) is the wire form; certId (camelCase) is TS convention.
 *
 * New code MUST import directly from `@semantos/protocol-types` (or the
 * `@semantos/protocol-types/identity` subpath).
 *
 * Cross-language conformance: Elixir mirror at
 * runtime/world-beam/apps/world_host/lib/world_host/identity.ex produces byte-identical
 * canonicalCertPreimage output for all conformance vectors.
 */

// ── Re-exports from canonical home ───────────────────────────────────────────
// Each symbol is re-exported with a @deprecated JSDoc note to guide
// new callers to the canonical import path.

/**
 * @deprecated Re-exported from @semantos/protocol-types; import directly from there in new code.
 */
export type {
  Brc52Cert,
  Brc52Certificate,
  CertIdPreimage,
  CertificatePreimage,
  PlexusCert,
  CertRegistrationRequest,
  CertRegistrationResult,
  CertRegistrationErrorCode,
  Brc100Headers,
  SignedBundle,
  IdentityProvider,
} from "@semantos/protocol-types";

/**
 * @deprecated Re-exported from @semantos/protocol-types; import directly from there in new code.
 */
export { canonicalCertPreimage, computeCertId } from "@semantos/protocol-types";

```
