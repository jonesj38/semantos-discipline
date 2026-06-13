---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-19.5-SHELL-PLEXUS-AUTH.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.702265+00:00
---

# Phase 19.5 — Shell Plexus Auth

**Version**: 1.0
**Date**: March 2026
**Status**: Pending Phase 19 gate
**Duration**: 1 week (with 2-day buffer)
**Prerequisites**: Phase 19 merged (shell scaffold exists), Phase 14 merged (PlexusAdapter + stub exists)
**Master document**: `SEMANTIC-SHELL-ARCHITECTURE.md`
**Branch**: `phase-19.5-shell-plexus-auth`

---

## Context

Phase 19 built the shell scaffold with command grammar, verb routing, and formatters. Phase 14 built the PlexusAdapter interface and StubPlexusAdapter, wiring identity derivation into the loom. This phase bridges them: the shell authenticates via Plexus identity, facet selection works through environment variables (like `AWS_PROFILE`), and all shell commands carry identity provenance through the Plexus capability system.

The shell now integrates with:
- **PlexusService**: for identity operations (register, derive, resolve)
- **IdentityStore**: to get active facet's capabilities
- **LoomStore**: all mutations now check capabilities before executing

Result: the shell is fully identity-aware. Commands can only be executed by facets with the required capabilities. Identity operations are accessible through the shell (`semantos identity register`, `semantos whoami`, etc.).

---

## Source Files / References

| Alias | Path | What to extract |
|-------|------|-----------------|
| `ARCH:SHELL` | `docs/prd/SEMANTIC-SHELL-ARCHITECTURE.md` | Command grammar, verb set, CLI identity integration |
| `PRD:SHELL` | `docs/prd/PHASE-19-SEMANTIC-SHELL.md` | Shell deliverables D19.1–D19.6 (already merged) |
| `SVC:PLEXUS` | `packages/loom/src/plexus/PlexusService.ts` | PlexusService API (registerIdentity, deriveChild, resolveIdentity) |
| `SVC:IDENTITY` | `packages/loom/src/services/IdentityStore.ts` | getActiveFacet(), getCapabilities(), getFacet() |
| `SVC:STORE` | `packages/loom/src/services/LoomStore.ts` | createObject(), applyPatch() with capability checks |
| `ADAPTER:TYPES` | `packages/loom/src/plexus/types.ts` | PlexusAdapter interface, capabilities, domain flags |
| `POLICY:BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming, branch rules |

---

## Deliverables

### D19.5.1 — SEMANTOS_FACET Environment Variable

**Modify file**: `packages/shell/src/config.ts`

Add environment variable support for facet selection (like `AWS_PROFILE`):

```typescript
export interface ShellConfig {
  adapterMode: 'stub' | 'local' | 'cloud';
  activeFacetId: string | null;
  activeFacetCertId: string | null;  // NEW: cert_id for capability checks
  defaultExtension: string;
  defaultFormat: OutputFormat;
  apiEndpoint?: string;
  plexusMode?: 'stub' | 'real' | 'cloud';
  plexusEndpoint?: string;
}

export function loadConfig(): ShellConfig {
  // 1. Load from ~/.semantos/config.toml or ./.semantos.toml
  // 2. Override with environment variables:
  //    - SEMANTOS_FACET: facet ID (e.g., "facet-3a2b")
  //    - SEMANTOS_EXTENSION: default extension
  //    - SEMANTOS_FORMAT: output format
  //    - SEMANTOS_MODE: stub|local|cloud
  //    - SEMANTOS_ENDPOINT: API endpoint
  //    - PLEXUS_MODE: stub|real|cloud (new)
  //    - PLEXUS_ENDPOINT: Plexus Control Plane endpoint (new)
  // 3. If SEMANTOS_FACET is set, resolve its cert_id via PlexusService
  // 4. Return merged config with both facetId and certId
}
```

Requirements:

- `SEMANTOS_FACET` env var acts like `AWS_PROFILE` — selects which identity context the shell runs in
- If not set, fall back to config file `active_facet` setting
- If neither set, use root identity (certId = null, meaning no active facet)
- Shell prompt updates to show active facet
- When facet changes, all subsequent commands are stamped with that facet's certId as provenance

Config file additions (TOML):

```toml
[shell]
active_facet = "facet-3a2b"           # Default facet if SEMANTOS_FACET not set

