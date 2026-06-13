---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/WALLET-VOICE-SHELL-GRAMMAR.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.724961+00:00
---

# Wallet — Voice Shell Grammar (`do | find | talk`) — VS1–VS5

**Version**: 0.1 DRAFT
**Status**: Plan
**Authors**: Todd
**Related**: `docs/design/WALLET-SHELL-VPS-SUBSTRATE.md` (Brain 3 REPL, Brain 5 LLM adapter), `docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md` (Helm-served operator portal), `docs/design/WALLET-MOBILE-AUTH-FLOW.md` (`purpose=operator_shell`), `docs/design/WALLET-LEGACY-INGEST.md` (ratification verbs surface here)

---

## 0. Headline

> The operator presses a mic button on Helm, says "let me see the job for Mrs Henderson," and the system parses that into a shell command — `find | self | who:"Mrs Henderson" what:job` — that dispatches through the same router the typed REPL uses, returning the job cell rendered in Helm's centre panel. Three modal verbs (`do`, `find`, `talk`) over a `who:what:why` payload give the operator a small, opinionated grammar that covers virtually everything a tradie says aloud about their work. The LLM is the parser's *aide*, not its controller; the existing shell verbs are the source of truth for what the system can actually do; the operator's corrections train the parser.

### On layering

The voice grammar and the LLM-assisted parser live **in the Shell** at `runtime/shell/src/` — not in Helm. Helm provides the mic UI affordance (`apps/loom-react/src/helm/VoiceInput.tsx`) and renders the parsed-command preview / approval card; the parsing, dispatch, and command execution are Shell concerns; the resulting state mutations land in the Loom service layer (`runtime/services/src/services/loom/`) and ripple back through Helm's reactive subscription. Voice is one more shuttle thrown through the Loom warp — symmetric with the typed REPL, the WSS-piped commands, and the chat-shell — not a special path. See chapter 17b of the textbook for the substrate position of Loom and the warp/shuttle architecture.

---

## 1. Where We Are

The substrate already has most of what voice-driven Helm needs:

- **`runtime/shell/src/parser.ts`** plus `router.ts` define a typed verb grammar
  (`new`, `patch`, `inspect`, `list`, `transition`, `verify`, `sign`, `publish`,
  `revoke`, `transfer`, `flow`, `eval`, `compile`, `bind`, `identity register|
  derive|resolve|list`, `whoami`, `capabilities`, `extension list|status|detail`)
  with flag handling, error codes, and tab completion.
- **`runtime/shell/src/intent-adapters/shell-to-intent.ts`** is a cleanly-named
  hook for "translate a free-form intent into a shell command." It exists; it
  is the right place for VS1's parser to live.
- **`runtime/shell/src/chat/`** has `chat-shell-repl.ts`, `llm-action-types.ts`,
  `llm-processor.ts`, `prompt-builders.ts`, `action-executor.ts` — an
  LLM-driven chat surface that already routes through the shell. This is the
  *architectural* prototype of voice-driven Helm; what's missing is the modal-
  grammar layer that constrains the LLM's output space and the voice-capture
  surface itself.
- **Brain 5** declares an LLM-conversation adapter (off by default) whose entire
  job is to translate natural language into structured commands the wallet
  engine validates. The voice-shell grammar is the *contract* Brain 5's
  translation produces against.

What is *missing* is three things:

1. The `do | find | talk` modal grammar itself, codified, with a typed contract
   the parser produces and the router consumes.
2. The mic-capture + STT surface in Helm — browser MediaRecorder, an STT
   provider (initially Whisper API; eventually local), turn-taking UX.
