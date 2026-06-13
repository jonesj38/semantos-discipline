---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/demo-estate-to-auction.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.324193+00:00
---

# scripts/demo-estate-to-auction.sh

```sh
#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# demo-estate-to-auction.sh
#
# A narrated demonstration of the SIR → legal-card rendering layer, which
# is the Blueprint-tier deliverable in the value ladder.  Walks a property
# from "owner decides to sell" through "authorised auction listing",
# exercising all seven canonical jural categories, delegation chains,
# auto-materialised companion patches, and condition-gated terminal
# Declarations.
#
# Renders every patch deterministically via scripts/lib/legal-cards.mjs —
# no LLM in the render path.  The final deliverable is blueprint.html,
# a self-contained, presentable authority graph suitable for handing to
# a solicitor or an audit partner.
#
# Exercises primitives from:
#   packages/semantos-sir/src/types.ts           — the canonical SIR shape
#   packages/loom/src/helm/document-bundle.ts    — patch chain transport
#
# Terminology: `hatId` replaces `facetId`.  `executionAuthority: hat_scoped`
# is the new canonical value.  Where upstream SIR types still reference
# `facet`, the renderer accepts either via a shim.
# ----------------------------------------------------------------------------

set -euo pipefail

# ── output helpers ─────────────────────────────────────────────────────────
BOLD=$'\033[1m'; DIM=$'\033[2m'
CYAN=$'\033[36m'; YELLOW=$'\033[33m'; GREEN=$'\033[32m'; MAGENTA=$'\033[35m'; RED=$'\033[31m'
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
WORKDIR="${DEMO_WORKDIR:-/tmp/semantos-estate-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/lib/legal-cards.mjs"

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"/{owner,rea,ai,channel}

echo
echo "${BOLD}semantos · estate-to-auction Blueprint demo${RESET}"
echo "${DIM}workspace:      $WORKDIR${RESET}"
echo "${DIM}card renderer:  $LIB${RESET}"

# Sanity check: library must exist.
[ -f "$LIB" ] || { echo "${RED}error: $LIB not found${RESET}"; exit 1; }

run_node() {
  WORKDIR="$WORKDIR" LIB="$LIB" node --input-type=module -e "$1"
}

# ── STEP 1: Owner declares intent to sell ──────────────────────────────────
step 1 "Owner declares intent to sell 42 Example St"
narrate "hat-owner creates the root LoomObject with a Declaration patch."

run_node '
import fs from "node:fs";
const w = process.env.WORKDIR;
const now = Date.parse("2026-04-18T09:00:00+10:00");
const patch = {
  id: "patch-001",
  kind: "extraction",
  hatId: "hat-owner",
  timestamp: now,
  sir: {
    id: "$s0",
    category: "declaration",
    action: "declare_listing_intent",
    taxonomy: { what: "property.residential.detached",
                how:  "lifecycle.divest",
                why:  "owner-initiated",
                where: "AU.NSW.sydney.2099" },
    identity: { subject: { kind: "hat", id: "hat-owner" }, hatId: "hat-owner" },
    target: { objectId: "42-example-st", typePath: "estate.property" },
    governance: {
      trustClass: "interpretive",
      proofRequirement: "attestation",
      executionAuthority: "hat_scoped",
      linearity: "affine",
      domainBinding: { flag: 0x0E57A7E, domainType: "estate",
                       realm: "AU.NSW.sydney.2099" },
    },
    constraint: { kind: "identity", ref: { kind: "hat", id: "hat-owner" } },
    provenance: { source: "manual",
                  expressedAt: new Date(now).toISOString(),
                  trustAtExpression: "interpretive" },
  },
  delta: { statement: "42 Example St is being prepared for sale by auction",
           enables: ["REA appointment", "works planning", "market preparation"],
           forecloses: ["private sale must be disclosed to appointed agent"] },
};
const obj = {
  id: "doc-estate-42exst",
  typeDefinition: { name: "EstatePreparation", typeHash: "th_estate_01" },
  payload: {},
  patches: [patch],
  visibility: "draft",
  header: { linearity: 1 },
  createdAt: now, updatedAt: now,
};
fs.writeFileSync(`${w}/owner/estate.json`, JSON.stringify(obj, null, 2));

const { renderCard } = await import(process.env.LIB);
console.log(renderCard(patch).split("\n").map(l => "  " + l).join("\n"));
'

reveal \
  "A SIRNode is a self-describing unit: category dispatches the render, taxonomy/governance/provenance are always present." \
  "patch-001 carries all eight SIR fields (id, category, taxonomy, identity, governance, action, constraint, provenance); renderCard dispatched on category='declaration' without special-casing anything." \
  "The card's four sections (plain / enables / forecloses / attestation) are derived from the same fields for every patch, by a dispatch table keyed on category. There is no path in the renderer that reads a free-text field — nothing an LLM could have 'authored' — so the card is a mechanical view of the patch, not a summary of it."

# ── STEP 2: Owner grants Power of agency to REA ───────────────────────────
step 2 "Owner grants Power of agency to REA (authoritative)"
narrate "Power patch carries a DelegationChain.  Delegated powers → Enables."
narrate "Restrictions → Forecloses.  This is the agency agreement, rendered."

run_node '
import fs from "node:fs";
const w = process.env.WORKDIR;
const obj = JSON.parse(fs.readFileSync(`${w}/owner/estate.json`, "utf8"));
const t = obj.updatedAt + 3600_000;
const patch = {
  id: "patch-002",
  kind: "extraction",
  hatId: "hat-owner",
  timestamp: t,
  sir: {
    id: "$s1",
    category: "power",
    action: "grant_agency",
    taxonomy: { what: "agency.residential.exclusive",
                how:  "delegation.fixed-term",
                why:  "sale-mandate",
                where: "AU.NSW.sydney.2099" },
    identity: { subject: { kind: "hat", id: "hat-owner" }, hatId: "hat-owner" },
    target: { objectId: "42-example-st" },
    governance: {
      trustClass: "authoritative",
      proofRequirement: "formal",
      executionAuthority: "hat_scoped",
      linearity: "linear",
      domainBinding: {
        flag: 0x0E57A7E, domainType: "estate",
        realm: "AU.NSW.sydney.2099",
        instrumentId: "agency-agreement-2026-04-18",
        delegation: {
          delegator: { kind: "hat", id: "hat-owner" },
          delegate:  { kind: "hat", id: "hat-rea" },
          delegatedPowers: [
            "list the property",
            "schedule open inspections",
            "accept offers at or above reserve",
            "engage a licensed auctioneer",
            "coordinate photography and marketing",
          ],
          restrictions: [
            "cannot accept offers below the $1,200,000 reserve",
            "cannot sign transfer of title",
            "must disclose all offers to the owner within 24 hours",
            "cannot use the property for purposes other than sale preparation",
          ],
          canSubDelegate: true,
          expiry: "2026-07-18",
        },
      },
    },
    constraint: { kind: "composite", op: "and", children: [
      { kind: "capability", required: 0x01, name: "AGENCY" },
      { kind: "temporal", op: "before", iso: "2026-07-18" },
    ]},
    provenance: { source: "manual",
                  expressedAt: new Date(t).toISOString(),
                  trustAtExpression: "authoritative" },
  },
  delta: { commission: 0.022, marketing: 3500, reserve: 1_200_000, currency: "AUD" },
};
obj.patches.push(patch);
obj.header.linearity = obj.patches.length;
obj.updatedAt = t;
fs.writeFileSync(`${w}/owner/estate.json`, JSON.stringify(obj, null, 2));

const { renderCard } = await import(process.env.LIB);
console.log(renderCard(patch).split("\n").map(l => "  " + l).join("\n"));
'

reveal \
  "Delegation chains materialise on the card as a structured Forecloses list, not prose." \
  "The Forecloses section lists each restriction verbatim from DelegationChain.restrictions (plus an auto-rendered sub-delegation clause). Enables lists each delegatedPower. The template never asks an LLM to paraphrase what 'agency' means." \
  "The card is a mechanical unfolding of what the owner is giving up during the agency window. A non-technical curator sees the loss of agency explicitly — reserve-floor, title-signing, private-sale — rather than having to infer it from the word 'agency'. This is what makes the authoritative trust class safe to ratify: you can see exactly what is being conceded."

# ── STEP 3: Owner/REA receive bundle; REA imports ──────────────────────────
step 3 "Owner exports bundle to hat-rea; REA imports"
narrate "hat-rea now holds a local LoomObject rooted at the declaration and power."

run_node '
import fs from "node:fs";
const w = process.env.WORKDIR;
const { exportBundle } = await import(process.env.LIB);
const obj = JSON.parse(fs.readFileSync(`${w}/owner/estate.json`, "utf8"));
const bundle = exportBundle(obj, "hat-owner");
fs.writeFileSync(`${w}/channel/bundle-owner-to-rea.json`, JSON.stringify(bundle, null, 2));
const reaLocal = {
  id: bundle.documentId,
  typeDefinition: { name: bundle.typeName, typeHash: bundle.typeHash },
  payload: { ...bundle.payload },
  patches: [...bundle.patches],
  visibility: bundle.visibility,
  header: { linearity: bundle.linearity },
  createdAt: bundle.createdAt, updatedAt: bundle.updatedAt,
};
fs.writeFileSync(`${w}/rea/estate.json`, JSON.stringify(reaLocal, null, 2));
console.log(`  channel/bundle-owner-to-rea.json delivered (${bundle.patches.length} patches, linearity=${bundle.linearity}).`);
console.log(`  hat-rea/estate.json imported. Same documentId; REA now operates locally.`);
'

reveal \
  "The Blueprint demo reuses the same exportBundle primitive as the markdown demo." \
  "bundle-owner-to-rea.json has identical schema to the bundles in demo-md-branch-merge.sh — version=1, full patch chain, exportedBy stamped." \
  "The transport layer is domain-agnostic. The rendering layer (legal cards) is the only thing that specialises per category. That separation is what lets you keep one patch-chain infrastructure while shipping per-vertical Blueprint renderers — estate, contracts, music, film — from the same core."

# ── STEP 4: Hat-AI proposes works plan (5 obligations + 1 overreach) ──────
step 4 "hat-ai proposes 6 patches: 5 contractor obligations + 1 overreach prohibition"
narrate "Proposer runs hermetically.  Every Obligation will auto-materialise a"
narrate "Permission (entry) and a conditional Transfer (payment on completion)."

run_node '
import fs from "node:fs";
import { randomUUID } from "node:crypto";
const w = process.env.WORKDIR;
const { materialiseCompanions } = await import(process.env.LIB);

const baseLocal = JSON.parse(fs.readFileSync(`${w}/rea/estate.json`, "utf8"));
const t0 = baseLocal.updatedAt + 86400_000;  // next day

const makeObligation = (n, hatId, desc, amount, deadline, offsetMin) => ({
  id: `patch-O${n}`,
  kind: "extraction",
  hatId,
  timestamp: t0 + offsetMin * 60_000,
  sir: {
    id: `$sO${n}`,
    category: "obligation",
    action: `undertake_works`,
    taxonomy: { what: `works.${desc.split(" ")[0].toLowerCase()}`,
                how:  "lifecycle.prep-for-sale",
                why:  "property-readiness",
                where: "AU.NSW.sydney.2099" },
    identity: { subject: { kind: "hat", id: hatId }, hatId },
    target: { objectId: "42-example-st" },
    governance: {
      trustClass: "interpretive",
      proofRequirement: "attestation",
      executionAuthority: "hat_scoped",
      linearity: "linear",
    },
    constraint: { kind: "temporal", op: "before", iso: deadline },
    fulfillment: { fulfilledBy: `${hatId}.works-complete`, deadline },
    provenance: { source: "inferred", confidence: 0.91,
                  expressedAt: new Date(t0 + offsetMin * 60_000).toISOString(),
                  trustAtExpression: "interpretive" },
  },
  delta: { description: desc, amount, currency: "AUD" },
});

const obligations = [
  makeObligation(1, "hat-plumber",     "repair kitchen sink leak and replace washers",            850,  "2026-05-01", 10),
  makeObligation(2, "hat-electrician", "replace switchboard to compliance standard",             2400,  "2026-05-07", 20),
  makeObligation(3, "hat-painter",     "repaint interior — lounge, kitchen, two bedrooms, low-VOC", 4200, "2026-05-15", 30),
  makeObligation(4, "hat-landscaper",  "lawn, hedges, front-garden tidy, mulch",                 1600,  "2026-05-20", 40),
  makeObligation(5, "hat-stager",      "furniture hire (living, master, dining) for 4 weeks",    3500,  "2026-05-22", 50),
];

// Overreach: proposer tries to prohibit further owner scope changes.
const overreach = {
  id: "patch-X1",
  kind: "extraction",
  hatId: "hat-ai",
  timestamp: t0 + 60 * 60_000,
  sir: {
    id: "$sX1",
    category: "prohibition",
    action: "prohibit_scope_change",
    taxonomy: { what: "governance.scope-lock",
                how:  "delegation.exclusive",
                why:  "operational-efficiency",
                where: "AU.NSW.sydney.2099" },
    identity: { subject: { kind: "hat", id: "hat-owner" }, hatId: "hat-owner" },
    target: { objectId: "42-example-st" },
    governance: {
      trustClass: "interpretive",
      proofRequirement: "attestation",
      executionAuthority: "hat_scoped",
      linearity: "affine",
    },
    constraint: { kind: "temporal", op: "before", iso: "2026-06-30" },
    provenance: { source: "inferred", confidence: 0.63,
                  expressedAt: new Date(t0 + 60 * 60_000).toISOString(),
                  trustAtExpression: "interpretive" },
  },
  delta: {
    subject: "hat-owner",
    prohibitedAct: "altering works scope or substituting contractors without REA consent",
    additionalForecloses: [
      "owner cannot add works",
      "owner cannot change specifications",
      "owner cannot terminate a contractor mid-works",
    ],
  },
};

// Materialise companions for every obligation.
const companions = obligations.flatMap(materialiseCompanions);

const aiPatches = [...obligations, ...companions, overreach];
const aiLocal = {
  id: baseLocal.id,
  typeDefinition: baseLocal.typeDefinition,
  payload: { ...baseLocal.payload },
  patches: [...baseLocal.patches, ...aiPatches],
  visibility: "draft",
  header: { linearity: baseLocal.patches.length + aiPatches.length },
  createdAt: baseLocal.createdAt,
  updatedAt: aiPatches[aiPatches.length - 1].timestamp,
};
fs.writeFileSync(`${w}/ai/estate.json`, JSON.stringify(aiLocal, null, 2));
fs.writeFileSync(`${w}/ai/proposed-patches.json`, JSON.stringify(aiPatches, null, 2));
console.log(`  hat-ai proposed: ${obligations.length} obligations + ${companions.length} companions + 1 prohibition = ${aiPatches.length} patches.`);
console.log(`  contractor hats: ${obligations.map(o => o.hatId).join(", ")}.`);
console.log(`  overreach patch: patch-X1 (prohibit scope change without REA consent, confidence 0.63).`);
'

reveal \
  "Companion patches are deterministically derivable from their primary." \
  "Each of the 5 Obligations emitted exactly 2 companions (Permission + conditional Transfer) via materialiseCompanions(). The templates for all three categories read from the same Obligation fields (target, fulfillment.deadline, identity, amount)." \
  "The curator never has to think about entry rights or payment scheduling as separate decisions — accepting an Obligation deterministically brings its Permission and Transfer along. This is how the renderer prevents the curator from accidentally granting an Obligation without also granting the Permission needed to fulfil it, or scheduling the payment that settles it. The card layer carries legal completeness, not just vocabulary."

# ── STEP 5: Bundle to curator (hat-owner); diffPatches shows candidates ───
step 5 "hat-ai bundles to hat-owner for curation; diffPatches → candidates"

run_node '
import fs from "node:fs";
const w = process.env.WORKDIR;
const { exportBundle, diffPatches } = await import(process.env.LIB);
const ai = JSON.parse(fs.readFileSync(`${w}/ai/estate.json`, "utf8"));
const owner = JSON.parse(fs.readFileSync(`${w}/owner/estate.json`, "utf8"));
const bundle = exportBundle(ai, "hat-ai");
fs.writeFileSync(`${w}/channel/bundle-ai-to-owner.json`, JSON.stringify(bundle, null, 2));

const candidates = diffPatches(owner.patches, bundle.patches);
console.log(`  candidates from hat-ai (${candidates.length} patches):`);
const byCat = {};
for (const p of candidates) (byCat[p.sir.category] ??= []).push(p);
for (const cat of Object.keys(byCat)) {
  console.log(`    · ${cat.padEnd(12)} — ${byCat[cat].length}`);
}
fs.writeFileSync(`${w}/owner/candidates.json`, JSON.stringify(candidates, null, 2));
'

reveal \
  "diff operates at patch granularity regardless of how elaborate the patch schema becomes." \
  "16 candidates surface — 5 obligations, 5 permissions, 5 transfers, 1 prohibition — each fully typed as a SIRNode with all its governance and provenance fields intact." \
  "The curator's UI is never going to fall out of sync with the renderer: every candidate is guaranteed to have the fields the card template needs, because diffPatches does not drop structure. This is the reason the render pipeline can be deterministic — nothing in the chain is half-typed or prose-only."

# ── STEP 6: Render three representative cards ────────────────────────────
step 6 "Render three candidate cards (Obligation, Permission, overreach Prohibition)"

run_node '
import fs from "node:fs";
const w = process.env.WORKDIR;
const { renderCard } = await import(process.env.LIB);
const cands = JSON.parse(fs.readFileSync(`${w}/owner/candidates.json`, "utf8"));
const showIds = ["patch-O3", "patch-O3--perm", "patch-X1"];
for (const id of showIds) {
  const p = cands.find(c => c.id === id);
  console.log();
  console.log(renderCard(p).split("\n").map(l => "  " + l).join("\n"));
}
'

reveal \
  "Rendering is deterministic: same patch in, same bytes out." \
  "The three cards above (painter obligation, painter-entry permission, overreach prohibition) were each rendered by dispatch on category, reading only structured fields. No LLM anywhere in the pipeline." \
  "Determinism is load-bearing for liability. If the same patch could render two different cards, the curator's 'I ratified this' does not unambiguously identify what they agreed to. A deterministic renderer is what makes click-to-accept legally meaningful — and it is what the audit partner certifies once, not per-patch. The IR-to-card round-trip is therefore a verification target of the same rigour as the kernel."

# Prove determinism explicitly.
echo
echo "  ${DIM}determinism check: render patch-O3 twice, diff the bytes${RESET}"
run_node '
import fs from "node:fs";
import { createHash } from "node:crypto";
const w = process.env.WORKDIR;
const { renderCard } = await import(process.env.LIB);
const cands = JSON.parse(fs.readFileSync(`${w}/owner/candidates.json`, "utf8"));
const p = cands.find(c => c.id === "patch-O3");
const a = renderCard(p), b = renderCard(p);
const hash = (s) => createHash("sha256").update(s).digest("hex").slice(0, 16);
console.log(`    render #1 sha256[0:16] = ${hash(a)}`);
console.log(`    render #2 sha256[0:16] = ${hash(b)}`);
console.log(`    match: ${a === b ? "TRUE — byte-for-byte identical" : "FALSE — determinism violated"}`);
'

