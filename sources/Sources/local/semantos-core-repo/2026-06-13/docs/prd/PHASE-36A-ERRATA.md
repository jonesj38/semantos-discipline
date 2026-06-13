---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-36A-ERRATA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.673589+00:00
---

# Phase 36A Errata — Extension Grammar JSON Schema

**Date**: 2026-04-12
**Status**: Complete
**Branch**: `claude/flamboyant-saha-814d` (worktree from `hackathon/semantos-swarm`)

---

## 1. Adversarial Schema Review

### Findings

The schema definition (`extension-grammar.ts`) covers the full PRD specification:
- 17 exported interfaces + 7 type aliases
- All sub-interfaces from the PRD are present: SourceDeclaration, SourceEntity, EntityMapping, FieldMapping, ObjectTypeDeclaration, CapabilityRequirement, TaxonomyExtension, MigrationRule

### Compute Expression Safety

The `FieldTransform.expression` field for `compute` type transforms is constrained by a regex that only permits:
- `source.<field>` references
- Numeric literals (integer and decimal)
- Arithmetic operators: `+`, `-`, `*`, `/`
- Whitespace

This prevents injection of arbitrary code (no function calls, no string operations, no property chaining beyond `source.<field>`). The regex is: `/^(\s*(source\.[a-zA-Z_][a-zA-Z0-9_]*|\d+(\.\d+)?)\s*([+\-*/]\s*(source\.[a-zA-Z_][a-zA-Z0-9_]*|\d+(\.\d+)?)\s*)*)$/`

**Tested adversarially**: `eval("malicious")`, `require("child_process")`, `process.exit(1)`, `source.foo.bar.baz` — all rejected.

### Schema Gaps Identified and Addressed

1. **FUNGIBLE linearity**: The PRD lists FUNGIBLE as a valid linearity, but ExtensionConfig only supports LINEAR, AFFINE, RELEVANT, DEBUG. The bridge maps FUNGIBLE → RELEVANT (closest semantic match). This is documented in the bridge code.

2. **Icon field**: ObjectTypeDeclaration in the grammar has no icon field. The bridge defaults all icons to 'box'. Extension authors can override via ExtensionManifest metadata. Phase 36E (Extension Manager UI) can extend this.

---

## 2. Validator Exhaustiveness

### Edge Cases Tested

| Input | Expected | Result |
|-------|----------|--------|
| `null` | Invalid | Pass |
| `{}` | Invalid (6+ errors) | Pass |
| `{ grammarId: "" }` | Invalid (empty string) | Pass |
| `{ grammarVersion: "abc" }` | Invalid (not semver) | Pass |
| `{ grammarVersion: "1.0.0-beta" }` | Valid (semver pre-release) | Pass |
| Unresolved sourceEntityId | Error with entity name | Pass |
| Unresolved targetObjectType | Error with type path | Pass |
| Unresolved sourceField in fieldMapping | Error with field name | Pass |
| initialPhase not in phases array | Error | Pass |
| enum type without enum values | Error | Pass |
| Invalid transform type | Error | Pass |
| Unsafe compute expression | Error | Pass |
| Safe compute expression | Valid | Pass |

### Validation Coverage

The validator checks:
- 7 top-level required fields
- grammarId format (dot-separated lowercase)
- grammarVersion semver format
- Author structure
- Source protocol, auth, pagination, entities, fields
- ObjectType structure including payloadSchema types
- EntityMapping reference resolution (3 levels: entity → type → field)
- Taxonomy extension structure
- Capability identifiers
- Migration rule structure
- FieldTransform types and compute expression safety

---

## 3. Bridge Completeness

### Field Mapping Coverage

| Grammar Field | Config Field | Status |
|---------------|-------------|--------|
| grammarId | id | Mapped |
| displayName | name | Mapped |
| objectTypes[].typePath | objectTypes[].category | Mapped |
| objectTypes[].typePath | objectTypes[].typeHash | SHA-256 |
| objectTypes[].displayName | objectTypes[].name | Mapped |
| objectTypes[].linearity | objectTypes[].linearity | Mapped |
| objectTypes[].payloadSchema | objectTypes[].fields | Mapped |
| objectTypes[].capabilities | objectTypes[].defaultCapabilities | Flattened |
| objectTypes[].phases | commercePhases | Union |
| objectTypes[].transitions | flows[] | Lifecycle flows |
| capabilities[] | capabilities[] | Mapped (string → numeric ID) |
| taxonomyExtensions[] | taxonomy.dimensions[] | Mapped |

