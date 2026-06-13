---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/crystallization/SOCIAL-ENGINEERING-DETECTION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.545296+00:00
---

# Detecting Narrative Manipulation with Architectural Crystallization

## The Core Idea

Reddit has two fundamentally different sorting mechanisms: **hot/top** and **controversial**.

- **Hot/top** = posts the platform amplified. High upvotes, fast velocity. This is what most users see.
- **Controversial** = posts with high engagement on *both sides* — lots of upvotes AND lots of downvotes. This is where the community is actively fighting about something.

Social engineering manipulates **hot** (coordinated upvote campaigns push a narrative into visibility) but leaves traces in **controversial** (the authentic community pushes back, creating the split that marks controversy).

By running the crystallization analyzer separately against each feed and comparing the concept lifecycle types, you can see which narratives are organic and which are being manufactured.

---

## What We Measure

The crystallization tool tracks **concept vocabulary** across multiple document collections (epochs). For each concept it asks: did this appear early, grow, fade, or never appear at all?

The nine lifecycle types collapse to a simpler question when applied to hot vs controversial:

| Lifecycle in hot | Lifecycle in controversial | Interpretation |
|---|---|---|
| 💎 CRYSTALLIZED | ⚡ TRANSITION_ONLY or absent | **Manufactured consensus** — concept is amplified by the platform but the community isn't organically discussing it |
| 💎 CRYSTALLIZED | 💎 CRYSTALLIZED | **Genuine discourse** — organic adoption, community agrees enough to argue *and* upvote |
| 🌟 LATE_EMERGENCE in hot | 💎 CRYSTALLIZED in controversial | **Pushed narrative winning** — community was fighting about it first, then it got amplified |
| ⚡ TRANSITION_ONLY in hot | — | **Failed astroturf** — manufactured burst that didn't stick |
| Absent in hot | 💎 CRYSTALLIZED in controversial | **Suppressed debate** — the community is actively contesting something the platform isn't surfacing |

---

## The Pask Score Signal

Beyond lifecycle types, the Pask co-occurrence stability score reveals **scripted talking points**.

Genuine discourse produces *varied* concept co-occurrence — different posts combine concepts differently. Coordinated messaging produces *suspiciously consistent* co-occurrence — every post that mentions concept A also mentions concept B, because they're working from the same script.

A concept pair with:
- **High Pask score in hot + low in controversial** → scripted talking point cluster
- **High Pask score in both** → genuine ideological pairing (e.g. `scarcity ↔ store-of-value` is a real Bitcoin belief, not just astroturf)
- **Low everywhere** → organic, loosely associated

---

## Burst Events as Timing Evidence

When a burst (a week with mentions > 3× the 4-week trailing average) appears:

- **Burst in controversial BEFORE hot** → the community noticed and fought about it first, *then* it got amplified. This is the classic sequence for a coordinated campaign that initially meets resistance before breaking through.
- **Burst in hot with no corresponding controversial burst** → the amplification wasn't contested. Either genuinely popular or invisible to the community that would push back.
- **Burst in controversial with no hot burst** → the community is inflamed about something the broader platform isn't picking up.

---

## Worked Example: r/Bitcoin + r/CryptoCurrency (past year, post titles only)

**Corpus:** 800 posts across 4 epochs — r/Bitcoin and r/CryptoCurrency, each split hot vs controversial.

| Epoch | Posts fetched | Matched docs | Match rate |
|---|---|---|---|
| bitcoin-hot | 200 | 43 | 22% |
| bitcoin-controversial | 200 | 119 | 60% |
| crypto-hot | 200 | 70 | 35% |
| crypto-controversial | 200 | 164 | 82% |

**The first finding is structural**: across both communities, the controversial feed matches Bitcoin-specific vocabulary at 2–3× the rate of hot. The technical and ideological discourse lives in controversial. The front page is price milestones, memes, and personal stories.

### CRYSTALLIZED concepts and what they reveal

16 concepts crystallized across the corpus (amplification ≥ 2×):

**`altcoin` — 27× amplification (19 → 70 → 80 → 509)**
The biggest volume signal in the dataset. Altcoin discussion explodes in crypto-controversial (509 mentions vs 80 in crypto-hot). The community is fighting about altcoins far more than it's celebrating them.

**`defi` — 45× amplification (1 → 9 → 7 → 45)**
Near-absent in hot feeds (1 mention in bitcoin-hot, 7 in crypto-hot), explodes to 45 in crypto-controversial. DeFi is the most actively *contested* topic relative to its hot-feed presence — being argued about far more than it's being upvoted. Candidate for coordinated pushback.

