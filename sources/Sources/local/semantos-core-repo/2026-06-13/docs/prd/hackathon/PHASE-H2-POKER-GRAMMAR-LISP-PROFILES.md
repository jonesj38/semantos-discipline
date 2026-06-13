---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/hackathon/PHASE-H2-POKER-GRAMMAR-LISP-PROFILES.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.761431+00:00
---

# Phase H2 — Poker Extension Grammar + Lisp Personality Profiles

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 3–4 days (concentrated sprint)
**Prerequisites**: Phase 21 complete (Lisp axiom compiler), Phase 27 complete (poker engine), Phase 36A complete (extension grammar schema)
**Branch**: `hackathon/h2-poker-grammar`

---

## Context

The Semantos Hackathon infrastructure now has:
- A fully-functional Lisp-to-bytecode compiler (Phase 21: `packages/shell/src/lisp/compiler.ts`) that deterministically transforms S-expressions into Forth-like Bitcoin Script opcodes
- A complete trustless poker engine (Phase 27: `packages/poker-agent/`, `packages/game-sdk/`) supporting mental poker, SRA hand evaluation, and betting validation
- An extension grammar schema (Phase 36A) that declares semantic object types with linearity, source entities, and field mappings

This phase marries all three: define the `depin.poker` extension grammar following the ExtensionGrammar JSON schema, then author three distinct Lisp personality profiles (The Nit, The Maniac, The Calculator) that compile to deterministic Forth bytecode. The poker engine selects a profile based on the `BOT_PERSONA` environment variable at runtime, loads the compiled policy, and uses it to make trustless, verifiable decisions.

### The Problem (What This Solves)

In traditional online poker:
- Bots are opaque black boxes; players can't audit their logic
- Decisions are signed assertions, not executable proofs
- No way to verify two rounds of the same bot use the same strategy
- Collusion is undetectable

Semantos solves all four:

| Problem | Semantos Mechanism |
|---------|-------------------|
| Audit trail | Lisp source → compiled Forth → bytecode hex (public) |
| Proof of behavior | SIGHASH_ALL signs the exact bytecode executed |
| Determinism | Same bytecode always executes the same way on same inputs |
| Collusion detection | Cell linearity prevents reusing decisions; each hand commits |

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              Poker Lisp Personality Profiles               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  (define (nit-decide hand-strength pot-odds) ...)          │
│  ↓ Phase 21 Lisp Compiler                                  │
│  [Script bytecode: pushes, field-loads, comparisons, ...]  │
│  ↓ Packer (phase 21 packer.ts)                             │
│  Hex string: "4c 20 0x... OP_LOADFIELD ..."                │
│                                                              │
│  Each decision action becomes a LINEAR cell:               │
│  - payload: { hand_strength: 0.85, action: "call" }        │
│  - signature: SIGHASH_ALL over entire bytecode             │
│  - references: [depin.poker.hand, depin.poker.table]       │
│                                                              │
│  Verifier reproduces bytecode hash → trusts the decision    │
│                                                              │
└─────────────────────────────────────────────────────────────┘

                            ┌──────────────────────┐
                            │  Poker Engine        │
                            │  (game-sdk)          │
                            │  TrustlessEngine     │
                            └──────────────────────┘
                                      ↑
                    ┌─────────────────┼──────────────────┐
                    │                 │                  │
              ┌─────┴──────┐  ┌──────┴────┐  ┌──────┴─────┐
              │ Nit        │  │ Maniac    │  │ Calculator │
              │ (profile)  │  │ (profile) │  │ (profile)  │
              │ bytecode   │  │ bytecode  │  │ bytecode   │
              └────────────┘  └───────────┘  └────────────┘
                    ↑                │                ↑
                    └────────────────┼────────────────┘
                     BOT_PERSONA env var selects
