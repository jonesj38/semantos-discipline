---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/crystallization/BSV-CSW-ANALYSIS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.546145+00:00
---

# BSV / Craig Wright Narrative Analysis — Deep Run

## Setup

**Corpus:** 217 matched documents across 10 epochs. 1,000 posts fetched with top-3 comments on matched posts. Past year.

| Epoch | Posts | Matched | Match rate |
|---|---|---|---|
| bsv-hot | 100 | 50 | 50% |
| bsv-controversial | 100 | 38 | 38% |
| bitcoincashsv-hot | 100 | 37 | 37% |
| bitcoincashsv-controversial | 100 | 26 | 26% |
| btc-hot | 100 | 9 | 9% |
| btc-controversial | 100 | 13 | 13% |
| bitcoin-hot | 100 | 6 | 6% |
| bitcoin-controversial | 100 | 8 | 8% |
| crypto-hot | 100 | 2 | 2% |
| crypto-controversial | 100 | 28 | 28% |

Note: r/bitcoinsv is restricted — the public API returns nothing. It is sealed from external analysis.

---

## The Structural Topology

The vocabulary does not vanish — it is siloed.

`csw` has 64 mentions across the BSV home subreddits (bsv-hot: 27, bsv-controversial: 14, bitcoincashsv-hot: 13, bitcoincashsv-controversial: 10) and only 5 total in the remaining six mainstream epochs combined — and those 5 are spread thin (1 each). `faketoshi` has 54 mentions in the home subs and 3 outside. `fraud` has 41 home mentions and 2 outside.

This is not absence. This is a **sealed narrative ecosystem** — the vocabulary is abundant inside the BSV communities and structurally absent everywhere else. Whether that's self-imposed isolation, platform suppression, or both is not resolved by the data alone, but the boundary is extremely sharp.

---

## The Two BSV Communities Are Running Different Narratives

r/bsv and r/bitcoincashsv share the BSV brand but appear to be organised around different framings:

**r/bsv** — CSW-personal defence
- `csw` (27 hot, 14 controversial), `faketoshi` (31 hot, 16 controversial), `fraud` (23 hot, 16 controversial), `evidence` (19 hot, 11 controversial), `kleiman` (14 hot, 4 controversial), `arthur-van-pelt` (3 hot, 1 controversial)
- This community is actively contesting the identity claim and defending the evidentiary record

**r/bitcoincashsv** — Blockstream/Core conspiracy frame
- `nullc` (Greg Maxwell): 9 hot, 6 controversial — TRANSITION_ONLY, concentrated entirely in this sub
- `adam-back`: 3 hot, 0 elsewhere — same pattern
- Epstein/Maxwell connection posts (visible in titles sampled)
- This community is attacking the adversary rather than defending CSW

The Pask pairs tell you which concepts travel together and therefore what the actual arguments being made are:

| Pair | Score | Reading |
|---|---|---|
| fraud ↔ kleiman | 0.426 | Kleiman discussions are always framed as fraud accusations |
| patents ↔ satoshi-claim | 0.422 | Patent claims and Satoshi identity are a single argument unit |
| evidence ↔ fraud | 0.373 | Evidence defence is always presented against fraud allegations |
| faketoshi ↔ kleiman | 0.360 | Kleiman = faketoshi framing is locked |
| csw ↔ faketoshi | 0.315 | CSW and faketoshi are nearly inseparable in any document |
| faketoshi ↔ fraud | 0.310 | The three concepts form a cluster: csw ↔ faketoshi ↔ fraud |
| csw ↔ evidence | 0.268 | Evidence claims always attach to CSW |
| arthur-van-pelt ↔ csw | 0.253 | Van Pelt discussions always name CSW directly |

The cluster `csw ↔ faketoshi ↔ fraud ↔ evidence ↔ kleiman` is the dominant narrative structure in the BSV community. It reads as a unit: "the fraud allegations against CSW via the Kleiman case are what the faketoshi crowd uses; here is the evidence they ignore."

---

## Lifecycle Findings

**`faketoshi` — FADING** (31 / 16 / 5 / 2 / 1 / 1 / 0 / 0 / 0 / 1)

The largest raw signal in the dataset. 31 mentions in bsv-hot means this community's most-upvoted content is heavily engaged with the faketoshi accusation. But it fades sharply across communities and epochs. FADING means it was dominant early and is declining — the community is losing the argument in the broader space, not gaining.

**`csw` — ABSORBED** (27 / 14 / 13 / 10 / 1 / 1 / 1 / 1 / 1 / 0)

High in home subs, absent in crypto-controversial (the final epoch, where mainstream contested discourse lives). ABSORBED: peaked, not growing. Zero in crypto-controversial is the sharpest signal — the broader crypto community's most contested space has completely stopped engaging with CSW by name.

**`fraud` — ABSORBED** (23 / 16 / 3 / 2 / 0 / 0 / 0 / 2 / 0 / 0)

