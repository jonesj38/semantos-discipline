---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase19.5-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.566098+00:00
---

# tests/gates/phase19.5-gate.test.ts

```ts
/**
 * Phase 19.5 Gate: Shell Plexus Auth (Identity + Capabilities)
 *
 * Tests T1–T8 covering:
 *   T1-T3: SEMANTOS_HAT environment variable
 *   T4-T5: Identity commands (whoami, register)
 *   T6-T7: Capability checks (publish, missing capability)
 *   T8:    Dry run shows capability checks
 *
 * Uses real process.env for env var tests (not mocked).
 * Uses source inspection for router patterns.
 * Uses direct imports for pure functions (parser, config, capabilities).
 */

import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { readFileSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");
const SHELL_SRC = join(ROOT, "runtime/shell/src");

// ── Pure function imports ─────────────────────────────────────

import { parseCommand, KNOWN_VERBS } from "../../runtime/shell/src/parser";
import { loadConfig } from "../../runtime/shell/src/config";
import {
  CAPABILITY_MAP,
  getRequiredCapability,
  getCapabilityName,
  MUTATION_VERBS,
} from "../../runtime/shell/src/capabilities";

// ═══════════════════════════════════════════════════════════════
// T1–T3: SEMANTOS_HAT Environment Variable Tests
// ═══════════════════════════════════════════════════════════════

describe("T1: SEMANTOS_HAT env var selects correct facet", () => {
  const saved = process.env.SEMANTOS_HAT;

  afterEach(() => {
    if (saved === undefined) {
      delete process.env.SEMANTOS_HAT;
    } else {
      process.env.SEMANTOS_HAT = saved;
    }
  });

  test("SEMANTOS_HAT=facet-456 → config.activeHatId = 'facet-456'", () => {
    process.env.SEMANTOS_HAT = "facet-456";
    const config = loadConfig();
    expect(config.activeHatId).toBe("facet-456");
  });
});

describe("T2: Config file active_hat used when env var not set", () => {
  test("loadConfig reads active_hat from [shell] section of TOML", () => {
    // We verify the config module parses TOML correctly by inspecting the source
    const configSrc = readFileSync(join(SHELL_SRC, "config.ts"), "utf-8");

    // Config reads SEMANTOS_HAT from process.env
    expect(configSrc).toContain("process.env.SEMANTOS_HAT");

    // Config reads active_hat from [shell] section
    expect(configSrc).toContain("shell.active_hat");

    // Config reads [plexus] section
    expect(configSrc).toContain("plexus.mode");
    expect(configSrc).toContain("plexus.endpoint");

    // Env var overrides file setting (Layer 3 > Layer 2 > Layer 1)
    expect(configSrc).toContain("Layer 3: Environment variables");
  });
});

describe("T3: Root identity used when neither env var nor config set", () => {
  const savedFacet = process.env.SEMANTOS_HAT;

  afterEach(() => {
    if (savedFacet === undefined) {
      delete process.env.SEMANTOS_HAT;
    } else {
      process.env.SEMANTOS_HAT = savedFacet;
    }
  });

  test("no env var and no config file → activeHatId = null", () => {
    delete process.env.SEMANTOS_HAT;
    const config = loadConfig();
    // Without a config file with active_hat, default is null
    expect(config.activeHatId).toBeNull();
  });

  test("default plexusMode is 'stub'", () => {
    const config = loadConfig();
    expect(config.plexusMode).toBe("stub");
  });

  test("default plexusEndpoint is 'http://localhost:9000'", () => {
    const config = loadConfig();
    expect(config.plexusEndpoint).toBe("http://localhost:9000");
  });

  test("activeHatCertId defaults to null", () => {
    const config = loadConfig();
    expect(config.activeHatCertId).toBeNull();
  });
});

// ═══════════════════════════════════════════════════════════════
// T4–T5: Identity Commands Tests
// ═══════════════════════════════════════════════════════════════

describe("T4: 'semantos whoami' returns identity, facet, capabilities", () => {
  test("parser recognizes 'whoami' verb", () => {
    const cmd = parseCommand(["whoami"]);
    expect(cmd.verb).toBe("whoami");
  });

  test("'whoami' is in KNOWN_VERBS", () => {
    expect(KNOWN_VERBS).toContain("whoami");
  });

  test("router handles 'whoami' verb", () => {
    const routerSrc = readFileSync(join(SHELL_SRC, "router.ts"), "utf-8");
    // Router dispatches whoami to routeWhoami
    expect(routerSrc).toContain("case 'whoami':");
    expect(routerSrc).toContain("routeWhoami(ctx)");
  });

  test("routeWhoami returns expected shape", () => {
    const identitySrc = readFileSync(join(SHELL_SRC, "identity.ts"), "utf-8");
    // Must return hatId, certId, capabilities, extension, timestamp
    expect(identitySrc).toContain("hatId:");
    expect(identitySrc).toContain("certId:");
    expect(identitySrc).toContain("capabilities");
    expect(identitySrc).toContain("extension:");
    expect(identitySrc).toContain("timestamp:");
  });
});

describe("T5: 'semantos identity register' calls PlexusService.registerIdentity()", () => {
  test("parser recognizes 'identity' verb", () => {
    const cmd = parseCommand(["identity", "register", "alice@example.com"]);
    expect(cmd.verb).toBe("identity");
    expect(cmd.flags.action).toBe("register");
    expect(cmd.objectId).toBe("alice@example.com");
  });

  test("parser recognizes 'identity derive'", () => {
    const cmd = parseCommand(["identity", "derive", "my-device"]);
    expect(cmd.verb).toBe("identity");
    expect(cmd.flags.action).toBe("derive");
    expect(cmd.objectId).toBe("my-device");
  });

  test("parser recognizes 'identity resolve'", () => {
    const cmd = parseCommand(["identity", "resolve", "cert:abc123"]);
    expect(cmd.verb).toBe("identity");
    expect(cmd.flags.action).toBe("resolve");
    expect(cmd.objectId).toBe("cert:abc123");
  });

  test("parser recognizes 'identity list'", () => {
    const cmd = parseCommand(["identity", "list"]);
    expect(cmd.verb).toBe("identity");
    expect(cmd.flags.action).toBe("list");
  });

  test("identity commands call PlexusService (not hardcoded)", () => {
    const identitySrc = readFileSync(join(SHELL_SRC, "identity.ts"), "utf-8");
    // Must call ctx.plexus methods, not hardcoded data
    expect(identitySrc).toContain("ctx.plexus.registerIdentity(");
    expect(identitySrc).toContain("ctx.plexus.deriveChild(");
    expect(identitySrc).toContain("ctx.plexus.resolveIdentity(");
    expect(identitySrc).toContain("ctx.plexus.querySubtree(");
    // Must NOT contain hardcoded cert IDs
    expect(identitySrc).not.toMatch(/certId:\s*['"][a-f0-9]{10,}['"]/);
  });

  test("'capabilities' is in KNOWN_VERBS", () => {
    expect(KNOWN_VERBS).toContain("capabilities");
  });
});

// ═══════════════════════════════════════════════════════════════
// T6–T7: Capability Check Tests
// ═══════════════════════════════════════════════════════════════

describe("T6: 'publish' verb checks capability 0x00010005 before executing", () => {
  test("publish maps to domain flag 0x00010005", () => {
    expect(getRequiredCapability("publish")).toBe(0x00010005);
  });

  test("all capability mappings match PLEXUS-INTEGRATION-MAP.md spec", () => {
    expect(CAPABILITY_MAP.new).toBe(0x00010002);       // Create
    expect(CAPABILITY_MAP.patch).toBe(0x00010003);     // Edit/Patch
    expect(CAPABILITY_MAP.revoke).toBe(0x00010004);    // Delete/Revoke
    expect(CAPABILITY_MAP.publish).toBe(0x00010005);   // Publish
    expect(CAPABILITY_MAP.vote).toBe(0x00010006);      // Govern (Vote)
    expect(CAPABILITY_MAP.dispute).toBe(0x00010007);   // Govern (Propose)
    expect(CAPABILITY_MAP.stake).toBe(0x00010008);     // Stake
    expect(CAPABILITY_MAP.transfer).toBe(0x00010009);  // Transfer
  });

  test("capability names are human-readable", () => {
    expect(getCapabilityName(0x00010005)).toBe("Publish");
    expect(getCapabilityName(0x00010002)).toBe("Create");
    expect(getCapabilityName(0x00010004)).toBe("Delete/Revoke");
  });

  test("router checks capability via PlexusService before executing", () => {
    const routerSrc = readFileSync(join(SHELL_SRC, "router.ts"), "utf-8");
    // Must use PlexusService.presentCapability
    expect(routerSrc).toContain("ctx.plexus.presentCapability(");
    // Must check BEFORE dispatching
    expect(routerSrc).toContain("MUTATION_VERBS.has(cmd.verb)");
    // Must import capability helpers
    expect(routerSrc).toContain("getRequiredCapability");
  });

  test("read-only verbs do not require capabilities", () => {
    expect(getRequiredCapability("inspect")).toBeNull();
    expect(getRequiredCapability("trace")).toBeNull();
    expect(getRequiredCapability("verify")).toBeNull();
    expect(getRequiredCapability("list")).toBeNull();
  });

  test("all mutation verbs are in MUTATION_VERBS set", () => {
    expect(MUTATION_VERBS.has("new")).toBe(true);
    expect(MUTATION_VERBS.has("patch")).toBe(true);
    expect(MUTATION_VERBS.has("publish")).toBe(true);
    expect(MUTATION_VERBS.has("revoke")).toBe(true);
    expect(MUTATION_VERBS.has("stake")).toBe(true);
    expect(MUTATION_VERBS.has("vote")).toBe(true);
    expect(MUTATION_VERBS.has("dispute")).toBe(true);
    expect(MUTATION_VERBS.has("transfer")).toBe(true);
    // Read-only verbs are NOT mutation verbs
    expect(MUTATION_VERBS.has("inspect")).toBe(false);
    expect(MUTATION_VERBS.has("list")).toBe(false);
  });
});

describe("T7: Missing capability returns error response (not exception)", () => {
  test("router returns error object when capability check fails", () => {
    const routerSrc = readFileSync(join(SHELL_SRC, "router.ts"), "utf-8");
    // Error is returned as { error: ... }, not thrown
    expect(routerSrc).toContain("return { error: check.message }");
    // No active facet also returns error
    expect(routerSrc).toContain("Cannot");
    expect(routerSrc).toContain("without an active facet");
  });

  test("capability check function returns structured result", () => {
    const routerSrc = readFileSync(join(SHELL_SRC, "router.ts"), "utf-8");
    // checkPlexusCapability returns { allowed, requiredCapability, message }
    expect(routerSrc).toContain("allowed: false");
    expect(routerSrc).toContain("requiredCapability:");
    expect(routerSrc).toContain("message:");
  });
});

// ═══════════════════════════════════════════════════════════════
// T8: Dry Run Test
// ═══════════════════════════════════════════════════════════════

describe("T8: '--dry-run' on mutation verb shows capability check without executing", () => {
  test("parser correctly parses --dry-run flag", () => {
    const cmd = parseCommand(["publish", "job-1774", "--dry-run"]);
    expect(cmd.verb).toBe("publish");
    expect(cmd.objectId).toBe("job-1774");
    expect(cmd.flags["dry-run"]).toBe(true);
  });

  test("dry run returns capability check result in response", () => {
    const routerSrc = readFileSync(join(SHELL_SRC, "router.ts"), "utf-8");
    // Dry run path returns structured capability info
    expect(routerSrc).toContain("dryRun: true");
    expect(routerSrc).toContain("wouldExecute:");
    expect(routerSrc).toContain("requiredCapability:");
    expect(routerSrc).toContain("hasCapability:");
    expect(routerSrc).toContain("requiredCapabilityName:");
  });

  test("dry run checks capabilities but does not execute", () => {
    const routerSrc = readFileSync(join(SHELL_SRC, "router.ts"), "utf-8");
    // isDryRun check happens inside MUTATION_VERBS block, before dispatch
    expect(routerSrc).toContain("if (isDryRun)");
    expect(routerSrc).toContain("checkPlexusCapability(ctx, cmd.verb)");
  });
});

// ═══════════════════════════════════════════════════════════════
// Additional Phase 19.5 Verification
// ═══════════════════════════════════════════════════════════════

describe("Phase 19.5: BRC-100 sendAuthenticated plumbing", () => {
  test("identity operations wire through sendAuthenticated", () => {
    const routerSrc = readFileSync(join(SHELL_SRC, "router.ts"), "utf-8");
    expect(routerSrc).toContain("ctx.plexus.sendAuthenticated(");
    expect(routerSrc).toContain("routeIdentityWithAuth");
  });

  test("sendAuthenticated is not bypassed", () => {
    const routerSrc = readFileSync(join(SHELL_SRC, "router.ts"), "utf-8");
    // identity case dispatches to routeIdentityWithAuth (not routeIdentity directly)
    expect(routerSrc).toContain("case 'identity':");
    // The next line after case 'identity' calls routeIdentityWithAuth
    const identityCaseMatch = routerSrc.match(/case 'identity':\s*\n\s*return\s+(\w+)/);
    expect(identityCaseMatch?.[1]).toBe("routeIdentityWithAuth");
  });
});

describe("Phase 19.5: ShellContext includes plexus service", () => {
  test("ShellContext has plexus field", () => {
    const typesSrc = readFileSync(join(SHELL_SRC, "types.ts"), "utf-8");
    expect(typesSrc).toContain("plexus: PlexusService");
    expect(typesSrc).toContain("activeHatCertId: string | null");
  });

  test("ShellConfig has plexus fields", () => {
    const typesSrc = readFileSync(join(SHELL_SRC, "types.ts"), "utf-8");
    expect(typesSrc).toContain("plexusMode:");
    expect(typesSrc).toContain("plexusEndpoint:");
    expect(typesSrc).toContain("activeHatCertId:");
  });
});

describe("Phase 19.5: PLEXUS env vars", () => {
  const savedMode = process.env.PLEXUS_MODE;
  const savedEndpoint = process.env.PLEXUS_ENDPOINT;

  afterEach(() => {
    if (savedMode === undefined) delete process.env.PLEXUS_MODE;
    else process.env.PLEXUS_MODE = savedMode;
    if (savedEndpoint === undefined) delete process.env.PLEXUS_ENDPOINT;
    else process.env.PLEXUS_ENDPOINT = savedEndpoint;
  });

  test("PLEXUS_MODE env var overrides config", () => {
    process.env.PLEXUS_MODE = "real";
    const config = loadConfig();
    expect(config.plexusMode).toBe("real");
  });

  test("PLEXUS_ENDPOINT env var overrides config", () => {
    process.env.PLEXUS_ENDPOINT = "https://plexus.example.com";
    const config = loadConfig();
    expect(config.plexusEndpoint).toBe("https://plexus.example.com");
  });
});

describe("Phase 19.5: No shell-specific identity storage", () => {
  test("identity.ts does not create its own storage", () => {
    const identitySrc = readFileSync(join(SHELL_SRC, "identity.ts"), "utf-8");
    // Must not contain localStorage, Map, or any identity storage
    expect(identitySrc).not.toContain("localStorage");
    expect(identitySrc).not.toContain("new Map");
    // All operations go through ctx.plexus or ctx.identity
    expect(identitySrc).toContain("ctx.plexus.");
    expect(identitySrc).toContain("ctx.identity.");
  });
});

describe("Phase 19.5: Shell prompt shows [hat@extension]", () => {
  test("REPL builds prompt with hat and extension", () => {
    const replSrc = readFileSync(join(SHELL_SRC, "repl.ts"), "utf-8");
    expect(replSrc).toContain("buildPrompt()");
    expect(replSrc).toContain("activeHatId");
    expect(replSrc).toContain("no-hat");
    // Format: [hatId@shortExtension] >
    expect(replSrc).toMatch(/\[.*@.*\]\s*>\s/);
  });
});

```