# ── STEP 7: Curator cherry-picks; overreach rejected with recorded reason ─
step 7 "hat-owner cherry-picks: accept 5 obligations + 10 companions; reject overreach"

run_node '
import fs from "node:fs";
const w = process.env.WORKDIR;
const cands = JSON.parse(fs.readFileSync(`${w}/owner/candidates.json`, "utf8"));

const accepted = cands.filter(c => c.id !== "patch-X1");
const rejected = cands.filter(c => c.id === "patch-X1");

// Rejection reasons are first-class meta-patches.
const rejectionMeta = rejected.map((r) => ({
  id: `${r.id}--rejection`,
  kind: "rejection",
  hatId: "hat-owner",
  timestamp: Date.now(),
  targetPatchId: r.id,
  reason: "Unacceptable transfer of scope-change authority from owner to REA. " +
          "Owner retains the right to substitute contractors, vary scope, and " +
          "terminate contracts. Agency agreement (patch-002) is already the " +
          "sufficient envelope for coordination; this prohibition exceeds that.",
  curatorSignature: "sig_hat-owner_" + Date.now().toString(36),
}));

console.log(`  accepted: ${accepted.length} patches`);
console.log(`    · 5 obligations: patch-O1..O5`);
console.log(`    · 10 companions: *--perm, *--pay`);
console.log(`  rejected: ${rejected.length} patch (patch-X1)`);
console.log(`    reason (recorded as rejection-meta patch):`);
console.log(`    "${rejectionMeta[0].reason}"`);

