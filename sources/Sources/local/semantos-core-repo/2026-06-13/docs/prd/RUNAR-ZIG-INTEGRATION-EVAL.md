---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/RUNAR-ZIG-INTEGRATION-EVAL.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.716078+00:00
---

# Rúnar-Zig SDK integration evaluation

**Version**: 0.1
**Date**: 2026-05-25
**Status**: EVAL MEMO — task #34 deliverable
**Master document**: [`UNIFICATION-ROADMAP.md` §11.10](UNIFICATION-ROADMAP.md)
**Sister docs**:
- [`ANCHOR-BACKEND-BRIDGE.md`](ANCHOR-BACKEND-BRIDGE.md) §0 — Rúnar/BSVM theoretical frame
- [`POLICY-RUNTIME-EXECUTOR-ADAPTER.md`](POLICY-RUNTIME-EXECUTOR-ADAPTER.md) — predicate-execution seam
- Upstream: `github.com/icellan/runar` (pushed 2026-05-25)

---

## TL;DR

**Recommendation: YES, integrate.** Specifically: adopt **Option A (build-time compilation)** — cartridges author preconditions as `.runar.zig` source files; the cartridge's `build.zig` invokes the runar-zig compiler at build time and emits Bitcoin Script hex as a Zig const. PolicyRuntime's `evaluateReal` (PR-2b) executes the hex unchanged. **Zero brain runtime cost; eliminates the "how do cartridges author opcode bytes" sharp edge; license + version + ABI all compatible.**

**Three caveats:**
1. **Plexus-extension opcodes (`OP_CHECKLINEARTYPE` 0xC0–0xC7, `OP_READPAYLOAD` 0xCC, etc.) are NOT in Bitcoin Script standard.** Rúnar will not emit them today. Cartridges needing Plexus enforcement either (a) hand-write those leaves and concatenate, or (b) extend Rúnar with custom builtins (upstream contribution work).
2. **Tx-context-bearing opcodes (`OP_CHECKSIG`) work in real-executor mode but PR-2b stubs `tx_context = null` (Phase 1).** Predicates that compile to `checkSig` calls will fail at runtime until Phase 2 lands.
3. **The runar-zig compiler is in `compilers/zig/`, not `packages/runar-zig/`** — the SDK package is the *contract-author runtime + deployment SDK*; the compiler is a separate Zig 0.15 binary. Build integration imports both.

**Sequencing recommendation**: propose §11.10 order **4b** for the integration. Three sub-orders mirror the PR-2a/2b/4a pattern:

| Order | Scope | Effort |
|---|---|---|
| 4b-1 | Add Rúnar repo as `build.zig.zon` dependency; produce a single "hello, OP_1" pilot script for a brain inline test | ~half day |
| 4b-2 | Build-time compile path: a cartridge `.runar.zig` → bundled hex `const`; smoke through `intent_cells_handler`'s PolicyRuntime call site | ~1 day |
| 4b-3 | Document the cartridge-author surface in `docs/cartridge-author-guide.md`; add a `runar` field to cartridge manifests | ~half day |

Total: **~2 days** for the seam + one consumer; cartridge migration is per-cartridge after.

---

## §1 What the runar-zig SDK actually ships

Surveyed from `github.com/icellan/runar` at commit on `main` (pushed 2026-05-25):

### Two distinct Zig packages

| Package | Purpose | Lives at |
|---|---|---|
| `packages/runar-zig` | **Contract-author runtime** + deployment SDK + ANF interpreter for off-chain simulation. Importable as `@import("runar")` in a `.runar.zig` source file. | `packages/runar-zig/src/` |
| `compilers/zig` | **The compiler binary** (`runar-zig` CLI). Parse → validate → typecheck → ANF → stack → emit. Takes `.runar.{zig,ts,sol,move,go,rs,py,rb,java}` source, emits hex + artifact JSON. | `compilers/zig/src/` |

Brain integration needs BOTH — the compiler at build time (turns source into bytes), the SDK at author time (the `@import("runar")` cartridge-side surface).

### Author-time surface (`packages/runar-zig/src/base.zig`)

The contract-author DSL surface, lightly excerpted:

