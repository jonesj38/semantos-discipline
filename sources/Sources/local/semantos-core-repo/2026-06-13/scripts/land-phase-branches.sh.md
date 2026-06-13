---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/land-phase-branches.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.319490+00:00
---

# scripts/land-phase-branches.sh

```sh
#!/usr/bin/env bash
# land-phase-branches.sh — push unmerged phase branches and create PRs
#
# Pushes each phase branch to origin and opens a GitHub PR via `gh`.
# Default mode is --dry-run. Pass --execute to actually push + create PRs.
#
# Usage:
#   ./scripts/land-phase-branches.sh                # dry run — shows the plan
#   ./scripts/land-phase-branches.sh --execute      # push all + create PRs
#   ./scripts/land-phase-branches.sh --execute 3    # push only PR #3
#
# Prerequisites:
#   - `gh` CLI authenticated (gh auth status)
#   - git fetch origin main already done (script does it for you)

set -euo pipefail

# ── Mode flags ───────────────────────────────────────────────────────────────

DRY_RUN=1
ONLY_INDEX=""
for arg in "$@"; do
  case "$arg" in
    --execute) DRY_RUN=0 ;;
    --dry-run) DRY_RUN=1 ;;
    --help|-h)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    [0-9]|[0-9][0-9])
      ONLY_INDEX="$arg"
      ;;
    *)
      echo "Unknown arg: $arg" >&2
      exit 2
      ;;
  esac
done

# ── Sanity ───────────────────────────────────────────────────────────────────

if [[ ! -d .git ]] || [[ ! -f package.json ]]; then
  echo "ERROR: run from semantos-core repo root" >&2
  exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

# ── Pretty printing ─────────────────────────────────────────────────────────

cyan()   { printf '\033[36m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }
hr()     { printf '%.0s─' {1..70}; printf '\n'; }

# ── Clean stale locks (same as prepare-pr.sh Phase 0.5) ─────────────────────

STALE=$(find .git -name '*.lock.stale-*' 2>/dev/null || true)
[[ -d .git/__stale_keen__ ]] && STALE="${STALE}
__stale_keen__"
if [[ -n "$STALE" ]]; then
  find .git -name '*.lock.stale-*' -delete 2>/dev/null || true
  rm -rf .git/__stale_keen__ 2>/dev/null || true
  find .git -maxdepth 4 -name '*.lock' -mmin +10 -delete 2>/dev/null || true
  green "✓ Cleaned stale lock files"
fi

# ── Fetch main ───────────────────────────────────────────────────────────────

bold "Fetching origin/main..."
if [[ $DRY_RUN == 1 ]]; then
  yellow "[dry-run] would: git fetch origin main --tags"
else
  git fetch origin main --tags
  green "✓ origin/main at $(git rev-parse origin/main)"
fi
echo

# ── PR definitions ───────────────────────────────────────────────────────────
#
# Format: BRANCH|TITLE|BODY
#
# Order: roughly chronological by phase number. No strict dependency —
# all branch off main independently. If conflicts arise on later merges,
# resolve in the PR.
#
# SKIPPED:
#   phase-25a-storage-adapter — fully contained in phase-24 (merged into it)
#   feat/games-poker-chess    — overlaps with landed esp32+games (8bc5452)
#                               and chess/poker being staged via prepare-pr.sh
#   wip/session-safety-net    — mega-branch, handle residual via prepare-pr.sh

BRANCHES=(
  "phase-12-implementation-bridge|Phase 12: implementation bridge, errata + compliance matrix|9 commits: reproducible WASM build, compliance coverage matrix, errata audit, gate tests"
  "phase-13-intent-taxonomy|Phase 13: hierarchical intent taxonomy + flow registry|7 commits: intent classifier, FlowRegistry, taxonomy browser UI, full test suite (T1-T24)"
  "phase-18-metering-control-plane|Phase 18: metering control plane — channels as governed objects|1 commit: D18.1-D18.9, T1-T12 metering deliverables"
  "phase-24-embedding-classification|Phase 24+25a: embedding classification + storage adapter|19 commits: includes phase-25a storage adapter merge, classifier enhancements, adapter migrations, gate tests"
  "claude/jolly-chaum|Phase 25c: semantic filesystem + VFS|4 commits: SemanticFS class, VFS delegates, CLI commands (ls/cat/stat/history/find), gate tests (T1-T16)"
  "phase-29-scada|Phase 29: SCADA telemetry + protocol adapters|11 commits: OPC UA/Modbus/DNP3/MQTT adapters, historian, alarms, handover, shell integration, demo script, errata sprint"
  "phase-30f2-cas-storage|Phase 30f2: content-addressable storage + Merkle journal|8 commits: CAS engine, namespace layer, append-only journal, Merkle tree anchoring, linearity per content hash"
  "claude/thirsty-babbage|Phase 30a: C ABI tx primitives + SPV verification|12 commits: tx_create, tx_input_add, tx_verify_spv with BUMP merkle, tx_chain_verify FSM, tx_stream_accept, 25 integration tests"
  "claude/wonderful-jennings|Phase 30g: Flutter/Dart integration + chess stakes|9 commits: FFI adapters (storage/identity/anchor/network), callback bridge, Flutter demo app, chess-stakes game + tests"
)

# ── Print plan ───────────────────────────────────────────────────────────────

bold "land-phase-branches.sh — $(if [[ $DRY_RUN == 1 ]]; then echo 'DRY RUN'; else echo 'EXECUTE'; fi)"
hr
echo
bold "PRs to create (${#BRANCHES[@]}):"
echo

IDX=1
for entry in "${BRANCHES[@]}"; do
  IFS='|' read -r branch title body <<< "$entry"
  ahead=$(git rev-list --count origin/main.."$branch" 2>/dev/null || echo "?")
  if [[ -n "$ONLY_INDEX" ]] && [[ "$IDX" != "$ONLY_INDEX" ]]; then
    printf "  \033[90m%2d. [skip] %-45s (%s ahead)\033[0m\n" "$IDX" "$branch" "$ahead"
  else
    printf "  %2d. %-45s (%s ahead)\n" "$IDX" "$branch" "$ahead"
  fi
  IDX=$((IDX + 1))
done

echo
bold "Skipped (already handled):"
yellow "  • phase-25a-storage-adapter  — fully inside phase-24"
yellow "  • feat/games-poker-chess     — overlaps with landed 8bc5452 + prepare-pr.sh"
yellow "  • wip/session-safety-net     — mega-branch, residual handled separately"
hr
echo

if [[ $DRY_RUN == 1 ]]; then
  bold "DRY RUN — no branches pushed, no PRs created."
  cyan "Re-run with --execute to push all and create PRs."
  cyan "Re-run with --execute N to push/create only PR #N."
  exit 0
fi

# ── Push + create PRs ───────────────────────────────────────────────────────

CREATED=0
FAILED=0

IDX=1
for entry in "${BRANCHES[@]}"; do
  IFS='|' read -r branch title body <<< "$entry"

  if [[ -n "$ONLY_INDEX" ]] && [[ "$IDX" != "$ONLY_INDEX" ]]; then
    IDX=$((IDX + 1))
    continue
  fi

  echo
  bold "[$IDX/${#BRANCHES[@]}] $branch"

  # Check if branch exists
  if ! git rev-parse --verify "$branch" >/dev/null 2>&1; then
    red "  ✗ Branch '$branch' not found — skipping"
    FAILED=$((FAILED + 1))
    IDX=$((IDX + 1))
    continue
  fi

  # Check commits ahead
  ahead=$(git rev-list --count origin/main.."$branch" 2>/dev/null || echo "0")
  if [[ "$ahead" == "0" ]]; then
    yellow "  Already merged into main — skipping"
    IDX=$((IDX + 1))
    continue
  fi

  cyan "  $ahead commit(s) ahead of main"

  # Push
  echo "  Pushing to origin..."
  if git push -u origin "$branch" 2>&1 | sed 's/^/  /'; then
    green "  ✓ Pushed"
  else
    red "  ✗ Push failed — skipping PR creation"
    FAILED=$((FAILED + 1))
    IDX=$((IDX + 1))
    continue
  fi

  # Check if PR already exists
  EXISTING_PR=$(gh pr list --head "$branch" --state open --json number --jq '.[0].number' 2>/dev/null || true)
  if [[ -n "$EXISTING_PR" ]]; then
    yellow "  PR #$EXISTING_PR already exists for this branch — skipping creation"
    IDX=$((IDX + 1))
    continue
  fi

  # Create PR
  echo "  Creating PR..."
  PR_BODY="## Summary
${body}

## Notes
- Auto-generated PR for unmerged phase work
- Branch has been independently developed and not rebased onto current main
- Merge conflicts are expected — resolve during review
- Build artifacts (.d.ts, .js.map, zig-out/, proof-artifacts/) should NOT be committed

## Test plan
- [ ] Review diff for unintended changes
- [ ] Resolve any merge conflicts
- [ ] Run \`bun run check\` (typecheck)
- [ ] Run relevant gate tests
- [ ] Verify no build artifacts slipped in"

  if PR_URL=$(gh pr create --base main --head "$branch" \
    --title "$title" \
    --body "$PR_BODY" 2>&1); then
    green "  ✓ $PR_URL"
    CREATED=$((CREATED + 1))
  else
    red "  ✗ PR creation failed:"
    echo "$PR_URL" | sed 's/^/    /'
    FAILED=$((FAILED + 1))
  fi

  IDX=$((IDX + 1))
done

echo
hr
bold "Summary: $CREATED PR(s) created, $FAILED failed"
if (( CREATED > 0 )); then
  echo
  cyan "Next steps:"
  cyan "  1. Review each PR on GitHub"
  cyan "  2. Merge in order (phase-12 → 13 → 18 → 24 → 25c → 29 → 30f2 → 30a → 30g)"
  cyan "     Resolve conflicts as they come — later PRs may conflict with earlier ones."
  cyan "  3. After all phase PRs land, run prepare-pr.sh for the remaining follow-up work."
  cyan "  4. Finally, diff wip/session-safety-net against the updated main to catch anything missed."
fi

```