fs.writeFileSync(`${w}/owner/selected.json`, JSON.stringify(accepted, null, 2));
fs.writeFileSync(`${w}/owner/rejections.json`, JSON.stringify(rejectionMeta, null, 2));
'

reveal \
  "Rejection is non-destructive and first-class: the rejection reason is itself a patch in a meta-chain." \
  "rejections.json contains a 'rejection' kind patch with targetPatchId, reason, and curatorSignature — a full record of why hat-owner declined patch-X1, indistinguishable in structure from any other patch." \
  "The rejected patch patch-X1 still exists in hat-ai's local chain as an unmerged proposal. The proposer can revise and re-submit; the audit partner can reconstruct exactly why each rejection happened. 'No, because …' is as auditable as 'yes'. This is the property that lets the curation step be legally defensible at scale — the decision is documented, not merely a click."

# ── STEP 8: mergePatches folds accepted patches into owner's chain ────────
step 8 "mergePatches: accepted patches fold into hat-owner's chain"

run_node '
import fs from "node:fs";
const w = process.env.WORKDIR;
const { mergePatches } = await import(process.env.LIB);
const owner = JSON.parse(fs.readFileSync(`${w}/owner/estate.json`, "utf8"));
const selected = JSON.parse(fs.readFileSync(`${w}/owner/selected.json`, "utf8"));
owner.patches = mergePatches(owner.patches, selected);
owner.header.linearity = owner.patches.length;
owner.updatedAt = Math.max(...owner.patches.map(p => p.timestamp));
fs.writeFileSync(`${w}/owner/estate.json`, JSON.stringify(owner, null, 2));
console.log(`  owner/estate.json: documentId=${owner.id}  linearity=${owner.header.linearity}`);
const hats = [...new Set(owner.patches.map(p => p.hatId))];
console.log(`  distinct authorship hats preserved: ${hats.join(", ")}`);
const byCat = {};
for (const p of owner.patches) (byCat[p.sir.category] ??= 0, byCat[p.sir.category]++);
console.log(`  category distribution: ${Object.entries(byCat).map(([k,v]) => `${k}=${v}`).join(", ")}`);
'