```zig
pub const Int = i64;
pub const Bigint = i64;
pub const PubKey = []const u8;
pub const Sig = []const u8;
pub const Addr = []const u8;
pub const ByteString = []const u8;
pub const Sha256 = []const u8;
pub const Ripemd160 = []const u8;
pub const SigHashPreimage = []const u8;

pub const SmartContract = struct {};
pub const UnsafeSmartContract = struct {};  // for asm() raw-script escape
pub const StatefulSmartContract = struct {}; // for OP_PUSH_TX state threading

pub const AsmArgs = struct { body: []const u8 };  // raw-hex escape hatch
```

A contract is a Zig `struct` with a `Contract` marker, readonly properties (the constructor-baked-in values), and one or more `pub fn` methods. From `script_integration_test.zig`:

```zig
const runar = @import("runar");

pub const P2PKH = struct {
    pub const Contract = runar.SmartContract;

    pubKeyHash: runar.Addr,

    pub fn init(pubKeyHash: runar.Addr) P2PKH {
        return .{ .pubKeyHash = pubKeyHash };
    }

    pub fn unlock(self: *const P2PKH, sig: runar.Sig, pubKey: runar.PubKey) void {
        runar.assert(runar.bytesEq(runar.hash160(pubKey), self.pubKeyHash));
        runar.assert(runar.checkSig(sig, pubKey));
    }
};
```

`runar.assert(...)` compiles to a Bitcoin Script predicate that ends with truthy-top-of-stack-on-pass. **Exactly the shape PolicyRuntime.evaluate expects.**

### Compile API (`compilers/zig/src/compiler_api.zig`)

```zig
pub const CompileResult = struct {
    script_hex: []const u8,
    artifact_json: ?[]const u8,
    pub fn deinit(self: CompileResult, allocator: std.mem.Allocator) void { ... }
};

pub const CompileError = error{ ParseFailed, ValidationFailed, TypeCheckFailed, ... };

// Plus a CLI: `runar-zig compile <file.runar.zig>` → JSON to stdout
//             `runar-zig --source <file> --hex` → script hex only
```

The CLI's `--hex` mode is the simplest build integration surface: invoke from `build.zig` as a `b.addSystemCommand(...)`, capture stdout, write as a generated file.

### Validation-only API (`packages/runar-zig/src/compile_check.zig`)

```zig
pub fn compileCheckSource(allocator, source, file_name) !CompileCheckResult;

pub const CompileCheckResult = struct {
    stage: ?CompileCheckStage,  // null on success; .parse/.validate/.typecheck on failure
    messages: []const []const u8,
    pub fn ok(self: CompileCheckResult) bool { return self.stage == null; }
};
```

This is for dev-time linting (a cartridge can verify its source compiles without producing bytes). Useful for our `zig build test` cartridge-test pass.

---

## §2 Wire-format compatibility with PolicyRuntime

The load-bearing question: **does the hex Rúnar emits work as `policy_bytes` for `PolicyRuntime.evaluateReal`?**

**Answer: yes, for the standard Bitcoin Script opcode set.**

| Surface | What it emits / accepts |
|---|---|
| Rúnar `compilers/zig/src/codegen/emit.zig` | Hex-encoded Bitcoin Script bytes (per Genesis-restored BSV spec) |
| Cell-engine `core/cell-engine/src/opcodes/standard.zig` | Same Genesis-restored Bitcoin Script opcode set (lines 44–215) |
| `PolicyRuntime.evaluateReal` (PR-2b) | Calls `ctx.loadScript(policy_bytes)` → `executor.execute(&ctx)` → maps `ExecuteError` → `rejection_code`. `policy_bytes` is opaque opcode bytes; provenance doesn't matter |

**Verified compatibility:**
- `OP_DUP` (0x76), `OP_EQUALVERIFY` (0x88), `OP_CHECKSIG` (0xAC), arithmetic, `OP_HASH160` (0xA9), `OP_RIPEMD160` (0xA6), `OP_SHA256` (0xA8) — all in both
- Push opcodes (0x01–0x4B, `OP_PUSHDATA1/2/4`) — both
- Conditionals (`OP_IF`, `OP_ELSE`, `OP_ENDIF`, `OP_VERIFY`) — both
- Arithmetic + boolean ops (`OP_ADD`, `OP_SUB`, `OP_MUL`, `OP_BOOLAND`, `OP_NUMEQUAL` ...) — both
- Stack manipulation (`OP_DROP`, `OP_DUP`, `OP_SWAP`, `OP_ROT`, `OP_PICK`, `OP_ROLL`) — both