[plexus]
mode = "stub"                          # or "real" or "cloud"
endpoint = "http://localhost:9000"    # Plexus Control Plane endpoint
```

Commit: `phase-19.5/D19.5.1: SEMANTOS_FACET environment variable — facet selection like AWS_PROFILE`

---

### D19.5.2 — Shell Identity Integration

**Modify file**: `packages/shell/src/router.ts` and create `packages/shell/src/identity.ts`

Wire shell's verb router to use PlexusService for identity operations:

```typescript
// New shell commands for identity management
case 'identity':
  switch (cmd.flags.action) {
    case 'register':
      // semantos identity register <email>
      const email = cmd.objectId;  // Reuse objectId for email
      return await ctx.plexus.registerIdentity(email);
    case 'derive':
      // semantos identity derive <resource-id>
      const resourceId = cmd.objectId;
      return await ctx.plexus.deriveChild(
        ctx.activeFacetCertId,
        resourceId,
        0x00010001  // Client-defined domain flag for facets
      );
    case 'resolve':
      // semantos identity resolve <cert-id>
      const certId = cmd.objectId;
      return await ctx.plexus.resolveIdentity(certId);
    case 'list':
      // semantos identity list
      return await ctx.plexus.querySubtree(ctx.activeFacetCertId, 2);
  }
```

**New shell commands**:
- `semantos identity register <email>` — create new root identity via PlexusService
- `semantos identity derive <resource-id>` — create child facet under current identity
- `semantos identity resolve <cert-id>` — look up certificate details
- `semantos identity list` — list all facets under current identity
- `semantos whoami` — show current identity, facet, capabilities, cert_id

All identity commands work against stub adapter (no real Plexus required during Phase 19.5).

Commit: `phase-19.5/D19.5.2: Shell identity integration — register, derive, resolve, list commands`

---

### D19.5.3 — Capability-Gated Shell Commands

**Modify file**: `packages/shell/src/router.ts`

Every mutation verb now checks capabilities before executing:

```typescript
export async function route(cmd: ShellCommand, ctx: RouterContext): Promise<unknown> {
  // Before routing any mutation verb:
  const requiredCapability = getRequiredCapability(cmd.verb);

  if (requiredCapability !== null) {
    const canExecute = await ctx.identity.hasCapability(
      ctx.activeFacetCertId,
      requiredCapability
    );

    if (!canExecute) {
      return {
        error: `Missing capability: ${getCapabilityName(requiredCapability)} (${requiredCapability})`,
        hint: `Your facet does not have permission to ${cmd.verb}. ` +
              `You may need to switch to a different facet or request this capability.`
      };
    }
  }

  // Now route the command
  switch (cmd.verb) { ... }
}
```

Capability mapping (from PLEXUS-INTEGRATION-MAP.md):

| Verb | Capability | Flag |
|------|-----------|------|
| new | Create | 0x00010002 |
| patch | Edit/Patch | 0x00010003 |
| publish | Publish | 0x00010005 |
| revoke | Delete/Revoke | 0x00010004 |
| stake | Stake | 0x00010008 |
| vote | Govern (Vote) | 0x00010006 |
| dispute | Govern (Propose) | 0x00010007 |
| transfer | Transfer | 0x00010009 |

**New shell commands**:
- `semantos capabilities` — list active facet's capabilities
- `semantos <verb> --dry-run` — show capability checks without executing

Requirements:

- Every mutation verb checks capabilities via PlexusService.presentCapability()
- Failure returns error response (not exception): "Missing capability X to Y"
- Error message shows which capability is needed
- `--dry-run` flag shows what capabilities would be checked without executing
- Read-only verbs (inspect, trace, verify, list) don't require capabilities

Commit: `phase-19.5/D19.5.3: Capability-gated shell commands — every mutation checks before executing`

---

### D19.5.4 — BRC-100 Signed Requests (Prep for Phase 15)

**Modify file**: `packages/shell/src/router.ts`

When PlexusAdapter is in production mode (real or cloud), shell commands that hit the Plexus Control Plane are authenticated via BRC-100 signed HTTP:

```typescript
export async function route(cmd: ShellCommand, ctx: RouterContext): Promise<unknown> {
  // When executing identity operations or capability checks:

  // In stub mode: PlexusService.sendAuthenticated() echoes the payload (no-op)
  // In real/cloud mode: PlexusService.sendAuthenticated() signs with active facet's key

  const payload = {
    action: cmd.verb,
    facetCertId: ctx.activeFacetCertId,
    timestamp: new Date().toISOString(),
    data: { ... }
  };

  const response = await ctx.plexus.sendAuthenticated(
    ctx.config.plexusEndpoint || 'http://localhost:9000',
    payload
  );

  return response;
}
```

Config file additions (TOML):

```toml
[plexus]
mode = "stub"              # stub | real | cloud
endpoint = "http://localhost:9000"
```

Requirements:

- In `stub` mode: sendAuthenticated() returns the payload unchanged (no real signing)
- In `real` or `cloud` mode: wire to the real PlexusAdapter implementation (Phase 15)
- For Phase 19.5, you are just plumbing the config and passing through to the adapter
- Do NOT implement real BRC-100 signing — that's Phase 15
- When a shell command needs to verify capability with Plexus, it goes through sendAuthenticated()

Commit: `phase-19.5/D19.5.4: BRC-100 signed requests (prep for Phase 15) — config + adapter passthrough`

---

## Gate Tests (T1–T8)

Create `packages/__tests__/phase19.5-gate.test.ts`.

### Environment Variable Tests (T1–T3)

```
T1:  SEMANTOS_FACET env var selects correct facet
     Set: SEMANTOS_FACET=facet-456
     Result: config.activeFacetId = "facet-456"

