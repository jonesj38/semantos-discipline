---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/00-MASTER-ROADMAP.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.772111+00:00
---

# Master Roadmap — Monolith Decomposition

> See `../../../MONOLITH_DECOMPOSITION.md` for the full architectural rationale.
> See `00-README.md` for house rules.

## Summary

45 prompts (one preamble rename + 44 splits) across 16 phases. Working alone, estimate ~6 calendar weeks (about 30 engineer-days heads-down, plus ~50% friction buffer). With two engineers in parallel from phase 6 onward, ~3–4 weeks.

Phase 0 (rename), then 1–5, are **strictly sequential**: each feeds the next. Phases 6 onward can fan out — the poker stack, MUD stack, games, and session protocol have no dependency between them once the foundation layer is in place.

## Critical path

```
00A (Facet→Hat rename — lands before any split)                            ~1–1.5 days
 └─ 01  (foundation)                                                       ~1 day
     └─ 02,03  (LoomStore)                                                 ~2 days
         ├─ 04,05,06,07  (core/protocol-types)                             ~3 days
         └─ 08  (router)                                                   ~1 day
             └─ 09,10,11,12  (runtime services)                            ~3 days
                 └─ 13,14,15  (payment-channel)                            ~3 days
                     └─ 16..21  (poker stack)                              ~4 days
                         └─ (everything else can parallelize from here)
```

## Full task list

Check off as you merge.

### Phase 0 — Rename preamble
- [ ] **00A** Rename `Facet` → `Hat` across code, UI, tests, and docs (codemod + audit)

### Phase 1 — Foundation
- [ ] **01** Build `core/state/` primitives (atom, derived, effect, port, registry, eventBus, slice)

### Phase 2 — LoomStore (biggest single win)
- [ ] **02** Extract pure `loomReducer` from `LoomStore`
- [ ] **03** Atomize `LoomStore` state + split lifecycle/dispute/channel handlers

### Phase 3 — Core protocol-types
- [ ] **04** Split `cell-store.ts` into header/packer/chunker/walker/indexer/facade
- [ ] **05** Split `semantic-fs.ts` into parser/validator/queries/search/tombstones
- [ ] **06** Split `wallet-client.ts` into transport/request-builder/response-parser/methods
- [ ] **07** Split `LocalIdentityAdapter.ts` into key-resolver/registrar/recovery/subtree

### Phase 4 — Router
- [ ] **08** Verb registry + collapse `router.ts` and `router-browser.ts`

### Phase 5 — Runtime services
- [ ] **09** Split `IntentClassifier.ts` (taxonomy navigator, embedding ranker, prompts)
- [ ] **10** Split `ConfigStore.ts` (loader, merger, seed applicator, overlays, ballots)
- [ ] **11** Split `runtime/shell/src/chat.ts` (REPL, LLM, ROM, attachments)
- [ ] **12** Split `runtime/shell/src/vfs/pathResolver.ts` (parser, serializer, walker)

### Phase 6 — Payment channel
- [ ] **13** Extract payment-channel FSM reducer (pure)
- [ ] **14** Define and wire payment-channel ports (wallet, utxo, broadcaster, signer)
- [ ] **15** Extract payment-channel effect atoms + keep facade alive

### Phase 7 — Poker stack
- [ ] **16** Extract poker-shared primitives (BeefCodec, UtxoProvider, Broadcaster, Signer)
- [ ] **17** Split `poker-state-machine.ts` (cell builder, signer, keys, anchor, utxo tracker)
- [ ] **18** Split `direct-broadcast-engine.ts` (keys, pool, tx builder, ARC adapter, stats)
- [ ] **19** Split `game-loop.ts` (deck, betting, phases, context, policy, events)
- [ ] **20** Split `p2p-agent-runner.ts` (turn coordinator, transceiver, shuffle, audit)
- [ ] **21** Split `game-state-db.ts` (action, snapshot, session, memory, context builder)

### Phase 8 — MUD + games (template applies)
- [ ] **22** Refactor `game-sdk/engine.ts` as reducer-plus-effects base
- [ ] **23** Split `apps/mud/room-actor.ts` (handlers, combat, inventory, doors, movement, persist)
- [ ] **24** Split `apps/mud/world-server.ts` (generator, sessions, pool, transfer, persistence)
- [ ] **25** Split `extensions/games/dungeon/engine.ts` (action dispatcher, systems, FOV, board)
- [ ] **26** Split `extensions/games/chess-stakes/strategy.ts`

### Phase 9 — Game extensions
- [ ] **27** Split `extensions/games/cli/game-commands.ts`
- [ ] **28** Split `extensions/scada/authorization.ts`
- [ ] **29** Split `extensions/cdm/lifecycle.ts`

### Phase 10 — Loom-react panels (atoms consumers)
- [ ] **30** Atomize `BindingWizard.tsx` and extract each step into its own component
- [ ] **31** Refactor `ChatView.tsx` to consume LoomStore atoms + extract sub-components
- [ ] **32** Refactor `ConversationPanel.tsx`
- [ ] **33** Refactor `GovernanceDashboard.tsx`

### Phase 11 — Site + navigation
- [ ] **34** Split `apps/site/InteractiveDemo.tsx`
- [ ] **35** Port `apps/navigation_app/bsv-app/navigation.js` to TypeScript
- [ ] **36** Split navigation_app shell (process cycles, object types, chat, overlays, kernel bridge)
- [ ] **37** Split `navigator.js` (lenses, commands, filters, views)

### Phase 12 — Session protocol
- [ ] **38** Split `multicast-adapter.ts` (codec port, peer manager, message handler, subscriptions)
- [ ] **39** Split `ws-node-adapter.ts` (peer connection, license, envelope, registry)
- [ ] **40** Split `bsv-overlay-bundle-client.ts` (publisher, subscriber, dedupe, polling)

### Phase 13 — Cell-ops
- [ ] **41** Split `cellPacker.ts` (continuation handlers, varint, multicell assembler)
- [ ] **42** Split `wasm-interface.ts` (error translator, memory accessor, per-feature wrappers)

### Phase 14 — Validators
- [ ] **43** Split `extension-grammar-validator.ts` (error collector + per-section validators)

### Phase 15 — Settlement
- [ ] **44** Split `apps/settlement/store.ts` (node, edge, delta log, stability, pruning, query)

## Parallelization notes

After phase 5 lands, the remaining phases fan out. Safe parallel tracks:

- **Track A (state):** 13 → 14 → 15 → 16 → 17–21
- **Track B (games):** 22 → 23/24/25/26 in any order
- **Track C (pure refactors, no deps):** 38, 39, 40, 41, 42, 43, 44 in any order
- **Track D (frontend, depends on 03):** 30, 31, 32, 33, 34 in any order
- **Track E (navigation, no deps):** 35 → 36 → 37

Tracks A, B, C, D, E are independent. Two engineers can sustain three tracks comfortably.

## Done criteria

This refactor is "done" when all 44 boxes are checked **and**:

1. Every file under `apps/`, `core/`, `runtime/`, `extensions/` (excluding tests, declarative data, and `archive/`) is ≤400 LOC.
2. `pnpm -r check` passes.
3. `bun test tests/gates/` passes (no new allowlist entries).
4. At least one end-to-end scenario per major surface has a golden snapshot test comparing pre- and post-refactor behavior.