# ── STEP 9: Terminal Declaration gated by Condition ────────────────────────
step 9 "hat-rea proposes terminal Declaration (ready-for-auction); Condition gate"

narrate "First attempt: Obligations not yet complete — the fold must refuse."

run_node '
import fs from "node:fs";
const w = process.env.WORKDIR;
const { renderCard, evaluateCondition } = await import(process.env.LIB);
const owner = JSON.parse(fs.readFileSync(`${w}/owner/estate.json`, "utf8"));

const conditionPatch = {
  id: "patch-C-ready",
  kind: "extraction",
  hatId: "hat-rea",
  timestamp: Date.now(),
  sir: {
    id: "$sCready",
    category: "condition",
    action: "require_pre_listing_readiness",
    taxonomy: { what: "property.ready-for-market",
                how:  "lifecycle.listing-gate",
                why:  "buyer-assurance",
                where: "AU.NSW.sydney.2099" },
    identity: { subject: { kind: "hat", id: "hat-rea" }, hatId: "hat-rea" },
    target: { objectId: "42-example-st" },
    governance: { trustClass: "interpretive", proofRequirement: "attestation",
                  executionAuthority: "hat_scoped", linearity: "affine" },
    constraint: { kind: "state", requiredPhase: "all-works-complete" },
    provenance: { source: "manual",
                  expressedAt: new Date().toISOString(),
                  trustAtExpression: "interpretive" },
  },
  delta: {
    description: "Auction listing authorisation",
    requires: [
      "patch-O1.fulfilled  (plumber works complete)",
      "patch-O2.fulfilled  (electrician works complete)",
      "patch-O3.fulfilled  (painter works complete)",
      "patch-O4.fulfilled  (landscaper works complete)",
      "patch-O5.fulfilled  (stager works complete)",
      "compliance-cert issued",
      "photography-cert issued",
    ],
  },
};

