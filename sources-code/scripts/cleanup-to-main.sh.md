---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/cleanup-to-main.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.320014+00:00
---

# scripts/cleanup-to-main.sh

```sh
#!/usr/bin/env bash
# cleanup-to-main.sh — prune stale worktrees, delete merged branches, get onto clean main
#
# Run from the semantos-core repo root:
#   ./scripts/cleanup-to-main.sh
#
# What it does:
#   1. Prunes all stale worktree tracking (46 dead worktrees)
#   2. Deletes local branches already merged via PRs (phase-13, phase-28)
#   3. Pops the payment-channel prev-hash stash
#   4. Switches to main and pulls
#   5. Shows remaining untracked files (PRDs, packages, scripts)

set -euo pipefail

cyan()   { printf '\033[36m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }
hr()     { printf '%.0s─' {1..70}; printf '\n'; }

if [[ ! -d .git ]] || [[ ! -f package.json ]]; then
  echo "ERROR: run from semantos-core repo root" >&2
  exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

# ── Step 1: Clean stale lock files ──────────────────────────────────────────
bold "Step 1: Clean stale lock files"
find .git -name '*.lock.stale-*' -delete 2>/dev/null || true
rm -rf .git/__stale_keen__ 2>/dev/null || true
find .git -maxdepth 4 -name '*.lock' -mmin +10 -delete 2>/dev/null || true
green "✓ Stale locks cleaned"
echo

# ── Step 2: Prune dead worktrees ────────────────────────────────────────────
bold "Step 2: Prune dead worktrees"
BEFORE=$(git worktree list | wc -l)
git worktree prune
AFTER=$(git worktree list | wc -l)
green "✓ Pruned $((BEFORE - AFTER)) stale worktrees ($AFTER remaining)"
echo

# ── Step 3: Delete stale branches (content already on main via PRs) ─────────
bold "Step 3: Delete stale local branches"

for branch in phase-13-intent-taxonomy phase-28-isda-cdm; do
  if git rev-parse --verify "$branch" >/dev/null 2>&1; then
    git branch -D "$branch" 2>&1 && green "  ✓ Deleted $branch" || yellow "  ⚠ Could not delete $branch"
  else
    yellow "  $branch not found (already gone)"
  fi
done
echo

# ── Step 4: Pop stash (payment-channel prev-hash fix) ──────────────────────
bold "Step 4: Pop stash"
if git stash list | grep -q "payment-channel prev-hash"; then
  yellow "  Stash contains: $(git stash list | head -1)"
  yellow "  Will apply after switching to main..."
  HAVE_STASH=1
else
  yellow "  No payment-channel stash found"
  HAVE_STASH=0
fi
echo

# ── Step 5: Switch to main ─────────────────────────────────────────────────
bold "Step 5: Switch to main"
CURRENT=$(git branch --show-current)
if [[ "$CURRENT" == "main" ]]; then
  green "  Already on main"
else
  cyan "  Currently on: $CURRENT"
  git checkout main
  green "  ✓ Switched to main"
fi
echo

# ── Step 6: Pull latest ────────────────────────────────────────────────────
bold "Step 6: Pull latest main"
git pull origin main
green "✓ main is up to date"
echo

# ── Step 7: Apply stash if needed ──────────────────────────────────────────
if [[ "${HAVE_STASH:-0}" == "1" ]]; then
  bold "Step 7: Apply stash"
  if git stash pop 2>&1; then
    green "  ✓ Stash applied"
  else
    yellow "  ⚠ Stash pop had conflicts — check git status"
  fi
  echo
fi

# ── Step 8: Remaining cleanup info ─────────────────────────────────────────
bold "Step 8: Status check"
hr
echo

bold "Remaining local branches (excluding main):"
git branch | grep -v '^\* main$' | grep -v '^  main$' || echo "  (none — clean!)"
echo

bold "Remaining worktrees:"
git worktree list
echo

bold "Untracked files (new work to commit or stage):"
git status --short | head -30
UNTRACKED=$(git status --short | wc -l | tr -d ' ')
if (( UNTRACKED > 30 )); then
  yellow "  ... and $((UNTRACKED - 30)) more"
fi
echo

hr
green "✓ Done! You're on clean main."
cyan "Next steps:"
cyan "  1. Review untracked files above — commit what you want to keep"
cyan "  2. Run prepare-pr.sh for any follow-up PRs (chess, cellsh, etc.)"
cyan "  3. Plan your sprints!"

```
