---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/aemo-dispatch/SALES/localvolts-cold-email.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.574276+00:00
---

# Localvolts cold email — v1

## Targeting

**To:** Jitendra Tomar, Founder & CEO, Localvolts
**Email:** jitendra@localvolts.com
**j@ pattern confirmed via About page / Hunter.io cross-check**

---

## Subject line (pick one)

1. **"AU$50k to put cryptographic per-trade proofs on Localvolts — 4-6 weeks"** ← my pick
2. "2 bytes of Bitcoin Script per trade — Localvolts matching engine becomes auditable"
3. "What Power Ledger spent 9 years trying to build — it's already inside Localvolts"

---

## Body

> Jitendra,
>
> "Individuals prefer to make their own decisions, and given the right tools and information, will do so." You built an entire market on that sentence. The whole Localvolts model is trust-through-transparency: no markup, no black box, you see the price and you choose.
>
> Here's the one layer that doesn't hold yet: buyers and sellers trust *you* that the match ran as your algorithm specified. That trust is asserted, not provable. In a P2P market where your whole pitch is "you're in control," the matching engine is still a black box to the people it serves.
>
> I've built what closes it. Your matching predicate — buyer bid ≥ seller ask — compiles to **2 bytes of Bitcoin Script**. Every matched trade can be anchored to BSV mainnet as a single SHA-256 commitment: `SHA-256(predicate_hex ‖ order_data_sha256 ‖ result_sha256)`. Either party can re-run the same 2-byte predicate against the published order state and confirm the on-chain txid was paid for a run that matches — independently, without asking you.
>
> Live proof — your own matching logic, verifiable in-browser right now:
>
> **https://realblockchainsolutions.com/localvolts/**
>
> **The offer: AU$50,000, 4-6 weeks, fixed-scope.**
>
> - Formalise your matching predicate as an auditable Rúnar predicate (already 2 bytes)
> - Per-trade anchor pipeline (Bun service, runs beside your existing stack — zero changes to the matching engine)
> - Buyer/seller "verify your trade" page: enter trade ID, get txid, click verify — done
> - Operator runbook + 3 months support
> - MIT-licensed source, all yours
>
> Power Ledger spent 9 years and roughly 96% of their market cap trying to build what you already have operationally. This is the 32-byte layer that makes it cryptographically provable — no legislation required, no regulator needed, just a timestamped on-chain commitment that neither side can dispute.
>
> Reply "send the SOW" and I'll have it in your inbox today.
>
> Cheers,
> Todd Price
> [phone] · [linkedin] · semantos.ai

---

## Word count and structure notes

~260 words. Slightly over the 200-word ideal but every sentence is load-bearing:

- **Para 1:** His own words back to him. Establishes I actually read the site, not a mass send.
- **Para 2:** Names the gap in his model precisely — the trust is at the *matching layer*, not the pricing layer. That's the insight that differentiates this from "blockchain for energy" hype.
- **Para 3:** Mechanism in one paragraph. 2 bytes is the hook — Power Ledger built an entire protocol; this is 2 bytes.
- **Para 4:** Live proof link. Click-to-verify, no server involved on my side.
- **Para 5:** Bullet list. Scope + price up front; "zero changes to the matching engine" is the objection-kill.
- **Para 6:** Power Ledger comparison. Sole founder, probably gets pitched by PL-adjacent people constantly. This names the comparison and inverts it.
- **Ask:** "Reply 'send the SOW'" — 14 keystrokes, self-selects serious buyers.

## Why this beats the Amber pitch

- Jitendra is a sole founder who builds his own matching engine — no committee, no VP of Product to convince first
- The trust gap is *more acute* in a P2P market: it's between two paying customers who may not trust each other, not between an operator and a regulator
- The Power Ledger comparison is uniquely apt for Localvolts (they have AEMO licence + operational P2P market; PL tried to build exactly that for 9 years)
- His stated values are literally the product pitch ("individuals prefer to make their own decisions")

## Pre-send checklist

- [ ] Replace `[phone]` and `[linkedin]` placeholders
- [ ] Confirm jitendra@localvolts.com still resolves (last checked 2026-05-26)
- [ ] Complete Task #47: anchor the demo trade, update localvolts.html Exhibit 2 with real txid
- [ ] localvolts-sow-v1.md ready to send on "yes"
- [ ] Send Tuesday/Wednesday 09:00 AEST
- [ ] Plain text in Gmail, no HTML

## Follow-up cadence

- **Day +5:** one-line bump — "Did this land? Happy to do a 10-minute screen share where you watch the anchor pipeline run live against your own match format."
- **Day +12:** different angle — "If timing's wrong, do you know anyone at AGL/Origin/EnergyAustralia building a P2P retail product? I'll go to them direct."
- **No 3rd touch.** Silence → move to Reposit, Sonnen, or a C&I battery owner.

## Adjacent buyers if Localvolts says no

1. **Reposit Power** — engineering-led VPP, transparency-curious
2. **Sonnen Australia** — German parent, audit culture, home battery VPP
3. **Amber Electric** — already has the transparency brand (Amber pitch in amber-cold-email.md)
4. **Powershop** — challenger-brand, small VPP, transparency angle
5. **Any C&I battery owner** with a transparency-curious CFO (Wesfarmers, Coles, Woolworths sustainability)
