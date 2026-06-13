---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-19.5-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.694948+00:00
---

# Phase 19.5 Execution Prompt — Shell Plexus Auth (Identity + Capabilities)

> Paste this prompt into a fresh session to execute Phase 19.5.

## Context

You are working in the `semantos-core` repo. Phase 19 built the semantic shell: a typed CLI that exposes Phase 9 services. Phase 14 built the PlexusAdapter interface with a stub implementation for identity and key derivation.

Your task is Phase 19.5: integrate the shell with Plexus identity. The shell now selects its active facet via environment variable (like `AWS_PROFILE`), checks capabilities for every mutation, and stamps all commands with identity provenance.

After Phase 19.5:
- `SEMANTOS_FACET=facet-3a2b semantos new trades.job.plumbing` runs as that facet
- `semantos publish job-1774` first checks if the facet has the publish capability
- `semantos identity register alice@example.com` creates a new identity via PlexusService
- All identity operations are CLI-accessible, all capability checks are enforced

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below.

**Read first** (the PRDs — your requirements):
- `docs/prd/PHASE-19.5-SHELL-PLEXUS-AUTH.md` — Phase 19.5 spec with deliverables D19.5.1–D19.5.4, TDD gate T1–T8

**Read second** (the shell from Phase 19 — understand what exists):
- `docs/prd/PHASE-19-SEMANTIC-SHELL.md` — Shell architecture (already merged)
- `docs/prd/SEMANTIC-SHELL-ARCHITECTURE.md` — Vision and Unix composability

**Read third** (the Plexus integration from Phase 14 — understand the adapter):
- `packages/loom/src/plexus/types.ts` — PlexusAdapter interface
- `packages/loom/src/plexus/PlexusService.ts` — PlexusService (the wrapper around the adapter)
- `docs/prd/PLEXUS-INTEGRATION-MAP.md` — Architecture: adapter boundary, domain flags, capability mapping

**Read fourth** (the services the shell uses):
- `packages/loom/src/services/IdentityStore.ts` — getActiveFacet(), hasCapability()
- `packages/loom/src/services/LoomStore.ts` — already capability-aware from Phase 14 integration

