---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/10-opcode-ir-and-emit.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.651703+00:00
---

# Opcode IR (OIR), ANF, and Emit

Part III — Cells and The Pipeline — boot step 7.

Chapter 8 traced a Lisp expression through the parser to an abstract syntax tree. Chapter 9 introduced SIR: the upper intermediate representation that types each node with a jural category, a governance context, and an identity binding. This chapter covers the layer below SIR — OIR, the opcode IR — and the two passes that produce it: `lower()`, which converts an AST or a lowered-SIR program into A-normal form, and `emit()`, which converts OIR into the byte sequence the cell engine executes.

The pipeline position is:

```
Surface grammar (Lisp ✓; LaTeX, Lean-ish, Ricardian, EDI — in design)
       │
       ▼
SIR   (jural category, taxonomy, identity, governance context)
       │  lowerSIR()
       ▼
OIR   (ANF — named bindings, explicit data flow, predicates)
       │  emit()
       ▼
Opcode bytes  (0x4C–0xD0)
       │
       ▼
Cell engine  (Zig/WASM 2-PDA)
```

OIR sits at the seam between meaning and mechanism. Every semantic claim encoded in SIR that survives the trust-tier enforcement gate of `lowerSIR()` becomes one or more OIR bindings. Every OIR binding emits to a fixed byte sequence. The cell engine sees none of the semantic metadata; it sees only bytes.

---

## Why a Dual IR

The pipeline maintains two separate intermediate representations rather than one. The reason is that the two layers answer different questions.

SIR answers: what is this expression semantically, who has the authority to make this claim, and under which governance context is it asserted? It carries jural categories, governance domain bindings, trust class, proof requirements, and execution authority. These are semantic claims — they constrain which computations are even legal, independent of what the computation actually does. `lowerSIR()` enforces those constraints structurally: an `authoritative` trust-class claim without a `formal` proof requirement is refused at the IR level, before any bytes are produced.

OIR answers: what are the concrete predicates, in what order do they evaluate, and what bytes do they emit? It carries named bindings, comparison operators, capability numbers, domain flags, timestamps, and logical combinators. It does not carry jural categories, governance context, or identity bindings — those were checked during lowering and are no longer load-bearing at emit time.

The table from PIPELINE.md captures this precisely:

| Layer | What it adds | Why it has to exist |
|---|---|---|
| SIR | Jural categories, trust class, proof requirement, execution authority, governance context | Semantic claims — constrain what computations are legal before lowering to mechanical predicates. `lowerSIR()` refuses to produce OIR if (e.g.) an `authoritative` claim has no `formal` proof. |
| OIR (ANF) | Named bindings, explicit data flow, computational predicates | Lingua franca of compilation — once in ANF, multiple back-ends can target it without re-parsing. |
| Opcode bytes | Concrete VM instructions in the 0x4C–0xD0 range | What the cell engine executes. |

There is also a cross-surface equivalence property. Two different surface grammars expressing the same semantic intent — a Lisp expression and a future LaTeX surface, say — should produce OIR programs that are α-equivalent: identical up to the renaming of binding names. This equivalence is the mechanism behind the compression-gradient claim: the kernel does not care which surface produced the bytes, because the bytes are the same. Adding a new surface grammar is a matter of writing a new parser and a new SIR construction pass; the OIR and everything below it remain untouched.

---

## ANF — A-Normal Form

OIR is defined in A-normal form (ANF). The definition, from the glossary:

> ANF (A-normal form) is the intermediate-form discipline used by OIR in which every non-trivial sub-expression is bound to a named variable, and operand positions hold only names or constants. ANF makes data-flow explicit and continuations sequential, simplifying lowering to bytecode.

The practical consequence: no expression nesting. Where a naive compiler might represent `(and (check-cap SIGNING) (domain-flag 0x0002))` as a tree of nested nodes, OIR flattens it into a sequence of named bindings:

```
$0 := check-cap(SIGNING)
$1 := domain-flag(0x0002)
$2 := logical-and($0, $1)
```

Each binding has a name (generated counter-based: `$0`, `$1`, `$2`, …), a kind, and kind-specific payload fields. Operand positions — where `$0` and `$1` appear in `$2` — hold only names, not sub-expressions. The final binding is the result of the program.