A Rúnar-compiled predicate that uses only these survives `evaluateReal` unchanged.

### Caveat 1 — Plexus-extension opcodes (0xC0–0xC7, 0xCC, etc.)

The cell-engine's `core/cell-engine/src/opcodes/plexus.zig` defines extension opcodes the standard Bitcoin Script spec doesn't have:

| Opcode | Hex | Purpose |
|---|---|---|
| `OP_CHECKLINEARTYPE` | 0xC0 | Linearity (cell-consumes-once) |
| `OP_CHECKAFFINETYPE` | 0xC1 | Affineness (cell-consumes-at-most-once) |
| `OP_CHECKRELEVANTTYPE` | 0xC2 | Relevance (cell-must-be-used) |
| `OP_CHECKCAPABILITY` | 0xC3 | Capability presented matches expectation |
| `OP_CHECKIDENTITY` | 0xC4 | Identity proof check |
| `OP_CHECKDOMAINFLAG` | 0xC6 | Domain flag matches cell schema |
| `OP_CHECKTYPEHASH` | 0xC7 | TypeHash matches |
| `OP_READPAYLOAD` | 0xCC | Load bytes from canonical cell payload region |

**Rúnar does NOT emit these.** Its codegen is targeted at deployable BSV Bitcoin Script. Cartridges that need to enforce Plexus semantics inside a precondition have three options:

- **(a) Hand-write the Plexus leaves** as `runar.asm(.{ .body = "c0" })` raw-hex escapes — works today, loses type-safety for those leaves
- **(b) Don't use Plexus opcodes in preconditions** — keep precondition logic at the standard-opcode level; let the cell-engine enforce Plexus invariants separately at cell-write time (this is how PR-2b's first consumer `intent_cells_handler` operates)
- **(c) Upstream Rúnar contribution** — add Plexus opcodes as Zig DSL builtins (`runar.checkLinearType(...)`, `runar.readPayload(...)`). Highest value-per-LOC; out of scope for the initial integration

**Recommendation**: start with (b) for the pilot; revisit (c) after a cartridge author hits the wall.

### Caveat 2 — `tx_context = null` (PR-2b Phase 1)

PR-2b's `evaluateReal` passes `tx_context = null` to `ExecutionContext.init`. This means **any opcode that needs the spending tx context will fail**:

- `OP_CHECKSIG`, `OP_CHECKSIGVERIFY`, `OP_CHECKMULTISIG`, `OP_CHECKMULTISIGVERIFY`
- BSV-specific introspection (`OP_PUSH_TX`, `OP_PUSH_TX_STATE`, etc.) — needed for `StatefulSmartContract` patterns

Rúnar's flagship P2PKH example uses `checkSig`. **It will compile fine, but fail at runtime against PolicyRuntime today.**

This is a Phase 1 limitation called out in `POLICY-RUNTIME-EXECUTOR-ADAPTER.md` §2 D3. Phase 2 lands when task #16 (real anchor backend) provides the spend-tx context. For the initial integration, cartridges should author preconditions that **don't rely on tx-context-bearing opcodes**:

- Field-equality checks (`runar.assert(self.amount == 100)`)
- Hash-preimage checks (`runar.assert(runar.bytesEq(runar.sha256(secret), self.commitment))`)
- Range constraints (`runar.assert(value > self.minimum)`)
- Type-tag checks
- Conditional branching

All of these compile to opcodes PolicyRuntime executes today. **The cartridge surface this opens is already large.**

---

## §3 Build integration

### Option A (recommended): build-time compilation

**Pattern**: each cartridge with Rúnar-authored preconditions ships its `.runar.zig` source files. The cartridge's `build.zig` runs the runar-zig compiler at build time. The output hex is written as a generated `.zig` file that `@embedFile`s or declares it as `const POLICY_BYTES: []const u8 = "76a914...";`. Cartridge handlers load this constant and pass it to `PolicyRuntime.evaluate(policy_bytes, ...)`.

**Pros:**
- Zero brain runtime cost (no compiler in the runtime binary)
- Compile errors caught at `zig build` time, not at first cartridge invocation
- Hex bytes are reviewable in git diff (security audit surface)
- Determinism guarantee Rúnar provides (byte-identical output across 7 compilers) is leveraged at the natural place — cartridge build
- Matches the Rúnar conformance discipline: each cartridge build asserts its produced hex matches the expected golden

