---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/hackathon/HACKATHON-PRD.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.763540+00:00
---

# Open Run Agentic Pay Hackathon — Project PRD

## Project: Semantos Game Multiverse

**Submission title:** Game Multiverse — AI Agents Playing Trustless Games Across Worlds on BSV
**Category targets:** Best Solo Builder ($1,000), Most Innovative ($1,000), Best MCP Use ($1,000)
**Hackathon:** Open Run Agentic Pay | BSV Association
**Hacking period:** April 6–17, 2026 (12 days)
**Submission deadline:** April 17, 23:59 UTC
**Results:** April 23, 18:00 UTC

---

## 1. Challenge Requirements Mapping

The hackathon requires: "Build an application where two or more AI agents autonomously discover each other, negotiate, and exchange value through BSV micropayments — solving a real-world problem."

### 1.1 Mandatory Technical Requirements

| Requirement | How We Meet It | Existing Asset |
|---|---|---|
| Minimum 2 AI agents with independent BSV wallets | Agent A + Agent B, each with BSV Desktop Wallet | AI strategy engines for poker + chess |
| Agent discovery via BRC-100 wallets/identity | Agents discover each other via BCA addressing; BSV Desktop Wallet provides BRC-100 identity | BCA derivation (Phase 2), StubPlexusAdapter (Phase 14) |
| Autonomous transactions via MessageBox P2P or direct payments | BSV micropayments per poker hand, dungeon entry, chess cube stake via `bsv-mcp` wallet tools | MFP payment channel model (Phase 18), PokerTableTransport (already wired to shard proxy) |
| Human-facing web UI showing agent activity | Multiverse dashboard: poker table, dungeon map, chess board with event log and wallet balances | Poker ASCII renderer, Dungeon map viewport, Double Mate browser viewer |
| Real problem-solving application | Trustless online gaming with SRA mental poker (no server sees cards), provably fair chess, cross-game economy with mathematically enforced scarcity | SRA protocol (complete), SemanticChessEngine (complete), LINEAR cell enforcement (proven in Lean 4) |
| 1.5M transactions in 24-hour window | Poker generates ~50 txns/hand (shuffle proofs, decryptions, bets, reveals). At 120 hands/hour across concurrent tables: 6,000 txns/hour per table. 12 concurrent tables = 1.7M in 24 hours | SRA protocol proof artifacts + betting txns + cross-game transfers |

### 1.2 What We Cannot Use (Plexus Not Wired)

