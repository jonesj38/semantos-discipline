---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-36A-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.667480+00:00
---

# Phase 36A Execution Prompt — Extension Grammar JSON Schema

> Paste this prompt into a fresh session to execute Phase 36A.

## Context

You are working in the `semantos-core` repo — the TypeScript application layer and shell for Semantos nodes (npm: `@semantos/core`). The kernel (cell engine, linearity, capability validation) is Zig/WASM in the sibling `semantos` repo; this repo holds the type system, protocol adapters, conversational shell, and loom UI.

Phases 36–38 build the declarative extension ecosystem. Phase 35 designed the Extension Grammar — a YAML-based DSL that connectors use to declare their data shapes, transforms, and taxonomy bindings. Phase 36A implements the **JSON Schema meta-schema** that every extension grammar must implement. This schema is the bridge between human-readable YAML extensions and the kernel's type system.

**Why this matters**: Every extension (trades, property management, dispatch) ships with a grammar file. The schema makes grammars machine-readable, validates them at load time, enables IDE autocompletion, and gives the shell commands (`semantos grammar validate`, `semantos grammar inspect`, `semantos grammar diff`) concrete definitions to check against. Without a rigorous schema, extensions will fail unpredictably at runtime.

Your task is Phase 36A: build the Extension Grammar JSON Schema, implement the grammarToExtensionConfig bridge, create an exhaustive validator, and integrate all shell grammar commands.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These are the real implementations you will build on. If you haven't read them, you will miss architectural dependencies.

**Read first** (the PRD and architecture):
- `docs/prd/PHASE-36A-EXTENSION-GRAMMAR-SCHEMA.md` — Phase 36A spec with schema spec, deliverables D36A.1–D36A.6, gate tests, completion criteria
- `docs/prd/PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md` — Context on the three-phase ecosystem build, where schemas fit, how grammars flow to extensions

**Read second** (the primary implementation targets — these are the reference implementations):
- `packages/protocol-types/src/extension-manifest.ts` — **ExtensionManifest** interface, metadata structure
- `packages/protocol-types/src/extension-loader.ts` — **ExtensionLoader**, how manifests load, dependencies
- `packages/loom/src/config/extensionConfig.ts` — **ExtensionConfig** interface, ObjectTypeDefinition, where schema validation integrates

**Read third** (configuration and reference grammars):
- `configs/extensions/core.json` — base extension config (reference)
- `configs/extensions/trades-services.json` — reference implementation with real entity shapes
- `docs/TAXONOMY-SEED-DESIGN.md` — entity taxonomy, PropertyMe stub, dispatch semantics

**Read fourth** (shell and CLI integration points):
- `packages/shell/src/parser.ts` — command parser, grammar command entry points
- `packages/shell/src/router.ts` — routing to grammar subcommands (validate, inspect, diff, list, test)

**Read fifth** (branching and CI):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-36a-extension-grammar-schema`, commits as `phase-36a/D36A.N:`

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. NO IMPERATIVE CODE IN GRAMMARS

Grammars are **declarative JSON**, not code. No `eval()`, no embedded expressions, no Turing-complete runtime. If you find yourself writing an interpreter, you are solving the wrong problem. The schema constrains what can be declared; the bridge translates declarations to ExtensionConfig.

### 2. TRANSFORMS MUST BE DECLARATIVE

PropertyMe transforms (e.g., `rent + maintenance → monthlyOwnershipCost`) live in the grammar as **name + input list + output type**, not as imperative formulas. The validator checks that all inputs are declared properties; the runner (outside Phase 36A) executes the transform as a typed operation.

### 3. THE BRIDGE IS MANDATORY

`grammarToExtensionConfig(grammar: ExtensionGrammar) → ExtensionConfig` must exist and be exhaustive. Every schema rule gets a corresponding bridge rule. Every ExtensionConfig field must be derivable from the grammar. If the bridge is incomplete, grammars cannot load.

### 4. VALIDATOR MUST BE EXHAUSTIVE

`validateExtensionGrammar(grammar: unknown) → ValidationResult` must check:
- Every property in PropertyMe has `type` (string, number, boolean, object, array, date, uuid)
- Every transform input references a declared property
- Every taxonomy binding references a valid ObjectType
- No circular references between object types
- No undefined type references
- All array types have `items` spec
- All object types have `properties` map

If a grammar passes validation, it is loadable.

### 5. REFERENCE GRAMMAR MUST BE REALISTIC

The PropertyMe stub in `docs/TAXONOMY-SEED-DESIGN.md` must have real entity shapes (not toy examples). Build the schema to accommodate:
- Address (street, city, state, zip, country, coordinates)
- Person (name, email, phone, identity fields)
- Property (address, bedrooms, bathrooms, square footage, year built, property type)
- Lease (tenant, property, rent, term, start date, end date)
- Maintenance (property, description, cost, date, status)

The schema must be rich enough to express these.

### 6. DON'T SKIP THE SHELL COMMANDS

These five commands must all work with real grammars:
- `semantos grammar validate <file.json>` — load and validate a grammar file
- `semantos grammar inspect <file.json>` — print the grammar structure
- `semantos grammar diff <old.json> <new.json>` — show what changed
- `semantos grammar list` — list all loaded extension grammars
- `semantos grammar test <file.json>` — validate + bridge + run type checks

All five must use the schema and bridge.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd /Users/toddprice/projects/semantos-core
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Commit or discard uncommitted work

Stage files explicitly, never `git add -A`. Discard stale files. Ignore `.claude/worktrees/`.

### 0.3 Verify prerequisites are complete

Phases 35 (Extension Grammar DSL design) must be complete in the documentation. These files must exist (they are the primary targets):

```bash
# Phase 35 design docs must exist
ls docs/prd/PHASE-35-EXTENSION-GRAMMAR.md
ls docs/prd/PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md
ls docs/TAXONOMY-SEED-DESIGN.md