```

---

## Part A: depin.poker Extension Grammar

### Grammar Definition

The `depin.poker` extension declares all poker-related semantic object types following the Phase 36A ExtensionGrammar schema.

**Grammar ID**: `com.semantos.depin.poker`
**Taxonomy namespace**: `depin.poker`
**Author**: Semantos Core Team (hackathon phase)

### Object Types with Linearity

All poker cell types follow the extension grammar pattern:

| Type Path | Linearity | Description | Anchor | Phases |
|-----------|-----------|-------------|--------|--------|
| `depin.poker.hand` | LINEAR | Player's dealt hand. Consumed once on showdown. | Required | SOURCE → ACTION → OUTCOME |
| `depin.poker.action` | LINEAR | Fold / call / raise / check. Consumed once, verifiable per betting round. | Required | SOURCE → ACTION |
| `depin.poker.shuffle.proof` | RELEVANT | Cryptographic proof of fair shuffle (DH-based). Referenceable post-hoc, not consumed. | Optional | EVIDENCE |
| `depin.poker.deck` | AFFINE | The shoe of undealt cards. Used (cards drawn) or discarded (hand ends). | Optional | SOURCE |
| `depin.poker.pot` | LINEAR | Table pot state. Consumed on showdown when winnings distributed. | Required | ACTION → OUTCOME |
| `depin.poker.table` | RELEVANT | Persistent table state (seats, bet round, community cards). Reference data, never consumed. | Optional | SOURCE |
| `depin.poker.seat` | AFFINE | A player's seat assignment. Taken when seated, abandoned on leave. | Optional | ACTION |
| `depin.poker.payment.tick` | LINEAR | MFP channel payment tick. Consumed on settlement (buyin, payout, rake). | Required | OUTCOME |
| `depin.poker.violation` | RELEVANT | Tamper evidence (cheat detected, invalid action, corrupted shuffle). Permanent audit record. | Required | EVIDENCE |
| `depin.poker.result` | RELEVANT | Hand result (winner, amounts paid, reason for end). Audit trail, never consumed. | Required | OUTCOME |

### Type Hash Registration

Each object type receives a deterministic type hash following Phase 1 cell packing. Hashes are computed from the type path and linearity:

```typescript
// packages/cell-ops/src/typeHashRegistry.ts additions
export const POKER_TYPE_HASHES = {
  'depin.poker.hand':           '0x3a7f...',    // LINEAR, 256 bits
  'depin.poker.action':         '0x4b2c...',    // LINEAR
  'depin.poker.shuffle.proof':  '0x1d8e...',    // RELEVANT
  'depin.poker.deck':           '0x2f5a...',    // AFFINE
  'depin.poker.pot':            '0x5e9c...',    // LINEAR
  'depin.poker.table':          '0x6b7d...',    // RELEVANT
  'depin.poker.seat':           '0x7c4f...',    // AFFINE
  'depin.poker.payment.tick':   '0x8a1e...',    // LINEAR
  'depin.poker.violation':      '0x9b3d...',    // RELEVANT
  'depin.poker.result':         '0xac2b...',    // RELEVANT
} as const;
```

### Anchor Policy

```typescript
export const POKER_ANCHOR_POLICY: AnchorPolicy = {
  requireAnchorOn: [
    'hand_created',           // Each dealt hand anchors
    'action_taken',           // Critical actions anchor
    'showdown_completed',     // Final hands reveal and settle
    'violation_detected',     // Cheating detected → immediate anchor
  ],
  complianceEvents: [
    'hand_shuffled',
    'hand_dealt',
    'action_folded',
    'action_raised',
    'showdown',
    'settlement',
    'cheating_detected',
  ],
  batchInterval: 30_000,      // 30 seconds (hackathon speed)
};
```

### Anchor Batch Semantics

The gateway collects LINEAR poker cells (hands, actions, pots) into batches every 30 seconds. Each batch:
1. Computes a merkle root over all cells in the batch
2. Submits the root to BSV mainnet as a single transaction
3. Issues proof-of-work: txid + block height to all players
4. Stores merkle path for each cell (for on-chain verification)

This amortizes anchor costs while preserving per-cell auditability.

---

## Part B: Three Lisp Personality Profiles

Each profile is a `.lisp` file authored in the Lisp dialect supported by the Phase 21 compiler. The compiler transforms each profile into bytecode, which is then packed into hex strings and stored in the poker engine's policy registry.

### Compilation Pipeline

```
poker/profiles/*.lisp
    ↓ (Lisp Parser: packages/shell/src/lisp/parser.ts)
SExpression tree
    ↓ (Constraint Interpreter: packages/shell/src/lisp/types.ts)
ConstraintExpr graph
    ↓ (Bytecode Compiler: packages/shell/src/lisp/compiler.ts)
{ words: string[], bytes: number[] }
    ↓ (Packer: packages/shell/src/lisp/packer.ts)
Hex string + metadata JSON
    ↓ (stored in configs/extensions/poker/profiles/*.compiled.json)
Poker engine loads at runtime, executes against game state
```

### 1. The Nit Profile

**File**: `configs/extensions/poker/profiles/nit.lisp`

**Persona**: Conservative, plays only premium hands. Folds 90%, raises with AA/KK/QQ/AKs only.

**Source Policy**:
```lisp
;; The Nit — folds everything except premium hands
;; hand-strength: 0.0 (worst) to 1.0 (best) — computed from hole cards vs. table equity
;; pot-odds: ratio of call cost to total pot (e.g., 0.1 = pay 10% of pot to call)

(define (nit-decide hand-strength pot-odds)
  ;; Premium hands: >0.9 strength (AA, KK, QQ, AKs from 6+ card equity)
  (if (> hand-strength 0.9)
    'raise
    ;; Good hands: 0.7-0.9 (medium pairs, AK, AQ, etc.)
    (if (> hand-strength 0.7)
      'call
      ;; Everything else: fold
      'fold)))

;; Hand classification logic (compiled separately for clarity)
(define (classify-hand cards)
  ;; cards: [c1 c2 ...] from depin.poker.hand payload
  ;; returns numeric strength 0.0-1.0
  ;; Uses pot-odds to refine calls
  'strength-computed-by-game-engine)
```

**Decision Tree**:
- If hand strength ≥ 0.9 (AA, KK, QQ, premium AK in position): **RAISE**
- Else if hand strength ≥ 0.7 (medium pairs, AQ, AJ, premium broadway): **CALL**
- Else: **FOLD**

**Bytecode Output** (compiled by Phase 21):
```
Words:  ['0.9 GT', 'RAISE', '0.7 GT', 'CALL', 'FOLD']
Bytes:  [
  0x4C, 0x01, 0x39, 0x00,   // push 0.9
  0xB0, 0x11, 'h','s',       // load field "hand-strength"
  0xA0,                       // OP_GREATERTHAN
  // ...if-else chain...
  0x4C, 0x05, 'r','a','i','s','e'  // push 'raise'
  // ...
]
Hex: "4c0139b0...a0..."
```

**Compiled artifact**: `configs/extensions/poker/profiles/nit.compiled.json`
```json
{
  "profile": "nit",
  "version": "1.0",
  "bytecodeHex": "4c0139b0...",
  "sourceHash": "sha256(nit.lisp)",
  "compiledAt": "2026-04-11T14:32:00Z",
  "gameRules": {
    "handStrengthThreshold1": 0.9,
    "handStrengthThreshold2": 0.7,
    "actions": ["raise", "call", "fold"]
  }
}
```

### 2. The Maniac Profile

**File**: `configs/extensions/poker/profiles/maniac.lisp`

**Persona**: Aggressive, plays many hands. Raises 80% of the time, 3-bets wide, bluffs frequently.

**Source Policy**:
```lisp
;; The Maniac — raise-happy, plays 80% of hands
;; Uses randomness (seeded by previous block hash for determinism)

(define (maniac-decide hand-strength pot-odds)
  ;; Raise 80% of the time (random seed: table-id + round-number)
  ;; This is seeded by the game engine's RNG (not cryptographically random)
  ;; For trustlessness, the RNG seed is public (in the table state cell)
  (if (> (random) 0.2)      ;; 80% chance of raise
    'raise
    ;; On the 20% fold margin, still call with marginal hands
    (if (> hand-strength 0.3)
      'call
      'fold)))

;; Random seed comes from depin.poker.table.rng_seed (public, in cell)
(define (random)
  ;; Deterministic PRNG: LCG seeded by table RNG + hand index
  'seeded-rng-output)
```

**Decision Tree**:
- If random() > 0.2 (80% probability): **RAISE** (aggressive bluffs)
- Else if hand strength ≥ 0.3 (any marginal hand): **CALL**
- Else: **FOLD**

**Bytecode Output**:
```
Words:  ['RANDOM', '0.2 LT', 'RAISE', '0.3 GT', 'CALL', 'FOLD']
Bytes:  [
  0xD0, 'r','a','n','d','o','m',     // OP_CALLHOST "random"
  0x4C, 0x01, 0x14,                  // push 0.2
  0x9F,                               // OP_LESSTHAN
  // ...if-else...
]
Hex: "d0726...9f..."
```

**Compiled artifact**: `configs/extensions/poker/profiles/maniac.compiled.json`
```json
{
  "profile": "maniac",
  "version": "1.0",
  "bytecodeHex": "d0726...",
  "sourceHash": "sha256(maniac.lisp)",
  "compiledAt": "2026-04-11T14:32:00Z",
  "gameRules": {
    "raiseThreshold": 0.2,
    "callThreshold": 0.3,
    "actions": ["raise", "call", "fold"]
  }
}
```

**Determinism Note**: The random seed comes from `depin.poker.table.rng_seed`, which is:
- Set by the game engine at table creation (from previous block hash + timestamp)
- Included in the signed table cell
- Verifiable by all players
- Yields deterministic output across reruns (same seed → same sequence)

### 3. The Calculator Profile

**File**: `configs/extensions/poker/profiles/calculator.lisp`

**Persona**: Game-theory optimal. Raises when equity > 2x pot odds, calls when equity > pot odds. Mathematically sound.

**Source Policy**:
```lisp
;; The Calculator — pot odds and equity-based strategy
;; GTO-inspired: raise when expected value > cost

(define (calc-decide hand-strength pot-odds)
  ;; hand-strength is the equity (probability of winning)
  ;; pot-odds is the cost-to-call / total-pot-after-call
  ;;
  ;; Raise (value bet): equity > 2.0 * pot-odds
  ;;   (e.g., if call costs 0.1 of final pot, need >20% equity to raise)
  (if (> hand-strength (* 2.0 pot-odds))
    'raise
    ;; Call (implied odds): equity > pot-odds
    ;;   (e.g., if call costs 0.1 of final pot, need >10% equity)
    (if (> hand-strength pot-odds)
      'call
      'fold)))

;; Multiplier for raise threshold (can be adjusted: 1.5x, 2.5x, etc.)
(define RAISE_MULTIPLIER 2.0)

;; house-adjusted: can vary RAISE_MULTIPLIER for different games
(define (calc-decide-adjusted hand-strength pot-odds multiplier)
  (if (> hand-strength (* multiplier pot-odds))
    'raise
    (if (> hand-strength pot-odds)
      'call
      'fold)))
```

**Decision Tree**:
- If hand strength ≥ 2.0 × pot odds: **RAISE** (strong value bet)
- Else if hand strength ≥ pot odds: **CALL** (long-term profitable)
- Else: **FOLD** (negative expected value)

**Bytecode Output**:
```
Words:  ['2.0 PUSHCONST', 'POT-ODDS MULTIPLY', 'HAND-STRENGTH GT', 'RAISE', 'POT-ODDS GT', 'CALL', 'FOLD']
Bytes:  [
  0x4C, 0x02, 0x00, 0x00,            // push 2.0 (as fixed-point or float)
  0xB0, 0x08, 'p','o','t','-','o','d','s',  // load pot-odds field
  0xA8,                               // OP_MULTIPLY (custom opcode)
  0xB0, 0x0D, 'h','a','n','d','-','s','t','r','e','n','g','t','h', // load field
  0xA0,                               // OP_GREATERTHAN
  // ...else-if chain...
]
Hex: "4c0200...a8a0..."
```

**Compiled artifact**: `configs/extensions/poker/profiles/calculator.compiled.json`
```json
{
  "profile": "calculator",
  "version": "1.0",
  "bytecodeHex": "4c0200...a8a0...",
  "sourceHash": "sha256(calculator.lisp)",
  "compiledAt": "2026-04-11T14:32:00Z",
  "gameRules": {
    "raiseMultiplier": 2.0,
    "callThreshold": 1.0,
    "actions": ["raise", "call", "fold"]
  }
}
```

---

## Part C: Profile Loader and Runtime Integration

### Profile Registry

**File**: `packages/poker-agent/src/profile-loader.ts`

```typescript
interface ProfileRegistry {
  profiles: Map<string, CompiledProfile>;
  load(profile: string): CompiledProfile;
  select(personaEnv: string): CompiledProfile;
}

interface CompiledProfile {
  name: string;                      // "nit" | "maniac" | "calculator"
  version: string;                   // semver
  bytecodeHex: string;               // Hex string of compiled policy
  sourceHash: string;                // SHA256 of original .lisp source
  compiledAt: ISO8601;
  gameRules: Record<string, unknown>;
}

// Load from configs/extensions/poker/profiles/*.compiled.json
// Select via BOT_PERSONA environment variable or programmatic API
export async function loadProfile(name: 'nit' | 'maniac' | 'calculator'): Promise<CompiledProfile> {
  const path = `configs/extensions/poker/profiles/${name}.compiled.json`;
  const data = await fs.readFile(path, 'utf8');
  return JSON.parse(data) as CompiledProfile;
}

// At game startup:
const persona = process.env.BOT_PERSONA || 'calculator';
const policy = await loadProfile(persona);
pokersEngine.setPolicy(policy.bytecodeHex);
```

### Execution in the Poker Engine

When a decision is needed (betting round, must act):

```typescript
// In TrustlessPokerEngine.decideAction(...)
async decideAction(playerState: PlayerState, tableState: TableState): Promise<Action> {
  // Load current policy bytecode
  const bytecode = this.currentPolicy.bytecodeHex;
  
  // Prepare game state as Forth stack input
  const handStrength = computeEquity(playerState.holeCards, tableState.boardCards);
  const potOdds = computePotOdds(tableState.pot, tableState.toCall);
  
  // Execute policy bytecode
  const action = this.vm.execute(bytecode, [handStrength, potOdds]);
  
  // Create decision cell (LINEAR, consumed once)
  const decisionCell: Cell = {
    type: 'depin.poker.action',
    linearity: 'LINEAR',
    payload: {
      action,              // 'raise' | 'call' | 'fold'
      hand_strength: handStrength,
      pot_odds: potOdds,
      bytecode_hash: sha256(bytecode),  // Proof of which policy was used
      policy_name: this.currentPolicy.name,
    },
    references: [
      playerState.holeCardsCell.id,
      tableState.id,
    ],
    timestamp: now(),
  };
  
  // Sign with player key (SIGHASH_ALL over bytecode)
  decisionCell.signature = sign(
    Buffer.concat([
      Buffer.from(bytecode, 'hex'),
      encodeAction(action),
    ]),
    playerKey
  );
  
  // Publish to game log (consumed in outcome phase)
  await this.gameLog.append(decisionCell);
  
  return action;
}
```

---

## Deliverables

### DH2.1 — Extension Grammar JSON

**File**: `configs/extensions/poker/grammar.json`

Follows the Phase 36A ExtensionGrammar schema exactly:

```json
{
  "metaSchemaVersion": "1.0.0",
  "grammarId": "com.semantos.depin.poker",
  "grammarVersion": "1.0.0",
  "displayName": "Poker Extension",
  "description": "Trustless poker with verifiable bot personalities and LINEAR action accountability",
  "author": {
    "certId": "semantos-core-hackathon-h2",
    "name": "Semantos Core Team",
    "contact": "https://semantos.io"
  },
  "source": {
    "protocol": "event-stream",
    "baseUrlTemplate": "memory://poker-tables",
    "auth": {
      "type": "certificate",
      "requiredCredentials": ["plexus.cert"]
    },
    "entities": [
      {
        "entityId": "hand",
        "displayName": "Poker Hand",
        "endpoint": {
          "list": "/hands",
          "get": "/hands/{id}"
        },
        "responseShape": {
          "dataPath": "$.hand",
          "idField": "id"
        },
        "fields": [
          { "sourceFieldName": "cards", "sourceType": "array", "required": true },
          { "sourceFieldName": "dealt_at", "sourceType": "datetime", "required": true }
        ]
      }
      // ... more entities ...
    ]
  },
  "objectTypes": [
    {
      "typePath": "depin.poker.hand",
      "displayName": "Poker Hand",
      "description": "A player's dealt hole cards, consumed on showdown",
      "linearity": "LINEAR",
      "phases": ["SOURCE", "ACTION", "OUTCOME"],
      "initialPhase": "SOURCE",
      "payloadSchema": {
        "cards": { "type": "array", "description": "Two hole cards [rank suit]" },
        "dealt_at": { "type": "string", "description": "ISO8601 timestamp" },
        "table_id": { "type": "string", "description": "Table cell ID" }
      }
    },
    {
      "typePath": "depin.poker.action",
      "displayName": "Betting Action",
      "description": "Fold / call / raise, consumed once per decision",
      "linearity": "LINEAR",
      "phases": ["SOURCE", "ACTION"],
      "initialPhase": "SOURCE",
      "payloadSchema": {
        "action": { "type": "enum", "enum": ["fold", "call", "raise", "check"] },
        "amount": { "type": "number", "description": "Raise amount in satoshis" },
        "policy_bytecode_hash": { "type": "string", "description": "SHA256 of executed policy" }
      }
    }
    // ... more object types ...
  ],
  "entityMappings": [
    {
      "sourceEntityId": "hand",
      "targetObjectType": "depin.poker.hand",
      "fieldMappings": [
        { "sourceField": "cards", "targetField": "cards", "required": true },
        { "sourceField": "dealt_at", "targetField": "dealt_at", "required": true }
      ],
      "taxonomy": {
        "what": "depin.poker",
        "how": "dealt.community",
        "why": "game.setup"
      }
    }
    // ... more mappings ...
  ],
  "capabilities": [
    {
      "capability": "storage.write",
      "reason": "Log game state and decisions",
      "required": true
    }
  ],
  "taxonomyNamespace": "depin.poker",
  "taxonomyExtensions": [
    {
      "axis": "what",
      "parentPath": "depin",
      "nodes": [
        {
          "segment": "poker",
          "displayName": "Poker Games",
          "children": [
            { "segment": "hand", "displayName": "Dealt hand" },
            { "segment": "action", "displayName": "Betting action" }
          ]
        }
      ]
    }
  ]
}
```

### DH2.2 — Type Hash Registration

**File**: `packages/cell-ops/src/typeHashRegistry.ts` (additions)

```typescript
import { blake2b } from 'blake2b';

export const POKER_TYPE_HASHES = {
  'depin.poker.hand':           computeTypeHash('depin.poker.hand', 'LINEAR'),
  'depin.poker.action':         computeTypeHash('depin.poker.action', 'LINEAR'),
  'depin.poker.shuffle.proof':  computeTypeHash('depin.poker.shuffle.proof', 'RELEVANT'),
  'depin.poker.deck':           computeTypeHash('depin.poker.deck', 'AFFINE'),
  'depin.poker.pot':            computeTypeHash('depin.poker.pot', 'LINEAR'),
  'depin.poker.table':          computeTypeHash('depin.poker.table', 'RELEVANT'),
  'depin.poker.seat':           computeTypeHash('depin.poker.seat', 'AFFINE'),
  'depin.poker.payment.tick':   computeTypeHash('depin.poker.payment.tick', 'LINEAR'),
  'depin.poker.violation':      computeTypeHash('depin.poker.violation', 'RELEVANT'),
  'depin.poker.result':         computeTypeHash('depin.poker.result', 'RELEVANT'),
} as const;

function computeTypeHash(typePath: string, linearity: string): string {
  // Deterministic: BLAKE2b(typePath || linearity)
  const input = Buffer.concat([
    Buffer.from(typePath, 'utf8'),
    Buffer.from(linearity, 'utf8'),
  ]);
  return '0x' + blake2b(input, null, 32).toString('hex');
}

// Register in the global type registry
export function registerPokerTypes(): void {
  for (const [typePath, typeHash] of Object.entries(POKER_TYPE_HASHES)) {
    typeHashRegistry.register(typePath, typeHash);
  }
}
```

### DH2.3 — The Nit Lisp Profile + Compiled Bytecode

**Source file**: `configs/extensions/poker/profiles/nit.lisp`

```lisp
;; The Nit: Conservative, Premium-Hands-Only
;; Folds 90%, raises with AA/KK/QQ/AKs only
;;
;; Inputs:
;;   - hand-strength: float 0.0–1.0, equity vs table
;;   - pot-odds: float, cost-to-call / final-pot
;;
;; Output:
;;   - 'raise' | 'call' | 'fold'

(define (nit-decide hand-strength pot-odds)
  (if (> hand-strength 0.9)
    'raise
    (if (> hand-strength 0.7)
      'call
      'fold)))
```

**Compiled artifact**: `configs/extensions/poker/profiles/nit.compiled.json`

```json
{
  "profile": "nit",
  "version": "1.0.0",
  "bytecodeHex": "4c0139b0116873d0a04c06076635d9604c04666f6c6405000a7e08636f4a",
  "wordAssembly": [
    "PUSH 0.9",
    "LOADFIELD hand-strength",
    "GREATERTHAN",
    "IF PUSH raise ELSE",
    "PUSH 0.7",
    "LOADFIELD hand-strength",
    "GREATERTHAN",
    "IF PUSH call ELSE PUSH fold ENDIF ENDIF"
  ],
  "sourceHash": "sha256:7e3a2b4c5d6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a",
  "compiledAt": "2026-04-11T14:32:00.000Z",
  "compiler": {
    "name": "semantos-lisp-compiler",
    "version": "1.0.0",
    "target": "forth-bytecode"
  },
  "gameRules": {
    "handStrengthThreshold1": 0.9,
    "handStrengthThreshold2": 0.7,
    "actions": ["raise", "call", "fold"],
    "description": "Only plays premium hands (top 10%). Raises >0.9, calls >0.7, otherwise folds."
  }
}
```

### DH2.4 — The Maniac Lisp Profile + Compiled Bytecode

**Source file**: `configs/extensions/poker/profiles/maniac.lisp`

```lisp
;; The Maniac: Aggressive, Plays Wide
;; Raises 80% of hands, 3-bets frequently
;;
;; Uses a seeded RNG (deterministic, publicly visible seed)
;; to make decisions appear random while being reproducible

(define (maniac-decide hand-strength pot-odds)
  (if (> (random) 0.2)
    'raise
    (if (> hand-strength 0.3)
      'call
      'fold)))

;; Random seed is provided by the game engine from table state
;; Ensures reproducibility: same table state → same RNG sequence
```

**Compiled artifact**: `configs/extensions/poker/profiles/maniac.compiled.json`

```json
{
  "profile": "maniac",
  "version": "1.0.0",
  "bytecodeHex": "d0072722616e646f6d4c0114a04c06076635d9604c04666f6c6405000a7e",
  "wordAssembly": [
    "CALLHOST random",
    "PUSH 0.2",
    "LESSTHAN",
    "IF PUSH raise ELSE",
    "PUSH 0.3",
    "LOADFIELD hand-strength",
    "GREATERTHAN",
    "IF PUSH call ELSE PUSH fold ENDIF ENDIF"
  ],
  "sourceHash": "sha256:a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a",
  "compiledAt": "2026-04-11T14:32:01.000Z",
  "compiler": {
    "name": "semantos-lisp-compiler",
    "version": "1.0.0",
    "target": "forth-bytecode"
  },
  "hostFunctions": [
    {
      "name": "random",
      "description": "Seeded PRNG. Seed comes from depin.poker.table.rng_seed (public, auditable)",
      "deterministic": true
    }
  ],
  "gameRules": {
    "raiseThreshold": 0.2,
    "callThreshold": 0.3,
    "actions": ["raise", "call", "fold"],
    "description": "Raises 80% of hands. Calls marginal hands (>0.3 strength), folds weak. Uses deterministic RNG seeded by table state."
  }
}
```

### DH2.5 — The Calculator Lisp Profile + Compiled Bytecode

**Source file**: `configs/extensions/poker/profiles/calculator.lisp`

```lisp
;; The Calculator: GTO-Inspired, Equity vs Odds
;; Raises when equity > 2x pot odds
;; Calls when equity > pot odds
;; Otherwise folds
;;
;; Game-theory optimal for many spots
;; Adjustable multiplier for different game contexts

(define (calc-decide hand-strength pot-odds)
  (if (> hand-strength (* 2.0 pot-odds))
    'raise
    (if (> hand-strength pot-odds)
      'call
      'fold)))
```

**Compiled artifact**: `configs/extensions/poker/profiles/calculator.compiled.json`

```json
{
  "profile": "calculator",
  "version": "1.0.0",
  "bytecodeHex": "4c0200004c0870e6c9904cb0106c6f61640aa004c06072635d9604c04666f6c",
  "wordAssembly": [
    "PUSH 2.0",
    "PUSH pot-odds",
    "LOADFIELD pot-odds",
    "MULTIPLY",
    "PUSH hand-strength",
    "LOADFIELD hand-strength",
    "GREATERTHAN",
    "IF PUSH raise ELSE",
    "PUSH hand-strength",
    "LOADFIELD hand-strength",
    "PUSH pot-odds",
    "LOADFIELD pot-odds",
    "GREATERTHAN",
    "IF PUSH call ELSE PUSH fold ENDIF ENDIF"
  ],
  "sourceHash": "sha256:f0e1d2c3b4a59687978695a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7a6b5",
  "compiledAt": "2026-04-11T14:32:02.000Z",
  "compiler": {
    "name": "semantos-lisp-compiler",
    "version": "1.0.0",
    "target": "forth-bytecode"
  },
  "gameRules": {
    "raiseMultiplier": 2.0,
    "callThreshold": 1.0,
    "actions": ["raise", "call", "fold"],
    "description": "Raises when equity > 2x pot odds (strong value). Calls when equity > pot odds (positive EV). GTO-inspired and adjustable."
  }
}
```

### DH2.6 — Profile Loader

**File**: `packages/poker-agent/src/profile-loader.ts`

```typescript
import fs from 'fs/promises';
import path from 'path';

export interface CompiledProfile {
  profile: string;
  version: string;
  bytecodeHex: string;
  wordAssembly: string[];
  sourceHash: string;
  compiledAt: string;
  compiler: {
    name: string;
    version: string;
    target: string;
  };
  hostFunctions?: Array<{ name: string; description: string; deterministic: boolean }>;
  gameRules: Record<string, unknown>;
}

export class ProfileLoader {
  private cache: Map<string, CompiledProfile> = new Map();
  private basePath: string = 'configs/extensions/poker/profiles';

  async load(profileName: string): Promise<CompiledProfile> {
    if (this.cache.has(profileName)) {
      return this.cache.get(profileName)!;
    }

    const filePath = path.join(this.basePath, `${profileName}.compiled.json`);
    const data = await fs.readFile(filePath, 'utf8');
    const profile = JSON.parse(data) as CompiledProfile;

    // Validate profile structure
    this.validateProfile(profile);

    this.cache.set(profileName, profile);
    return profile;
  }

  /**
   * Select a profile based on BOT_PERSONA env var or default.
   * Supports: 'nit', 'maniac', 'calculator'
   */
  async selectByPersona(persona?: string): Promise<CompiledProfile> {
    const selectedPersona = persona || process.env.BOT_PERSONA || 'calculator';
    
    const valid = ['nit', 'maniac', 'calculator'];
    if (!valid.includes(selectedPersona)) {
      throw new Error(
        `Invalid persona "${selectedPersona}". Must be one of: ${valid.join(', ')}`
      );
    }

    return this.load(selectedPersona);
  }

  /**
   * Get bytecode hex for a profile
   */
  async getBytecode(profileName: string): Promise<string> {
    const profile = await this.load(profileName);
    return profile.bytecodeHex;
  }

  /**
   * Verify bytecode matches source (for audit trail)
   */
  async verifyBytecode(profileName: string, expectedSourceHash: string): Promise<boolean> {
    const profile = await this.load(profileName);
    return profile.sourceHash === expectedSourceHash;
  }

  /**
   * List available profiles
   */
  async listProfiles(): Promise<string[]> {
    try {
      const files = await fs.readdir(this.basePath);
      return files
        .filter(f => f.endsWith('.compiled.json'))
        .map(f => f.replace('.compiled.json', ''));
    } catch {
      return ['nit', 'maniac', 'calculator']; // fallback
    }
  }

  private validateProfile(profile: CompiledProfile): void {
    if (!profile.profile || !profile.version || !profile.bytecodeHex) {
      throw new Error('Invalid profile structure: missing required fields');
    }
    if (!/^[0-9a-f]{2,}$/i.test(profile.bytecodeHex)) {
      throw new Error('Invalid bytecodeHex: not valid hex string');
    }
  }
}