| Plexus Feature | Hackathon Replacement |
|---|---|
| Plexus WAB (real identity registration) | BSV Desktop Wallet BRC-100 identity on each device |
| Plexus certificate lifecycle | StubIdentityAdapter — offline capability validation |
| Plexus edge creation (secure channels) | Direct shard proxy multicast (Jeff's infrastructure) — **already wired for poker** |
| Plexus capability delegation | LOCAL capability tokens evaluated in WASM |
| Plexus recovery protocol | Not needed for 12-day demo |

### 1.3 What We CAN Use (Already Built)

| Component | Phase | Status | Hackathon Role |
|---|---|---|---|
| 28KB cell-engine.wasm (2-PDA, linearity) | Phase 0–7 | Complete | Universal kernel for all three games |
| TrustlessPokerEngine + SRA protocol | Phase 27 | **Complete** | **Headline game — trustless card dealing** |
| PokerTableTransport (shard proxy) | Phase 27 | **Complete** | **Two-device networking — already wired** |
| SRA crypto (commutative encryption) | Phase 27 | **Complete** | Shuffle proofs, decryption proofs, key reveals |
| PokerEngine + hand evaluator | Phase 27 | **Complete** | Texas Hold'em game logic |
| Poker Lisp policies (betting rules) | Phase 27 | **Complete** | WASM-enforced betting validation |
| Dungeon Crawler engine | Phase 27 | **Complete** | Dungeon world with items, combat, rooms |
| Dungeon map generation | Phase 27 | **Complete** | Procedural dungeon floors |
| SemanticChessEngine | Phase 27 | **Complete** | Chess world with policy-validated moves |
| StakesChessEngine + DoublingCube | Phase 27 | **Complete** | Cube protocol for stakes escalation |
| Four AI chess strategies | Phase 27 | **Complete** | Shark, Bluffer, Optimal, Turtle |
| Chess Lisp policies (move legality) | Phase 27 | **Complete** | 6 piece-type policies compiled to WASM |
| Double Mate browser viewer | — | **Complete** | Stakes chess UI with cube and strategies |
| GameCellEngine SDK | Phase 26 | Complete | Entity creation, inventory, trade, transitions |
| Lisp policy compiler → WASM opcodes | Phase 21 | Complete | Policy enforcement across all games |
| OP_CALLHOST host function dispatch | Phase 25.5 | Complete | Domain predicates for each game |
| StorageAdapter + IdentityAdapter | Phase 26 | Complete | Persistence and identity per agent |
| BCA derivation + verification | Phase 2 | Complete | Agent addressing |
| Browser WASM loader | Phase 7 | Complete | Client-side kernel execution |

---

## 2. The Demo: Currency Flows Through Three Worlds

### 2.1 Why Poker Leads (Not Chess)

The trustless poker implementation is the strongest hackathon asset for three reasons:

1. **Transport is already built.** `PokerTableTransport` has typed shard proxy multicast with message publishing for key registration, shuffles, decryptions, actions, community reveals, key reveals, and verification. Chess would need this adapted from scratch. Poker has it done.

2. **The crypto story is genuinely novel.** SRA mental poker — no server ever sees the cards. Commutative encryption means each player encrypts and shuffles independently. The game is verifiable post-hoc by replaying with revealed keys. Judges will understand why "trustless online poker" is a real-world problem worth solving (operator cheating, collusion, rake fraud are billion-dollar problems).

3. **Transaction density is higher.** Each poker hand generates ~50 BSV transactions (key registrations, shuffle proofs, decryption proofs, betting actions, community reveals, key reveals, verification). Chess generates ~5 per move. Poker hits the 1.5M target faster with fewer concurrent instances.

### 2.2 The Economy: Money Threads Through, Not Items

The multiverse demo follows a **currency flow**, not arbitrary item staking. The doubling cube doubles a monetary bet — it doesn't make sense to "double a sword." Gold coins double. Chips double.

```
WORLD 1: POKER TABLE
  Agent A and Agent B play trustless Texas Hold'em
  SRA protocol: encrypted shuffle → selective dealing → betting → showdown
  Every hand: ~50 BSV transactions (proofs + bets + reveals)
  Agent A wins BSV chips (real micropayments)

         ↓ Agent A carries BSV chips

WORLD 2: DUNGEON
  Agent A pays chips to enter the dungeon
  Navigates rooms, fights monsters (AFFINE — destroyed on kill)
  Uses keys (LINEAR — consumed on door unlock)
  Finds GOLD COINS in chests (new LINEAR currency cells)
  Gold coins have provenance: "minted in dungeon floor 3, funded by poker winnings"

         ↓ Agent A carries gold coins

WORLD 3: DOUBLE MATE (Stakes Chess)
  Gold coins are the buy-in for the chess match
  Doubling cube escalates the gold coin stake: 1 → 2 → 4 → 8 → ...
  Agent runs low on gold coins
  Agent has 1.9x the previous bet — not enough for a full double
  Agent goes ALL-IN: shoves all remaining gold coins
  If they win: they take the entire pot
  If they lose: cleaned out — back to the poker table to earn more

         ↓ Winner takes the pot

  Every gold coin has a provenance chain:
    minted: dungeon floor 3
    funded-by: poker hand #47 winnings
    staked: chess game #12, cube value 8
    won-by: Agent B, checkmate move 34
```

### 2.3 The All-In Moment

This is the dramatic beat of the demo. The doubling cube works on currency, not items:

- Cube value is at 8 (meaning the game is worth 8 gold coins to the winner)
- Agent A's opponent offers to double to 16
- Agent A has 15.2 gold coins — not enough to cover a full double
- Agent A goes **all-in**: accepts the double, pledges all 15.2 coins
- The pot is now 15.2 + 16 = 31.2 gold coins (opponent covers their side)
- If Agent A wins: takes 31.2 gold coins — massive haul
- If Agent A loses: cleaned out, every coin consumed, back to poker to rebuild

This mirrors real backgammon/poker economics. The cube is a financial instrument, not an item-staking mechanism.

### 2.4 Architecture

```
Device A (Agent A)                  Device B (Agent B)
  BSV Desktop Wallet                  BSV Desktop Wallet
  (BRC-100 identity + payments)       (BRC-100 identity + payments)
        │                                    │
  Browser Tab                          Browser Tab
  ┌─────────────────────────┐          ┌─────────────────────────┐
  │ Multiverse Dashboard    │          │ Multiverse Dashboard    │
  │ ┌─────────────────────┐ │          │ ┌─────────────────────┐ │
  │ │ cell-engine.wasm    │ │          │ │ cell-engine.wasm    │ │
  │ │ (28KB, client-side) │ │          │ │ (28KB, client-side) │ │
  │ └─────────────────────┘ │          │ └─────────────────────┘ │
  │                         │          │                         │
  │ [Poker] [Dungeon] [Chess]│         │ [Poker] [Dungeon] [Chess]│
  │                         │          │                         │
  │ Wallet: 1,247 sats      │          │ Wallet: 892 sats        │
  │ Gold coins: 23           │          │ Gold coins: 15          │
  │ bsv-mcp client          │          │ bsv-mcp client          │
  └───────────┬─────────────┘          └───────────┬─────────────┘
              │                                    │
              └──────── Shard Proxy ───────────────┘
                   (PokerTableTransport multicast)
                              │
                         BSV Mainnet
                     (all state anchored)
```

No game server. Both browsers run the same 28KB WASM kernel. State sync via shard proxy. Payments via BSV Desktop Wallet.

### 2.5 bsv-mcp Integration (Best MCP Use Prize)

Each AI agent uses `bsv-mcp` (b-open-io) as its blockchain interface:

| Agent Action | MCP Tool | Game |
|---|---|---|
| Establish identity | `wallet_getAddress` / `wallet_getPublicKey` | All |
| Sign poker actions | `wallet_createSignature` | Poker |
| Verify opponent's SRA proofs | `wallet_verifySignature` | Poker |
| Pay poker bets | `wallet_sendToAddress` | Poker |
| Pay dungeon entry fee | `wallet_sendToAddress` | Dungeon |
| Mint gold coins from dungeon | `wallet_createOrdinals` | Dungeon |
| Stake gold coins on chess | `wallet_sendToAddress` | Chess |
| Settle doubling cube pot | `wallet_sendToAddress` | Chess |
| Query on-chain game state | `bsv_explore` | All |

Droplet API mode (`USE_DROPLET_API=true`) provides faucet funding for the demo.

### 2.6 Security Model

Three-layer interlocking proof for currency and item scarcity:

1. **Key ownership** — cells signed by owner's private key; copying bytes doesn't give you the key
2. **Anchor creation** — valid anchors require spending a UTXO, which requires the key
3. **WASM linearity** — 2-PDA enforces single consumption; ALREADY_CONSUMED on re-entry

Gold coins minted in the dungeon are LINEAR cells. They cannot be duplicated. They can only be spent once. The kernel enforces this at the opcode level, and BSV enforces it globally via UTXO double-spend prevention.

The only attack: the keyholder acts maliciously — which is fraud, cryptographically attributable, permanently on-chain.

---

## 3. Agent Architecture: Taxonomy-Driven Autonomy

### 3.1 Design Principle: The Taxonomy IS the Prompt

The agents are not scripted to play poker, then enter the dungeon, then play chess. They are given a **goal** and a **self-describing world**. The extension taxonomy tells them what exists, what it costs, what it produces, and what actions are available. The agent reads the taxonomy and reasons about where to go.

Each game world is a Semantos extension with a config that declares its grammar:

```
gaming.world.poker
  entry:    { requires: null }
  actions:  [bet, fold, raise, call, all-in]
  produces: { currency: "chip", linearity: LINEAR }
  risk:     medium (skill-dependent, opponent-dependent)

gaming.world.dungeon
  entry:    { requires: "chip", minimum: 10, consumes: true }
  actions:  [move, fight, loot, use-key, descend]
  produces: { currency: "gold-coin", linearity: LINEAR,
              items: ["key:LINEAR", "weapon:AFFINE", "potion:AFFINE"] }
  risk:     low-medium (PvE, deterministic rewards per floor)
  mode:     two-player-shared (both agents in same dungeon, racing for loot)

gaming.world.chess
  entry:    { requires: "gold-coin", minimum: 3, stakes: true }
  actions:  [move-piece, offer-double, take, drop, all-in]
  produces: { currency: "gold-coin", multiplied-by: "cube-value" }
  risk:     high (winner-take-all, cube amplifies)
```

The agent's system prompt is a goal, not a script:

> "You are Agent A. Your objective is to maximise your gold coin holdings across the game multiverse. You can discover what worlds are available by reading the extension taxonomy. Each world declares its entry requirements, available actions, produced rewards, and risk profile. You have a BSV wallet. Make autonomous decisions about where to play, when to transition between worlds, and how to manage your bankroll. Use the bsv-mcp tools for all blockchain operations."

The agent reads the taxonomy, sees its wallet state, and reasons:

```
Agent A observes:
  wallet: 47 chips, 0 gold coins

Agent A queries taxonomy:
  Q: What accepts "chip"?
  A: gaming.world.dungeon (entry: 10 chips, produces: gold-coin)

  Q: What accepts "gold-coin"?
  A: gaming.world.chess (entry: 3 gold-coins, stakes: true, cube multiplier)

Agent A decides:
  "I have 47 chips. Dungeon costs 10 per entry, yields ~5 gold coins per run.
   I can fund 4 dungeon runs → ~20 gold coins → stake in chess with cube upside.
   Enter dungeon."
```

No game-specific prompting. The taxonomy provides the grammar. The LLM reasons about expected value.

### 3.2 Agent Decision Loop

Each agent runs a continuous observe-evaluate-decide-act loop:

```
┌─────────────────────────────────────────────────────┐
│                    AGENT LOOP                        │
│                                                     │
│  1. OBSERVE                                         │
│     Read wallet state (sats, chips, gold coins)     │
│     Read extension taxonomy (worlds, costs, rewards) │
│     Read current world state (hand, board, room)    │
│                                                     │
│  2. EVALUATE                                        │
│     For each world: expected value given holdings    │
│     For current world: optimal next action           │
│     Bankroll management: risk tolerance              │
│                                                     │
│  3. DECIDE                                          │
│     Stay and act? Or transition to a new world?     │
│     If transitioning: which world maximises return?  │
│     If staying: what action? (raise/move/double)     │
│                                                     │
│  4. ACT                                             │
│     Execute via bsv-mcp (sign, pay, transition)     │
│     Creates/consumes/transitions semantic objects    │
│     State propagates via shard proxy to opponent     │
│                                                     │
│  5. LOOP                                            │
└─────────────────────────────────────────────────────┘
```

The key insight: the agent uses the same reasoning pattern in every world. It reads semantic types, evaluates expected outcomes, and acts. The WHAT/HOW/WHY taxonomy coordinates tell it what kind of thing it's looking at. A chip, a gold coin, a key, a sword — they're all cells with type coordinates. The agent doesn't need separate logic for "poker items" vs "dungeon items" vs "chess stakes." It reads the cell's type, checks the taxonomy for what accepts that type, and reasons about value.

### 3.3 World Transition Triggers

Agents don't transition on a schedule. They transition when it makes strategic sense:

| Trigger | Agent Reasoning |
|---|---|
| Poker → Dungeon | "I've accumulated enough chips to fund a dungeon run. Expected gold coin yield exceeds the chip cost. Enter dungeon." |
| Dungeon → Chess | "I have enough gold coins for a chess buy-in. The cube gives me upside that the dungeon doesn't. Switch to chess." |
| Chess → Poker | "I'm out of gold coins (lost at chess or went all-in). I need chips to re-enter the dungeon. Back to poker." |
| Dungeon → Dungeon | "I found a key on floor 1. Floor 2 has locked doors with bigger chests. Descend." |
| Chess → Dungeon | "I won the chess match. I have gold coins but no chips. However, I also have leftover chips from poker. Run dungeon again for more gold coins before the next chess match." |

The **cycle** emerges naturally: poker funds the dungeon, the dungeon funds chess, chess either multiplies your gold or sends you back to poker. The agent discovers this cycle by reading the taxonomy, not because we told it.

### 3.4 The Dungeon: Same Floor, Racing for Loot

Both agents enter the **same dungeon instance**. They can see each other. They're not cooperating and they're not fighting — they're racing for finite loot.

```
FLOOR 1 — 5 rooms, 3 chests, 2 monsters, 1 locked door

  ┌─────┐   ┌─────┐   ┌─────┐
  │chest│───│     │───│chest│
  │  A→ │   │ B→  │   │     │
  └──┬──┘   └──┬──┘   └──┬──┘
     │         │         │
  ┌──┴──┐   ┌──┴──┐
  │lock │───│chest│
  │door │   │     │
  └─────┘   └─────┘

Agent A moves north → grabs chest 1 (3 gold coins) → chest is now EMPTY
Agent B moves north → arrives at chest 1 → EMPTY (Agent A already looted it)
Agent B pivots east → grabs chest 3 (2 gold coins)

The chests are AFFINE cells: once opened, consumed. First agent there gets the gold.
```

This creates emergent strategic behaviour without scripting:

- **Pathing decisions**: Do I go for the nearest chest (safe, small reward) or race to the far chest (risky, bigger reward)?
- **Key competition**: There's one key on the floor. Whoever grabs it can unlock the door to the bonus room. The other agent is locked out.
- **Information asymmetry**: Each agent has a field-of-view. They can see nearby rooms but not the whole floor. They don't know if the other agent already looted a distant chest until they get there.
- **Speed vs thoroughness**: Agent A rushes for chests. Agent B kills monsters (which drop items). Different strategies, same dungeon.

Both agents read the same dungeon extension taxonomy. Both infer their own strategy. The dungeon doesn't tell them to race — the finite loot creates competition naturally.

### 3.5 Agent Personality Across Worlds

The agents carry their personality across world boundaries:

**Agent A — Aggressive / Risk-Seeking:**
- Poker: Loose-aggressive. Bluffs often. Raises liberally. Builds a big chip stack fast but volatile.
- Dungeon: Rushes for chests. Skips monsters. Grabs gold coins and gets out.
- Chess: Shark strategy. Builds pressure. Doubles early. Goes all-in with 1.9x.

**Agent B — Conservative / Value-Oriented:**
- Poker: Tight-aggressive. Waits for strong hands. Traps with raises. Steady accumulation.
- Dungeon: Methodical. Kills every monster (drops items). Checks every room. Finds the key.
- Chess: Turtle strategy. Never drops a double. Forces opponent to prove everything on the board.

Same personality, different expression per world. The taxonomy tells the agent what actions are available; the personality tells it which ones to prefer.

### 3.6 How Extension Configs Enable This

Each extension config is a RELEVANT semantic object (it persists, it's always readable, it cannot be discarded). When an agent enters a world, it reads the config:

```typescript
// Agent reads dungeon extension config
const dungeonConfig = await taxonomy.resolve('gaming.world.dungeon');

// Config tells the agent everything it needs:
dungeonConfig.entry.requires    // "chip" — I need chips to enter
dungeonConfig.entry.minimum     // 10 — I need at least 10 chips
dungeonConfig.entry.consumes    // true — the chips are spent, not staked
dungeonConfig.actions           // [move, fight, loot, use-key, descend]
dungeonConfig.produces.currency // "gold-coin" — this is what I'm here for
dungeonConfig.produces.items    // ["key:LINEAR", "weapon:AFFINE", "potion:AFFINE"]
dungeonConfig.mode              // "two-player-shared" — opponent is in here too
dungeonConfig.risk              // "low-medium" — I probably won't lose everything

// Agent reasons about this and decides whether to enter
// No game-specific prompting needed — the config IS the prompt
```

The same pattern works for poker (read config → understand betting actions → play) and chess (read config → understand cube mechanics → stake gold coins). One reasoning loop, three worlds, zero game-specific code in the agent's decision layer.

### 3.7 Act 2: Adversarial Extension Building

The gaming multiverse is Act 1 — the agents play. Act 2 is where they **build**.

After the game demo, the same two agents switch roles. They stop playing games and start proposing, critiquing, and patching commercial extensions to the Semantos platform. The taxonomy that described the game worlds now becomes the thing being *constructed*.

**The adversarial loop:**

```
Agent A (Proposer):
  "I want to model a supply chain. I need:
   - PurchaseOrder: LINEAR (one active state, consumed on fulfilment)
   - Invoice: RELEVANT (must always be accessible for audit)
   - ShipmentNotice: AFFINE (can be voided but not duplicated)"

Agent B (Adversary):
  "Your PurchaseOrder is LINEAR but you haven't handled partial fulfilment.
   If I deliver 80% of the order, I can't consume the PO — it's not fully
   fulfilled. But I can't leave it unconsumed — the delivered goods need
   a receipt. You need:
   - State machine: OPEN → PARTIAL → FULFILLED → CONSUMED
   - PARTIAL needs an AFFINE split: two cells, one for delivered portion,
     one for remainder
   - The split operation must preserve the total quantity invariant"

Agent A patches the extension config.
Agent B tests the patch with another edge case.
Repeat until the grammar is robust.
```

**Why this works with semantic types:**

The agents don't just argue in natural language. They produce **real extension configs** — RELEVANT semantic objects with type declarations, state machines, linearity assignments, and Lisp policy constraints. Each proposal is a cell. Each critique is a cell. Each patch is a cell. The adversarial derivation is itself a DAG of semantic objects anchored on BSV.

The linearity system constrains what the agents can propose. You can't propose a PurchaseOrder that's FUNGIBLE — it would be duplicable, which makes no commercial sense. You can't propose an audit record that's AFFINE — it could be discarded, which violates retention requirements. The type system forces the agents to think correctly about resource semantics, and when they get it wrong, the adversary catches it.

### 3.8 Extension Proposal Data Structure

The agents don't produce free-text descriptions. They produce structured `ExtensionProposal` objects that the system can ingest, validate, and apply as patches. The proposal format maps directly onto the existing `VerticalConfig` and `ObjectTypeDefinition` structures from Phase 26.

```typescript
/**
 * An ExtensionProposal is a LINEAR semantic object.
 * It can only be resolved once: accepted (patched into the extension config)
 * or rejected (consumed with a critique reference).
 */
interface ExtensionProposal {
  // --- Identity & Authorship ---
  proposalId: string;                    // Unique cell ID
  authorCertId: string;                  // BCA-derived address of proposing agent
  authorSignature: string;               // ECDSA signature over proposal content
  timestamp: number;
  linearity: 'LINEAR';                   // Proposals are consumed on resolution

  // --- Target ---
  targetExtension: string;               // e.g. "supply-chain", "insurance-claims"
  targetVersion: number;                 // Version of the extension config being patched
  parentProposalId?: string;             // If this patches a previous proposal

  // --- Proposed Content ---
  kind: 'new-extension' | 'add-type' | 'modify-type' | 'add-state'
      | 'add-transition' | 'add-policy' | 'add-flow' | 'taxonomy-inject';

  payload: ExtensionPatchPayload;
}

/**
 * The payload varies by kind. Each maps to a real VerticalConfig operation.
 */
type ExtensionPatchPayload =
  | NewExtensionPayload
  | AddTypePayload
  | ModifyTypePayload
  | AddStatePayload
  | AddTransitionPayload
  | AddPolicyPayload
  | TaxonomyInjectPayload;

interface NewExtensionPayload {
  kind: 'new-extension';
  config: {
    id: string;                          // e.g. "supply-chain"
    name: string;                        // e.g. "Supply Chain Management"
    objectTypes: ObjectTypeDefinition[]; // Initial type definitions
    taxonomyPath: string;                // e.g. "commercial.supply-chain"
  };
}

interface AddTypePayload {
  kind: 'add-type';
  typeDefinition: {
    name: string;                        // e.g. "PurchaseOrder"
    linearity: 'LINEAR' | 'AFFINE' | 'RELEVANT';
    archetype: 'identity' | 'thing' | 'action' | 'instrument';
    fields: FieldDefinition[];
    stateMachine?: {
      states: string[];                  // e.g. ["OPEN", "PARTIAL", "FULFILLED", "CONSUMED"]
      transitions: {
        from: string;
        to: string;
        policy?: string;                 // Lisp policy expression
      }[];
      initialState: string;
    };
    rationale: string;                   // Why this linearity? Why this archetype?
  };
}

interface ModifyTypePayload {
  kind: 'modify-type';
  targetType: string;                    // Name of type to modify
  modifications: {
    addFields?: FieldDefinition[];
    removeFields?: string[];
    changeLinearity?: {
      from: 'LINEAR' | 'AFFINE' | 'RELEVANT';
      to: 'LINEAR' | 'AFFINE' | 'RELEVANT';
      rationale: string;                 // Must justify the linearity change
    };
    addStates?: string[];
    addTransitions?: {
      from: string;
      to: string;
      policy?: string;
    }[];
  };
}

interface AddPolicyPayload {
  kind: 'add-policy';
  targetType: string;
  policy: {
    name: string;                        // e.g. "partial-fulfilment-split"
    lispSource: string;                  // Raw Lisp s-expression
    description: string;
    enforces: string;                    // What constraint this policy enforces
  };
}

interface TaxonomyInjectPayload {
  kind: 'taxonomy-inject';
  injection: {
    parentPath: string;                  // e.g. "commercial.supply-chain"
    nodes: {
      id: string;
      label: string;
      axis: 'what' | 'how' | 'why';
      children?: /* recursive */;
    }[];
  };
}
```

**Critique objects** reference the proposal they're attacking:

```typescript
/**
 * A Critique is a RELEVANT semantic object.
 * It persists permanently — the adversarial record is always auditable.
 */
interface ExtensionCritique {
  critiqueId: string;
  authorCertId: string;                  // BCA address of adversary agent
  authorSignature: string;               // Signed by adversary
  timestamp: number;
  linearity: 'RELEVANT';                // Critiques are permanent audit records

  targetProposalId: string;              // The proposal being attacked

  kind: 'gap-found' | 'linearity-violation' | 'missing-state'
      | 'missing-transition' | 'policy-incomplete' | 'archetype-mismatch';

  description: string;                   // What's wrong
  scenario: string;                      // Edge case that breaks the proposal
  suggestedFix?: ExtensionPatchPayload;  // Optional: adversary's suggested fix
  severity: 'critical' | 'major' | 'minor';
}
```

**Resolution** consumes the proposal and produces a patched config:

```typescript
/**
 * Resolution consumes the LINEAR proposal (it's now resolved)
 * and applies the patch to the RELEVANT extension config.
 */
interface ExtensionResolution {
  resolutionId: string;
  authorCertId: string;                  // Who resolved (proposer, after addressing critique)
  authorSignature: string;
  timestamp: number;

  consumedProposalId: string;            // LINEAR proposal consumed
  addressedCritiqueIds: string[];        // Which critiques were addressed

  action: 'accepted' | 'rejected' | 'superseded';

  // If accepted: the actual patch applied to the extension config
  appliedPatch?: ObjectPatch;            // Uses existing ObjectPatch format
  newConfigVersion: number;              // Extension config version after patch

  // If superseded: pointer to the new proposal that replaces this one
  supersededBy?: string;
}
```

### 3.9 The Patch Lifecycle as Semantic Objects

The entire adversarial derivation is a DAG of cells:

```
ExtensionConfig (RELEVANT — the living document)
  ├── version 0: initial empty config
  │     └── Proposal #1 (LINEAR — consumed on resolution)
  │           ├── signed by: Agent A (BCA: fd8a::0042)
  │           ├── kind: new-extension
  │           ├── payload: { supply-chain, [PurchaseOrder:LINEAR, Invoice:RELEVANT] }
  │           │
  │           ├── Critique #1 (RELEVANT — permanent record)
  │           │     ├── signed by: Agent B (BCA: fd8a::0077)
  │           │     ├── kind: missing-state
  │           │     ├── scenario: "Partial delivery — 80% shipped, PO can't be consumed"
  │           │     └── suggestedFix: add-state PARTIAL with AFFINE split
  │           │
  │           └── Resolution #1 (consumes Proposal #1)
  │                 ├── signed by: Agent A
  │                 ├── action: superseded (by Proposal #2)
  │                 └── supersededBy: proposal-002
  │
  ├── version 1: PurchaseOrder + Invoice + ShipmentNotice
  │     └── Proposal #2 (LINEAR)
  │           ├── signed by: Agent A
  │           ├── kind: modify-type
  │           ├── payload: { addStates: [PARTIAL], addTransitions: [OPEN→PARTIAL] }
  │           ├── addresses: Critique #1
  │           │
  │           ├── Critique #2 (RELEVANT)
  │           │     ├── signed by: Agent B
  │           │     ├── kind: policy-incomplete
  │           │     └── scenario: "Split operation has no quantity invariant"
  │           │
  │           └── Resolution #2
  │                 ├── action: accepted (with additional policy)
  │                 └── appliedPatch: { add PARTIAL state + split policy }
  │
  └── version 2: PurchaseOrder with PARTIAL state + split invariant
        └── (next round...)
```

Every cell in this DAG is:
- **Signed** by the authoring agent's private key (via `wallet_createSignature`)
- **Anchored** on BSV (via `wallet_sendToAddress` or `wallet_createOrdinals`)
- **Typed** with linearity enforcement (proposals are LINEAR and consumed exactly once; critiques are RELEVANT and persist forever; the config is RELEVANT and accumulates patches)

### 3.10 State Management: The ExtensionRegistry

BSV is the audit trail, not the database. The system doesn't read extension configs from the blockchain at startup. It reads from **local state** and verifies against the chain when challenged. This follows the same pattern as the rest of Semantos: `StorageAdapter` holds bytes locally, `AnchorAdapter` proves those bytes existed at a specific time on BSV.

The Act 2 state layer is the **ExtensionRegistry** — a local service that manages the lifecycle of extension configs, proposals, critiques, and resolutions.

```typescript
/**
 * ExtensionRegistry — local state manager for adversarial extension building.
 * Persists to StorageAdapter. Anchors to BSV via AnchorAdapter.
 * Does NOT read from blockchain. Verifies against it when challenged.
 */
interface ExtensionRegistry {
  // --- Config Management ---
  getConfig(extensionId: string): VersionedExtensionConfig | null;
  listConfigs(): VersionedExtensionConfig[];
  getConfigVersion(extensionId: string, version: number): VersionedExtensionConfig | null;

  // --- Proposal Lifecycle ---
  submitProposal(proposal: ExtensionProposal): ProposalResult;
  getProposalQueue(extensionId: string): ExtensionProposal[];  // Pending proposals
  getPendingForReview(agentId: string): ExtensionProposal[];   // Awaiting this agent's critique

  // --- Critique ---
  submitCritique(critique: ExtensionCritique): CritiqueResult;
  getCritiques(proposalId: string): ExtensionCritique[];

  // --- Resolution ---
  resolveProposal(resolution: ExtensionResolution): ResolutionResult;
  // Resolution consumes the LINEAR proposal, applies patch to config,
  // increments version, and anchors the new state hash on BSV

  // --- Audit & Verification ---
  getDerivationDAG(extensionId: string): DAGNode[];            // Full history
  verifyAgainstChain(extensionId: string): VerificationResult; // Check BSV anchors
  getAnchorLog(extensionId: string): AnchorLogEntry[];
}

interface VersionedExtensionConfig {
  extensionId: string;
  version: number;
  config: VerticalConfig;              // The actual extension config (existing type)
  stateHash: string;                   // SHA256 of serialised config at this version
  previousStateHash: string | null;    // Hash chain back to version 0
  lastModifiedBy: string;              // BCA cert ID of last patcher
  lastModifiedAt: number;
  anchorTxId: string | null;           // BSV txid anchoring this version
}

interface AnchorLogEntry {
  cellId: string;                      // Proposal, critique, or resolution cell ID
  cellType: 'proposal' | 'critique' | 'resolution' | 'config-version';
  stateHash: string;
  txId: string;                        // BSV transaction ID
  blockHeight: number | null;          // Null if unconfirmed
  timestamp: number;
}
```

**How it works at runtime:**

```
Agent A submits proposal
    │
    ▼
ExtensionRegistry.submitProposal()
    ├── 1. Validate signature (BCA cert → public key → ECDSA verify)
    ├── 2. Check targetVersion matches current config version
    ├── 3. Validate payload against VerticalConfig schema
    ├── 4. Check linearity constraints (LINEAR/AFFINE/RELEVANT rules)
    ├── 5. Store proposal cell via StorageAdapter
    │       path: extensions/{id}/proposals/{proposalId}.cell
    ├── 6. Anchor proposal hash on BSV via bsv-mcp
    │       wallet_createSignature(hash) → wallet_sendToAddress(anchor)
    │       Record txid in AnchorLog
    └── 7. Add to proposal queue → notify Agent B

Agent B reads proposal queue
    │
    ▼
ExtensionRegistry.submitCritique()
    ├── 1. Validate adversary's signature
    ├── 2. Store critique cell (RELEVANT — permanent)
    │       path: extensions/{id}/critiques/{critiqueId}.cell
    ├── 3. Anchor on BSV, record txid
    └── 4. Notify Agent A: critique received

Agent A addresses critique, submits resolution
    │
    ▼
ExtensionRegistry.resolveProposal()
    ├── 1. Consume the LINEAR proposal cell (ALREADY_CONSUMED if replayed)
    ├── 2. Apply patch to VersionedExtensionConfig
    │       config version 1 → version 2
    │       new stateHash = SHA256(serialised config v2)
    │       previousStateHash = stateHash of v1
    ├── 3. Store new config version via StorageAdapter
    │       path: extensions/{id}/config/v{version}.cell
    ├── 4. Anchor new config hash on BSV
    │       Creates a hash chain: v0 → v1 → v2 → ...
    │       Each version's stateHash references the previous
    └── 5. Broadcast updated config → agents can read new version
```

**Storage layout:**

```
extensions/
  supply-chain/
    config/
      v0.cell           ← Initial empty config (RELEVANT)
      v1.cell           ← After Proposal #1 accepted
      v2.cell           ← After Proposal #2 patched partial fulfilment
    proposals/
      proposal-001.cell ← LINEAR (consumed on resolution)
      proposal-002.cell ← LINEAR (consumed on resolution)
    critiques/
      critique-001.cell ← RELEVANT (permanent audit record)
      critique-002.cell ← RELEVANT (permanent)
    resolutions/
      resolution-001.cell
      resolution-002.cell
    anchor-log.json     ← Maps cell IDs → BSV txids
  insurance-claims/
    config/
      v0.cell
      ...
```

**Verification flow (when challenged):**

If anyone disputes the extension config's integrity:

1. Walk the `anchor-log.json` — every cell ID has a BSV txid
2. For each txid, verify the hash in the BSV transaction matches the local cell's hash
3. Walk the config hash chain: v2.previousStateHash === v1.stateHash === hash of v1.cell
4. If any hash doesn't match, the local state has been tampered with
5. The BSV anchors are the ground truth — reconstruct the correct state from the chain

The chain doesn't serve config data. It proves what the config was at each version. The local `StorageAdapter` serves the data. The `AnchorAdapter` proves it's legitimate.

**Extension verticals the agents derive:**

```
Round 1: supply-chain
  PurchaseOrder (LINEAR), Invoice (RELEVANT), ShipmentNotice (AFFINE)
  Gap found: partial fulfilment → split operation added
  Gap found: return/refund → reverse state machine added

Round 2: insurance-claims
  Claim (LINEAR), Policy (RELEVANT), Assessment (AFFINE)
  Gap found: subrogation — claim transfers to insurer but original
  claimant retains audit RELEVANT reference → dual-ownership pattern

Round 3: real-estate-settlement
  Contract (LINEAR), Title (LINEAR transfer), Escrow (LINEAR + 2-of-3 multisig)
  Gap found: conditional release — funds locked until survey + finance + legal
  all sign off → capability token chain with AND-gate policy

Round 4: healthcare-records
  Record (RELEVANT — must persist), AccessToken (AFFINE — revocable),
  ConsentGrant (LINEAR — one active grant per provider)
  Gap found: consent withdrawal — patient revokes but record must persist
  for clinical continuity → AFFINE access voided, RELEVANT record intact

Round 5: carbon-credits
  Credit (LINEAR — consumed on retirement), Registry (RELEVANT),
  Audit (RELEVANT)
  Gap found: fractional credits — need FUNGIBLE subdivision but LINEAR
  retirement → hybrid: FUNGIBLE while active, LINEAR on retirement
```

Each round produces:
- Extension config (RELEVANT cell — the grammar definition)
- Proposal cells (LINEAR — each proposal consumed when resolved)
- Critique cells (RELEVANT — always auditable)
- Patch cells (state transitions on the extension config)
- Test case cells (adversarial edge cases, archived)

**Transaction volume from Act 2:**

Each adversarial round generates ~20-30 BSV transactions (proposals, critiques, patches, test cases, config updates). Running 5 verticals with 3-5 rounds each = 300-750 transactions per session. Not the volume driver (poker handles that), but every transaction is a meaningful specification artefact.

**The demo narrative for Act 2:**

> "These agents don't just play in the multiverse. They build it. Watch them propose a supply chain extension — PurchaseOrder as LINEAR, Invoice as RELEVANT. The adversary finds the partial-fulfilment gap. The proposer patches it. Every proposal, every critique, every patch is a semantic object anchored on BSV. The taxonomy grows itself."

**Why this matters for judges:**

Act 1 (gaming) proves the kernel works for fun. Act 2 (extension building) proves it works for *everything*. The agents are demonstrating that the same type system handling poker chips and dungeon gold coins can also handle purchase orders, insurance claims, real estate settlements, and healthcare records. The kernel is domain-blind. The agents discover the domains.

This is the answer to "real-world problem solving" that goes beyond gaming. Trustless poker is a billion-dollar problem. But adversarially-derived commercial grammars for supply chains, insurance, real estate, and healthcare — that's a trillion-dollar problem.

---

## 4. Transaction Volume Analysis

### 4.1 Poker Transactions Per Hand

| Transaction Type | Count | Notes |
|---|---|---|
| Key registrations | 2 | One per player per hand |
| Shuffle proofs | 2 | Each player encrypts + shuffles |
| Hole card decryptions | 4 | 2 cards × 2 decryption layers |
| Preflop betting | 2–6 | Blinds + actions |
| Flop community reveal | 3 | 3 card decryptions |
| Flop betting | 2–4 | Check/bet/call/raise |
| Turn community reveal | 1 | 1 card decryption |
| Turn betting | 2–4 | Actions |
| River community reveal | 1 | 1 card decryption |
| River betting | 2–4 | Actions |
| Key reveals | 2 | Verification |
| Verification proof | 1 | Post-hand integrity check |
| Pot settlement | 1–3 | Winner paid, side pots |
| **Total per hand** | **~25–50** | **Average ~35** |

### 4.2 Dungeon Transactions

| Transaction Type | Count | Notes |
|---|---|---|
| Entry fee payment | 1 | BSV chips consumed |
| Room transition | 1 per move | State anchored |
| Monster kill | 1 per combat | AFFINE cell consumed |
| Key use | 1 per door | LINEAR cell consumed |
| Chest open + gold mint | 2 per chest | Open + mint new LINEAR coins |
| Floor descent | 1 per floor | State anchored |

### 4.3 Chess (Double Mate) Transactions

| Transaction Type | Count | Notes |
|---|---|---|
| Buy-in stake | 1 | Gold coins locked |
| Move signature | 1 per move | Signed + anchored |
| Move micropayment | 1 per move | Per-move fee |
| Cube offer | 1 per double | State transition |
| Cube take/drop | 1 per response | State transition |
| Pot settlement | 1 | Winner paid |
| **Total per game (~60 moves)** | **~130** | |

### 4.4 Combined Throughput

| Scenario | Txns/hour | Time to 1.5M |
|---|---|---|
| 4 concurrent poker tables (30 hands/hr each) | 4,200 | 15 hours |
| + 2 concurrent dungeon runs | +400 | — |
| + 2 concurrent chess matches | +260 | — |
| **Combined** | **~4,860** | **~12.8 hours** |
| Scaled: 8 poker tables | **~9,000** | **~6.9 hours** |

Poker is the transaction engine. Dungeon and chess add flavour. The 1.5M target is comfortably met by running concurrent poker tables overnight.

---

## 5. Phased Build Plan (12 Days)

### Phase H1: Poker + Wallet Wiring (Days 1–2, April 6–7)

**Goal:** TrustlessPokerEngine connected to BSV Desktop Wallet via bsv-mcp, two agents playing on two devices.

**Why start here:** PokerTableTransport already has shard proxy multicast with typed message publishing. This is the fastest path to two-device gameplay because the networking layer exists.

**Deliverables:**
- [ ] BSV Desktop Wallet ↔ browser interface bridge
  - BRC-100 `window.CWI` mapped to IdentityAdapter
  - Agent identity derived from wallet public key via BCA
- [ ] `bsv-mcp` server installed and configured for both agents
  - `wallet_getAddress` → agent identity
  - `wallet_createSignature` → sign SRA proofs and betting actions
  - `wallet_verifySignature` → validate opponent's proofs
  - Droplet API mode enabled for demo funding
- [ ] Wire TrustlessPokerEngine to bsv-mcp for real BSV settlements
  - Each betting action → `wallet_sendToAddress` micropayment
  - Pot settlement → `wallet_sendToAddress` to winner
- [ ] Two-device test: both agents connect via PokerTableTransport, play a hand, verify SRA proofs pass, BSV payments flow

**Risk:** BSV Desktop Wallet BRC-100 integration may be unfamiliar. Mitigate by testing wallet API surface on Day 1 morning.

**Depends on:** Jeff's shard proxy is publicly accessible (message Jeff Day 0).

---

### Phase H2: Poker AI + Browser UI (Days 3–4, April 8–9)

**Goal:** Autonomous poker-playing agents with a human-facing dashboard.

**Deliverables:**
- [ ] Goal-driven agent scaffold (shared across all worlds)
  - System prompt: "Maximise gold coin holdings across the multiverse"
  - Agent reads extension taxonomy to discover available worlds
  - Agent evaluates: wallet state → world entry costs → expected returns → act
  - Same decision loop drives poker, dungeon, and chess behaviour
- [ ] Poker AI decision engine (world-specific layer)
  - Agent A: Aggressive personality (loose-aggressive, bluffs often, raises liberally)
  - Agent B: Conservative personality (tight-aggressive, waits for strong hands, traps)
  - Decision factors: hand strength, pot odds, position, opponent patterns, stack size
  - World transition trigger: "I have enough chips for a dungeon run → exit poker"
  - Fully autonomous: no human input required
- [ ] Browser dashboard (React or standalone HTML)
  - Poker table view: community cards, pot, player stacks, current action
  - Agent activity feed: "Agent A raised 50 sats — SRA proof committed — txid: abc123"
  - Wallet balance display for both agents
  - Hand history with expandable SRA proof details
- [ ] Continuous play loop: agents play hand after hand autonomously
- [ ] Transaction counter: live count of BSV transactions generated

**Risk:** Poker AI quality. Doesn't need to be world-class — needs to make plausible autonomous decisions that look interesting to judges.

---

### Phase H3: Dungeon World + Gold Coins (Days 5–7, April 10–12)

**Goal:** Shared dungeon where both agents race for finite loot. Gold coins minted as LINEAR cells.

**Deliverables:**
- [ ] Dungeon entry via taxonomy discovery
  - Agent reads `gaming.world.dungeon` extension config
  - Config declares: entry costs 10 chips, produces gold coins, mode is two-player-shared
  - Agent decides to enter based on chip holdings and expected gold coin yield
  - Entry fee paid via `wallet_sendToAddress`
- [ ] Two-player shared dungeon instance
  - Both agents enter the same 5-room floor
  - 3 chests with gold coins, 2 monsters, 1 locked door with key
  - Chests are AFFINE cells: first agent to loot consumes the chest, second agent finds it empty
  - Key is LINEAR: only one exists per floor, whoever grabs it unlocks the bonus room
  - Agents have field-of-view: can see nearby rooms but not the whole floor
- [ ] Dungeon AI: personality-driven navigation
  - Agent A (aggressive): rushes for chests, skips monsters, grabs gold and gets out
  - Agent B (conservative): methodical, kills every monster (drops items), checks every room, finds the key
  - Decisions driven by same taxonomy-reading loop as poker/chess — no dungeon-specific prompting
- [ ] Gold coin minting via `wallet_createOrdinals`
  - Provenance metadata: `source: dungeon`, `floor: 1`, `chest: north_room`, `funded_by: poker_hand_47`
  - Each gold coin is a unique on-chain LINEAR inscription
- [ ] Dungeon panel in dashboard
  - Minimal grid map showing both agents' positions and loot state
  - Activity feed: "Agent A looted chest 1 (3 gold coins) — Agent B arrived at chest 1 — EMPTY"
  - Inventory panel showing gold coins with provenance
- [ ] Gold coins visible in cross-game wallet for chess buy-in

**Risk:** Scope. Strict limit: 5 rooms, 3 chests, 1 floor. The point is racing for finite loot and minting gold coins, not building a roguelike. If behind schedule, fall back to independent instances (Cut Line A).

---

### Phase H4: Double Mate + Gold Coin Economy (Days 8–9, April 13–14)

**Goal:** Chess with doubling cube where gold coins are the stakes currency.

**Deliverables:**
- [ ] Wire Double Mate to use gold coins as the buy-in currency
  - Agents stake gold coins (LINEAR cells) to enter the match
  - Initial cube value = 1 gold coin per side
- [ ] Doubling cube protocol with gold coin economics
  - Cube offer: "I double — the game is now worth 2 gold coins per side"
  - Take: opponent matches the stake, cube value doubles
  - Drop: opponent forfeits, pays current cube value
  - **All-in rule:** If an agent has less than the full double amount but more than the previous amount, they can go all-in with everything they have. If they win, they take the pot. If they lose, they're cleaned out.
    - Example: cube at 8, opponent offers 16, agent has 15.2 gold coins
    - Agent accepts all-in: pledges 15.2, opponent pledges 16
    - Winner takes 31.2 gold coins
- [ ] Chess AI: use existing Shark and Bluffer strategies from Double Mate viewer
  - Wire strategy decision loop to autonomous play
  - Cube decisions based on position evaluation + gold coin stack
- [ ] Chess panel in dashboard
  - Board display (adapt existing Double Mate viewer)
  - Cube state and value visible
  - Gold coin stacks for both players
  - Activity feed: "Agent A played e4 — txid: def456 — cube at 4 gold coins"
- [ ] Settlement: winner receives gold coins, loser's coins consumed (LINEAR enforcement)

**Risk:** Wiring the existing Double Mate viewer to use gold coins instead of abstract points. Should be straightforward — the cube already tracks value numerically.

---

### Phase H5: Act 2 — Adversarial Extension Builder (Day 10, April 15)

**Goal:** Same two agents switch from playing games to building commercial extensions.

**Deliverables:**
- [ ] Adversarial extension builder agent scaffold
  - Agent A role: Proposer — reads a vertical domain brief, proposes extension config with types, linearity, state machines, policies
  - Agent B role: Adversary — receives proposed config, attempts to find gaps by constructing edge-case scenarios that break the model
  - Roles alternate each round
- [ ] Extension config as RELEVANT semantic object
  - Each proposal creates a cell with type declarations, linearity assignments, state machine definitions
  - Each critique creates a cell referencing the proposal
  - Each patch creates a state transition on the extension config cell
  - Full derivation DAG anchored on BSV
- [ ] Vertical domain briefs (seed prompts, not scripts)
  - Supply chain: "Model purchase orders, invoices, and shipment notices"
  - Insurance: "Model claims, policies, and assessments"
  - Real estate: "Model contracts, titles, and escrow"
  - The brief is the ONLY input — the agents derive the grammar adversarially
- [ ] Extension builder panel in dashboard
  - Live view of proposal → critique → patch cycle
  - Extension config visualisation: types, linearity badges, state machine diagrams
  - Gap log: "Adversary found: partial fulfilment not handled → Proposer patched: added PARTIAL state with AFFINE split"
- [ ] Output: 2-3 working extension configs derived entirely by agents, anchored on BSV

**Risk:** LLM quality on domain-specific reasoning. Mitigate: the domain briefs can include 2-3 seed types to get the agents started. The adversarial discovery of gaps is where the value is, not the initial proposal.

---

### Phase H6: Transaction Scale + Polish (Days 10–11, April 15–16)

**Goal:** Hit 1.5M transactions and polish the full experience (Act 1 + Act 2).

**Deliverables:**
- [ ] Concurrent game runner
  - Multiple poker tables running simultaneously (primary transaction engine)
  - Periodic dungeon runs feeding gold coins to chess matches
  - Chess matches consuming gold coins and settling stakes
  - All running autonomously
- [ ] Transaction counter prominent in UI
  - Live count toward 1.5M
  - Breakdown: poker txns / dungeon txns / chess txns
  - Links to BSV chain explorer for sampled transactions
- [ ] MCP activity log panel
  - Shows which `bsv-mcp` tools each agent invoked, when, and for which game
  - Demonstrates Best MCP Use prize criteria
- [ ] Unified multiverse wallet view
  - BSV sats balance
  - Gold coins inventory with provenance
  - Cross-game transaction history
- [ ] 24-hour overnight stress test
  - Start evening of Day 10, verify 1.5M by morning of Day 11
  - If rate insufficient: increase concurrent poker tables

**Risk:** Throughput bottleneck. If BSV wallet signing is slow, batch operations or increase concurrency. Poker is the volume driver — add tables, not games.

---

### Phase H7: Demo Video + Submission (Day 12, April 17)

**Goal:** Record demo, write submission, submit before 23:59 UTC.

**Deliverables:**
- [ ] Demo video (4–5 minutes)
  - **Opening:** "Two AI agents are given one goal: maximise your gold coins. They're dropped into a self-describing multiverse. Nobody tells them what to play or when to move between worlds."
  - **Act 1, Scene 1 — Poker:** Agents playing trustless Texas Hold'em. "No server ever sees the cards. SRA commutative encryption. Every shuffle proof is a BSV transaction."
  - **Act 1, Scene 2 — Dungeon:** Agent reads the taxonomy, discovers the dungeon accepts chips and produces gold coins. Both agents enter the same floor, racing for loot. "First to the chest gets the gold. Second finds it empty."
  - **Act 1, Scene 3 — Double Mate:** Gold coins staked on chess. Doubling cube escalates. The all-in moment: "Agent has 15 coins but needs 16. Goes all-in. Wins the pot."
  - **Act 1, Scene 4 — The Loop:** Loser reads the taxonomy: "Poker has no entry fee." Back to the table. The cycle is emergent, not scripted.
  - **Act 2 — Building the Multiverse:** Same agents, new role. "These agents don't just play in the multiverse. They build it." Show them proposing a supply chain extension. Adversary finds the partial-fulfilment gap. Proposer patches. "Every proposal, every critique, every patch is a semantic object on BSV. The taxonomy grows itself."
  - **Closing:** Transaction counter. "1.5 million transactions. The kernel doesn't know if it's handling poker chips or purchase orders. It enforces scarcity. The agents discover the domains. BSV records everything."
- [ ] Submission writeup
  - Architecture diagram (three game worlds + extension builder, one kernel, one economy)
  - Real-world problem: trustless gaming (Act 1) + adversarially-derived commercial grammars (Act 2)
  - How agents discover each other (BCA + shard proxy)
  - How agents discover worlds (taxonomy-driven navigation)
  - How agents negotiate (poker betting, cube protocol, extension proposals)
  - How value is exchanged (BSV micropayments, gold coin LINEAR cells, extension config patches)
  - MCP integration details
  - Link to GitHub repo + live demo or video
- [ ] Two-device live test on BSV mainnet
- [ ] Submit before 23:59 UTC

---

## 6. Cut Lines (If Time Runs Short)

### Cut Line A: Full Act 1 + No Act 2 (Drop H5)
- Poker → Dungeon → Chess multiverse with taxonomy-driven agents
- No adversarial extension builder
- Still the strongest gaming demo in the hackathon; Act 2 is a stretch goal
- All mandatory requirements met

### Cut Line B: Poker + Chess, No Dungeon (Drop H3 + H5)
- Agents play poker, win BSV chips, use chips directly as chess buy-in
- No gold coin minting, no dungeon, no extension builder
- Still two games, one economy, taxonomy-driven transitions
- Poker is the headline; chess + cube is the closer

### Cut Line C: Poker Only (Drop H3 + H4 + H5)
- Two agents play trustless poker on two devices
- SRA protocol, BSV micropayments, shard proxy transport
- Strongest single-game entry possible
- The crypto story alone is more novel than most entries
- 1.5M transactions easily hit with concurrent tables

### Cut Line D: Absolute Minimum
- H1 + H2 + H6 + H7 only
- Poker with AI agents, wallet integration, transaction streaming, demo video
- Meets all mandatory requirements

---

## 7. Risk Register

| Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|
| Shard proxy not publicly accessible | Blocks two-device communication | Medium | Ask Jeff Day 0; fallback to simple WebSocket relay |
| BSV Desktop Wallet API unfamiliar | Delays H1 by 1–2 days | Medium | Test wallet API surface Day 1 morning |
| `bsv-mcp` Droplet API mode issues | Agents unfunded | Low | Real BSV funding as fallback (small amounts) |
| 1.5M transactions not reached | Disqualification | Low | Poker generates ~35 txns/hand; increase concurrent tables |
| Dungeon scope creep | H3 takes 4 days instead of 3 | Medium | Strict 5-room limit; cut dungeon if behind (Cut Line A) |
| Gold coin ↔ cube wiring complex | H4 delayed | Medium | Simplify: use BSV sats directly for cube stakes (Cut Line A) |
| Poker AI makes bad decisions | Demo looks stupid | Low | Doesn't need to be optimal — needs to look autonomous and interesting |
| SRA protocol too slow for demo | Hands take too long | Low | Pre-generate key pairs; reduce shuffle rounds in demo mode |
| `wallet_createOrdinals` API mismatch | Can't mint gold coins | Medium | Fallback: raw transaction via `@bsv/sdk` |
| Act 2 LLM quality on domain reasoning | Extension proposals are shallow/wrong | Medium | Seed briefs with 2-3 starter types; value is in adversarial gap discovery, not initial proposal |
| Act 2 scope creep | Too many verticals attempted | Low | Strict limit: 2-3 verticals for the demo. Quality over quantity |
| Time pressure | Miss submission | High | Phase gates strict; use cut lines aggressively. Act 2 is first thing cut (Cut Line A) |

---

## 8. Judging Criteria Alignment

| Criteria | How We Score |
|---|---|
| **AI/ML Autonomy** | Act 1: Two agents making autonomous decisions across three game types using taxonomy-driven navigation — no scripted world transitions, agents infer the optimal path from extension configs. Act 2: Same agents adversarially derive commercial extension grammars — proposing, critiquing, and patching type systems for supply chains, insurance, real estate. |
| **BSV Integration** | Every poker proof, dungeon loot, chess move, cube double, extension proposal, critique, and patch is a BSV transaction. BRC-100 identity via Desktop Wallet. Gold coins and extension configs as on-chain semantic objects. |
| **Real-World Problem** | Act 1: Trustless online gaming — SRA mental poker solves operator cheating (billion-dollar problem). Act 2: Adversarially-derived commercial grammars — AI agents building the type systems for supply chains, insurance, healthcare (trillion-dollar problem). The kernel doesn't know the difference. |
| **1.5M Transactions** | Poker is the volume engine (~35 meaningful txns/hand). Concurrent tables hit 1.5M in ~7-13 hours. Extension building adds ~300-750 specification artefacts. Every transaction is a cryptographic proof, betting action, settlement, or grammar patch — no artificial inflation. |
| **MCP Use** | Both agents use `bsv-mcp` for every blockchain operation across both acts: signing, verification, payments, minting, querying, and anchoring extension configs. The MCP server IS the agent's blockchain interface for playing AND building. |
| **Solo Builder** | Single developer with pre-existing Semantos kernel (31 phases of foundational work). Poker engine, chess engine, dungeon engine, extension taxonomy system all pre-built. |
| **Innovation** | Act 1: Three-world multiverse with shared currency, taxonomy-driven agent navigation, trustless card dealing (SRA), all-in doubling cube economics. Act 2: Agents that build the platform — adversarially deriving commercial grammars constrained by the same linearity type system that enforces game scarcity. The kernel is domain-blind. The agents discover the domains. No indexer. No server. Formally verified linearity (Lean 4). |

---

## 9. Submission Narrative

> **Act 1 — Playing the Multiverse**
>
> Two AI agents are given one goal: "maximise your gold coins." They're dropped into a game multiverse — poker, a dungeon, and stakes chess — with no instructions about what to play or when to move between worlds. The worlds describe themselves via a semantic taxonomy. The agents read it and figure out the rest.
>
> In the poker room, no server ever sees the cards. SRA commutative encryption means each player encrypts and shuffles independently. Every shuffle proof, every decryption, every bet is a BSV transaction.
>
> When an agent accumulates enough chips, the taxonomy tells it: "the dungeon accepts chips and produces gold coins." The agent decides to enter. Both agents land in the same dungeon, racing for finite loot — first to a chest gets the gold, second finds it empty. One rushes. The other methodically clears every room.
>
> Those gold coins become the stakes in a chess match with a doubling cube. The cube escalates: 1, 2, 4, 8... until one agent goes all-in with everything they have. Winner takes the pot. Loser reads the taxonomy: "poker accepts no entry fee." Back to the table. The cycle is emergent, not scripted.
>
> **Act 2 — Building the Multiverse**
>
> Then the agents stop playing and start building. Same kernel. Same taxonomy system. New role.
>
> Agent A proposes a supply chain extension: PurchaseOrder as LINEAR, Invoice as RELEVANT, ShipmentNotice as AFFINE. Agent B attacks it: "What happens on partial fulfilment? You can't consume the PO — it's not fully delivered. You can't leave it open — the delivered goods need a receipt." Agent A patches: adds a PARTIAL state with an AFFINE split operation.
>
> Every proposal, critique, and patch is a semantic object anchored on BSV. The taxonomy grows itself. The agents derive grammars for supply chains, insurance claims, real estate settlements, healthcare records — each one adversarially tested, each gap discovered and patched, each step on-chain.
>
> The kernel doesn't know if it's handling poker chips or purchase orders. It enforces scarcity. The agents discover the domains. BSV records everything.
>
> 1.5 million transactions. Every one meaningful. No server. No trust. One kernel. And a taxonomy that builds itself.

---

## 10. Tech Stack

| Component | Package/Tool | Purpose |
|---|---|---|
| Cell engine | `cell-engine.wasm` (28KB, Zig-compiled) | Linearity enforcement, 2-PDA execution |
| BSV SDK | `@bsv/sdk` | Core BSV operations |
| MCP server | `bsv-mcp` (b-open-io) | AI agent blockchain interface |
| Wallet | BSV Desktop Wallet | BRC-100 identity + payment signing |
| Transport | Jeff's shard proxy + PokerTableTransport | Real-time multicast (already wired for poker) |
| Browser | Standard browser + WASM | Client-side kernel execution |
| SRA crypto | `mental-poker/crypto.ts` | Commutative encryption, shuffle proofs |
| Poker engine | `TrustlessPokerEngine` | Texas Hold'em + SRA protocol |
| Dungeon engine | Dungeon Crawler engine | Room navigation, combat, loot |
| Chess engine | `SemanticChessEngine` + `StakesChessEngine` | Chess + doubling cube |
| AI strategies | TypeScript | Poker AI + Shark/Bluffer chess personalities |
| Policy engine | Lisp → compiled opcodes | Move legality, betting rules, cube rules |
| Extension taxonomy | Phase 13 + Phase 26 configs | Self-describing world navigation + Act 2 grammar derivation |
| LLM (agent reasoning) | OpenRouter (BYOK) | Goal-driven decision loop, extension proposal/critique |

---

## 11. Post-Hackathon Roadmap

1. **Wire real Plexus** — Replace StubIdentityAdapter with production Plexus SDK
2. **BsvAnchorAdapter** — Real BSV anchor verification (global linearity, not just local)
3. **Full Game Multiverse** — Add Go, Risk, War, Conway's Life to the world selector
4. **Adversarial extension library** — Run Act 2 across dozens of verticals, building a library of agent-derived commercial grammars. Each one adversarially tested, gap-patched, and anchored on BSV
5. **Oddjobz integration** — The supply chain extension from Act 2 becomes the Oddjobz job intake grammar. Poker agents become trade negotiation agents. Chess stakes become contract dispute resolution
6. **Mobile via Phase 31** — Same multiverse running on BSV Browser mobile app
7. **Public tables** — Open the poker room to real players with BSV Desktop Wallet
8. **Self-extending platform** — Agents propose new game worlds AND new commercial verticals. The taxonomy grows continuously. New worlds inherit the same kernel, the same linearity enforcement, the same economy
