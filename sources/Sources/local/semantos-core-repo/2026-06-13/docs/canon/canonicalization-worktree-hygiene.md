---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/canonicalization-worktree-hygiene.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.631094+00:00
---

# Canonicalization Worktree Hygiene

**Status**: canonical. Every session touching canonicalization follows these rules. Violations cause lost work, branch shenanigans, and the kind of "schizo archaeological maze" we're explicitly trying to eliminate.

**Companions**: `canonicalization-matrix.yml` · `canonicalization-glossary.md` · `canonicalization-decisions.md` · `canonicalization-golden-slice.md`

---

## §1 — Topology

The canonicalization runs as **one worktree per track**, branched from a shared `canon/c0-foundation` base.

```
origin/main
   │
   └── canon/c0-foundation       worktrees/canon-c0-foundation
        │   (Android scaffolding, main.dart bootstrap, oddjobz Uri.base fix,
        │    all C0 docs, C7 test scaffold)
        │
        ├── canon/c1-primitives  worktrees/canon-c1-primitives
        ├── canon/c2-self-experience  worktrees/canon-c2-self-experience
        ├── canon/c6a-wallet     worktrees/canon-c6a-wallet
        └── canon/c5-extension-loader  (future)
             canon/c9-helm       (future)
             canon/c4-brain-handler-extract  (future)
             canon/c6b-plexus-recovery-spec  (future)
```

When canon/c0-foundation merges to main, all dependent tracks rebase `--onto main`.

Worktree paths use `/Users/toddprice/projects/semantos-core/worktrees/canon-<name>/` — distinct from the existing `/Users/toddprice/projects/worktrees/` (which holds non-canon work). Keeps canonicalization worktrees grouped, easy to ls.

---

## §2 — Session-start checklist

The FIRST Bash call of any canonicalization session, no exceptions:

```bash
cd /Users/toddprice/projects/semantos-core/worktrees/canon-<your-track>
git branch --show-current     # confirm you're on canon/<your-track>
git rev-list --left-right --count HEAD...origin/main  # ahead/behind
git status --short            # dirty entries — surface before any work
git worktree list | grep canon-  # verify topology unchanged
```

If `git branch --show-current` does NOT print `canon/<your-track>`, STOP. Don't `git checkout` to fix it — that means somebody else's session might have flipped the worktree. Investigate before proceeding.

Surface any of the following to the user immediately:
- branch is not `canon/<your-track>`
- dirty entries that aren't yours
- a sister worktree (`canon-c1`, `canon-c2`, `canon-c6a`) appears missing or moved

---

## §3 — Commit rules

### Rule 1 — Always scope commits to paths

```bash
# RIGHT
git commit apps/semantos/lib/src/identity/ packages/betterment_experience/lib/ -m "..."

# WRONG — commits the entire index, including any concurrent session's staged work
git commit -m "..."
```

Per memory `[[git-commit-scope-to-paths]]`: `git status` shows the index across worktrees + sessions; a blanket `git commit -m` sweeps in things you didn't author. Always pass paths.

### Rule 2 — Commit early, commit often

