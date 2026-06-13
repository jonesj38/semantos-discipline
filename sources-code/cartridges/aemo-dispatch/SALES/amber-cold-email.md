---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/aemo-dispatch/SALES/amber-cold-email.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.574686+00:00
---

# Amber Electric cold email — draft v3 (customer-trust-led, no regulatory framing)

## Why v3

v1 ended with a 30-min discovery call ask — wrong shape for Todd's position.
v2 fixed that with a deliverable-led $50k pitch but still leaned on a
"regulator-ready" frame. Friend pointed out: no auditable-dispatch legislation
exists in AU, none is realistically coming while DNSPs are state-owned, and
Power Ledger has burned 9 years and ~96% of their market cap betting otherwise.

v3 strips the regulatory angle and leans into what's *actually* sellable:
**customer-trust differentiation** for an operator whose brand is already
"we don't mark up the wholesale price, here's the algorithm". Amber's whole
business model is built on this; auditable dispatch is a straight extension
of their existing transparency pitch, not a bet on legislation.

---

## Targeting (unchanged)

**Primary:** Dan Adams, Co-founder & CEO of Amber Electric
**Backup:** Chris Thompson, Co-founder & Chief Product Officer
**Send to:** Dan, CC Chris.

---

## Subject line (pick one)

1. **"AU$50k to extend Amber's transparency story to the dispatch layer — 4-6 weeks"** ← my pick
2. "Mainnet receipts for SmartShift — turn dispatch transparency into a moat"
3. "What Amber is to retail pricing, this is to dispatch — fixed-scope POC inside"

---

## Body

> Dan,
>
> Amber's whole pitch to customers is "no markup, here's the wholesale price, here's the algorithm." That works at the **pricing** layer because the spot price is public. At the **dispatch** layer it doesn't, because no customer can independently verify that the algorithm you published is the algorithm SmartShift ran on their battery last Tuesday.
>
> I've built a framework that closes that gap. Every dispatch strategy compiles to **6 to 11 bytes of Bitcoin Script**. Every batch of dispatch decisions can be anchored on BSV mainnet as `SHA-256(strategy_hex ‖ input_data_sha256 ‖ result_sha256)` — a public, timestamped commitment. Anyone holding the txid plus your published strategy can re-execute and verify byte-for-byte.
>
> Two live mainnet anchors from my backtest harness — each verifiable end-to-end in your browser at:
>
> **https://realblockchainsolutions.com/aemo-dispatch/**
>
> One exhibit is H1 2024 NSW1 (52,416 intervals, 1 MW/1 MWh battery, net AU$54,536). The other is May–Jul 2022 QLD1 across the east-coast gas crisis (net AU$43,432). Same 10-byte predicate, two market regimes. Click "Verify on chain" on either — your browser independently re-computes the commitment hash and finds the matching bytes in the on-chain transaction script via the public WhatsOnChain API. No server on my side is involved in the verification.
>
> **The offer: AU$50,000, 4-6 weeks, fixed-scope.**
>
> - Transcribe SmartShift's existing dispatch rule as a Rúnar predicate (6-15 bytes)
> - Backtest it against 12 months of Amber dispatch data, prove byte-equivalent behavior
> - Stand up a production anchor pipeline (Bun service, runs alongside your existing stack — touches nothing in SmartShift itself)
> - Per-batch txids published to a customer-facing "verify your dispatch" page that any Amber customer can hit with their NMI and a date
> - Operator runbook + 3 months of fix-it support
> - MIT-licensed source, all of it yours
>
> What you get is the only retail-energy story in Australia where the customer can *click a link and prove* the dispatch they paid for is the dispatch you said you'd run. Tesla VPP, Reposit, Indra — none of them can claim this, because they didn't build their brand on transparency. You did. This makes that brand provable rather than asserted.
>
> Reply "send the SOW" and I'll have the one-pager back in your inbox today. If the answer is "not now," who at Amber would care about this in 6 months — I'll come back to them direct.
>
> Cheers,
> Todd Price
> [phone] · [linkedin] · semantos.ai

---

## What changed from v2 (and why)

- **Opening sentence rewritten** to lead with Amber's existing brand, not the substrate. The pitch has to start in Dan's world, not Todd's.
- **Removed "regulator or board member"** language. Replaced with "customer" — singular, specific, the actual buyer-buyer of Amber's product.
- **Removed the "static-threshold beaten 6× in the gas crisis" stat.** That was load-bearing for the regulator angle ("silent regression nobody sees until a billing cycle") but reads as fear-selling when the buyer's motivation is brand extension, not risk mitigation.
- **Added the competitor list** (Tesla VPP, Reposit, Indra). Frames this as a *competitive differentiator*, not a compliance hedge. The fight Amber is actually in is for VPP customers, not regulator approval.
- **Verify-page description sharpened**: "any Amber customer can hit with their NMI and a date." Concrete user action, not abstract "audit envelope."

## Sender notes

- **Length:** 263 words. Over the 200-word rule, but the offer + the brand-fit reasoning + the txids are all doing genuine work. Cutting further would weaken the brand-fit argument, which is the v3 thesis.
- **Hook order:** brand observation → mechanism → proof (txids) → offer → moat. Each line answers the question raised by the previous one.
- **Ask:** "Reply 'send the SOW'" — 14 keystrokes. Self-selects for serious buyers.
- **No call ask.** If they want one before signing they'll ask; offer a 15-min "watch the harness run live" only if requested.
- **Price up front.** Still right. AU$50k fits in a Series-B founder's discretionary spend without procurement involvement.

## Pre-send checklist

- [ ] Replace `[phone]` and `[linkedin]` placeholders
- [ ] Verify Dan Adams's current email (Hunter.io on amber.com.au; LinkedIn InMail backup)
- [ ] SOW one-pager (`amber-sow-v1.md`) is ready to send (regulator-framing already stripped)
- [ ] Send Tuesday/Wednesday 09:00 AEST
- [ ] Plain text in Gmail, no HTML
- [ ] Calendar reminders for day-5 and day-12 follow-up

## Follow-up cadence

- **Day +5:** one-line bump ("Did this land? I can send a 90-second screencast of the anchor pipeline running live if useful.")
- **Day +12:** different angle — **NOT the AER**, since regulators aren't buyers. Better: "If Amber's not the right fit, do you know anyone at Reposit, Indra, or one of the larger C&I battery owners (Wesfarmers, Coles) who'd want a look?"
- **No 3rd touch.** Silence after two follow-ups → move to Reposit Power, Indra Renewable, or a C&I battery owner with a transparency-curious CFO.

## Adjacent buyers if Amber says no

The brand-fit reasoning narrows the buyer list compared to v2. Best fits:

1. **Reposit Power** (AU home-battery VPP) — engineering-led, transparency-curious
2. **Indra Renewable Technologies** (international VPP, AU presence) — sells to retailers
3. **Sonnen Australia** (home battery + VPP) — German parent, audit culture
4. **Powershop** (AU retailer, has a small VPP) — challenger-brand, transparency angle
5. **C&I battery owners** with brand-conscious CFOs — Wesfarmers (Bunnings/Officeworks rooftop solar+battery), Coles, Woolworths sustainability teams

NOT good fits (don't waste energy):
- AGL, Origin, EnergyAustralia (gentailers) — too big, no transparency brand to extend, will route to procurement
- Akaysha, Vena, Pacific Green (utility BESS developers) — wrong buyer motion; they sell to gentailers, no customer-facing transparency story
- AEMO / AEMC / AER (regulators) — not buyers, no legislation, no incentive