# Phase 26+ infra must exist
ls packages/protocol-types/src/extension-manifest.ts
ls packages/protocol-types/src/extension-loader.ts
ls packages/loom/src/config/extensionConfig.ts
ls configs/extensions/core.json
ls configs/extensions/trades-services.json
```

All files must exist. If any are missing, prerequisites are incomplete — STOP and report.

### 0.4 Create Phase 36A branch

```bash
git checkout -b phase-36a-extension-grammar-schema
```

---

## Step 1: Extension Grammar JSON Schema Definition (D36A.1)

### 1.1 Create schema file

Create `packages/protocol-types/src/extension-grammar-schema.ts` with the full JSON Schema definition. The schema must define:

```typescript
// ExtensionGrammarSchema: the meta-schema that all extension grammars implement
// Properties:
// - version: "1.0"
// - extensionId: string (kebab-case identifier)
// - name: string
// - description: string
// - objectTypes: Map<string, ObjectTypeDefinition>
//   - Each ObjectTypeDefinition has:
//     - name: string
//     - description: string
//     - properties: Map<string, PropertyDefinition>
//       - Each PropertyDefinition has:
//         - name: string
//         - type: "string" | "number" | "boolean" | "date" | "uuid" | "object" | "array"
//         - required: boolean
//         - description: string
//         - validation?: { minLength?, maxLength?, pattern?, min?, max? }
//         - items?: ObjectTypeDefinition (for arrays)
//     - taxonomy?: {
//         - path: string (e.g., "location/address/street")
//         - rootEntity: string (the object type this belongs to)
//       }
// - transforms?: Map<string, TransformDefinition>
//   - Each TransformDefinition has:
//     - name: string
//     - inputs: string[] (property names)
//     - output: PropertyDefinition
//     - description: string
```

Export this as `ExtensionGrammarSchema` (TypeScript interface).

### 1.2 Add to barrel exports

In `packages/protocol-types/src/index.ts`:
```typescript
export type { ExtensionGrammarSchema } from './extension-grammar-schema';
export { validateExtensionGrammar } from './extension-grammar-schema';
```

### 1.3 Verify

```bash
bun run check 2>&1 | grep -i "grammar-schema" | head -10
```

Commit: `phase-36a/D36A.1: define Extension Grammar JSON Schema`

---

## Step 2: Grammar Validator (D36A.2)

### 2.1 Implement exhaustive validator

Create `packages/protocol-types/src/grammar-validator.ts` with:

```typescript
export type ValidationError = {
  path: string;
  message: string;
  severity: "error" | "warning";
};

export type ValidationResult = {
  valid: boolean;
  errors: ValidationError[];
};