// Singleton instance
export const profileLoader = new ProfileLoader();
```

**Integration in TrustlessPokerEngine**:

```typescript
// In packages/poker-agent/src/poker-engine.ts
import { profileLoader } from './profile-loader';

export class TrustlessPokerEngine {
  private currentProfile: CompiledProfile | null = null;

  async initialize(persona?: string): Promise<void> {
    this.currentProfile = await profileLoader.selectByPersona(persona);
    console.log(`[Poker Engine] Loaded profile: ${this.currentProfile.profile}`);
  }

  async decideAction(
    playerState: PlayerState,
    tableState: TableState
  ): Promise<BettingAction> {
    if (!this.currentProfile) {
      throw new Error('Profile not loaded. Call initialize() first.');
    }

    const bytecode = this.currentProfile.bytecodeHex;
    const handStrength = await this.computeEquity(playerState, tableState);
    const potOdds = await this.computePotOdds(tableState);

    // Execute bytecode, get action
    const action = await this.executeBytecode(bytecode, {
      handStrength,
      potOdds,
    });

    return action;
  }

  private async executeBytecode(
    hex: string,
    inputs: Record<string, number>
  ): Promise<string> {
    // Delegate to Zig VM (packages/cell-engine/src/vm.zig)
    return this.vm.execute(hex, inputs);
  }
}
```

### DH2.7 — Gate Tests (T1–T12)

**File**: `packages/poker-agent/__tests__/profile-loader.test.ts`

```typescript
import { describe, it, expect, beforeAll } from 'vitest';
import { profileLoader } from '../src/profile-loader';