3. The disambiguation + correction loop that makes the LLM's parsing improve
   from operator feedback over time (the same Paskian mechanic as legacy
   ingest, applied to the operator's own utterances).

VS is the workstream that fills those three gaps.

---

## 2. The Grammar

### 2.1 The three modal verbs

Every utterance maps to exactly one of three modal verbs:

| Modal | Meaning | Side effects |
|---|---|---|
| **`do`** | Perform a state-mutating action — write a cell, sign an action, transition a flow, send a message | Yes — gated by hat policy + Verifier Sidecar; may require `purpose=operator_shell` re-auth (cf. MOBILE-AUTH-FLOW §10.1) |
| **`find`** | Read-only retrieval — surface objects, render history, compute aggregates | No — pure VFS query + render |
| **`talk`** | Open a conversational scope — chat with self / chat with object / chat with another hat | Yes (the conversation produces messages and may produce ratifications) |

The operator says `"let me see Mrs Henderson's last quote"` → modal is `find`.
`"send Mrs Henderson the updated quote"` → modal is `do`. `"talk to me about
Mrs Henderson's history"` → modal is `talk`.

This three-way partition is small enough to hold in the operator's head, large
enough to cover the operator's actual utterances, and aligns with how the
substrate already partitions reads (`inspect`, `list`, `trace`, `verify`) from
writes (`new`, `patch`, `transition`, `sign`, `publish`) from conversational
flows (the existing `runtime/shell/src/chat/`).

### 2.2 The `who:what:why` payload

Every utterance carries up to three semantic slots:

| Slot | Meaning | Examples |
|---|---|---|
| **`who`** | The principal or counterparty in scope | `self`, `"Mrs Henderson"`, hat-id, cert-id, `tenant:<id>`, `customer:<id>` |
| **`what`** | The object kind or specific object | `job`, `quote`, `lead`, `invoice`, `calendar:<date>`, `<cell-id>` |
| **`why`** | Optional intent qualifier | `--for "ROM update"`, `--because "weather change"`, `--via gmail`, `--in trades.fence` |

Not every slot is required. `find | self | calendar:tomorrow` is a complete
utterance ("show me my schedule for tomorrow"). `do | "Mrs Henderson" |
quote --for "fence ROM"` is complete ("draft a fence-ROM quote for Mrs
Henderson"). `talk | self` is complete ("open a chat scope with myself").

### 2.3 The dispatch contract

The parser produces a typed object:

```typescript
export interface VoiceCommand {
  modal: "do" | "find" | "talk";
  who?: VoicePrincipal;        // self | named | resolved-cert
  what?: VoiceTarget;           // object kind | object id | calendar | etc.
  why?: VoiceQualifier;         // free-text intent qualifier
  raw: string;                  // the original transcript
  confidence: number;           // 0..1, parser's self-assessment
  alternatives?: VoiceCommand[]; // up to 3 alternative parses if ambiguous
}
```

This is what the parser hands to the existing shell router via
`intent-adapters/shell-to-intent.ts`. The router's job: map `(modal, who, what,
why)` to the appropriate concrete shell verb (`new`, `inspect`, `list`,
`patch`, etc.) plus its flags, then dispatch through `route()`. Every
substrate operation that voice can produce is one the typed REPL can also
produce; voice does not introduce new capabilities, only a new input surface.

### 2.4 What the grammar deliberately does *not* cover

- Multi-step plans. "Quote Mrs Henderson, then schedule the visit, then send
  her a confirmation" is three utterances, not one. The grammar refuses to
  collapse a sequence into one command — the operator explicitly chains.
  This is the substrate's existing `flow` mechanism; the operator can name a
  flow and `do | self | flow:<name>` to execute pre-declared sequences.
- Quantitative reasoning ("how much did I make last week"). Those are
  `find | self | revenue --since "1 week ago"` — read-side queries with a
  computed projection; the answer comes from the existing REPL `revenue`
  verb (cf. WSITE5).
- Open-ended conversation. The `talk` modal opens a scoped chat, but each
  *turn* in that chat is itself a `do | find | talk` utterance. The operator
  can leave the modal grammar by being inside a `talk` scope — and the LLM
  there is freer — but the moment a turn produces a state mutation, it
  exits back to the grammar for explicit confirmation.

---

## 3. Phases

### VS1 — Modal grammar + parser implementation (~ 1.5 days)

**Goal**: the typed `VoiceCommand` is a real value, the parser is a real
function, the router knows how to dispatch it. No voice yet, no LLM yet — just
the grammar plumbing, exercised from typed input.

**Deliverables**:

1. New file `runtime/shell/src/voice-grammar.ts`. Defines the `VoiceCommand`
   type, the `VoicePrincipal` / `VoiceTarget` / `VoiceQualifier` enums and
   types, the dispatch table from `(modal, what)` to concrete shell verb +
   flag construction.

2. **Static parser** — accepts already-structured input (e.g. JSON) and
   produces a `VoiceCommand`. No LLM. This is the contract surface; it lets
   us test the grammar plumbing end-to-end without depending on a
   transcription model.

   ```typescript
   parseVoiceCommand({
     modal: "find",
     who: { kind: "named", text: "Mrs Henderson" },
     what: { kind: "object", text: "job" },
     why: undefined,
     raw: "let me see the job for Mrs Henderson",
   }) → dispatchable shell command:
       { verb: "list", flags: { type: "Job", who: "Mrs Henderson" }, format: "table" }
   ```

3. **Dispatch table**. Defines, for each `(modal × what)` pair, which shell
   verb fires:
   - `find × object` → `list` with `--type` from `what.text`
   - `find × cell-id` → `inspect <cell-id>`
   - `find × calendar` → `calendar list --range <date>` (calendar extension)
   - `do × object` → `new <type-path>` with flags from `why`
   - `do × cell-id` → `patch <cell-id>` with flags from `why`
   - `do × ratification` → calls `legacy ratify` (cf. LEGACY-INGEST §3 LI4)
   - `talk × self` → opens `chat-shell-repl` with the operator's own hat
   - `talk × object` → opens chat scope over a specific cell
   - … etc.

4. **Tests**. Round-trip: a known-good `VoiceCommand` produces a known-good
   shell command; a malformed `VoiceCommand` produces a structured error;
   the dispatch table covers every `(modal, what)` pair declared as
   "supported in v0.1."

5. **REPL command** — `voice <json>` accepts a typed `VoiceCommand` (passed
   as JSON on the command line) and dispatches it. Useful for end-to-end
   testing without the parser-aid path lit up.

**Success criterion**: a hand-authored `VoiceCommand` for "find Mrs Henderson's
job" dispatches through the existing router and renders the same output as the
typed REPL command does. Every intended `(modal, what)` pair in v0.1 has a
test.

### VS2 — LLM-as-parser-aid (~ 1.5 days)

**Goal**: a transcript string in, a `VoiceCommand` (with `confidence` and
`alternatives`) out. The LLM's role is constrained: it produces structured
output that matches the `VoiceCommand` schema; it does not invent new verbs;
it does not bypass the dispatch table.

**Deliverables**:

1. New file `runtime/shell/src/voice-parser-llm.ts`. Wraps Brain 5's LLM adapter
   (cf. BRAIN §3 Brain 5) but with a strict output schema and a system prompt
   that encodes the modal-verb grammar.

2. **System prompt** declares the grammar explicitly:
   ```
   You translate the operator's natural-language utterance into a structured
   command. The command must be one of:

     do   <verb-or-target> [for|because|via|in <qualifier>]
     find <verb-or-target> [for|because|via|in <qualifier>]
     talk <verb-or-target>

   Available object kinds: job, quote, lead, invoice, calendar, customer,
   message, capability, hat, cell.

   Available principal forms: self, <named-person>, hat:<id>, cert:<id>,
   tenant:<id>, customer:<id>.

   Output JSON conforming to the VoiceCommand schema. If the utterance is
   ambiguous, produce the top-K parses (K up to 3) ranked by confidence.

   Do NOT produce a parse that uses verbs not in this list.
   Do NOT produce a parse for an utterance that is not a command (e.g. a
   greeting, an off-topic remark) — return { modal: null, alternatives: [] }.
   ```

3. **Few-shot examples** drawn from the operator's own correction history
   (cf. VS5). Initially seeded with ~20 hand-authored examples covering the
   common utterances; grows as the operator corrects.

4. **Confidence calibration**. The LLM is asked to produce a self-assessed
   confidence; this is paired with a heuristic confidence (e.g. "all named
   slots resolve to known principals/objects" → boost; "principal slot
   doesn't match anyone in the operator's directory" → lower). The combined
   confidence drives the disambiguation UX (VS4): high → execute; medium →
   confirm; low → clarification dialogue.

5. **Schema-validated output**. The LLM's response is JSON-parsed against the
   `VoiceCommand` schema; non-conforming output is rejected and the user
   sees a "couldn't parse — please rephrase" error rather than a garbage
   command. This is the trust boundary: even if the LLM hallucinates,
   schema validation catches it before the dispatch table.

6. **Backend selection**. Reuses Brain 5's config: local llama.cpp, OpenAI-
   compatible, Anthropic, or none. Default for the OJT operator: Anthropic
   (already in his stack via `@anthropic-ai/sdk`).

**Success criterion**: a corpus of ~100 operator-style utterances parses to
correct `VoiceCommand` values; ambiguous utterances surface alternatives;
non-command utterances are flagged as such; schema validation catches every
hallucinated verb.

### VS3 — Mic capture + transcription on Helm (~ 1.5 days)

**Goal**: a real microphone affordance on Helm; the operator presses, speaks,
releases (or the system detects end-of-utterance via VAD), the audio is
transcribed, the transcript flows into the parser, the parsed command
dispatches.

**Deliverables**:

1. **Helm UI surface**. A persistent mic button on Helm (mobile + desktop),
   styled as the primary affordance. Press-and-hold or tap-to-toggle (the
   operator can choose in settings). When recording: visible level meter,
   estimated duration, "tap to stop." When transcribing: spinner with the
   transcript appearing as it arrives if the STT supports streaming.

2. **Browser MediaRecorder** capture. WebM/Opus on most browsers; Safari
   gets MP4/AAC. 16 kHz mono is enough for STT and saves bandwidth.

3. **STT routing**. Configurable per BRAIN config:
   ```toml
   [voice.stt]
   backend = "whisper-api"           # or "local-whisper" or "cloud-anthropic"
   endpoint = "https://api.openai.com/v1/audio/transcriptions"
   model = "whisper-1"
   ```
   The audio blob is sent over `POST /api/v1/voice/transcribe` to the
   operator's Semantos Brain, which proxies to the configured STT (so the mobile
   browser doesn't need a separate STT API key — the operator's node holds
   it). Local-whisper is the path for full sovereignty (operator runs
   `whisper.cpp` locally, no transcript leaves the VPS); cloud routes are
   the path for low-latency on small VPSes.

4. **VAD-driven end-of-utterance detection** (optional, on by default for
   tap-to-toggle mode). Uses a small VAD library (Silero, WebRTC VAD) to
   detect when the operator stops speaking; auto-stops the recording.
   Saves a tap.

5. **Transcript-then-confirm UX**. The transcript appears on Helm with the
   parsed `VoiceCommand` rendered as a one-line preview:
   ```
   You said: "let me see the job for Mrs Henderson"
   I'll run: find | self | who:"Mrs Henderson" what:job
   [Confirm] [Edit] [Cancel]
   ```
   For high-confidence parses with no state mutation (`find` and most
   `talk`), the confirm step can be skipped (operator settings choose);
   `do` always confirms.

6. **Mobile-friendly latency budget**. End-to-end (mic-press → confirm
   appears) target ≤ 2 seconds on a 4G connection. Pre-loaded WASM for the
   mic UI; STT request streamed; parser-aid call streamed.

7. **Audit log**. Every voice utterance produces a substrate audit cell —
   the transcript, the parsed command, the confidence, the dispatch
   outcome — signed by the operator's hat. Useful for "what did I just
   say?" and for the VS5 correction loop.

**Success criterion**: operator presses the mic on his phone in the field,
says "show me Mrs Henderson's job," within 2 seconds the parsed command
preview appears, taps Confirm, the job cell renders in Helm's centre panel.
Same flow on desktop. STT backend is swappable. Audit log accumulates.

### VS4 — Disambiguation + clarification dialogue (~ 1 day)

**Goal**: when the parse is ambiguous (low confidence, or multiple plausible
alternatives, or named slots resolving to multiple candidates), the system
asks one focused clarification question — voice or tap.

**Deliverables**:

1. **Resolution layer**. Before dispatch, named principals and named objects
   are resolved against the operator's directory (the substrate's customer
   cells, lead cells, hat records). Resolution returns:
   - `unique` — exactly one match → proceed
   - `multiple` — multiple matches → clarification UX
   - `none` — no match → clarification UX with create-new affordance

2. **Clarification UX in Helm**:
   ```
   You said: "the job for Mrs Henderson"
   I found three customers named Henderson:
     [1] Mrs Sarah Henderson — Tewantin (last contact 4 days ago)
     [2] Mrs Patricia Henderson — Coolum (last contact 3 weeks ago)
     [3] Mr David Henderson — Noosa (last contact 6 months ago)
   Which one?
   ```
   Operator picks (tap, or voice "the one in Tewantin," or voice "the
   recent one"). The picked option is recorded as a *resolution edge* —
   "when this operator says 'Mrs Henderson' on a normal day, they mean #1"
   — which feeds back as a few-shot example in VS5.

3. **Multi-modal disambiguation**. Voice clarifications are themselves
   parsed by VS2 (with a shorter, scoped prompt — "the operator just heard
   options 1/2/3 and is responding"). Tap clarifications skip the parser.

4. **Negative responses**. "None of them" / "that's not it" / "actually
   never mind" are first-class outcomes that abort the command and record
   the false-resolution as a correction (VS5).

5. **Smart defaults**. Resolution incorporates recency, frequency,
   currently-active surface (if Helm is on the kanban view, candidates
   already in the kanban rank higher), explicit operator pinning ("Mrs
   Henderson is *always* Sarah").

**Success criterion**: ambiguous principal references get one focused
clarification; the operator's pick is recorded; subsequent same-utterance
phrases skip clarification because the resolution edge is in the few-shot
context.

### VS5 — Correction-feedback loop + few-shot retraining (~ 1 day)

**Goal**: the operator's corrections to parses + resolutions become the
parser-aid's in-context examples. The Paskian mechanic, applied to the
operator's own speech.

**Deliverables**:

1. **Correction capture**. The Helm UX surfaces "Edit" on every parse
   preview (VS3 §5). Edit produces a corrected `VoiceCommand`. The pair
   `(transcript, original-parse, corrected-parse, timestamp)` is persisted
   as a *parser-correction cell* signed by the operator's hat.

2. **Resolution-correction capture**. From VS4, every clarification
   produces a *resolution-correction cell* with `(transcript-fragment,
   resolved-principal, alternatives-shown)`.

3. **Few-shot retrieval**. The voice parser's prompt (VS2) appends the K
   most recent and most relevant correction cells as in-context examples.
   Relevance is scored by transcript similarity (cheap embedding lookup
   against the operator's correction corpus).

4. **Operator-visible parser quality**. `voice quality` REPL command
   surfaces metrics:
   ```
   > voice quality
     Last 30 days:
       Utterances:   847
       High confidence:  712 (84%)  — auto-confirmed for find/talk
       Confirmed:    761 (90%)
       Edited:        72 (8.5%)     — corrections fed back
       Cancelled:     14 (1.6%)
       Top edit categories:
         - principal misresolution    27 (e.g. "Henderson" → wrong customer)
         - modal misclass              9 (e.g. "find" parsed as "do")
         - target object miss         24 (e.g. "quote" parsed as "lead")
   ```
   The operator can see, concretely, where the parser is failing and where
   it is improving.

5. **Pinning canonical examples**. `voice pin <correction-id>` marks a
   correction as *always include in few-shot context*. Useful for OJT-
   specific idioms: e.g. "the Tewantin one" should always resolve to the
   most-recent Tewantin customer; "the fence job" should always be a
   `trades.job.fencing` type.

6. **Privacy**. Corrections are never sent to a third-party LLM provider as
   training data. They live in the substrate, are loaded into the prompt
   only at inference time, and the chosen LLM backend's terms of service
   determine whether prompts are retained — the operator can switch to a
   local model (`backend = "local-whisper"` + `backend = "local-llama"`)
   at any point and *all* of voice runs without a third party.

**Success criterion**: a fresh operator's voice parser starts at ~75% confirm
rate (small few-shot from the doc's seed examples); after a week of corrections,
confirm rate is ≥ 90%; quality metric surfaces are accurate; pinned corrections
are visibly in effect (the same misresolution doesn't recur).

---

## 4. Dependency Graph

```
   Brain 3 (typed REPL) ───┬─► VS1 (grammar + dispatch)
                        │           │
   Brain 5 (LLM adapter) ──┴───────────┼─► VS2 (LLM-as-parser-aid)
                                    │           │
                                    │           ▼
                                    │     VS3 (mic + STT on Helm)
                                    │           │
                                    │           ▼
                                    │     VS4 (disambiguation)
                                    │           │
                                    │           ▼
                                    └──► VS5 (correction-feedback loop)
```

VS1 stands alone (typed input). VS2 layers on. VS3 is the user-visible surface.
VS4 + VS5 close the loop and make the parser improve over time.

---

## 5. Sizing

| Phase | Effort | Risk |
|---|---|---|
| VS1 — Grammar + dispatch table | 1.5 days | Low — typed plumbing over the existing shell |
| VS2 — LLM-as-parser-aid | 1.5 days | Medium — prompt iteration, schema validation, confidence calibration |
| VS3 — Mic + STT on Helm | 1.5 days | Medium — browser MediaRecorder cross-browser quirks; STT latency tuning |
| VS4 — Disambiguation | 1 day | Low — resolution layer + clarification dialogue UX |
| VS5 — Correction loop | 1 day | Low — few-shot retrieval, metrics surface |

**Total**: ~6.5 days for one engineer. Dependent on Brain 3 + Brain 5 being available.

---

## 6. Commit Boundary Plan

1. `feat(shell): VS1 — voice-command grammar + dispatch table + typed parser`
2. `feat(shell): VS2 — LLM-as-parser-aid with schema-validated structured output`
3. `feat(helm): VS3 — mic capture + STT routing + transcript-then-confirm UX`
4. `feat(shell): VS4 — principal/object resolution + clarification dialogue`
5. `feat(shell): VS5 — correction-feedback few-shot retraining + quality metrics`

Each independently mergeable.

---

## 7. Acceptance Criteria

VS is done when:

1. Operator can press the mic on Helm (mobile + desktop), speak a command,
   confirm the parsed preview, and see the result rendered.
2. Voice end-to-end latency ≤ 2 seconds on a 4G connection.
3. STT backend is swappable between cloud (OpenAI Whisper API, Anthropic
   audio) and local (`whisper.cpp`).
4. The grammar covers the common operator utterances: find/inspect a
   customer/job/quote, list calendar, draft a quote, send a message, ratify
   a legacy proposal, switch hat, open self-chat.
5. Ambiguous principals trigger a single clarification step, and the chosen
   resolution is remembered in subsequent utterances.
6. Confirm rate on routine utterances is ≥ 90% after a week of corrections
   (measured via `voice quality`).
7. Every voice utterance produces a signed audit cell with transcript +
   parse + dispatch outcome.
8. Local-only mode (`backend = "local-whisper"` + `backend = "local-llama"`)
   runs end-to-end with no third-party calls.
9. State-mutating `do` commands always require explicit confirmation;
   `find` and routine `talk` can be operator-configured to auto-confirm
   high-confidence parses.

---

## 8. What VS Does Not Cover

- **Wake-word detection** — out of scope. The operator presses the mic; no
  always-listening mode. (Privacy + reliability concerns; wake-word is a
  v1.x research project.)
- **Multi-speaker contexts** — voice assumes the operator is the speaker.
  Customer-side voice (e.g. customer leaves a voicemail) is a separate
  workstream that flows through the legacy-ingest pipeline as audio
  RawItems extracted to SIR proposals (cf. LEGACY-INGEST §3 LI3).
- **Real-time spoken responses** — the system speaks back via text on Helm,
  not via TTS audio. TTS adds complexity (voice selection, audio playback
  on mobile) and value is unclear; defer until operator demand is concrete.
- **Multi-language** — v0.1 is English. The grammar is language-agnostic in
  principle (the modal verbs and slot names are interlingual concepts) but
  the LLM prompts and few-shot examples are English-anchored.
- **Voice commands that bypass the typed REPL** — every voice command
  produces a typed REPL command first, then dispatches. The voice surface
  is *always* a thin layer over the existing shell; no shadow command set.
- **Voice for end-users** — VS is operator-facing. A future workstream
  could expose voice to authenticated end-users (e.g. customers calling a
  phone number whose voice is transcribed and routed through the intake
  bot), but that's separate.

---

## 9. Cross-references

- `docs/design/WALLET-SHELL-VPS-SUBSTRATE.md` — Brain 3 provides the typed REPL
  the voice grammar dispatches through; Brain 5 is the LLM adapter VS2 wraps
- `docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md` — the Helm UI mic surface
  is a WSITE-served route (VS3)
- `docs/design/WALLET-MOBILE-AUTH-FLOW.md` §10.1 — `purpose=operator_shell`
  re-auth pattern that state-mutating `do` commands use when the operator
  is on mobile
- `docs/design/WALLET-LEGACY-INGEST.md` §3 LI4 — ratification verbs
  (`do | ratify | proposal:<id>`) surface in the voice grammar
- `runtime/shell/src/parser.ts` — typed-REPL parser the voice grammar
  produces commands for
- `runtime/shell/src/router.ts` — dispatcher voice commands invoke
- `runtime/shell/src/intent-adapters/shell-to-intent.ts` — the existing
  hook for "translate intent → shell command"; VS1's parser lives here
- `runtime/shell/src/chat/` — the existing LLM-driven chat surface that VS
  generalises and constrains via the modal grammar
- `runtime/intent/sir-builder.ts` — SIR construction when `do` produces a
  semantic-object mutation
- `runtime/intent/voice/` — existing cert-bound voice-session contract
  (`createVoiceSession` / `addTranscript` / `verifyTranscript`); VS3's
  mic-capture path uses it for cert-binding the transcripts
- OpenAI Whisper API, `whisper.cpp` — STT backends VS3 supports
- Web Speech API, MediaRecorder API — browser-side voice capture