export function validateExtensionGrammar(grammar: unknown): ValidationResult {
  // Check: grammar is object
  // Check: has extensionId (kebab-case)
  // Check: has name, description
  // Check: version is "1.0"
  // For each objectType:
  //   - Check: has name, description
  //   - Check: has properties (non-empty map)
  //   - For each property:
  //     - Check: has name, type, required
  //     - Check: type is valid (string | number | boolean | date | uuid | object | array)
  //     - If type is array, check items is defined
  //     - If validation rules present, check they are valid (min/max/pattern etc.)
  //   - If taxonomy present:
  //     - Check: path is string
  //     - Check: rootEntity references declared object type
  // For each transform:
  //   - Check: has name, inputs (array), output (PropertyDefinition)
  //   - For each input: check it references a declared property
  //   - Check: output type is valid
  // Return ValidationResult with all errors collected (don't short-circuit)
}
```

### 2.2 Add unit tests

Create `packages/__tests__/grammar-validator.test.ts` with:
- T1: Valid minimal grammar passes
- T2: Valid PropertyMe grammar with Address/Person/Property/Lease passes
- T3: Missing extensionId fails
- T4: Invalid extensionId (not kebab-case) fails
- T5: ObjectType with undefined property type fails
- T6: Transform with missing input property fails
- T7: Transform referencing undefined input fails
- T8: Circular reference detection (if applicable)
- T9: Valid taxonomy binding passes
- T10: Invalid taxonomy path fails

### 2.3 Verify

```bash
bun test packages/__tests__/grammar-validator.test.ts
```

All tests must pass.

Commit: `phase-36a/D36A.2: implement exhaustive Extension Grammar validator`

---

## Step 3: Grammar-to-ExtensionConfig Bridge (D36A.3)

### 3.1 Implement bridge function

Create `packages/protocol-types/src/grammar-to-config.ts` with:

```typescript
export function grammarToExtensionConfig(
  grammar: ExtensionGrammarSchema,
): ExtensionConfig {
  // For each ObjectType in grammar:
  //   - Create ObjectTypeDefinition in config
  //   - Map properties: grammar PropertyDefinition → config ObjectTypeProperty
  //   - Map taxonomy: grammar taxonomy binding → config taxonomy path
  // For each Transform in grammar:
  //   - Create a ComputedProperty in the target ObjectType
  //   - Map inputs and output
  // Return ExtensionConfig with all mappings complete
  //
  // This function is the **contract** between declarative grammars and the type system.
  // If grammarToExtensionConfig(grammar) succeeds, the grammar is loadable.
}
```

### 3.2 Test the bridge

Create `packages/__tests__/grammar-to-config.test.ts` with:
- T1: Minimal valid grammar → ExtensionConfig (property by property verification)
- T2: PropertyMe with Address object → config has address properties
- T3: PropertyMe with Person object → config has person properties
- T4: Transform with rent + maintenance → monthlyOwnershipCost → config has computed property
- T5: Taxonomy binding for Person.email → contact/email/primary → config has taxonomy
- T6: Array property (Lease has array of maintenances) → config has array items
- T7: Round-trip: grammar → config → validate config → must not error

### 3.3 Verify

```bash
bun test packages/__tests__/grammar-to-config.test.ts
```

All tests must pass.

Commit: `phase-36a/D36A.3: implement grammar-to-config bridge with exhaustive tests`

---

## Step 4: Shell Grammar Commands (D36A.4)

### 4.1 Update parser and router

In `packages/shell/src/parser.ts`, add grammar command group:

```typescript
// grammar validate <file.json>
// grammar inspect <file.json>
// grammar diff <old.json> <new.json>
// grammar list
// grammar test <file.json>
```

In `packages/shell/src/router.ts`, add handlers:

```typescript
async function handleGrammarValidate(filePath: string): Promise<void> {
  // Load file as JSON
  // Call validateExtensionGrammar()
  // Print results
}

async function handleGrammarInspect(filePath: string): Promise<void> {
  // Load file as JSON
  // Call validateExtensionGrammar() (must pass)
  // Print human-readable structure (object types, properties, transforms)
}

async function handleGrammarDiff(oldPath: string, newPath: string): Promise<void> {
  // Load both files
  // Validate both
  // Compute diff (added/removed/modified object types, properties, transforms)
  // Print diff
}

async function handleGrammarList(): Promise<void> {
  // List all ExtensionGrammarSchema objects currently loaded
  // Print: extensionId, name, object type count, property count
}

