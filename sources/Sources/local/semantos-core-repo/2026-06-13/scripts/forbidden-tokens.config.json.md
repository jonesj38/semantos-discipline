---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/forbidden-tokens.config.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.319759+00:00
---

# scripts/forbidden-tokens.config.json

```json
{
  "comment": [
    "Forbidden-token CI lint rules (CW Lift L14).",
    "Layer 1 of the 4-layer prohibition stack — semantos's BSV-only +",
    "post-Genesis + no-AI-in-substrate invariants made mechanical.",
    "",
    "Rule severity:",
    "  - 'error' — flagged in --strict mode; will fail CI when wired",
    "  - 'warn'  — flagged in report mode; informational",
    "",
    "Adding a rule: add an entry under `rules`. The scope.include/exclude",
    "patterns use a minimal glob (** for path-wildcard, * for segment-",
    "wildcard, trailing / for directory).",
    "",
    "Adding a whitelist entry: extend `scope.exclude` on the relevant",
    "rule. Prefer per-rule excludes over globalIgnores so the scope of",
    "the exception is explicit.",
    "",
    "Self-test: this file pinpoints its own mention paths via scope.exclude.",
    "Anchor docs (cw-lift-matrix.yml, CW-LIFT-ROADMAP.md, cross-repo-",
    "path-dep-pattern.md) intentionally discuss prohibited tokens by name;",
    "they are excluded per-rule."
  ],
  "globalIgnores": [
    "node_modules/",
    "dist/",
    "build/",
    ".pnpm-store/",
    "worktrees/",
    "archive/",
    "coverage/",
    "audit.sqlite",
    "cell-store.sqlite",
    ".git/"
  ],
  "rules": [
    {
      "id": "op-checklocktimeverify",
      "pattern": "op_checklocktimeverify",
      "severity": "error",
      "rationale": "BSV post-Genesis: OP_CHECKLOCKTIMEVERIFY is a no-op (`bsv_no_cltv_use_nlocktime`). Use tx-level nLockTime instead.",
      "scope": {
        "exclude": [
          "docs/canon/cw-lift-matrix.yml",
          "docs/prd/CW-LIFT-ROADMAP.md",
          "docs/canon/cross-repo-path-dep-pattern.md",
          "scripts/forbidden-tokens.config.json",
          "scripts/forbidden-tokens.mjs",
          "core/cell-ops/src/opcodes.ts",
          "core/protocol-types/src/mnca/forwarding-payment.ts"
        ]
      },
      "_excludeRationale": "cell-ops/opcodes.ts: defines the constant 0xb1 so a script-validator can identify+REJECT scripts that contain it. mnca/forwarding-payment.ts: doc-comment line 11 explains the BSV-no-CLTV/CSV invariant. Both are documentation/identification, not use."
    },
    {
      "id": "op-checksequenceverify",
      "pattern": "op_checksequenceverify",
      "severity": "error",
      "rationale": "BSV post-Genesis: OP_CHECKSEQUENCEVERIFY is a no-op. Use tx-level nSequence instead.",
      "scope": {
        "exclude": [
          "docs/canon/cw-lift-matrix.yml",
          "docs/prd/CW-LIFT-ROADMAP.md",
          "docs/canon/cross-repo-path-dep-pattern.md",
          "scripts/forbidden-tokens.config.json",
          "scripts/forbidden-tokens.mjs",
          "core/cell-ops/src/opcodes.ts",
          "core/protocol-types/src/mnca/forwarding-payment.ts"
        ]
      },
      "_excludeRationale": "same as op-checklocktimeverify — constant definition + documentation, not script use."
    },
    {
      "id": "blockstream",
      "pattern": "blockstream",
      "severity": "warn",
      "rationale": "BSV-only: avoid Blockstream-branded tooling / library references in source code.",
      "scope": {
        "exclude": [
          "docs/canon/cw-lift-matrix.yml",
          "docs/prd/CW-LIFT-ROADMAP.md",
          "docs/canon/cross-repo-path-dep-pattern.md",
          "scripts/forbidden-tokens.config.json"
        ]
      }
    },
    {
      "id": "rust-bitcoin",
      "pattern": "rust-bitcoin",
      "severity": "warn",
      "rationale": "BSV-only: avoid rust-bitcoin (BTC-shaped) crate references. Use BSV-native crypto.",
      "scope": {
        "exclude": [
          "docs/canon/cw-lift-matrix.yml",
          "docs/prd/CW-LIFT-ROADMAP.md",
          "scripts/forbidden-tokens.config.json"
        ]
      }
    },
    {
      "id": "taproot",
      "pattern": "taproot",
      "severity": "warn",
      "rationale": "BSV post-Genesis does not implement Taproot. Don't write code that assumes it.",
      "scope": {
        "exclude": [
          "docs/canon/cw-lift-matrix.yml",
          "docs/prd/CW-LIFT-ROADMAP.md",
          "scripts/forbidden-tokens.config.json"
        ]
      }
    },
    {
      "id": "segwit",
      "pattern": "segwit",
      "severity": "warn",
      "rationale": "BSV post-Genesis does not implement SegWit. Don't write code that assumes it.",
      "scope": {
        "exclude": [
          "docs/canon/cw-lift-matrix.yml",
          "docs/prd/CW-LIFT-ROADMAP.md",
          "scripts/forbidden-tokens.config.json",
          "core/cell-engine/src/host_assemble_tx.zig",
          "core/cell-engine/src/sighash.zig"
        ]
      },
      "_excludeRationale": "These files document the BSV-Chronicle 'reinstates pre-SegWit Satoshi algorithm' invariant. They identify what BSV is NOT (SegWit-free), which is the right framing — not adopting SegWit."
    },
    {
      "id": "openai-in-substrate",
      "pattern": "openai",
      "severity": "error",
      "rationale": "Per `semantos_no_ai_in_substrate`: no LLM/AI vendor SDKs inside core/. Intelligence stays at the edges (intent parser, optional top-layer interaction model).",
      "scope": {
        "include": ["core/**"],
        "exclude": []
      }
    },
    {
      "id": "anthropic-in-substrate",
      "pattern": "anthropic",
      "severity": "error",
      "rationale": "Per `semantos_no_ai_in_substrate`: no LLM/AI vendor SDKs inside core/. Intelligence stays at the edges.",
      "scope": {
        "include": ["core/**"],
        "exclude": [
          "core/conversation-graph/src/pipeline.ts"
        ]
      },
      "_excludeRationale": "pipeline.ts doc-comment (line 21) explicitly notes that the GENERIC core pipeline does NOT use @anthropic-ai/sdk — the mention is metadata about what's intentionally absent, not an import or call. The rule correctly caught it; we evaluated context and excluded."
    }
  ]
}

```
