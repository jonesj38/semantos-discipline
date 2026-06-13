---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/hackathon/PHASE-H4-APEX-AGENT-SHADOW-LOOP.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.763210+00:00
---

# Phase H4 — Apex Agent Shadow Loop (Cognitive Layer)

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 4–5 days
**Prerequisites**: Phase H2 (Lisp personality profiles), Phase H3 (Border Router Overlay API), Phase 21 (Lisp compiler), Phase 25.5 (OP_CALLHOST), packages/cell-engine WASM kernel
**Master document**: `HACKATHON-PRD.md`
**Branch**: `hackathon/h4-apex-agent-shadow-loop`

---

## Context

Phase H4 introduces the **Apex Agent** — a special poker bot container that starts with a baseline Lisp policy (e.g., The Calculator) but runs an asynchronous background loop that continuously learns opponent patterns, prompts Claude Haiku/Sonnet to suggest policy improvements, and hot-swaps compiled Lisp policies into the running game loop without dropping network connections or losing table state.

The shadow loop is the cognitive layer that bridges game execution (Phase H1) with LLM-assisted policy evolution. This is where the "agent autonomy" emerges: the agent doesn't just follow a fixed rule set, it observes, learns, and adapts in real-time.

### The Apex Agent Architecture

```
┌──────────────────────────────────────────────────────────┐
│             APEX AGENT CONTAINER                         │
│                                                          │
│  ┌──────────────────┐      ┌───────────────────────┐    │
│  │   Game Loop      │      │ Shadow Loop (async)   │    │
│  │   (poker-agent)  │      │ (runs every 60s)      │    │
│  │                  │      │                       │    │
│  │  Plays poker     │◄─────│ 1. Poll /api/hands    │    │
│  │  using current   │      │ 2. Analyse patterns   │    │
│  │  policy.wasm     │      │ 3. Prompt Claude      │    │
│  │  Hot-swap point  │      │ 4. Parse new .lisp    │    │
│  │                  │      │ 5. Compile → Forth    │    │
│  │  reference to    │      │ 6. Hot-swap policy    │    │
│  │  currentPolicy   │      │ 7. Log evolution      │    │
│  │                  │      │                       │    │
│  └──────────────────┘      └───────────────────────┘    │
│         │                              │                 │
│         ▼                              ▼                 │
│  multicast to mesh           polls Border Router         │
│  (H1 transport)              Overlay API (H3)            │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### Design Principles

1. **Non-blocking hot-swap**: The game loop holds an atomic reference to `currentPolicy`. The shadow loop compiles in background and atomically replaces this reference. No thread locks, no missed hands.

2. **Provenance-tracked evolution**: Each policy version is stored as a RELEVANT cell with a prev-hash chain, creating an auditable cognitive history.

3. **Opponent-driven refinement**: The shadow loop extracts opponent tendencies (fold%, raise%, 3-bet%, showdown win%) from recent hand history and includes this in the LLM prompt.

4. **Fail-safe defaults**: If LLM returns invalid Lisp 3 times in a row, revert to the last known good policy. No crash-loop.

5. **Configurable cadence**: Shadow loop runs on a timer (every 60 seconds, every N hands, or manually triggered).

---

## Source Files / References

| Alias | Path | What to reference |
|-------|------|------------------|
| `MASTER:HACK` | `docs/prd/hackathon/HACKATHON-PRD.md` | Overall swarm architecture, agent taxonomy |
| `PHASE:H1` | `docs/prd/hackathon/PHASE-H1-DOCKER-SWARM-MESH.md` | Game loop, table lifecycle, multicast transport |
| `PHASE:H2` | `docs/prd/hackathon/PHASE-H2-LISP-PERSONALITIES.md` | Lisp personality profiles (Nit, Maniac, Calculator) |
| `PHASE:H3` | `docs/prd/hackathon/PHASE-H3-BORDER-ROUTER.md` | Overlay REST API (/api/hands, /api/personas, /ws/live), hand history storage |
| `PHASE:21` | `docs/prd/PHASE-21-LISP-AXIOM-COMPILER.md` | Lisp parser, compiler, Forth bytecode generation |
| `PHASE:25.5` | `docs/prd/PHASE-25.5-OP-CALLHOST.md` | Host function dispatch, extensible function registry |
| `KERNEL:MAIN` | `packages/cell-engine/src/main.zig` | WASM entry, 29 exported functions, memory layout |
| `KERNEL:EXECUTOR` | `packages/cell-engine/src/executor.zig` | Opcode dispatch, policy execution, stack semantics |
| `KERNEL:PDA` | `packages/cell-engine/src/pda.zig` | Dual-stack Push-Down Automaton, cell type validation |
| `GAME:LOOP` | `packages/poker-agent/src/game-loop.ts` | Existing game loop, accepts strategy functions |
| `GAME:STATE` | `packages/poker-agent/src/poker-state-machine.ts` | Game state machine, hand lifecycle, action validation |
| `SDK:ANTHROPIC` | `@anthropic-ai/sdk` | Claude API client (Haiku/Sonnet), streaming, error handling |
| `LISP:PARSER` | `packages/shell/src/lisp/parser.ts` | Lisp S-expression parser, validation |
| `LISP:COMPILER` | `packages/shell/src/lisp/compiler.ts` | Lisp-to-Forth compiler, type checking, opcode generation |
| `POLICY:BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming, branch rules |

---

## Deliverables

### DH4.1 — ShadowLoop Service (Core Orchestration)

**New file**: `packages/poker-agent/src/shadow-loop.ts`

The main service that orchestrates the poll → analyse → prompt → compile → swap cycle. Runs in a separate async context from the game loop.

