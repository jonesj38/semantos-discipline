---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/08-surface-to-ast.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.654167+00:00
---

# Surface to AST

Chapter 8 covers the first stage of boot step 7: what happens to text before the cell engine sees it. The pipeline described in `docs/PIPELINE.md` begins at Lisp source text and ends at opcode bytes. This chapter covers the left portion of that journey — from surface text through tokenisation, parsing, and the construction of a typed abstract syntax tree (AST). The right portion — lowering to opcode bytes — is taken up in chapter 10.

The scope is deliberately narrow. The current live pipeline has exactly one surface grammar: a Lisp policy DSL. LaTeX, Lean-ish, Ricardian, and EDI surfaces are listed in the pipeline plan but are not yet implemented; they share a section at the end of this chapter. Everything here is grounded in the code at `runtime/shell/src/lisp/parser.ts` and `runtime/shell/src/lisp/compiler.ts`.

---

## The live pipeline, stage by stage

The pipeline for Lisp policy expressions, as recorded in `docs/PIPELINE.md § "Live flow today"`, is:

```
Lisp source text
        │
        ▼  runtime/shell/src/lisp/parser.ts
        │
   SExpression (parse tree)
        │
        ▼  runtime/shell/src/lisp/types.ts: interpretConstraint() / interpretPolicy()
        │
   ConstraintExpr (AST)
        │
        ▼  runtime/shell/src/lisp/compiler.ts: compile()
        │
   Uint8Array (opcode bytes 0x4C–0xD0)
        │
        ▼
   Cell engine (Zig/WASM 2-PDA)
```

The pipeline has three named stages between text and bytes:

1. Tokenise and parse: `parser.ts` produces an `SExpression`.
2. Interpret: `types.ts` walks the `SExpression` and produces a `ConstraintExpr` (the typed AST).
3. Compile: `compiler.ts` walks the `ConstraintExpr` and emits bytes.

Stage 1 is syntax. Stage 2 is semantics — the point where operator names become typed node kinds. Stage 3 is code generation. This chapter covers stages 1 and 2. Stage 3 is covered in chapter 10.

One observation from the pipeline document is worth stating explicitly: the Lisp compiler bypasses IR entirely. It does not emit SIR or OIR; it goes directly from the typed AST to opcode bytes. That bypass is intentional, is covered by golden-file tests, and is the live behaviour at boot step 7. The SIR and OIR layers are both fully implemented in separate packages and will be wired in during Phase 3 of the restructure. Chapters 9 and 10 describe those layers in depth.

---

## Parser architecture

The parser lives in `runtime/shell/src/lisp/parser.ts`. It has no external dependencies. It is a pure function: same input, same output, no I/O, no side effects.

### Token and node types

The parser works in terms of two node types, together forming the `SExpression` union:

```ts
export type SExpression = Atom | List;

export interface Atom {
  type: 'atom';
  kind: 'symbol' | 'number' | 'string' | 'keyword';
  value: string | number;
  line: number;
  column: number;
}

export interface List {
  type: 'list';
  elements: SExpression[];
  line: number;
  column: number;
}
```

Every node carries a source location (`line`, `column`). This matters for error reporting: the `ParseError` class propagates location through to the user-facing message. There is no separate tokeniser phase — atoms are parsed character-by-character as they are encountered during recursive descent.

### The four atom kinds

`Atom.kind` takes one of four values:

| Kind | Example | Rule |
|------|---------|------|
| `symbol` | `has-capability`, `and`, `>` | Any token that is not a keyword, number, or string |
| `number` | `42`, `-7`, `3.14` | Matches `/^-?\d+(\.\d+)?$/` |
| `string` | `"signing"` | Delimited by double-quotes; supports `\n`, `\t`, `\\`, `\"` escapes |
| `keyword` | `:subject`, `:linearity` | Starts with `:` |