ANF does two things that matter for emit. First, it makes evaluation order unambiguous: the topological order of the binding list is the execution order. Second, it makes each binding independently emittable: `emitBinding($2)` can inspect `$2.kind` and `$2.operands` without traversing the tree again. The emit pass is a flat loop over an ordered list.

---

## The OIR Type Definitions

The types that define OIR are in `core/semantos-ir/src/types.ts`:

```ts
export type IRKind =
  | 'comparison'
  | 'logical_and'
  | 'logical_or'
  | 'logical_not'
  | 'capability'
  | 'domainCheck'
  | 'timeConstraint'
  | 'hostCall'
  | 'typeHashCheck'
  | 'deref';

export interface IRBinding {
  /** Unique binding name (counter-based: "$0", "$1", ...) */
  name: string;
  /** Which constraint kind produced this binding */
  kind: IRKind;

  // Kind-specific payload (only relevant fields are set)
  op?: string;          // comparison operator (>, <, >=, <=, =, !=)
  field?: string;       // field name for comparison
  value?: number | string;   // literal value for comparison

  operands?: string[];  // references to operand bindings (logical combinators)

  capabilityNumber?: number;
  domainFlag?: number | string;

  timeOp?: 'timeAfter' | 'timeBefore';
  timestamp?: number;   // Unix timestamp (seconds since epoch)

  functionName?: string;
  expectedHash?: string; // 64-char hex
}

export interface IRProgram {
  /** Ordered sequence of bindings (topological order) */
  bindings: IRBinding[];
  /** Name of the final binding whose value is the program result */
  result: string;
}
```

Ten `IRKind` variants cover the full constraint vocabulary. The `IRBinding` interface uses optional fields in a tagged-union style: each kind uses only the fields relevant to it. An `IRProgram` is an ordered list of bindings plus the name of the result binding.

The topological ordering is a contract: every binding's `operands` (for logical kinds) reference only earlier bindings in the list. The lower pass maintains this contract by construction — it recurses into sub-expressions before creating the combinator binding, so operand bindings are always pushed before the binding that references them.

---

## Nanopass 1: Lower — AST to OIR

The lower pass is in `core/semantos-ir/src/lower.ts`. It is a recursive descent over a `ConstraintExpr` AST that produces an `IRProgram`. The entire pass is a pure function with no I/O.

```ts
export function lower(expr: ConstraintExpr): IRProgram {
  const names = new NameGen();
  const bindings: IRBinding[] = [];
  const result = lowerExpr(expr, names, bindings);
  return { bindings, result };
}
```

`NameGen` is a counter that produces `$0`, `$1`, `$2`, … in order. `lowerExpr` is a `switch` over `expr.kind`:

```ts
function lowerExpr(
  expr: ConstraintExpr,
  names: NameGen,
  bindings: IRBinding[],
): string {
  switch (expr.kind) {
    case 'comparison': {
      const name = names.next();
      bindings.push({
        name,
        kind: 'comparison',
        op: expr.op,
        field: expr.field,
        value: expr.value,
      });
      return name;
    }

    case 'logical': {
      // Lower all operands first (ANF: sub-expressions before combinators)
      const operandNames = expr.operands.map(op => lowerExpr(op, names, bindings));

      if (expr.op === 'not') {
        const name = names.next();
        bindings.push({ name, kind: 'logical_not', operands: operandNames });
        return name;
      }

      const irKind: IRKind = expr.op === 'and' ? 'logical_and' : 'logical_or';
      const name = names.next();
      bindings.push({ name, kind: irKind, operands: operandNames });
      return name;
    }

    case 'capability': {
      const name = names.next();
      bindings.push({ name, kind: 'capability', capabilityNumber: expr.capabilityNumber });
      return name;
    }

    case 'domainCheck': {
      const name = names.next();
      bindings.push({ name, kind: 'domainCheck', domainFlag: expr.domainFlag });
      return name;
    }

    case 'timeConstraint': {
      const unix = Math.floor(new Date(expr.isoTimestamp).getTime() / 1000);
      const name = names.next();
      bindings.push({ name, kind: 'timeConstraint', timeOp: expr.op, timestamp: unix });
      return name;
    }

    // ... hostCall, typeHashCheck, deref follow the same pattern
  }
}
```