async function handleGrammarTest(filePath: string): Promise<void> {
  // Load file
  // Call validateExtensionGrammar()
  // Call grammarToExtensionConfig()
  // Validate resulting config
  // Print: "Grammar valid. Config generated successfully."
}
```

### 4.2 Test shell commands

Create `packages/__tests__/phase36a-shell-commands.test.ts` with:
- T1: `semantos grammar validate <valid-grammar.json>` exits 0
- T2: `semantos grammar validate <invalid-grammar.json>` exits 1, shows errors
- T3: `semantos grammar inspect <grammar.json>` prints object types, properties
- T4: `semantos grammar diff <old.json> <new.json>` shows changes
- T5: `semantos grammar list` shows loaded grammars
- T6: `semantos grammar test <grammar.json>` succeeds if grammar → config succeeds

### 4.3 Verify

```bash
bun test packages/__tests__/phase36a-shell-commands.test.ts
```

All tests must pass.

Commit: `phase-36a/D36A.4: implement shell grammar commands (validate/inspect/diff/list/test)`

---

## Step 5: Reference PropertyMe Grammar (D36A.5)

### 5.1 Create example grammar file

Create `configs/extensions/propertyme-grammar.json` — a complete Extension Grammar Schema for PropertyMe. Include:

```json
{
  "version": "1.0",
  "extensionId": "propertyme-propertymanagement",
  "name": "PropertyMe Property Management Grammar",
  "description": "Real property management entities with addresses, people, leases, and maintenance.",
  "objectTypes": {
    "Address": {
      "name": "Address",
      "description": "Physical location with street, city, state, zip, country, coordinates",
      "properties": {
        "street": { "type": "string", "required": true, "description": "Street address" },
        "city": { "type": "string", "required": true, "description": "City" },
        "state": { "type": "string", "required": true, "description": "State/province" },
        "zip": { "type": "string", "required": true, "description": "ZIP/postal code" },
        "country": { "type": "string", "required": true, "description": "Country code (ISO 3166)" },
        "latitude": { "type": "number", "required": false, "description": "Latitude coordinate" },
        "longitude": { "type": "number", "required": false, "description": "Longitude coordinate" }
      }
    },
    "Person": {
      "name": "Person",
      "description": "Individual with contact and identity information",
      "properties": {
        "firstName": { "type": "string", "required": true, "description": "Given name" },
        "lastName": { "type": "string", "required": true, "description": "Family name" },
        "email": { "type": "string", "required": true, "description": "Email address" },
        "phone": { "type": "string", "required": false, "description": "Phone number" },
        "ssn": { "type": "string", "required": false, "description": "Social security number (last 4 digits only)" }
      },
      "taxonomy": {
        "path": "contact/person",
        "rootEntity": "Person"
      }
    },
    "Property": {
      "name": "Property",
      "description": "Real property with location, structure, and ownership details",
      "properties": {
        "address": { "type": "object", "required": true, "description": "Physical location" },
        "bedrooms": { "type": "number", "required": true, "description": "Number of bedrooms" },
        "bathrooms": { "type": "number", "required": true, "description": "Number of bathrooms" },
        "squareFootage": { "type": "number", "required": true, "description": "Total square footage" },
        "yearBuilt": { "type": "number", "required": false, "description": "Year of construction" },
        "propertyType": { "type": "string", "required": true, "description": "Type: apartment, house, condo, commercial" }
      }
    },
    "Lease": {
      "name": "Lease",
      "description": "Tenancy agreement between landlord and tenant",
      "properties": {
        "tenant": { "type": "object", "required": true, "description": "Tenant Person object" },
        "property": { "type": "object", "required": true, "description": "Property object" },
        "rent": { "type": "number", "required": true, "description": "Monthly rent in dollars" },
        "term": { "type": "number", "required": true, "description": "Lease term in months" },
        "startDate": { "type": "date", "required": true, "description": "Lease commencement date" },
        "endDate": { "type": "date", "required": true, "description": "Lease expiration date" }
      }
    },
    "Maintenance": {
      "name": "Maintenance",
      "description": "Property maintenance task or repair",
      "properties": {
        "property": { "type": "object", "required": true, "description": "Property being maintained" },
        "description": { "type": "string", "required": true, "description": "Work description" },
        "cost": { "type": "number", "required": true, "description": "Cost in dollars" },
        "date": { "type": "date", "required": true, "description": "Date work was performed" },
        "status": { "type": "string", "required": true, "description": "Status: pending, in-progress, completed" }
      }
    }
  },
  "transforms": {
    "monthlyOwnershipCost": {
      "name": "monthlyOwnershipCost",
      "inputs": ["rent", "maintenance"],
      "output": {
        "type": "number",
        "description": "Rent plus prorated maintenance costs"
      },
      "description": "Calculate total monthly ownership cost by adding rent and maintenance"
    }
  }
}
```

### 5.2 Validate the reference grammar

```bash
semantos grammar validate configs/extensions/propertyme-grammar.json
# Should output: "Grammar is valid. 5 object types, 1 transform."
```

### 5.3 Test all grammar commands on reference

```bash
semantos grammar inspect configs/extensions/propertyme-grammar.json
semantos grammar diff configs/extensions/propertyme-grammar.json configs/extensions/propertyme-grammar.json
semantos grammar list
semantos grammar test configs/extensions/propertyme-grammar.json
```

All must succeed.

Commit: `phase-36a/D36A.5: add reference PropertyMe Extension Grammar (realistic entities)`

---

## Step 6: Gate Tests (D36A.6)

### 6.1 Create gate test file

Create `packages/__tests__/phase36a-gate.test.ts` with comprehensive tests:

- **T1–T4: Schema completeness**
  - T1: ExtensionGrammarSchema type is exported
  - T2: validateExtensionGrammar() is exported
  - T3: grammarToExtensionConfig() is exported
  - T4: All five grammar shell commands exist (validate, inspect, diff, list, test)

- **T5–T10: Validator correctness**
  - T5: Valid minimal grammar passes
  - T6: Invalid extensionId fails
  - T7: Missing required properties in object type fails
  - T8: Transform with undefined input fails
  - T9: Valid PropertyMe grammar with all five entity types passes
  - T10: Circular reference detection (if implemented) works

- **T11–T13: Bridge correctness**
  - T11: Grammar → config produces valid ExtensionConfig
  - T12: All properties in grammar appear in config
  - T13: Transforms appear as computed properties in config

- **T14–T16: Shell command integration**
  - T14: `semantos grammar validate` works end-to-end
  - T15: `semantos grammar test` calls both validator and bridge
  - T16: Reference PropertyMe grammar passes all commands

### 6.2 Run gate tests

```bash
bun test packages/__tests__/phase36a-gate.test.ts
```

All 16 tests must pass.

Commit: `phase-36a/D36A.6: add Phase 36A gate tests (T1–T16, full coverage)`

---

## Step 7: Final Verification

### 7.1 Full codebase scan

```bash
# Check that schema, validator, bridge are exported
grep -n "ExtensionGrammarSchema\|validateExtensionGrammar\|grammarToExtensionConfig" packages/protocol-types/src/index.ts