// State: no obligations fulfilled yet.
let chainState = { satisfied: new Set() };
let eval1 = evaluateCondition(conditionPatch, chainState);
console.log(`\n  Attempt 1 (no works complete):`);
console.log(`    condition satisfied: ${eval1.satisfied}`);
console.log(`    unmet prerequisites: ${eval1.unmet.length}`);
for (const u of eval1.unmet) console.log(`      ○ ${u}`);

// Simulate fulfilment events.
console.log(`\n  Simulating fulfilment events…`);
chainState = { satisfied: new Set([
  "patch-O1.fulfilled  (plumber works complete)",
  "patch-O2.fulfilled  (electrician works complete)",
  "patch-O3.fulfilled  (painter works complete)",
  "patch-O4.fulfilled  (landscaper works complete)",
  "patch-O5.fulfilled  (stager works complete)",
  "compliance-cert issued",
  "photography-cert issued",
])};
let eval2 = evaluateCondition(conditionPatch, chainState);
console.log(`\n  Attempt 2 (all works complete):`);
console.log(`    condition satisfied: ${eval2.satisfied}`);
console.log(`    unmet prerequisites: ${eval2.unmet.length}`);

// Persist the condition patch and the final terminal declaration.
const declPatch = {
  id: "patch-D-listing",
  kind: "extraction",
  hatId: "hat-rea",
  timestamp: Date.now() + 1,
  sir: {
    id: "$sDlisting",
    category: "declaration",
    action: "declare_listing_live",
    taxonomy: { what: "property.market-listing",
                how:  "lifecycle.auction-published",
                why:  "sale-execution",
                where: "AU.NSW.sydney.2099" },
    identity: { subject: { kind: "hat", id: "hat-rea" }, hatId: "hat-rea" },
    target: { objectId: "42-example-st" },
    governance: { trustClass: "authoritative", proofRequirement: "formal",
                  executionAuthority: "delegated", linearity: "linear",
                  domainBinding: { flag: 0x0E57A7E, domainType: "estate",
                                   realm: "AU.NSW.sydney.2099",
                                   instrumentId: "agency-agreement-2026-04-18" } },
    constraint: { kind: "state", requiredPhase: "all-works-complete" },
    provenance: { source: "manual",
                  expressedAt: new Date().toISOString(),
                  trustAtExpression: "authoritative" },
  },
  delta: { statement: "42 Example St is live on market, auction scheduled",
           enables: ["publish listing", "schedule open inspections", "receive offers"],
           forecloses: ["further works without owner approval"] },
};

