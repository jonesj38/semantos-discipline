---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/02-llm-failure-modes.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.648722+00:00
---

# What Goes Wrong with LLM-Driven Systems

Part I of this textbook is motivational. It does not present the substrate in detail. It
presents the problem the substrate exists to solve, in enough depth that the design choices
in Parts II–VIII are legible rather than arbitrary.

This chapter describes what goes wrong when a large language model is treated as the
execution front-end of a system — as the component whose output directly becomes action.
The failure modes are not exotic. They are predictable from first principles, and they have
been observed repeatedly across every class of deployment that places an LLM in the
execution path without typed, inspectable intermediate forms between the user's intent and
the state change.

The chapter closes with a worked example — a tenant reporting a broken door hinge — that
makes the failure modes concrete and introduces the structural concept that the rest of this
book answers: the compression gradient.

---

## The Standard Architecture and Its Shape

Most LLM-driven systems share a structural shape, regardless of the specific model or
framework involved. A user provides input in natural language. The system passes that input
to a model, possibly augmented with context about available tools and prior state. The model
produces a structured output — a function call, a JSON payload, a plan, a command — which
the host runtime executes against external state.

Variations exist. Modern LLM agent frameworks add a planner layer, a separate executor, a
verification step, or a retrieval pass. Some systems add a second model to check the first.
Some constrain the model's output schema at decoding time to prevent syntactic malformation.
Each of these mitigations is well-motivated. None of them changes the structural fact at the
centre of the architecture: **the model's output is directly executed**. There is no typed
intermediate form that the system can independently inspect, refuse, or ratify before
execution proceeds.

This shape has a name in compiler literature: a one-pass lowering. The input — natural
language — goes directly to the output — an action in the world — without passing through
layers the system can reason about independently. Compilers abandoned one-pass lowering
decades ago, because it produces systems that are fragile, unverifiable, and opaque when
they fail. LLM-driven system design has, largely, not absorbed this lesson.

The practical consequence is that every failure in this architecture presents as a binary
event. The system either did the right thing or it did not. There is no intermediate
structural form where the failure can be located, diagnosed, and corrected. The model is the
gradient. When the model is wrong, the system is wrong, and there is nothing between the
model and the world that the system could have caught it.

---

## Five Paths, Five Shapes, Four Without a Kernel

The cost of not having a canonical execution path is not hypothetical. Consider the actual
state of a representative runtime that supports multiple input modalities — natural language,
shell commands, UI events, network frames, and governance flows. Each modality works. But
each works differently:

| Path | Express intent | Authorise | Compile to bytes | Execute and record |
|---|---|---|---|---|
| Natural-language chat | LLM JSON | none | for display only | JSON object store |
| Shell verb dispatch | parser to `ShellCommand` | partial capability check | per-verb handler | per-verb mutation |
| UI buttons | direct method calls | none | none | reducer mutation |
| Network frames (host command) | `HostCommand` | trust-tier + cert sig | full path | yes — kernel |
| Governance flows | `Ballot`, `Stake`, `Dispute` types | per-flow ad-hoc | none | reducer mutation |

Five paths. Five different shapes. Five different authorisation models. Four of those five
paths never reach the kernel — the component that is specifically designed to enforce
linearity, authorisation, domain isolation, and cryptographic provenance. The kernel exists.
It runs. It enforces. But almost nothing in the runtime goes through it, because there is no
canonical path that everything rides on.

The network-frame path (the host command path) is the existence proof that the full pipeline
can be wired: intent expression through trust-tier checks through compilation through kernel
execution through cryptographic receipt. That path works. The open question — the one this
book answers — is why every other path does not converge on the same shape.

The answer is that converging on a single canonical path requires a canonical intermediate
form that every input modality can produce and that the compilation and execution pipeline
can consume. Without that form, every input modality invents its own path to state mutation,
and the kernel's guarantees apply to none of them.

---

## Failure Mode 1: Hallucinated Action

A model invents a function call that does not exist. It produces a syntactically valid JSON
payload with an action name that no registered handler responds to. The runtime raises an
error, or silently no-ops, depending on its implementation. The user sees either an error
message or nothing. The system does not tell the user which part of their intent was
syntactically parseable, which was semantically valid, and which was simply invented.

