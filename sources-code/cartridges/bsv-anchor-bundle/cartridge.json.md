---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/cartridge.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.412235+00:00
---

# cartridges/bsv-anchor-bundle/cartridge.json

```json
{
  "id": "bsv-anchor-bundle",
  "name": "BSV Anchor Bundle",
  "version": "0.0.1",
  "role": "infra",
  "description": "BSV anchor backend cartridge — implements Phase 26C AnchorAdapter using BSV as the timestamping + verification chain. Substrate-exposing infra cartridge.",
  "taxonomyPath": "brain/src/taxonomy.json",
  "flowsDir": "brain/src/flows",
  "promptsDir": "brain/src/prompts",
  "objectTypesDir": "brain/src/object-types",
  "capabilitiesPath": "brain/src/capabilities.ts",
  "provides": [
    "@semantos/protocol-types/anchor"
  ],
  "wssSubprotocols": [
    {
      "name": "wallet.v1",
      "handlerPath": "brain/zig/src/wss_wallet_reactor.zig",
      "capability_required": "cap.bsv-anchor.wallet.sign"
    }
  ],
  "verbs": [
    { "name": "anchor.write", "capability_required": "cap.bsv-anchor.write" },
    { "name": "anchor.read", "capability_required": "cap.bsv-anchor.read" },
    {
      "name": "wallet.sign",
      "capability_required": "cap.bsv-anchor.wallet.sign",
      "deprecated": true,
      "deprecatedNote": "PR-C11-7e: substrate flips to cells-only (LINEAR-CELL-SPV-STATE.md §10). Verb retires in PR-C11-7g once cells provide the signing-callback path via `bsv.tx.sign.request`/`response`."
    },
    {
      "name": "wallet.derive",
      "capability_required": "cap.bsv-anchor.wallet.derive",
      "deprecated": true,
      "deprecatedNote": "PR-C11-7e: superseded by Dart-side `WalletKeyService.deriveReceive` + cell-engine host calls. Retires in PR-C11-7g."
    },
    {
      "name": "payment.verify",
      "capability_required": "cap.bsv-anchor.payment.verify",
      "deprecated": true,
      "deprecatedNote": "PR-C11-7e: superseded by the `bsv.spv.verify.intent` / `bsv.spv.verify.result` cell pair declared below. The cell path invokes the same `core/cell-engine/src/beef.zig::verifyBeefSpv` primitive via the host call bound in PR-C11-7d. Verb retires in PR-C11-7g."
    },
    {
      "name": "payment.refund",
      "capability_required": "cap.bsv-anchor.payment.refund",
      "deprecated": true,
      "deprecatedNote": "PR-C11-7e: refund is a linear-cell state transition (`bsv.linear.anchor → bsv.linear.anchor`); refund-specific verb is unnecessary substrate. Retires in PR-C11-7g."
    },
    { "name": "headers.sync", "capability_required": "cap.bsv-anchor.headers.sync" },
    { "name": "headers.serve", "capability_required": "cap.bsv-anchor.headers.serve" }
  ],
  "cellTypes": [
    {
      "name": "bsv.spv.verify.intent",
      "triple": {
        "segment1": "bsv",
        "segment2": "spv",
        "segment3": "verify",
        "segment4": "intent"
      },
      "linearity": "EPHEMERAL",
      "description": "Dart → engine. Request SPV verification of a BEEF against the brain's trusted-roots set. Payload carries (txid, inline BEEF) per `core/protocol-types/src/bsv/spv-verify.ts`. The script-handler (declared below) invokes `host_verify_beef_spv` (PR-7a) and returns truthy iff the BEEF verified against a trusted root.",
      "handler": {
        "script": "510120cc6b14686f73745f7665726966795f626565665f737076d076020001977c020001966b6b530020136523b9fea2b732db1b9104389b7cc6a12dd3a7fd3203a4f6a214f7a5fcda0c1000000000000000000000000000000000ca5100d16c51d16c0122d16c52d1",
        "scriptHash": "21f832c1923558780c85a1608d14a025a9b46f7bca2ab1facf0bf7a6d42232fc",
        "capabilities": ["cap.bsv.beef.verify"],
        "emits": ["bsv.spv.verify.result"],
        "opcountBudget": 1000
      }
    },
    {
      "name": "bsv.spv.verify.result",
      "triple": {
        "segment1": "bsv",
        "segment2": "spv",
        "segment3": "verify",
        "segment4": "result"
      },
      "linearity": "EPHEMERAL",
      "description": "Engine → Dart. Result of an SPV verification — `{outcome: invalid|valid|error, txid, errorTag}` echoing the intent's txid for correlation. Payload per `core/protocol-types/src/bsv/spv-verify.ts`."
    },
    {
      "name": "bsv.linear.anchor",
      "triple": {
        "segment1": "bsv",
        "segment2": "linear",
        "segment3": "anchor",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "description": "Substrate state record binding a piece of application state to a single 1-sat BSV UTXO. Carries `(anchor UTXO ref, payload hash, leafPk, status, beefHead)`. State transitions consume the old anchor + mint a new one with the new payload hash committed to via OP_PUSHDROP. Wire format ships in PR-C11-7e-3."
    },
    {
      "name": "bsv.linear.status",
      "triple": {
        "segment1": "bsv",
        "segment2": "linear",
        "segment3": "status",
        "segment4": ""
      },
      "linearity": "EPHEMERAL",
      "description": "Engine-emitted notice that a linear cell's status changed (pending → confirmed, confirmed → spent, reorg → failed). Drives the renderer's UTXOs panel refresh. Wire format ships in PR-C11-7e-3."
    },
    {
      "name": "bsv.beef.carriage.head",
      "triple": {
        "segment1": "bsv",
        "segment2": "beef",
        "segment3": "carriage",
        "segment4": "head"
      },
      "linearity": "PERSISTENT",
      "description": "First chunk of a BEEF that exceeds the 1024-byte cell payload budget. Carries `(total_len, successor_hash, payload_chunk[0])`. The intent or anchor cell that needs the BEEF references this head's hash; the engine reassembles via `head → body → body → ... → terminal`. Chunking algorithm in LINEAR-CELL-SPV-STATE.md §5; wire format ships in PR-C11-7e-3."
    },
    {
      "name": "bsv.beef.carriage.body",
      "triple": {
        "segment1": "bsv",
        "segment2": "beef",
        "segment3": "carriage",
        "segment4": "body"
      },
      "linearity": "PERSISTENT",
      "description": "Subsequent chunk of a BEEF carriage chain. Carries `(successor_hash, payload_chunk[i])`. Terminal body has a zero successor_hash. Wire format ships in PR-C11-7e-3."
    },
    {
      "name": "bsv.tx.partial.shell",
      "triple": {
        "segment1": "bsv",
        "segment2": "tx",
        "segment3": "partial",
        "segment4": "shell"
      },
      "linearity": "LINEAR",
      "description": "PR-6 / LOCKSCRIPT-CLEAVAGE.md §6.3. LINEAR shell that accumulates partial-tx state — expected counterparties (hash160 list) + recorded contributions (party_index + contribution_hash) + lifecycle status (Active|BroadcastPending|Finalised|Cancelled). One-shot destructor: consumed by either a `bsv.tx.assemble.intent` (broadcast path) or transitions to status=Cancelled via a `bsv.tx.partial.cancel`. Wire format: `core/protocol-types/src/bsv/tx-partial.ts::encodePartialShell`."
    },
    {
      "name": "bsv.tx.partial.contribution",
      "triple": {
        "segment1": "bsv",
        "segment2": "tx",
        "segment3": "partial",
        "segment4": "contribution"
      },
      "linearity": "EPHEMERAL",
      "description": "PR-6 / LOCKSCRIPT-CLEAVAGE.md §6.3. One counterparty's signed input/output contribution to an active shell. Single-shot — replay-resistant via EPHEMERAL linearity (§6.1). Carries (shell_cell_hash, party_index, contributor_pubkey, signature). Wire format: `core/protocol-types/src/bsv/tx-partial.ts::encodePartialContribution`."
    },
    {
      "name": "bsv.tx.partial.assemble",
      "triple": {
        "segment1": "bsv",
        "segment2": "tx",
        "segment3": "partial",
        "segment4": "assemble"
      },
      "linearity": "EPHEMERAL",
      "description": "PR-6 / LOCKSCRIPT-CLEAVAGE.md §6.3. Cartridge-side trigger: 'all sigs collected, finalize this shell.' Substrate handler verifies completeness, emits `bsv.tx.assemble.intent` to the broker, and transitions the shell to status=BroadcastPending. Wire format: `core/protocol-types/src/bsv/tx-partial.ts::encodePartialAssemble`."
    },
    {
      "name": "bsv.tx.partial.cancel",
      "triple": {
        "segment1": "bsv",
        "segment2": "tx",
        "segment3": "partial",
        "segment4": "cancel"
      },
      "linearity": "EPHEMERAL",
      "description": "PR-6 / LOCKSCRIPT-CLEAVAGE.md §6.3. Abort the workflow. Substrate handler transitions the shell to status=Cancelled — terminal, no successor cell. Carries (shell_cell_hash, reason). Wire format: `core/protocol-types/src/bsv/tx-partial.ts::encodePartialCancel`."
    },
    {
      "name": "bsv.tx.sign.request",
      "triple": {
        "segment1": "bsv",
        "segment2": "tx",
        "segment3": "sign",
        "segment4": "request"
      },
      "linearity": "EPHEMERAL",
      "description": "PR-6 / LOCKSCRIPT-CLEAVAGE.md §3.5 + §4c. Substrate → wallet. Carries a 32-byte sighash digest + derivation context (recipe_id, input_index, sighash_flags). The wallet NEVER sees the handler script — only the digest, which has already committed to scope via SIGHASH flags. This is the cleavage invariant in cell form. Wire format: `core/protocol-types/src/bsv/tx-sign.ts::encodeTxSignRequest`."
    },
    {
      "name": "bsv.tx.sign.response",
      "triple": {
        "segment1": "bsv",
        "segment2": "tx",
        "segment3": "sign",
        "segment4": "response"
      },
      "linearity": "EPHEMERAL",
      "description": "PR-6 / LOCKSCRIPT-CLEAVAGE.md §3.5. Wallet → substrate. Carries the DER-encoded ECDSA signature with the trailing sighash-flag byte (BSV convention). References the request cell-hash for correlation. Wire format: `core/protocol-types/src/bsv/tx-sign.ts::encodeTxSignResponse`."
    },
    {
      "name": "bsv.tx.derivation.recipe",
      "triple": {
        "segment1": "bsv",
        "segment2": "tx",
        "segment3": "derivation",
        "segment4": "recipe"
      },
      "linearity": "PERSISTENT",
      "description": "PR-9c. BRC-42 / BRC-43 key-material derivation schema as a substrate cell. Carries (securityLevel, counterparty, protocolName, keyID) — the inputs BRC-43's invoice-number derivation expects. Content-addressable + reusable: a single recipe cell binds many output UTXOs to the same derivation; recovery requires only the seed + this recipe's cell-hash. The bsv.tx.sign.request payload's recipe_id field at offset 33 carries the cell-hash of a DerivationRecipe so the wallet can resolve the derivation context + derive the right leaf key. Distinct from SpendPolicy (brain-side on-chain enforcement dispatch — sighash flag + structural predicate + grind surface; see runtime/semantos-brain/src/spend_policy.zig). PR-9 v2 split these two concepts after they were briefly conflated in PR-9 v1. Wire format: `core/protocol-types/src/bsv/derivation-recipe.ts::encodeDerivationRecipe`."
    },
    {
      "name": "bsv.tx.assemble.intent",
      "triple": {
        "segment1": "bsv",
        "segment2": "tx",
        "segment3": "assemble",
        "segment4": "intent"
      },
      "linearity": "EPHEMERAL",
      "description": "PR-6 / LOCKSCRIPT-CLEAVAGE.md §8.3. Broker's 'assemble and broadcast' trigger. Consumes a `bsv.tx.partial.shell` (via the substrate handler chain) and emits a `bsv.tx.broadcast.intent` carrying the serialized tx bytes (built via `host_assemble_tx`, cap.tx.build). Wire format: `core/protocol-types/src/bsv/tx-broadcast.ts::encodeTxAssembleIntent`."
    },
    {
      "name": "bsv.tx.broadcast.intent",
      "triple": {
        "segment1": "bsv",
        "segment2": "tx",
        "segment3": "broadcast",
        "segment4": "intent"
      },
      "linearity": "EPHEMERAL",
      "description": "PR-6 / LOCKSCRIPT-CLEAVAGE.md §8.3. Raw serialized BSV transaction bytes for ARC. Inline-only in v1 (cap = ~940 bytes; carriage chain for larger txs in a later PR). Wire format: `core/protocol-types/src/bsv/tx-broadcast.ts::encodeTxBroadcastIntent`."
    },
    {
      "name": "bsv.tx.broadcast.result",
      "triple": {
        "segment1": "bsv",
        "segment2": "tx",
        "segment3": "broadcast",
        "segment4": "result"
      },
      "linearity": "EPHEMERAL",
      "description": "PR-6 / LOCKSCRIPT-CLEAVAGE.md §8.3. ARC's response, carried back as a cell: { outcome (Rejected|Accepted|Error), txid (echoed for correlation), arc_status (None..Mined|Rejected), confirmations (u32) }. Wire format: `core/protocol-types/src/bsv/tx-broadcast.ts::encodeTxBroadcastResult`."
    }
  ],
  "consumes": {
    "StorageAdapter": "required — for output-store + derivation-state + header storage",
    "IdentityAdapter": "required — for BRC-42 derivation under operator's identity cert",
    "wssSubprotocolRegistry": "required — registers wallet.v1 against the substrate WSS transport"
  },
  "_notes": {
    "scaffold_only": "This manifest declares the cartridge boundaries. Real implementation arrives via DLBA.2 (wallet) + DLBA.3 (payment) + DLBA.4 (headers) + DLBA.5 (fallback wiring). See docs/prd/D-LIFT-BSV-ANCHOR.md.",
    "capability_page": "Domain-flag page allocation TBD — see brain/src/capabilities.ts for the canonical assignment scheme inheriting from the page-aligned model in cartridges/oddjobz/brain/src/capabilities.ts.",
    "manifest_format": "Phase 36A ExtensionManifest (cartridge.json) shape per core/protocol-types/src/extension-manifest.ts. role=infra ⇒ exempt from taxonomy/flows/prompts (declared anyway, scaffold). CC4-4: collapsed to cartridges/bsv-anchor-bundle/; runtime <data_dir>/extensions/<id>/ install convention preserved (source-tree-only).",
    "substrate_cells_only": "C11 PR-C11-7c locked the substrate to cells-only (LINEAR-CELL-SPV-STATE.md). PR-C11-7e (this commit) added the cellTypes[] catalog and marked the superseded wallet/payment verbs as deprecated. The verbs stay callable through the 7e→7f→7g transition so callers don't break mid-flip. PR-C11-7g retires them once the cell path is proven end-to-end via the BRC-29 internalize flow. The vault layers above the substrate keep their own security parameters and can have non-cell entry points; this cartridge is the substrate, so cells-only here."
  }
}

```
