---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/canonicalization/golden-slice/v1_release.fixture.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.591947+00:00
---

# tests/canonicalization/golden-slice/v1_release.fixture.json

```json
{
  "_meta": {
    "slice": "v1_release",
    "version": "0.1.0",
    "createdAt": "2026-05-27",
    "spec": "docs/canon/canonicalization-golden-slice.md",
    "purpose": "C7 acceptance fixture. Red on day 1; cell-by-cell goes green as canonicalization tracks land. No track may claim full ✓ without re-running tests against this fixture.",
    "deterministic": "Most fields are byte-deterministic given the utterance. Fields under _runtime are per-run (timestamps) or per-operator (owner_pubkey, signature). Tests assert structure on those, not exact values."
  },

  "_runtime": {
    "note": "Fields below are NOT byte-asserted — they're per-run or per-operator and only their shape is checked.",
    "cell_timestamp": "u64 unix-millis at sign time",
    "cell_owner_id": "16 bytes derived from hat:self pubkey (per-operator)",
    "cell_payload_total": "u32 = serialized payload length",
    "cell_domain_payload_root": "32-byte sha256 of canonical payload bytes",
    "wallet_signature": "64-byte secp256k1 sig (per-run, deterministic given key+hash)",
    "wallet_pubkey": "33-byte compressed secp256k1 pubkey (per-operator)",
    "brain_cell_id": "32-byte sha256 of full 1024-byte canonical cell (computed; matches PWA-computed cell-id)"
  },

  "layer1_voice": {
    "utterance_audio_source": "operator speaks into helm mic",
    "expected_transcript": "release: I'm letting go of the pressure to make every interaction perfect.",
    "stt_path": "brain upload via POST /api/v1/voice-extract (per Q1 decision; on-device whisper.cpp as future enhancement)",
    "acceptance": "transcript matches expected_transcript verbatim (modulo trailing punctuation/whitespace)"
  },

  "layer2_sir": {
    "input": "layer1_voice.expected_transcript",
    "expected": {
      "modal": "do",
      "who": "betterment",
      "what": "release",
      "why": null,
      "payload": {
        "rawText": "I'm letting go of the pressure to make every interaction perfect."
      }
    },
    "acceptance": "parser output JSON-equals expected (modal, who, what, payload.rawText). 'why' may be null or absent.",
    "parser_source": "monolith apps/semantos/lib/src/voice/sir_extractor.dart (forklifted to canonical PWA in C1)"
  },

  "layer3_oir": {
    "input": "layer2_sir.expected",
    "expected": {
      "verb": "do.new",
      "cellType": "betterment.practice.release",
      "cartridge": "betterment",
      "hat": "betterment",
      "payload": {
        "rawText": "I'm letting go of the pressure to make every interaction perfect."
      },
      "anchor": "optional"
    },
    "acceptance": "gradient pipeline output JSON-equals expected. Cartridge resolution looks up `self` from CartridgeRegistry, flow resolution maps trigger 'release' to cartridges/betterment/cartridge.json's daily-release flow.",
    "resolver_source": "monolith apps/semantos/lib/src/gradient/sir_to_oir.dart (forklifted to canonical PWA in C1)"
  },

  "layer4_opcode": {
    "input": "layer3_oir.expected",
    "expected_sequence": [
      {"op": "OP_NEW_CELL", "args": {"typehash_hex": "sha256('betterment.practice.release')"}},
      {"op": "OP_SET_FIELD", "args": {"name": "rawText", "value": "I'm letting go of the pressure to make every interaction perfect."}},
      {"op": "OP_SIGN", "args": {"hat": "betterment"}},
      {"op": "OP_PERSIST", "args": {}}
    ],
    "expected_byte_length": "deterministic given OIR; recorded once layer is wired",
    "acceptance": "opcode-encoder output matches the expected sequence (semantic equality on ops + args). Byte-equality asserted once encoder is stable.",
    "encoder_source": "monolith apps/semantos/lib/src/gradient/oir_to_bytes.dart (forklifted in C1)"
  },

  "layer5_cell": {
    "input": "layer4_opcode.expected_sequence",
    "expected_header": {
      "MAGIC": "16 bytes — per core/cell-engine/src/constants.zig",
      "LINEARITY": "LINEAR (betterment.practice.release is LINEAR per cartridges/betterment/cartridge.json)",
      "VERSION": 1,
      "TYPE_HASH": "32 bytes — sha256('betterment.practice.release')",
      "OWNER_ID": "_runtime.cell_owner_id (16 bytes)",
      "TIMESTAMP": "_runtime.cell_timestamp",
      "PAYLOAD_TOTAL": "_runtime.cell_payload_total",
      "PARENT_HASH": "32 bytes all-zero (root cell — no parent)",
      "PREV_STATE_HASH": "32 bytes all-zero (first state)",
      "DOMAIN_PAYLOAD_ROOT": "_runtime.cell_domain_payload_root"
    },
    "expected_payload": {
      "encoding": "canonical-encoded fields per cell-engine spec",
      "fields": {
        "rawText": "I'm letting go of the pressure to make every interaction perfect."
      }
    },
    "expected_total_bytes": 1024,
    "acceptance": "cell bytes total 1024; header fields match exactly except _runtime fields; payload encoding produces the rawText field at the right offset."
  },

  "layer6_wallet_sign": {
    "input": "sha256(layer5_cell bytes)",
    "expected": {
      "signature_length_bytes": 64,
      "pubkey_length_bytes": 33,
      "pubkey_compressed": true,
      "sig_algorithm": "secp256k1-ecdsa",
      "key_custody": "Android Keystore / iOS Keychain via semantos_shell_native_identity (per Q4 decision)",
      "wallet_module_source": "unified wallet (C6a) — collapses cartridges/wallet-headers + cartridges/shared/anchor/headless-wallet"
    },
    "acceptance": "signature verifies against (cell_hash, pubkey). Same wallet module callable from PWA's WalletService and brain's HTTP surface (the C6a unification proof)."
  },

  "layer7_brain_dispatch": {
    "_status": "CORRECTED 2026-06-04: the 2026-05-28 'VERIFIED GREEN' below was a FALSE POSITIVE (old monolith in the emulator — canonicalization-matrix C7-E). The real, current proof is the converted v1_release.{dart,zig} gate + the taped Level-1 (unsigned) and Level-2 (signed, operator-key-verified) runs on the canonical app. The request body below IS the accurate sovereign-mint wire (Option A: PWA signs the payload, brain verifies + assembles); the _live_proof block is retained only as a historical record of the false positive.",
    "request": {
      "method": "POST",
      "url": "https://oddjobtodd.info/api/v1/cells",
      "headers": {"Authorization": "Bearer <token>", "Content-Type": "application/json"},
      "body": {
        "typeHashHex": "06d0a049e88a982bada750e3f8464e9ea4d451ec23463726e3b0c44298fc1c14",
        "payload": {
          "rawText": "I'm letting go of the pressure to make every interaction perfect.",
          "source": "keyboard",
          "prompt": "freeform",
          "elevation": 5
        }
      }
    },
    "typeHash_computation": "buildTypeHash(s1, s2, s3, s4) per core/cell-engine/src/type_hash.zig — 4×8-byte segments, each = sha256(segment)[0..8]. For betterment.practice.release: triple={s1:'betterment', s2:'practice', s3:'release', s4:''}.",
    "payload_schema": "Per cartridges/betterment/cartridge.json betterment.practice.release cellType — REQUIRED fields: rawText, source (enum: voice|keyboard|photo), prompt (enum: I feel...|I release...|I am...|I choose...|freeform), elevation (number). Optional: journalImageRef, extractedSummary, valence, themes.",
    "expected_response": {
      "status": 200,
      "body_shape": {
        "cellId": "<64-hex sha256 over canonical cell bytes>",
        "cartridgeId": "betterment",
        "cellType": "betterment.practice.release",
        "persistedAt": "<unix-ms number>"
      }
    },
    "brain_handler_source": "runtime/semantos-brain/src/cells_mint_handler.zig + cells_mint_http.zig — GENERIC mint handler in brain core (BRAIN-GENERIC-MINT-VERB M3). HTTP route at POST /api/v1/cells per runtime/semantos-brain/src/site_server/reactor.zig. No self-specific handler required for the V1 slice — the C4 plan was wrong to assume one was needed.",
    "verified_retrieval": "GET /api/v1/cell/<cellId> returns the raw 1024-byte canonical cell with the payload at the appropriate offset. Round-trip works.",
    "acceptance": "brain returns 200 with cellId + cartridgeId='betterment' + cellType='betterment.practice.release' + persistedAt timestamp. Cell queryable via GET /api/v1/cell/<cellId>.",
    "_live_proof": {
      "minted_2026-05-28": {
        "request_payload": {"rawText":"I am letting go of the pressure to make every interaction perfect.","source":"keyboard","prompt":"freeform","elevation":5},
        "response": {"cellId":"2002206665f7e6f4cdc6c90b7b425fc4fba53b0589aa2ffd7560e923834f504a","cartridgeId":"betterment","cellType":"betterment.practice.release","persistedAt":1779920150423},
        "retrieval_confirmed": true,
        "retrieved_payload_substring": "rawText\":\"I am letting go of the pressure to make every interaction perfect.\",\"source\":\"keyboard\",\"prompt\":\"freeform\",\"elevation\":5"
      }
    }
  },

  "layer8_helm_render": {
    "input": "successful layer7 response",
    "expected_card": {
      "title": "Release",
      "title_source": "displayName field in cartridges/betterment/cartridge.json cellTypes['betterment.practice.release'].displayName",
      "snippet": "I'm letting go of the pressure to make every interactio…",
      "snippet_source": "first 80 chars of cell payload rawText field",
      "timestamp_iso": "ISO-8601 derived from _runtime.cell_timestamp",
      "icon": "from cartridges/betterment/cartridge.json (defaults to Icons.extension if not specified)"
    },
    "acceptance": "AttentionSurface query returns the new cell as one of its items; rendered card matches expected_card structure. Card appears within 500ms of layer7 success."
  },

  "layer9_optional_anchor": {
    "_note": "DEFERRED to V2 slice. With Q5 decision (default local-only), the V1 slice does NOT exercise chain anchoring. See docs/canon/canonicalization-golden-slice.md §2 layer 9 + §4."
  },

  "v1_slice_acceptance": {
    "definition": "layers 1-8 all pass. layer 9 deferred to v2_anchored fixture.",
    "rerun_rule": "no canonicalization track may claim ✓ on its C (tests) axis without re-running this test and reporting the result in its matrix cell note."
  }
}

```