The `isSymbolChar` predicate defines the delimiter set: the characters `(`, `)`, `"`, `;`, whitespace, `'`, `` ` ``, and `,` are not valid inside a symbol. Everything else is. This gives the parser flexibility without requiring a reserved-word list.

### Whitespace and comments

Before any form is parsed, `skipWhitespaceAndComments` advances past spaces, tabs, and newlines, and discards everything from a `;` to the end of the line. Lisp comment syntax is fully supported; no multi-line comment form exists.

### Recursive descent

The entry point for a single form is `parseForm`. It inspects the first character:

- `(` → call `parseList`, which loops collecting `parseForm` calls until `)`.
- `'` → expand quote shorthand: consume the `'`, parse the next form `inner`, and return a synthetic `List` node containing `[quote, inner]`.
- `"` → call `parseString`, which scans until the closing `"` handling escape sequences.
- `)` → immediate `ParseError` (unmatched closing paren).
- Anything else → call `parseAtomToken`, which scans while `isSymbolChar` holds, then classifies the accumulated token as keyword, number, or symbol.

`parseList` does the work for nested forms: it consumes `(`, then loops calling `skipWhitespaceAndComments` and `parseForm` until it sees `)` or hits end-of-input. On end-of-input before `)`, it throws `ParseError: Unmatched opening parenthesis` with the location of the opening `(`.

The public surface is two functions:

```ts
export function parseExpression(input: string): SExpression   // exactly one top-level form
export function parseProgram(input: string): SExpression[]    // zero or more top-level forms
```

`parseExpression` additionally checks that no non-whitespace input follows the form, which makes it appropriate for single-constraint contexts such as the `compile` verb in `semantos-shell`.

### Quote shorthand

The parser supports one piece of syntactic sugar: the `'` (quote) character before any form. `'x` expands to `(quote x)`. The expansion is done structurally during parsing — a synthetic `List` node is returned with `quote` as the first element and the quoted form as the second. This is purely a parser convenience; the interpreter in `types.ts` does not currently define a `quote` operator in the constraint grammar, but the parse tree correctly represents the expansion so it is available for future use without parser changes.

### Determinism and parser state

The `ParserState` record is a plain mutable object passed by reference through each parser function:

```ts
interface ParserState {
  input: string;
  pos: number;
  line: number;
  column: number;
}
```

There is no global state. Two calls to `parseExpression` with the same input string produce structurally identical `SExpression` trees. The `line` and `column` fields are advanced by `advance`: on `\n`, `line` increments and `column` resets to 1; on any other character, `column` increments. The position tracking is used exclusively for error messages; it does not affect parse logic.

The `atEnd` check guards all inner loops, preventing any buffer overrun. The `peek` function returns `undefined` at end-of-input (accessing beyond the string length), which propagates to the `if (atEnd(s)) break` guards in `parseString`. This is the one place where `undefined` propagates silently rather than through a `ParseError`; the outer check in `parseAtomToken` — `token.length === 0` — will catch any form that reduces to an empty token.

### Error handling

All parse failures are `ParseError` instances carrying `line` and `column`. The parser is strict: unmatched parens, unterminated strings, and trailing garbage all produce errors rather than being silently ignored. There is no error-recovery pass; the first error terminates the parse.

The error cases by location:

- `parseList`: end-of-input before `)` → `Unmatched opening parenthesis` at the location of `(`.
- `parseString`: end-of-input before `"` → `Unterminated string literal` at the location of the opening `"`.
- `parseAtomToken`: zero-length token (a character that is not `isSymbolChar` but also not any of the special forms) → `Unexpected character 'X'`.
- `parseForm`: `)` encountered outside a list → `Unexpected closing parenthesis`.
- `parseExpression`: non-whitespace trailing input → `Unexpected input after expression: '...'` (truncated to 20 characters).

---

## From parse tree to typed AST

The parse tree produced by the parser is structurally valid but semantically flat: the symbol `has-capability` is just an atom with `kind: 'symbol'`. The interpretation pass in `types.ts` does the semantic work: it walks the `SExpression` and produces a `ConstraintExpr`, a discriminated union of typed node kinds.

### The ConstraintExpr union

The `ConstraintExpr` type is defined in `@semantos/semantos-ir/expr` and re-exported from `types.ts`. Its discrimination is on a `kind` field:

| `kind` | Lisp form | Represents |
|--------|-----------|------------|
| `comparison` | `(> amount 500)` | Field comparison against a literal |
| `logical` | `(and ...)`, `(or ...)`, `(not ...)` | Boolean combination |
| `capability` | `(has-capability 2)` | Capability token check |
| `domainCheck` | `(check-domain 0x01)` | Governance domain flag check |
| `timeConstraint` | `(time-after "2025-01-01")` | Temporal boundary |
| `hostCall` | `(call-host "is-member")` | Opaque host-side predicate |
| `typeHashCheck` | `(check-type-hash "abcd...")` | Cell type-hash equality |
| `deref` | `(deref)` | Pointer dereference |

Each kind has a specific set of fields. A `comparison` node carries `op`, `field`, and `value`. A `capability` node carries `capabilityNumber`. A `logical` node carries `op` (one of `and`, `or`, `not`) and `operands`, which is a recursive slice of `ConstraintExpr`.

### interpretConstraint

`interpretConstraint(expr: SExpression): ConstraintExpr` is the core of the interpretation pass. It expects a `List` with at least one element; the first element must be a `symbol` atom naming the operator. The function dispatches on the operator name and validates argument count and types, throwing descriptive errors with source locations on any mismatch.

A few details worth noting:

- Comparison operators (`>`, `<`, `>=`, `<=`, `=`, `!=`) require exactly two arguments: a symbol (the field name) and a number or string literal (the comparison value).
- `and` and `or` require at least two operands and recurse via `interpretConstraint` on each, producing a tree of logical nodes.
- `not` requires exactly one operand and recurses.
- `has-capability` requires exactly one numeric argument, producing a `capability` node with `capabilityNumber` set to that value.
- Symbols ending in `?` with no arguments are treated as zero-argument host calls — syntactic sugar for predicate-style naming.

### Validation at the interpretation boundary

`interpretConstraint` performs structural validation as it interprets. Errors at this stage are semantic errors, not syntax errors — the input is well-formed S-expression syntax, but the constraint tree does not conform to the expected grammar.

The validation rules per operator:

- Any comparison operator requires exactly two arguments after the operator: first a `symbol` atom (the field name), second either a `number` or `string` atom. Passing a nested list as the field argument, or a keyword as the value, throws with the source location of the offending element.
- `and` and `or` require at least two operand expressions (three list elements total including the operator). A single-operand `and` is rejected at the interpretation stage even though it would be valid syntax.
- `has-capability` requires exactly one `number` atom argument. The capability number must be a parsed integer; a string such as `"SIGNING"` is not accepted by the current interpreter (the `capabilityNumber` field on the node is a plain `number`).
- `check-domain` accepts either a `number` atom or any other atom kind (the field is `string | number`). This allows hex literals if the parser has already classified them as numbers, and string flags for symbolic domain names.
- `time-after` and `time-before` require exactly one `string` atom argument. The value is treated as an ISO 8601 timestamp; the conversion to Unix epoch happens in the compiler, not the interpreter.
- `check-type-hash` requires exactly one `string` atom argument of exactly 64 characters (32 bytes SHA-256 in hex). The length check is at the interpretation stage, not the compilation stage.
- The zero-arity `?`-suffix predicate sugar requires that the operator atom end in `?` and that the list have exactly one element (the operator itself, no arguments).

A `validateConstraintFields` helper function exists for an optional secondary validation pass: it walks a `ConstraintExpr` and checks that every `comparison` node's `field` name appears in a supplied `FieldDefinition[]` list. This pass is not part of the basic compile path but is available to callers that hold schema definitions for the cell type being constrained.

### PolicyForm and interpretPolicy

A full policy form is a `List` headed by the symbol `policy`, followed by keyword-argument pairs:

```lisp
(policy
  :subject   tenant
  :action    transfer
  :constraint (has-capability 2)
  :linearity  linear)