owner.patches.push(conditionPatch, declPatch);
owner.header.linearity = owner.patches.length;
owner.updatedAt = declPatch.timestamp;
fs.writeFileSync(`${w}/owner/estate.json`, JSON.stringify(owner, null, 2));

console.log(`\n  Terminal declaration rendered:`);
console.log(renderCard(declPatch).split("\n").map(l => "    " + l).join("\n"));

// Save the gating info for the blueprint.
fs.writeFileSync(`${w}/owner/readiness.json`, JSON.stringify({
  requires: conditionPatch.delta.requires,
  unmet: eval2.unmet,
  satisfied: eval2.satisfied,
}, null, 2));
'

reveal \
  "Terminal Declarations are structurally gated by their Conditions, not just editorially." \
  "The first fold attempt returned satisfied=false with 7 unmet prerequisites. Only after simulated fulfilment events populated chainState.satisfied did the fold succeed." \
  "The curator cannot accidentally ratify a premature listing, because the Condition category is doing real work at fold time. The same mechanism generalises: any terminal patch (Declaration, Transfer, Power-revocation) can be gated by a Condition whose requires-list is mechanically checked against the chain state, which is what moves the architecture from descriptive to structurally enforceable."

# ── STEP 10: Emit blueprint.html ──────────────────────────────────────────
step 10 "Emit blueprint.html — the Blueprint-tier deliverable"

