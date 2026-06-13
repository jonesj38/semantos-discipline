---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-10-ERRATA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.682790+00:00
---

# Phase 10 Errata

Adversarial audit of Phase 10 — Taxonomy Governance + Reputation.

## BUG-1: insertNodeAtParent mutates TaxonomyNode tree in place

**Severity**: BUG
**File**: `packages/loom/src/services/ConfigStore.ts`, lines 392-405
**Details**: `insertNodeAtParent` called `node.children.push(newNode)`, mutating the shared taxonomy tree. This broke the immutability contract — the original config's taxonomy was modified when overlays were applied.
**Fix**: Refactored to return a new `TaxonomyNode[]` array (or null if parent not found). All ancestor nodes are rebuilt immutably. Callers updated to use the returned array.
**Status**: FIXED

## BUG-2: Context-scoped reputation filtering too broad

**Severity**: BUG
**File**: `packages/loom/src/services/ReputationComputer.ts`, lines 99-114
**Details**: `isPatchInContext` checked if a patch's facetId matched any facet on any scoped object. This meant ALL patches from a facet counted toward context-scoped reputation if that facet authored even one object in scope — defeating the purpose of context scoping.
**Fix**: Replaced with `filterPatchesByContext` which builds a set of patch IDs from scoped objects and only includes identity patches whose ID appears in that set. Context-scoped reputation now properly differs from global.
**Status**: FIXED

## BUG-3: objectFactory doesn't initialize TypeCoordinate

**Severity**: BUG
**File**: `packages/loom/src/state/objectFactory.ts`, lines 82-90
**Details**: `createObject()` never set `typeCoordinate` on new objects, leaving them unbound from the taxonomy. Objects created from type definitions with axis-compatible categories (starting with `what.`, `how.`, or `why.`) had no initial coordinate.
**Fix**: Added category-to-coordinate derivation: if `typeDef.category` starts with an axis prefix, the initial `typeCoordinate` is populated from it.
**Status**: FIXED

## INC-1: TaxonomyBrowser renders empty state when seed fails to load

**Severity**: INCONSISTENCY
**File**: `packages/loom/src/sidebar/TaxonomyBrowser.tsx`, lines 134-150
**Details**: If the taxonomy seed fails to load, `axisDims.size === 0` and the tab bar doesn't render. However, non-axis "extra" dimensions still render, creating a confusing partial taxonomy display.
**Status**: NOTED — acceptable for development; seed load failure is an edge case. The component already returns null if `!config?.taxonomy`.

## TD-1: No type safety on governance patch structure

**Severity**: TECH_DEBT
**File**: `packages/loom/src/canvas/ConversationPanel.tsx`, lines 99-115
**Details**: The challenge-classification flow stores `proposedCoordinate` in an `evidence_merge` patch delta, and `LoomStore.resolveDisputeReclassification()` reads it back from `evidencePatch.delta.proposedCoordinate`. The structure is correct but undocumented — another flow creating misclassification disputes without this structure would fail silently.
**Status**: NOTED — acceptable for now. Adding a typed governance patch interface would add complexity for little near-term benefit.

## Summary

| ID | Category | Severity | Status |
|----|----------|----------|--------|
| BUG-1 | Mutation in insertNodeAtParent | High | FIXED |
| BUG-2 | Overly broad context reputation filter | High | FIXED |
| BUG-3 | Missing TypeCoordinate in objectFactory | Medium | FIXED |
| INC-1 | Empty taxonomy when seed fails | Low | NOTED |
| TD-1 | Untyped governance patch structure | Low | NOTED |