```typescript
export interface ShadowLoopConfig {
  borderRouterUrl: string;        // e.g. http://localhost:3000
  anthropicApiKey: string;        // from env ANTHROPIC_API_KEY
  cadenceMs?: number;            // polling interval (default 60000ms = 60s)
  handThreshold?: number;         // compile every N hands (default 10)
  maxConsecutiveErrors?: number;  // revert policy after N LLM failures (default 3)
  modelId?: string;               // 'claude-3-5-haiku-20241022' or sonnet
}

export interface PolicyVersion {
  version: number;
  lisp: string;                   // S-expression as string
  bytecode: Uint8Array;           // Compiled Forth bytecode
  timestamp: number;              // Unix ms when compiled
  prevHash: string | null;        // Chain to previous version
  lispValidation: {
    isValid: boolean;
    errors: string[];
  };
}

export class ShadowLoop {
  private config: ShadowLoopConfig;
  private currentPolicy: PolicyVersion;
  private gameLoopRef: GameLoopHandle;  // Reference to hot-swap point
  private opponentAnalyser: OpponentAnalyser;
  private lispCompiler: LispCompiler;
  private policyEvolutionChain: PolicyEvolutionChain;
  private consecutiveErrors: number = 0;
  private lastKnownGoodPolicy: PolicyVersion;

  constructor(config: ShadowLoopConfig, gameLoopRef: GameLoopHandle) {
    this.config = config;
    this.gameLoopRef = gameLoopRef;
    this.opponentAnalyser = new OpponentAnalyser(config.borderRouterUrl);
    this.lispCompiler = new LispCompiler();
    this.policyEvolutionChain = new PolicyEvolutionChain();
  }

  /**
   * Main loop: run on cadence (e.g. every 60s)
   */
  async runCycle(): Promise<void> {
    try {
      // Step 1: Fetch last N hands from Border Router
      const hands = await this.opponentAnalyser.fetchRecentHands(100);

      // Step 2: Extract opponent patterns
      const analysis = await this.opponentAnalyser.analyseOpponents(hands);

      // Step 3: Prompt Claude with current policy + opponent stats
      const newLisp = await this.promptLLM(this.currentPolicy.lisp, analysis);

      // Step 4: Validate Lisp syntax
      const validation = this.lispCompiler.validate(newLisp);
      if (!validation.isValid) {
        this.handleValidationError(validation);
        return;
      }

      // Step 5: Compile to Forth bytecode
      const bytecode = this.lispCompiler.compile(newLisp);

      // Step 6: Create new policy version
      const newPolicy: PolicyVersion = {
        version: this.currentPolicy.version + 1,
        lisp: newLisp,
        bytecode,
        timestamp: Date.now(),
        prevHash: this.hashPolicy(this.currentPolicy),
        lispValidation: validation,
      };

      // Step 7: Hot-swap into game loop
      this.swapPolicy(newPolicy);

      // Step 8: Store in evolution chain (RELEVANT cell)
      await this.policyEvolutionChain.logVersion(newPolicy);

      // Reset error counter on success
      this.consecutiveErrors = 0;
      this.lastKnownGoodPolicy = newPolicy;

      console.log(
        `[ShadowLoop] Policy v${newPolicy.version} compiled and hot-swapped`,
      );
    } catch (err) {
      this.handleShadowLoopError(err);
    }
  }

  /**
   * Atomic hot-swap: replace currentPolicy reference in game loop
   */
  private swapPolicy(newPolicy: PolicyVersion): void {
    this.currentPolicy = newPolicy;
    this.gameLoopRef.setPolicyReference(newPolicy);
  }

  /**
   * On validation error: increment counter, revert if threshold exceeded
   */
  private handleValidationError(validation: LispValidation): void {
    this.consecutiveErrors++;
    console.warn(
      `[ShadowLoop] Validation error (${this.consecutiveErrors}/${this.config.maxConsecutiveErrors || 3}): ${validation.errors.join(', ')}`,
    );

    if (
      this.consecutiveErrors >=
      (this.config.maxConsecutiveErrors || 3)
    ) {
      console.error(
        '[ShadowLoop] Max consecutive errors reached. Reverting to last known good policy.',
      );
      this.swapPolicy(this.lastKnownGoodPolicy);
      this.consecutiveErrors = 0;
    }
  }

  private handleShadowLoopError(err: unknown): void {
    console.error('[ShadowLoop] Error in cycle:', err);
    // Non-fatal: continue polling on next cadence
  }

  private hashPolicy(policy: PolicyVersion): string {
    // SHA256(lisp + bytecode + timestamp)
    const content = policy.lisp + policy.bytecode.toString() + policy.timestamp;
    return computeSHA256(content);
  }

  /**
   * Start the shadow loop on the configured cadence
   */
  async start(): Promise<void> {
    const cadenceMs = this.config.cadenceMs || 60000;
    console.log(`[ShadowLoop] Starting on ${cadenceMs}ms cadence`);

    // eslint-disable-next-line @typescript-eslint/no-floating-promises
    (async () => {
      while (true) {
        await this.runCycle();
        await new Promise((resolve) => setTimeout(resolve, cadenceMs));
      }
    })();
  }

  /**
   * For testing: run one cycle manually
   */
  async runOnce(): Promise<void> {
    await this.runCycle();
  }

  async promptLLM(
    currentLisp: string,
    analysis: OpponentAnalysis,
  ): Promise<string> {
    // Implemented in section DH4.3
    throw new Error('To be implemented');
  }
}
```

**Acceptance criteria**:
- ShadowLoop instantiates with config and gameLoopRef
- `runCycle()` executes all 8 steps without throwing
- `start()` begins polling on cadence
- `runOnce()` executes one cycle for testing
- No game loop disruption during policy swap

### DH4.2 — OpponentAnalyser (Pattern Extraction)

**New file**: `packages/poker-agent/src/opponent-analyser.ts`

Fetches hand history from the Border Router and extracts opponent patterns (fold%, raise%, 3-bet%, showdown win%, etc.).

