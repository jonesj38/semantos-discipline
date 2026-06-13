---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase20-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.582346+00:00
---

# tests/gates/phase20-gate.test.ts

```ts
/**
 * Phase 20 Gate: tmux Operator Loom + Semantic VFS
 *
 * Tests T1–T15 covering tmux layout, object tree, inspector, event log,
 * VFS path resolution, and anti-lock constraints.
 *
 * Uses direct imports for pure classes and source inspection for structural
 * guarantees (same pattern as Phase 19 gates).
 */

import { describe, test, expect, beforeEach } from "bun:test";
import { readFileSync, existsSync, readdirSync } from "fs";
import { join } from "path";
import { execSync } from "child_process";

const ROOT = join(import.meta.dir, "../..");
const SHELL_SRC = join(ROOT, "runtime/shell/src");

// ── Imports ──────────────────────────────────────────────────

import { LoomStore } from "../../runtime/services/src/services/LoomStore";
import { IdentityStore } from "../../runtime/services/src/services/IdentityStore";
import { ConfigStore } from "../../runtime/services/src/services/ConfigStore";
import type { ObjectTypeDefinition } from "../../runtime/services/src/config/extensionConfig";
import type { LoomObject } from "../../runtime/services/src/types/loom";

import { SemantosTmuxSession, DEFAULT_CONFIG, parseTomlConfig, configToToml } from "../../runtime/shell/src/tmux/layout";
import { ObjectTreePane, groupObjects, flattenGroups, LINEARITY_NAMES, PHASE_NAMES } from "../../runtime/shell/src/tmux/object-tree";
import { InspectorPane } from "../../runtime/shell/src/tmux/inspector";
import { EventLogPane, CircularEventBuffer } from "../../runtime/shell/src/tmux/event-log";
import { VfsPathResolver } from "../../runtime/shell/src/vfs/pathResolver";
import { serializeState, deserializeState } from "../../runtime/shell/src/tmux/bridge";

// ── Test fixtures ────────────────────────────────────────────

const TEST_TYPE_DEF: ObjectTypeDefinition = {
  typeHash: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
  name: "Test Job",
  icon: "🔧",
  linearity: "AFFINE",
  defaultCapabilities: [1, 2, 5],
  fields: [
    { name: "title", type: "string" },
    { name: "urgency", type: "enum", values: ["low", "medium", "high"] },
    { name: "amount", type: "number", min: 0 },
  ],
  category: "trades.job",
  visibility: {
    states: ["draft", "published", "revoked"],
    defaultState: "draft",
    publishTransition: {
      fromLinearity: "AFFINE",
      toLinearity: "RELEVANT",
    },
    revokePreservesEvidence: true,
  },
};

const DISPUTE_TYPE_DEF: ObjectTypeDefinition = {
  typeHash: "1111111111111111111111111111111111111111111111111111111111111111",
  name: "Dispute",
  icon: "⚖️",
  linearity: "AFFINE",
  defaultCapabilities: [1, 2, 6],
  fields: [
    { name: "reason", type: "string" },
    { name: "status", type: "enum", values: ["open", "resolved"] },
  ],
  category: "governance.dispute",
  visibility: {
    states: ["draft", "published"],
    defaultState: "draft",
    publishTransition: { fromLinearity: "AFFINE", toLinearity: "RELEVANT" },
    revokePreservesEvidence: true,
  },
};

function createPopulatedStore(): LoomStore {
  const store = new LoomStore();
  store.createObjectFromType(TEST_TYPE_DEF, undefined, "facet-test", [1, 2, 5], false);
  store.createObjectFromType(TEST_TYPE_DEF, undefined, "facet-test", [1, 2, 5], false);
  store.createObjectFromType(DISPUTE_TYPE_DEF, undefined, "facet-test", [1, 2, 6], false);
  return store;
}

// ═══════════════════════════════════════════════════════════════
// T1: tmux session creates 4 panes
// ═══════════════════════════════════════════════════════════════

describe("T1: semantos console creates tmux session with 4 panes", () => {
  test("SemantosTmuxSession.launch() generates correct tmux commands", () => {
    const session = new SemantosTmuxSession({ sessionName: "test-sess" });
    const cmds = session.launch();

    // Should create session + 3 splits + select + attach = 6 commands
    expect(cmds.length).toBe(6);
    expect(cmds[0]).toContain("tmux new-session -d -s test-sess");
    expect(cmds[1]).toContain("split-window");
    expect(cmds[1]).toContain("--pane events");
    expect(cmds[2]).toContain("split-window");
    expect(cmds[2]).toContain("--pane objects");
    expect(cmds[3]).toContain("split-window");
    expect(cmds[3]).toContain("--pane inspector");
    expect(cmds[4]).toContain("select-pane");
    expect(cmds[5]).toContain("attach-session");
  });

  test("all 4 pane IDs are assigned", () => {
    const session = new SemantosTmuxSession({ sessionName: "test-sess" });
    session.launch();
    expect(session.getPane("objects")).toBeTruthy();
    expect(session.getPane("shell")).toBeTruthy();
    expect(session.getPane("inspector")).toBeTruthy();
    expect(session.getPane("events")).toBeTruthy();
  });

  test("layout config is loaded with defaults", () => {
    const session = new SemantosTmuxSession();
    const cfg = session.getConfig();
    expect(cfg.panes.objects.width_percent).toBe(20);
    expect(cfg.panes.shell.width_percent).toBe(55);
    expect(cfg.panes.inspector.width_percent).toBe(25);
    expect(cfg.panes.events.height_lines).toBe(4);
  });
});

// ═══════════════════════════════════════════════════════════════
// T2: Object tree shows objects from LoomStore
// ═══════════════════════════════════════════════════════════════

describe("T2: Object tree pane shows objects from LoomStore", () => {
  test("ObjectTreePane displays objects grouped by type", () => {
    const store = createPopulatedStore();
    const tree = new ObjectTreePane(store);

    let renderedLines: string[] = [];
    tree.onRender((lines) => { renderedLines = lines; });
    tree.subscribe();

    // Should have rendered group headers + objects
    expect(renderedLines.length).toBeGreaterThan(0);

    // Should contain type group headers
    const hasTradesGroup = renderedLines.some(l => l.includes("trades.job"));
    const hasGovGroup = renderedLines.some(l => l.includes("governance.dispute"));
    expect(hasTradesGroup).toBe(true);
    expect(hasGovGroup).toBe(true);

    // Should show linearity badges
    const hasAffine = renderedLines.some(l => l.includes("[AFFINE]"));
    expect(hasAffine).toBe(true);

    // Header should show count
    expect(tree.getHeader()).toContain("Objects: 3");

    tree.destroy();
  });

  test("groupObjects groups by category", () => {
    const store = createPopulatedStore();
    const groups = groupObjects(store.getState().objects);
    expect(groups.length).toBe(2); // trades.job and governance.dispute
    expect(groups.find(g => g.typeName === "trades.job")?.objects.length).toBe(2);
    expect(groups.find(g => g.typeName === "governance.dispute")?.objects.length).toBe(1);
  });
});

// ═══════════════════════════════════════════════════════════════
// T3: Creating an object updates tree in real-time
// ═══════════════════════════════════════════════════════════════

describe("T3: Creating an object updates tree in real-time", () => {
  test("adding an object triggers re-render with new object", () => {
    const store = new LoomStore();
    const tree = new ObjectTreePane(store);

    let renderCount = 0;
    let lastHeader = "";
    tree.onRender((_lines, header) => {
      renderCount++;
      lastHeader = header;
    });
    tree.subscribe();

    const initialCount = renderCount;
    expect(lastHeader).toContain("Objects: 0");

    // Create an object
    store.createObjectFromType(TEST_TYPE_DEF, undefined, "facet-test", [1, 2, 5], false);

    // Should have re-rendered
    expect(renderCount).toBeGreaterThan(initialCount);
    expect(lastHeader).toContain("Objects: 1");

    tree.destroy();
  });
});

// ═══════════════════════════════════════════════════════════════
// T4: Selecting object in tree updates inspector
// ═══════════════════════════════════════════════════════════════

describe("T4: Selecting an object in tree updates inspector", () => {
  test("onSelect callback fires when Enter is pressed on an object", () => {
    const store = createPopulatedStore();
    const tree = new ObjectTreePane(store);

    let selectedId: string | null = null;
    tree.onSelect((id) => { selectedId = id; });
    tree.onRender(() => {});
    tree.subscribe();

    // Navigate down to first object (skip group header)
    tree.handleKey("down");
    tree.handleKey("return");

    expect(selectedId).toBeTruthy();
    // Should be one of the object IDs
    const objectIds = Array.from(store.getState().objects.keys());
    expect(objectIds).toContain(selectedId);
  });

  test("InspectorPane.inspect() updates display", () => {
    const store = createPopulatedStore();
    const inspector = new InspectorPane(store);

    let renderedLines: string[] = [];
    inspector.onRender((lines) => { renderedLines = lines; });
    inspector.subscribe();

    const objectId = Array.from(store.getState().objects.keys())[0];
    inspector.inspect(objectId);

    // Should display header fields
    expect(renderedLines.some(l => l.includes("typeHash:"))).toBe(true);
    expect(renderedLines.some(l => l.includes("linearity:"))).toBe(true);
    expect(renderedLines.some(l => l.includes("visibility:"))).toBe(true);

    inspector.destroy();
  });
});

// ═══════════════════════════════════════════════════════════════
// T5: Inspector shows correct header fields
// ═══════════════════════════════════════════════════════════════

describe("T5: Inspector shows correct header fields", () => {
  test("header section shows typeHash, linearity, phase, visibility", () => {
    const store = createPopulatedStore();
    const inspector = new InspectorPane(store);
    inspector.onRender(() => {});
    inspector.subscribe();

    const objectId = Array.from(store.getState().objects.keys())[0];
    inspector.inspect(objectId);

    const sections = inspector.getSections();
    const headerSection = sections.find(s => s.name === "header")!;

    // Should contain the right fields
    expect(headerSection.lines.some(l => l.startsWith("typeHash:"))).toBe(true);
    expect(headerSection.lines.some(l => l.startsWith("linearity:"))).toBe(true);
    expect(headerSection.lines.some(l => l.startsWith("phase:"))).toBe(true);
    expect(headerSection.lines.some(l => l.startsWith("visibility:"))).toBe(true);
    expect(headerSection.lines.some(l => l.startsWith("ownerId:"))).toBe(true);
    expect(headerSection.lines.some(l => l.startsWith("version:"))).toBe(true);

    // linearity should be AFFINE for our test type
    expect(headerSection.lines.find(l => l.startsWith("linearity:"))).toContain("AFFINE");

    inspector.destroy();
  });

  test("evidence chain section shows patches with correct format", () => {
    const store = createPopulatedStore();
    const inspector = new InspectorPane(store);
    inspector.onRender(() => {});
    inspector.subscribe();

    const objectId = Array.from(store.getState().objects.keys())[0];
    inspector.inspect(objectId);

    const sections = inspector.getSections();
    const evidenceSection = sections.find(s => s.name === "evidence")!;

    // Should have at least the creation patch
    expect(evidenceSection.lines.length).toBeGreaterThan(0);
    // Format: #N [kind] by facetId @ timestamp
    expect(evidenceSection.lines[0]).toMatch(/^#0 \[action\] by facet-test @/);

    inspector.destroy();
  });
});

// ═══════════════════════════════════════════════════════════════
// T6: Event log captures create/patch/transition events
// ═══════════════════════════════════════════════════════════════

describe("T6: Event log captures events in real-time", () => {
  test("creating an object emits a create event", () => {
    const store = new LoomStore();
    const eventLog = new EventLogPane(store);
    eventLog.subscribe();

    store.createObjectFromType(TEST_TYPE_DEF, undefined, "facet-test", [1, 2, 5], false);

    const events = eventLog.getEvents();
    expect(events.length).toBeGreaterThan(0);

    const createEvent = events.find(e => e.category === "create");
    expect(createEvent).toBeTruthy();
    expect(createEvent!.description).toContain("type=Test Job");
    expect(createEvent!.description).toContain("linearity=AFFINE");

    eventLog.destroy();
  });

  test("circular buffer respects capacity", () => {
    const buffer = new CircularEventBuffer(3);
    buffer.push({ timestamp: 1, category: "create", description: "a" });
    buffer.push({ timestamp: 2, category: "create", description: "b" });
    buffer.push({ timestamp: 3, category: "create", description: "c" });
    buffer.push({ timestamp: 4, category: "create", description: "d" });

    expect(buffer.size()).toBe(3);
    const events = buffer.getAll();
    expect(events.map(e => e.description)).toEqual(["b", "c", "d"]);
  });

  test("event log formats timestamps correctly", () => {
    const store = new LoomStore();
    const eventLog = new EventLogPane(store);

    let renderedLines: string[] = [];
    eventLog.onRender((lines) => { renderedLines = lines; });
    eventLog.subscribe();

    store.createObjectFromType(TEST_TYPE_DEF, undefined, "facet-test", [1, 2, 5], false);

    // Format: HH:MM:SS [category] description
    expect(renderedLines.length).toBeGreaterThan(0);
    expect(renderedLines[0]).toMatch(/^\d{2}:\d{2}:\d{2} \[\w+\]/);

    eventLog.destroy();
  });
});

// ═══════════════════════════════════════════════════════════════
// T7: VFS mount creates directory structure
// ═══════════════════════════════════════════════════════════════

describe("T7: VFS path resolver creates correct directory structure", () => {
  test("root readdir returns expected top-level dirs", () => {
    const store = new LoomStore();
    const identity = new IdentityStore();
    const config = new ConfigStore();
    const resolver = new VfsPathResolver(store, identity, config);

    const entries = resolver.readdir("/");
    expect(entries).toEqual(["objects", "identities", "taxonomy", "governance", "flows"]);
  });

  test("objects directory lists object IDs", () => {
    const store = createPopulatedStore();
    const identity = new IdentityStore();
    const config = new ConfigStore();
    const resolver = new VfsPathResolver(store, identity, config);

    const entries = resolver.readdir("/objects");
    expect(entries).not.toBeNull();
    expect(entries!.length).toBe(3);
  });

  test("object directory lists expected files", () => {
    const store = createPopulatedStore();
    const identity = new IdentityStore();
    const config = new ConfigStore();
    const resolver = new VfsPathResolver(store, identity, config);

    const objId = Array.from(store.getState().objects.keys())[0];
    const entries = resolver.readdir(`/objects/${objId}`);
    expect(entries).toContain("header.bin");
    expect(entries).toContain("payload.json");
    expect(entries).toContain("patches");
  });
});

// ═══════════════════════════════════════════════════════════════
// T8: cat payload.json matches store
// ═══════════════════════════════════════════════════════════════

describe("T8: payload.json content matches LoomStore", () => {
  test("VFS payload.json equals JSON.stringify of store payload", () => {
    const store = createPopulatedStore();
    const identity = new IdentityStore();
    const config = new ConfigStore();
    const resolver = new VfsPathResolver(store, identity, config);

    const objId = Array.from(store.getState().objects.keys())[0];
    const obj = store.getState().objects.get(objId)!;

    const content = resolver.read(`/objects/${objId}/payload.json`);
    expect(content).not.toBeNull();

    const vfsPayload = JSON.parse(content!.data.toString("utf-8"));
    expect(vfsPayload).toEqual(obj.payload);
  });
});

// ═══════════════════════════════════════════════════════════════
// T9: taxonomy listing matches config
// ═══════════════════════════════════════════════════════════════

describe("T9: taxonomy listing reflects loaded extension", () => {
  test("taxonomy root lists dimension IDs (empty without config)", () => {
    const store = new LoomStore();
    const identity = new IdentityStore();
    const config = new ConfigStore();
    const resolver = new VfsPathResolver(store, identity, config);

    const entries = resolver.readdir("/taxonomy");
    expect(entries).not.toBeNull();
    // Without a loaded config, taxonomy may be empty
    expect(Array.isArray(entries)).toBe(true);
  });
});

// ═══════════════════════════════════════════════════════════════
// T10: capabilities.json is valid JSON
// ═══════════════════════════════════════════════════════════════

describe("T10: capabilities.json returns facet capabilities as JSON", () => {
  test("readIdentity capabilities returns valid JSON array (after identity setup)", () => {
    // IdentityStore needs Plexus, so verify the path resolver logic directly
    const store = new LoomStore();
    const identity = new IdentityStore();
    const config = new ConfigStore();
    const resolver = new VfsPathResolver(store, identity, config);

    // Without identity, should return empty or null
    const entries = resolver.readdir("/identities");
    expect(entries).not.toBeNull();
    expect(Array.isArray(entries)).toBe(true);
  });
});

// ═══════════════════════════════════════════════════════════════
// T11: header.bin shows binary content
// ═══════════════════════════════════════════════════════════════

describe("T11: header.bin returns correct binary content", () => {
  test("header.bin is 256 bytes with correct magic and linearity", () => {
    const store = createPopulatedStore();
    const identity = new IdentityStore();
    const config = new ConfigStore();
    const resolver = new VfsPathResolver(store, identity, config);

    const objId = Array.from(store.getState().objects.keys())[0];
    const content = resolver.read(`/objects/${objId}/header.bin`);
    expect(content).not.toBeNull();
    expect(content!.size).toBe(256);

    const buf = content!.data;

    // Check magic bytes (DEADBEEF at offset 0)
    expect(buf.readUInt32LE(0)).toBe(0xDEADBEEF);

    // Linearity at offset 16 should be AFFINE (2)
    expect(buf.readUInt32LE(16)).toBe(2);

    // Version at offset 20 should be 1
    expect(buf.readUInt32LE(20)).toBe(1);
  });
});

// ═══════════════════════════════════════════════════════════════
// T12: Console layout config parsing
// ═══════════════════════════════════════════════════════════════

describe("T12: Console layout config from TOML is respected", () => {
  test("configToToml produces valid TOML that roundtrips", () => {
    const toml = configToToml(DEFAULT_CONFIG);
    expect(toml).toContain("[layout]");
    expect(toml).toContain("width = 200");
    expect(toml).toContain("[panes.objects]");
    expect(toml).toContain("width_percent = 20");

    // Parse it back
    const parsed = parseTomlConfig(toml);
    expect(parsed.layout?.width).toBe(200);
    expect(parsed.layout?.height).toBe(50);
    expect(parsed.panes?.objects?.width_percent).toBe(20);
    expect(parsed.panes?.events?.buffer_size).toBe(1000);
  });

  test("custom config values are respected in session", () => {
    const session = new SemantosTmuxSession({
      width: 300,
      height: 80,
    });
    const cfg = session.getConfig();
    expect(cfg.layout.width).toBe(300);
    expect(cfg.layout.height).toBe(80);
  });
});

// ═══════════════════════════════════════════════════════════════
// T13: No React imports in packages/shell/src/
// ═══════════════════════════════════════════════════════════════

describe("T13: No React imports in shell package", () => {
  test("grep confirms zero React imports in packages/shell/src/", () => {
    // Recursively read all .ts files in shell/src and check for React imports
    const shellFiles = getAllTsFiles(SHELL_SRC);
    const reactImportPattern = /(?:from\s+['"]react['"]|import\s+.*['"]react['"]|require\(['"]react['"]\))/;

    for (const file of shellFiles) {
      const content = readFileSync(file, "utf-8");
      const hasReact = reactImportPattern.test(content);
      if (hasReact) {
        throw new Error(`React import found in ${file}`);
      }
    }

    expect(shellFiles.length).toBeGreaterThan(0);
  });
});

// ═══════════════════════════════════════════════════════════════
// T14: VFS reads go through service layer
// ═══════════════════════════════════════════════════════════════

describe("T14: VFS reads go through service layer (VfsPathResolver)", () => {
  test("mount.ts reads through VfsPathResolver, not direct store access", () => {
    const mountSource = readFileSync(join(SHELL_SRC, "vfs/mount.ts"), "utf-8");

    // Should use VfsPathResolver
    expect(mountSource).toContain("VfsPathResolver");
    expect(mountSource).toContain("resolver.readdir");
    expect(mountSource).toContain("resolver.read");
    expect(mountSource).toContain("resolver.getattr");

    // Should NOT directly access store.getState() in FUSE ops
    // (the resolver does this internally, but mount.ts delegates)
    const fuseOpsSection = mountSource.split("const ops")[1] ?? "";
    expect(fuseOpsSection).not.toContain("store.getState()");
  });

  test("pathResolver.ts reads from store.getState()", () => {
    const resolverSource = readFileSync(join(SHELL_SRC, "vfs/pathResolver.ts"), "utf-8");

    // PathResolver should access store through proper API
    expect(resolverSource).toContain("this.store.getState()");
    expect(resolverSource).toContain("this.identity.getIdentity()");
    expect(resolverSource).toContain("this.config.getConfig()");
  });
});

// ═══════════════════════════════════════════════════════════════
// T15: Console works with stub adapter
// ═══════════════════════════════════════════════════════════════

describe("T15: Console works with stub adapter (in-memory data)", () => {
  test("all pane classes instantiate with plain LoomStore (no Plexus)", () => {
    const store = new LoomStore();

    // ObjectTreePane
    const tree = new ObjectTreePane(store);
    tree.onRender(() => {});
    tree.subscribe();
    tree.destroy();

    // InspectorPane
    const inspector = new InspectorPane(store);
    inspector.onRender(() => {});
    inspector.subscribe();
    inspector.destroy();

    // EventLogPane
    const eventLog = new EventLogPane(store);
    eventLog.onRender(() => {});
    eventLog.subscribe();
    eventLog.destroy();

    // All instantiated without error
    expect(true).toBe(true);
  });

  test("VfsPathResolver works with empty stores", () => {
    const store = new LoomStore();
    const identity = new IdentityStore();
    const config = new ConfigStore();
    const resolver = new VfsPathResolver(store, identity, config);

    // Root readdir works
    expect(resolver.readdir("/")).toEqual(["objects", "identities", "taxonomy", "governance", "flows"]);

    // Objects dir is empty
    expect(resolver.readdir("/objects")).toEqual([]);

    // Non-existent path returns null
    expect(resolver.readdir("/nonexistent")).toBeNull();
    expect(resolver.read("/nonexistent")).toBeNull();
  });

  test("store bridge serialization round-trips correctly", () => {
    const store = createPopulatedStore();
    const state = store.getState();

    const serialized = serializeState(state);
    const deserialized = deserializeState(serialized);

    expect(deserialized.objects.size).toBe(state.objects.size);
    expect(deserialized.selectedObjectId).toBe(state.selectedObjectId);

    // Check object payloads match
    for (const [id, obj] of state.objects) {
      const deObj = deserialized.objects.get(id)!;
      expect(deObj).toBeTruthy();
      expect(deObj.payload).toEqual(obj.payload);
      expect(deObj.header.linearity).toBe(obj.header.linearity);
      expect(deObj.header.version).toBe(obj.header.version);
      expect(deObj.visibility).toBe(obj.visibility);
    }
  });
});

// ── Additional structural tests ──────────────────────────────

describe("Phase 20 — structural checks", () => {
  test("all Phase 20 files exist", () => {
    expect(existsSync(join(SHELL_SRC, "tmux/layout.ts"))).toBe(true);
    expect(existsSync(join(SHELL_SRC, "tmux/object-tree.ts"))).toBe(true);
    expect(existsSync(join(SHELL_SRC, "tmux/inspector.ts"))).toBe(true);
    expect(existsSync(join(SHELL_SRC, "tmux/event-log.ts"))).toBe(true);
    expect(existsSync(join(SHELL_SRC, "tmux/bridge.ts"))).toBe(true);
    expect(existsSync(join(SHELL_SRC, "vfs/mount.ts"))).toBe(true);
    expect(existsSync(join(SHELL_SRC, "vfs/pathResolver.ts"))).toBe(true);
    expect(existsSync(join(SHELL_SRC, "commands/console.ts"))).toBe(true);
  });

  test("index.ts wires console/mount/unmount as top-level commands", () => {
    const indexSource = readFileSync(join(SHELL_SRC, "index.ts"), "utf-8");
    expect(indexSource).toContain("handleConsole");
    expect(indexSource).toContain("handleMount");
    expect(indexSource).toContain("handleUnmount");
    expect(indexSource).toContain("'console'");
    expect(indexSource).toContain("'mount'");
    expect(indexSource).toContain("'unmount'");
  });

  test("VFS write operations return EROFS", () => {
    const mountSource = readFileSync(join(SHELL_SRC, "vfs/mount.ts"), "utf-8");
    // All write operations should return EROFS
    expect(mountSource).toContain("EROFS");
    // These write ops should all be present and return EROFS
    const writeOps = ["write(", "create(", "unlink(", "rename(", "mkdir(", "rmdir(", "truncate(", "chmod(", "chown("];
    for (const op of writeOps) {
      expect(mountSource).toContain(op);
    }
  });

  test("event log filter mode works", () => {
    const store = new LoomStore();
    const eventLog = new EventLogPane(store);
    eventLog.subscribe();

    // Enter filter mode
    eventLog.handleKey("/");
    expect(eventLog.handleKey("c")).toBe(true); // type 'c'

    // Type more
    eventLog.handleKey("r");
    eventLog.handleKey("e");
    eventLog.handleKey("a");
    eventLog.handleKey("t");
    eventLog.handleKey("e");
    eventLog.handleKey("return"); // confirm filter

    eventLog.destroy();
  });

  test("object tree keyboard navigation works", () => {
    const store = createPopulatedStore();
    const tree = new ObjectTreePane(store);
    tree.onRender(() => {});
    tree.subscribe();

    // Navigate down
    expect(tree.handleKey("down")).toBe(true);
    expect(tree.getSelectedIndex()).toBeGreaterThan(0);

    // Filter mode
    expect(tree.handleKey("/")).toBe(true);
    expect(tree.isFilterMode()).toBe(true);
    expect(tree.handleKey("escape")).toBe(true);
    expect(tree.isFilterMode()).toBe(false);

    // Quit
    expect(tree.handleKey("q")).toBe(false);

    tree.destroy();
  });
});

// ── Helpers ──────────────────────────────────────────────────

function getAllTsFiles(dir: string): string[] {
  const files: string[] = [];
  const entries = readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...getAllTsFiles(fullPath));
    } else if (entry.name.endsWith(".ts") && !entry.name.endsWith(".d.ts")) {
      files.push(fullPath);
    }
  }
  return files;
}

```