The pre-mortem (mitigation #1) called out forklift dependencies as the #1 failure mode. Counter: small, frequent commits per worktree. Don't sit on a 500-line uncommitted forklift waiting to be "complete." Each subsystem moved = one commit minimum.

### Rule 3 — Commit messages reference the matrix cell

Format:
```
canon(C<n>): <verb> <subsystem> — <one-line what>

Updates D-CANON-C<n>-<axis> cell <from>→<to>.
Re-ran tests/canonicalization/golden-slice/v1_release.dart: layer <N> went <FROM>→<TO>.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
Co-Authored-By: Claude <noreply@anthropic.com>
```

The `Updates D-CANON-<id>` line makes matrix-cell-progression searchable via `git log --grep`.

### Rule 4 — Never use --no-verify, --no-gpg-sign, or --amend

`--amend` rewrites the previous commit. Per memory and standing rules: only create NEW commits. If a hook fails, fix the cause and make a new commit.

---

## §4 — Branch rules

### Rule 5 — Never `git checkout` in a canon worktree

A worktree's branch is fixed. You arrived in `worktrees/canon-c1-primitives/` because you're working on `canon/c1-primitives`. If you need a different branch, leave this worktree (`cd` away) and enter the right one (`cd worktrees/canon-<other-track>`).

If a checkout is unavoidable (e.g., grabbing a file from a sister branch), do it in a **detached HEAD** so it doesn't move the branch:

```bash
# WRONG
git checkout canon/c2-self-experience -- packages/betterment_experience/

# RIGHT (file extraction from a sister branch, no branch mutation)
git show canon/c2-self-experience:packages/betterment_experience/pubspec.yaml > /tmp/borrow.yaml
```

### Rule 6 — Never `git reset --hard` in a canon worktree without explicit user confirmation

Per memory `[[semantos-shared-checkout-reset-hazard]]`: a parallel session's `reset --hard` wipes uncommitted tracked-file edits. The canon worktree topology was specifically chosen to give each track its own checkout — preserve that property by not destructively rewinding.

If you need to discard work, ask the user first. Quote what would be lost.

### Rule 7 — Rebase canon/c<n>-<track> onto canon/c0-foundation regularly

While canon/c0-foundation evolves (more foundation work lands), each track branch rebases onto the new tip:

```bash
cd worktrees/canon-c1-primitives
git fetch origin
git rebase canon/c0-foundation
```

Conflict? Stop and ask user — don't auto-resolve.

When canon/c0-foundation merges to main, every track rebases `--onto main canon/c0-foundation`.

---

## §5 — Stash rules

### Rule 8 — Never `git stash drop` or `stash clear` without reading the message

Per memory `[[git-stash-safety]]`: stash list is shared across worktrees. Verify the stash you're about to drop is yours by reading the "WIP on <branch>" header. Recover via stash hash from `drop` output before GC if you make a mistake.

```bash
git stash list                # read it
git stash show <stash-id>     # inspect contents
# only then:
git stash drop <stash-id>     # never just "drop" without an id
```

### Rule 9 — Name your stashes

```bash
git stash push -m "canon-c1: half-forklifted contacts/contact_record.dart" path1 path2
```

Untitled stashes are hostile to the next session.

---

## §6 — File-move rules

### Rule 10 — Use `git mv` for in-tree relocations

```bash
# RIGHT — preserves history continuity
cd worktrees/canon-c1-primitives
git mv apps/semantos/lib/src/identity apps/semantos/lib/src/identity
```

For forklifts FROM the monolith TO the canonical shell within the same worktree: `git mv` records the rename.

### Rule 11 — For cross-worktree moves: cp + commit + verify, then rm

Cross-worktree (e.g., extracting a file from main checkout into a canon worktree):

```bash
cp /path/in/main/file.dart /path/in/canon-c2-worktree/file.dart
cd /path/in/canon-c2-worktree
git add packages/betterment_experience/<file>.dart
# commit + verify it landed in canon worktree
# only then:
cd /path/in/main
rm <original>
```

NEVER do this with files that contain other sessions' uncommitted work without their consent.

---

## §7 — Tests after every commit

Per the canonicalization brief and the C7 spec: every track-✓ claim requires re-running the C7 golden slice test. Therefore, at minimum every commit in a canon worktree should be followed by:

```bash
cd tests/canonicalization/golden-slice
dart test v1_release.dart 2>&1 | tail -20
```

Report the result in the commit message ("layer N went RED → assertion failure on X" or "layer N went RED → GREEN").

For Zig-side changes:
```bash
cd runtime/semantos-brain
zig build test -j1 --summary all
```

If a tests-pass claim is made on a matrix cell, the test result excerpt goes in the cell's note.

---

## §8 — Worktree lifecycle

### Creating a canon worktree

```bash
cd /Users/toddprice/projects/semantos-core
git fetch origin
git worktree add -b canon/<track-name> worktrees/canon-<track-name> origin/main
# or, for tracks branching off canon/c0-foundation:
git worktree add -b canon/<track-name> worktrees/canon-<track-name> canon/c0-foundation
```

### Inspecting all canon worktrees

```bash
git worktree list | grep canon-
```

### Retiring a canon worktree (after PR merge)

```bash
cd /Users/toddprice/projects/semantos-core
git worktree remove worktrees/canon-<track-name>
git branch -D canon/<track-name>   # only after PR is merged to main
```

NEVER `worktree remove --force` unless the user explicitly OKs it — `--force` discards uncommitted work in the worktree.

---

## §9 — When things go wrong

### Symptom: you're on the wrong branch in a canon worktree

Don't `git checkout`. STOP. Tell the user. Investigate via:
```bash
git reflog -10
git log --oneline -5
```
The reflog shows recent HEAD movements; the log shows current branch tip.

### Symptom: dirty entries you don't recognize in a canon worktree

Don't `git stash` (might be another session's WIP). Don't `git checkout -- <file>` (destroys the entry). Tell the user. Inspect via:
```bash
git diff <file>
git log -p -1 <file>
```

### Symptom: a canon worktree is "missing"

Possibly removed by another session. Check:
```bash
git worktree list
ls /Users/toddprice/projects/semantos-core/worktrees/
```
If genuinely gone, re-create per §8. The branch should still exist; the worktree is just its on-disk checkout.

### Symptom: a commit got rejected by a pre-commit hook

Fix the cause. Make a NEW commit. NEVER `--amend` or `--no-verify` per Rule 4.

---

## §10 — Per-track session entry instructions

These get saved to memory as `[[canonicalization-worktree-topology]]` for fast session-start lookup:

| Track | Worktree | Branch | First Bash call |
|-------|----------|--------|-----------------|
| C0 foundation | `worktrees/canon-c0-foundation` | `canon/c0-foundation` | `cd /Users/toddprice/projects/semantos-core/worktrees/canon-c0-foundation && git status --short` |
| C1 primitives | `worktrees/canon-c1-primitives` | `canon/c1-primitives` | `cd /Users/toddprice/projects/semantos-core/worktrees/canon-c1-primitives && git status --short` |
| C2 betterment_experience | `worktrees/canon-c2-self-experience` | `canon/c2-self-experience` | `cd /Users/toddprice/projects/semantos-core/worktrees/canon-c2-self-experience && git status --short` |
| C6a wallet | `worktrees/canon-c6a-wallet` | `canon/c6a-wallet` | `cd /Users/toddprice/projects/semantos-core/worktrees/canon-c6a-wallet && git status --short` |

Each track's "next move" is recorded in its branch's most recent commit message + the matrix cell notes. A session entering a worktree finds context via:
```bash
git log -3 --oneline
cat docs/canon/canonicalization-matrix.yml | grep -A20 "id: C<n>"
```
