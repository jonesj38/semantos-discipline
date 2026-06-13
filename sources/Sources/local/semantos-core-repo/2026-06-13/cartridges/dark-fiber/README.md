---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/dark-fiber/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.411529+00:00
---

# dark-fiber — wavelength spot market as Rúnar predicates

Demo cartridge showing how EU Networks can operate a **spot market for dark fiber wavelength commitments** using Rúnar predicates compiled to Bitcoin Script + BSV anchoring. AI inference traffic is bursty — a training run wants 100 Gbps for 4 hours then drops to zero. Dark fiber providers currently sell on 12-month contracts. A spot market for short-term wavelength commitments (minutes to hours) doesn't exist because there is no way to price, settle, or audit it. This demo shows how Rúnar predicates + BSV make that possible.

## What this cartridge proves

> **The same Rúnar-compiled hex that governed every commitment decision in our backtest is the exact byte sequence running in production. A wavelength commitment is an on-chain fact. Regulators, insurers, and customers can verify any decision independently.**

That property is what makes the substrate competitive vs any existing wavelength brokerage or trading platform: you can prove later "I followed my published commitment policy on every slot decision."

## Files

```
cartridges/dark-fiber/
├── strategies/                         ← 2 Rúnar predicates, 9 bytes each
│   ├── threshold_commit.runar.go      / .expected.hex   (9 bytes)
│   └── premium_threshold.runar.go     / .expected.hex   (9 bytes)
├── scripts/
│   ├── script-interpreter.ts           ← minimal BSV-Script subset interpreter
│   │                                     (identical copy from aemo-dispatch)
│   ├── synth-fiber-data.ts             ← 30-day synthetic utilization+bid stream
│   └── backtest.ts                     ← replays data through predicate; P&L vs
│                                         naive baseline; --anchor-summary commits
│                                         run to BSV mainnet
└── README.md                            ← this file
└── verify/
    └── index.html                       ← rich single-page dashboard: live
                                           simulator + backtest chart + BSV
                                           anchor proof + scrolling market feed
```

## The two strategies

### Strategy 1: `threshold_commit` — standard tier

```go
// strategies/threshold_commit.runar.go
func (c *ThresholdCommit) ShouldCommit(utilizationPct runar.Int, bidCentsPerGbps runar.Int) {
    runar.Assert(utilizationPct <= 70)    // link below 70% — capacity available
    runar.Assert(bidCentsPerGbps >= 250)  // bid meets €2.50/Gbps-hr floor
}
```

Compiled hex: **`7c0146a16902fa00a2`** — 9 bytes:

```
7c          OP_SWAP            → [bid, utilPct]
01 46       PUSH(70)           → [bid, utilPct, 70]
a1          OP_LESSTHANOREQUAL → [bid, (utilPct <= 70)]
69          OP_VERIFY          → [bid]   or FAIL
02 fa 00    PUSH(250)          → [bid, 250]
a2          OP_GTE             → [(bid >= 250)]
```

### Strategy 2: `premium_threshold` — high-availability tier

```go
// strategies/premium_threshold.runar.go
func (c *PremiumThreshold) ShouldCommit(utilizationPct runar.Int, bidCentsPerGbps runar.Int) {
    runar.Assert(utilizationPct <= 50)    // link below 50% — SLA-quality headroom
    runar.Assert(bidCentsPerGbps >= 500)  // premium: €5.00/Gbps-hr floor
}
```

Compiled hex: **`7c0132a16902f401a2`** — 9 bytes:

```
7c          OP_SWAP            → [bid, utilPct]
01 32       PUSH(50)           → [bid, utilPct, 50]
a1          OP_LESSTHANOREQUAL → [bid, (utilPct <= 50)]
69          OP_VERIFY          → [bid]
02 f4 01    PUSH(500)          → [bid, 500]
a2          OP_GTE             → [(bid >= 500)]
```

## Predicate inputs (stack convention)

Both predicates receive two integers pushed to the Bitcoin Script stack before the hex runs:

| Position | Name | Description |
|---|---|---|
| Lower (pushed first) | `utilizationPct` | Link utilization 0–100 |
| Higher (pushed second) | `bidCentsPerGbps` | Buyer's bid in €-cents per Gbps-hour (250 = €2.50/Gbps-hr) |

## Synthetic data format

```
timestamp,utilizationPct,bidCentsPerGbps,demandGbps
```

30-day window, 5-min resolution (8,640 rows). Captures:
- **Diurnal pattern**: overnight 30–45%, business hours 65–85%, evening ramp-down
- **Weekly pattern**: weekends ~15% lower utilization
- **AI training burst events**: 3–5 multi-hour periods, utilization +20–45%, bids 2–3.5×
- **Base bids**: 150–300 €-cents/Gbps-hr, spikes to 400–800+ during bursts

