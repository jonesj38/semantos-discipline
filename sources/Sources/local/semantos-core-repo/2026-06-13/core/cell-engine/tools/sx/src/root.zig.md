---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tools/sx/src/root.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.997641+00:00
---

# core/cell-engine/tools/sx/src/root.zig

```zig
//! Public surface of the `sx` module.
//!
//! Mirrors bitcoinsx's `src/sx/src/index.ts`, plus the lower-level types the
//! tokeniser tests need access to. Consumers (the brain dispatcher, the
//! future WASM shim, the dialect registry in `core/cell-engine/tools/`)
//! import from here.

pub const node = @import("node.zig");
pub const NodeType = node.NodeType;
pub const Node = node.Node;

pub const lex = @import("lex.zig");
pub const Lexer = lex.Lexer;
pub const TokeniseResult = lex.TokeniseResult;

pub const parse = @import("parse.zig");
pub const Parser = parse.Parser;
pub const ParseResult = parse.ParseResult;
pub const ParseError = parse.ParseError;

pub const lower = @import("lower.zig");
pub const Lowerer = lower.Lowerer;
pub const LowerResult = lower.LowerResult;
pub const DeployArgs = lower.DeployArgs;

pub const err = @import("error.zig");
pub const TokeniserError = err.TokeniserError;
pub const ErrorMsg = err.ErrorMsg;

pub const short_ops = @import("short_ops.zig");
pub const ShortOp = short_ops.ShortOp;

test {
    // Pull in unit-level tests from each module.
    _ = node;
    _ = lex;
    _ = parse;
    _ = lower;
    _ = err;
    _ = short_ops;
}

```
