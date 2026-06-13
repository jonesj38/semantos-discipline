---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/prepare-poker-pr.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.321850+00:00
---

# scripts/prepare-poker-pr.sh

```sh
#!/usr/bin/env bash
# prepare-poker-pr.sh — surgical PR staging for the 2PDA poker hackathon work
#
# What this does (and doesn't do):
#
#   1. Tags your current HEAD as a safety snapshot so nothing can be lost.
#   2. Fetches origin/main fresh.
#   3. Creates an isolated git worktree off origin/main at ../semantos-core-poker-pr.
#   4. Copies the poker file-set from your current worktree into the new worktree.
#   5. Leaves the new worktree UNCOMMITTED so you can `git diff`, resolve any
#      conflicts (anchor.ts / anchor-scheduler.ts have evolved on main), review,
#      and commit manually.
#
# It does NOT:
#   - Push anything to origin
#   - Create PRs
#   - Commit automatically in --execute mode (it stages, you commit)
#   - Touch your current worktree's index or working tree (except for the tag)
#   - Delete or reset anything
#
# Default mode is --dry-run. Pass --execute to actually create the worktree.
# Pass --audit to also write a full categorization of your 452-file delta.

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────

MAIN_BRANCH="origin/main"
NEW_BRANCH_NAME="feat/poker-2pda-hackathon"
SNAPSHOT_TAG_PREFIX="safety/pre-pr-snapshot"
WORKTREE_SUFFIX="-poker-pr"  # appended to repo dir name
AUDIT_FILE="/tmp/poker-pr-audit.txt"

# ── Mode flags ────────────────────────────────────────────────────────────────

DRY_RUN=1
DO_AUDIT=0
for arg in "$@"; do
  case "$arg" in
    --execute) DRY_RUN=0 ;;
    --dry-run) DRY_RUN=1 ;;  # explicit — same as default
    --audit)   DO_AUDIT=1 ;;
    --help|-h)
      sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# ── Sanity checks ─────────────────────────────────────────────────────────────

# Must run from repo root
if [[ ! -d .git ]] || [[ ! -f package.json ]]; then
  echo "ERROR: run this from the semantos-core repo root" >&2
  exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

# Derive the new worktree path (sibling of repo)
REPO_NAME=$(basename "$REPO_ROOT")
NEW_WORKTREE="$(dirname "$REPO_ROOT")/${REPO_NAME}${WORKTREE_SUFFIX}"

# Refuse to run if the new worktree already exists (don't clobber)
if [[ -e "$NEW_WORKTREE" ]]; then
  echo "ERROR: $NEW_WORKTREE already exists. Remove it (git worktree remove --force $NEW_WORKTREE) or rename it before running." >&2
  exit 1
fi

# Timestamp for the safety tag
TS=$(date -u +%Y%m%dT%H%M%SZ)
SNAPSHOT_TAG="${SNAPSHOT_TAG_PREFIX}-${TS}"

# ── The POKER file set (high-confidence hackathon PR contents) ────────────────
#
# Categorized by our audit of the 452-file delta between merge-base
# (2b5b5d0 = last common ancestor with main) and HEAD.
#
# POKER_FILES_NEW → files added/modified in our branch that main doesn't have.
# POKER_FILES_MODIFIED → files that exist on main AND on our branch, both sides
#   have evolved, and our poker work depends on the state from our branch.
#   These will produce merge conflicts in the new worktree — RESOLVE MANUALLY.
# POKER_FILES_KERNEL → Zig kernel + constants changes required by the 2PDA flow.
# POKER_FILES_SCRIPTS → top-level arena/dashboard/runner scripts.

POKER_FILES_NEW=(
  # Poker agent package (all new)
  "packages/poker-agent/package.json"
  "packages/poker-agent/src/agent-discovery.ts"
  "packages/poker-agent/src/agent-runtime.ts"
  "packages/poker-agent/src/direct-broadcast-engine.ts"
  "packages/poker-agent/src/direct-poker-state-machine.ts"
  "packages/poker-agent/src/game-loop.ts"
  "packages/poker-agent/src/game-state-db.ts"
  "packages/poker-agent/src/index.ts"
  "packages/poker-agent/src/p2p-agent-runner.ts"
  "packages/poker-agent/src/payment-channel.ts"
  "packages/poker-agent/src/poker-message-transport.ts"
  "packages/poker-agent/src/poker-state-machine.ts"

  # Protocol-types additions (new in our branch)
  "packages/protocol-types/src/transition-validator.ts"
  "packages/protocol-types/src/wallet-client.ts"
  "packages/protocol-types/src/agent-context.ts"
  "packages/protocol-types/src/adapters/bsv-anchor-adapter.ts"
  "packages/protocol-types/src/adapters/stub-anchor-adapter.ts"

  # Gate test for transition-validator (new)
  "packages/__tests__/transition-validator.test.ts"
)

POKER_FILES_MODIFIED=(
  # ⚠ Main has evolved these independently — expect merge conflicts.
  # Our versions depend on APIs that our transition-validator and poker-agent use.
  "packages/protocol-types/src/anchor.ts"
  "packages/protocol-types/src/anchor-scheduler.ts"
  "packages/protocol-types/src/cell-token.ts"
  "packages/protocol-types/src/index.ts"
)

POKER_FILES_KERNEL=(
  # Zig kernel changes that enable last_cell_linearity caching.
  # Without these, kernel_get_type_class() returns UNCLASSIFIED after
  # PushDrop's OP_2DROP empties the stack, and the poker validator breaks.
  # NOTE: build.zig is NOT in this list — all its changes are cellsh-related
  # and belong to the feat/cellsh-native-debug-shell PR. The kernel wasm still
  # builds from pda.zig + main.zig without any build.zig edits.
  "packages/cell-engine/src/main.zig"
  "packages/cell-engine/src/pda.zig"

  # New opcodes (OP_CHECKDOMAINFLAG, OP_CHECKTYPEHASH, OP_DEREF_POINTER)
  # used by our cell scripts. Defined in constants.json + mirrored in opcodes.ts.
  "packages/constants/constants.json"
  "packages/cell-ops/src/opcodes.ts"
)

POKER_FILES_SCRIPTS=(
  "scripts/poker-arena.ts"
  "scripts/poker-dashboard.html"
  "scripts/poker-match.ts"
  "scripts/poker-p2p.ts"
  "scripts/poker-speed-test.ts"
)

# All poker files combined (used by the copy phase)
ALL_POKER_FILES=(
  "${POKER_FILES_NEW[@]}"
  "${POKER_FILES_MODIFIED[@]}"
  "${POKER_FILES_KERNEL[@]}"
  "${POKER_FILES_SCRIPTS[@]}"
)

# ── Pretty printing helpers ───────────────────────────────────────────────────

cyan()   { printf '\033[36m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

hr() { printf '%.0s─' {1..70}; printf '\n'; }

# ── Phase 0: Print the plan ───────────────────────────────────────────────────

bold "prepare-poker-pr.sh — $(if [[ $DRY_RUN == 1 ]]; then echo 'DRY RUN'; else echo 'EXECUTE'; fi)"
hr
cyan "Repo root:     $REPO_ROOT"
cyan "Current HEAD:  $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD))"
cyan "Target branch: $MAIN_BRANCH"
cyan "Safety tag:    $SNAPSHOT_TAG"
cyan "New worktree:  $NEW_WORKTREE"
cyan "New branch:    $NEW_BRANCH_NAME"
cyan "Poker files:   ${#ALL_POKER_FILES[@]} (${#POKER_FILES_NEW[@]} new, ${#POKER_FILES_MODIFIED[@]} conflict-prone, ${#POKER_FILES_KERNEL[@]} kernel, ${#POKER_FILES_SCRIPTS[@]} scripts)"
hr

# ── Phase 1: Verify files actually exist in the current worktree ─────────────

bold "Phase 1: Verifying poker files exist in the current worktree"

MISSING=()
for f in "${ALL_POKER_FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    MISSING+=("$f")
  fi
done

if (( ${#MISSING[@]} > 0 )); then
  red "MISSING ${#MISSING[@]} file(s) from the current worktree:"
  for f in "${MISSING[@]}"; do echo "  ✗ $f"; done
  echo
  yellow "These files are in the script's manifest but not on disk."
  yellow "Either the manifest is wrong or your worktree is inconsistent."
  exit 1
else
  green "✓ All ${#ALL_POKER_FILES[@]} poker files present"
fi
echo

# ── Phase 2: Safety tag (ALWAYS, even in dry-run) ─────────────────────────────

bold "Phase 2: Safety tag"

if git rev-parse "$SNAPSHOT_TAG" >/dev/null 2>&1; then
  yellow "Tag $SNAPSHOT_TAG already exists — skipping"
else
  if [[ $DRY_RUN == 1 ]]; then
    yellow "[dry-run] would: git tag -a $SNAPSHOT_TAG -m 'safety snapshot before poker PR staging'"
  else
    git tag -a "$SNAPSHOT_TAG" -m "safety snapshot before poker PR staging" HEAD
    green "✓ Tagged HEAD as $SNAPSHOT_TAG (annotated, local only)"
    yellow "  To preserve across a reinstall, push it: git push origin $SNAPSHOT_TAG"
  fi
fi
echo

# ── Phase 3: Fetch origin/main ────────────────────────────────────────────────

bold "Phase 3: Fetching $MAIN_BRANCH"

if [[ $DRY_RUN == 1 ]]; then
  yellow "[dry-run] would: git fetch origin main --tags"
else
  git fetch origin main --tags
  green "✓ origin/main at $(git rev-parse origin/main)"
fi
echo

# ── Phase 4: (Optional) Audit the full 452-file delta ───────────────────────

if (( DO_AUDIT == 1 )); then
  bold "Phase 4: Writing full delta audit → $AUDIT_FILE"

  MERGE_BASE=$(git merge-base HEAD origin/main 2>/dev/null || echo "")
  if [[ -z "$MERGE_BASE" ]]; then
    red "Cannot compute merge-base with origin/main — skipping audit"
  else
    {
      echo "# Poker PR delta audit"
      echo "# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "# HEAD:       $(git rev-parse HEAD)"
      echo "# main:       $(git rev-parse origin/main 2>/dev/null || echo '?')"
      echo "# merge-base: $MERGE_BASE"
      echo "#"
      echo "# Categories:"
      echo "#   POKER      = part of this PR (ALL_POKER_FILES in this script)"
      echo "#   KERNEL     = part of this PR (Zig + constants)"
      echo "#   ARTIFACT   = build artifact, NEVER commit"
      echo "#   ORTHOGONAL = separate PR — do not lose, but not this PR"
      echo "#"
      echo

      # Build a regex of poker files for categorization
      POKER_REGEX=$(printf "%s\n" "${ALL_POKER_FILES[@]}" | sed 's/[]\/$*.^|[]/\\&/g' | paste -sd'|' -)

      git diff --name-status "$MERGE_BASE..HEAD" | while IFS=$'\t' read -r status path; do
        cat="ORTHOGONAL"
        case "$path" in
          *.d.ts|*.d.ts.map|*.js|*.js.map) cat="ARTIFACT" ;;
          packages/cell-engine/zig-out/*)  cat="ARTIFACT" ;;
          packages/cell-engine/proof-artifacts/*) cat="ARTIFACT" ;;
          packages/shell/tsconfig.tsbuildinfo) cat="ARTIFACT" ;;
          proofs/lean/.lake/*)             cat="ARTIFACT" ;;
          *.tsbuildinfo)                   cat="ARTIFACT" ;;
        esac
        if [[ "$cat" == "ORTHOGONAL" ]] && echo "$path" | grep -qE "^(${POKER_REGEX})$"; then
          cat="POKER"
        fi
        printf "%-11s %s %s\n" "$cat" "$status" "$path"
      done | sort -k1,1 -k3,3
    } > "$AUDIT_FILE"
    green "✓ Audit written to $AUDIT_FILE"
    cyan  "  Review it: less $AUDIT_FILE"
    cyan  "  Breakdown:"
    awk '{print $1}' "$AUDIT_FILE" | grep -v '^#' | grep -v '^$' | sort | uniq -c | sed 's/^/    /'
  fi
  echo
fi

# ── Phase 5: Create isolated worktree off origin/main ───────────────────────

bold "Phase 5: Create worktree at $NEW_WORKTREE"

if [[ $DRY_RUN == 1 ]]; then
  yellow "[dry-run] would: git worktree add -b $NEW_BRANCH_NAME $NEW_WORKTREE $MAIN_BRANCH"
  yellow "[dry-run] would: copy ${#ALL_POKER_FILES[@]} poker files from $REPO_ROOT into $NEW_WORKTREE"
  yellow "[dry-run] would: cd $NEW_WORKTREE && git status"
  echo
  bold "DRY RUN COMPLETE"
  cyan "Re-run with --execute to actually perform the above steps."
  cyan "Re-run with --audit to also write the full 452-file categorization to $AUDIT_FILE."
  exit 0
fi

git worktree add -b "$NEW_BRANCH_NAME" "$NEW_WORKTREE" "$MAIN_BRANCH"
green "✓ Worktree created at $NEW_WORKTREE (branch $NEW_BRANCH_NAME off $MAIN_BRANCH)"
echo

# ── Phase 6: Copy poker files into the new worktree ────────────────────────

bold "Phase 6: Copying poker files"

COPIED=0
OVERWROTE=0
CREATED_DIRS=()

for f in "${ALL_POKER_FILES[@]}"; do
  dest="$NEW_WORKTREE/$f"
  dest_dir=$(dirname "$dest")
  if [[ ! -d "$dest_dir" ]]; then
    mkdir -p "$dest_dir"
    CREATED_DIRS+=("$dest_dir")
  fi
  if [[ -f "$dest" ]]; then
    OVERWROTE=$((OVERWROTE + 1))
  fi
  cp -p "$REPO_ROOT/$f" "$dest"
  COPIED=$((COPIED + 1))
done

green "✓ Copied $COPIED files ($OVERWROTE overwrote existing files in main's tree)"
if (( OVERWROTE > 0 )); then
  yellow "  The $OVERWROTE overwritten files are candidates for merge conflicts:"
  for f in "${POKER_FILES_MODIFIED[@]}"; do
    echo "    ⚠ $f"
  done
  yellow "  → cd into the new worktree and run 'git diff' on each to verify intent."
fi
echo

# ── Phase 7: Show git status in the new worktree ───────────────────────────

bold "Phase 7: git status in the new worktree"
hr
(cd "$NEW_WORKTREE" && git status --short)
hr
echo

# ── Phase 8: Next steps ────────────────────────────────────────────────────

bold "Done. Next steps (manual, for your review):"
cat <<EOF

  cd "$NEW_WORKTREE"

  # 1. Review what changed vs main
  git diff --stat
  git diff packages/protocol-types/src/anchor.ts              # likely conflict
  git diff packages/protocol-types/src/anchor-scheduler.ts    # likely conflict
  git diff packages/protocol-types/src/index.ts               # barrel exports
  git diff packages/protocol-types/src/cell-token.ts          # small delta

  # 2. Typecheck and test before committing
  bun install                          # pull workspace deps
  bun run check                        # or: ./node_modules/.bin/tsc --noEmit -p packages/protocol-types/tsconfig.json
  bun test packages/__tests__/transition-validator.test.ts

  # 3. If the Zig kernel changed, rebuild the wasm — do NOT commit zig-out/
  (cd packages/cell-engine && zig build)

  # 4. Stage + commit (reuse this heredoc or write your own message)
  git add -A
  git commit -m 'feat(poker): 2PDA-validated heads-up poker with BSV mainnet state anchoring

- Add packages/poker-agent: Claude-driven agents, payment channels,
  watchlist, violation anchoring, arena harness
- Add protocol-types/transition-validator: K1/K3/K6 invariant checks
  including new hash-chain continuity binding (sha256(v1) → v2.commercePrevState)
- Add wallet-client, agent-context, bsv-anchor-adapter, stub-anchor-adapter
- Zig kernel: cache last_cell_linearity in pda.zig so
  kernel_get_type_class() survives PushDrop OP_2DROP
- New opcodes: OP_CHECKDOMAINFLAG, OP_CHECKTYPEHASH, OP_DEREF_POINTER
- Scripts: poker-arena, poker-dashboard, poker-match, poker-p2p, poker-speed-test
- Tests: transition-validator.test.ts covering K1/K3/K6 + break-prev-hash'

  # 5. Push and open PR (only when you are sure)
  git push -u origin $NEW_BRANCH_NAME
  gh pr create --base main --head $NEW_BRANCH_NAME --title 'feat(poker): 2PDA-validated heads-up poker' --body-file -

  # 6. Cleanup when merged
  git worktree remove "$NEW_WORKTREE"
  git branch -D $NEW_BRANCH_NAME                  # local branch after merge

Safety net:
  • Tag $SNAPSHOT_TAG points at your old HEAD — nothing you had is lost.
  • Push the tag so you don't lose it: git push origin $SNAPSHOT_TAG
  • Everything in the old worktree ($REPO_ROOT) is untouched.

Follow-up PRs (orthogonal work still sitting on $SNAPSHOT_TAG):
  • chore/gitignore-build-artifacts  — .gitignore tightening
  • feat/cellsh-native-debug-shell   — packages/cell-engine/src/cellsh.zig
  • feat/shell-chat-rom              — packages/shell/src/{chat,rom}.ts + lisp/*
  • feat/chess-stakes-demo           — chess-stakes-viewer.html
  • chore/agent-tooling-scripts      — scripts/dual-agent-setup.ts, anchor-demo.ts, wallet-diag.ts
  • docs/phase-25.5-26-30-31-prds    — docs/prd/PHASE-*.md additions
  • feat/host-functions-metering     — packages/metering/src/host-functions.ts

Already landed (do not re-stage):
  • feat(esp32+games) 8bc5452        — esp32-hackkit/** + game-sdk/src/ecs/**

Each of these can use the same pattern: run this script with a different
FILE_SET, or just do 'git worktree add' off main + 'cp' from the snapshot tag.
EOF

```