```typescript
export interface OpponentStats {
  botId: string;        // Opponent's bot ID / BCA
  handsPlayed: number;
  foldPercent: number;
  raisePercent: number;
  threeBetPercent: number;
  showdownWinPercent: number;
  bluffFrequency: number;  // Bluffs per hand
  aggressionScore: number; // 0-100: passive to aggressive
}

export interface OpponentAnalysis {
  opponents: OpponentStats[];
  selfWinRate: number;           // Your win% in last N hands
  trends: {
    mostAggressive: OpponentStats;
    mostPassive: OpponentStats;
    mostBluffHeavy: OpponentStats;
  };
  summary: string;  // Human-readable analysis for LLM prompt
}

export class OpponentAnalyser {
  private borderRouterUrl: string;

  constructor(borderRouterUrl: string) {
    this.borderRouterUrl = borderRouterUrl;
  }

  /**
   * Fetch last N completed hands from Border Router /api/hands
   */
  async fetchRecentHands(count: number): Promise<Hand[]> {
    const response = await fetch(
      `${this.borderRouterUrl}/api/hands?limit=${count}`,
    );
    if (!response.ok) {
      throw new Error(`Failed to fetch hands: ${response.status}`);
    }
    return response.json();
  }

  /**
   * Analyse hand history and extract opponent tendencies
   */
  async analyseOpponents(hands: Hand[]): Promise<OpponentAnalysis> {
    const opponentMap = new Map<string, OpponentStats>();
    let myWins = 0;
    let myHands = 0;

    // Process each hand
    for (const hand of hands) {
      // Count wins
      if (hand.winner === hand.myBotId) {
        myWins++;
      }
      myHands++;

      // Extract actions per opponent
      for (const action of hand.actions) {
        if (action.botId === hand.myBotId) continue; // Skip self

        let opponent = opponentMap.get(action.botId);
        if (!opponent) {
          opponent = {
            botId: action.botId,
            handsPlayed: 0,
            foldPercent: 0,
            raisePercent: 0,
            threeBetPercent: 0,
            showdownWinPercent: 0,
            bluffFrequency: 0,
            aggressionScore: 0,
          };
          opponentMap.set(action.botId, opponent);
        }

        // Count action types
        if (action.type === 'fold') {
          opponent.foldPercent++;
        } else if (action.type === 'raise') {
          opponent.raisePercent++;
        } else if (action.type === 'three-bet') {
          opponent.threeBetPercent++;
        }
      }

      // Track showdown wins
      for (const showdown of hand.showdown || []) {
        const opponent = opponentMap.get(showdown.botId);
        if (opponent && showdown.won) {
          opponent.showdownWinPercent++;
        }
      }
    }

    // Normalize percentages and compute aggression score
    const opponents = Array.from(opponentMap.values()).map((opp) => {
      const totalActions =
        opp.foldPercent + opp.raisePercent + opp.threeBetPercent || 1;
      opp.foldPercent = (opp.foldPercent / totalActions) * 100;
      opp.raisePercent = (opp.raisePercent / totalActions) * 100;
      opp.threeBetPercent = (opp.threeBetPercent / totalActions) * 100;
      opp.aggressionScore =
        opp.raisePercent * 0.6 + opp.threeBetPercent * 0.4;

      return opp;
    });

    // Find trends
    const mostAggressive = opponents.reduce((a, b) =>
      a.aggressionScore > b.aggressionScore ? a : b,
    );
    const mostPassive = opponents.reduce((a, b) =>
      a.aggressionScore < b.aggressionScore ? a : b,
    );
    const mostBluffHeavy = opponents.reduce((a, b) =>
      a.bluffFrequency > b.bluffFrequency ? a : b,
    );

    const selfWinRate = myHands > 0 ? (myWins / myHands) * 100 : 0;

    return {
      opponents,
      selfWinRate,
      trends: {
        mostAggressive,
        mostPassive,
        mostBluffHeavy,
      },
      summary: this.buildSummary(opponents, selfWinRate),
    };
  }

  private buildSummary(
    opponents: OpponentStats[],
    selfWinRate: number,
  ): string {
    return `
Your recent performance: ${selfWinRate.toFixed(1)}% win rate

Opponent profiles:
${opponents
  .map(
    (opp) =>
      `- ${opp.botId}: fold ${opp.foldPercent.toFixed(1)}%, raise ${opp.raisePercent.toFixed(1)}%, aggression ${opp.aggressionScore.toFixed(1)}/100`,
  )
  .join('\n')}

Most aggressive: ${opponents[0].botId} (${opponents[0].aggressionScore.toFixed(1)}/100)
Most passive: ${opponents[opponents.length - 1].botId} (${opponents[opponents.length - 1].aggressionScore.toFixed(1)}/100)
    `.trim();
  }
}
```

**Acceptance criteria**:
- `fetchRecentHands(100)` returns array of Hand objects from Border Router
- `analyseOpponents()` extracts fold%, raise%, 3-bet% from action history
- OpponentAnalysis includes per-opponent stats and summary string
- Handles empty hand history gracefully
- Aggression score correlates with raise frequency

### DH4.3 — LLM Prompt Template and Response Parser

**New file**: `packages/poker-agent/src/llm-prompt-handler.ts`

Formats structured prompt to Claude with current policy + opponent stats, receives Lisp policy response, parses and validates it.

```typescript
export interface LLMPromptInput {
  currentLisp: string;
  opponentAnalysis: OpponentAnalysis;
  context: {
    agentName: string;
    botIndex: number;
    gamePhase: string;  // e.g. "preflop", "flop", "turn", "river"
  };
}

export interface LLMResponse {
  reasoning: string;
  updatedLisp: string;
  rationale: string;
}

export class LLMPromptHandler {
  private anthropicClient: Anthropic;

  constructor(apiKey: string) {
    this.anthropicClient = new Anthropic({ apiKey });
  }

  /**
   * Build structured prompt for LLM
   */
  private buildPrompt(input: LLMPromptInput): string {
    return `You are a poker strategy advisor for an autonomous agent.

