---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/BRAINSTORM-DOCK-SHELL-SILOS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.329515+00:00
---

# Brainstorm: Dock, Shell, and the Failure of the Commerce/Productivity/Entertainment Silos

**Status:** Recovered conversational response from pre-compaction brainstorm. Captures the substantive takes that should feed the next course of action.

**Date:** 2026-04-16

---

## 1. The 1-3-5 Pyramid is What/How/Why Made Physical

The 1-3-5 Pyramid the Claude Code session was building toward is actually the what/how/why taxonomy made physical. We just hadn't named it that way.

- **WHY** — "why am I using the computer right now" — the three intents (Do / Talk / Find).
- **HOW** — "what mode of operation am I in" — the fifteen contexts.
- **WHAT** — "which object am I working with" — the fifty-seven types.

Most software today puts **WHAT** at the top of the hierarchy (this is a spreadsheet app, this is an email client, this is a calendar). Semantos inverts that stack so intent comes first, which is much closer to how humans actually think. You don't wake up thinking "I need to use my spreadsheet application." You wake up thinking "I need to make sense of last quarter's numbers" — that's **Do → Manage** with a spreadsheet object surfaced underneath.

---

## 2. Zero Friction Voice-to-Economic-Execution Collapses the Compression Gradient

Zero Friction: Voice to Economic Execution is really a statement about **collapsing the compression gradient into a single human action**.

Right now, to execute an economic action — invoicing a client, buying a domain, paying a contractor — you open an app, navigate to a screen, find a button, fill a form, submit, confirm, wait, verify. Five to twenty discrete steps.

What Semantos lets someone do is say: *"invoice Dave $500 for the plumbing job yesterday"* — and the system walks down the gradient automatically:

1. NL extracts intent and fields.
2. CLI shape becomes `offer create --to=dave --amount=500 --source=job-abc --due=2026-04-22`.
3. Lisp compiles the pricing policy into opcodes.
4. Kernel validates linearity and signs via BRC-100.
5. Invoice is a published semantic object visible to Dave within milliseconds.

The friction isn't just fewer clicks — it's that the **entire chain from intent to economic commitment is one continuous utterance**.

The dock's text+mic at tier 3 of the UI is the affordance for this. The favourites are the CLI-level compressions of common actions; the text box is raw CLI; the mic is NL. **Three levels of the gradient exposed as three input modes in one popover.** The UI itself embodies the gradient.

---

## 3. Types Are Primitives; Contexts Are Starting Points

The type classification Claude Code ran is interesting in what it reveals about the architecture. `Document` is "in" Do→Create but also surfaces in Talk→Self, Talk→Direct, Talk→Squad, Find→Memory. **That many-to-many relationship is correct and important.** Types are primitives; contexts are starting points. A Document isn't owned by Create — it's native to Create, but it appears anywhere creativity produces artifacts and anywhere recall retrieves them.

If you forced types into a strict hierarchy under contexts, you'd duplicate everything three times or create awkward abstraction layers. The favourites-per-context with free-text fallback is the right design because it matches reality: most of the time in a given context you want the common actions, but the whole type library is available when you type or speak.

This is also why `Thing` shouldn't be a favourite anywhere — it's a meta-primitive that should be reachable only through explicit intent ("create a generic thing called X"), otherwise it clutters every context.

---

## 4. Commerce / Productivity / Entertainment is a SaaS Fiction, Not a Reality

Commercial, productivity, and entertainment as separate categories is a **software-industry convention, not a reflection of how people actually use computers**.

In real life:

- Someone watching a YouTube tutorial on their phone while cooking dinner is doing entertainment (watching), productivity (learning a skill), and commerce (the platform is monetizing them) simultaneously.
- Someone playing chess against a friend for stakes is playing, communicating, and transacting at once.

The app industry fragmented these into silos because each vertical could sell a SaaS subscription. Semantos treats them as **facets of the same object system** because they share primitives:

- Every "entertainment" action creates semantic objects (game states, scores, narratives).
- Every "commerce" action produces semantic objects (offers, transactions, invoices).
- Every "productivity" action produces semantic objects (documents, tasks, events).

**The distinction was never real at the data layer; it was only real at the business-model layer.** A Game object and an Invoice object are different types but live in the same store, under the same governance, with the same evidence chain. You can pipe them. You can tax them. You can audit them. Same substrate.

---

## 5. Pipe-and-Cat for Objects = n8n Through the Shell

The pipe-and-cat for objects is where the shell as universal coordinator becomes legible:

```
semantos list --type=invoice --status=overdue \
  | semantos patch --status=chasing \
  | semantos notify --template=reminder
```

That's a three-stage workflow that in n8n would be a flowchart with nodes and connections. In the shell it's one line.

Because each object maintains its evidence chain as it passes through, the audit trail is **automatic** — by the time you get to the notify step, the object knows it was overdue, was transitioned to chasing, and a reminder was sent. All three patches appear on the object. In n8n you'd have to explicitly log each step. In Semantos it's free because the model is right.

The n8n equivalent through shell isn't harder — it's actually **easier**, because you have the full expressiveness of unix pipe composition plus typed objects plus evidence chains. A Semantos workflow is just a shell script you can save and rerun. Scheduled triggers become cron + shell invocation. Webhook triggers become the HTTP layer calling into shell commands. Everything collapses to the same primitive.

---

## 6. Verbs Have Types, and They Layer

Verbs absolutely have types, and this is already modeled in the route descriptor system. Each verb has:

- **Required argument types** (`new` requires a type path, `patch` requires an object ID, `transfer` requires source + destination + hat cert).
- **Required capabilities** (only hats with certain capabilities can invoke it).
- **Return types** (some return objects, some return receipts, some return stream handles).