```

`interpretPolicy` parses this into a `PolicyForm`:

```ts
export interface PolicyForm {
  subject:     IdentityRef;
  action:      string;
  constraint:  ConstraintExpr;
  linearity:   LinearityMode;
  description?: string;
}
```

`IdentityRef` covers three subject shapes: a symbol becomes a `role` reference; a number becomes a `domainFlag` reference; a string becomes a `certPattern` reference. `LinearityMode` is the four-value enum — `LINEAR`, `AFFINE`, `RELEVANT`, `FUNGIBLE` — matching the linearity class on a cell header.

The separation between `PolicyForm` and `ConstraintExpr` is deliberate. The constraint branch handles evaluation semantics: what must be true for the policy to pass. The policy shell handles identity and structural metadata: who the subject is, what action is authorised, and what the linearity of the resource is. Chapter 9 shows how SIR extends this structure further by adding jural category, governance context, and provenance.

### The LispCompiler class

`LispCompiler` is the public entry point to the compilation pipeline. It is constructed with an optional `compiledAt` timestamp, which defaults to `new Date().toISOString()`. The timestamp is included in `ScriptOutput.metadata` and is the only non-deterministic element in the output. Tests that require byte-identical output pass a fixed timestamp:

```ts
const compiler = new LispCompiler({ compiledAt: '2026-01-01T00:00:00.000Z' });
```

Two public methods:

- `compile(expr: SExpression): ScriptOutput` — interprets the expression as a constraint (calling `interpretConstraint`), compiles it, and returns the result. This is the path for bare constraint expressions.
- `compilePolicy(expr: SExpression): ScriptOutput` — interprets the expression as a full policy form (calling `interpretPolicy`), compiles both subject and constraint, and joins them with `OP_BOOLAND` and `OP_VERIFY`.

The class does not hold any state between calls other than `compiledAt`. It is safe to reuse a single instance across many compilations; the `compiledAt` metadata will be the same for all.

A helper `sExprToString` converts an `SExpression` back to a printable string for inclusion in the metadata's `inputExpr` field. This is used for audit logging and is not part of the execution path.

---

## The compiler: from typed AST to opcode bytes

`compiler.ts` takes a `ConstraintExpr` (or a full `PolicyForm`) and emits a `ScriptOutput`:

```ts
export interface ScriptOutput {
  scriptWords: string;       // human-readable mnemonic sequence
  scriptBytes: Uint8Array;   // packed bytes for the cell engine
  metadata: { ... };
}
```

`scriptWords` is the space-joined mnemonic sequence — the same bytes in readable form. `scriptBytes` is the `Uint8Array` handed to the cell engine.

### Opcode constants

The compiler defines opcode constants as bare numbers, sourced from the cell engine:

```ts
const OP_BOOLAND          = 0x9A;
const OP_BOOLOR           = 0x9B;
const OP_NOT              = 0x91;
const OP_EQUAL            = 0x87;
const OP_GREATERTHAN      = 0xA0;
const OP_LESSTHAN         = 0x9F;
const OP_CHECKCAPABILITY  = 0xC3;
const OP_CHECKDOMAINFLAG  = 0xC6;
const OP_CHECKTYPEHASH    = 0xC7;
const OP_DEREF_POINTER    = 0xC8;
const OP_CALLHOST         = 0xD0;
const OP_LOADFIELD        = 0xB0;
const OP_VERIFY           = 0x69;
const OP_PUSHDATA1        = 0x4C;
```

The standard Bitcoin Script opcodes occupy `0x00`–`0x4B`; the Plexus extension opcodes occupy `0x4C`–`0xD0`. `OP_PUSHDATA1` is the boundary: it is both the first Plexus extension opcode and the push-with-length-prefix instruction for data larger than 75 bytes.

### Encoding

Push operations use Bitcoin Script's minimal-encoding convention. Numbers are encoded as little-endian signed bytes with a sign bit in the high bit of the last byte; zero is encoded as `[0x00]`. Data up to 75 bytes is prefixed with a single length byte; data from 76 to 255 bytes uses `OP_PUSHDATA1` followed by a length byte. The compiler uses `encodePushNumber` and `encodePushString` as helpers, both calling `encodePushData`.

### compileConstraint dispatch

The `compileConstraint` function dispatches on `ConstraintExpr.kind` and produces a `CompileResult`:

```ts
interface CompileResult {
  words: string[];
  bytes: number[];
}
```

The two arrays stay parallel and are concatenated by `concatResults` when compiling compound expressions.

For each kind:

- `comparison`: push the comparison value, push the field name and emit `OP_LOADFIELD`, then emit the comparison opcode. For example, `(> amount 500)` becomes `[push 500] [push "amount"] OP_LOADFIELD OP_GREATERTHAN`.
- `logical/not`: compile the single operand, then emit `OP_NOT`.
- `logical/and`, `logical/or`: compile each operand in order, then emit `n−1` `OP_BOOLAND` or `OP_BOOLOR` opcodes to chain them pairwise. Two operands produce one `BOOLAND`; three produce two; and so on.
- `capability`: push the capability number and emit `OP_CHECKCAPABILITY`.
- `domainCheck`: push the domain flag and emit `OP_CHECKDOMAINFLAG`.
- `timeConstraint`: convert the ISO timestamp to a Unix epoch integer, push it, and emit `OP_GREATERTHAN` (for `time-after`) or `OP_LESSTHAN` (for `time-before`).
- `hostCall`: push the function name as a string and emit `OP_CALLHOST`.
- `typeHashCheck`: decode the 64-character hex string to 32 bytes, push those bytes, and emit `OP_CHECKTYPEHASH`.
- `deref`: emit `OP_DEREF_POINTER` with no preceding push.

### compilePolicy

`LispCompiler.compilePolicy` compiles a full policy form. It calls `compileSubject` for the identity check, `compileConstraint` for the constraint, concatenates the two results, appends `OP_BOOLAND` to AND them together, and appends `OP_VERIFY` to require the combined result to be truthy. The cell engine halts with a policy-violation fault if `OP_VERIFY` receives a false value.

The subject compiler produces an `OP_CHECKDOMAINFLAG` regardless of whether the subject is expressed as a role name, a numeric flag, or a cert pattern. The distinction is in how the argument is encoded before the opcode: role names are pushed as strings; numeric flags as numbers; cert patterns as strings. The cell engine receives the same opcode in all three cases and dispatches internally on the argument type.

---

## Intermediate representation in this pipeline

As noted in `docs/canon/glossary.yml`, IR (intermediate representation) is the umbrella term for the pipeline's intermediate forms. In the full intended pipeline there are exactly two: SIR (semantic IR, jural-typed) and OIR (opcode IR, A-normal form). In the current live pipeline the Lisp compiler bypasses both.

What the live pipeline uses instead is the `ConstraintExpr` AST. This is structurally simpler than either SIR or OIR: it carries no jural category, no governance context, no trust class, and no ANF discipline. It is a direct one-to-one translation of the surface syntax into a typed tree, sufficient for the current golden-file compiler but not sufficient to enforce governance properties at compile time. That enforcement is precisely what the SIR layer adds (chapter 9) and what the Phase 3 wiring delivers.

The relationship to the glossary entry for IR is as follows: the `ConstraintExpr` is not a named IR in the canonical sense — it is the typed AST that sits between the parser and the compiler in the Lisp-specific fast path. SIR and OIR are the canonical IR layers; they are present in the codebase and covered in chapters 9 and 10.

### Policy compilation: subject plus constraint

When `compilePolicy` is called, the compiled output is the concatenation of three blocks:

1. The subject block: an `OP_CHECKDOMAINFLAG` prefixed by an argument encoding the subject identity. The argument is a role name string, a numeric domain flag, or a cert pattern string, depending on which `IdentityRef` shape the subject resolved to.
2. The constraint block: the full compiled constraint expression.
3. The combiner: `OP_BOOLAND` joins the subject check and the constraint result; `OP_VERIFY` requires the combination to be true.

The subject check runs first. If the caller's hat is not associated with the declared domain or role, the subject check produces 0, `OP_BOOLAND` produces 0 regardless of the constraint result, and `OP_VERIFY` faults. The constraint is still evaluated (the operands to `OP_BOOLAND` are evaluated left-to-right), but its result is irrelevant to the policy outcome if the subject fails. This is a property of the simple stack-based evaluation model rather than a deliberate short-circuit design.

---

## Future surface grammars

The pipeline plan identifies four additional surface grammars that have not yet been implemented:

| Surface | Status |
|---------|--------|
| LaTeX | Not yet built |
| Lean-ish | Not yet built |
| Ricardian contract | Not yet built |
| EDI | Not yet built |

When these surfaces are implemented, each one will produce a SIR program as output — not a `ConstraintExpr`. The architectural requirement is that two surface grammars expressing the same semantic intent must produce OIR programs that are alpha-equivalent. That equivalence is the compression-gradient claim: the kernel does not care which surface produced the bytes, because all surfaces lower into the same OIR. The current Lisp fast-path bypasses SIR, which means it cannot participate in cross-surface alpha-equivalence checking until Phase 3 wiring is complete.

---

## Worked example — `(and (has-capability 2) (> amount 500))`

The following traces a Lisp constraint expression through tokenise → parse → AST → compiled bytes. The expression encodes the policy: "the caller must hold capability token 2 and the amount field must be greater than 500."

> **Constraint expression**
>
> ```lisp
> (and (has-capability 2) (> amount 500))
> ```

### Stage 1 — tokenise

The parser does not maintain a separate token stream; it tokenises on demand during recursive descent. Reading left-to-right, the characters produce the following token classification sequence:

```
(          open-paren → begin List
and        symbol atom, value="and"
(          open-paren → begin nested List
has-capability  symbol atom, value="has-capability"
2          number atom, value=2
)          close-paren → end nested List
(          open-paren → begin nested List
>          symbol atom, value=">"
amount     symbol atom, value="amount"
500        number atom, value=500
)          close-paren → end nested List
)          close-paren → end outer List
```

Each token captures its source position (`line`, `column`).

### Stage 2 — parse tree (SExpression)

`parseExpression` is called on the input string. `parseForm` sees `(` and calls `parseList`. `parseList` collects forms until `)`:

```
List {
  elements: [
    Atom { kind: "symbol", value: "and" },
    List {
      elements: [
        Atom { kind: "symbol", value: "has-capability" },
        Atom { kind: "number", value: 2 }
      ]
    },
    List {
      elements: [
        Atom { kind: "symbol", value: ">" },
        Atom { kind: "symbol", value: "amount" },
        Atom { kind: "number", value: 500 }
      ]
    }
  ]
}
```

This is the raw parse tree. Every node is either an `Atom` or a `List`. No semantic meaning has been assigned yet: `has-capability` is just a symbol, `2` is just a number.

### Stage 3 — typed AST (ConstraintExpr)

`interpretConstraint` is called on the outer `List`. It reads the first element: symbol `and`. It enters the `logical` branch, calls `interpretConstraint` on each of the remaining two child lists, and builds:

```
LogicalExpr {
  kind: "logical",
  op: "and",
  operands: [
    CapabilityExpr {
      kind: "capability",
      capabilityNumber: 2
    },
    ComparisonExpr {
      kind: "comparison",
      op: ">",
      field: "amount",
      value: 500
    }
  ]
}
```

The inner `(has-capability 2)` list: head is `has-capability`, count is 2 (head + one arg), the argument is a number atom — valid. Result: `CapabilityExpr { kind: "capability", capabilityNumber: 2 }`.

The inner `(> amount 500)` list: head is `>`, count is 3 (head + field + value), field is a symbol atom, value is a number atom — valid. Result: `ComparisonExpr { kind: "comparison", op: ">", field: "amount", value: 500 }`.

The outer `and`: count is 3 (head + two operands), both operands recursively valid — valid. `interpretConstraint` requires at least two operands for `and`; two are present.

### Stage 4 — compileConstraint (bytes and mnemonics)

`compileConstraint` is called on the `LogicalExpr`. It dispatches to the `logical` case, sees `op: "and"`, and compiles each operand:

**Operand 1 — `CapabilityExpr { capabilityNumber: 2 }`**

```
kind = "capability"
→ encodePushNumber(2) = [0x01, 0x02]   (length 1, then byte 2)
→ OP_CHECKCAPABILITY  = 0xC3