**Cons:**
- Build-time toolchain coupling: a brain-side `zig build` needs the Rúnar binary available. Mitigated by adding Rúnar as a `build.zig.zon` dependency (the Zig package manager handles fetch + lock automatically)
- Less dynamic — a cartridge can't compile a new precondition at runtime. Acceptable: cartridge preconditions are policy code, not user input

### Option B (rejected for now): runtime compilation

**Pattern**: the brain embeds the runar-zig compiler. Cartridges call a `cell_signer`-shaped seam: `PrecondCompiler.compile(source) → policy_bytes`. Hex bytes never appear in source.

**Pros:**
- Cartridges can compose preconditions dynamically (e.g., parameterized by runtime state)
- No build-step coupling

**Cons:**
- Compiler-in-brain adds ~3 MB+ binary footprint (compilers/zig is the full pipeline)
- Compile errors land at runtime instead of `zig build` — bad DX for cartridge authors
- Wright-frame discipline: deterministic predicates should be reviewable + auditable; runtime-compiled bytes are neither

Rejected pending a real use case that needs dynamism.

### `build.zig.zon` integration sketch

```zig
// runtime/semantos-brain/build.zig.zon (new dependency)
.dependencies = .{
    .runar = .{
        .url = "https://github.com/icellan/runar/archive/<pinned-commit>.tar.gz",
        .hash = "<computed-by-zig-fetch>",
    },
    // ... existing deps
},
```

```zig
// runtime/semantos-brain/build.zig (new step for each cartridge using Rúnar)
const runar_dep = b.dependency("runar", .{ .target = target, .optimize = optimize });
const runar_compiler = runar_dep.artifact("runar-zig");

// For each cartridge .runar.zig source:
const compile_policy = b.addRunArtifact(runar_compiler);
compile_policy.addArg("--source");
compile_policy.addFileArg(b.path("cartridges/oddjobz/brain/zig/src/intent_cell_precondition.runar.zig"));
compile_policy.addArg("--hex");
const hex_out = compile_policy.captureStdOut();

// Bundle as a generated module:
const policy_const = b.addWriteFiles().addCopyFileToSource(hex_out, "src/generated/intent_cell_precondition.hex");
intent_cells_handler_mod.addImport("intent_cell_precondition_hex", policy_const);
```

**Estimated cost**: ~1 hour to get the first cartridge wired; subsequent cartridges are 10 minutes each.

---

## §4 Conformance discipline adoption

Rúnar's flagship property is **byte-identical output across all 7 compiler implementations** for every fixture. This is enforced in CI: `frontend parity` (all 7 parsers accept all 9 formats) + `Stack-IR + hex parity` (per-fixture cross-tier hex matching).

Our cross-language fixtures (e.g. `intent_cell_envelope_fixture.json` — Dart + Zig agree on decode) are the same pattern at smaller scale.

**Recommendation**: adopt Rúnar's per-cartridge conformance gate verbatim. Each cartridge that ships a `.runar.zig` policy file commits two artifacts to git:

1. The `.runar.zig` source
2. The compiled hex (`.expected.hex` golden)

The cartridge build asserts `compile(source) == golden`. Drift detection runs at `zig build`. Same shape Rúnar uses for its 56 fixtures.

This gives us:
- **Audit reviewability**: hex changes are reviewable in PR diff (security-critical for predicate-bearing cells)
- **Cross-compiler-version sanity**: if a future runar-zig update changes codegen for any opcode, our goldens catch the drift before it reaches production
- **Determinism guarantee inheritance**: Rúnar proves source → bytes is deterministic; our golden gate proves our build pipeline preserves that determinism end-to-end

---

## §5 License + version compatibility

| Surface | Status |
|---|---|
| **License** | MIT (per `LICENSE` in the repo). Compatible with our existing brain MIT-likes; no concerns |
| **Zig version** | Rúnar requires **Zig 0.15.x** (per `docs/getting-started.md`). **Exact match for our brain** (per memory `semantos_cli_modularize_pattern`) |
| **Build system** | `build.zig` + `build.zig.zon` — same as ours |
| **Standard library** | Uses `std.crypto.hash.sha2`, `std.crypto.sign.ecdsa.EcdsaSecp256k1Sha256`, `std.json` — same surfaces we use throughout the brain |
| **External deps** | `bsvz` (Zig BSV primitives) — we already depend on `bsvz` for `bsvz.primitives.ec.PrivateKey`, etc. (see `cell_signer.zig` + `hat_bkds.zig`). **Zero net new transitive deps** |