**`privacy` — 30× amplification (1 → 3 → 1 → 30)**
One mention in bitcoin-hot. Thirty in crypto-controversial. Privacy is the single most suppressed technical concept in the corpus. Given that privacy was a central Bitcoin design goal, its near-total absence from amplified content is a strong structural signal.

**`scaling` — 20× amplification, `censorship` — 20×**
Same pattern: active in controversial, largely absent from hot. Both were dominant Bitcoin topics for years. They've been pushed out of the amplified surface entirely.

**`cold-storage` — 7× amplification (1 → 28 → 0 → 7)**
Peaks sharply in bitcoin-controversial (28 mentions) then drops to zero in crypto-hot and only 7 in crypto-controversial. Bitcoin's own community is fighting about self-custody; the broader crypto audience barely mentions it.

### The scripted narrative pairs (Pask co-occurrence)

**`scarcity ↔ store-of-value` — score 0.433, highest in the dataset.**
Every post that mentions scarcity mentions store of value. These two concepts have merged into a single unit of expression — they're no longer two ideas, they're one talking point. Appears consistently across both feeds, meaning it's a genuine ideological crystallization, not active coordination. The Bitcoin community has internalized this framing so thoroughly it's indivisible.

**`altcoin ↔ price` — score 0.410, 84 co-occurrences.**
Highest volume pair. When altcoins are discussed, price almost always follows. Less scripted than scarcity/store-of-value, more reflecting the actual structure of how the community thinks about the space.

**`censorship ↔ consensus` — score 0.387.**
Tight ideological cluster: when censorship resistance comes up, consensus rules follow. Shows up in principled arguments rather than scattered mentions — a genuine conceptual linkage, not a talking point.

**`medium-of-exchange ↔ scaling` — score 0.322.**
When someone argues Bitcoin should be used for payments, they argue for scaling. This pair lives almost entirely in controversial — it's the contested alternative to the store-of-value narrative.

### The suppression signal

`privacy`, `scaling`, `layer2`, `lightning-routing` are absent from hot feeds or appear only once. These were the dominant Bitcoin technical debates for years. Their systematic absence from amplified content — while remaining active in controversial — is measurable topic suppression.

The burst events add timing detail: `scaling` burst at 5× trailing average in W32-2025 and again in W43-2025. Both bursts appear in the controversial feed. No corresponding hot-feed burst. The community was actively inflamed about scaling twice in the past year; neither episode broke through to the front page.

This is the key asymmetry: **hot and controversial are supposed to diverge for organic reasons** (some things are popular, some things are contested). But when a concept is *persistently* active in controversial and *persistently* absent from hot over a full year, that's not random variation — it's structural suppression.

---

## Limitations

- **Post titles only** — comment text would increase signal density 5–10×. Reddit's public API rate-limits comment fetching; OAuth credentials would enable a full run.
- **Single time window** — running this quarterly and tracking *changes* in lifecycle classifications reveals campaigns in progress rather than just crystallized outcomes. A concept moving from TRANSITION_ONLY to CRYSTALLIZED over two quarters is a narrative gaining ground in real time.
- **Vocabulary coverage** — the 30-concept vocabulary targets narrative-level concepts. Finer vocabulary (specific projects, named actors, events) would catch targeted operations rather than broad narrative drift.
- **No ground truth** — structural anomalies are candidates, not convictions. The tool flags patterns; verification requires reading the actual posts.

---

## Why This Works as a Detection Method

Traditional content moderation looks at individual posts for policy violations. That misses coordinated behaviour where each individual post is innocuous but the *pattern* across posts is manufactured.

Crystallization analysis looks at **vocabulary evolution across the corpus**, not individual posts. A concept that is CRYSTALLIZED in controversial but absent from hot has a structural fingerprint that no single post would reveal. You need the population to see it.

This is why Pask's original insight applies here: learning (and manipulation) is visible in the *pattern of interactions*, not in any single interaction. The crystallization tool makes that pattern legible.

---

## Running It

```bash
# Two-epoch run: r/Bitcoin hot vs controversial
bun tools/crystallization/analyze-reddit.ts \
  tools/crystallization/config.reddit-example.json \
  --output output/bitcoin-influence

# Four-epoch run: r/Bitcoin + r/CryptoCurrency, hot vs controversial
bun tools/crystallization/analyze-reddit.ts \
  tools/crystallization/config.reddit-large.json \
  --output output/bitcoin-narrative-influence
```

Results are written as `.md` (human-readable) and `.json` (machine-readable for further analysis).