### Unmapped Fields (By Design)

These grammar fields have no ExtensionConfig equivalent and are handled by the extraction pipeline (Phase 36B):
- `source` (API connection details)
- `entityMappings` (field-level transformation rules)
- `migrations` (version upgrade rules)
- `author` (provenance metadata)
- `extends` (grammar inheritance)

---

## 4. Shell Command Integration

### Commands Verified

| Command | Input | Expected Output | Status |
|---------|-------|-----------------|--------|
| `grammar validate <valid>` | PropertyMe grammar | Valid, 6 types, 6 entities | Pass |
| `grammar validate <invalid>` | Nonexistent file | Error message | Pass |
| `grammar inspect <valid>` | PropertyMe grammar | Full structured summary | Pass |
| `grammar diff <same> <same>` | Same file twice | hasChanges: false | Pass |
| `grammar list` | configs/extensions/ | Finds propertyme | Pass |
| `grammar test <valid>` | PropertyMe grammar | Success, config generated | Pass |
| `grammar` (no subcommand) | None | Usage message | Pass |
| `grammar bogus` | Invalid subcommand | Error message | Pass |

---

## 5. PropertyMe Grammar Check

The reference grammar at `configs/extensions/propertyme/grammar.json`:
- Contains 6 source entities (property, lease, tenant, maintenance_request, inspection, owner)
- Contains 6 object types (property.listing, property.lease, property.tenant, property.maintenance-request, property.inspection, property.owner)
- Contains 6 entity mappings (one per source entity → object type)
- Contains 4 capability requirements (network.outbound, storage.write, storage.read, identity.read)
- Contains taxonomy extensions under the `what` axis for property maintenance
- Contains a compute transform (bedrooms + bathrooms → totalRooms) that passes safety validation
- Passes `validateExtensionGrammar()` with zero errors
- Bridges to a valid ExtensionConfig with 6 object types, 64-char hex typeHashes, taxonomy, and flows

---

## 6. Import Path Verification

All cross-package imports resolve correctly:
- `grammar-config-bridge.ts` imports from `extension-grammar.ts` (same package) and `extensionConfig.ts` (loom package, relative path)
- `extension-grammar-validator.ts` imports types from `extension-grammar.ts`
- `extension-grammar-loader.ts` imports from `storage.ts` and `extension-grammar.ts`
- `commands/grammar.ts` imports from `extension-grammar-validator.ts` and `grammar-config-bridge.ts`
- `index.ts` barrel exports all grammar modules

---

## 7. Test Summary

| Test File | Tests | Pass | Fail |
|-----------|-------|------|------|
| phase36a-grammar-validator.test.ts | 20 | 20 | 0 |
| phase36a-grammar-bridge.test.ts | 12 | 12 | 0 |
| phase36a-shell-commands.test.ts | 11 | 11 | 0 |
| phase36a-extension-grammar.test.ts | 27 | 27 | 0 |
| **Total** | **70** | **70** | **0** |

---

## 8. Known Limitations (Deferred to Later Phases)

1. **No circular extends detection at runtime**: The validator doesn't check for circular `extends` chains because `resolveGrammarExtends()` takes already-loaded grammars. The loader in Phase 36B should track visited grammarIds during resolution.

2. **No field-level diff in `grammar diff`**: The diff command compares at entity/type/mapping granularity, not individual field changes. Field-level diff is deferred to Phase 36E (Extension Manager UI).

3. **Pre-existing merge conflicts**: The `hackathon/semantos-swarm` branch has merge conflict markers in anchor-related files (bsv-anchor-adapter.ts, stub-anchor-adapter.ts, anchor-scheduler.ts). These are unrelated to Phase 36A and pre-date this work.