**Read fifth** (branching policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-19.5-shell-plexus-auth`. Commits as `phase-19.5/D19.5.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. NO STUBS

Every function must do real work. If it's a stub, you have failed. The shell is a thin routing layer that delegates to real services.

### 2. NO MOCK IDENTITY DATA

All identity operations must flow through PlexusService. No hardcoded facet IDs. No test fixtures that pretend to be identities.

### 3. NO BYPASSED CAPABILITY CHECKS

Every mutation verb checks capabilities. Period. No exceptions like "in dry-run mode, skip the check". No shortcuts.

### 4. NO REAL BRC-100 IMPLEMENTATION

Phase 15 implements real signing. Phase 19.5 just wires the adapter's sendAuthenticated() method. In stub mode, it echoes. That's it.

### 5. ENVIRONMENT VARIABLES ARE NOT MOCKED

Tests for `SEMANTOS_FACET` must actually set and read process.env. Don't fake it. Don't mock it.

### 6. CAPABILITY MAPPING MATCHES SPEC

The PLEXUS-INTEGRATION-MAP.md defines the domain flag → capability number mapping. Your code must match:
- Create: 0x00010002
- Edit/Patch: 0x00010003
- Publish: 0x00010005
- Delete/Revoke: 0x00010004
- Stake: 0x00010008
- Govern (Vote): 0x00010006
- Govern (Propose): 0x00010007
- Transfer: 0x00010009

If your code uses different numbers, you have broken the spec.

### 7. PHASED INTEGRATION, NOT NEW CODE

You are integrating existing pieces (shell from Phase 19, PlexusService from Phase 14), not building new backends. Modifications to the shell's router and config are minimal and surgical.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd <path-to-semantos-core>
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Verify prerequisites are complete

```bash
# Phase 19 is merged
git log --oneline | grep "phase-19.*SEMANTIC-SHELL" || echo "Phase 19 not yet merged"

# Phase 14 is merged
git log --oneline | grep "phase-14.*PLEXUS-ADAPTER" || echo "Phase 14 not yet merged"

# Shell package exists
ls packages/shell/src/router.ts
ls packages/shell/src/config.ts

# PlexusService exists
ls packages/loom/src/plexus/PlexusService.ts
```

All must exist. If Phase 19 or Phase 14 are not merged, STOP.

### 0.3 Create Phase 19.5 branch

```bash
git checkout -b phase-19.5-shell-plexus-auth
```

---

## Step 1: SEMANTOS_FACET Environment Variable (D19.5.1)

Modify `packages/shell/src/config.ts`:

1. Add new fields to `ShellConfig`:
   ```typescript
   activeFacetId: string | null;
   activeFacetCertId: string | null;  // NEW
   plexusMode?: 'stub' | 'real' | 'cloud';
   plexusEndpoint?: string;
   ```

2. In `loadConfig()`:
   - Check `process.env.SEMANTOS_FACET` first
   - Fall back to config file `active_facet` setting
   - Fall back to null (root identity)
   - If facet ID is set, resolve its cert_id via PlexusService (synchronously if stub, error if not available)

3. Add config file support (TOML):
   ```toml
   [shell]
   active_facet = "facet-3a2b"

   [plexus]
   mode = "stub"
   endpoint = "http://localhost:9000"
   ```

4. Update shell prompt to show facet:
   - Modify `packages/shell/src/repl.ts` prompt to read from config
   - Format: `[facet-3a2b@trades] > ` (show active facet and extension)
   - When facet is null: `[no-facet@trades] > `

Test case:
- Set `SEMANTOS_FACET=facet-xyz`
- Load config: should have `activeFacetId = "facet-xyz"`
- Resolve cert_id via PlexusService.resolveIdentity("facet-xyz") (stub returns deterministic cert)

Commit: `phase-19.5/D19.5.1: SEMANTOS_FACET environment variable — facet selection like AWS_PROFILE`

---

## Step 2: Shell Identity Integration (D19.5.2)

Create `packages/shell/src/identity.ts` and modify `packages/shell/src/router.ts`:

Add new verb: `identity` with actions:

```typescript
case 'identity':
  const action = cmd.flags.action as string;
  switch (action) {
    case 'register':
      // semantos identity register alice@example.com
      const email = cmd.objectId;
      return await ctx.plexus.registerIdentity(email);

    case 'derive':
      // semantos identity derive my-device
      const resourceId = cmd.objectId;
      return await ctx.plexus.deriveChild(
        ctx.activeFacetCertId || await getRootCertId(),
        resourceId,
        0x00010001  // Client facet domain flag
      );

    case 'resolve':
      // semantos identity resolve abc123...
      const certId = cmd.objectId;
      return await ctx.plexus.resolveIdentity(certId);

    case 'list':
      // semantos identity list
      return await ctx.plexus.querySubtree(ctx.activeFacetCertId, 2);
  }
```

Add built-in command: `semantos whoami`

```typescript
case 'whoami':
  const facet = ctx.identity.getActiveFacet();
  const capabilities = facet ? ctx.identity.getCapabilities(facet.certId) : [];
  return {
    facetId: ctx.config.activeFacetId,
    certId: ctx.config.activeFacetCertId,
    capabilities: capabilities,
    extension: ctx.config.defaultExtension,
    timestamp: new Date().toISOString()
  };
```

Requirements:
- All identity commands call PlexusService (not IdentityStore directly)
- Works in stub mode (no real Plexus required)
- Returns structured response (JSON-serializable)

Commit: `phase-19.5/D19.5.2: Shell identity integration — register, derive, resolve, list commands`

---

## Step 3: Capability-Gated Shell Commands (D19.5.3)

Modify `packages/shell/src/router.ts`:

Before executing any mutation verb, check capabilities:

```typescript
async function checkCapability(
  ctx: RouterContext,
  verb: string
): Promise<{ allowed: boolean; message?: string }> {
  const requiredCap = getRequiredCapability(verb);
  if (requiredCap === null) {
    // Read-only verb
    return { allowed: true };
  }

  const facet = ctx.identity.getActiveFacet();
  if (!facet) {
    return {
      allowed: false,
      message: `Cannot ${verb} without an active facet. Set SEMANTOS_FACET=<facet-id>.`
    };
  }

  const hasCapability = await ctx.plexus.presentCapability(
    facet.certId,
    requiredCap
  ).then(result => result.valid);

  if (!hasCapability) {
    return {
      allowed: false,
      message: `Missing capability ${getCapabilityName(requiredCap)} (${requiredCap}) to ${verb}.`
    };
  }

  return { allowed: true };
}
```

Update router:

```typescript
export async function route(cmd: ShellCommand, ctx: RouterContext): Promise<unknown> {
  // Check capability for mutation verbs
  if (isMutationVerb(cmd.verb)) {
    const check = await checkCapability(ctx, cmd.verb);
    if (!check.allowed) {
      return { error: check.message };
    }
  }

  // Handle --dry-run
  if (cmd.flags.dryRun) {
    const requiredCap = getRequiredCapability(cmd.verb);
    const facet = ctx.identity.getActiveFacet();
    const hasCapability = facet && requiredCap !== null
      ? (await ctx.plexus.presentCapability(facet.certId, requiredCap)).valid
      : true;

    return {
      dryRun: true,
      verb: cmd.verb,
      wouldExecute: hasCapability,
      requiredCapability: requiredCap,
      facetId: ctx.config.activeFacetId
    };
  }

  // Now route normally
  switch (cmd.verb) { ... }
}
```

Capability mapping (from PLEXUS-INTEGRATION-MAP.md):

```typescript
function getRequiredCapability(verb: string): number | null {
  const capMap: Record<string, number> = {
    new: 0x00010002,        // Create
    patch: 0x00010003,      // Edit
    publish: 0x00010005,    // Publish
    revoke: 0x00010004,     // Delete
    stake: 0x00010008,      // Stake
    vote: 0x00010006,       // Govern Vote
    dispute: 0x00010007,    // Govern Propose
    transfer: 0x00010009    // Transfer
  };
  return capMap[verb] || null;
}
```

New shell commands:
- `semantos capabilities` — list active facet's capabilities

Commit: `phase-19.5/D19.5.3: Capability-gated shell commands — every mutation checks before executing`

---

## Step 4: BRC-100 Signed Requests (D19.5.4)

Modify `packages/shell/src/config.ts` and `packages/shell/src/router.ts`:

Wire sendAuthenticated() calls through the router when executing identity operations:

```typescript
// In router.ts, when calling PlexusService methods:
const payload = {
  action: cmd.verb,
  facetCertId: ctx.config.activeFacetCertId,
  timestamp: new Date().toISOString(),
  params: { ... }
};

const response = await ctx.plexus.sendAuthenticated(
  ctx.config.plexusEndpoint || 'http://localhost:9000',
  payload
);
```

For Phase 19.5, this is just plumbing:
- In stub mode: PlexusService.sendAuthenticated() echoes the payload (already implemented in Phase 14)
- In real mode: Phase 15 replaces the stub, real signing happens
- Your job: pass the config correctly, call the method, let the adapter do the work

Config file support:

```toml
[plexus]
mode = "stub"              # stub | real | cloud
endpoint = "http://localhost:9000"
```

No implementation of BRC-100. Just wire it.

Commit: `phase-19.5/D19.5.4: BRC-100 signed requests (prep for Phase 15) — config + adapter passthrough`

---

## Step 5: Gate Tests

Create `packages/__tests__/phase19.5-gate.test.ts`.

### Environment Variable Tests (T1–T3)

```typescript
describe("SEMANTOS_FACET environment variable", () => {
  // T1: SEMANTOS_FACET=facet-456 → config.activeFacetId = "facet-456"
  // T2: Config file active_facet = "facet-789", no env var → "facet-789"
  // T3: Neither set → config.activeFacetId = null
});
```

### Identity Commands Tests (T4–T5)

```typescript
describe("Identity commands", () => {
  // T4: 'semantos whoami' returns { facetId, certId, capabilities, ... }
  // T5: 'semantos identity register alice@example.com' calls PlexusService.registerIdentity()
});
```

### Capability Tests (T6–T7)

```typescript
describe("Capability checks", () => {
  // T6: 'publish' verb checks capability 0x00010005 before executing
  // T7: Missing capability returns error response (not exception)
});
```

### Dry Run Test (T8)

```typescript
describe("Dry run", () => {
  // T8: '--dry-run' shows capability checks without executing
});
```

---

## Step 6: Errata Sprint

After all tests pass, run the errata protocol in a fresh session:

1. Verify all capability flags match PLEXUS-INTEGRATION-MAP.md
2. Check that identity commands are not hardcoded
3. Verify capability checks are not bypassed anywhere
4. Check that SEMANTOS_FACET env var is actually read (not mocked in tests)
5. Verify sendAuthenticated() is called for identity operations
6. Write errata doc as `docs/prd/PHASE-19.5-ERRATA.md`

---

## Completion Criteria

- [ ] `SEMANTOS_FACET` env var works (sets active facet)
- [ ] Config file supports `active_facet` and `plexus.*` settings
- [ ] Shell prompt shows `[facet-id@extension]` format
- [ ] `semantos identity register <email>` works via PlexusService
- [ ] `semantos identity derive <resource-id>` works
- [ ] `semantos identity resolve <cert-id>` works
- [ ] `semantos identity list` works
- [ ] `semantos whoami` shows identity, facet, capabilities
- [ ] `semantos capabilities` lists active facet's capabilities
- [ ] Every mutation verb checks capabilities before executing
- [ ] Missing capability returns error response (not exception)
- [ ] `--dry-run` shows capability checks without executing
- [ ] Capability flags match PLEXUS-INTEGRATION-MAP.md spec
- [ ] Tests T1–T8 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] All commits follow `phase-19.5/D19.5.N:` naming convention
- [ ] Branch is `phase-19.5-shell-plexus-auth`
- [ ] Errata sprint complete with `docs/prd/PHASE-19.5-ERRATA.md`

---

## Next Phase

Phase 20: tmux operator console with multi-pane layout, live object tree, inspector pane, event log, FUSE-based VFS mount.