This failure mode is not primarily a training or fine-tuning problem, though training and
fine-tuning affect its frequency. It is a structural problem. The model produces output
against a vocabulary it learned implicitly; the system has no mechanism to verify that the
output is valid against the vocabulary the runtime actually supports before attempting
execution. Schema validation at decoding time can constrain the output shape, but it cannot
constrain the semantic validity of the content — a model that invents an action name
produces a schema-valid payload that refers to nothing.

A typed intermediate form would catch this at the layer before execution. The question "is
this action in the registered vocabulary for this extension?" is a compile-time check. In a
pipeline that has a compilation layer, it refuses statically. In a direct-lowering
architecture, it fails at runtime, often with an opaque error.

---

## Failure Mode 2: Authorisation Not Checked

A model produces an action that the user did not have authority to perform. The system
executes it. This failure is silent — no error is raised, because the system never checked
whether the identity attempting the action held the necessary capability.

This is the most serious failure mode in enterprise or regulated contexts. A user asks for a
status report and the model, interpreting "show me everything about this account," produces
a data-retrieval action that crosses a governance boundary the user does not have authority
to cross. The data is returned. The system has no record that an unauthorised access
occurred, because no authorisation check ran.

In the five-path table above, three of the five paths list "none" under authorisation. This
is not negligence; it is a predictable consequence of the direct-lowering architecture. When
the model's output is the action, and the action is implemented as a direct method call or a
reducer mutation, there is no natural place to insert an authorisation check that applies
uniformly across all inputs. Each path either implements its own ad-hoc check or skips it.

Authorisation is not a runtime concern in a well-structured pipeline. It is a compile-time
concern: the intent is typed with the identity of the actor, the hat under which they are
acting, and the capability they hold. The compilation layer refuses to produce execution
bytes for an intent whose identity binding does not carry the required capability. The kernel
then enforces the same check at the bytecode gate as a second line of defence. In a
direct-lowering architecture, neither check is structurally present. The authorisation that
does exist is ad-hoc, per-path, and incomplete.

---

## Failure Mode 3: Destructive Action on Ambiguous Intent

A model executes a destructive action when the user intended a query. The user asks "what
would happen if I deleted this record?" and the model, parsing "delete this record" as the
operative verb, deletes the record. Or the user asks "can you move this payment to
next month?" and the model, treating this as a command rather than a question, executes the
payment adjustment without a confirmation turn.

This failure mode has a well-known mitigation: add a confirmation turn before any
destructive action. Many systems implement this. The problem is that "destructive" is a
category the system has to decide, and deciding it requires semantic understanding of the
intent — the same understanding the model was supposed to provide. The confirmation-turn
mitigation shifts the problem but does not resolve it. If the system misclassifies the
intent as non-destructive, the confirmation turn does not fire.

A typed intermediate form makes intent classification explicit and checkable. The jural
categories of the semantic intermediate representation (SIR) — declaration, obligation,
permission, prohibition, power, condition, transfer — are the minimum vocabulary sufficient
to distinguish what the user is doing. A query is a declaration or a condition. A mutation
is a power or a transfer. A constraint is a prohibition. These are not semantic labels
attached after the fact; they are structural types that the compilation layer requires to be
present before it produces execution bytes.

When the jural category is structurally required, misclassification becomes a type error.
The model either produces an intent typed as a query (and the kernel does not mutate state)
or an intent typed as a mutation (and the confirmation discipline fires structurally). The
ambiguity between "what would happen if" and "do this" is resolved at the layer that assigns
jural types, not at the layer that executes bytes.

---

## Failure Mode 4: Non-Reproducible Output

The same prompt produces different actions on different runs. This is an inherent property
of probabilistic language models: for a given input, the model samples from a distribution
over possible outputs. With sufficiently high temperature, two runs of the same prompt
produce different structured outputs. For low-stakes applications, this is acceptable. For
applications where the action matters — where state is mutated, where records are created,
where capabilities are consumed — non-reproducibility is a reliability property, not a
cosmetic one.

