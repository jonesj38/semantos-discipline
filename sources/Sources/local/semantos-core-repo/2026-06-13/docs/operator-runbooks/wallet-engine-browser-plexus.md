---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/operator-runbooks/wallet-engine-browser-plexus.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.640624+00:00
---

# Wallet Engine Browser + Plexus Runbook

This is the v0.4 operator shape for the browser wallet. It makes the old
`wallet-engine.wasm` name real without introducing a second engine: the
artifact is the embedded cell engine built from `core/cell-engine`, copied
under both names for ergonomics.

## Build

```bash
cd apps/wallet-browser
bun install
bun run build
```

`bun run build` produces:

- `dist/cell-engine-embedded.wasm` — canonical embedded WASM artifact.
- `dist/wallet-engine.wasm` — byte-identical alias for BRAIN/operator config.
- `dist/index.html` — hidden bridge iframe.
- `dist/popup.html` — wallet UI, first-run creation, recovery, send, policy.
- `dist/signup.html` — redirects to `popup.html?intent=plexus-signup`.
- `dist/wallet-bridge.js` and `dist/wallet-popup.js`.

The alias exists so first-run BRAIN docs and operator conversations can say
"wallet engine" without making people hunt for `cell-engine-embedded.wasm`.
When hash-pinning in BRAIN, hash the exact file being configured.

## Browser Signup Flow

Host the `dist/` directory at the wallet origin, for example:

```text
https://wallet.semantos.example/bridge  -> index.html
https://wallet.semantos.example/popup   -> popup.html
https://wallet.semantos.example/signup  -> signup.html
```

The signup URL redirects to `popup.html?intent=plexus-signup`.

If no wallet exists, the popup opens the create screen. The user supplies:

- contact email,
- exactly three recovery challenge questions,
- each challenge answer twice,
- Tier-1 PIN,
- optional Tier-2 factor,
- optional Tier-3 vault factor.

`createWallet()` then:

- generates a local seed,
- derives identity and tier base keys,
- self-issues the identity cert id,
- creates the encrypted Plexus recovery envelope,
- persists that envelope locally,
- wipes the seed and raw challenge answers.

After creation, the signup intent lands on Status. Plexus enrollment is an
explicit opt-in action. If no operator is configured, Enroll/Recover render a
visible "not available yet" message and disable the forms. When an operator is
configured, the preferred enrollment path mirrors the already-created recovery
envelope with `enrollCachedEnvelope()`. That path does not require the seed or
plaintext challenge answers.

## Security Posture

Recovery envelope:

- Challenge answers never leave the device in plaintext.
- The envelope stores salted answer hashes.
- The recovery seed is AES-GCM encrypted under a PBKDF2 key derived from
  normalized challenge answers.
- The envelope is signed by the wallet identity key.
- Plexus receives ciphertext, public identity material, and answer hashes.

Tier 0:

- Tier 0 is intentionally unencumbered.
- It is for identity and tiny economic execution only.
- The plaintext-key exposure limit is `1_000_000` sats.
- Wallet status reports `tier0PlaintextExposure`.
- `planTier0Sweep()` returns a deterministic outpoint plan when unspent
  owned outputs exceed the limit.

The current patch prepares the sweep boundary. It does not yet construct or
broadcast the sweep transaction. The Chronicle/default-sighash transaction
builder should consume `planTier0Sweep()` and sweep selected outpoints into
the next tier before ordinary hot-key operation continues.

## BRAIN Mapping

BRAIN no longer needs a mandatory default module entry to boot. For a sovereign
wallet node that wants WASM wallet execution, configure the module explicitly:

```jsonc
{
  "shell": {
    "data_dir": "~/.semantos/data",
    "modules_dir": "~/.semantos/wasm"
  },
  "modules": {
    "wallet-engine": {
      "path": "wallet-engine.wasm",
      "sha256": "<brain hash ~/.semantos/wasm/wallet-engine.wasm>",
      "max_memory": "128MB"
    }
  }
}
```

That keeps first-run boot native-first while preserving the future WASM
sandbox boundary: hash-pinned module, brokered host imports, and audit log.