The integration is **drop-in compatible** at the toolchain level. No new language, no new build system, no new transitive dep tree.

---

## §6 Risks + mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Rúnar repo is pushed-today (2026-05-25), actively evolving — API churn risk | Medium | Pin to specific commit in `build.zig.zon`. Bump deliberately + run cartridge golden tests on every bump |
| Plexus-opcode gap (§2 caveat 1) | Low | Use approach (b) — preconditions stay at standard-opcode level; Plexus enforcement stays in the cell-engine |
| Phase-1 tx_context limit (§2 caveat 2) | Low | Cartridge authors get clear "this opcode needs Phase 2" error in docs; high-signal authoring guidance |
| Build-time toolchain coupling | Low | `build.zig.zon` handles fetch + lock; CI gets it for free; offline dev needs cached deps (standard Zig pattern) |
| Compiler bug in runar-zig produces wrong bytes | Low | Rúnar's 7-compiler conformance gate + per-cartridge goldens catch this; Lean verification at `runar-verification/` provides additional defence |
| Upstream relicensing | Very low | MIT today; if Rúnar relicenses to non-permissive, our `build.zig.zon` pin holds. Fork is always an option |

---

## §7 Proposed §11.10 order 4b sequence

| Order | Scope | Effort | Gates on |
|---|---|---|---|
| **4b-1** | Add runar as `build.zig.zon` dep. Pin commit. Single inline test in `runtime/semantos-brain/src/policy_runtime.zig`: compile a hello-world `runar.assert(true)` (or `runar.assert(1 == 1)`) source via `b.addRunArtifact`; pass output bytes to `evaluateReal`; assert `ok=true`. **Substrate**, no cartridge changes | ~half day | #657 (PR-2b), #661 (anchor design doc) merge |
| **4b-2** | First cartridge consumer: `intent_cells_handler` precondition lifted from hand-emitted opcode bytes (or `UQ==` hardcoded) to a `.runar.zig` source compiled at build time. Add the per-cartridge `.expected.hex` golden gate | ~1 day | 4b-1 |
| **4b-3** | Author guide: `docs/cartridge-author-guide.md` covering the runar.assert / runar.bytesEq / runar.sha256 / runar.hash160 surface, Phase-1 limitations, the goldens convention. Add `runar` field to cartridge manifests | ~half day | 4b-2 |
| **4b-4** *(optional, deferred)* | Upstream Plexus-opcode contribution to Rúnar: `runar.checkLinearType`, `runar.readPayload`, etc. Lands as a PR to icellan/runar | TBD — depends on Rúnar maintainer | All above + a real cartridge needing it |

Total for 4b-1/2/3 to land in our repo: **~2 days**. After 4b-3, cartridge migration is per-cartridge and ~10-30 minutes per precondition.

---

## §8 Recommendation

**Land §11.10 order 4b** in the next /loop wave after PRs #657 + #660 + #661 merge. Start with 4b-1 (substrate-only smoke). 4b-2 picks `intent_cells_handler` as the first consumer — symmetric with PR-2b's "intent_cells flips first because smoke fixtures are smallest" rationale.

**Strategic value:** this is the closest the brain gets to closing the "one brain, many cartridges" sharp edge Todd named on 2026-05-25. Cartridges currently emit opcode bytes by hand (or by-Dart-via-base64). Rúnar makes the authoring surface a language they already know (Zig — the brain's native language) with **formal verification underneath**.

**Non-strategic value:** the Plexus-opcode gap (§2 caveat 1) is a real but bounded thing. The standard-opcode surface is already big enough to express the precondition vocabulary current cartridges need.

---

## §9 Change log

- **v0.1** (2026-05-25) — Initial evaluation memo. Drafted from direct inspection of `github.com/icellan/runar` (pushed 2026-05-25, commit on `main`). Recommends YES with Option A (build-time compilation); proposes §11.10 order 4b with 3 sub-orders + 1 optional upstream contribution.
