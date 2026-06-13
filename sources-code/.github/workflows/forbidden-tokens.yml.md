---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/.github/workflows/forbidden-tokens.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.593460+00:00
---

# .github/workflows/forbidden-tokens.yml

```yml
name: Forbidden-token lint

# CW Lift L14 — Layer 1 of the 4-layer prohibition stack (CI static scan).
# Enforces semantos's BSV-only + post-Genesis + no-AI-in-substrate invariants
# mechanically rather than via reviewer attention.
#
# Strategy: ship in REPORT MODE first (non-blocking). The lint reports on PRs
# so authors see if they introduced a forbidden token, but the check does NOT
# fail — that gives us telemetry on real-world false-positive rates without
# blocking merges while the surface settles. Once a few PRs flow through with
# no false positives, flip the script invocation to `--strict` to make this
# job blocking. The flip is a one-line change in this file (drop the
# `--no-color` flag and add `--strict`).
#
# Rule config: scripts/forbidden-tokens.config.json
# Script:      scripts/forbidden-tokens.mjs
# Self-tests:  scripts/__tests__/forbidden-tokens.test.ts

on:
  push:
    branches: [main, "phase-*"]
  pull_request:
    branches: [main]

jobs:
  forbidden-tokens:
    name: Forbidden-token static scan (report-mode)
    runs-on: ubuntu-latest
    # Non-blocking initially. Drop this once we flip --strict below; until
    # then a failure here should NOT prevent merge.
    continue-on-error: true
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v1
        with:
          bun-version: latest
      - name: Run forbidden-tokens lint (report mode)
        # Report mode: lists hits but always exits 0.
        # To flip to PR-blocking strict mode, change to:
        #   run: bun scripts/forbidden-tokens.mjs --strict --no-color
        # AND drop the `continue-on-error: true` above.
        run: bun scripts/forbidden-tokens.mjs --no-color
      - name: Self-test the lint
        # Self-test verifies the scanner itself works — uses bun:test against
        # the script's own test file. Should always pass.
        run: bun test scripts/__tests__/forbidden-tokens.test.ts

```