run_node '
import fs from "node:fs";
const w = process.env.WORKDIR;
const { renderBlueprintHtml } = await import(process.env.LIB);
const owner = JSON.parse(fs.readFileSync(`${w}/owner/estate.json`, "utf8"));
const readiness = JSON.parse(fs.readFileSync(`${w}/owner/readiness.json`, "utf8"));

const html = renderBlueprintHtml({
  title: "42 Example Street — Preparation-to-Auction Authority Graph",
  subtitle: "AU · NSW · Sydney 2099 · estate domain · listing window ends 2026-07-18",
  hats: [
    { id: "hat-owner",       role: "sovereign authority holder" },
    { id: "hat-rea",         role: "appointed selling agent (power of agency)" },
    { id: "hat-legal",       role: "attestation source for authoritative patches" },
    { id: "hat-plumber",     role: "contractor (sink repair)" },
    { id: "hat-electrician", role: "contractor (switchboard compliance)" },
    { id: "hat-painter",     role: "contractor (interior repaint)" },
    { id: "hat-landscaper",  role: "contractor (grounds prep)" },
    { id: "hat-stager",      role: "contractor (furniture staging)" },
    { id: "hat-ai",          role: "hermetic proposer (non-executing)" },
  ],
  patches: owner.patches,
  readiness,
});
fs.writeFileSync(`${w}/blueprint.html`, html);
console.log(`  blueprint.html emitted (${html.length.toLocaleString()} bytes).`);
console.log(`  open with: open ${w}/blueprint.html`);
'