bytes: [0x01, 0x02, 0xC3]
words: ["2 CHECK-CAP"]
```

`encodePushNumber(2)` calls `encodeScriptNumber(2)` which produces `[0x02]` (one byte, no sign extension needed), then `encodePushData([0x02])` which prepends `0x01` (the length), giving `[0x01, 0x02]`.

**Operand 2 — `ComparisonExpr { op: ">", field: "amount", value: 500 }`**

```
kind = "comparison", op = ">"
→ encodePushNumber(500):
    encodeScriptNumber(500):
      500 = 0x01F4 → bytes [0xF4, 0x01]
      high bit of 0x01 is not set → no sign byte
      result: [0xF4, 0x01]
    encodePushData([0xF4, 0x01]) = [0x02, 0xF4, 0x01]   (length 2)
→ encodePushString("amount"):
    TextEncoder("amount") = [0x61, 0x6D, 0x6F, 0x75, 0x6E, 0x74]   (6 bytes)
    encodePushData → [0x06, 0x61, 0x6D, 0x6F, 0x75, 0x6E, 0x74]
→ OP_LOADFIELD  = 0xB0
→ OP_GREATERTHAN = 0xA0

bytes: [0x02, 0xF4, 0x01, 0x06, 0x61, 0x6D, 0x6F, 0x75, 0x6E, 0x74, 0xB0, 0xA0]
words: ["500 AMOUNT-GT"]
```

**Chaining with BOOLAND**

Two operands, so one `OP_BOOLAND` is appended:

```
bytes: [...operand1, ...operand2, 0x9A]
words: ["2 CHECK-CAP", "500 AMOUNT-GT", "BOOLAND"]
```

**Final opcode sequence**

```
Offset   Byte    Meaning
0x00     0x01    push 1 byte
0x01     0x02    literal 2 (capability number)
0x02     0xC3    OP_CHECKCAPABILITY
0x03     0x02    push 2 bytes
0x04     0xF4    } 500 in little-endian script encoding
0x05     0x01    }
0x06     0x06    push 6 bytes
0x07     0x61    } "amount" in UTF-8
0x08     0x6D    }
0x09     0x6F    }
0x0A     0x75    }
0x0B     0x6E    }
0x0C     0x74    }
0x0D     0xB0    OP_LOADFIELD
0x0E     0xA0    OP_GREATERTHAN
0x0F     0x9A    OP_BOOLAND
```

The `scriptWords` string is `"2 CHECK-CAP 500 AMOUNT-GT BOOLAND"`. The `scriptBytes` is a 16-byte `Uint8Array`.

### What the cell engine receives

The 16-byte sequence is handed to the 2-PDA cell engine (chapter 11). The engine executes each opcode in order:

1. `0x01 0x02` — push the number 2 onto the data stack.
2. `0xC3` (`OP_CHECKCAPABILITY`) — pop 2, verify that the executing hat holds capability token 2; push 1 (true) or 0 (false).
3. `0x02 0xF4 0x01` — push the number 500 onto the data stack.
4. `0x06 0x61...0x74` — push the string "amount" onto the data stack.
5. `0xB0` (`OP_LOADFIELD`) — pop "amount", load the `amount` field from the current cell, push its value.
6. `0xA0` (`OP_GREATERTHAN`) — pop 500 and the field value, push 1 if `field_value > 500`, else 0.
7. `0x9A` (`OP_BOOLAND`) — pop the two boolean results from steps 2 and 6, push 1 if both are 1, else 0.

If the final stack top is 0, the constraint fails; the cell engine enforces the failure under K4 (failure atomicity). If it is 1, the constraint passes and execution continues.

---

## Summary

The surface-to-AST pass has three stages: the recursive-descent parser in `parser.ts` produces an `SExpression` parse tree; `interpretConstraint` in `types.ts` walks that tree and produces a typed `ConstraintExpr` AST; and the `compileConstraint` function in `compiler.ts` walks the `ConstraintExpr` and emits a flat sequence of opcode bytes. The parse tree is structurally valid but semantically opaque; the typed AST assigns operator identity and argument types; the byte sequence is what the cell engine executes. At every stage the representation is inspectable and deterministic. The same source text always produces the same bytes, which is the property that makes golden-file testing sufficient for the current live pipeline.

The IR gloss entry notes that bare "IR" should be avoided in favour of SIR or OIR when a specific representation is meant. The `ConstraintExpr` is the Lisp-specific typed AST sitting between the parser and the compiler, not a canonical IR layer in that sense. Chapters 9 and 10 describe SIR and OIR respectively, and the relationship between the current Lisp fast-path and the intended full pipeline.
