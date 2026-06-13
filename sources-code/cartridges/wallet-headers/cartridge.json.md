---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/cartridge.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.415899+00:00
---

# cartridges/wallet-headers/cartridge.json

```json
{
  "id": "wallet-headers",
  "name": "Wallet & Headers",
  "version": "0.1.0",
  "role": "infra",
  "description": "Infra cartridge: BSV wallet + PoW-verified headers + indexer-less BEEF SPV. Provides the canonical SpvVerifier the capability/license substrate (SW2 / cartridge-license / NL-1) consumes — retiring the SpvContext stub-debt. Wave Canonical-Cartridge CC1 (the keystone).",
  "provides": [
    "@semantos/protocol-types/ports#SpvVerifier"
  ],
  "consumes": {
    "StorageAdapter": "required — header store + output/UTXO store"
  },
  "_notes": {
    "spvVerifier": "brain/src/spv-verifier.ts HeadersSpvVerifier — BEEF parse (beef-codec) + BUMP merkle root checked against the headers half (PoW-verified trusted roots via header-spv.ts LocalChainTracker, injected as isTrustedRoot). Fail-closed.",
    "directory": "CC4-3: collapsed to cartridges/wallet-headers/ (brain/ holds the @semantos/wallet-browser package — SpvVerifier impl + BRC-100 + header/output stores). pnpm-workspace globs cartridges/*/brain. Infra cartridge: role=infra exempt from taxonomy/flows/prompts; no runtime <data_dir>/extensions/<id>/ install (build-time provided adapter)."
  }
}

```