The key ANF invariant is visible in the `logical` case: `expr.operands.map(op => lowerExpr(op, names, bindings))` lowers each operand into the binding list first, collecting their names, before the combinator binding is pushed. This ensures combinator bindings always follow their operand bindings in the list — the topological ordering contract is maintained structurally, not as a post-pass sort.

The `timeConstraint` case contains the one non-trivial transformation in the pass: ISO 8601 timestamps are converted to Unix seconds (`Math.floor(new Date(isoTimestamp).getTime() / 1000)`) at lower time. The emit pass sees only integer seconds; it does not need to parse dates.

---

## Nanopass 2: Emit — OIR to Bytes

The emit pass is in `core/semantos-ir/src/emit.ts`. It is equally a pure function: an `IRProgram` in, a `Uint8Array` of opcode bytes out.

```ts
export function emit(program: IRProgram): Uint8Array {
  const bytes: number[] = [];
  for (const binding of program.bindings) {
    bytes.push(...emitBinding(binding));
  }
  return new Uint8Array(bytes);
}
```

The loop is flat. Each binding emits independently via `emitBinding`. The result is the concatenation of all binding byte sequences.

### Opcode Constants

The emit pass references the cell engine's opcode set directly:

```ts
const OP_PUSHDATA1      = 0x4C;
const OP_EQUAL          = 0x87;
const OP_NOT            = 0x91;
const OP_NUMNOTEQUAL    = 0x9E;
const OP_BOOLAND        = 0x9A;
const OP_BOOLOR         = 0x9B;
const OP_LESSTHAN       = 0x9F;
const OP_GREATERTHAN    = 0xA0;
const OP_LESSTHANOREQUAL    = 0xA1;
const OP_GREATERTHANOREQUAL = 0xA2;
const OP_CHECKCAPABILITY    = 0xC3;
const OP_CHECKDOMAINFLAG    = 0xC6;
const OP_CHECKTYPEHASH      = 0xC7;
const OP_DEREF_POINTER      = 0xC8;
const OP_CALLHOST       = 0xD0;
const OP_LOADFIELD      = 0xB0;
```

Standard Bitcoin Script opcodes occupy `0x00`–`0x4B`. The Plexus extension range occupies `0x4C`–`0xD0`. OIR targets both: comparison and logical opcodes are from the standard range; capability, domain, type-hash, and host-call opcodes are from the Plexus extension range.

### Encoding Helpers

The emit pass includes three encoding helpers copied from the Lisp compiler:

`encodeScriptNumber(n)` — converts an integer to the little-endian Bitcoin Script number encoding. Zero maps to `[0x00]`. Negative numbers have the sign bit in the most-significant byte. The encoding is minimal: no leading zero bytes unless required by the sign rule.

`encodePushData(data)` — wraps a byte array in a push instruction. For data ≤ 75 bytes: `[len, ...data]`. For data 76–255 bytes: `[0x4C, len, ...data]` (the `OP_PUSHDATA1` form).

`encodePushNumber(n)` — composes the two: `encodePushData(encodeScriptNumber(n))`.

### The emitBinding Switch

`emitBinding` dispatches on `binding.kind`:

```ts
function emitBinding(binding: IRBinding): number[] {
  switch (binding.kind) {
    case 'comparison': {
      const opcode = COMPARISON_OPCODES[binding.op!];
      const pushBytes = typeof binding.value === 'number'
        ? [...encodePushNumber(binding.value)]
        : [...encodePushString(binding.value as string)];
      const fieldBytes = [...encodePushString(binding.field!), OP_LOADFIELD];
      return [...pushBytes, ...fieldBytes, opcode];
    }

    case 'logical_not':
      return [OP_NOT];

    case 'logical_and': {
      const count = binding.operands!.length - 1;
      return Array(count).fill(OP_BOOLAND);
    }

    case 'logical_or': {
      const count = binding.operands!.length - 1;
      return Array(count).fill(OP_BOOLOR);
    }

    case 'capability':
      return [...encodePushNumber(binding.capabilityNumber!), OP_CHECKCAPABILITY];

    case 'domainCheck': {
      const flag = typeof binding.domainFlag === 'number'
        ? binding.domainFlag
        : parseInt(binding.domainFlag as string, 16) || 0;
      return [...encodePushNumber(flag), OP_CHECKDOMAINFLAG];
    }

    case 'timeConstraint': {
      const opcode = binding.timeOp === 'timeAfter' ? OP_GREATERTHAN : OP_LESSTHAN;
      return [...encodePushNumber(binding.timestamp!), opcode];
    }

    case 'hostCall':
      return [...encodePushString(binding.functionName!), OP_CALLHOST];

    case 'typeHashCheck': {
      const hashBytes = hexToBytes(binding.expectedHash!);
      return [...encodePushData(hashBytes), OP_CHECKTYPEHASH];
    }

    case 'deref':
      return [OP_DEREF_POINTER];
  }
}
```

