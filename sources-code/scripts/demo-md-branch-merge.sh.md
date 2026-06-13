---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/demo-md-branch-merge.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.323140+00:00
---

# scripts/demo-md-branch-merge.sh

```sh
#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# demo-md-branch-merge.sh
#
# A narrated, end-to-end demonstration of the semantos markdown document
# lifecycle: create → branch → parallel edit (disconnected) → return →
# cherry-pick → merge.  Each step prints a structured reveal block:
#   - claim       (what just happened, stated as a property)
#   - evidence    (the observable in the step output that supports it)
#   - implication (what it tells you about the architecture)
#
# Exercises the primitives in:
#   packages/loom/src/helm/document-bundle.ts  — exportBundle / diffPatches /
#                                                 mergePatches / describePatch
#   packages/loom/src/helm/share-channel.ts    — per-recipient mailbox
#
# Terminology note: `hat` is the operator identity (formerly `facet`).  The
# demo's on-the-wire shapes mirror document-bundle.ts but rename `facetId` →
# `hatId` on every patch.
#
# Requirements: node >= 18 (ESM + top-level await).  Bun works too; swap the
# `node --input-type=module -e` invocation below for `bun -e`.
# ----------------------------------------------------------------------------

set -euo pipefail

# ── output helpers ─────────────────────────────────────────────────────────
BOLD=$'\033[1m'; DIM=$'\033[2m'
CYAN=$'\033[36m'; YELLOW=$'\033[33m'; GREEN=$'\033[32m'; MAGENTA=$'\033[35m'
RESET=$'\033[0m'

step() {
  local n="$1"; local title="$2"
  echo
  echo "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════╗${RESET}"
  printf "${BOLD}${CYAN}║${RESET} ${BOLD}STEP %-2s — %-52s${RESET}${BOLD}${CYAN} ║${RESET}\n" "$n" "$title"
  echo "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════════╝${RESET}"
}

narrate() { printf "${MAGENTA}▶${RESET} %s\n" "$*"; }

reveal() {
  echo
  echo "${YELLOW}${BOLD}◆ REVEAL${RESET}"
  echo "  ${BOLD}claim:${RESET}       $1"
  echo "  ${BOLD}evidence:${RESET}    $2"
  echo "  ${BOLD}implication:${RESET} $3"
}

# ── workspace ──────────────────────────────────────────────────────────────
WORKDIR="${DEMO_WORKDIR:-/tmp/semantos-md-demo}"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"/{hat-a,hat-b,hat-c,channel}

echo
echo "${BOLD}semantos · markdown branch / cherry-pick merge demo${RESET}"
echo "${DIM}workspace: $WORKDIR${RESET}"

# ── node helper ────────────────────────────────────────────────────────────
# Mirrors document-bundle.ts with `facetId → hatId`.  Written to $WORKDIR so
# each step's subprocess can dynamic-import it; the file is also left behind
# for post-run inspection.
NODE_LIB="$WORKDIR/lib.mjs"
cat > "$NODE_LIB" <<'JS'
import fs from 'node:fs';

export const readJson  = (p)    => JSON.parse(fs.readFileSync(p, 'utf8'));
export const writeJson = (p, v) => fs.writeFileSync(p, JSON.stringify(v, null, 2));

// exportBundle: lossless, patch-chain-carrying snapshot.
export const exportBundle = (obj, exportedBy) => ({
  version: 1,
  exportedAt: Date.now(),
  exportedBy,
  documentId: obj.id,
  typeHash:   obj.typeDefinition.typeHash,
  typeName:   obj.typeDefinition.name,
  payload:    { ...obj.payload },
  patches:    obj.patches.map((p) => ({ ...p })),
  visibility: obj.visibility,
  linearity:  obj.header.linearity,
  createdAt:  obj.createdAt,
  updatedAt:  obj.updatedAt,
});

// diffPatches: patches present in incoming that are not in base (by id).
export const diffPatches = (base, incoming) => {
  const baseIds = new Set(base.map((p) => p.id));
  return incoming.filter((p) => !baseIds.has(p.id));
};

// mergePatches: cherry-pick — union existing with `selected`, dedupe by id,
// sort by timestamp. The `selected` subset IS the curator's cherry-pick.
export const mergePatches = (existing, selected) => {
  const existingIds = new Set(existing.map((p) => p.id));
  const novel = selected.filter((p) => !existingIds.has(p.id));
  return [...existing, ...novel].sort((a, b) => a.timestamp - b.timestamp);
};

// describePatch: human-readable one-liner for the cherry-pick UI.
export const describePatch = (patch) => {
  const t  = new Date(patch.timestamp).toISOString().slice(11, 19);
  const by = patch.hatId ? ` by ${patch.hatId}` : '';
  const action = patch.delta.action ?? patch.delta.field ?? patch.kind;
  const key = patch.delta.key ? ` [${patch.delta.key}]` : '';
  return `${t} — ${patch.kind}${by}: ${action}${key}`;
};

// foldBody: synthesize the document body from the patch chain.
// last-writer-wins per section key, in timestamp order. The body is a
// derived view; patches are the ground truth.
export const foldBody = (patches) => {
  const sections = new Map();
  for (const p of [...patches].sort((a, b) => a.timestamp - b.timestamp)) {
    const d = p.delta;
    if (d.action === 'add_section' || d.action === 'edit_section') {
      sections.set(d.key, d.body);
    } else if (d.action === 'remove_section') {
      sections.delete(d.key);
    }
  }
  return [...sections.values()].map((b) => b.trimEnd()).join('\n\n') + '\n';
};

// importBundle: reconstruct a local LoomObject from a received bundle.
export const importBundle = (b) => ({
  id:             b.documentId,
  typeDefinition: { name: b.typeName, typeHash: b.typeHash },
  payload:        { ...b.payload },
  patches:        [...b.patches],
  visibility:     b.visibility,
  header:         { linearity: b.linearity },
  createdAt:      b.createdAt,
  updatedAt:      b.updatedAt,
});
JS

# Thin shim: run a JS snippet with WORKDIR/NODE_LIB on the env.
run_node() {
  WORKDIR="$WORKDIR" NODE_LIB="$NODE_LIB" node --input-type=module -e "$1"
}

# ─────────────────────────────────────────────────────────────────────────
step 1 "Hat A creates the document"
# ─────────────────────────────────────────────────────────────────────────
narrate "Hat A (Drafter) opens the Helm dock and types a preamble and Article I."

run_node '
const { writeJson } = await import(process.env.NODE_LIB);
const now = Date.parse("2026-04-18T12:00:00Z");
const patches = [
  { id: "patch-001", kind: "extraction", hatId: "hat-a", timestamp: now,
    delta: { action: "add_section", key: "preamble",
      body: "# Treaty Draft\n\nBetween parties A, B, and C." } },
  { id: "patch-002", kind: "extraction", hatId: "hat-a", timestamp: now + 60_000,
    delta: { action: "add_section", key: "article_i",
      body: "## Article I — Intent\n\nThe parties affirm mutual intent." } },
];
writeJson(`${process.env.WORKDIR}/hat-a/doc.json`, {
  id: "doc-treaty-001",
  typeDefinition: { name: "TreatyDraft", typeHash: "th_7f3c_…" },
  payload: {},
  patches,
  visibility: "draft",
  header: { linearity: patches.length },
  createdAt: now,
  updatedAt: now + 60_000,
});
console.log("  hat-a/doc.json:");
console.log("   id: doc-treaty-001  linearity: 2  visibility: draft");
for (const p of patches) {
  console.log(`   · ${p.id}  ${p.kind}  hatId=${p.hatId}  action=${p.delta.action}  key=${p.delta.key}`);
}
'

reveal \
  "The document is a LoomObject whose body is a fold over a patch list, not a stored string." \
  "doc.json has patches[] with kind/hatId/delta, and payload is {}. The body is never written anywhere." \
  "Every subsequent operation — bundling, diffing, merging — operates on patches because patches are ground truth. The rendered markdown is derivable, disposable, and cheap to recompute."

# ─────────────────────────────────────────────────────────────────────────
step 2 "Duplicate into two branches (exportBundle ×2)"
# ─────────────────────────────────────────────────────────────────────────
narrate "Hat A wants parallel review from Hat B (Diplomat) and Hat C (Economist)."
narrate "exportBundle serialises the ENTIRE LoomObject — payload AND patch chain."

run_node '
const { readJson, writeJson, exportBundle } = await import(process.env.NODE_LIB);
const w = process.env.WORKDIR;
const obj = readJson(`${w}/hat-a/doc.json`);
const bToB = exportBundle(obj, "hat-a");
const bToC = exportBundle(obj, "hat-a");
writeJson(`${w}/channel/bundle-to-b.json`, bToB);
writeJson(`${w}/channel/bundle-to-c.json`, bToC);
console.log(`  channel/bundle-to-b.json: documentId=${bToB.documentId} patches=${bToB.patches.length} linearity=${bToB.linearity}`);
console.log(`  channel/bundle-to-c.json: documentId=${bToC.documentId} patches=${bToC.patches.length} linearity=${bToC.linearity}`);
console.log(`  both bundles share the SAME documentId — identity is invariant across the branch.`);
'

reveal \
  "A bundle is lossless transport, not a snapshot of rendered state." \
  "bundle-to-b.json carries every patch (not just current body) plus provenance (exportedBy, exportedAt). Identical documentId on both bundles." \
  "Receivers can audit history back to creation; branches are forks of the patch trajectory, NOT forks of identity. That distinction is what makes the later merge clean."

# ─────────────────────────────────────────────────────────────────────────
step 3 "Deliver via share-channel (per-recipient mailbox)"
# ─────────────────────────────────────────────────────────────────────────
narrate "Each hat has its own inbox. No live sync, no CRDT — a real boundary."

run_node '
const { readJson, writeJson, importBundle } = await import(process.env.NODE_LIB);
const w = process.env.WORKDIR;
const bToB = readJson(`${w}/channel/bundle-to-b.json`);
const bToC = readJson(`${w}/channel/bundle-to-c.json`);
writeJson(`${w}/hat-b/inbox.json`, [{
  id: "env-001", from: "hat-a", fromName: "Drafter", to: "hat-b",
  bundle: bToB, sentAt: Date.now(), read: false,
}]);
writeJson(`${w}/hat-c/inbox.json`, [{
  id: "env-002", from: "hat-a", fromName: "Drafter", to: "hat-c",
  bundle: bToC, sentAt: Date.now(), read: false,
}]);
writeJson(`${w}/hat-b/doc.json`, importBundle(bToB));
writeJson(`${w}/hat-c/doc.json`, importBundle(bToC));
console.log("  hat-b/inbox.json: 1 envelope from hat-a (doc-treaty-001, unread)");
console.log("  hat-c/inbox.json: 1 envelope from hat-a (doc-treaty-001, unread)");
console.log("  hat-b and hat-c now each hold an independent local LoomObject with linearity=2.");
'

reveal \
  "Transport is explicit, addressed, and per-recipient." \
  "hat-b/inbox.json and hat-c/inbox.json are disjoint; no global store mediates between them." \
  "Disconnection is load-bearing. The architecture has no ambient coherence layer trying to silently reconcile parallel edits, which is WHY the divergence about to happen is safe."

# ─────────────────────────────────────────────────────────────────────────
step 4 "Hat B edits — adds Article III (Sanctions), overrides preamble tone"
# ─────────────────────────────────────────────────────────────────────────
run_node '
const { readJson, writeJson, foldBody } = await import(process.env.NODE_LIB);
const w = process.env.WORKDIR;
const obj = readJson(`${w}/hat-b/doc.json`);
const t0  = obj.updatedAt;
obj.patches.push(
  { id: "patch-B1", kind: "extraction", hatId: "hat-b", timestamp: t0 + 3_600_000,
    delta: { action: "add_section", key: "article_iii",
      body: "## Article III — Sanctions\n\nBreaches trigger graduated sanctions per Annex S." } },
  { id: "patch-B2", kind: "manual_override", hatId: "hat-b", timestamp: t0 + 3_720_000,
    delta: { action: "edit_section", key: "preamble", field: "preamble",
      body: "# Treaty Draft\n\nBetween the Sovereign Parties — A, B, and C — pursuant to the Accord of 2026." } },
);
obj.header.linearity = obj.patches.length;
obj.updatedAt = t0 + 3_720_000;
writeJson(`${w}/hat-b/doc.json`, obj);
console.log("  hat-b patches now:");
for (const p of obj.patches) {
  console.log(`   · ${p.id}  ${p.kind}  hatId=${p.hatId}  action=${p.delta.action}  key=${p.delta.key}`);
}
console.log("\n  hat-b rendered body (folded):");
for (const line of foldBody(obj.patches).split("\n")) console.log(`   │ ${line}`);
'

reveal \
  "Local edits are strictly append-only." \
  "patch-B2 is a manual_override on the preamble, yet patch-001 (original preamble) remains in the chain, unchanged." \
  "Every intention is individually addressable by id and individually auditable by (hatId, kind, delta). This is the precondition for cherry-pick: rejecting a later override does not lose the original."

# ─────────────────────────────────────────────────────────────────────────
step 5 "Hat C edits — rival Article III (Quotas), adds Article IV, removes Article I"
# ─────────────────────────────────────────────────────────────────────────
run_node '
const { readJson, writeJson, foldBody } = await import(process.env.NODE_LIB);
const w = process.env.WORKDIR;
const obj = readJson(`${w}/hat-c/doc.json`);
const t0  = obj.updatedAt;
obj.patches.push(
  { id: "patch-C1", kind: "extraction", hatId: "hat-c", timestamp: t0 + 3_000_000,
    delta: { action: "add_section", key: "article_iii",
      body: "## Article III — Quotas\n\nImport quotas follow the schedule in Annex Q." } },
  { id: "patch-C2", kind: "extraction", hatId: "hat-c", timestamp: t0 + 3_060_000,
    delta: { action: "add_section", key: "article_iv",
      body: "## Article IV — Tariffs\n\nTariffs are capped at 4% absent mutual consent." } },
  { id: "patch-C3", kind: "manual_override", hatId: "hat-c", timestamp: t0 + 3_120_000,
    delta: { action: "remove_section", key: "article_i" } },
);
obj.header.linearity = obj.patches.length;
obj.updatedAt = t0 + 3_120_000;
writeJson(`${w}/hat-c/doc.json`, obj);
console.log("  hat-c patches now:");
for (const p of obj.patches) {
  console.log(`   · ${p.id}  ${p.kind}  hatId=${p.hatId}  action=${p.delta.action}  key=${p.delta.key ?? "—"}`);
}
console.log("\n  hat-c rendered body (folded):");
for (const line of foldBody(obj.patches).split("\n")) console.log(`   │ ${line}`);
'

reveal \
  "Competing patches for the same section key coexist across branches without conflict." \
  "patch-B1 (Article III — Sanctions) and patch-C1 (Article III — Quotas) both target key=article_iii, in separate local chains." \
  "Conflict is NOT detected at write time. The architecture defers conflict to the curation site, where the curator has full author context — hatId, kind, timestamp — not just a diff hunk."

# ─────────────────────────────────────────────────────────────────────────
step 6 "B and C send bundles back to Hat A"
# ─────────────────────────────────────────────────────────────────────────
run_node '
const { readJson, writeJson, exportBundle } = await import(process.env.NODE_LIB);
const w = process.env.WORKDIR;
const b = readJson(`${w}/hat-b/doc.json`);
const c = readJson(`${w}/hat-c/doc.json`);
const bFromB = exportBundle(b, "hat-b");
const bFromC = exportBundle(c, "hat-c");
writeJson(`${w}/channel/bundle-from-b.json`, bFromB);
writeJson(`${w}/channel/bundle-from-c.json`, bFromC);
writeJson(`${w}/hat-a/inbox.json`, [
  { id: "env-010", from: "hat-b", fromName: "Diplomat", to: "hat-a",
    bundle: bFromB, sentAt: Date.now(), read: false },
  { id: "env-011", from: "hat-c", fromName: "Economist", to: "hat-a",
    bundle: bFromC, sentAt: Date.now(), read: false },
]);
console.log("  hat-a/inbox.json: 2 envelopes");
console.log(`   · env-010 from hat-b  documentId=${bFromB.documentId}  linearity=${bFromB.linearity}`);
console.log(`   · env-011 from hat-c  documentId=${bFromC.documentId}  linearity=${bFromC.linearity}`);
'

reveal \
  "The return trip uses the same primitives as the outbound trip — symmetric, not special-cased." \
  "bundle-from-b.json and bundle-from-c.json have the same schema as bundle-to-{b,c}.json; the shared documentId ties them to the origin." \
  "Identity (documentId) survived the entire branch-and-return cycle unchanged. Branches are trajectories of the same identity — never forks of identity — which is why merging them in the next steps does not require an identity resolution step."

# ─────────────────────────────────────────────────────────────────────────
step 7 "Hat A runs diffPatches against local for each incoming bundle"
# ─────────────────────────────────────────────────────────────────────────
run_node '
const { readJson, diffPatches, describePatch } = await import(process.env.NODE_LIB);
const w = process.env.WORKDIR;
const local = readJson(`${w}/hat-a/doc.json`);
const inbox = readJson(`${w}/hat-a/inbox.json`);
for (const env of inbox) {
  const cand = diffPatches(local.patches, env.bundle.patches);
  console.log(`  candidates from ${env.fromName} (${env.from}):`);
  for (const p of cand) console.log(`   [ ] ${p.id}  ${describePatch(p)}`);
  console.log();
}
'

reveal \
  "Diff operates at patch granularity, not text granularity." \
  "Each candidate is an (id, kind, hatId, delta) tuple — no line ranges, no hunks, no merge markers." \
  "The merge UI is a checklist of authored intentions. The curator's question is 'whose intention do I accept for this section?' — not 'which chunk wins?'. This is the core ergonomic move that distinguishes semantos merge from git merge."

# ─────────────────────────────────────────────────────────────────────────
step 8 "Hat A cherry-picks: keep B's Article III + tone override, and C's Article IV"
# ─────────────────────────────────────────────────────────────────────────
narrate "Rationale (human, not derivable): trust hat-b on sanctions; trust hat-c on tariffs;"
narrate "reject hat-c's rival Article III (redundant with B's) and reject hat-c's removal"
narrate "of Article I (too aggressive for a draft)."

run_node '
const { readJson, writeJson, describePatch } = await import(process.env.NODE_LIB);
const w = process.env.WORKDIR;
const inbox = readJson(`${w}/hat-a/inbox.json`);
const all = [...inbox[0].bundle.patches, ...inbox[1].bundle.patches];
const keep = new Set(["patch-B1", "patch-B2", "patch-C2"]);
const selected = all.filter((p) => keep.has(p.id));
const rejected = all.filter((p) => !keep.has(p.id) && !p.id.startsWith("patch-0"));
console.log("  selected (cherry-picked):");
for (const p of selected) console.log(`   [x] ${p.id}  ${describePatch(p)}`);
console.log("\n  rejected (not included in merge, but still exist in proposer chains):");
for (const p of rejected) console.log(`   [ ] ${p.id}  ${describePatch(p)}`);
writeJson(`${w}/hat-a/selected-patches.json`, selected);
'

reveal \
  "Cherry-pick is intentional curation, not automatic conflict resolution." \
  "The selected set is an arbitrary subset of the global candidates; rejected patches have no auto-resolved variant and carry no 'conflict' marker." \
  "Rejection is non-inclusion, not deletion. The rejected patches remain in hat-b's and hat-c's local chains as unmerged proposals; they can be re-submitted in a future bundle, or debated asynchronously, without any state change at the origin."

# ─────────────────────────────────────────────────────────────────────────
step 9 "Apply mergePatches — fold selection into Hat A's chain"
# ─────────────────────────────────────────────────────────────────────────
run_node '
const { readJson, writeJson, mergePatches, foldBody, describePatch } = await import(process.env.NODE_LIB);
const w = process.env.WORKDIR;
const local    = readJson(`${w}/hat-a/doc.json`);
const selected = readJson(`${w}/hat-a/selected-patches.json`);
local.patches  = mergePatches(local.patches, selected);
local.header.linearity = local.patches.length;
local.updatedAt = Math.max(...local.patches.map((p) => p.timestamp));
writeJson(`${w}/hat-a/doc.json`, local);
console.log(`  hat-a/doc.json now: documentId=${local.id}  linearity=${local.header.linearity}`);
console.log("\n  final chain (chronological):");
for (const p of local.patches) console.log(`   · ${describePatch(p)}`);
const hats = [...new Set(local.patches.map((p) => p.hatId))];
console.log(`\n  authors preserved in chain: ${hats.join(", ")}`);
console.log("\n  final rendered body:");
for (const line of foldBody(local.patches).split("\n")) console.log(`   │ ${line}`);
'

reveal \
  "Merge extends the chain; it does not synthesize a merge commit." \
  "documentId is unchanged (doc-treaty-001). linearity went 2 → 5. Each surviving patch still carries its original hatId." \
  "A downstream consumer querying patches[*].hatId can reconstruct exactly who authored each surviving section. There is no synthetic 'merge author' — provenance is per-patch, and the cherry-pick itself is visible in the structure of the chain (sparse hatId pattern) rather than an opaque commit object."

# ─────────────────────────────────────────────────────────────────────────
step 10 "Coda — five load-bearing properties of this architecture"
# ─────────────────────────────────────────────────────────────────────────
cat <<'EOF'

  1. State is a fold, not a field.
     The body was never stored; it is recomputed from patches every time.
     That is what lets bundles be lossless: ship the patches, recompute the body.

  2. Identity survives divergence.
     documentId is invariant across bundle → inbox → branch → return → merge.
     Branches fork the trajectory, not the identity.

  3. Conflict is deferred to the curator, not resolved in the graph.
     Competing "Article III" patches coexist globally; the merge site is where
     intent is weighed. No silent convergence, no line-merge folklore.

  4. Author identity is first-class at patch granularity.
     hatId on every patch makes cherry-pick meaningful — curation is a function
     of WHO proposed WHAT, not only WHICH text changed.

  5. Disconnection is load-bearing.
     The share-channel is explicit, addressed, and per-recipient. No ambient
     coherence layer runs behind your back, which is why parallel edits cannot
     interfere and the merge step is honest.

EOF
echo "${GREEN}✓ demo complete${RESET}"
echo "${DIM}  artefacts preserved at $WORKDIR${RESET}"
echo "${DIM}  inspect: ls -R $WORKDIR${RESET}"

```