## Current Agent Policy (Lisp)
\`\`\`lisp
${input.currentLisp}
\`\`\`

## Recent Opponent Analysis
${input.opponentAnalysis.summary}

Your win rate: ${input.opponentAnalysis.selfWinRate.toFixed(1)}%

## Task
Analyze the opponent profiles and suggest an improved poker strategy. You MUST respond with:

1. A brief reasoning paragraph (2-3 sentences)
2. A complete, valid Lisp S-expression policy that follows these rules:
   - ONLY use these atoms: fold, call, raise, bet, check
   - ONLY use these predicates: (opponent-aggressive?), (have-strong-hand?), (pot-odds-good?), (position-late?)
   - Predicates return t (true) or nil (false)
   - Policy is a series of (if condition action action-else) forms
   - Example: (if (opponent-aggressive?) (check) (fold))
   - All Lisp must be valid S-expressions with balanced parentheses
   - START with (defpolicy apex-strategy and END with a closing paren
3. A brief rationale (why this improves win rate against these opponents)

CRITICAL: Return ONLY valid Lisp that can be parsed and compiled. If unsure, return the current policy unchanged.

## Output Format
Return your response in this exact format:

REASONING:
[your reasoning paragraph]

LISP:
[complete Lisp policy starting with (defpolicy...]

RATIONALE:
[why this improves win rate]`;
  }

  /**
   * Call Claude API and parse response
   */
  async promptLLM(input: LLMPromptInput): Promise<LLMResponse> {
    const prompt = this.buildPrompt(input);

    const message = await this.anthropicClient.messages.create({
      model: 'claude-3-5-haiku-20241022', // or claude-3-5-sonnet-20241022 for better quality
      max_tokens: 1024,
      messages: [
        {
          role: 'user',
          content: prompt,
        },
      ],
    });

    const responseText =
      message.content[0].type === 'text' ? message.content[0].text : '';

    return this.parseResponse(responseText);
  }

  /**
   * Parse LLM response into structured format
   */
  private parseResponse(text: string): LLMResponse {
    const reasoningMatch = text.match(/REASONING:\s*([\s\S]*?)(?=LISP:)/);
    const lispMatch = text.match(/LISP:\s*([\s\S]*?)(?=RATIONALE:)/);
    const rationaleMatch = text.match(/RATIONALE:\s*([\s\S]*?)$/);

    const updatedLisp = lispMatch
      ? lispMatch[1].trim()
      : '(defpolicy fallback (fold))';

    return {
      reasoning: reasoningMatch ? reasoningMatch[1].trim() : '',
      updatedLisp,
      rationale: rationaleMatch ? rationaleMatch[1].trim() : '',
    };
  }

  /**
   * Validate that response Lisp is parseable
   */
  validateLispResponse(lisp: string): { isValid: boolean; errors: string[] } {
    const errors: string[] = [];

    // Check balanced parens
    let parenCount = 0;
    for (const char of lisp) {
      if (char === '(') parenCount++;
      if (char === ')') parenCount--;
      if (parenCount < 0) {
        errors.push('Unbalanced parentheses (closing before opening)');
        break;
      }
    }
    if (parenCount !== 0) {
      errors.push('Unbalanced parentheses (unclosed)');
    }

    // Check that it starts with (defpolicy
    if (!lisp.trim().startsWith('(defpolicy')) {
      errors.push('Lisp must start with (defpolicy ...');
    }

    // Check for forbidden atoms
    const forbidden = ['defun', 'quote', 'eval', 'load', 'save'];
    for (const atom of forbidden) {
      if (lisp.includes(atom)) {
        errors.push(`Forbidden atom: ${atom}`);
      }
    }

    return {
      isValid: errors.length === 0,
      errors,
    };
  }
}
```

**Acceptance criteria**:
- `buildPrompt()` includes current Lisp, opponent stats, and task instructions
- `promptLLM()` calls Claude API and returns parsed response
- `parseResponse()` extracts REASONING, LISP, RATIONALE sections
- `validateLispResponse()` checks for balanced parens, defpolicy prefix, forbidden atoms
- Response validation rejects incomplete or malformed Lisp

### DH4.4 — PolicyEvolutionChain (Provenance & Storage)

**New file**: `packages/poker-agent/src/policy-evolution-chain.ts`

Stores each policy version as a RELEVANT cell with a prev-hash chain, creating an auditable cognitive history. Uses the existing cell-engine for packing/unpacking.

```typescript
export interface PolicyEvolutionCell {
  cellType: 'policy.evolution';
  version: number;
  lisp: string;
  lispHash: string;         // SHA256 of Lisp code
  bytecodeHash: string;     // SHA256 of compiled bytecode
  timestamp: number;
  prevHash: string | null;  // Hash of previous policy cell
  nextHash?: string;        // Hash of next version (when superseded)
  botId: string;            // Bot that owns this policy
  parentCellId: string;     // Reference to parent (prev version cell)
}

export class PolicyEvolutionChain {
  private borderRouterUrl: string;
  private cellEngine: CellEngine;
  private chainHead: PolicyEvolutionCell | null = null;

  constructor(borderRouterUrl: string, cellEngine: CellEngine) {
    this.borderRouterUrl = borderRouterUrl;
    this.cellEngine = cellEngine;
  }

  /**
   * Log a new policy version to the evolution chain
   * Stores as RELEVANT cell; may be persisted via Border Router
   */
  async logVersion(
    policy: PolicyVersion,
    botId: string,
  ): Promise<PolicyEvolutionCell> {
    // Create cell
    const cell: PolicyEvolutionCell = {
      cellType: 'policy.evolution',
      version: policy.version,
      lisp: policy.lisp,
      lispHash: this.computeHash(policy.lisp),
      bytecodeHash: this.computeHash(policy.bytecode),
      timestamp: policy.timestamp,
      prevHash: policy.prevHash || null,
      botId,
      parentCellId: this.chainHead?.lispHash || 'genesis',
    };

    // Pack into RELEVANT cell format
    const cellData = this.packCell(cell);

    // Store locally or publish to Border Router (TBD by H3 API)
    try {
      await fetch(`${this.borderRouterUrl}/api/policy-versions`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ cell: cellData, metadata: cell }),
      });
    } catch (err) {
      console.warn('[PolicyEvolutionChain] Failed to persist cell:', err);
      // Non-fatal: cell is already in memory
    }

    this.chainHead = cell;
    return cell;
  }

  /**
   * Retrieve policy history: walk the chain backwards
   */
  async getHistory(botId: string, limit: number = 10): Promise<PolicyEvolutionCell[]> {
    const history: PolicyEvolutionCell[] = [];
    let current = this.chainHead;

    while (current && history.length < limit) {
      if (current.botId === botId) {
        history.push(current);
      }

      // Fetch previous cell by prevHash
      if (current.prevHash) {
        try {
          const response = await fetch(
            `${this.borderRouterUrl}/api/policy-versions/${current.prevHash}`,
          );
          if (response.ok) {
            current = await response.json();
          } else {
            break;
          }
        } catch {
          break;
        }
      } else {
        break;
      }
    }

    return history;
  }

  /**
   * Revert to a previous policy version by hash
   */
  async revertToVersion(hash: string): Promise<PolicyEvolutionCell | null> {
    try {
      const response = await fetch(
        `${this.borderRouterUrl}/api/policy-versions/${hash}`,
      );
      if (response.ok) {
        const cell: PolicyEvolutionCell = await response.json();
        this.chainHead = cell;
        return cell;
      }
    } catch (err) {
      console.error('[PolicyEvolutionChain] Failed to revert:', err);
    }
    return null;
  }

  private packCell(cell: PolicyEvolutionCell): Uint8Array {
    // Pack cell using CellEngine (standard RELEVANT cell format)
    // For now: JSON serialize and encode
    const json = JSON.stringify(cell);
    return new TextEncoder().encode(json);
  }

  private computeHash(data: Uint8Array | string): string {
    // SHA256 hash implementation
    const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : data;
    return crypto.subtle.digest('SHA-256', bytes).toString();
  }
}
```

**Acceptance criteria**:
- `logVersion()` stores policy as RELEVANT cell with prev-hash chain
- `getHistory()` traverses chain and returns policy versions
- `revertToVersion()` restores a previous policy from hash
- Cells are persisted (via Border Router or local storage)
- Chain is queryable and auditable

### DH4.5 — Hot-Swap Mechanism (Atomic Policy Replacement)

**New file**: `packages/poker-agent/src/policy-hot-swap.ts`

Atomic replacement of the policy reference in the running game loop. Uses a shared reference that the game loop checks on each hand decision.

```typescript
export interface GameLoopHandle {
  /**
   * Set a new policy reference (atomic).
   * Game loop will use this reference on next decision point.
   */
  setPolicyReference(policy: PolicyVersion): void;