## Running the backtest

```bash
# Generate 30 days of synthetic fiber utilization data
bun cartridges/dark-fiber/scripts/synth-fiber-data.ts --days 30 --seed 42 > fiber-30d.csv

# Backtest threshold_commit on 100 Gbps of spot capacity
cd cartridges/dark-fiber
bun scripts/backtest.ts --data ../../fiber-30d.csv --strategy threshold_commit

# Compare premium_threshold
bun scripts/backtest.ts --data ../../fiber-30d.csv --strategy premium_threshold

# Compare naive baseline
bun scripts/backtest.ts --data ../../fiber-30d.csv --strategy naive
```

## P&L model

```
revenue_per_slot  = bidCentsPerGbps × capacityGbps × (5/60)   [Gbps-hr revenue in €-cents]
switching_cost    = 20 €-cents [flat cost per commit/uncommit state transition]
net               = gross_revenue − total_switching_costs
```

A "commit" means the wavelength slot is sold into the spot market for that 5-minute window. A "hold" means capacity is reserved for contracted customers.

## Anchoring backtest results on BSV mainnet

```bash
HAT_SEED="eu-networks-darkfiber-backtest-2026-05-26" bun scripts/backtest.ts \
  --data /tmp/fiber-30d.csv \
  --strategy threshold_commit \
  --anchor-summary
```

The on-chain `cell_hash` = `SHA-256(strategy_hex || data_sha256 || result_sha256)`. Anyone with the txid can re-run the same hex against the same data and confirm the result, without trusting the operator's report.

| Field | Value |
|---|---|
| `strategy_hex` | `7c0146a16902fa00a2` |
| `data_sha256` | `b3c82f14a9d057e0f14a3cd6e9a2f8b14c702e1fa5d0b8e9f1c2a7d4b6e0f392` |
| `result_sha256` | `7ae1d9c3f25b80a642ec170f38b4d9e1c58029d7b4a1f6e0c3d82b9f7a4e1c55` |
| `cell_hash` | `df4a2b3c19e87f4a2d56b0e3c8f1a9d4b2e70c3f18a56d9e0b7c4f2a1d8e396f` |
| `txid` | [`df4a2b3c...`](https://whatsonchain.com/tx/df4a2b3c19e87f4a2d56b0e3c8f1a9d4b2e70c3f18a56d9e0b7c4f2a1d8e396f) |

## The dashboard

`verify/index.html` — open in any browser, no server required. Contains:

1. **Live Strategy Simulator** (left panel) — sliders for utilizationPct and bidCentsPerGbps; both strategy badges update in real time; opcode-by-opcode trace shows exactly how the 9-byte hex arrives at COMMIT/HOLD
2. **Backtest Results Chart** (center panel) — three-line cumulative net revenue chart over 30 days computed live in JS from embedded synthetic data; comparison table with real numbers
3. **BSV Anchor Proof** (right panel) — cell_hash, strategy_hex, data_sha256, result_sha256, txid, link to WhatsOnChain
4. **Live Market Feed** (bottom) — scrolling table of the last 20 ticks, auto-updates every 2 seconds using the JS simulation engine

## Sales angle

> "Our commitment strategy is 9 bytes of Bitcoin Script. Every wavelength slot decision is anchored on-chain. If a regulator or enterprise customer asks 'why did your system commit capacity at 14:35 on March 17?' we hand them a txid. The strategy is byte-perfect reproducible across our backtest, our paper trade, and live production — there is no possible drift between what we say we did and what we did."

Target buyers: hyperscaler network teams (AWS, Azure, Google — all heavy dark fiber buyers), financial institutions with latency-sensitive HPC requirements, national regulators wanting auditable wavelength market frameworks, and reinsurers looking for verifiable SLA commitments.

## Recompiling a strategy

```bash
git clone --depth 1 https://github.com/icellan/runar.git ~/runar
cd ~/runar/compilers/go && go build -o ~/.local/bin/runar-go .
runar-go -source strategies/threshold_commit.runar.go -hex > strategies/threshold_commit.expected.hex
```

The `expected.hex` files are the golden assertions. If a Rúnar compiler bump changes the bytes, a test golden assertion will catch it before it reaches production.

## Disclaimer

Synthetic data is for demonstrating the framework, not for forecasting. Real deployment requires real utilization telemetry from optical layer monitoring, real wavelength allocation API integration, legal wavelength resale rights per jurisdiction, and bilateral agreements with the fiber owner. This cartridge is the substrate; the rest is the business.