A few structural observations:

The logical combinator cases (`logical_and`, `logical_or`) emit only the combinator opcode(s) — never the operand bytes. The operand bindings were already emitted earlier in the flat loop, in topological order, and their results sit on the stack. A two-operand `logical_and` emits one `OP_BOOLAND` (`0x9A`). A three-operand `logical_and` emits two: the first combines operands 1 and 2; the second combines that result with operand 3. The pattern is `n - 1` chained opcodes for `n` operands.

`logical_not` emits a single `OP_NOT` (`0x91`). Again, the operand bytes were already emitted.

`comparison` follows the Bitcoin Script convention for binary operators: push both operands, then opcode. The field name is pushed via `encodePushString`, then `OP_LOADFIELD` (`0xB0`) is issued to resolve it to a value on the stack. The comparison value (numeric or string) is pushed before the field. The comparison opcode follows.

`capability` emits a push of the capability number followed by `OP_CHECKCAPABILITY` (`0xC3`). The cell engine's `OP_CHECKCAPABILITY` handler pops the number and verifies the caller holds the corresponding capability via SPV proof in the continuation cell.

`domainCheck` emits a push of the domain flag (a `uint32` in the Plexus namespace partition) followed by `OP_CHECKDOMAINFLAG` (`0xC6`), which enforces the K3 domain-isolation invariant at bytecode level.

`typeHashCheck` converts the hex-encoded expected hash to raw bytes, pushes them, then issues `OP_CHECKTYPEHASH` (`0xC7`) to compare the top-of-stack cell's type hash against the expected value.

`deref` emits a single `OP_DEREF_POINTER` (`0xC8`), resolving a pointer cell to its target.

`hostCall` emits the function name as a string push followed by `OP_CALLHOST` (`0xD0`), the highest byte in the Plexus extension range.

---

## Worked Trace: One SIR Program Through to Bytes

This section traces a single program end-to-end — from SIR through OIR lowering to the final byte sequence — so the reader can verify each transformation by hand.

### The program

The policy: "a party may perform this action only if they hold the SIGNING capability (capability number 1) and the request falls within governance domain flag 0x0002."