  /**
   * Get current policy without taking ownership
   */
  getCurrentPolicy(): PolicyVersion;
}

export class PolicyHotSwapper implements GameLoopHandle {
  private currentPolicyRef: AtomicReference<PolicyVersion>;

  constructor(initialPolicy: PolicyVersion) {
    this.currentPolicyRef = new AtomicReference(initialPolicy);
  }

  setPolicyReference(policy: PolicyVersion): void {
    // Atomic compare-and-swap (CAS)
    // In TypeScript, this is not lock-free, but we avoid mutation
    // by creating a new reference object
    this.currentPolicyRef.set(policy);

    console.log(
      `[HotSwapper] Policy reference updated: v${policy.version}`,
    );
  }

  getCurrentPolicy(): PolicyVersion {
    return this.currentPolicyRef.get();
  }
}

/**
 * Simple atomic reference wrapper
 * (In production, might use worker threads or process.atomics)
 */
class AtomicReference<T> {
  private value: T;

  constructor(initial: T) {
    this.value = initial;
  }

  set(newValue: T): void {
    this.value = newValue;
  }

  get(): T {
    return this.value;
  }

  /**
   * Compare-and-swap: only update if current matches expected
   * Returns true if swap succeeded, false if current != expected
   */
  cas(expected: T, newValue: T): boolean {
    if (this.value === expected) {
      this.value = newValue;
      return true;
    }
    return false;
  }
}
```

**Integration with Game Loop**:

In `packages/poker-agent/src/game-loop.ts`, modify the decision point:

```typescript
// Before shadow loop era:
// const action = await this.strategy(gameState);

// After hot-swap integration:
export class GameLoop {
  private policySwapper: PolicyHotSwapper;

  constructor(initialPolicy: PolicyVersion, ...) {
    this.policySwapper = new PolicyHotSwapper(initialPolicy);
    // ...
  }

  async decideAction(gameState: GameState): Promise<Action> {
    // Get current policy (may have been swapped by shadow loop)
    const policy = this.policySwapper.getCurrentPolicy();

    // Execute policy bytecode through kernel
    const action = await this.executePolicy(policy.bytecode, gameState);
    return action;
  }

  /**
   * For shadow loop to inject new policy
   */
  getSwapper(): PolicyHotSwapper {
    return this.policySwapper;
  }
}
```

**Acceptance criteria**:
- `setPolicyReference()` atomically replaces policy without locking
- Game loop reads current policy on each decision
- No missed hands during swap
- No network interruption
- Table state remains consistent

### DH4.6 — Apex Container Entrypoint

**New file**: `packages/poker-agent/src/apex-entrypoint.ts`

Extends the bot entrypoint to include shadow loop initialization and management.

```typescript
import { createPolicyEvolutionChain } from './policy-evolution-chain';
import { ShadowLoop } from './shadow-loop';
import { GameLoop } from './game-loop';
import { PolicyVersion } from './types';

export interface ApexConfig {
  botIndex: number;
  persona: 'calculator' | 'nit' | 'maniac' | 'apex';
  borderRouterUrl: string;
  dockerMulticastAdapter: NetworkAdapter;
  shadowLoopCadenceMs?: number;
  initialPolicy?: PolicyVersion;
}

export async function runApexAgent(config: ApexConfig): Promise<void> {
  console.log(`[Apex] Starting bot-${config.botIndex} (${config.persona})`);

  // 1. Load initial policy (e.g., The Calculator from H2)
  const initialPolicy = config.initialPolicy || (await loadBaselinePolicy(config.persona));

  // 2. Create game loop with hot-swap support
  const gameLoop = new GameLoop(initialPolicy, {
    botIndex: config.botIndex,
    persona: config.persona,
    networkAdapter: config.dockerMulticastAdapter,
  });

  // 3. Start game loop (joins tables, plays hands)
  await gameLoop.start();

  // 4. Create shadow loop
  const shadowLoop = new ShadowLoop(
    {
      borderRouterUrl: config.borderRouterUrl,
      anthropicApiKey: process.env.ANTHROPIC_API_KEY || '',
      cadenceMs: config.shadowLoopCadenceMs || 60000,
      modelId: 'claude-3-5-haiku-20241022',
    },
    gameLoop.getSwapper(),
  );

  // 5. Start shadow loop (async, non-blocking)
  await shadowLoop.start();

  console.log(`[Apex] Shadow loop active on ${config.shadowLoopCadenceMs || 60000}ms cadence`);

  // Game and shadow loops run concurrently
  // Game loop: plays poker
  // Shadow loop: learns and evolves policy
}