Same structure. Two mentions in bitcoin-controversial (not hot) suggest the fraud framing briefly surfaced in r/Bitcoin's contested space but didn't establish itself.

**`evidence` — FADING** (19 / 11 / 3 / 3 / 0 / 0 / 0 / 2 / 0 / 1)

The evidentiary argument — early documents, pre-2016 evidence, Satoshi keys — is active inside BSV communities but declining and not crossing over.

**`corruption` — CRYSTALLIZED** (1 / 0 / 0 / 0 / 0 / 0 / 0 / 4 / 2 / 3) — 3× amplification

This is the most significant finding. One mention in bsv-hot. Then zero across the next six epochs. Then 4 in bitcoin-controversial, 2 in crypto-hot, 3 in crypto-controversial. The judicial corruption argument is not coming from the BSV home community — it's appearing in the mainstream contested and hot spaces. Something in the past year caused the "corrupt court" narrative to surface in r/Bitcoin and r/CryptoCurrency's contested feeds, not just in BSV circles.

**`nullc` (Greg Maxwell) — TRANSITION_ONLY** (0 / 1 / 9 / 6 / 0 / 0 / 0 / 0 / 0 / 0)

Entirely contained in r/bitcoincashsv. 9 mentions in bitcoincashsv-hot, 6 in controversial. Zero everywhere else. TRANSITION_ONLY means it appeared and then didn't persist beyond those two epochs. The nullc/Blockstream conspiracy narrative is a r/bitcoincashsv-specific phenomenon — it has not propagated outward.

**`tuftythecat` (David Pearce) — below threshold**

Zero presence in the data. Pearce doesn't register across 1,000 posts and their top comments. Either the handle doesn't appear in these subreddits or discussion of him uses different vocabulary than we captured.

**`arthur-van-pelt` — ABSORBED** (3 / 1 / 0 / 0 / 0 / 0 / 0 / 0 / 0 / 0)

Present only in r/bsv. Van Pelt is discussed specifically within the BSV community's own space — 3 mentions in hot suggests he's being named in upvoted content, but the signal is small and confined.

---

## Burst Events: Timing the Campaigns

| Week | Concept | Magnitude | Reading |
|---|---|---|---|
| 2025-W32 | fraud | 3.3× | First fraud burst — Aug 2025 |
| 2025-W32 | evidence | 3.0× | Same week — evidence/fraud paired |
| 2025-W40 | nchain | 5.6× | Oct 2025 — nchain push |
| 2025-W40 | teranode | 4.5× | Same week — teranode announced/pushed |
| 2025-W40 | calvin-ayre | 3.1× | Same week — Ayre amplifying |
| 2025-W42 | nchain | 4.4× | Oct 2025 — nchain second wave |
| 2026-W09 | csw | 3.3× | Feb/Mar 2026 — CSW name resurfaces |
| 2026-W14 | fraud | 4.0× | Apr 2026 — fraud discourse returns |
| 2026-W14 | faketoshi | 3.2× | Same week — paired with fraud burst |

Two distinct campaign patterns:

1. **W40 2025 (October)** — nchain/teranode/Calvin Ayre burst, all same week. Enterprise push. Calvin Ayre is amplifying alongside nchain's teranode announcement. This is coordinated product launch messaging inside the BSV community.

2. **W32 + W14 bursts** — fraud and evidence/faketoshi paired bursts separated by months. These map to external events (court filings, media coverage) triggering BSV community response cycles. The W14 2026 fraud+faketoshi burst is recent — April 2026 — suggesting active proceedings or media coverage at that time.

The W09 2026 CSW burst (February/March 2026) is isolated — CSW by name resurfaces in a single week, not attached to fraud or faketoshi, which suggests a specific event (interview, court appearance, statement) rather than a narrative campaign.

---

## The Suppression Question Revisited

The previous run (post titles only, no BSV home subreddits) found csw, faketoshi, fraud all below the 2-mention threshold. This run, with comments and home subreddits, shows them at 27, 31, and 23 mentions respectively in bsv-hot alone.

The vocabulary exists. The discussion is active. It is contained.

The question of whether this is self-containment or active suppression requires reading the actual posts — particularly any removed or locked threads in r/Bitcoin and r/CryptoCurrency that mention CSW. The tool can identify structural anomalies; it cannot see deleted content.

What the data can say: the `corruption` lifecycle (CRYSTALLIZED, 0 in home subs → appearing in bitcoin-controversial and crypto-hot/controversial) is the closest thing to a suppression signal the tool can detect. The "court was corrupt" narrative did not originate in the BSV community's amplified content — it emerged in the mainstream contested space. That's an unusual directionality: normally narrative flows from a community's hot feed outward. Here it appears to be flowing inward or arising independently in hostile territory.

---

## Running It

```bash
bun tools/crystallization/analyze-reddit.ts \
  tools/crystallization/config.bsv-csw.json \
  --output tools/crystallization/output/bsv-csw-deep
```
