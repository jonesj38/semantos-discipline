---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/error-codes.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.367842+00:00
---

# runtime/shell/src/error-codes.ts

```ts
/**
 * Shell error codes — stable identifiers for programmatic error handling.
 *
 * Every error returned from shell commands should include one of these codes.
 * Codes are grouped by category for readability but are flat strings at runtime.
 */

// ── General ──────────────────────────────────────────────────
export const NO_CONFIG = 'NO_CONFIG';
export const NO_ACTIVE_HAT = 'NO_ACTIVE_HAT';
export const CAPABILITY_CHECK_FAILED = 'CAPABILITY_CHECK_FAILED';
export const UNKNOWN_VERB = 'UNKNOWN_VERB';

// ── Object operations ────────────────────────────────────────
export const MISSING_OBJECT_ID = 'MISSING_OBJECT_ID';
export const OBJECT_NOT_FOUND = 'OBJECT_NOT_FOUND';
export const MISSING_TYPE_PATH = 'MISSING_TYPE_PATH';
export const UNKNOWN_TYPE = 'UNKNOWN_TYPE';
export const NO_PATCH_FIELDS = 'NO_PATCH_FIELDS';

// ── Visibility transitions ───────────────────────────────────
export const INVALID_VISIBILITY_FLAG = 'INVALID_VISIBILITY_FLAG';
export const TRANSITION_FAILED = 'TRANSITION_FAILED';
export const PUBLISH_FAILED = 'PUBLISH_FAILED';
export const REVOKE_FAILED = 'REVOKE_FAILED';

// ── Transfer ─────────────────────────────────────────────────
export const MISSING_TO_FLAG = 'MISSING_TO_FLAG';

// ── Flow ─────────────────────────────────────────────────────
export const NO_GOVERNANCE_FLOW = 'NO_GOVERNANCE_FLOW';
export const INVALID_FLOW_USAGE = 'INVALID_FLOW_USAGE';
export const FLOW_NOT_FOUND = 'FLOW_NOT_FOUND';
export const MISSING_FLOW_CAPABILITIES = 'MISSING_FLOW_CAPABILITIES';
export const UNKNOWN_FLOW_SUBCOMMAND = 'UNKNOWN_FLOW_SUBCOMMAND';

// ── Identity ─────────────────────────────────────────────────
export const INVALID_REGISTER_USAGE = 'INVALID_REGISTER_USAGE';
export const INVALID_DERIVE_USAGE = 'INVALID_DERIVE_USAGE';
export const INVALID_RESOLVE_USAGE = 'INVALID_RESOLVE_USAGE';

// ── Eval / Compile / Bind ────────────────────────────────────
export const MISSING_EXPRESSION = 'MISSING_EXPRESSION';
export const PARSE_ERROR = 'PARSE_ERROR';
export const INVALID_CONSTRAINT = 'INVALID_CONSTRAINT';
export const COMPILE_ERROR = 'COMPILE_ERROR';
export const FIELD_VALIDATION_FAILED = 'FIELD_VALIDATION_FAILED';
export const MISSING_BIND_REFERENCE = 'MISSING_BIND_REFERENCE';
export const MISSING_BIND_TYPE = 'MISSING_BIND_TYPE';
export const TYPE_NOT_FOUND = 'TYPE_NOT_FOUND';
export const INVALID_POLICY_EXPRESSION = 'INVALID_POLICY_EXPRESSION';

// ── Grammar ──────────────────────────────────────────────────
export const INVALID_GRAMMAR_USAGE = 'INVALID_GRAMMAR_USAGE';
export const INVALID_GRAMMAR = 'INVALID_GRAMMAR';
export const GRAMMAR_LOAD_FAILED = 'GRAMMAR_LOAD_FAILED';
export const GRAMMAR_PARSE_FAILED = 'GRAMMAR_PARSE_FAILED';
export const FILE_NOT_FOUND = 'FILE_NOT_FOUND';
export const EXTENSIONS_DIR_SCAN_FAILED = 'EXTENSIONS_DIR_SCAN_FAILED';

// ── Infer ────────────────────────────────────────────────────
export const INVALID_INFER_USAGE = 'INVALID_INFER_USAGE';
export const INFERENCE_FAILED = 'INFERENCE_FAILED';
export const INFERRED_GRAMMAR_NOT_FOUND = 'INFERRED_GRAMMAR_NOT_FOUND';
export const JSON_PARSE_FAILED = 'JSON_PARSE_FAILED';
export const MISSING_REJECTION_REASON = 'MISSING_REJECTION_REASON';

// ── Extract ──────────────────────────────────────────────────
export const GRAMMAR_NOT_FOUND = 'GRAMMAR_NOT_FOUND';

// ── Extension ────────────────────────────────────────────────
export const INVALID_EXTENSION_USAGE = 'INVALID_EXTENSION_USAGE';
export const EXTENSION_NOT_FOUND = 'EXTENSION_NOT_FOUND';

// ── CDM ──────────────────────────────────────────────────────
export const INVALID_CDM_USAGE = 'INVALID_CDM_USAGE';
export const CDM_IMPORT_FAILED = 'CDM_IMPORT_FAILED';
export const MISSING_EVENT_TYPE = 'MISSING_EVENT_TYPE';
export const PRODUCT_NOT_FOUND = 'PRODUCT_NOT_FOUND';
export const EVENT_EXECUTION_FAILED = 'EVENT_EXECUTION_FAILED';
export const NOVATE_FAILED = 'NOVATE_FAILED';
export const NO_LIFECYCLE_EVENTS = 'NO_LIFECYCLE_EVENTS';
export const NETTING_FAILED = 'NETTING_FAILED';
export const FPML_NOT_SUPPORTED = 'FPML_NOT_SUPPORTED';

// ── Govern ───────────────────────────────────────────────────
export const INVALID_GOVERN_USAGE = 'INVALID_GOVERN_USAGE';
export const UNKNOWN_GOVERN_ACTION = 'UNKNOWN_GOVERN_ACTION';
export const MISSING_DISPUTE_TARGET = 'MISSING_DISPUTE_TARGET';

// ── Taxonomy ─────────────────────────────────────────────────
export const NO_EMBEDDING_CACHE = 'NO_EMBEDDING_CACHE';
export const COHERENCE_ANALYSIS_FAILED = 'COHERENCE_ANALYSIS_FAILED';
export const INVALID_TAXONOMY_USAGE = 'INVALID_TAXONOMY_USAGE';
export const EMBEDDING_FAILED = 'EMBEDDING_FAILED';
export const VALIDATION_FAILED = 'VALIDATION_FAILED';

// ── Settlement ───────────────────────────────────────────────
export const SETTLE_NOT_AVAILABLE = 'SETTLE_NOT_AVAILABLE';
export const MISSING_ORDER_ID = 'MISSING_ORDER_ID';

// ── Host Execution (Phase 38) ────────────────────────────────
export const HOST_EXEC_NOT_IMPLEMENTED = 'HOST_EXEC_NOT_IMPLEMENTED';
export const UNKNOWN_HANDLER = 'UNKNOWN_HANDLER';
export const INVALID_HANDLER_ARGS = 'INVALID_HANDLER_ARGS';
export const HANDLER_TIMEOUT = 'HANDLER_TIMEOUT';
export const HANDLER_CRASHED = 'HANDLER_CRASHED';
export const MISSING_HANDLER = 'MISSING_HANDLER';
export const NO_HAT_CERT = 'NO_HAT_CERT';

// ── Operation failed (generic catch blocks) ──────────────────
export const OPERATION_FAILED = 'OPERATION_FAILED';

```
