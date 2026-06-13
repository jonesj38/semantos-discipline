---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase19-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.579493+00:00
---

# tests/gates/phase19-gate.test.ts

```ts
/**
 * Phase 19 Gate: Semantic Shell (Typed CLI Renderer)
 *
 * Tests T1–T18 covering parser, router, formatters, config, REPL, and anti-lock.
 * Parser, formatter, and config tests import shell code directly (pure functions).
 * Router tests use source inspection (same pattern as Phase 9 gates) to avoid
 * the protocol-types circular dependency issue in Bun.
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, existsSync, readdirSync } from "fs";
import { join } from "path";
import { execSync } from "child_process";

const ROOT = join(import.meta.dir, "../..");
const SHELL_SRC = join(ROOT, "runtime/shell/src");
const CONFIGS_DIR = join(ROOT, "configs/extensions");

// ── Parser imports (pure functions, no service deps) ──────────

import { parseCommand, KNOWN_VERBS } from "../../runtime/shell/src/parser";
import type { ShellCommand } from "../../runtime/shell/src/parser";

// ── Formatter imports (pure functions) ────────────────────────

import { OutputFormatter, parseOutputFormat } from "../../runtime/shell/src/formatters";

// ── Config imports (uses fs + env, no service deps) ──────────

import { loadConfig } from "../../runtime/shell/src/config";

// ═══════════════════════════════════════════════════════════════
// T1–T4: Parser Tests
// ═══════════════════════════════════════════════════════════════

describe("T1: Parser parses 'new trades.job.plumbing --urgency high'", () => {
  test("extracts verb, typePath, and flags correctly", () => {
    const cmd = parseCommand(["new", "trades.job.plumbing", "--urgency", "high"]);
    expect(cmd.verb).toBe("new");
    expect(cmd.typePath).toBe("trades.job.plumbing");
    expect(cmd.objectId).toBeUndefined();
    expect(cmd.flags.urgency).toBe("high");
  });
});

describe("T2: Parser parses 'inspect job-1774'", () => {
  test("extracts verb and objectId with no typePath", () => {
    const cmd = parseCommand(["inspect", "job-1774"]);
    expect(cmd.verb).toBe("inspect");
    expect(cmd.objectId).toBe("job-1774");
    expect(cmd.typePath).toBeUndefined();
    expect(Object.keys(cmd.flags).length).toBe(0);
  });
});

describe("T3: Parser parses 'list --type governance.dispute --status open --format json'", () => {
  test("extracts verb and multiple flag key-value pairs", () => {
    const cmd = parseCommand(["list", "--type", "governance.dispute", "--status", "open", "--format", "json"]);
    expect(cmd.verb).toBe("list");
    expect(cmd.typePath).toBeUndefined();
    expect(cmd.objectId).toBeUndefined();
    expect(cmd.flags.type).toBe("governance.dispute");
    expect(cmd.flags.status).toBe("open");
    expect(cmd.flags.format).toBe("json");
  });
});

describe("T4: Parser rejects malformed commands with helpful errors", () => {
  test("empty args throws with usage hint", () => {
    expect(() => parseCommand([])).toThrow("No command provided");
  });

  test("unknown verb 'foo' throws with suggestion", () => {
    try {
      parseCommand(["foo"]);
      expect(true).toBe(false); // should not reach
    } catch (e) {
      const msg = (e as Error).message;
      expect(msg).toContain("Unknown verb 'foo'");
      expect(msg).toContain("Did you mean 'flow'?");
      expect(msg).toContain("Available verbs:");
    }
  });

  test("unknown verb 'nwe' suggests 'new'", () => {
    try {
      parseCommand(["nwe"]);
    } catch (e) {
      const msg = (e as Error).message;
      expect(msg).toContain("Did you mean 'new'?");
    }
  });

  test("boolean flags (--dry-run) are parsed as true", () => {
    const cmd = parseCommand(["publish", "job-1774", "--dry-run"]);
    expect(cmd.verb).toBe("publish");
    expect(cmd.objectId).toBe("job-1774");
    expect(cmd.flags["dry-run"]).toBe(true);
  });

  test("all verbs are recognized (16 original + 4 Phase 19.5/20 + 2 Phase 21 + 1 Phase 28 + 1 Phase 27 + 1 Phase 36A)", () => {
    expect(KNOWN_VERBS).toHaveLength(25);
    for (const verb of KNOWN_VERBS) {
      // Each verb should parse without error when given minimal args
      const args = ["inspect", "trace", "verify", "sign", "publish", "revoke", "transfer", "patch", "transition"].includes(verb)
        ? [verb, "test-id"]
        : verb === "new"
          ? [verb, "test.type"]
          : [verb];
      const cmd = parseCommand(args);
      expect(cmd.verb).toBe(verb);
    }
  });

  test("flow verb parses subcommand and flow name", () => {
    const cmd = parseCommand(["flow", "start", "new-job-intake", "--category", "plumbing"]);
    expect(cmd.verb).toBe("flow");
    expect(cmd.flags.subcommand).toBe("start");
    expect(cmd.flags.flow).toBe("new-job-intake");
    expect(cmd.flags.category).toBe("plumbing");
  });
});

// ═══════════════════════════════════════════════════════════════
// T5–T9: Router Tests (source inspection)
// ═══════════════════════════════════════════════════════════════

const routerSource = readFileSync(join(SHELL_SRC, "router.ts"), "utf-8");

describe("T5: Router maps 'new' verb to LoomStore.createObjectFromType()", () => {
  test("routeNew calls createObjectFromType", () => {
    expect(routerSource).toContain("ctx.store.createObjectFromType(");
    expect(routerSource).toContain("case 'new':");
    expect(routerSource).toContain("routeNew(cmd, ctx)");
  });
});

describe("T6: Router maps 'inspect' verb to getObject()", () => {
  test("routeInspect reads object state", () => {
    expect(routerSource).toContain("case 'inspect':");
    expect(routerSource).toContain("routeInspect(cmd, ctx)");
    // Should serialize full object with header and evidence
    expect(routerSource).toContain("serializeObject(obj)");
    expect(routerSource).toContain("obj.header.");
  });
});

describe("T7: Router maps 'flow start' to FlowRunner.startFlow()", () => {
  test("routeFlow calls startFlow", () => {
    expect(routerSource).toContain("case 'flow':");
    expect(routerSource).toContain("ctx.flowRunner.startFlow(");
    expect(routerSource).toContain("routeFlow(cmd, ctx)");
  });
});

describe("T8: Router maps 'publish' to visibility transition with capability check", () => {
  test("routePublish calls transitionVisibility and capability is checked", () => {
    expect(routerSource).toContain("case 'publish':");
    // Phase 19.5: capability check is unified at the top of route() via checkPlexusCapability
    expect(routerSource).toContain("checkPlexusCapability(ctx, cmd.verb)");
    expect(routerSource).toContain("ctx.store.transitionVisibility(cmd.objectId, 'published'");
  });
});

describe("T9: Router returns error object if capability missing", () => {
  test("checkPlexusCapability returns descriptive error object, not exception", () => {
    // Verify the pattern: returns { error: "..." } not throw
    expect(routerSource).toContain("return { error:");
    expect(routerSource).toContain("Missing capability");
    // Phase 19.5: unified check returns error for all mutation verbs
    expect(routerSource).toContain("return { error: check.message }");
  });

  test("revoke capability is checked via unified gate", () => {
    // Phase 19.5: revoke is in MUTATION_VERBS, checked via getRequiredCapability
    expect(routerSource).toContain("case 'revoke':");
    expect(routerSource).toContain("MUTATION_VERBS.has(cmd.verb)");
  });

  test("dry-run flag is handled", () => {
    expect(routerSource).toContain("const isDryRun = cmd.flags['dry-run'] === true;");
    expect(routerSource).toContain("dryRun: true");
  });
});

// ═══════════════════════════════════════════════════════════════
// T10–T12: Formatter Tests
// ═══════════════════════════════════════════════════════════════

describe("T10: JSON formatter outputs valid JSON parseable by JSON.parse", () => {
  const formatter = new OutputFormatter();

  test("formats array of objects as valid JSON", () => {
    const data = [
      { id: "job-1", type: "Job", visibility: "draft" },
      { id: "job-2", type: "Job", visibility: "published" },
    ];
    const output = formatter.format(data, "json");
    const parsed = JSON.parse(output);
    expect(parsed).toHaveLength(2);
    expect(parsed[0].id).toBe("job-1");
    expect(parsed[1].visibility).toBe("published");
  });

  test("handles Map and Uint8Array in JSON output", () => {
    const data = {
      objects: new Map([["a", 1]]),
      bytes: new Uint8Array([0x48, 0x65]),
    };
    const output = formatter.format(data, "json");
    const parsed = JSON.parse(output);
    expect(parsed.objects).toEqual({ a: 1 });
    expect(parsed.bytes).toEqual([0x48, 0x65]);
  });

  test("handles BigInt values", () => {
    const data = { timestamp: BigInt("1234567890123456789") };
    const output = formatter.format(data, "json");
    const parsed = JSON.parse(output);
    expect(parsed.timestamp).toBe("1234567890123456789");
  });
});

describe("T11: Table formatter outputs aligned columns", () => {
  const formatter = new OutputFormatter();

  test("produces header row and aligned data rows", () => {
    const data = [
      { id: "job-1774", type: "Job", visibility: "draft", owner: "facet-3a2b", patches: 3 },
      { id: "job-1775", type: "Job", visibility: "published", owner: "facet-3a2b", patches: 2 },
    ];
    const output = formatter.format(data, "table");
    const lines = output.split("\n");

    // Header row should contain column names in uppercase
    expect(lines[0]).toContain("ID");
    expect(lines[0]).toContain("TYPE");
    expect(lines[0]).toContain("VISIBILITY");

    // Data rows exist
    expect(lines.length).toBeGreaterThanOrEqual(3); // header + 2 rows

    // Values appear in rows
    expect(lines[1]).toContain("job-1774");
    expect(lines[2]).toContain("published");
  });

  test("empty array shows '(no results)'", () => {
    const output = formatter.format([], "table");
    expect(output).toBe("(no results)");
  });

  test("single object renders as key-value pairs", () => {
    const output = formatter.format({ id: "job-1", status: "ok" }, "table");
    expect(output).toContain("id");
    expect(output).toContain("job-1");
  });
});

describe("T12: CSV formatter outputs valid CSV with headers", () => {
  const formatter = new OutputFormatter();

  test("produces header row followed by data rows", () => {
    const data = [
      { HASH: "7f3a2b1e", AUTHOR: "facet-3a2b", ACTION: "create", TIMESTAMP: "2026-03-29T14:32:15Z" },
      { HASH: "a91c4d3f", AUTHOR: "facet-3a2b", ACTION: "patch", TIMESTAMP: "2026-03-29T14:32:16Z" },
    ];
    const output = formatter.format(data, "csv");
    const lines = output.split("\n");

    // First line is headers
    expect(lines[0]).toBe("HASH,AUTHOR,ACTION,TIMESTAMP");
    // Data lines
    expect(lines[1]).toBe("7f3a2b1e,facet-3a2b,create,2026-03-29T14:32:15Z");
    expect(lines[2]).toBe("a91c4d3f,facet-3a2b,patch,2026-03-29T14:32:16Z");
  });

  test("escapes values containing commas", () => {
    const data = [{ name: "hello, world", value: "ok" }];
    const output = formatter.format(data, "csv");
    const lines = output.split("\n");
    expect(lines[1]).toContain('"hello, world"');
  });
});

// ═══════════════════════════════════════════════════════════════
// T13: Config Tests
// ═══════════════════════════════════════════════════════════════

describe("T13: Config loads from file, env vars override file, defaults fill gaps", () => {
  test("defaults are applied when no file or env vars exist", () => {
    // Clear relevant env vars
    const saved = {
      SEMANTOS_MODE: process.env.SEMANTOS_MODE,
      SEMANTOS_HAT: process.env.SEMANTOS_HAT,
      SEMANTOS_EXTENSION: process.env.SEMANTOS_EXTENSION,
      SEMANTOS_FORMAT: process.env.SEMANTOS_FORMAT,
      SEMANTOS_ENDPOINT: process.env.SEMANTOS_ENDPOINT,
    };

    delete process.env.SEMANTOS_MODE;
    delete process.env.SEMANTOS_HAT;
    delete process.env.SEMANTOS_EXTENSION;
    delete process.env.SEMANTOS_FORMAT;
    delete process.env.SEMANTOS_ENDPOINT;

    try {
      const config = loadConfig();
      expect(config.adapterMode).toBe("stub");
      expect(config.defaultFormat).toBe("json");
      expect(config.defaultExtension).toBe("core");
      expect(config.activeHatId).toBeNull();
    } finally {
      // Restore
      for (const [k, v] of Object.entries(saved)) {
        if (v !== undefined) process.env[k] = v;
        else delete process.env[k];
      }
    }
  });

  test("env vars override defaults", () => {
    const saved = {
      SEMANTOS_MODE: process.env.SEMANTOS_MODE,
      SEMANTOS_HAT: process.env.SEMANTOS_HAT,
      SEMANTOS_EXTENSION: process.env.SEMANTOS_EXTENSION,
      SEMANTOS_FORMAT: process.env.SEMANTOS_FORMAT,
    };

    process.env.SEMANTOS_MODE = "cloud";
    process.env.SEMANTOS_HAT = "facet-test-123";
    process.env.SEMANTOS_EXTENSION = "trades-services";
    process.env.SEMANTOS_FORMAT = "table";

    try {
      const config = loadConfig();
      expect(config.adapterMode).toBe("cloud");
      expect(config.activeHatId).toBe("facet-test-123");
      expect(config.defaultExtension).toBe("trades-services");
      expect(config.defaultFormat).toBe("table");
    } finally {
      for (const [k, v] of Object.entries(saved)) {
        if (v !== undefined) process.env[k] = v;
        else delete process.env[k];
      }
    }
  });

  test("invalid env var values are ignored", () => {
    const saved = process.env.SEMANTOS_MODE;
    process.env.SEMANTOS_MODE = "invalid_mode";

    try {
      const config = loadConfig();
      // Should fall back to default since 'invalid_mode' is not a valid AdapterMode
      expect(["stub", "local", "cloud"]).toContain(config.adapterMode);
    } finally {
      if (saved !== undefined) process.env.SEMANTOS_MODE = saved;
      else delete process.env.SEMANTOS_MODE;
    }
  });

  test("parseOutputFormat validates format strings", () => {
    expect(parseOutputFormat("json")).toBe("json");
    expect(parseOutputFormat("table")).toBe("table");
    expect(parseOutputFormat("cell")).toBe("cell");
    expect(parseOutputFormat("csv")).toBe("csv");
    expect(parseOutputFormat("invalid")).toBe("json"); // default
    expect(parseOutputFormat(undefined)).toBe("json");
    expect(parseOutputFormat(true)).toBe("json");
  });
});

// ═══════════════════════════════════════════════════════════════
// T14–T15: REPL Tests
// ═══════════════════════════════════════════════════════════════

describe("T14: REPL prompt reflects active hat and extension", () => {
  const replSource = readFileSync(join(SHELL_SRC, "repl.ts"), "utf-8");

  test("buildPrompt uses hatId and extension", () => {
    expect(replSource).toContain("this.ctx.activeHatId");
    expect(replSource).toContain("this.ctx.activeExtension");
    expect(replSource).toContain("no-hat");
    // Prompt format: [hat@extension] >
    expect(replSource).toContain("`[${hatId}@${shortExtension}] > `");
  });

  test("switch command updates prompt", () => {
    expect(replSource).toContain("cmd === 'switch'");
    expect(replSource).toContain("this.ctx.activeHatId = hatId");
    expect(replSource).toContain("this.rl.setPrompt(this.buildPrompt())");
  });

  test("load command updates extension and prompt", () => {
    expect(replSource).toContain("cmd === 'load'");
    expect(replSource).toContain("ctx.config.switchExtension(extension)");
    expect(replSource).toContain("this.ctx.activeExtension = extension");
  });
});

describe("T15: 'eval' verb routes to Lisp compiler", () => {
  test("router dispatches eval to routeEval", () => {
    expect(routerSource).toContain("case 'eval':");
    expect(routerSource).toContain("routeEval");
  });

  test("eval parser accepts the verb without error", () => {
    const cmd = parseCommand(["eval"]);
    expect(cmd.verb).toBe("eval");
  });
});

// ═══════════════════════════════════════════════════════════════
// T16–T18: Anti-Lock Tests
// ═══════════════════════════════════════════════════════════════

describe("T16: Shell package has ZERO React imports", () => {
  test("no 'react' imports in packages/shell/src/", () => {
    const shellFiles = readdirSync(SHELL_SRC).filter(f => f.endsWith(".ts"));
    for (const file of shellFiles) {
      const content = readFileSync(join(SHELL_SRC, file), "utf-8");
      const hasReact = /import\s.*from\s+['"]react['"]/i.test(content) ||
                       /import\s.*from\s+['"]react-dom['"]/i.test(content) ||
                       /require\s*\(\s*['"]react['"]\s*\)/i.test(content);
      expect(hasReact).toBe(false);
    }
  });
});

describe("T17: Shell imports only from service layer, not canvas/UI", () => {
  test("no canvas, UI, or component imports in shell source", () => {
    const shellFiles = readdirSync(SHELL_SRC).filter(f => f.endsWith(".ts"));
    for (const file of shellFiles) {
      const content = readFileSync(join(SHELL_SRC, file), "utf-8");
      const hasUIImport = /from\s+['"].*\/canvas\//i.test(content) ||
                          /from\s+['"].*\/ui\//i.test(content) ||
                          /from\s+['"].*\/components\//i.test(content) ||
                          /from\s+['"].*\.tsx['"]/i.test(content);
      expect(hasUIImport).toBe(false);
    }
  });

  test("shell imports reference only services/ and types/ paths", () => {
    const shellFiles = readdirSync(SHELL_SRC).filter(f => f.endsWith(".ts"));
    for (const file of shellFiles) {
      const content = readFileSync(join(SHELL_SRC, file), "utf-8");
      // Find all imports from workbench
      const workbenchImports = content.match(/from\s+['"]\.\.\/\.\.\/workbench\/src\/[^'"]+['"]/g) ?? [];
      for (const imp of workbenchImports) {
        // Each must reference services/, types/, config/, or plexus/ — never canvas, ui, components
        const isAllowed = imp.includes("/services/") || imp.includes("/types/") || imp.includes("/config/") || imp.includes("/plexus/");
        expect(isAllowed).toBe(true);
      }
    }
  });
});

describe("T18: Shell output goes to stdout/stderr correctly", () => {
  test("no console.log in router, parser, or formatters", () => {
    const restrictedFiles = ["router.ts", "parser.ts", "formatters.ts", "config.ts", "types.ts"];
    for (const file of restrictedFiles) {
      const path = join(SHELL_SRC, file);
      if (!existsSync(path)) continue;
      const content = readFileSync(path, "utf-8");
      const hasConsoleLog = /console\.(log|warn|error|info|debug)\s*\(/g.test(content);
      expect(hasConsoleLog).toBe(false);
    }
  });

  test("index.ts and repl.ts use process.stdout/process.stderr", () => {
    const indexSource = readFileSync(join(SHELL_SRC, "index.ts"), "utf-8");
    const replSource = readFileSync(join(SHELL_SRC, "repl.ts"), "utf-8");

    // index.ts should use process.stdout for output and process.stderr for errors
    expect(indexSource).toContain("process.stdout.write(");
    expect(indexSource).toContain("process.stderr.write(");

    // repl.ts should use process.stdout for command output and process.stderr for prompts/errors
    expect(replSource).toContain("process.stdout.write(");
    expect(replSource).toContain("process.stderr.write(");
  });
});

// ═══════════════════════════════════════════════════════════════
// Anti-regression: shell package structure
// ═══════════════════════════════════════════════════════════════

describe("Anti-regression: shell package completeness", () => {
  test("packages/shell/package.json exists with bin entry", () => {
    const pkg = JSON.parse(readFileSync(join(ROOT, "runtime/shell/package.json"), "utf-8"));
    expect(pkg.name).toBe("@semantos/shell");
    expect(pkg.bin["semantos-shell"]).toBe("./dist/index.js");
  });

  test("all required source files exist", () => {
    const requiredFiles = ["index.ts", "shell.ts", "parser.ts", "router.ts", "formatters.ts", "config.ts", "repl.ts", "types.ts"];
    for (const file of requiredFiles) {
      expect(existsSync(join(SHELL_SRC, file))).toBe(true);
    }
  });

  test("tsconfig.json extends root", () => {
    const tsconfig = JSON.parse(readFileSync(join(ROOT, "runtime/shell/tsconfig.json"), "utf-8"));
    expect(tsconfig.extends).toBe("../../tsconfig.json");
  });
});

```
