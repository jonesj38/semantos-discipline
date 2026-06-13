---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/gradient/oddjobz_extension_context.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.876688+00:00
---

# archive/apps-semantos-monolith/lib/src/gradient/oddjobz_extension_context.dart

```dart
// 2026-05-07 — oddjobz extension constants + helpers for the on-device
// L1→L4 pipeline.  Decouples the production-deps factory from
// hard-coded magic numbers.
//
// The constants here mirror the canonical capability page declared at
// `extensions/oddjobz/src/capabilities.ts` (`0x000101xx`).  Bumping
// either side without bumping the other will cause `K3 domain
// mismatch` rejections at the kernel — keep them in lock-step.

import '../identity/child_cert_store.dart';
import 'dart_pipeline.dart';

/// Canonical oddjobz extension page used as the per-extension domain
/// flag in `PipelineHatContext`.  Matches the `0x000101xx` page in
/// `extensions/oddjobz/src/capabilities.ts`.  Specific caps differ in
/// the low byte (e.g. `cap.oddjobz.quote = 0x00010101`); the
/// intent-level domain flag is the page itself.
const int kOddjobzDomainFlag = 0x00010100;

/// Canonical extension id used in Intent emission + brain-side
/// validation.
const String kOddjobzExtensionId = 'oddjobz';

/// Maximum trust class a paired phone can claim from the typed-NL
/// path.  The phone is always cert-bound but never running formal
/// proofs locally, so the ceiling is `interpretive` (per the TS
/// `defaultTrustCeiling` rule for cert-bound hats without proof
/// machinery).  Tests can override.
const String kOddjobzMaxTrustClass = 'interpretive';

/// Build a `PipelineHatContext` from the operator's persisted child
/// cert record.  The pipeline consumes this to gate K3 (domain) +
/// trust-class lowering during SIR → OIR.
PipelineHatContext oddjobzPipelineHatContext(ChildCertRecord record) {
  return PipelineHatContext(
    hatId: record.operatorCertId,
    certId: record.childPubHex,
    domainFlag: kOddjobzDomainFlag,
    maxTrustClass: kOddjobzMaxTrustClass,
    extensionId: kOddjobzExtensionId,
  );
}

```