# Check that grammar commands are in parser/router
grep -n "grammar validate\|grammar inspect\|grammar diff\|grammar list\|grammar test" packages/shell/src/parser.ts packages/shell/src/router.ts
```

Both must show results.

### 7.2 Type check and build

```bash
bun run check
bun run build
```

Both must succeed with zero errors.

### 7.3 Full test suite

```bash
bun test
```

All tests must pass, including new Phase 36A gate tests.

### 7.4 Test all grammar commands with reference grammar

```bash
semantos grammar validate configs/extensions/propertyme-grammar.json
semantos grammar inspect configs/extensions/propertyme-grammar.json
semantos grammar diff configs/extensions/propertyme-grammar.json configs/extensions/propertyme-grammar.json
semantos grammar list
semantos grammar test configs/extensions/propertyme-grammar.json
```

All five commands must complete without error.

---

## Step 8: Errata Sprint

After all tests pass, run the errata protocol in a fresh session:

1. **Adversarial review** of schema definition — does it constrain enough? Are there gaps?
2. **Validator exhaustiveness check** — run validator on edge cases (empty objects, null values, type mismatches)
3. **Bridge completeness check** — verify every schema field maps to ExtensionConfig field
4. **Command integration check** — test each grammar command with realistic errors (malformed JSON, missing fields, circular refs)
5. **PropertyMe grammar check** — ensure it validates and bridges successfully
6. **Import path check** — verify all barrel exports and cross-package imports resolve
7. **Full codebase grep** — one final scan for any references to schema, validator, or bridge that might be missed
8. Write errata doc as `docs/prd/PHASE-36A-ERRATA.md`

---

## Completion Criteria

- [ ] ExtensionGrammarSchema type defined and exported
- [ ] validateExtensionGrammar() function exhaustive (checks all rules from PRD)
- [ ] grammarToExtensionConfig() bridge complete (every schema field maps to config)
- [ ] All five grammar shell commands implemented (validate, inspect, diff, list, test)
- [ ] Validator tests T5–T10 all pass
- [ ] Bridge tests T11–T13 all pass
- [ ] Shell command tests T14–T16 all pass
- [ ] Gate tests T1–T16 all pass
- [ ] Reference PropertyMe grammar validates and bridges successfully
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] `bun test` succeeds (all existing tests still pass)
- [ ] All five grammar commands work with real grammars
- [ ] All commits follow `phase-36a/D36A.N:` naming convention
- [ ] Branch is `phase-36a-extension-grammar-schema`
- [ ] Errata sprint complete with `docs/prd/PHASE-36A-ERRATA.md`

---

## Next Phase

Phase 36B builds the Extension Registry and Loader — the runtime that takes validated grammars, bridges them to ExtensionConfig, and registers them with the kernel. Phase 36C integrates the full ecosystem with tenant looms, making extensions discoverable and switchable at runtime.
