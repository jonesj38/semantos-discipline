---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/PIGGY-BANK-COMPANION-DESIGN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.734188+00:00
---

# Piggy Bank Companion — Design Brief

**Version**: 0.1 DRAFT
**Date**: May 2026
**Author**: Todd
**Audience**: Claude Design (handoff brief). Also for design review by anyone who has read `CSD_QUICK_REFERENCE.md`, `docs/design/HELM-ATTENTION-SURFACE.md`, the jam‑room PRDs, and `docs/paskian-learning-system-explainer.md`.
**Status**: Intent + UX brief. No code. No data‑model commitments beyond the existing `@semantos/piggybank` types it inherits.

---

## 0. Headline

> The Piggy Bank Companion is the parent‑facing iPad app that closes the loop on the BitPiggy. The child does the chore, taps the BitPiggy, and stakes a claim. The parent, on the iPad, ratifies (or doesn't) — and in the act of ratifying, pocket money settles. The Companion is also where parents shape the household — define chores, set goals, mint reward tokens that aren't money — and where the child's progress is reflected back to them as something they recognise as theirs.
>
> It is not a chore‑tracker app with payments bolted on. It is a small piece of family operating system, written in the same dialect as the Helm and the Jam Box: a 1‑3‑5‑3‑1 stack that compresses gracefully, a Paskian loop that learns the household without surveilling it, and a wallet that quietly handles BSV underneath.

---

## 1. Where This Sits

The Companion is the third surface in a family of three.

- **The BitPiggy (ESP32 device, child surface).** Already prototyped in `esp32-hackkit/examples/piggybank/`. A physical object on the child's desk. A button to claim a chore. A small screen that shows their balance and what they're saving for. Holds its own keypair, signs chore claims locally, syncs to the Companion when the parent's iPad is on the same network.
- **The Paskian kernel (substrate).** Already in `core/pask`. The household is a small Paskian graph: chore concepts, kid concepts, goal concepts, reward concepts, time concepts. Co‑occurrence reinforces edges. Stable threads (Pask's notion of *learned*) are how the system knows that "Tuesday + bin night + Lily = high constraint weight" without anyone ever programming a rule.
- **The Companion (iPad app, parent surface).** What this brief is about. A Flutter app that talks to the BitPiggy fleet over local Wi‑Fi, holds the parent‑side wallet (WASM, the same kernel‑isolation WASM build that ships in `runtime/wasm`), and renders the household at three levels: *what's pending right now*, *what each child is working on*, and *how the household is moving over weeks*.

Everything semantic flows through the same `@semantos/piggybank` types that already exist (`ChoreTemplate` as RELEVANT, `ChoreClaim` as LINEAR, `ChoreApproval` as LINEAR, `BonusQuest` as AFFINE, `SavingsGoal` as device state). The protocol layer is solved. This brief is about the surfaces.

### Parallels we are deliberately drawing on

- **Helm (`docs/design/HELM-ATTENTION-SURFACE.md`).** The Companion's home view *is* a household attention surface. It is not a feed of every event — it is an inferred ranked list of *what to look at next*. A pending claim, a child who is two days from a goal, a reward token about to expire, a Tuesday‑evening "the bins" reminder that history says you act on between 17:30 and 18:30. The same five‑factor scoring shape (recency / deadline / active‑work / goal‑alignment / pending‑action) maps almost line‑for‑line.
- **Jam Box (`docs/prd/jam-room/`).** The Companion is the jam room of family work: an instrument that is playable first, programmable second, semantic underneath. A parent should be able to ratify a stack of pending claims in the same gesture economy as a producer punching pads — quick, low‑friction, with the substrate quietly recording lineage and signed proofs.
- **Conscious Stack Design (1‑3‑5‑3‑1).** The pyramid is a budget, not a metaphor. We use it twice — once for the parent surface (iPad), once for the child surface (BitPiggy). The compression gradient peels from the bottom up, the same way the jam‑room compresses from desktop to phone.
- **Paskian conversational loop.** The Companion is the parent's side of an ongoing conversation with the household. Not a chat — a turn‑taking pattern of claims, ratifications, goal updates, reward redemptions, and the ambient drift of which chores stick and which don't. The kernel makes that drift legible.

---

## 2. Who This Is For

Two personas, one shared surface.

### Parent — "Sam"

Has 1–4 children aged 5–12. Owns the iPad. Wants their kids to internalise the connection between effort and outcome without turning every dinner into a negotiation. Doesn't want to think about Bitcoin. Will tolerate (and probably eventually like) the fact that the system is durable, signed, and not at the mercy of a SaaS company; will not tolerate a UI that demands they understand any of that to use it. Reads at adult level, multitasks, often runs the app one‑handed while doing something else. Will use the app in two‑minute bursts, mostly evenings.

### Child — "Lily" / "Theo"

Ages 5–12. The 5‑year‑old can read pictures and her own name; the 12‑year‑old is fluent and self‑directed. They each have a BitPiggy. The Companion mostly belongs to the parent — but the child sees themselves reflected on it: their goals, their balance, their streak, their unredeemed reward tokens. The "kid view" of the iPad app is a read‑mostly mode the parent can hand the iPad over to without worrying about chaos. **The child *acts* on the BitPiggy, not on the iPad.** That separation is load‑bearing for both psychology (Section 3) and security.

---

## 3. Empirical Grounding (Child Psychology)

The design is informed by four mature lines of evidence in developmental and behavioural psychology. None of these is a single‑study fashion; all are widely taught and replicated. The brief is honest where the evidence is contested.

### 3.1 Self‑Determination Theory — autonomy, competence, relatedness

Deci and Ryan's framework is the spine. Sustained motivation in children rests on three psychological needs: a sense of agency over what they do (autonomy), a sense that they are getting better at it (competence), and a sense that the people who matter notice (relatedness). Pocket money is one extrinsic input; the design must not let it crowd the other three.

**What this means for the Companion.** The child *chooses* which chores to claim and in what order, where the household allows it. Streaks and goals are visible to the child as a competence cue (not as a leaderboard against siblings). Parental ratification is shown to the child as *being seen* — a short, real comment from a real parent ("nice job — I noticed you did the bins without me asking") is worth more than a green tick. The reward‑token system (Section 9) exists precisely so the household has currencies that aren't money — a Friday movie pick, a sleepover token — that lean into relatedness rather than pure exchange.

### 3.2 The over‑justification effect — and why we ration it

Lepper, Greene, and Nisbett (1973) and many follow‑ups have shown that paying children for things they already do for fun can erode the intrinsic motivation. The mechanism is straightforward: if I draw because I enjoy it, and you start paying me to draw, I begin to read my own drawing as work, and the enjoyment dims.

**What this means for the Companion.** The default chore set is *household contribution*, not enrichment. The app should resist the parent's instinct to put everything on the chore wheel. Two design moves:

- A "this is its own reward" toggle on each chore template — the parent can mark chores that should *not* pay sats, only build streak and earn reward‑token credit.
- A friendly nudge in the chore‑creation flow when a parent tries to tokenise something a child does for free. Not a lecture; a single sentence: *"Some kids stop enjoying things they get paid for. Want to leave this one off the money side?"* Then it gets out of the way.

### 3.3 Token economies — what the clinical literature actually says

Token economies (Ayllon & Azrin and the long applied‑behaviour line that followed) work — when the tokens are immediate, when the redemption is concrete and the child cares about it, and when the token‑to‑reward ratio is stable enough that the child can plan against it. They fail when redemption is delayed, vague, or politically hostage to parental mood.

**What this means for the Companion.** Sats payout from an approved claim should be **immediate** at the protocol level (the BitPiggy gets a settled receipt before the kid leaves the room) even though the underlying BSV anchor is asynchronous. Reward‑token redemption must be calendar‑backed: a "movie night vote" token has a real Friday it gets spent on, not a vague future. Parents can see (and the system can softly warn about) a household where ratification is consistently delayed past 24 hours — that is the early signal of a token economy starting to fail.

### 3.4 Scaffolding and the zone of proximal development

Vygotsky's framing — children grow in the band just above what they can already do alone, when an adult supports the next step — is why the BitPiggy is age‑graduated and why goals are a first‑class object. A 5‑year‑old's screen says *"Make your bed → 10c"* with a picture; a 12‑year‑old's screen says *"$8 to your skateboard goal — 4 weeks left at this pace"*. The scaffolding that makes the second sentence legible to a 12‑year‑old is the cumulative experience of doing the first one.

**What this means for the Companion.** Each child profile has an age band that drives reading level, iconography density, money representation (cents vs dollars), and goal complexity. The parent can override; the default tracks chronological age within the 5–12 range. New children boot at the lower end of their band and the system raises the ceiling as the child acts.

### 3.5 What we are *not* claiming

Not claiming the Companion will improve any clinical outcome. Not claiming any specific multi‑week behavioural lift. Not claiming the marshmallow test is a serious framework for a household app (it is famous and contested, and we mention it only to note we're not building on it). The grounding above is sufficient to design a coherent app; it is not a clinical‑outcomes claim.

---

## 4. The Pyramid — Companion (iPad)

Apply 1‑3‑5‑3‑1 to the parent surface. This is the analogue of the jam‑room's compression gradient (`docs/prd/jam-room/design/CSD-COMPRESSION-GRADIENT.md`), oriented for family work.

```
                     L1 — 1 ANCHOR
                     ┌─────────────────────────────┐
                     │   PENDING REVIEW            │
                     │   (the next claim that      │
                     │    needs you, with the      │
                     │    child's name and proof)  │
                     └─────────────────────────────┘

                     L2 — 3 ACTIVE  (the household trinity)
            ┌──────────────┬──────────────┬──────────────┐
            │   CHILDREN    │   CHORES     │  REWARDS &   │
            │  per‑child    │  templates   │   GOALS      │
            │  cards        │  & schedule  │  tokens, jars│
            └──────────────┴──────────────┴──────────────┘

                     L3 — 5 SUPPORT  (reach when needed)
       ┌─────────┬─────────┬─────────┬─────────┬─────────┐
       │ HISTORY │ STREAKS │ BONUS   │ FAMILY  │ WALLET  │
       │ /lineage│ & insts │ QUESTS  │ SETTINGS│ & SPV   │
       │         │         │ (AFFINE)│         │         │
       └─────────┴─────────┴─────────┴─────────┴─────────┘

                     L4 — 3 INFRASTRUCTURE  (invisible)
            ┌──────────────┬──────────────┬──────────────┐
            │   IDENTITY    │  TIME &      │ PERSISTENCE  │
            │  parent /     │  CALENDAR    │  CAS / anchor │
            │  child certs  │  (Pask clock)│  / sync queue │
            └──────────────┴──────────────┴──────────────┘

                     L5 — 1 DEVICE
                     ┌─────────────────────────────┐
                     │  THE iPAD                   │
                     │  (one‑handed evening use,   │
                     │   touch + voice)            │
                     └─────────────────────────────┘
```

### Why each row passes the Sincerity Filter

- **L1 = Pending Review, not "Home".** A household app whose anchor is a generic dashboard fails the Sincerity Filter. The single thing the parent opens this app for, more often than anything else, is *did one of the kids claim something I now have to look at?* L1 always shows the next claim awaiting ratification — child, chore, time, optional photo proof, the buttons "Approve" / "Approve with note" / "Not yet". If there are no claims, L1 shows the most useful adjacent thing (a goal close to landing; a token about to expire) — never blank chrome.
- **L2 = Children, Chores, Rewards & Goals.** The trinity of family administration. *Children* is the per‑kid card — balance, streak, current goal, recent claims. *Chores* is the template library and the weekly schedule. *Rewards & Goals* is where parent‑defined reward tokens are minted and managed, and where each child's savings goals are visible. These three are the only top‑level navigation; everything else is L3.
- **L3 = History, Streaks, Bonus Quests, Settings, Wallet.** Five supports, one bench each. *History* is the chain of approved claims with parent comments — the family's ledger as a story. *Streaks* exposes the streak‑bonus configuration per chore. *Bonus Quests* is the AFFINE one‑off mechanism — "Saturday lawn = $5, expires Sunday night". *Settings* covers household, child profiles, age bands, devices. *Wallet* is where the parent funds the household pot and inspects on‑chain anchoring; it is deliberately L3, not L1, because the Companion is a household app first and a wallet second.
- **L4 = Identity, Time/Calendar, Persistence.** The three Loom invariants, collapsed for this domain. The parent never sees these directly. Identity = the parent and child certificates, family‑sync keys (`FAMILY_SYNC` domain). Time/Calendar = the Pask‑backed sense of "Tuesday evening" that powers schedules and streak rollovers. Persistence = the local‑first sync queue, BEEF anchoring, the BitPiggy peer.
- **L5 = the iPad.** The literal device. The Companion targets a 10–13" iPad in landscape and portrait, one‑handed friendly, with a voice path (Section 7) for hands‑busy moments.

### Compression — Companion on iPhone

The Companion is iPad‑first; an iPhone build is a real second‑class surface (the parent's phone in the supermarket, etc.). Apply the peel‑from‑bottom rule:

| Surface | Surfaced layers |
| ------- | --------------- |
| **iPad (full)** | L1 + L2 + L3 (inline) + L4 (hover‑HUD only) |
| **iPhone (compressed)** | L1 + L2 (bottom 3‑tab bar) + L3 (overflow) + L4 (hidden) |

A child should never have a Companion install on their own phone. The Companion is a parent surface; the child surface is the BitPiggy.

---

## 5. The Pyramid — BitPiggy (child)

The BitPiggy is the L5 device of the Companion stack, but it has its own internal pyramid. Worth saying out loud so designers know what each surface owes the other.

```
   L1 — 1 ANCHOR        BALANCE + WHAT I'M SAVING FOR
   L2 — 3 ACTIVE        TODAY'S CHORES   |   GOAL JAR   |   REWARD TOKENS
   L3 — 5 SUPPORT       streak / bonus quest / approval pings / history / parent comment
   L4 — 3 INFRA         identity / clock / sync (all invisible)
   L5 — 1 DEVICE        the BitPiggy itself
```

The BitPiggy *cannot* show L4. The 5‑year‑old's BitPiggy compresses to L1 + L2; the 12‑year‑old's BitPiggy adds L3. Same compression rule.

---

## 6. Language and Tone

A short style guide. The Companion is in the same household register as the Jam Box's "playable first, programmable second": warm, plain, never cute, never patronising. The BitPiggy is a half‑step lighter for the child surface.

### Companion (parent)

- **Plain English. Short verbs.** "Approve", "Not yet", "Add a chore", "Pay out", "Set goal". Never "ratify", "settle", "anchor", "submit transaction".
- **Money is dollars and cents to the parent**, sats only in the Wallet support panel. The unit *can be* configured in Settings; default is the household's local currency, displayed conventionally.
- **Speak about the child by name, not by role.** "Lily's claim" not "Child #2's claim".
- **No celebratory exclamation marks on payment screens.** Neutral confirmation. Celebrating money exchange between parent and child is the wrong register.
- **No gamification creep.** No XP, no levels, no badges, no leaderboards across siblings. Streaks are a competence cue, not a scoreboard. There is no global score.
- **Never use "blockchain", "crypto", "BSV", or "Bitcoin" in any default surface.** They appear only inside the Wallet support panel and only when the parent goes looking. The household runs on "pocket money" and "tokens"; the substrate is invisible.

### BitPiggy (child)

- **Reading age tracks the child's age band.** A 5‑year‑old's BitPiggy uses one‑word labels and large icons; a 12‑year‑old's uses sentences.
- **Friendly, not infantilising.** "Made your bed?" not "Hooray, did you do your job today, sport?".
- **The child sees the parent's note when a claim is approved.** This is a relatedness moment, not a notification — it should look hand‑written, not boxed.
- **No emoji storms.** A small set of glyphs (chore icons) maps consistently across both surfaces. Same icon for "make bed" on the iPad as on the BitPiggy.

### Voice (both surfaces, future‑facing)

The Companion has a voice surface ("Hey, what's pending?", "Approve Lily's bins claim with a note"). It draws on the same Voice‑Shell grammar as `WALLET-VOICE-SHELL-GRAMMAR.md` but with a household vocabulary. Voice is L3 from Phase 1; the brief flags it as a deliberate adjacency, not a launch surface.

---

## 7. Core Flows

Five flows are load‑bearing. Each is described at intent‑and‑UX level — no schemas, no widget trees. Each ends in a *what success feels like* line that the design polish should be measured against.

### 7.1 Kid claims a chore (BitPiggy)

The child finishes the chore, walks to the BitPiggy, picks the chore from a short list, presses claim. The BitPiggy shows a brief "claim sent — waiting for [Parent Name]" state. If the parent ratifies within a few minutes (network online), the screen updates — "approved! +$0.50" — and the parent's note appears. If the parent isn't online, the BitPiggy sits patient; nothing escalates, the child does not get a phone notification on a parent's phone they don't have.

*Success feels like:* the child gets a quiet sense of "I did a thing, and it landed". No fanfare, no negotiation, no hovering for adult attention.

### 7.2 Parent ratifies a claim (Companion)

The parent picks up the iPad. L1 shows the oldest pending claim. Two‑thirds of the screen is the child's name, the chore, when they claimed it, and any photo proof the chore template required. One thumb‑sized button — *Approve* — pays out. A second — *Approve with a note* — opens a one‑line text field that ships the note back to the BitPiggy. A third — *Not yet* — opens a two‑line reason box that sends a soft message to the BitPiggy ("Mum says the bin lid wasn't shut — please fix and re‑claim"). The parent never has to type the child's name; never has to confirm the amount; never has to choose between a sat number and a dollar number.

If multiple claims are pending, *Approve* advances to the next; the parent can clear five claims in fifteen seconds without ever seeing the inside of the wallet. If a claim is being held more than 24 hours, the L1 banner softens to a reminder — *"Lily has been waiting since Tuesday morning"* — because delayed ratification is the failure mode of a token economy (Section 3.3).

*Success feels like:* a parent who happens to glance at the iPad after dinner taps three times and the household's evening is settled.

### 7.3 Parent shapes the household (Companion)

In *Chores*, the parent creates and edits chore templates: name, icon, schedule, base reward (sats and/or "is its own reward"), which kids it applies to, whether it requires a photo proof, whether it requires manual approval. In *Rewards & Goals*, the parent mints reward tokens (Section 9), edits the household's goal jars, and sets per‑child savings goals.

The chore creation flow is short by default and gets longer only on demand. The first screen asks four things: name, icon, base value, who. The second screen — collapsed by default behind "more options" — exposes schedule, photo‑proof, streak rules, requires‑approval, and the over‑justification nudge from Section 3.2.

*Success feels like:* a parent can sketch a new chore in under thirty seconds and only feels the weight of the system when they want to.

### 7.4 Reward‑token redemption (both surfaces)

The child has earned three "Friday Movie Pick" tokens. On Friday afternoon, the BitPiggy nudges *"You have 3 movie picks — use one tonight?"*. The child taps yes. The Companion shows the parent a small unobtrusive item in L3: *"Theo wants to spend a Movie Pick — confirm?"*. Parent taps confirm. The token is consumed (LINEAR semantics — it cannot be double‑spent), and the household calendar entry for Friday night is augmented with "Theo's pick".

The redemption is *event‑backed*, not vague: a token always has a specific concrete redemption surface — a calendar slot, a parent‑defined activity, a vote. This is the discipline from Section 3.3.

*Success feels like:* the child knows what each token actually buys, and the moment of redemption is something both child and parent recognise as real.

### 7.5 Saving toward a goal (both surfaces)

A child sets a savings goal (with parental approval for goals over a configurable amount). The BitPiggy's L1 anchor shows the goal jar — "Skateboard, $42 of $80, 4 weeks at this pace". Each approved chore that pays sats fills the jar according to the child's saving rate (configurable per child, default 30 % to goal, 70 % spendable). On the Companion, the parent sees each child's goal trajectory in *Children > Lily > Goals*; if a goal stalls for more than 14 days, the system surfaces it gently in L1 so the parent can talk to the child rather than letting the goal die quietly.

*Success feels like:* a goal that the child reaches feels earned, and a goal that a child gives up on doesn't disappear silently — it gets a conversation.

---

## 8. The Paskian Loop — How the Household Becomes Legible

The substrate is `core/pask`. The household is a small graph where nodes are children, chores, days‑of‑week, time‑of‑day bands, goals, and reward tokens; edges are constraint weights between them, reinforced every time they co‑occur in a real claim or ratification.

What this gives the Companion that a CRUD app cannot:

- **The attention engine knows what's "due"** without a hand‑coded rule. If the household's actual history is that "the bins" co‑occurs with Tuesday evening + Lily about 80 % of the time, the L1 anchor on Tuesday at 17:30 will surface the bins‑claim slot before it has been claimed, as a soft preview ("Lily usually claims this around now"). If the pattern stops — the child takes a break, the parent rotates the chore — the edge's delta trend goes negative and the prediction quietly dims. The system never *insists*.
- **Streak and goal weights drift toward what actually motivates this child.** Same shape as the Helm's Phase 39B+ weight learner, applied to household engagement. If Theo consistently engages with goal‑progress notifications and ignores streak cues, the BitPiggy's L1 leans goal‑heavy for him. If Lily is the opposite, hers leans streak‑heavy. Per‑child profiles are signed cells; the parent can inspect and roll back drift in *Settings > Family > Reset Profile*.
- **Bonus Quests (AFFINE) are scheduled by the system as well as by the parent.** When a chore template's edge weights to a particular kid go cold, the system can offer the parent a one‑tap "Post a Saturday bonus quest?" suggestion to revive engagement. The parent always confirms; the system never autonomously posts.

The parent never sees the word "Pask". They see *Insights*, an L3 panel inside *Settings*, that exposes "what the household has learned" in plain language: *"Lily's evening chores have stabilised — she does them between 17:00 and 18:30 most days. Theo's morning chores haven't found a stable time yet."* That sentence is the human‑readable rendering of stable‑thread status from the kernel.

This loop must be **legible and reversible**. Same principle as the Helm: the operator can inspect the current weight map and roll back drift via REPL. For the Companion, the equivalent is *Settings > Family > Reset Profile* per child.

---

## 9. Token Model — Sats and Reward Tokens

Two currencies, one app. Both are first‑class semantic objects on the same substrate.

### 9.1 Pocket money (sats)

Approved chore claim → BSV sats credited to the child's `PAYMENT_RECEIPT` address, anchored on the parent's wallet. Internally sats; presented to parent and child as the household's local currency. Spending limits are per child (`SpendingLimits` from `chores.ts`); above the per‑transaction or per‑day cap, the BitPiggy queues a `SPENDING_AUTH` co‑signature request that surfaces on the Companion.

The parent funds the household pot by topping up the parent wallet. Funds flow on approval, not on top‑up. There is no "kid balance held by the app" abstraction — the kid genuinely owns their sats and the BitPiggy holds the receiving keys.

### 9.2 Reward tokens (parent‑defined)

The parent can mint named non‑monetary tokens. The model is two‑axis:

- **Linearity.** *LINEAR* tokens (a "Movie Pick" — exactly one claim, consumed on redemption). *AFFINE* tokens (a "Sleepover Pass — expires Sunday" — can be consumed or can expire). *RELEVANT* tokens (a "Weekly Allowance Boost" — always available, parent can revoke).
- **Redemption surface.** Each token must declare *what it actually does*. A movie‑pick redeems to a calendar entry. A sleepover pass redeems to an event. A "screen‑time minutes" token decrements a household timer. A "later" token has no concrete redemption — and the system warns the parent at mint time that vague‑redemption tokens are the failure mode of a token economy (Section 3.3).

The set of redemption surfaces is small and shipped — calendar slot, event, vote, custom note — and each one has a defined ratification flow on the Companion. The parent does not write redemption logic; they pick from a menu.

### 9.3 Why both

Sats give the child a real‑world currency (food trucks, charity, online stores that take BSV) and lessons in saving. Reward tokens lean on relatedness and autonomy — they *aren't money*, they're agreements. The intent is that most households gravitate to a mix where money handles the impersonal and tokens handle the relational, which is the right shape for the over‑justification literature (Section 3.2).

---

## 10. Voice and Hands‑Busy Moments

Flagged for adjacency, not for v1.

The Companion borrows the Voice‑Shell grammar pattern (`WALLET-VOICE-SHELL-GRAMMAR.md`) for short voice intents:

- *"What's pending?"* → reads out L1.
- *"Approve Lily's bins claim with a note that says: nice job."* → ratifies and ships the note.
- *"Post a Saturday lawn quest, $5, until Sunday night."* → drafts a Bonus Quest and waits for tap confirmation.

Voice is opt‑in, family‑local (the iPad's microphone, not a cloud), and always confirms an action before it commits. The same intent surface routes to the same handlers as the touch UI.

---

## 11. Privacy, Safety, and the Things We Won't Build

- **No social graph beyond the household.** No friends, no leaderboards across families, no public profiles. The substrate supports it; the Companion will not surface it.
- **No photo‑proof storage in the cloud.** Photo proofs of chores are hashed onto the chain (the `proofHash` field is already there) but the photo itself lives only on the BitPiggy and the iPad's local CAS. The hash is enough to prove the photo existed at claim time; nothing requires the photo to be uploaded.
- **No marketing of unredeemed sats.** The Companion will not show the parent "your kids have $X in unspent sats — here's what they could buy". That is the wrong relationship.
- **No auto‑posting of bonus quests.** The Paskian loop suggests; the parent confirms.
- **No access control delegation.** A child cannot grant another child a token or a chore. Only parents shape the household.
- **No "quick win" reward defaults that override the over‑justification nudge.** Designers should resist the pressure to ship a starter pack of "earn $5 for sleeping" chores. The default chore set is contribution, not enrichment.
- **No notifications competing for the child's attention.** The BitPiggy is always the child's primary surface. The iPad is the parent's. We do not push to a child's phone.

---

## 12. Open Questions for Design Polish

The doc above is firm on intent and language. The following are open and explicitly handed to design.

`TODO(design)`:

1. **Visual identity for L1 on the Companion.** The pending‑claim card is the most‑seen surface in the app. What does it actually look like at rest, with one claim, with five? How is "more behind this" suggested without crowding?
2. **Photo proof presentation.** Same card, but with a photo. How do we show the photo so the parent can read what it actually shows in two seconds without it taking over?
3. **Chore icons.** A unified glyph set for the 30 most common household chores, legible at BitPiggy resolution and iPad resolution. Whose iconography style do we draw on?
4. **The "is its own reward" toggle.** Where does this live in the chore creation flow so it doesn't feel like a moralising checkbox?
5. **Reward‑token visualisation on the BitPiggy.** A child has 3 movie picks and a sleepover pass. How does that read on the small screen? Are these jars, cards, glyphs, or something else?
6. **Multi‑kid contention on a single Companion.** Two pending claims from two kids landing five seconds apart. Does L1 stack them, or batch the second behind a small badge?
7. **Goal trajectory rendering.** "$42 of $80, 4 weeks at this pace" can be a bar, a curve, an honest scatter. The shape should feel like progress, not surveillance.
8. **Tone of the over‑justification nudge.** One sentence, friendly, never schoolmarmy. Worth several drafts.
9. **The parent's note as a handwritten artefact on the BitPiggy.** How do we make it feel personal — typography, animation, colour — without it becoming twee?
10. **The "stalled goal" gentle surfacing.** L1 banner copy that opens a conversation, not a guilt trip.
11. **Voice surface look.** When the parent says *"approve Lily's claim with a note"*, the iPad should make the voice‑intercepted action visible and reversible without being modal.

---

## 13. What This Brief Is Not

- Not an engineering PRD. Schemas and flows already exist in `@semantos/piggybank`; the WASM wallet integration follows the same pattern as `apps/oddjobz-mobile/`; the BitPiggy firmware is in `esp32-hackkit/examples/piggybank/`. None of those are restated here.
- Not a brand brief. Naming, colour, type system, motion are open and tagged for design.
- Not a parenting manual. The empirical grounding in Section 3 is enough to design a coherent app; it is not a clinical claim and not a promise of behavioural outcomes.

---

## 14. Coda

The Piggy Bank Companion is a small piece of family operating system. The design discipline is the same one we apply to the Helm and to the Jam Box: *the pyramid is a budget, not a metaphor*; if a thing on screen does not serve the user's cognition at its layer, delete it. The Paskian kernel is what lets us build a small app that learns the household without becoming a surveillance object — because the learning is local, legible, and reversible.

Pocket money done well is one of the few daily rituals where children get to *feel* the connection between effort and outcome. The Companion should make that ritual lighter for the parent and more dignified for the child. Everything else is decoration.

---

## Appendix A — One‑page summary for handoff

- **Product**: Piggy Bank Companion — iPad app, parent surface for the BitPiggy fleet.
- **Stack**: Flutter on iPad (with iPhone as compressed second surface). WASM wallet (BSV). `@semantos/piggybank` types. `core/pask` substrate. BitPiggy device on ESP32‑S3.
- **Pyramid**: L1 Pending Review · L2 Children / Chores / Rewards & Goals · L3 History / Streaks / Bonus Quests / Settings / Wallet · L4 Identity / Time / Persistence (invisible) · L5 the iPad.
- **Anchor (L1) is non‑negotiable**: the next claim that needs the parent. If none, the most useful adjacent thing.
- **Two currencies**: pocket‑money sats + parent‑defined reward tokens (LINEAR, AFFINE, RELEVANT).
- **Psychology spine**: Self‑Determination Theory, with active mitigation of the over‑justification effect, immediate token redemption, and Vygotskian age scaffolding.
- **Paskian loop**: the household becomes legible to itself — what chore lands when, with which kid — and the system surfaces this as plain‑English Insights, never as "AI".
- **Out of scope for the design**: schemas, engineering PRD, brand identity, parenting claims, social features.
- **Doc is firm on**: intent, language, layer budget, what we will not build.
- **Doc is open on**: visual identity, iconography, motion, edge cases listed in Section 12.