In SIR (as constructed by `lowerSIR()` or by the Lisp compiler's `buildSIR()` step):

```
SIRProgram {
  jural:      permission
  trustClass: interpretive
  proofReq:   attestation
  execAuth:   hat_scoped
  linearity:  RELEVANT
  constraint: {
    kind: logical-and
    operands: [
      { kind: capability, capabilityNumber: 1 },
      { kind: domainCheck, domainFlag: 0x0002 }
    ]
  }
}
```

The Lisp surface form of this policy is:

```lisp
(and (check-cap 1) (domain-flag 2))
```

The SIR carries the jural, trust, and governance metadata. The `constraint` field holds the predicate structure. `lowerSIR()` has already verified that the trust class is within the hat's ceiling, that the jural category is consistent with the governance context, and that the execution authority matches the hat scope. It passes the constraint structure to `lower()` for ANF conversion.

### Step 1: ANF lowering

`lower()` processes the `constraint` field. The AST is:

```
LogicalExpr(op='and', operands=[
  CapabilityExpr(capabilityNumber=1),
  DomainCheckExpr(domainFlag=0x0002)
])
```

The lower pass recurses. The `logical` case maps each operand before creating the combinator binding:

First operand: `CapabilityExpr(capabilityNumber=1)` → binding `$0`:

```
$0 = IRBinding { name: '$0', kind: 'capability', capabilityNumber: 1 }
```

Second operand: `DomainCheckExpr(domainFlag=0x0002)` → binding `$1`:

```
$1 = IRBinding { name: '$1', kind: 'domainCheck', domainFlag: 0x0002 }
```

Combinator: `logical_and` over `[$0, $1]` → binding `$2`:

```
$2 = IRBinding { name: '$2', kind: 'logical_and', operands: ['$0', '$1'] }
```

The resulting `IRProgram`:

```
IRProgram {
  bindings: [
    { name: '$0', kind: 'capability',   capabilityNumber: 1      },
    { name: '$1', kind: 'domainCheck',  domainFlag: 0x0002        },
    { name: '$2', kind: 'logical_and',  operands: ['$0', '$1']   },
  ],
  result: '$2'
}
```

Three bindings; topological order is maintained — `$2` references `$0` and `$1`, both of which appear earlier in the list.

### Step 2: Emit

The emit pass iterates over the three bindings in order.

**Binding `$0` — capability, capabilityNumber=1:**

`encodePushNumber(1)` produces `encodeScriptNumber(1)` = `[0x01]`, then `encodePushData([0x01])` = `[0x01, 0x01]` (length 1, then the byte).

Appended: `OP_CHECKCAPABILITY` = `0xC3`.

Bytes from `$0`: `[0x01, 0x01, 0xC3]`

**Binding `$1` — domainCheck, domainFlag=0x0002:**

`domainFlag` is numeric (2). `encodePushNumber(2)` → `encodeScriptNumber(2)` = `[0x02]` → `encodePushData([0x02])` = `[0x01, 0x02]`.

Appended: `OP_CHECKDOMAINFLAG` = `0xC6`.

Bytes from `$1`: `[0x01, 0x02, 0xC6]`

**Binding `$2` — logical_and, operands=['$0','$1']:**

Operand count = 2; combinator count = 2 - 1 = 1. One `OP_BOOLAND` = `0x9A`.

Bytes from `$2`: `[0x9A]`

**Final byte sequence:**

```
01 01 C3   // push 1, OP_CHECKCAPABILITY
01 02 C6   // push 2, OP_CHECKDOMAINFLAG
9A         // OP_BOOLAND
```

Total: 7 bytes.

The cell engine will execute this sequence left to right. `OP_CHECKCAPABILITY` pops `1` from the stack and verifies the caller holds capability number 1. `OP_CHECKDOMAINFLAG` pops `2` and verifies the current domain flag matches. `OP_BOOLAND` pops both boolean results and pushes their logical AND. The top of stack is the program result; the cell engine tests it to allow or deny the action.

### Step 3: Byte-budget verification

At the ANF level, the full three-binding OIR program fits in one printed line per binding. At the byte level, the encoding is 7 bytes for a two-predicate conjunctive policy. The whitepaper § 3.6 example shows a comparable single-predicate capability check at 4 bytes. The two-predicate version costs 3 additional bytes — the domain-flag predicate occupies 3 bytes and the BOOLAND costs 1, but the BOOLAND subsumes the previous 1-byte overhead, so the net cost of adding one more predicate to a conjunctive policy is 3 bytes (push operand: 2 bytes, check opcode: 1 byte), with 1 BOOLAND byte amortised across the set.

---

## The Byte-Budget Table

The following table reproduces the compression-gradient byte-budget from Whitepaper v3 § 3.6, which traces the single-predicate capability-check example:

> "any party with the SIGNING capability for protocol 0x02 may perform this action"

| Stage | Approximate size | Form |
|---|---|---|
| Natural language | ~14 words | "any party with the SIGNING capability for protocol 0x02 …" |
| Lisp surface | 3 forms | `(check-cap SIGNING 0x02)` |
| OIR (ANF) | 1 binding | `$0 := check-cap(SIGNING, 0x02)` |
| Opcode bytes | 4 bytes | `0xC3 0x01 0x02` + length prefix |

The OIR column is one binding: `IRBinding { kind: 'capability', capabilityNumber: 0x01, domainFlag: 0x0002 }`. The emit of that binding is `encodePushNumber(1)` → `[0x01, 0x01]` plus `OP_CHECKCAPABILITY` `[0xC3]`, giving 3 encoded bytes. (The whitepaper cites "4 bytes" inclusive of the `OP_PUSHDATA1` form's leading length byte when protocol IDs are 2 bytes; the exact encoding depends on the capability number size.)

The compression gradient from top to bottom is not linear — natural language is more than 14× larger than the OIR binding, and the OIR binding is roughly 10× larger (in semantic content) than the 4-byte opcode sequence. The dramatic compression at the bottom is what makes the kernel small. The cell engine's full WASM profile is 185 KB; the embedded profile is 29 KB. Those sizes are affordable because the instruction set is compact: the 7-byte sequence above encodes a two-predicate conjunctive policy that in a general-purpose language would require dozens of bytes of function-call overhead.

The dramatic compression at the top — from natural language through SIR — is what makes domain-specific surface grammars commercially feasible. A LaTeX-surface policy and a Lisp-surface policy expressing the same intent lower to α-equivalent OIR programs. The kernel executes the same bytes regardless of which grammar produced them.

---

## The OIR as Lingua Franca

The OIR occupies the structural position of lingua franca in a multi-surface compiler. The PIPELINE.md documents this explicitly: SIR and OIR are both fully implemented but currently bypassed by the direct Lisp compiler, which emits bytes without going through either IR. Phase 3 of the restructuring wires the IR chain in.

When that wiring is complete, the invariant that the existing Lisp golden corpus establishes becomes the seam contract:

> For every program in the existing Lisp golden corpus, `compile(src)` must produce bytes byte-identical (or α-equivalent) to `emit(lowerSIR(compileToSIR(src)))`.

This equivalence is testable: the lower and emit passes are pure functions; their composition is deterministic; differential testing against the existing compiled outputs can verify the seam without changing the cell engine or the kernel at all.

The α-equivalence weaker condition is necessary for cases where binding names differ but the byte output is identical. Binding names (`$0`, `$1`, …) are artifacts of counter-based generation; the bytes produced by `emit()` do not embed them. Two programs that produce the same bytes are semantically equivalent regardless of their intermediate binding names.

---

## What Each Kind Emits — Reference

The following table summarises the byte structure each `IRKind` produces, for reference when reading emit output by hand:

| Kind | Stack effect before opcode | Byte pattern |
|---|---|---|
| `comparison` | push value; push field name; `OP_LOADFIELD` | `[len, ...value_bytes, len, ...field_bytes, 0xB0, opcode]` |
| `logical_not` | operand already on stack | `[0x91]` |
| `logical_and` (n operands) | all n operands on stack | `[0x9A] × (n−1)` |
| `logical_or` (n operands) | all n operands on stack | `[0x9B] × (n−1)` |
| `capability` | — | `[len, cap_num, 0xC3]` |
| `domainCheck` | — | `[len, flag_bytes, 0xC6]` |
| `timeConstraint` (after) | — | `[len, ts_bytes, 0xA0]` (OP_GREATERTHAN) |
| `timeConstraint` (before) | — | `[len, ts_bytes, 0x9F]` (OP_LESSTHAN) |
| `hostCall` | — | `[len, ...name_bytes, 0xD0]` |
| `typeHashCheck` | — | `[0x4C, 0x20, ...32_hash_bytes, 0xC7]` |
| `deref` | — | `[0xC8]` |

The `typeHashCheck` case deserves a note: a type hash is always 32 bytes (SHA-256). That exceeds the 75-byte threshold for the compact push form, so it uses `OP_PUSHDATA1` (`0x4C`) with an explicit length byte `0x20` (32 decimal). The resulting 3-byte header plus 32 payload bytes gives a 35-byte push sequence, followed by `OP_CHECKTYPEHASH` (`0xC7`) — 36 bytes total for a type hash check. A policy that checks a capability, a domain flag, and a type hash will therefore cost roughly 3 + 3 + 36 = 42 bytes of predicate payload, plus `(3−1) = 2` BOOLAND bytes for the conjunction: 44 bytes total. Still compact at the scale of a 1 KB cell.

---

## Equivalence of the OIR and Lisp Compiler Paths

The emit pass is designed with a specific contract:

> The output is byte-for-byte identical to `LispCompiler.compileConstraint()` for the same input `ConstraintExpr`.

This contract is stated in the source comment of `emit.ts` and is the foundation of the Phase 3 seam test. It means the OIR chain is not a new compiler — it is a re-articulation of the existing Lisp compiler's logic through a named-binding intermediate form. The opcode constants, the encoding helpers (`encodeScriptNumber`, `encodePushData`), and the per-kind emission logic are copied verbatim from the Lisp compiler. The OIR chain adds the intermediate form and the ANF discipline; it does not change the bytes.

This design choice has a practical consequence: any test that passes for the Lisp compiler can be re-run against `emit(lower(expr))` and must produce identical bytes. The existing golden-file test corpus is therefore the acceptance criterion for the OIR chain, not an additional test burden. When Phase 3 wiring connects the OIR path to the Lisp compiler's surface, the existing 240+ conformance tests provide the verification signal at zero marginal cost.

---

## Current Status

The component table from PIPELINE.md:

| Component | Built? | Wired? |
|---|---|---|
| OIR types (ANF) | Yes | unused by live Lisp path |
| OIR `lower(CExpr → IRProgram)` | Yes | unused by live Lisp path |
| OIR `emit(IRProgram → bytes)` | Yes | unused by live Lisp path |
| SIR `lowerSIR(SIRProgram → IRProgram)` | Yes | unused by live Lisp path |

All four components are fully implemented. The Lisp compiler, which is wired in production, emits opcodes directly from the AST without using the OIR layer. This is a deliberate deferral: the Lisp compiler has golden-file test coverage and ships; the OIR chain is implemented and tested in isolation but not yet connected at the Lisp-compiler seam. Phase 3 of the restructuring creates that connection. Until then, the OIR and SIR packages serve as the reference implementation for the intended full pipeline and as the target against which future surface grammars (LaTeX, Lean-ish, Ricardian, EDI) will compile.

---

## Summary

OIR (Opcode IR) is the lower of the two intermediate representations in the pipeline. It is ANF-shaped: every sub-expression is a named binding; operand positions hold only names or constants; the binding list is in topological order. The lower pass (`lower()`) converts a `ConstraintExpr` AST into an `IRProgram` by recursive descent, pushing operand bindings before combinator bindings. The emit pass (`emit()`) converts an `IRProgram` into a `Uint8Array` of cell-engine opcodes by iterating the binding list in order and concatenating per-binding byte sequences.

The two-pass structure — lower then emit — keeps each pass simple and independently testable. The lower pass is pure tree traversal with a counter; the emit pass is pure pattern matching with arithmetic encoding. Neither pass has I/O; both are deterministic. The composition of the two passes is the mechanism that, combined with `lowerSIR()`, makes the full pipeline from surface grammar to opcode bytes a verifiable sequence of typed transformations — operationally boring by construction.

---

## Worked Program (Complete Trace)

> The complete SIR → OIR → bytes trace for the two-predicate policy from this chapter:

**Input SIR constraint (from `lowerSIR()` output):**

```
constraint: logical-and(
  capability(capabilityNumber=1),
  domainCheck(domainFlag=0x0002)
)
```

**After `lower()` — OIR (ANF):**

```
$0 := capability(capabilityNumber=1)
$1 := domainCheck(domainFlag=0x0002)
$2 := logical_and(operands=[$0, $1])
result: $2
```

**After `emit()` — opcode bytes:**

```
01 01 C3   // $0: push 0x01, OP_CHECKCAPABILITY (0xC3)
01 02 C6   // $1: push 0x02, OP_CHECKDOMAINFLAG (0xC6)
9A         // $2: OP_BOOLAND (0x9A)
```

Total: 7 bytes. The cell engine pops the BOOLAND result; if truthy, the action proceeds; if not, the action is denied and the cell engine state is left unchanged (kernel invariant K4, failure atomicity).

**Compression-gradient byte-budget table (from Whitepaper v3 § 3.6):**

| Stage | Approx. size | Form |
|---|---|---|
| Natural language | ~14 words | "any party with the SIGNING capability for protocol 0x02 …" |
| Lisp surface | 3 forms | `(check-cap SIGNING 0x02)` |
| OIR (ANF) | 1 binding | `$0 := check-cap(SIGNING, 0x02)` |
| Opcode bytes | 4 bytes | `0xC3 0x01 0x02` (+ encoding prefix) |

The next chapter covers the 2-PDA cell engine that executes these bytes — what happens after `emit()` returns, and how the kernel invariants K1 through K10 are enforced at bytecode level. Boot step 7 (`kernel_set_enforcement(1)`) activates at the end of that chapter.
