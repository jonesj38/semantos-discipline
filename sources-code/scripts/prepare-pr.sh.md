---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/prepare-pr.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.316540+00:00
---

# scripts/prepare-pr.sh

```sh
#!/usr/bin/env bash
# prepare-pr.sh — generalized follow-up PR staging for the post-poker work
#
# Sibling of prepare-poker-pr.sh. Same safety pattern:
#   1. Tag current HEAD as a safety snapshot (nothing ever gets lost).
#   2. Fetch origin/main fresh.
#   3. Create an isolated worktree off origin/main at a sibling dir.
#   4. Copy the named PR's file-set from your current worktree into it.
#   5. Leave the new worktree UNCOMMITTED so you can diff, resolve, commit by hand.
#
# Each PR is one named case below. Default mode is --dry-run. Pass --execute
# to actually create the worktree and copy files.
#
# Usage:
#   ./scripts/prepare-pr.sh list                    # show available PRs
#   ./scripts/prepare-pr.sh <name>                  # dry run
#   ./scripts/prepare-pr.sh <name> --execute        # do it
#
# Available PR names:
#   chess        — feat/chess-stakes-demo             (1 file)
#   cellsh       — feat/cellsh-native-debug-shell    (2 files: cellsh.zig + build.zig)
#   shell-chat   — feat/shell-chat-rom                (4 files: chat.ts, rom.ts, lisp/*)
#   agent-tools  — chore/agent-tooling-scripts       (3 files: scripts/*.ts)
#   metering     — feat/host-functions-metering      (2 files: metering/src/*)
#   docs         — docs/phase-25.5-31-prds            (dynamic: docs/prd/*.md diff)
#   gitignore    — chore/gitignore-build-artifacts   (1 file: .gitignore)

set -euo pipefail

# ── Static configuration ─────────────────────────────────────────────────────

MAIN_BRANCH="origin/main"
SNAPSHOT_TAG_PREFIX="safety/pre-pr-snapshot"

# ── Mode flags ───────────────────────────────────────────────────────────────

DRY_RUN=1
PR_NAME=""
for arg in "$@"; do
  case "$arg" in
    --execute) DRY_RUN=0 ;;
    --dry-run) DRY_RUN=1 ;;
    --help|-h)
      sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    list|chess|cellsh|shell-chat|agent-tools|metering|docs|gitignore)
      if [[ -n "$PR_NAME" ]]; then
        echo "ERROR: only one PR name allowed, got '$PR_NAME' and '$arg'" >&2
        exit 2
      fi
      PR_NAME="$arg"
      ;;
    *)
      echo "Unknown arg: $arg" >&2
      echo "Run: $0 --help  (or: $0 list)" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$PR_NAME" ]]; then
  echo "ERROR: no PR name given" >&2
  echo "Usage: $0 <name> [--execute]" >&2
  echo "       $0 list" >&2
  exit 2
fi

# ── Sanity: run from repo root ───────────────────────────────────────────────

if [[ ! -d .git ]] || [[ ! -f package.json ]]; then
  echo "ERROR: run this from the semantos-core repo root" >&2
  exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"
REPO_NAME=$(basename "$REPO_ROOT")

# ── Pretty printing helpers ─────────────────────────────────────────────────

cyan()   { printf '\033[36m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }
hr()     { printf '%.0s─' {1..70}; printf '\n'; }

# ── `list` mode ──────────────────────────────────────────────────────────────

if [[ "$PR_NAME" == "list" ]]; then
  bold "Available follow-up PRs:"
  hr
  cat <<'LIST'
  chess        feat/chess-stakes-demo
               └─ chess-stakes-viewer.html
               (standalone demo file, no conflict risk)

  cellsh       feat/cellsh-native-debug-shell
               ├─ packages/cell-engine/src/cellsh.zig
               └─ packages/cell-engine/build.zig
               (build.zig may conflict — main has evolved zig build steps)

  shell-chat   feat/shell-chat-rom
               ├─ packages/shell/src/chat.ts
               ├─ packages/shell/src/rom.ts
               ├─ packages/shell/src/lisp/compiler.ts
               └─ packages/shell/src/lisp/types.ts
               (lisp/* may conflict if main has lisp edits)

  agent-tools  chore/agent-tooling-scripts
               ├─ scripts/anchor-demo.ts
               ├─ scripts/dual-agent-setup.ts
               └─ scripts/wallet-diag.ts
               (low conflict risk, dev scripts only)

  metering     feat/host-functions-metering
               ├─ packages/metering/src/host-functions.ts
               └─ packages/metering/src/index.ts
               (index.ts is a clean one-line append)

  docs         docs/phase-25.5-31-prds
               └─ docs/prd/*.md that differ from origin/main
               (file list computed dynamically; HIGH conflict risk —
                main may have phase-26H/30 PRDs already)

  gitignore    chore/gitignore-build-artifacts
               └─ .gitignore
               (CONFLICT RISK — the esp32 wasm allowlist line may already
                be on main after 8bc5452; dry-run the diff before committing)
LIST
  hr
  echo
  cyan "Usage: $0 <name>            # dry run"
  cyan "       $0 <name> --execute  # actually create worktree"
  exit 0
fi

# ── PR definitions ───────────────────────────────────────────────────────────
#
# Each case populates:
#   BRANCH      — new branch name
#   TITLE       — PR title (used by gh pr create in the final instructions)
#   FILES       — array of paths to copy into the new worktree
#   COMMIT_MSG  — suggested commit message heredoc
#   NOTES       — any special warnings printed in the final phase

BRANCH=""
TITLE=""
FILES=()
COMMIT_MSG=""
NOTES=""

case "$PR_NAME" in
  chess)
    BRANCH="feat/chess-stakes-demo"
    TITLE="feat(chess): chess stakes viewer demo"
    FILES=("chess-stakes-viewer.html")
    NOTES="Standalone HTML demo. No conflicts expected."
    COMMIT_MSG="feat(chess): add chess stakes viewer demo

Standalone HTML viewer for chess match stakes — sibling of
poker-dashboard.html. Useful for demo-ing BSV-anchored game state
without pulling in the poker package."
    ;;

  cellsh)
    BRANCH="feat/cellsh-native-debug-shell"
    TITLE="feat(cellsh): native debug shell for cell-engine"
    FILES=(
      "packages/cell-engine/src/cellsh.zig"
      "packages/cell-engine/build.zig"
    )
    NOTES="build.zig may conflict — main has evolved zig build steps since divergence.
Run 'git diff packages/cell-engine/build.zig' in the new worktree first."
    COMMIT_MSG="feat(cellsh): native debug shell for cell-engine

- Add packages/cell-engine/src/cellsh.zig: interactive REPL for
  poking the PDA kernel, inspecting cell headers, and stepping
  through transitions without going through the JS harness
- Update packages/cell-engine/build.zig: add cellsh build step

This is purely additive — the wasm build target is unchanged."
    ;;

  shell-chat)
    BRANCH="feat/shell-chat-rom"
    TITLE="feat(shell): chat + rom + lisp tweaks"
    FILES=(
      "packages/shell/src/chat.ts"
      "packages/shell/src/rom.ts"
      "packages/shell/src/lisp/compiler.ts"
      "packages/shell/src/lisp/types.ts"
    )
    NOTES="lisp/compiler.ts and lisp/types.ts may conflict if main has touched lisp.
Run 'git diff packages/shell/src/lisp/' in the new worktree first."
    COMMIT_MSG="feat(shell): chat + rom with lisp type tweaks

- chat.ts: shell chat command improvements
- rom.ts: rom handling updates
- lisp/compiler.ts + lisp/types.ts: supporting type refinements"
    ;;

  agent-tools)
    BRANCH="chore/agent-tooling-scripts"
    TITLE="chore(scripts): agent setup + diagnostics"
    FILES=(
      "scripts/anchor-demo.ts"
      "scripts/dual-agent-setup.ts"
      "scripts/wallet-diag.ts"
    )
    NOTES="Dev scripts only. Low conflict risk — these were all new on our branch."
    COMMIT_MSG="chore(scripts): agent setup and diagnostic tools

- anchor-demo.ts: standalone anchor broadcast demo
- dual-agent-setup.ts: provisions wallets/keys for two-agent runs
- wallet-diag.ts: wallet state inspector / UTXO dump"
    ;;

  metering)
    BRANCH="feat/host-functions-metering"
    TITLE="feat(metering): host function wiring"
    FILES=(
      "packages/metering/src/host-functions.ts"
      "packages/metering/src/index.ts"
    )
    NOTES="index.ts is a clean one-line append (export of registerMeteringHostFunctions).
host-functions.ts is new. Low conflict risk unless main has touched the barrel."
    COMMIT_MSG="feat(metering): host function wiring for kernel import

- Add packages/metering/src/host-functions.ts: registers the metering
  host functions (gas counters, limits, traps) on a wasm instance
- Re-export registerMeteringHostFunctions + MeteringContext from index.ts"
    ;;

  docs)
    BRANCH="docs/phase-25.5-31-prds"
    TITLE="docs: add phase 25.5 + 31 PRDs"
    # Dynamic file list: whatever under docs/prd/ differs from main.
    # Falls back to empty if fetch fails; the verify phase will catch that.
    if git rev-parse --verify "$MAIN_BRANCH" >/dev/null 2>&1; then
      mapfile -t FILES < <(git diff --name-only "$MAIN_BRANCH" -- 'docs/prd/' 2>/dev/null || true)
    fi
    NOTES="HIGH CONFLICT RISK. Main may already have phase-26H/30 PRDs since
the last sync. The file list is computed dynamically from:
  git diff --name-only $MAIN_BRANCH -- docs/prd/
Review the list in Phase 1 output and prune any PRDs that belong to
other efforts before running with --execute."
    COMMIT_MSG="docs: phase 25.5 + 31 PRD additions

Add PRDs for phase 25.5 (linearity classes / 2PDA foundations) and
phase 31 (downstream agent runtime). These documents back the poker
work but are orthogonal to the code PR."
    ;;

  gitignore)
    BRANCH="chore/gitignore-build-artifacts"
    TITLE="chore(gitignore): tighten build-artifact rules"
    FILES=(".gitignore")
    NOTES="CONFLICT RISK. The esp32 wasm allowlist line may already be on main
after 8bc5452 (esp32+games). Diff carefully in the new worktree:
  git diff .gitignore
If the esp32 line already exists on main, drop it from your version
before committing — keep only the .env.*, backup, and chat-state lines."
    COMMIT_MSG="chore(gitignore): tighten build-artifact rules

- Ignore .env and .env.* (except .env.example)
- Ignore .semantos-chat-state.json
- Ignore .cowork-backups/
- Keep esp32 embedded wasm whitelisted (may already be on main)"
    ;;

  *)
    echo "ERROR: internal — unhandled case '$PR_NAME'" >&2
    exit 99
    ;;
esac

# ── Derived paths ────────────────────────────────────────────────────────────

NEW_WORKTREE="$(dirname "$REPO_ROOT")/${REPO_NAME}-${PR_NAME}-pr"
TS=$(date -u +%Y%m%dT%H%M%SZ)
SNAPSHOT_TAG="${SNAPSHOT_TAG_PREFIX}-${PR_NAME}-${TS}"

# Refuse to clobber an existing worktree
if [[ -e "$NEW_WORKTREE" ]]; then
  red "ERROR: $NEW_WORKTREE already exists."
  yellow "Remove it first:  git worktree remove --force $NEW_WORKTREE"
  yellow "                  rm -rf $NEW_WORKTREE  (if git no longer tracks it)"
  exit 1
fi

# ── Phase 0: Print the plan ──────────────────────────────────────────────────

bold "prepare-pr.sh [$PR_NAME] — $(if [[ $DRY_RUN == 1 ]]; then echo 'DRY RUN'; else echo 'EXECUTE'; fi)"
hr
cyan "Repo root:     $REPO_ROOT"
cyan "Current HEAD:  $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD))"
cyan "Target branch: $MAIN_BRANCH"
cyan "Safety tag:    $SNAPSHOT_TAG"
cyan "New worktree:  $NEW_WORKTREE"
cyan "New branch:    $BRANCH"
cyan "PR title:      $TITLE"
cyan "Files:         ${#FILES[@]}"
hr

# ── Phase 0.5: Clean stale sandbox lock files ──────────────────────────────
#
# Some sandbox/filesystem helpers rename abandoned *.lock files to
# `*.lock.stale-keen-<epoch>` or move whole refs into `.git/__stale_keen__/`.
# These leftovers make `git fetch` fail with:
#   fatal: bad object refs/heads/<branch>.lock.stale-keen-<n>
# We detect and silently remove them before touching git.

bold "Phase 0.5: Cleaning stale sandbox lock files"

STALE_LOCKS=$(find .git -name '*.lock.stale-*' 2>/dev/null || true)
STALE_DIR_EXISTS=0
[[ -d .git/__stale_keen__ ]] && STALE_DIR_EXISTS=1

# Also stale PLAIN .lock files older than 10 minutes — these are from
# crashed processes and git can't recover from them on its own.
STALE_PLAIN_LOCKS=$(find .git -maxdepth 4 -name '*.lock' -mmin +10 2>/dev/null | grep -v '\.lock\.stale' || true)

if [[ -z "$STALE_LOCKS" ]] && (( STALE_DIR_EXISTS == 0 )) && [[ -z "$STALE_PLAIN_LOCKS" ]]; then
  green "✓ No stale locks found"
else
  if [[ -n "$STALE_LOCKS" ]]; then
    yellow "Found $(echo "$STALE_LOCKS" | wc -l | tr -d ' ') stale *.lock.stale-* file(s):"
    echo "$STALE_LOCKS" | sed 's/^/    /'
  fi
  if (( STALE_DIR_EXISTS == 1 )); then
    yellow "Found stale directory: .git/__stale_keen__/"
  fi
  if [[ -n "$STALE_PLAIN_LOCKS" ]]; then
    yellow "Found stale *.lock file(s) (>10 min old):"
    echo "$STALE_PLAIN_LOCKS" | sed 's/^/    /'
  fi

  if [[ $DRY_RUN == 1 ]]; then
    yellow "[dry-run] would: delete all of the above"
  else
    [[ -n "$STALE_LOCKS" ]] && find .git -name '*.lock.stale-*' -delete 2>/dev/null || true
    (( STALE_DIR_EXISTS == 1 )) && rm -rf .git/__stale_keen__ 2>/dev/null || true
    if [[ -n "$STALE_PLAIN_LOCKS" ]]; then
      # Delete one-by-one so a failure on one doesn't kill the rest
      while IFS= read -r lock; do
        [[ -n "$lock" ]] && rm -f "$lock" 2>/dev/null || true
      done <<< "$STALE_PLAIN_LOCKS"
    fi
    green "✓ Stale locks cleaned"
  fi
fi
echo

# ── Phase 1: Verify files exist in the current worktree ─────────────────────

bold "Phase 1: Verifying files exist in the current worktree"

if (( ${#FILES[@]} == 0 )); then
  red "No files in the manifest for PR '$PR_NAME'."
  if [[ "$PR_NAME" == "docs" ]]; then
    yellow "The docs case computes its file list dynamically from:"
    yellow "  git diff --name-only $MAIN_BRANCH -- docs/prd/"
    yellow "Either origin/main wasn't fetched, or there are no diffs there."
    yellow "Fetch first:  git fetch origin main"
  fi
  exit 1
fi

echo "Files to stage:"
for f in "${FILES[@]}"; do echo "  • $f"; done
echo

MISSING=()
for f in "${FILES[@]}"; do
  if [[ ! -f "$f" ]]; then MISSING+=("$f"); fi
done

if (( ${#MISSING[@]} > 0 )); then
  red "MISSING ${#MISSING[@]} file(s):"
  for f in "${MISSING[@]}"; do echo "  ✗ $f"; done
  exit 1
fi
green "✓ All ${#FILES[@]} files present"
echo

# ── Phase 2: Safety tag ─────────────────────────────────────────────────────

bold "Phase 2: Safety tag"
if git rev-parse "$SNAPSHOT_TAG" >/dev/null 2>&1; then
  yellow "Tag $SNAPSHOT_TAG already exists — skipping"
else
  if [[ $DRY_RUN == 1 ]]; then
    yellow "[dry-run] would: git tag -a $SNAPSHOT_TAG -m 'safety snapshot before $PR_NAME PR staging'"
  else
    git tag -a "$SNAPSHOT_TAG" -m "safety snapshot before $PR_NAME PR staging" HEAD
    green "✓ Tagged HEAD as $SNAPSHOT_TAG"
    yellow "  Push to preserve: git push origin $SNAPSHOT_TAG"
  fi
fi
echo

# ── Phase 3: Fetch origin/main ──────────────────────────────────────────────

bold "Phase 3: Fetching $MAIN_BRANCH"
if [[ $DRY_RUN == 1 ]]; then
  yellow "[dry-run] would: git fetch origin main --tags"
else
  git fetch origin main --tags
  green "✓ origin/main at $(git rev-parse origin/main)"
fi
echo

# ── Phase 4: Create worktree ────────────────────────────────────────────────

bold "Phase 4: Create worktree at $NEW_WORKTREE"

if [[ $DRY_RUN == 1 ]]; then
  yellow "[dry-run] would: git worktree add -b $BRANCH $NEW_WORKTREE $MAIN_BRANCH"
  yellow "[dry-run] would: copy ${#FILES[@]} file(s) from $REPO_ROOT into $NEW_WORKTREE"
  yellow "[dry-run] would: cd $NEW_WORKTREE && git status"
  echo
  bold "DRY RUN COMPLETE"
  if [[ -n "$NOTES" ]]; then
    echo
    yellow "Notes for this PR:"
    echo "$NOTES" | sed 's/^/  /'
  fi
  echo
  cyan "Re-run with --execute to actually perform the above steps:"
  cyan "  $0 $PR_NAME --execute"
  exit 0
fi

git worktree add -b "$BRANCH" "$NEW_WORKTREE" "$MAIN_BRANCH"
green "✓ Worktree created at $NEW_WORKTREE (branch $BRANCH off $MAIN_BRANCH)"
echo

# ── Phase 5: Copy files ─────────────────────────────────────────────────────

bold "Phase 5: Copying files"
COPIED=0
OVERWROTE=0
OVERWRITTEN_FILES=()

for f in "${FILES[@]}"; do
  dest="$NEW_WORKTREE/$f"
  dest_dir=$(dirname "$dest")
  [[ -d "$dest_dir" ]] || mkdir -p "$dest_dir"
  if [[ -f "$dest" ]]; then
    OVERWROTE=$((OVERWROTE + 1))
    OVERWRITTEN_FILES+=("$f")
  fi
  cp -p "$REPO_ROOT/$f" "$dest"
  COPIED=$((COPIED + 1))
done

green "✓ Copied $COPIED file(s) ($OVERWROTE overwrote files from main)"
if (( OVERWROTE > 0 )); then
  yellow "  Overwritten files (review for conflicts):"
  for f in "${OVERWRITTEN_FILES[@]}"; do echo "    ⚠ $f"; done
fi
echo

# ── Phase 6: git status ─────────────────────────────────────────────────────

bold "Phase 6: git status in the new worktree"
hr
(cd "$NEW_WORKTREE" && git status --short)
hr
echo

# ── Phase 7: Next steps ─────────────────────────────────────────────────────

bold "Done. Next steps (manual, for your review):"
cat <<EOF

  cd "$NEW_WORKTREE"

  # 1. Review what changed vs main
  git diff --stat
  git diff        # full diff
EOF

if (( OVERWROTE > 0 )); then
  echo
  echo "  # 1a. These files existed on main already — diff them carefully:"
  for f in "${OVERWRITTEN_FILES[@]}"; do
    echo "  git diff $f"
  done
fi

cat <<EOF

  # 2. Sanity check (adjust for this PR's scope)
  bun install       # if deps are needed
  # bun run check   # optional typecheck

  # 3. Stage + commit
  git add -A
  git commit -m '$(echo "$COMMIT_MSG" | head -1)'
  # (full message below — paste into an editor with: git commit --amend)

  # 4. Push + open PR
  git push -u origin $BRANCH
  gh pr create --base main --head $BRANCH --title '$TITLE'

  # 5. Cleanup when merged
  git worktree remove "$NEW_WORKTREE"
  git branch -D $BRANCH
EOF

if [[ -n "$NOTES" ]]; then
  echo
  yellow "⚠ Notes for this PR:"
  echo "$NOTES" | sed 's/^/  /'
fi

echo
bold "Full commit message:"
hr
echo "$COMMIT_MSG"
hr
echo
bold "Safety net:"
cyan "  • Tag $SNAPSHOT_TAG points at your old HEAD — nothing is lost."
cyan "  • Push it to preserve across reinstall:  git push origin $SNAPSHOT_TAG"
cyan "  • The old worktree ($REPO_ROOT) is untouched."

```