describe('Phase H2: Poker Grammar + Lisp Profiles', () => {
  // ── T1: Grammar schema validation ──
  it('T1: Extension grammar JSON is valid Phase 36A schema', async () => {
    const grammarPath = 'configs/extensions/poker/grammar.json';
    const grammar = JSON.parse(
      await fs.readFile(grammarPath, 'utf8')
    );
    
    expect(grammar.metaSchemaVersion).toBeDefined();
    expect(grammar.grammarId).toBe('com.semantos.depin.poker');
    expect(grammar.objectTypes).toBeInstanceOf(Array);
    expect(grammar.objectTypes.length).toBeGreaterThan(0);
  });

  // ── T2: Poker type hash registration ──
  it('T2: All poker types registered with correct hashes', async () => {
    const { POKER_TYPE_HASHES } = await import('../src/type-hashes');
    
    const expected = [
      'depin.poker.hand',
      'depin.poker.action',
      'depin.poker.pot',
      'depin.poker.result',
    ];
    
    for (const typePath of expected) {
      expect(POKER_TYPE_HASHES[typePath]).toBeDefined();
      expect(POKER_TYPE_HASHES[typePath]).toMatch(/^0x[0-9a-f]{64}$/);
    }
  });

  // ── T3: Nit profile loads and compiles ──
  it('T3: Nit profile loads successfully', async () => {
    const nit = await profileLoader.load('nit');
    expect(nit.profile).toBe('nit');
    expect(nit.bytecodeHex).toBeDefined();
    expect(nit.bytecodeHex.length).toBeGreaterThan(0);
  });

  // ── T4: Nit policy is deterministic ──
  it('T4: Nit bytecode hash is deterministic', async () => {
    const nit1 = await profileLoader.load('nit');
    const nit2 = await profileLoader.load('nit');
    expect(nit1.bytecodeHex).toBe(nit2.bytecodeHex);
  });

  // ── T5: Nit makes correct decisions ──
  it('T5: Nit raises with 0.95 strength', async () => {
    const nit = await profileLoader.load('nit');
    const result = await executeProfile(nit.bytecodeHex, {
      'hand-strength': 0.95,
      'pot-odds': 0.1,
    });
    expect(result).toBe('raise');
  });

  it('T5b: Nit calls with 0.75 strength', async () => {
    const nit = await profileLoader.load('nit');
    const result = await executeProfile(nit.bytecodeHex, {
      'hand-strength': 0.75,
      'pot-odds': 0.1,
    });
    expect(result).toBe('call');
  });

  it('T5c: Nit folds with 0.5 strength', async () => {
    const nit = await profileLoader.load('nit');
    const result = await executeProfile(nit.bytecodeHex, {
      'hand-strength': 0.5,
      'pot-odds': 0.1,
    });
    expect(result).toBe('fold');
  });

  // ── T6: Maniac profile loads ──
  it('T6: Maniac profile loads successfully', async () => {
    const maniac = await profileLoader.load('maniac');
    expect(maniac.profile).toBe('maniac');
    expect(maniac.hostFunctions).toBeDefined();
  });

  // ── T7: Calculator profile loads ──
  it('T7: Calculator profile loads successfully', async () => {
    const calc = await profileLoader.load('calculator');
    expect(calc.profile).toBe('calculator');
    expect(calc.gameRules.raiseMultiplier).toBe(2.0);
  });

  // ── T8: Calculator decision logic ──
  it('T8: Calculator raises when equity > 2x pot odds', async () => {
    const calc = await profileLoader.load('calculator');
    // equity=0.25 (25%), pot-odds=0.1 (10%): 0.25 > 2*0.1 → raise
    const result = await executeProfile(calc.bytecodeHex, {
      'hand-strength': 0.25,
      'pot-odds': 0.1,
    });
    expect(result).toBe('raise');
  });

  it('T8b: Calculator calls when equity > pot odds', async () => {
    const calc = await profileLoader.load('calculator');
    // equity=0.15 (15%), pot-odds=0.1 (10%): 0.15 > 0.1 but 0.15 < 2*0.1 → call
    const result = await executeProfile(calc.bytecodeHex, {
      'hand-strength': 0.15,
      'pot-odds': 0.1,
    });
    expect(result).toBe('call');
  });

  // ── T9: Profile selector by persona ──
  it('T9: selectByPersona() selects correct profile', async () => {
    const calc = await profileLoader.selectByPersona('calculator');
    expect(calc.profile).toBe('calculator');
  });

  // ── T10: BOT_PERSONA env var works ──
  it('T10: BOT_PERSONA environment variable selects profile', async () => {
    process.env.BOT_PERSONA = 'nit';
    const nit = await profileLoader.selectByPersona();
    expect(nit.profile).toBe('nit');
  });

  // ── T11: Bytecode hex is valid ──
  it('T11: All profiles have valid bytecode hex', async () => {
    for (const profileName of ['nit', 'maniac', 'calculator']) {
      const profile = await profileLoader.load(profileName);
      // Hex string: even length, 0-9a-f only
      expect(profile.bytecodeHex).toMatch(/^[0-9a-fA-F]{2,}$/);
      expect(profile.bytecodeHex.length % 2).toBe(0);
    }
  });

  // ── T12: Source hash audit trail ──
  it('T12: Profile source hashes are consistent', async () => {
    const nit = await profileLoader.load('nit');
    expect(nit.sourceHash).toMatch(/^sha256:[0-9a-f]{64}$/);
    
    // Recompile from source, verify hash matches
    const recompiled = await recompileProfile('nit');
    expect(recompiled.sourceHash).toBe(nit.sourceHash);
  });
});

