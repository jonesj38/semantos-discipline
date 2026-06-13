---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/.github/workflows/tla-verify.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.592927+00:00
---

# .github/workflows/tla-verify.yml

```yml
# Standalone TLA+ verification workflow.
#
# Runs on every push/PR that touches proofs/tla/ so the gate result is always
# current with the spec.  The full gate.yml already covers tla on every push;
# this workflow adds:
#   - a path filter so proof-only changes get a dedicated, focused result
#   - an explicit jar cache keyed on TLA2TOOLS_VERSION from the Makefile
#   - a per-spec timing summary posted to the GitHub Actions step summary
#
# Toolchain choice: tla2tools 1.8.0 — matches TLA2TOOLS_VERSION in Makefile.
# Java:             Temurin 17 — same as gate.yml.
# Model sizes:      all specs use N ≤ 3 constant sets (see each .cfg); the full
#                   make check run targets < 2 min on a standard Actions runner.

name: TLA+ Verify

on:
  push:
    branches: [main, "phase-*", "feat/**"]
    paths:
      - "proofs/tla/**"
  pull_request:
    branches: [main]
    paths:
      - "proofs/tla/**"

jobs:
  tlc:
    name: TLC model checker — all 20 specs
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: proofs/tla

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"

      # Cache tla2tools.jar between runs.  Key on the version string extracted
      # from the Makefile so a version bump automatically busts the cache.
      - name: Cache tla2tools.jar
        id: cache-tla
        uses: actions/cache@v4
        with:
          path: proofs/tla/.tools/tla2tools.jar
          key: tla2tools-${{ hashFiles('proofs/tla/Makefile') }}

      - name: Download tla2tools.jar (cache miss)
        if: steps.cache-tla.outputs.cache-hit != 'true'
        run: make setup

      # Smoke-test the jar even on a cache hit — guards against a corrupted
      # cache entry surviving across runner images.
      - name: Verify tla2tools.jar is runnable
        run: java -jar .tools/tla2tools.jar 2>&1 | grep -q "TLC2 Version"

      # Run TLC on every spec.  The Makefile's `check` target:
      #   - invokes TLC with -deadlock on each spec
      #   - tees output to <spec>.log
      #   - fails if any log lacks "Model checking completed. No error"
      #   - fails if any log shows "0 distinct states found" (vacuous model)
      - name: Run TLC on all specs
        run: |
          START=$(date +%s)
          make check
          END=$(date +%s)
          echo "TLC_ELAPSED=$((END - START))" >> "$GITHUB_ENV"

      # Belt-and-suspenders: re-check the vacuous-model condition explicitly so
      # the step name appears in the UI even when make check already caught it.
      - name: Assert no vacuous models
        run: |
          FAILED=0
          for log in *.log; do
            [ -f "$log" ] || continue
            if grep -q ", 0 distinct states found," "$log"; then
              echo "FAIL: vacuous model in $log (0 distinct states)"
              FAILED=1
            fi
          done
          if [ "$FAILED" -eq 1 ]; then exit 1; fi
          echo "All models non-vacuous."

      # Assert no invariant violations or deadlocks appear in any log.
      # TLC exits non-zero on these, but surface the message explicitly so the
      # failing spec name is visible in the UI.
      - name: Assert no invariant violations or deadlocks
        run: |
          FAILED=0
          for log in *.log; do
            [ -f "$log" ] || continue
            if grep -qE "Invariant .* is violated|Deadlock reached|Error:" "$log"; then
              echo "FAIL: error in $log:"
              grep -E "Invariant .* is violated|Deadlock reached|Error:" "$log"
              FAILED=1
            fi
          done
          if [ "$FAILED" -eq 1 ]; then exit 1; fi
          echo "No violations or deadlocks detected."

      # Post a markdown timing + state-count summary to the job summary page.
      - name: Post spec summary to GitHub Actions
        if: always()
        run: |
          {
            echo "### TLA+ Verification Summary"
            echo ""
            echo "Total elapsed: ${TLC_ELAPSED:-unknown}s"
            echo ""
            echo "| Spec | States found | Result |"
            echo "|------|-------------|--------|"
            for log in *.log; do
              [ -f "$log" ] || continue
              SPEC="${log%.log}"
              STATES=$(grep -oE "[0-9]+ distinct states found" "$log" | grep -oE "^[0-9]+" || echo "?")
              if grep -q "Model checking completed. No error" "$log"; then
                RESULT="passed"
              else
                RESULT="FAILED"
              fi
              echo "| $SPEC | $STATES | $RESULT |"
            done
          } >> "$GITHUB_STEP_SUMMARY"

```