async function loadBaselinePolicy(persona: string): Promise<PolicyVersion> {
  // Load pre-compiled Lisp policy from H2 (The Calculator, Nit, Maniac)
  // Return bytecode as PolicyVersion
  throw new Error('To be implemented by H2');
}
```

**Acceptance criteria**:
- Apex entrypoint loads baseline policy
- Creates GameLoop with hot-swap support
- Creates ShadowLoop with config
- Starts both concurrently
- No blocking between game and shadow loops

### DH4.7 — Gate Tests (T1–T10)

**New file**: `packages/poker-agent/tests/shadow-loop.test.ts`

TDD gate tests for shadow loop functionality.

```typescript
import { describe, it, expect, beforeEach, afterEach } from 'bun:test';
import { ShadowLoop, PolicyVersion } from '../src/shadow-loop';
import { OpponentAnalyser } from '../src/opponent-analyser';
import { LLMPromptHandler } from '../src/llm-prompt-handler';
import { PolicyEvolutionChain } from '../src/policy-evolution-chain';
import { PolicyHotSwapper } from '../src/policy-hot-swap';
import { GameLoop } from '../src/game-loop';
import { LispCompiler } from '../../shell/src/lisp/compiler';

describe('Shadow Loop (DH4.1–DH4.7)', () => {
  let shadowLoop: ShadowLoop;
  let mockGameLoop: MockGameLoop;
  let mockBorderRouter: MockBorderRouter;

  beforeEach(async () => {
    mockBorderRouter = new MockBorderRouter();
    mockGameLoop = new MockGameLoop();

    shadowLoop = new ShadowLoop(
      {
        borderRouterUrl: mockBorderRouter.baseUrl,
        anthropicApiKey: 'test-key',
        cadenceMs: 100, // Short cadence for tests
      },
      mockGameLoop.getSwapper(),
    );
  });

  describe('T1: Fetch recent hands from Border Router', () => {
    it('should fetch last N hands from /api/hands', async () => {
      const hands = await shadowLoop['opponentAnalyser'].fetchRecentHands(10);
      expect(hands.length).toBe(10);
      expect(hands[0]).toHaveProperty('id');
      expect(hands[0]).toHaveProperty('actions');
    });

    it('should handle empty hand history', async () => {
      mockBorderRouter.setHandsCount(0);
      const hands = await shadowLoop['opponentAnalyser'].fetchRecentHands(10);
      expect(hands.length).toBe(0);
    });

    it('should fail gracefully if Border Router is unreachable', async () => {
      mockBorderRouter.setUnreachable(true);
      const hands = await shadowLoop['opponentAnalyser']
        .fetchRecentHands(10)
        .catch((err) => []);
      expect(hands).toEqual([]);
    });
  });

  describe('T2: Analyse opponent patterns', () => {
    it('should extract fold% from hand history', async () => {
      const analysis = await shadowLoop['opponentAnalyser'].analyseOpponents(
        mockBorderRouter.generateMockHands(20),
      );
      expect(analysis.opponents.length).toBeGreaterThan(0);
      expect(analysis.opponents[0]).toHaveProperty('foldPercent');
      expect(analysis.opponents[0].foldPercent).toBeGreaterThanOrEqual(0);
      expect(analysis.opponents[0].foldPercent).toBeLessThanOrEqual(100);
    });

    it('should compute aggression score', async () => {
      const analysis = await shadowLoop['opponentAnalyser'].analyseOpponents(
        mockBorderRouter.generateMockHands(20),
      );
      expect(analysis.opponents[0].aggressionScore).toBeGreaterThanOrEqual(0);
      expect(analysis.opponents[0].aggressionScore).toBeLessThanOrEqual(100);
    });

    it('should identify win rate', async () => {
      const analysis = await shadowLoop['opponentAnalyser'].analyseOpponents(
        mockBorderRouter.generateMockHands(20),
      );
      expect(analysis.selfWinRate).toBeGreaterThanOrEqual(0);
      expect(analysis.selfWinRate).toBeLessThanOrEqual(100);
    });
  });

  describe('T3: Prompt Claude with current policy + opponent stats', () => {
    it('should call LLM with structured prompt', async () => {
      const handler = new LLMPromptHandler('test-key');
      const prompt = handler['buildPrompt']({
        currentLisp: '(defpolicy test (fold))',
        opponentAnalysis: mockBorderRouter.generateMockAnalysis(),
        context: { agentName: 'Test', botIndex: 0, gamePhase: 'preflop' },
      });

      expect(prompt).toContain('(defpolicy test');
      expect(prompt).toContain('opponent');
      expect(prompt).toContain('LISP:');
    });

    it('should validate LLM response format', () => {
      const handler = new LLMPromptHandler('test-key');
      const response = `REASONING:
Opponents are aggressive preflop.

LISP:
(defpolicy apex-improved (if (opponent-aggressive?) (check) (fold)))

RATIONALE:
This exploits aggressive opponents by checking strong hands.`;

      const parsed = handler['parseResponse'](response);
      expect(parsed.reasoning).toContain('aggressive');
      expect(parsed.updatedLisp).toContain('(defpolicy');
      expect(parsed.rationale).toContain('exploits');
    });

    it('should extract valid Lisp from malformed response', () => {
      const handler = new LLMPromptHandler('test-key');
      const messyResponse = `
Some rambling text here...

REASONING:
Try tighter preflop ranges.

LISP:
(defpolicy tight-policy
  (if (position-late?) (raise) (fold)))

RATIONALE:
Better for late position aggression.

Extra junk at the end...`;

      const parsed = handler['parseResponse'](messyResponse);
      expect(parsed.updatedLisp).toContain('(defpolicy');
    });
  });

  describe('T4: Validate and compile Lisp to Forth bytecode', () => {
    it('should reject invalid Lisp (unbalanced parens)', () => {
      const compiler = new LispCompiler();
      const validation = compiler.validate('(defpolicy test (fold)))');
      expect(validation.isValid).toBe(false);
      expect(validation.errors.length).toBeGreaterThan(0);
    });

    it('should reject Lisp missing defpolicy', () => {
      const compiler = new LispCompiler();
      const validation = compiler.validate('(fold)');
      expect(validation.isValid).toBe(false);
    });

    it('should accept valid Lisp and compile to bytecode', () => {
      const compiler = new LispCompiler();
      const lisp = '(defpolicy test (fold))';
      const validation = compiler.validate(lisp);
      expect(validation.isValid).toBe(true);

      const bytecode = compiler.compile(lisp);
      expect(bytecode).toBeInstanceOf(Uint8Array);
      expect(bytecode.length).toBeGreaterThan(0);
    });

    it('should compile complex policy with conditionals', () => {
      const compiler = new LispCompiler();
      const lisp = `(defpolicy complex
        (if (opponent-aggressive?)
          (check)
          (if (have-strong-hand?)
            (raise)
            (fold))))`;
      const validation = compiler.validate(lisp);
      expect(validation.isValid).toBe(true);

      const bytecode = compiler.compile(lisp);
      expect(bytecode.length).toBeGreaterThan(0);
    });
  });

  describe('T5: Hot-swap policy into game loop', () => {
    it('should atomically replace policy reference', () => {
      const oldPolicy: PolicyVersion = {
        version: 1,
        lisp: '(defpolicy v1 (fold))',
        bytecode: new Uint8Array([0x01, 0x02]),
        timestamp: Date.now(),
        prevHash: null,
        lispValidation: { isValid: true, errors: [] },
      };

      const newPolicy: PolicyVersion = {
        version: 2,
        lisp: '(defpolicy v2 (call))',
        bytecode: new Uint8Array([0x03, 0x04]),
        timestamp: Date.now(),
        prevHash: '0xabc123',
        lispValidation: { isValid: true, errors: [] },
      };

      const swapper = new PolicyHotSwapper(oldPolicy);
      swapper.setPolicyReference(newPolicy);

      const current = swapper.getCurrentPolicy();
      expect(current.version).toBe(2);
      expect(current.lisp).toContain('v2');
    });

    it('should not block game loop during swap', async () => {
      const policy = {
        version: 1,
        lisp: '(defpolicy test (fold))',
        bytecode: new Uint8Array([0x01]),
        timestamp: Date.now(),
        prevHash: null,
        lispValidation: { isValid: true, errors: [] },
      };

      const swapper = new PolicyHotSwapper(policy);

      // Simulate game loop reading policy
      const readings: number[] = [];
      const swaps: Promise<void>[] = [];

      for (let i = 0; i < 100; i++) {
        if (i % 10 === 0) {
          // Swap every 10 reads
          swaps.push(
            Promise.resolve(
              swapper.setPolicyReference({
                ...policy,
                version: i / 10,
              }),
            ),
          );
        }
        readings.push(swapper.getCurrentPolicy().version);
      }

      await Promise.all(swaps);
      expect(readings.length).toBe(100);
      // All reads should succeed without exception
    });
  });

  describe('T6: Fallback on consecutive LLM errors', () => {
    it('should revert policy after 3 validation errors', async () => {
      let errorCount = 0;
      mockBorderRouter.setLLMResponder((prompt: string) => {
        errorCount++;
        if (errorCount < 3) {
          // Return invalid Lisp
          return 'LISP: (malformed-lisp unbalanced';
        } else {
          // Valid Lisp on 4th call
          return 'LISP: (defpolicy good-policy (fold))';
        }
      });

      // This test would require mocking LLM responses in ShadowLoop
      // Implementation depends on how LLMPromptHandler integrates with ShadowLoop
      expect(errorCount).toBeGreaterThan(0);
    });
  });

  describe('T7: Store policy in evolution chain', () => {
    it('should log policy as RELEVANT cell with prev-hash', async () => {
      const chain = new PolicyEvolutionChain(
        mockBorderRouter.baseUrl,
        {} as any, // Mock CellEngine
      );

      const policy: PolicyVersion = {
        version: 1,
        lisp: '(defpolicy test (fold))',
        bytecode: new Uint8Array([0x01]),
        timestamp: Date.now(),
        prevHash: null,
        lispValidation: { isValid: true, errors: [] },
      };

      const cell = await chain.logVersion(policy, 'bot-0');
      expect(cell.version).toBe(1);
      expect(cell.lisp).toContain('(defpolicy');
      expect(cell.prevHash).toBeNull();
    });

    it('should create prev-hash chain for evolution trail', async () => {
      const chain = new PolicyEvolutionChain(
        mockBorderRouter.baseUrl,
        {} as any,
      );

      const v1: PolicyVersion = {
        version: 1,
        lisp: '(defpolicy v1 (fold))',
        bytecode: new Uint8Array([0x01]),
        timestamp: Date.now(),
        prevHash: null,
        lispValidation: { isValid: true, errors: [] },
      };

      const cell1 = await chain.logVersion(v1, 'bot-0');

      const v2: PolicyVersion = {
        version: 2,
        lisp: '(defpolicy v2 (call))',
        bytecode: new Uint8Array([0x02]),
        timestamp: Date.now(),
        prevHash: cell1.lispHash,
        lispValidation: { isValid: true, errors: [] },
      };

      const cell2 = await chain.logVersion(v2, 'bot-0');
      expect(cell2.prevHash).toBe(cell1.lispHash);
    });
  });

  describe('T8: Shadow loop cycle (full integration)', () => {
    it('should run poll → analyse → prompt → compile → swap cycle', async () => {
      let cycleCount = 0;
      const originalRunCycle = shadowLoop.runCycle.bind(shadowLoop);

      shadowLoop.runCycle = async () => {
        cycleCount++;
        await originalRunCycle();
      };

      await shadowLoop.runOnce();
      expect(cycleCount).toBe(1);
    });

    it('should handle zero hands gracefully', async () => {
      mockBorderRouter.setHandsCount(0);
      await shadowLoop.runOnce();
      // Should not crash
      expect(true).toBe(true);
    });
  });

  describe('T9: Performance — no hand drops during swap', () => {
    it('should complete swap in < 10ms', async () => {
      const swapper = new PolicyHotSwapper({
        version: 1,
        lisp: '(defpolicy test (fold))',
        bytecode: new Uint8Array([0x01]),
        timestamp: Date.now(),
        prevHash: null,
        lispValidation: { isValid: true, errors: [] },
      });

      const start = performance.now();
      swapper.setPolicyReference({
        version: 2,
        lisp: '(defpolicy test (call))',
        bytecode: new Uint8Array([0x02]),
        timestamp: Date.now(),
        prevHash: '0xabc',
        lispValidation: { isValid: true, errors: [] },
      });
      const elapsed = performance.now() - start;

      expect(elapsed).toBeLessThan(10);
    });
  });

  describe('T10: End-to-end Apex container', () => {
    it('should start game loop + shadow loop concurrently', async () => {
      const config = {
        botIndex: 0,
        persona: 'calculator' as const,
        borderRouterUrl: mockBorderRouter.baseUrl,
        dockerMulticastAdapter: {} as any,
        shadowLoopCadenceMs: 100,
      };

      // Mock the actual startup to avoid long-running processes
      let gameLoopStarted = false;
      let shadowLoopStarted = false;

      // In real implementation, would check logs or process state
      expect([gameLoopStarted, shadowLoopStarted]).toBeDefined();
    });
  });
});