The direct-lowering architecture inherits this property unconditionally. The model is the
pipeline; what the model produces is what executes. There is no layer at which two
semantically-equivalent model outputs converge to an operationally-identical execution path.

A pipeline with a typed intermediate form provides what is described in paper A1 as the
byte-identical α-equivalence property: two natural-language inputs that express the same
semantic intent, when lowered through the SIR and the opcode intermediate representation
(OIR) in A-normal form (ANF), must produce α-equivalent OIR programs and, under canonical
variable naming, byte-identical opcode output. The kernel executes the same bytes regardless
of which surface phrasing produced them. This property does not eliminate model variation at
the natural-language boundary; it eliminates the propagation of that variation into
execution. Two phrasings of the same intent either converge at the OIR layer to the same
bytes, or they do not — and if they do not, the discrepancy is located at a specific named
layer with a specific structural cause.

---

## Failure Mode 5: No Surface for Verification

A system based on direct lowering cannot be formally verified in any meaningful sense. The
model's output is not a structural form over which verification can apply. There is no type
system, no grammar, no inference rule that characterises what the model is permitted to
produce. Any attempt to verify the system's correctness devolves into characterising the
model's distribution over outputs — a statistical claim, not a structural one.

This matters for regulated industries. A compliance team cannot audit a system that has no
formal specification of its execution semantics. A regulator cannot inspect an audit trail
that is a log of JSON payloads whose authorisation was never checked. A security review
cannot find the boundary between inputs the system will accept and inputs it will refuse,
because that boundary is not structurally defined — it is wherever the model happens to draw
it on any given run.

A pipeline with named layers provides a verification surface at each layer. The SIR's trust
tier — interpretive, authoritative — is a syntactic property checkable by a rule. The OIR's
binding graph is a structural property checkable against the ANF well-formedness rules. The
cell engine's execution semantics are mechanically proved as kernel invariants over the
abstract 2-PDA model. Each layer is independently auditable. The audit trail from a single
user turn — one correlation identifier tagging every stage event from producer adapter
through kernel receipt — is a structured artefact, not a log of opaque JSON.

The direct-lowering architecture does not provide this. What it provides is a model call log
and a record of what the runtime did afterward. These are useful for post-hoc debugging.
They are not a verification surface.

---

## Failure Mode 6: The Gradient Is Absent

These five failure modes — hallucinated action, unchecked authorisation, ambiguous intent,
non-reproducible output, no verification surface — are not independent. They are
consequences of a single structural absence: there is no gradient between the user's input
and the system's action. The user's words and the machine's execution are one hop apart. The
system cannot stop in the middle, inspect what it has so far, refuse to proceed, or hand
the intermediate form to a human for ratification.

This is the shape that makes LLM-driven systems unreliable in contexts where reliability
matters. It is not the only shape available. The alternative — a sequence of typed
transformations, each with a canonical form, a validation rule, an explicit loss boundary,
and an emit pass to the next layer — has been the standard shape for trustworthy execution
pipelines for decades. The LLM's role in such a pipeline is as a producer of typed
candidates at the boundary between natural language and the first structured layer. It does
not execute. It proposes.

---

## The Handyman Intake: A Worked Example

> The following example threads one natural-language input through the failure modes above
> and then through the pipeline structure that avoids them. It is drawn from the handyman
> intake scenario in paper A1 §5.2 and will reappear throughout this book as the canonical
> illustration of the compression gradient.

A tenant sends a message to a property management system:

> *"need door fixed, kinda broken at the hinge, might need replacing idk"*

Consider what a direct-lowering architecture does with this input.

The model receives the message. It has access to tool descriptions: `create_maintenance_job`,
`schedule_inspection`, `order_replacement`. It produces one of these — call it a function
call. Which one? The input is ambiguous. "Might need replacing idk" is an explicit
uncertainty marker. The user does not know whether repair or replacement is the right
course. They are reporting a problem, not authorising an action.

A model in a direct-lowering architecture must resolve this ambiguity in one inference pass.
It will produce either `create_maintenance_job` (committing to repair) or
`schedule_inspection` (deferring) or some other action. If it commits to repair, and the
hinge is irreparable, the system has authorised work that cannot complete. If it commits to
replacement, and the hinge is repairable, the system has over-spent the maintenance budget.
Neither commit was what the user authorised — the user reported a problem and said "I don't
know."

