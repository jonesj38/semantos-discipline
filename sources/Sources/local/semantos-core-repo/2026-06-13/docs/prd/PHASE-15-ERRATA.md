---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-15-ERRATA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.702533+00:00
---

# Phase 15 Errata

**Date**: 2026-03-30
**Phase**: 15 — Production Plexus SDK Integration
**Status**: Implementation complete, errata sprint done

## Scope Notes

Phase 15 was implemented with LOCAL workspace packages (`@plexus/contracts`, `@plexus/vendor-sdk`) because the real Dusk Inc packages are not yet published on npm. The local packages use real BSV crypto via `@bsv/sdk` v2.0.13, making the implementation functionally equivalent to what the real SDK will provide. When Dusk ships, swap the local packages for the real ones (see swap path in plan).

## Issues Found

### E15.1: PBKDF2 iteration count varies by mode

**File**: `packages/loom/src/plexus/real.ts:38`
**Issue**: The RealPlexusAdapter uses 1,000 PBKDF2 iterations for `:memory:` mode and 100,000 for persistent DBs. This is intentional for test performance but means in-memory tests and persistent-DB runs produce DIFFERENT certIds for the same email.
**Severity**: Low (test-only concern)
**Fix**: Document this behavior. When Dusk ships their SDK, their iteration count will be authoritative. The adapter always passes through to the SDK's config.

### E15.2: `presentCapability` is a pass-through (always valid)

**File**: `packages/plexus-vendor-sdk/src/VendorSDK.ts:159`
**Issue**: `presentCapability()` always returns `{ valid: true }` in local mode. Real Plexus will do SPV checks on BRC-108 UTXO capability tokens.
**Severity**: Expected — matches stub behavior. Phase 16 will wire real capability verification.
**Fix**: No action needed until Phase 16.

### E15.3: `sendAuthenticated` has no real transport

**File**: `packages/plexus-vendor-sdk/src/VendorSDK.ts:178`
**Issue**: `sendAuthenticated()` just computes a deterministic messageId without actually sending anything. Real Plexus Network SDK will handle BRC-100 transport.
**Severity**: Expected — local mode has no server to talk to.
**Fix**: Phase 16 will integrate the Network SDK.

### E15.4: Recovery challenges are hardcoded

**File**: `packages/plexus-vendor-sdk/src/VendorSDK.ts:131`
**Issue**: The recovery flow uses 4 hardcoded challenge questions (same as stub). Real Plexus Identity Domain will generate user-specific challenge sets with server-stored SHA-256 hashed answers.
**Severity**: Low — matches stub behavior for parity.
**Fix**: Will be replaced when Dusk SDK ships with real Identity Domain integration.

### E15.5: No `derivationPath` in PlexusAdapter return values

**File**: `packages/loom/src/plexus/types.ts:96`
**Issue**: The PRD's execution prompt shows `deriveChild` returning `derivationPath`, but the actual Phase 14 PlexusAdapter interface doesn't include it. The VendorSDK tracks derivation paths internally but doesn't expose them through the adapter.
**Severity**: Low — the loom doesn't need derivation paths; they're Plexus internals.
**Fix**: No change to interface (Phase 14 contract is frozen). If needed later, add a separate `getDerivationPath(certId)` method.

## Items Verified Clean

1. Every method in `RealPlexusAdapter` delegates to `VendorSDK` — no stubs, no fallbacks
2. Every `catch` block wraps errors as `PlexusError` with code, message, recoverable
3. Same email → same certId across adapter instances (BRC-42 determinism verified by T29, T34)
4. No `PlexusCert`, `PlexusNode`, `BRC52Certificate` types leak outside `real.ts` (T32, T33)
5. All 12 adapter methods are implemented (9 in PlexusAdapter + 3 internal SDK methods)
6. `@plexus/*` imports appear ONLY in `real.ts` (T33 enforces this)
7. Phase 14 tests T1-T20 pass unchanged (regression verified)
8. `PLEXUS_MODE=stub` and `PLEXUS_MODE=local` both work via `createAdapter()` (T30)