T2:  Config file active_facet used when env var not set
     File: ~/.semantos/config.toml with active_facet = "facet-789"
     Env: not set
     Result: config.activeFacetId = "facet-789"

T3:  Root identity used when neither env var nor config set
     Env: not set
     File: no active_facet
     Result: config.activeFacetId = null
```

### Identity Commands Tests (T4–T5)

```
T4:  'semantos whoami' shows current identity with cert_id and capabilities
     Output includes: current facet ID, cert_id, list of capabilities
     Example: { facetId: "facet-3a2b", certId: "abc123...", capabilities: [2, 3, 5] }

T5:  'semantos identity register test@example.com' creates identity via PlexusService
     Calls: plexus.registerIdentity("test@example.com")
     Returns: { certId: "...", publicKey: "..." }
```

### Capability Check Tests (T6–T7)

```
T6:  'semantos publish job-1774' checks publish capability (5) before executing
     Facet has cap 5: command executes
     Facet missing cap 5: returns error (not exception)

T7:  Missing capability returns clear error message
     Output: { error: "Missing capability: publish (5)", hint: "..." }
     Does not throw exception, does not call LoomStore.transitionObject()
```

### Dry Run Test (T8)

```
T8:  '--dry-run' on mutation verb shows capability check result without executing
     Command: 'semantos publish job-1774 --dry-run'
     Output: { wouldExecute: true/false, requiredCapability: 5, hasCapability: true/false, ... }
     Verify: no actual object mutation occurs
```

---

## What NOT to Do

1. **Do NOT implement real BRC-100 auth.** Phase 15 does that. Just wire the adapter's sendAuthenticated() method.
2. **Do NOT bypass capability checks for any mutation verb.** Every mutation checks before executing.
3. **Do NOT create shell-specific identity storage.** Use PlexusService and IdentityStore exclusively.
4. **Do NOT hardcode facet IDs.** Always resolve from env/config/default.

---

## Completion Criteria

- [ ] `SEMANTOS_FACET` env var works like `AWS_PROFILE` (selects active facet)
- [ ] Config file supports `active_facet` and `plexus.*` settings
- [ ] Shell prompt shows `[facet-id@extension]` format
- [ ] `semantos identity register <email>` creates identity via PlexusService
- [ ] `semantos identity derive <resource-id>` creates child facet
- [ ] `semantos identity resolve <cert-id>` looks up certificate
- [ ] `semantos identity list` lists all facets
- [ ] `semantos whoami` shows current identity, facet, capabilities, cert_id
- [ ] `semantos capabilities` lists active facet's capabilities
- [ ] Every mutation verb checks capabilities before executing
- [ ] Missing capability returns error response (not exception)
- [ ] `--dry-run` shows capability checks without executing
- [ ] Tests T1–T8 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] All commits follow `phase-19.5/D19.5.N:` naming convention
- [ ] Branch is `phase-19.5-shell-plexus-auth`
- [ ] Errata sprint complete with `docs/prd/PHASE-19.5-ERRATA.md`

---

## Next Phase

Phase 20 adds tmux integration: multi-pane operator console, live object tree pane, inspector pane, event log pane, FUSE-based VFS mount.