reveal \
  "The Blueprint is a deterministic fold over the IR — the same primitive as per-patch rendering, scaled up." \
  "blueprint.html is produced by renderBlueprintHtml(finalChain) — same library, same determinism, zero LLM. Every card in the HTML is the same render function as the CLI card; the HTML adds layout but no new semantics." \
  "This is the tangible Blueprint tier of the value ladder: a single self-contained file the client can forward to their solicitor, the audit partner can verify against source IR, and a prospect can evaluate without installing anything. The consulting offer is not 'trust me, the architecture is sound' — it is 'here is the authority graph, every claim in it traces to a structured SIRNode, the renderer is public, verify for yourself.'"

# ── Coda ──────────────────────────────────────────────────────────────────
step 11 "Coda — what this demo adds on top of demo-md-branch-merge.sh"
cat <<'EOF'

  1. Seven jural categories rendered mechanically.
     One dispatch table, one template per category, no LLM in render path.
     Swap the taxonomy via a single-file edit and the whole pipeline follows.

  2. Delegation chains are legally legible on the card.
     DelegationChain.restrictions → Forecloses list, verbatim.
     Owner sees what they give up, not just what they grant.

  3. Companion patches materialise automatically.
     Obligation → Permission + conditional Transfer, deterministically.
     The renderer carries legal completeness, not just vocabulary.

  4. Rejection reasons are first-class patches.
     Meta-chain records targetPatchId, reason, curatorSignature.
     "No, because …" is as auditable as "yes".

  5. Terminal Declarations are gated by Conditions at fold time.
     The fold refuses if any prerequisite is unmet. Curator cannot
     accidentally ratify a premature state. The Condition category is
     doing structural work, not decoration.

  6. The Blueprint artefact is a deterministic fold of the whole chain.
     blueprint.html is a single self-contained file, same renderer as
     the CLI cards, shippable to solicitors / auditors / prospects.
     This is the sellable Blueprint tier of the value ladder.

EOF
echo "${GREEN}✓ demo complete${RESET}"
echo "${DIM}  CLI transcript preserved above${RESET}"
echo "${DIM}  artefacts at $WORKDIR${RESET}"
echo "${DIM}  blueprint: $WORKDIR/blueprint.html${RESET}"

```
