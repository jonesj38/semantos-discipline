---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-19.5-ERRATA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.697934+00:00
---

# Phase 19.5 Errata — Shell Plexus Auth

**Date**: 2026-03-30
**Branch**: `claude/elastic-mirzakhani` (worktree)
**Status**: Complete

---

## Errata Checklist

### 1. Capability flags match PLEXUS-INTEGRATION-MAP.md

Verified. All domain flags in `packages/shell/src/capabilities.ts` match the spec:

| Verb | Expected Flag | Actual Flag | Status |
|------|--------------|-------------|--------|
| new | 0x00010002 (Create) | 0x00010002 | OK |
| patch | 0x00010003 (Edit/Patch) | 0x00010003 | OK |
| revoke | 0x00010004 (Delete/Revoke) | 0x00010004 | OK |
| publish | 0x00010005 (Publish) | 0x00010005 | OK |
| vote | 0x00010006 (Govern Vote) | 0x00010006 | OK |
| dispute | 0x00010007 (Govern Propose) | 0x00010007 | OK |
| stake | 0x00010008 (Stake) | 0x00010008 | OK |
| transfer | 0x00010009 (Transfer) | 0x00010009 | OK |

### 2. Identity commands are NOT hardcoded

Verified. `packages/shell/src/identity.ts`:
- `routeIdentity()` calls `ctx.plexus.registerIdentity()`, `ctx.plexus.deriveChild()`, `ctx.plexus.resolveIdentity()`, `ctx.plexus.querySubtree()`
- No hardcoded cert IDs, facet IDs, or test fixtures
- No `localStorage`, `new Map()`, or any identity storage

### 3. Capability checks are NOT bypassed anywhere

Verified. `packages/shell/src/router.ts`:
- Unified check at top of `route()`: `if (MUTATION_VERBS.has(cmd.verb))` → `checkPlexusCapability()`
- All 8 mutation verbs are in `MUTATION_VERBS` set
- `--dry-run` STILL checks capabilities (shows result without executing)
- Read-only verbs (inspect, trace, verify, list, whoami, capabilities) skip the check

### 4. SEMANTOS_FACET env var is ACTUALLY read (not mocked)

Verified. `packages/shell/src/config.ts`:
- `process.env.SEMANTOS_FACET` is read directly at line ~104
- Gate test T1 sets `process.env.SEMANTOS_FACET = "facet-456"` and calls `loadConfig()` — real env var, not mocked
- Gate test T3 deletes the env var and confirms `activeFacetId = null`

### 5. sendAuthenticated() is called for identity operations

Verified. `packages/shell/src/router.ts`:
- `routeIdentityWithAuth()` wraps `routeIdentity()` with a `ctx.plexus.sendAuthenticated()` call
- The `case 'identity':` in `route()` dispatches to `routeIdentityWithAuth` (not `routeIdentity` directly)
- In stub mode, `sendAuthenticated()` returns a deterministic messageId (echo behavior)

### 6. PLEXUS_MODE and PLEXUS_ENDPOINT env vars

Verified. Both env vars are read in `config.ts` and override TOML config values.

---

## Deviations from PRD

### sendAuthenticated() signature

The PRD execution prompt describes `sendAuthenticated(endpoint, payload)` but the actual `PlexusAdapter` interface (Phase 14 source of truth) uses `sendAuthenticated(senderCertId, receiverCertId, payload)`. Implementation follows the actual interface.

### Dry-run behavior

The PRD suggests per-verb dry-run handling. Implementation uses unified dry-run at the top of `route()` for mutation verbs — this is cleaner and ensures no mutation verb can accidentally bypass the dry-run check.

### Capability check: dual-layer

Implementation checks capabilities through both PlexusService.presentCapability() (Plexus domain flags) and IdentityStore local capabilities (legacy numbers). This belt-and-suspenders approach ensures that even if the stub always returns `{ valid: true }`, the local capability set is still verified.

---

## Test Results

- Phase 19.5 gate tests (T1-T8): **35 pass, 0 fail**
- Phase 19 gate tests (updated): **41 pass, 0 fail**
- `bun run check`: **0 TypeScript errors**
- `bun run build`: **success**
