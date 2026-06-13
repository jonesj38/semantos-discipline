---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/ScriptBroadcastCleavage.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.349435+00:00
---

# proofs/tla/ScriptBroadcastCleavage.cfg

```cfg
\* TLC configuration for ScriptBroadcastCleavage.
\* Small-model parameters per the spec's "Notes for the model checker"
\* section. Updated 2026-05-31 for BSV v1.2.0 Chronicle. Sized to fit
\* in TLC's default working-set bound (1M elements per constructed
\* set) — straddles the Chronicle cleavage boundary so every
\* IsConsensusValidByte branch fires.

CONSTANTS
    OpcodeBytes    = {81, 182, 208}
    \* 0x51 (OP_1)            — standard
    \* 0xb6 (OP_LSHIFTNUM)    — consensus (Chronicle exemption)
    \* 0xd0 (OP_CALLHOST)     — semantos (must trigger cleavage rejection)
    \* Three bytes covering the three IsConsensusValidByte branches:
    \* < 0xB0 (standard), = 0xB6/0xB7 (Chronicle), >= 0xB0 not exempt
    \* (semantos). Minimal but coverage-complete.

    ContentHashes  = {"h1", "h2"}
    Parties        = {"alice", "bob"}
    WorkflowIds    = {"wf1"}
    SighashFlags   = {"ALL_FORKID", "ALL_CHRONICLE"}
    \* One BIP-143 + one OTDA flag to exercise dual dispatch.

SPECIFICATION Spec

INVARIANTS
    Safety
    NoSemantosBytesInAnySignedDigest
    LinearityOneShot
    PartialShellMonotonic
    AllBroadcastTxsConsensusValid

```