There is no mechanism in the direct-lowering architecture to surface this uncertainty to the
compilation layer. The model is the pipeline. Whatever it outputs, executes.

Now consider the same input through a pipeline with typed intermediate forms.

**Layer 0 to Layer 1 (natural language to SIR).** A producer adapter calls an LLM with a
strict structured-output schema parameterised by the property management extension's domain
grammar. The model produces a candidate intent with jural category `obligation`, action
`report_issue`, taxonomy path `services.trades.carpentry`, primary subject `door`, secondary
attribute `hinge_damage`, and an explicit `uncertainty: { repair_or_replace: true }` field.
Confidence is computed by the host — not self-reported by the model — at 0.91, sufficient
to route the intent to the pipeline. Latency: approximately 1.4 seconds.

The intent is not an action. It is a typed claim about what the user wants. The uncertainty
field is not discarded; it is a first-class element of the intent shape.

**Layer 1 (SIR construction).** The SIR program carries the obligation category, the
property management taxonomy, the tenant's identity binding (the hat under which they are
acting), and a governance context with trust class `interpretive` and proof requirement
`attestation`. The constraint structure includes a typed temporal gate for response time and
propagates the `uncertainty` field. The SIR is the system's commit to what the user's words
mean — typed, inspectable, and refusable if any element is malformed.

**Layer 2 (lowering to OIR).** This is where the direct-lowering architecture would have
already committed to an action. The pipeline does not. The lowering pass refuses to commit
to either `repair` or `replace`. Instead, it lowers to an OIR program that records the
report, holds the resulting cell in `triaged` state, and produces a structured request for
the next-step decision. The decision will be made either by the property manager — a human
ratification step — or by an inspection visit that resolves the uncertainty with physical
evidence. The system's commit is precisely this: a maintenance obligation in the
carpentry/hinge-damage taxonomy with an unresolved repair-or-replace uncertainty.

**What the pipeline produces.** A typed cell in `triaged` state. A hash-chained evidence
record anchored to the tenant's identity. A structured request for ratification routed to
the property manager's Helm interface. No premature commit to repair or replacement. No
unauthorised expenditure. No opaque failure.

The difference between the direct-lowering output and the pipeline output is not the quality
of the model. It is the presence of intermediate layers that the system can stop at,
inspect, and hand to a human before proceeding. The tenant said "I don't know." The pipeline
preserved that statement as a typed fact. The direct-lowering architecture discarded it.

---

## What This Failure Pattern Motivates

The six failure modes above — and the handyman intake that illustrates them — point to the
same structural requirement: the pipeline between natural language and execution must have
typed intermediate forms. Each form must have a canonical shape, a validation rule, an
explicit boundary for what it preserves and what it discards, and a pass to the next layer
that can refuse.

This is the compression gradient. The term describes the progressive reduction of entropy
across a sequence of typed layers: natural language through the SIR, the SIR through the
OIR in ANF, the OIR through opcode bytes, and the bytes through bounded execution in the
2-PDA cell engine. Each layer is more constrained than the last. Each compression step has a
loss boundary — an explicit statement of what is preserved and what is normalised away.
Across the gradient, semantically equivalent inputs converge to operationally equivalent
execution.

The handyman intake makes the gradient concrete. The tenant's uncertain natural language
does not compress directly to an action. It compresses first to a typed semantic intent,
then to a structured obligation with a named uncertainty, then — only after human
ratification resolves the uncertainty — to opcode bytes that the kernel executes. The
compression is staged. Each stage is inspectable. Each stage can refuse.

The chapters that follow describe each layer of this gradient in detail, beginning with the
identity and capability substrate that makes authorisation structural (Part II) and the cell
engine that makes execution deterministic and provable (Part III). By the time the reader
reaches Part VI on the universal intent pipeline, the handyman intake will have been traced
through every layer of the system from the tenant's words to the anchored cell that records
the maintenance obligation. What follows here is the architecture that makes that trace
possible.
