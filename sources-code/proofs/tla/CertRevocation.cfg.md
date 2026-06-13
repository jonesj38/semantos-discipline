---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/CertRevocation.cfg
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.342912+00:00
---

# proofs/tla/CertRevocation.cfg

```cfg
SPECIFICATION Spec

CONSTANTS
    NULL = NULL
    Certs = {c1, c2, c3}
    Revokers = {r1, r2}

CONSTRAINT Constraint

INVARIANTS
    RevokedStaysRevoked
    RevocationHasProof
    UnrevokedIsClean

```