// Helper: execute bytecode with given inputs
async function executeProfile(
  bytecodeHex: string,
  inputs: Record<string, number>
): Promise<string> {
  // Mock VM for testing; real VM in packages/cell-engine/src/vm.zig
  return mockVMExecute(bytecodeHex, inputs);
}

function mockVMExecute(bytecodeHex: string, inputs: Record<string, number>): string {
  // Simplified: decode bytecode, execute ops, return action
  // This would call the real Zig VM in production
  return 'call'; // placeholder
}

async function recompileProfile(profileName: string): Promise<CompiledProfile> {
  // Recompile from .lisp source, verify bytecode matches
  const lisp = await fs.readFile(
    `configs/extensions/poker/profiles/${profileName}.lisp`,
    'utf8'
  );
  const compiled = await compileToForth(lisp);
  return compiled;
}
```

---

## Source File References

| Artifact | Path | Created/Modified |
|----------|------|-----------------|
| Extension Grammar | `configs/extensions/poker/grammar.json` | CREATE |
| Type Hashes | `packages/cell-ops/src/typeHashRegistry.ts` | MODIFY (add POKER_TYPES) |
| Nit Source | `configs/extensions/poker/profiles/nit.lisp` | CREATE |
| Nit Compiled | `configs/extensions/poker/profiles/nit.compiled.json` | CREATE |
| Maniac Source | `configs/extensions/poker/profiles/maniac.lisp` | CREATE |
| Maniac Compiled | `configs/extensions/poker/profiles/maniac.compiled.json` | CREATE |
| Calculator Source | `configs/extensions/poker/profiles/calculator.lisp` | CREATE |
| Calculator Compiled | `configs/extensions/poker/profiles/calculator.compiled.json` | CREATE |
| Profile Loader | `packages/poker-agent/src/profile-loader.ts` | CREATE |
| Gate Tests | `packages/poker-agent/__tests__/profile-loader.test.ts` | CREATE |
| Engine Integration | `packages/poker-agent/src/poker-engine.ts` | MODIFY (add profile init) |
| Lisp Compiler | `packages/shell/src/lisp/compiler.ts` | UNMODIFIED (already supports all operations) |
| Lisp Parser | `packages/shell/src/lisp/parser.ts` | UNMODIFIED |
| Packer | `packages/shell/src/lisp/packer.ts` | UNMODIFIED |

---

## Completion Criteria

All of the following must be true:

1. **Grammar is valid**: `configs/extensions/poker/grammar.json` passes Phase 36A schema validation
2. **Types registered**: All 10 poker types in `POKER_TYPE_HASHES` have unique, deterministic hashes
3. **Lisp source files exist**: Three `.lisp` files in `configs/extensions/poker/profiles/`
4. **Compilation works**: Each `.lisp` compiles to bytecode hex without errors
5. **Compiled artifacts exist**: Three `.compiled.json` files with valid bytecodeHex
6. **Profiles load**: `profileLoader.load()` succeeds for all three personas
7. **Decisions are correct**: Each profile makes decisions matching its policy (see gate tests T5–T8)
8. **Environment selection works**: `BOT_PERSONA` env var correctly selects profiles (T10)
9. **Bytecode is deterministic**: Same source always produces same hex (T4)
10. **Audit trail intact**: sourceHash and compiledAt metadata present in all artifacts
11. **All 12 gate tests pass**: T1–T12 in `profile-loader.test.ts` pass without error
12. **No regressions**: Existing Phase 21 compiler, Phase 27 poker engine, Phase 36A grammar infrastructure all work

---

## What NOT to Do

**Do NOT**:

1. **Implement or modify the Lisp compiler** — Phase 21 is done. Use it as-is.
2. **Modify the poker engine's hand evaluation logic** — Phase 27 is complete. Only integrate the profile loader.
3. **Change the ExtensionGrammar schema** — Phase 36A defines it. This phase implements one instance of it.
4. **Add new poker types beyond the 10 listed** — Stick to the specification. New types require governance.
5. **Use cryptographic randomness in profiles** — Maniac profile uses seeded RNG from table state, which is public and verifiable.
6. **Hard-code profile selection in the engine** — Use the environment variable pattern (BOT_PERSONA).
7. **Store compiled bytecode in the source control without comment** — Include both `.lisp` and `.compiled.json`; comment the `.compiled.json` with the source hash.
8. **Deploy profiles before all tests pass** — Gate tests T1–T12 are mandatory.
9. **Skip the audit trail** — Every compiled profile must record sourceHash, compiledAt, compiler version.
10. **Assume profiles are immutable** — They can be upgraded (new version) with migration rules in Phase 36A.

---

## Implementation Order

1. **Day 1 Morning**: Create the extension grammar JSON (`configs/extensions/poker/grammar.json`) following Phase 36A exactly. Register type hashes.
2. **Day 1 Afternoon**: Write the three `.lisp` source files. Compile each to bytecode using Phase 21 compiler (command-line or programmatic). Save `.compiled.json` artifacts.
3. **Day 2 Morning**: Write the profile loader (`packages/poker-agent/src/profile-loader.ts`). Implement caching, validation, persona selection.
4. **Day 2 Afternoon**: Integrate profile loader into `TrustlessPokerEngine`. Test initialization and decision execution.
5. **Day 3**: Write and run gate tests T1–T12. Debug any failures. Ensure all 12 pass.
6. **Day 3 Evening**: Final audit: verify grammar schema compliance, verify no regressions in Phase 21/27/36A, document any deviations.

---

## Phase Decomposition (Optional)

If concurrent work is needed:

```
H2.A: Grammar + Type Hashes (1 day)
H2.B: Profile source + compilation (1 day) — can run in parallel with H2.A
H2.C: Loader + integration (1 day) — depends on H2.B
H2.D: Tests + validation (1 day) — depends on H2.C
```

H2.A and H2.B can run in parallel; H2.C requires H2.B; H2.D requires H2.C.

---

## Key Insights

- **Bytecode is auditable**: Players can reproduce `bytecodeHex` from `nit.lisp` using the public Phase 21 compiler. Proof of bot behavior is cryptographic, not a signature.
- **Determinism is enforced**: The Lisp compiler is pure (no I/O, no randomness). Same source → same bytecode, always.
- **Seeded randomness is verifiable**: The Maniac profile's "random" decisions are actually deterministic PRNG seeded by the table cell (which is public). Collusion is detectable: two players would need the same seed to coordinate, which leaves evidence in the cell log.
- **LINEAR action cells prevent double-spending**: Each decision is a cell consumed once. A player cannot replay or reuse a past decision.
- **Personality profiles are swappable**: The poker engine loads bytecode at runtime. New profiles can be added without code changes; just deploy a new `.compiled.json` and restart with `BOT_PERSONA=newprofile`.

---

## References

| Document | Purpose |
|----------|---------|
| Phase 21 — Lisp axiom compiler | S-expression parsing, constraint interpretation, Forth bytecode generation |
| Phase 27 — Poker engine | Hand evaluation, SRA mental poker, betting FSM |
| Phase 36A — Extension grammar schema | ExtensionGrammar JSON contract, field mappings, linearity, phases |
| Phase 33 — DePIN 6LoWPAN | Example of DePIN vertical grammar and linear cell accountability |
| packages/shell/src/lisp/\* | Parser, types, compiler, packer (reference implementations) |
| packages/poker-agent/src/\* | Game engine integration points |
| packages/cell-ops/src/typeHashRegistry.ts | Type hash registration system |

---

**End of Phase H2 PRD**
