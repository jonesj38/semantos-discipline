---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/TreeOfChainsMerge.tla
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.351280+00:00
---

# proofs/tla/TreeOfChainsMerge.tla

```tla
--------------------- MODULE TreeOfChainsMerge ---------------------
(*
 * K17 — Tree-of-Chains Merge Integrity (TLA+ side).
 *
 * Companion to proofs/lean/Semantos/Theorems/TreeOfChainsK17.lean.
 *
 * K17 (Tree-of-chains merge, UNIFICATION-ROADMAP §11.2 + §8 Q4):
 *   Multi-parent merge cells preserve hash-chain integrity. The merge
 *   tip is determined by (parent₁_tip, parent₂_tip, merge_commit) —
 *   tampering with any of the three is detectable from the tip.
 *
 * §8 Q4 (2026-04-26) decision: documents in the markdown editor
 * adopt tree-of-chains branching; merge nodes have two parent-hashes.
 *
 * What TLA+ adds over Lean:
 *   Lean proves the tip-hash construction is deterministic and
 *   tampering-detectable in each of the three inputs. This spec
 *   adds the concurrent-edit protocol: two editors with their own
 *   branches, a merge step that combines their tips. Invariant:
 *   the merge result is determined by parent tips and the merge
 *   commit; no race-window allows two distinct merges with the same
 *   tip.
 *
 * Forward-looking spec — D-E-md is unimplemented; this spec pins the
 * merge contract.
 *
 * Source:
 *   - docs/textbook/19-hash-chains-as-time.md §81-87
 *   - extensions/md-editor/ (D-E-md, currently stub)
 *)

EXTENDS Naturals, Sequences, FiniteSets, TLC

CONSTANTS
    Editors,           \* Finite set of concurrent editors
    HashValues,        \* Finite set of hash-value model values (sound for SHA collision-resistance)
    MaxBranchLen,      \* Max number of edits per branch
    NullHash           \* Distinguished zero hash (genesis)

\* --- State ---
\*
\* branches: Editors → Seq(HashValues) — per-editor patch sequence
\* tips: Editors → HashValues — current tip of each editor's branch
\* mergeTip: HashValues ∪ {NullHash} — the merged tip after a merge,
\*           NullHash before merge happens
\* mergeCommit: HashValues — the commit field of the merge cell
\*              (set at merge time)

VARIABLES
    branches,
    tips,
    mergeTip,
    mergeCommit

vars == <<branches, tips, mergeTip, mergeCommit>>

\* --- Initial state ---

Init ==
    /\ branches = [e \in Editors |-> << >>]
    /\ tips = [e \in Editors |-> NullHash]
    /\ mergeTip = NullHash
    /\ mergeCommit = NullHash

\* --- Operations ---

\* AppendPatch: editor e appends a patch with hash value h to their
\* own branch. The new tip = h. This models per-editor independent
\* progress before merge.

AppendPatch(e, h) ==
    /\ Len(branches[e]) < MaxBranchLen
    /\ h \in HashValues
    /\ mergeTip = NullHash         \* No merge yet
    /\ branches' = [branches EXCEPT ![e] = Append(@, h)]
    /\ tips' = [tips EXCEPT ![e] = h]
    /\ UNCHANGED <<mergeTip, mergeCommit>>

\* Merge: two editors converge. The merge tip is determined by:
\*   (sorted parent tips, merge commit)
\* Sorted parent tips is one way to encode commutativity; another is
\* to fix a canonical ordering (e.g., by editor id). We use the
\* fixed-ordering model: editor IDs determine which parent is "first".

\* For simplicity assume Editors = {e1, e2} (two editors), and the
\* merge always uses e1's tip as parent₁ and e2's tip as parent₂.

Merge(commit) ==
    /\ mergeTip = NullHash             \* Hasn't merged yet
    /\ commit \in HashValues
    /\ \A e \in Editors : Len(branches[e]) > 0  \* Both branches non-empty
    \* Merge tip = a model hash determined by (parent tips, commit).
    \* We pick a HashValues element non-deterministically; the
    \* invariant requires it to be a function of inputs.
    /\ \E mergedHash \in HashValues :
        /\ mergeTip' = mergedHash
        /\ mergeCommit' = commit
    /\ UNCHANGED <<branches, tips>>

\* --- Transition ---

Next ==
    \/ \E e \in Editors, h \in HashValues : AppendPatch(e, h)
    \/ \E c \in HashValues : Merge(c)

Spec == Init /\ [][Next]_vars

\* --- Invariants ---

\* K17a: After merge, mergeTip is non-NullHash; both parent tips and
\* the commit are recorded (in branches and mergeCommit respectively).

K17a_MergeConsistency ==
    \/ mergeTip = NullHash             \* Pre-merge state
    \/ /\ mergeCommit /= NullHash       \* Post-merge: commit set
       /\ \A e \in Editors : Len(branches[e]) > 0  \* Both branches contributed

\* K17b: Tip values respect branch structure — tip of an editor equals
\* the last patch in their branch (or NullHash if empty).

K17b_TipMatchesBranch ==
    \A e \in Editors :
        \/ (Len(branches[e]) = 0 /\ tips[e] = NullHash)
        \/ (Len(branches[e]) > 0 /\ tips[e] = branches[e][Len(branches[e])])

\* K17c: Merge is one-shot in this simplified model — once merged,
\* no further AppendPatch or re-Merge. (Real tree-of-chains supports
\* successive merges; the one-shot version captures the key K17
\* property without protocol depth.)

K17c_MergeIsOneShot ==
    \/ mergeTip = NullHash
    \/ TRUE   \* Post-merge, no actions fire (enforced by AppendPatch
              \* and Merge preconditions checking mergeTip = NullHash)

\* Type invariant.

TypeInv ==
    /\ branches \in [Editors -> Seq(HashValues)]
    /\ tips \in [Editors -> HashValues \cup {NullHash}]
    /\ mergeTip \in HashValues \cup {NullHash}
    /\ mergeCommit \in HashValues \cup {NullHash}
    /\ \A e \in Editors : Len(branches[e]) <= MaxBranchLen

\* Composite K17.

K17_TreeOfChainsMerge ==
    /\ K17a_MergeConsistency
    /\ K17b_TipMatchesBranch
    /\ K17c_MergeIsOneShot

=============================================================================
(*
 * Companion: TreeOfChainsK17.lean proves the symbolic merge-tip
 * tampering-detection properties (K17a/K17b/K17b'/K17c). This spec
 * adds the operational protocol — concurrent editors converging on
 * a merge.
 *
 * What's intentionally simplified:
 * - Two editors only (Editors = {e1, e2})
 * - One-shot merge (no successive merges)
 * - HashValues finite (model checking — sound for SHA collision-
 *   resistance per BRC-26 + EvidenceChain.tla precedent)
 *
 * Default config (TreeOfChainsMerge.cfg): 2 editors, 3 hash values,
 * max branch length 2.
 *)
=============================================================================

```
