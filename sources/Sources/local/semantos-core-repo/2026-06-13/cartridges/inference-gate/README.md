---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.407513+00:00
---

# inference-gate — access control for AI inference as Rúnar predicates

Demo cartridge: a Rúnar-governed access gate for enterprise GPU inference workloads. Every access decision is a Bitcoin Script predicate execution. Every decision is anchored individually on-chain. An auditor gets a txid list for any date range — every access event, byte-perfect reproducible, no gaps.

## The pitch

Enterprises send sensitive data (patient records, IP, financial models) to GPU providers for AI inference. The killer problem: there is no way to prove the GPU provider didn't read the data, and there is no audit trail of access decisions. GDPR fines are paid not because data leaked, but because you cannot prove it didn't.

> **"Our access control policy is 7 bytes of Bitcoin Script. Every access decision is anchored on-chain with a txid. When regulators ask 'who accessed patient record X on August 17?' we hand them a txid, not a log file that could have been edited."**

## What this cartridge proves

> The same Rúnar-compiled hex you backtest against synthetic access-request data is the EXACT byte sequence the brain would run in production via PolicyRuntime.evaluateReal. There is no port. There is no drift. The policy IS the bytes.

That property is what makes the substrate competitive vs every access-control framework on the market: you can prove, after the fact, that every access decision followed your published policy — byte for byte.

## Files

```
cartridges/inference-gate/
├── strategies/
│   ├── cert_gate.runar.go          / .expected.hex  (7 bytes)
│   └── enterprise_gate.runar.go    / .expected.hex  (7 bytes)
├── scripts/
│   ├── script-interpreter.ts       ← minimal BSV-Script subset interpreter
│   │                                 (identical copy from aemo-dispatch)
│   ├── synth-access-data.ts        ← synthetic 7-day access-request stream
│   └── backtest.ts                 ← replays access log through predicate;
│                                     counts allowed/denied/prevented breaches;
│                                     --anchor-summary commits run to BSV
└── verify/
    └── index.html                  ← live dashboard (no external deps except Chart.js CDN)
```

## The two strategies

Both predicates receive two integer inputs pushed to the Bitcoin Script stack before the hex runs:

| Input | Label | Meaning |
|---|---|---|
| A (pushed first, lower) | `certTier` | Identity clearance: 0=none, 1=basic, 2=enterprise, 3=sovereign |
| B (pushed second, top) | `dataClass` | Data classification: 0=public, 1=internal, 2=confidential, 3=restricted |

### `cert_gate` — 7 bytes: `7c760101a269a2`

Allow if `certTier >= 1` AND `certTier >= dataClass`.

```
7c          OP_SWAP  → [dataClass, certTier]
76          OP_DUP   → [dataClass, certTier, certTier]
01 01       PUSH(1)  → [dataClass, certTier, certTier, 1]
a2          OP_GTE   → [dataClass, certTier, (certTier >= 1)]
69          OP_VERIFY→ [dataClass, certTier]   or FAIL
a2          OP_GTE   → [(certTier >= dataClass)]
```

Blocks anonymous/bots. Allows basic-tier users to access internal data. The baseline policy for most workloads.

### `enterprise_gate` — 7 bytes: `7c760102a269a2`

Allow if `certTier >= 2` AND `certTier >= dataClass`.

```
7c          OP_SWAP  → [dataClass, certTier]
76          OP_DUP   → [dataClass, certTier, certTier]
01 02       PUSH(2)  → [dataClass, certTier, certTier, 2]
a2          OP_GTE   → [dataClass, certTier, (certTier >= 2)]
69          OP_VERIFY→ [dataClass, certTier]   or FAIL
a2          OP_GTE   → [(certTier >= dataClass)]
```

Requires enterprise-tier minimum. Blocks basic-tier (1) users from everything — even internal (class 1) data. One byte different from `cert_gate` (`0x01` → `0x02`). That one byte IS the policy decision; it is the thing that appears on-chain.

## Running the backtest

```bash
# Generate 7 days of synthetic access requests
bun cartridges/inference-gate/scripts/synth-access-data.ts --days 7 --seed 42 > /tmp/access.csv

# Backtest cert_gate
bun cartridges/inference-gate/scripts/backtest.ts \
  --data /tmp/access.csv --strategy cert_gate

# Compare enterprise_gate
bun cartridges/inference-gate/scripts/backtest.ts \
  --data /tmp/access.csv --strategy enterprise_gate

# Anchor the result on BSV mainnet
HAT_SEED="todd-inference-gate-2026-05-26" \
  bun cartridges/inference-gate/scripts/backtest.ts \
  --data /tmp/access.csv --strategy cert_gate --anchor-summary
```