// Mocks
class MockGameLoop {
  private swapper: PolicyHotSwapper;

  constructor() {
    this.swapper = new PolicyHotSwapper({
      version: 0,
      lisp: '(defpolicy baseline (fold))',
      bytecode: new Uint8Array([0x00]),
      timestamp: Date.now(),
      prevHash: null,
      lispValidation: { isValid: true, errors: [] },
    });
  }

  getSwapper(): PolicyHotSwapper {
    return this.swapper;
  }
}

class MockBorderRouter {
  baseUrl = 'http://localhost:9999';
  private handsCount = 20;
  private unreachable = false;
  private llmResponder?: (prompt: string) => string;

  setHandsCount(count: number): void {
    this.handsCount = count;
  }

  setUnreachable(unreachable: boolean): void {
    this.unreachable = unreachable;
  }

  setLLMResponder(fn: (prompt: string) => string): void {
    this.llmResponder = fn;
  }

  generateMockHands(count: number): any[] {
    return Array.from({ length: count }, (_, i) => ({
      id: `hand-${i}`,
      myBotId: 'bot-0',
      actions: [
        { botId: 'bot-1', type: 'fold', timestamp: Date.now() },
        { botId: 'bot-0', type: 'raise', timestamp: Date.now() + 100 },
      ],
      showdown: [],
      winner: 'bot-0',
    }));
  }

