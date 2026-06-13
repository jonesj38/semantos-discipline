---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/cartridge-author-guide-runar.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.333596+00:00
---

# Cartridge author guide — Rúnar-compiled preconditions

**Status**: §11.10 order 4b-2 (PR-4b-2 — this document)
**Scope**: how cartridge authors write Bitcoin Script preconditions for `PolicyRuntime.evaluateReal` (PR-2b) using the Rúnar compiler suite (`github.com/icellan/runar`)
**Prerequisites**: read [`POLICY-RUNTIME-EXECUTOR-ADAPTER.md`](prd/POLICY-RUNTIME-EXECUTOR-ADAPTER.md) and [`RUNAR-ZIG-INTEGRATION-EVAL.md`](prd/RUNAR-ZIG-INTEGRATION-EVAL.md) first

---

## TL;DR

Cartridge authors write Bitcoin-Script predicates in a high-level language (Go DSL today; TypeScript/Rust/Python/Ruby/Java/Zig as Rúnar tiers stabilise), compile them **offline** via Rúnar, and commit **both** the source AND the compiled hex into the cartridge tree. The brain build does NOT need Rúnar or any compiler toolchain — it just reads the pre-compiled hex as bytes and hands them to `PolicyRuntime.evaluateReal`.

Per Todd 2026-05-25 (in response to PR #664's three integration options): **option (c) — pre-compile + goldens, no need for Go toolchain in the brain build**.

---

## §1 The workflow

```
┌──────────────────┐    ┌──────────────────────────┐    ┌────────────────┐
│ cartridge author │ -> │ Rúnar compiler (offline) │ -> │ commit BOTH    │
│ writes .runar.go │    │ runar-go -source X -hex  │    │ source + .hex  │
└──────────────────┘    └──────────────────────────┘    └────────────────┘
                                                                 │
                                                                 ▼
┌──────────────────────────────────────────────────────────────────┐
│ brain build: @embedFile("X.expected.hex"); hexDecode → policy_bytes │
│ → PolicyRuntime.evaluateReal(policy_bytes, context)                │
└──────────────────────────────────────────────────────────────────┘
```

The brain build is **toolchain-independent of Rúnar**. Authors who change a `.runar.go` source MUST recompile and re-commit the matching `.expected.hex`. CI / review catches drift via the hex diff.

---

## §2 Step-by-step

### 2.1 One-time author setup

You need Rúnar's Go tier compiler. Clone + build once:

```bash
git clone --depth 1 https://github.com/icellan/runar.git ~/runar
cd ~/runar/compilers/go
go build -o ~/.local/bin/runar-go .  # or anywhere on PATH
```

**Why Go tier**: Rúnar's `compilers/zig` and `packages/runar-zig` currently target post-0.15.2 Zig nightly APIs (`std.process.Init`, `b.graph.io`) and fail to build on our Zig 0.15.2 stable. Per PR #664's friction story. When the Zig tier supports 0.15.2 stable, this guide will add `runar-zig` as the recommended frontend.

**Why not embed Go in the brain build**: Todd 2026-05-25 directive — no new toolchain deps. Authors pre-compile; the brain build only reads bytes.

### 2.2 Author a precondition

Write `.runar.go` in your cartridge's policies directory. Example shape from [`runtime/semantos-brain/src/policies-demo/range_check.runar.go`](../runtime/semantos-brain/src/policies-demo/range_check.runar.go):

```go
package contracts

import "github.com/icellan/runar/packages/runar-go/runar"

type RangeCheck struct {
    runar.SmartContract
}

func (c *RangeCheck) Verify(amount runar.Int) {
    runar.Assert(amount > 0)
    runar.Assert(amount <= 100)
}
```

The `runar.Assert(...)` calls compile to predicates that end with truthy top-of-stack on pass. That's what `PolicyRuntime.evaluateReal` expects.

### 2.3 Compile offline

```bash
runar-go -source range_check.runar.go -hex
# → 7600a0690164a1
```

The output is hex-encoded Bitcoin Script bytes. **Save them** to a sibling `.expected.hex` file:

```bash
runar-go -source range_check.runar.go -hex > range_check.expected.hex
```

### 2.4 Commit both files

```bash
git add range_check.runar.go range_check.expected.hex
git commit -m "feat(cartridge): range-check precondition (Rúnar Go-tier compiled)"
```

The hex is the **load-bearing artifact**. The source is documentation + audit provenance. A reviewer reading the diff sees BOTH the human-readable predicate AND the bytes the brain will execute — diff-visible audit surface.

### 2.5 Consume from the brain (Zig)

```zig
const std = @import("std");
const policy_runtime = @import("policy_runtime");

// Compiled offline via Rúnar Go tier — see range_check.runar.go.
const RANGE_CHECK_HEX = @embedFile("policies/range_check.expected.hex");

fn rangeCheckBytes(allocator: std.mem.Allocator) ![]u8 {
    // Strip trailing newlines + decode hex → bytes.
    const trimmed = std.mem.trim(u8, RANGE_CHECK_HEX, &std.ascii.whitespace);
    var out = try allocator.alloc(u8, trimmed.len / 2);
    _ = try std.fmt.hexToBytes(out, trimmed);
    return out;
}

pub fn enforceRange(
    rt: *policy_runtime.PolicyRuntime,
    ctx: policy_runtime.PolicyContext,
    amount: i64,
) !policy_runtime.PolicyResult {
    // Prepend a push of `amount` so the predicate has its input.
    const policy = try rangeCheckBytes(rt.allocator);
    defer rt.allocator.free(policy);

    var script: std.ArrayListUnmanaged(u8) = .{};
    defer script.deinit(rt.allocator);

    // Encode `amount` push (minimal form for 0–255 range; CScriptNum
    // for larger.  Real cartridges use a helper).
    try script.append(rt.allocator, 1);
    try script.append(rt.allocator, @intCast(amount));
    try script.appendSlice(rt.allocator, policy);

    return try rt.evaluate(script.items, ctx);
}
```

See [`runtime/semantos-brain/src/policy_runtime.zig`](../runtime/semantos-brain/src/policy_runtime.zig) inline tests for runnable examples.

---

## §3 What you can author today

**Available** under PolicyRuntime PR-2b (`tx_context = null`, `OP_READPAYLOAD` not wired):

- Numeric comparisons (`==`, `!=`, `<`, `<=`, `>`, `>=`)
- Arithmetic (`+`, `-`, `*`, `/`, `%`, `&`, `|`, `^`, `<<`, `>>`)
- Boolean logic (`&&`, `||`, `!`)
- Hash checks (`runar.bytesEq(runar.sha256(x), commitment)`, same for `ripemd160`, `hash160`, `hash256`, `blake3`)
- Conditionals (`if (...) { ... } else { ... }`)
- Field-equality checks against readonly constructor params
- Range / bound checks (like the `RangeCheck` example)

**NOT available today** (Phase 2 — gates on tasks #16 + extending `evaluateReal`):

- `runar.checkSig(sig, pubKey)` — needs `tx_context`
- `runar.checkSigVerify(...)` — same
- `OP_PUSH_TX` family (BSV introspection) — needs the spending tx
- Plexus-extension opcodes (`OP_CHECKLINEARTYPE`, `OP_READPAYLOAD`, etc.) — Rúnar doesn't emit them; see [`RUNAR-ZIG-INTEGRATION-EVAL.md`](prd/RUNAR-ZIG-INTEGRATION-EVAL.md) §2 caveat 1

If you write a contract that calls one of the unavailable functions, Rúnar will compile it fine, but PolicyRuntime will reject at runtime with a specific token (`invalid_sighash`, `not_implemented`, `disabled_opcode`, etc.). Iterate against the test surface; the rejection token tells you what's missing.

---

## §4 Naming + layout conventions

For a cartridge at `cartridges/<cartridge_name>/`, policies live under:

```
cartridges/<cartridge_name>/brain/zig/policies/
├── <policy_name>.runar.go             # author surface
├── <policy_name>.expected.hex         # compiled golden
└── README.md                          # what each policy guards, how to recompile
```

Multiple policies per cartridge are fine; one file pair per logical predicate.

**File naming**:
- `.runar.go` (or future `.runar.zig`, `.runar.ts`, etc.) — REQUIRED suffix Rúnar's frontend dispatcher uses
- `.expected.hex` — single-line lowercase hex, trailing newline OK; whitespace trimmed by the brain's `hexToBytes` adapter

**Header comment block** in every `.runar.go`:
- `Upstream:` line citing `icellan/runar` + commit hash you used
- `Compiler:` line naming the tier (`Rúnar Go tier`)
- `Invocation:` line with the exact command
- `Output:` line repeating the hex (so the source is self-documenting)
- `Decode:` opcode-by-opcode breakdown of the output (security audit aid)

The [`range_check.runar.go` example](../runtime/semantos-brain/src/policies-demo/range_check.runar.go) demonstrates all five.

---

## §5 Recompilation discipline

Authors who modify a `.runar.go` source MUST:

1. Run `runar-go -source X.runar.go -hex` again
2. Replace the matching `.expected.hex` with the new output
3. Update the `Output:` header comment in the source
4. Update the `Decode:` opcode breakdown if opcodes changed
5. Re-run `zig build test -j1` to confirm the new hex still satisfies any inline-test assertions

CI today doesn't auto-recompile (no Rúnar in the brain build); review catches drift. The hex diff is reviewable: a reviewer who sees `.runar.go` change without matching `.expected.hex` change should reject the PR.

Future option: a CI job that runs in a separate workflow with Go installed (only on PR open) recompiles and compares. Not in scope today; the diff-review discipline is sufficient for the volume of policies we currently ship.

---

## §6 What "no need for Go toolchain" means

Per Todd 2026-05-25: the **brain build** does not depend on Go. Authors who modify `.runar.go` need Go installed on their dev machine to recompile, but:

- `zig build` works on machines without Go
- CI builds work on machines without Go
- Cartridge consumers (oddjobz-mobile, the operator's iPhone) never see Rúnar or Go

This is the cleanest possible coupling: source + golden ship together; the consumer reads bytes.

---

## §7 Cross-references

- [`POLICY-RUNTIME-EXECUTOR-ADAPTER.md`](prd/POLICY-RUNTIME-EXECUTOR-ADAPTER.md) — what `evaluateReal` actually does with the bytes
- [`RUNAR-ZIG-INTEGRATION-EVAL.md`](prd/RUNAR-ZIG-INTEGRATION-EVAL.md) — the eval that justified this integration
- [`ANCHOR-BACKEND-BRIDGE.md`](prd/ANCHOR-BACKEND-BRIDGE.md) §0 — the Rúnar/BSVM theoretical frame
- [PR #664](https://github.com/semantos/semantos-core/pull/664) — substrate smoke that proved Rúnar bytes work
- [`runtime/semantos-brain/src/policies-demo/range_check.runar.go`](../runtime/semantos-brain/src/policies-demo/range_check.runar.go) — the worked example this guide cites throughout (lives in the brain tree because Zig 0.15's `@embedFile` doesn't cross package boundaries — see the example's README for the full story)

---

## §8 Change log

- **v0.1** (2026-05-25) — Initial author guide. Codifies Todd's 2026-05-25 directive ("let's go c, no need for go") into the workflow. Cites the worked `range_check.runar.go` example + PR #664's substrate smoke as proof the pipeline works end-to-end.