## Anchoring format

`cell_hash = SHA-256(strategy_hex || data_sha256 || result_sha256)` — same construction as `aemo-dispatch`. Anyone can re-run the same 7-byte Bitcoin Script against the same access log, hash the result, and confirm the txid was paid for a run that matches.

`type_hash = SHA-256("inference-gate.backtest.v1")` — stable cell type for wallet recognition.

## Policy comparison (7-day synthetic run, ~2100 requests)

| Strategy | Bytes | Allow rate | Prevented breaches | Notes |
|---|---|---|---|---|
| `cert_gate` | 7 | ~62% | varies | basic-tier users can access internal |
| `enterprise_gate` | 7 | ~45% | higher count | stricter floor; blocks basic→internal |

`enterprise_gate` catches more access attempts by under-cleared identities. The cost: some legitimate tier-1 users are blocked from internal data. That trade-off is encoded in 7 bytes and published on-chain. No ambiguity about what policy ran.

## Sales angle

Target buyers: enterprise AI infrastructure operators, regulated-sector GPU cloud providers, compliance teams under GDPR Article 30 (records of processing activities).

> "Every access decision is on-chain. When regulators or insurers ask 'what governed access to this dataset?' — we hand them a txid and a 7-byte Bitcoin Script. The policy is self-verifying. There is no log file to falsify."

## Disclaimer

Synthetic data is for testing the framework, not for forecasting. Real deployment requires: production identity certificate issuance (BRC-52 cert tier verification), real data classification tagging at ingestion, integration with GPU provider's access-control hook, and GDPR-compliant data-subject record linkage.

---

## Layer Collapse: Cell request/response loop

The inference-gate cartridge has been extended with a live cell-based inference pipeline
that works alongside the policy backtest above. This layer runs on the Skyminer mesh.

### Architecture

```
Device (mic/camera/sensor)
  │  audio/image → whisper.cpp / local model
  │  text → inference.request.classify cell
  ▼
Relay (:5199)  —  routes by typeHash tier=inference (200 sats/cell, highest priority)
  ▼
cell-handler.ts (:5196)  —  subscribes to relay SSE
  │  mock: keyword classifier (no dependencies)
  │  real: WHISPER_URL → whisper.cpp REST  OR  OLLAMA_URL → Ollama
  ▼
inference.result.response cell  →  relay  →  dashboard + any subscriber
  ▼
CashLanes settlement (every 50MB)  →  PushDrop anchor txid on BSV mainnet
```

### Quick start (laptop, mock inference)

```bash
# 1. Start the demo stack
bash cartridges/shared/demo/start-demo.sh

# 2. In another terminal — send a test inference request:
bun cartridges/inference-gate/infer-client.ts "hard hat missing in zone 3"
# → ⚠️  Safety event detected (2 indicators) — 75% confidence  [~310ms round-trip]

bun cartridges/inference-gate/infer-client.ts --loop 10  # 10 random prompts
```

### Pi deployment (whisper.cpp ASR on real hardware)

```bash
# Deploy whisper.cpp + cell-handler to all reachable Pis
RELAY_URL=http://192.168.0.50:5199 bash cartridges/inference-gate/deploy-model-to-pis.sh

# Model build takes ~12 min on H5 ARM — monitor:
ssh todriguez@192.168.0.3 'tail -f /tmp/whisper-build.log'

# Once whisper-cpp.service is active on a Pi, test it:
curl -F file=@test.wav http://192.168.0.3:8080/inference

# Start mic-to-cell on the Pi (continuous capture → transcribe → cell):
bun cartridges/inference-gate/mic-to-cell.ts
```

### Upgrading the laptop handler to whisper.cpp

```bash
# Point the handler at a Pi running whisper.cpp:
WHISPER_URL=http://192.168.0.3:8080 bash cartridges/shared/demo/start-demo.sh

# Or upgrade to Ollama (LLM):
OLLAMA_URL=http://localhost:11434 bash cartridges/shared/demo/start-demo.sh
```

### Files

| File | Description |
|---|---|
| `cell-handler.ts` | HTTP :5196 — inference request handler (mock/whisper/ollama) |
| `infer-client.ts` | Demo client — send a text prompt, receive classified result |
| `mic-to-cell.ts` | Pi mic capture → whisper transcription → inference cell |
| `deploy-model-to-pis.sh` | Deploy whisper.cpp + handler to all Pis over SSH |