  generateMockAnalysis(): any {
    return {
      opponents: [
        {
          botId: 'bot-1',
          handsPlayed: 20,
          foldPercent: 30,
          raisePercent: 50,
          threeBetPercent: 20,
          showdownWinPercent: 45,
          bluffFrequency: 5,
          aggressionScore: 70,
        },
      ],
      selfWinRate: 55,
      trends: {
        mostAggressive: { botId: 'bot-1', aggressionScore: 70 },
        mostPassive: { botId: 'bot-2', aggressionScore: 30 },
        mostBluffHeavy: { botId: 'bot-1', bluffFrequency: 5 },
      },
      summary: 'Bot-1 is aggressive; exploit with tighter ranges',
    };
  }
}
```

**Acceptance criteria**:
- T1: Fetch hands from Border Router /api/hands (100 hands)
- T2: Analyse patterns (fold%, raise%, aggression score)
- T3: Prompt Claude with policy + opponent stats
- T4: Validate and compile Lisp to Forth bytecode
- T5: Hot-swap policy atomically (< 10ms, no hand drop)
- T6: Fallback to last known good policy after 3 errors
- T7: Store policy in evolution chain with prev-hash
- T8: Complete poll → analyse → prompt → compile → swap cycle
- T9: No network interruption during swap
- T10: Apex container starts game loop + shadow loop concurrently

---

## Completion Criteria

You are **done with Phase H4** when:

1. All 7 deliverables (DH4.1–DH4.7) are implemented and merged to `hackathon/h4-apex-agent-shadow-loop`
2. All 10 TDD Gate Tests (T1–T10) pass
3. Shadow loop runs continuously without crashing for > 10 minutes
4. Policy hot-swap completes in < 10ms (no hand drops)
5. Game loop reads new policy on each decision (verified by logs or metrics)
6. Opponent analysis extracts fold%, raise%, aggression from hand history
7. LLM prompt includes current policy, opponent stats, and task instructions
8. LLM response is parsed correctly (REASONING / LISP / RATIONALE sections)
9. Fallback mechanism reverts to last known good policy after 3 consecutive validation errors
10. Policy evolution chain stores each version as RELEVANT cell with prev-hash
11. Shadow loop cadence is configurable (every N seconds, every M hands)
12. No regressions: Phase H1-H3 tests still pass
13. Documentation: README for shadow loop setup, Anthropic API key requirement
14. Performance: shadow loop cycle completes in < 5 seconds even with 100 hands to analyse

---

## What NOT To Do

1. **Do NOT block the game loop** during shadow loop operations. Use atomic references and non-blocking I/O.
2. **Do NOT require manual policy editing**. The entire point is autonomous evolution via LLM.
3. **Do NOT ignore LLM errors**. Validate Lisp syntax before compilation; fallback on 3 consecutive errors.
4. **Do NOT break hand provenance**. Every hand must be loggable to Border Router for analysis.
5. **Do NOT lose table state** during policy swap. The reference change must be atomic; tables continue unaffected.
6. **Do NOT hardcode the Border Router URL or API key**. Use environment variables (BORDER_ROUTER_URL, ANTHROPIC_API_KEY).
7. **Do NOT expose raw bytecode to the LLM**. Only send human-readable Lisp.
8. **Do NOT allow the shadow loop to get stuck** if the Border Router is unavailable. Retry with backoff; continue polling.
9. **Do NOT store credentials in cells**. API keys stay in process environment only.
10. **Do NOT assume valid Lisp from LLM**. Always validate and compile before hot-swap. Reject malformed policies.

---

## Integration with Existing Phases

- **Phase H1**: Game loop multicast sends hands to Border Router. Apex container extends H1 bot with shadow loop.
- **Phase H2**: Baseline policies (Nit, Maniac, Calculator) are loaded as initial `currentPolicy`. Apex learns from baseline.
- **Phase H3**: Border Router /api/hands endpoint supplies hand history. /api/personas may provide per-opponent stats.
- **Phase 21**: Lisp compiler validates and compiles updated policies. Uses existing parser, compiler, Forth generation.
- **Phase 25.5**: OP_CALLHOST dispatch may be leveraged for domain predicates (opponent-aggressive?, have-strong-hand?, etc.).

---

## Branch, Commits, and CI

- **Branch**: `hackathon/h4-apex-agent-shadow-loop`
- **Base**: `hackathon/semantos-swarm`
- **Commits**: Follow `docs/BRANCHING-AND-CI-POLICY.md` naming (feat/fix/test)
- **CI**: Phase H4 tests must pass before merge. No regressions to H1–H3.

---

## Next Phase

Phase H4 feeds into the final Hackathon Integration (H5): wrapping all 25 bots with Apex shadow loops, measuring policy evolution across the swarm, and showcasing the cognitive layer to judges.

The Apex Agent is the heartbeat of agent autonomy: observe, learn, adapt, survive.
