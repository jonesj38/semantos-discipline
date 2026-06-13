---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26D-ERRATA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.668593+00:00
---

# Phase 26D Errata — NetworkAdapter Interface & Overlay Composition

**Date**: 2026-04-01
**Phase**: 26D
**Branch**: `phase-26d-network-adapter`

---

## Adversarial Review

All new and modified files reviewed for correctness, type safety, and contract compliance.

### 1. StubNetworkAdapter txid determinism

**Status**: PASS

Txid format: `"stub" + counter.toString(16).padStart(60, '0')` produces a 64-character string matching txid length. Counter starts at 0, increments on each publish. JavaScript `Number` handles integers safely to 2^53, so overflow is not a concern for any practical workload.

Verified: `stub` + `000...001` through `stub` + `000...00N` are unique and sequential.

### 2. Subscribe callbacks fire AFTER publish stores

**Status**: PASS

In `StubNetworkAdapter.publish()`, the call order is:
1. Generate txid
2. Build NetworkResult
3. Store in `this.objects` map
4. Build PublishResult
5. Fire subscriber callbacks
6. Return PublishResult

Subscribers see the stored object when their callback fires.

### 3. Resolve respects limit

**Status**: PASS

`resolve()` breaks iteration when `results.length >= limit`. Default limit is 10. Tested with T6 (publish 5 objects, limit=2 returns exactly 2).

### 4. BsvOverlayNetworkAdapter public API type safety

**Status**: PASS

All public method signatures use only types from `network.ts` (primitive types and NetworkAdapter-defined interfaces). Internal methods (`decodeAnswerToResults`, `fireSubscribers`, `topicForObject`) are `private` and may use @bsv/sdk types internally. The `LookupAnswer` import is used only in the private method signature — it does not appear in any public method parameter or return type.

### 5. BsvOverlayAdapter.write() unchanged

**Status**: PASS

Only the module-level JSDoc comment was modified (added storage/network separation documentation and cross-reference to `bsv-overlay-network-adapter.ts`). No changes to method signatures, implementation, or behavior.

### 6. StorageAdapter and NetworkAdapter test independence

**Status**: PASS

`phase26d-gate.test.ts` imports from `memory-adapter.ts` and `stub-network-adapter.ts` separately. No test imports both a StorageAdapter test and a NetworkAdapter test helper.

### 7. No `any` casts at adapter boundary

**Status**: PASS

Searched all new files for `as any` — none found. Type safety maintained throughout.

### 8. ownerCert field semantics

**Status**: KNOWN CONCERN (low severity)

In `BsvOverlayNetworkAdapter.decodeAnswerToResults()`, the `ownerCert` field is derived from `output.ownerPubKey.toString()`. This produces a hex-encoded compressed public key string. The `ownerCert` field in `NetworkResult` is documented as "Owner cert ID" which is intentionally vague — it's a string identifier. The exact format depends on the identity system in use:

- In overlay mode: hex-encoded compressed public key
- In stub mode: whatever string the caller passes
- In Phase 26E (node bootstrap): mapped to IdentityAdapter cert IDs

No action required now. Phase 26E will define the canonical cert ID format.

### 9. hexToBytes input validation

**Status**: ACCEPTABLE (low severity)

`hexToBytes()` in `bsv-overlay-network-adapter.ts` does not validate that the input hex string has even length. Odd-length strings would silently truncate. This is acceptable because:
- The function is private to the adapter
- All callers pass content hashes (64-char hex = 32 bytes)
- The function matches the same pattern used in `bsv-overlay-adapter.ts`

---

## Summary

| Item | Status | Severity |
|------|--------|----------|
| Txid determinism | PASS | — |
| Subscribe timing | PASS | — |
| Resolve limit | PASS | — |
| Public API types | PASS | — |
| BsvOverlayAdapter unchanged | PASS | — |
| Test independence | PASS | — |
| No `any` casts | PASS | — |
| ownerCert semantics | Known concern | Low |
| hexToBytes validation | Acceptable | Low |

**Zero MUST FIX items. Two low-severity observations documented for Phase 26E.**