**Universal business verbs sit at the core:** create, destroy, transform, transfer, publish, consume, verify, stake, dispute, resolve. These map onto linearity operations and state transitions and are common across every domain.

**Context-specific verbs layer on top:** move/forfeit/challenge for Do→Play, pay/invoice/refund for Do→Transact, reflect/journal for Talk→Self, verify/prove for Find→Truth. These are usually aliases or specializations of universal verbs with specific type contexts baked in — `pay` is really `transfer` on a PaymentChannel object.

**The core verbs are few** (ten or so primitives). **Context verbs are many** but syntactic sugar over the core.

---

## 7. Attention Surface = Personal Working Set

The attention surface as a Miro board for objects is the right metaphor, but push it further. What you're describing is a **personal working set** — the objects currently in flight for you right now. This is distinct from:

- The object store as a whole (too big, most not relevant).
- Recent-items lists (just temporal, not attention-weighted).
- Tabs (ephemeral, not persistent).

A working set has both:

- **Auto-surfaced items** — things the system thinks you should attend to: overdue tasks, incoming messages, pending approvals, objects someone else patched that you care about.
- **Pinned items** — things you explicitly want in your peripheral vision.

The horizontal/vertical splitter is how you adjust the ratio. Maybe today you want mostly auto-surfaced because you're triaging, and other days you want mostly pinned because you're executing on a known set.

**This is the "active window" at the object level, persistent across sessions.** It's also the agent's context. If an agent is operating on your behalf, the working set tells it what's current. Archive something from your working set and the agent stops considering it. **Operational hygiene becomes UI interaction.**

---

## 8. Shell is Where HOW and WHAT Meet

The shell is the right abstraction because the shell is where **HOW and WHAT meet**:

| Layer    | Shape       | Answers                                    |
|----------|-------------|--------------------------------------------|
| UI       | WHY-shaped  | "why are you here" — modes and flows       |
| Shell    | HOW-shaped  | "how do I compose actions" — verbs, pipes  |
| Database | WHAT-shaped | "what objects exist" — tables, indices     |

Each layer has its own rightful place. The mistake would be letting UI assumptions leak into the shell, or letting database schemas leak into the UI. **Keep the shell as the canonical instruction layer; let UI and database be dumb projections of it.**

That's also why subdomain-per-extension works — each subdomain is a WHY context (`shop.example.com` is "why am I here" = "to buy"), but underneath it's the same shell, same objects, same governance.

---

## 9. The Dock is Apple's Compression Gradient (They Didn't Know It)

The Dock pattern with voice+text+favourites at tier 3 is the **Apple version of the compression gradient — they just didn't know that's what they were building**:

- **Spotlight** is text compression.
- **Siri** is voice compression.
- **Dock** is favourites compression.

Our insight is to **unify these into one interaction surface** that sits at the edge of every workflow.

Things worth stealing from that direction:

- **Hover states** that show object previews without committing to open them.
- **Spring-loading** so dragging an object onto a tier-2 context reveals the tier-3 popover for that context automatically.
- **Keyboard shortcuts that mirror the mouse path** (hold `D` then `C` then `1` = Do→Create→first-favourite).

The muscle memory for power users comes from these affordances. And everything in the UI is really just invoking shell commands underneath, so the shortcuts are really just command aliases.

---

## 10. Federation: The Dock is the Action Surface of a Protocol

The last piece: how this plays with federation.

- **RSS + multicast + typehash** gives you federated publication.
- **Sessions-as-objects** give you federated identity with audit trails.
- **The 1-3-5 dock** gives you federated action surface.

Someone running Semantos on their VPS has the same Do/Talk/Find pyramid as you. When you share a Document with them, it arrives in their Find→Memory. When they respond, it arrives in your Talk→Direct. When they publish a Product, it multicasts to everyone subscribed to that typehash and appears in their Find→Market. **The UI pattern is consistent across nodes.**

This is where Semantos becomes an actual alternative stack rather than just a better app — because **the protocol is the product, and the dock is just one implementation of how to surface the protocol to humans**. Someone else could build a different UI (a command palette, a terminal overlay, a spatial VR interface) and it would talk to the same shell and federate with the same objects. That's a much bigger thing than "a better everything app."

---

## Takeaways for the Next Course of Action

1. **UI embodies the compression gradient.** Tier 3 dock popover = favourites (compressed CLI) + text (raw CLI) + mic (NL). Three gradient levels, one surface.
2. **Types ↔ contexts are many-to-many.** Favourites-per-context with free-text fallback is the right pattern. Don't force hierarchy.
3. **Kill the commerce/productivity/entertainment silos at the data layer.** Same substrate, same store, same evidence chain. Silos exist only for SaaS pricing — we're not SaaS.
4. **Pipe-and-cat objects are n8n without the flowchart.** Evidence chain is automatic. Shell scripts = workflows. Cron = scheduler. HTTP = webhooks. Collapse everything into shell.
5. **Verbs have types, and layer.** ~10 core universal verbs, many context-specific sugar verbs on top.
6. **Attention surface = personal working set.** Auto-surfaced + pinned, persistent across sessions, shared with agents as context.
7. **Don't cross-contaminate layers.** UI = WHY, Shell = HOW, DB = WHAT. Shell is canonical; UI and DB are projections.
8. **Steal more from Apple's dock.** Hover previews, spring-loading, keyboard path mirroring.
9. **The protocol is the product.** The dock is one UI implementation. Others will emerge. That's the real thing being built.

---

*This brainstorm should feed the next spec pass: UI dock affordances, verb core vs sugar split, the "object store is unified" stance (no commerce/productivity/entertainment partitioning), and the federation-surface framing for public messaging about what Semantos is.*
