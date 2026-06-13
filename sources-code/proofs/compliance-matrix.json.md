---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/compliance-matrix.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.313924+00:00
---

# proofs/compliance-matrix.json

```json
[
  {
    "id": "1.1.1",
    "framework": "IEC 62443",
    "title": "Component integrity verification",
    "kernelInvariants": ["K1", "K7"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/LinearityK1.lean"},
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/CellImmutabilityK7.lean"},
      {"type": "zig-conformance", "file": "packages/cell-engine/tests/linearity_conformance.zig"},
      {"type": "fuzz", "file": "packages/cell-engine/fuzz/linearity_fuzz.zig"}
    ],
    "additionalAssumptions": ["SHA-256 collision resistance"],
    "status": "supported"
  },
  {
    "id": "1.1.2",
    "framework": "IEC 62443",
    "title": "Software binary authentication",
    "kernelInvariants": ["K7"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/CellImmutabilityK7.lean"},
      {"type": "wasm-manifest", "file": "packages/cell-engine/WASM-MANIFEST.json"},
      {"type": "build-script", "file": "packages/cell-engine/scripts/reproducible-build.sh"}
    ],
    "additionalAssumptions": ["SHA-256 collision resistance", "BSV chain availability"],
    "status": "supported"
  },
  {
    "id": "1.2.1",
    "framework": "IEC 62443",
    "title": "Communication integrity protection",
    "kernelInvariants": ["K6"],
    "proofArtifacts": [
      {"type": "tla-property", "file": "proofs/tla/EvidenceChain.tla"}
    ],
    "additionalAssumptions": ["SHA-256 collision resistance", "HMAC-SHA-256 PRF security"],
    "status": "supported"
  },
  {
    "id": "1.3.1",
    "framework": "IEC 62443",
    "title": "System availability under attack",
    "kernelInvariants": ["K5"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/TerminationK5.lean"},
      {"type": "zig-conformance", "file": "packages/cell-engine/tests/executor_conformance.zig"},
      {"type": "fuzz", "file": "packages/cell-engine/fuzz/stack_bounds_fuzz.zig"}
    ],
    "additionalAssumptions": [],
    "status": "supported"
  },
  {
    "id": "2.1.1",
    "framework": "IEC 62443",
    "title": "User authentication and authorization",
    "kernelInvariants": ["K2"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/AuthSoundnessK2.lean"},
      {"type": "zig-conformance", "file": "packages/cell-engine/tests/plexus_conformance.zig"}
    ],
    "additionalAssumptions": ["ECDSA unforgeability"],
    "status": "supported"
  },
  {
    "id": "2.1.2",
    "framework": "IEC 62443",
    "title": "Capability-based access control",
    "kernelInvariants": ["K2", "K1"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/AuthSoundnessK2.lean"},
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/LinearityK1.lean"},
      {"type": "zig-conformance", "file": "packages/cell-engine/tests/plexus_conformance.zig"},
      {"type": "differential", "file": "packages/cell-engine/tests/differential_conformance.zig"}
    ],
    "additionalAssumptions": ["ECDSA unforgeability"],
    "status": "supported"
  },
  {
    "id": "3.3.1",
    "framework": "IEC 62443",
    "title": "Failure-safe operation",
    "kernelInvariants": ["K4"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/FailureAtomicK4.lean"},
      {"type": "zig-conformance", "file": "packages/cell-engine/tests/plexus_conformance.zig"},
      {"type": "fuzz", "file": "packages/cell-engine/fuzz/plexus_atomic_fuzz.zig"}
    ],
    "additionalAssumptions": [],
    "status": "supported"
  },
  {
    "id": "3.4.1",
    "framework": "IEC 62443",
    "title": "Deterministic execution",
    "kernelInvariants": ["K5"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/TerminationK5.lean"},
      {"type": "zig-conformance", "file": "packages/cell-engine/tests/executor_conformance.zig"}
    ],
    "additionalAssumptions": [],
    "status": "supported"
  },
  {
    "id": "2.1",
    "framework": "EU AI Act",
    "title": "Risk identification and mitigation",
    "kernelInvariants": ["K1", "K3"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/LinearityK1.lean"},
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/DomainIsolationK3.lean"},
      {"type": "fuzz", "file": "packages/cell-engine/fuzz/linearity_fuzz.zig"}
    ],
    "additionalAssumptions": [],
    "status": "supported"
  },
  {
    "id": "2.2",
    "framework": "EU AI Act",
    "title": "Data governance and quality",
    "kernelInvariants": ["K7"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/CellImmutabilityK7.lean"},
      {"type": "differential", "file": "packages/cell-engine/tests/differential_conformance.zig"}
    ],
    "additionalAssumptions": [],
    "status": "supported"
  },
  {
    "id": "2.3",
    "framework": "EU AI Act",
    "title": "Transparency and traceability",
    "kernelInvariants": ["K6", "K7"],
    "proofArtifacts": [
      {"type": "tla-property", "file": "proofs/tla/EvidenceChain.tla"},
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/CellImmutabilityK7.lean"}
    ],
    "additionalAssumptions": ["SHA-256 collision resistance"],
    "status": "supported"
  },
  {
    "id": "2.4",
    "framework": "EU AI Act",
    "title": "Human oversight capability",
    "kernelInvariants": ["K5", "K4"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/TerminationK5.lean"},
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/FailureAtomicK4.lean"}
    ],
    "additionalAssumptions": [],
    "status": "supported"
  },
  {
    "id": "3.1",
    "framework": "GDPR",
    "title": "Data integrity and confidentiality",
    "kernelInvariants": ["K1", "K7"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/LinearityK1.lean"},
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/CellImmutabilityK7.lean"},
      {"type": "fuzz", "file": "packages/cell-engine/fuzz/linearity_fuzz.zig"}
    ],
    "additionalAssumptions": [],
    "status": "supported"
  },
  {
    "id": "3.2",
    "framework": "GDPR",
    "title": "Lawful processing controls",
    "kernelInvariants": ["K2", "K3"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/AuthSoundnessK2.lean"},
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/DomainIsolationK3.lean"},
      {"type": "zig-conformance", "file": "packages/cell-engine/tests/plexus_conformance.zig"}
    ],
    "additionalAssumptions": ["ECDSA unforgeability"],
    "status": "supported"
  },
  {
    "id": "3.3",
    "framework": "GDPR",
    "title": "Data subject rights (erasure, portability)",
    "kernelInvariants": ["K1", "K2"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/LinearityK1.lean"},
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/AuthSoundnessK2.lean"},
      {"type": "tla-property", "file": "proofs/tla/ReplayPrevention.tla"}
    ],
    "additionalAssumptions": ["LINEAR consumption ensures single-use (no replay)"],
    "status": "supported"
  },
  {
    "id": "4.1",
    "framework": "Basel III/IV",
    "title": "Operational risk management",
    "kernelInvariants": ["K4", "K5"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/FailureAtomicK4.lean"},
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/TerminationK5.lean"},
      {"type": "fuzz", "file": "packages/cell-engine/fuzz/plexus_atomic_fuzz.zig"},
      {"type": "fuzz", "file": "packages/cell-engine/fuzz/stack_bounds_fuzz.zig"}
    ],
    "additionalAssumptions": [],
    "status": "supported"
  },
  {
    "id": "4.2",
    "framework": "Basel III/IV",
    "title": "Counterparty credit risk controls",
    "kernelInvariants": ["K1", "K2"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/LinearityK1.lean"},
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/AuthSoundnessK2.lean"},
      {"type": "tla-property", "file": "proofs/tla/ReplayPrevention.tla"}
    ],
    "additionalAssumptions": ["LINEAR prevents double-spend of financial instruments"],
    "status": "supported"
  },
  {
    "id": "5.1",
    "framework": "HIPAA",
    "title": "Access controls (technical safeguards)",
    "kernelInvariants": ["K2", "K3"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/AuthSoundnessK2.lean"},
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/DomainIsolationK3.lean"},
      {"type": "zig-conformance", "file": "packages/cell-engine/tests/plexus_conformance.zig"}
    ],
    "additionalAssumptions": ["ECDSA unforgeability"],
    "status": "supported"
  },
  {
    "id": "5.2",
    "framework": "HIPAA",
    "title": "Audit controls and integrity",
    "kernelInvariants": ["K6", "K7"],
    "proofArtifacts": [
      {"type": "tla-property", "file": "proofs/tla/EvidenceChain.tla"},
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/CellImmutabilityK7.lean"}
    ],
    "additionalAssumptions": ["SHA-256 collision resistance"],
    "status": "supported"
  },
  {
    "id": "5.3",
    "framework": "HIPAA",
    "title": "Transmission security",
    "kernelInvariants": ["K6"],
    "proofArtifacts": [
      {"type": "tla-property", "file": "proofs/tla/EvidenceChain.tla"},
      {"type": "tla-property", "file": "proofs/tla/PartitionResilience.tla"}
    ],
    "additionalAssumptions": ["SHA-256 collision resistance", "HMAC-SHA-256 PRF security"],
    "status": "supported"
  },
  {
    "id": "6.1",
    "framework": "NIS2",
    "title": "Incident handling and response",
    "kernelInvariants": ["K4", "K6"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/FailureAtomicK4.lean"},
      {"type": "tla-property", "file": "proofs/tla/EvidenceChain.tla"},
      {"type": "tla-property", "file": "proofs/tla/CertRevocation.tla"}
    ],
    "additionalAssumptions": [],
    "status": "supported"
  },
  {
    "id": "6.2",
    "framework": "NIS2",
    "title": "Business continuity and resilience",
    "kernelInvariants": ["K5"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/TerminationK5.lean"},
      {"type": "tla-property", "file": "proofs/tla/PartitionResilience.tla"},
      {"type": "tla-property", "file": "proofs/tla/MeteringFSM.tla"}
    ],
    "additionalAssumptions": [],
    "status": "supported"
  },
  {
    "id": "P1.1",
    "framework": "Cross-Framework",
    "title": "Resource linearity (single-use guarantee)",
    "kernelInvariants": ["K1"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/LinearityK1.lean"},
      {"type": "zig-conformance", "file": "packages/cell-engine/tests/linearity_conformance.zig"},
      {"type": "fuzz", "file": "packages/cell-engine/fuzz/linearity_fuzz.zig"},
      {"type": "differential", "file": "packages/cell-engine/tests/differential_conformance.zig"},
      {"type": "mutation", "file": "packages/cell-engine/mutations/linearity_mutations.md"}
    ],
    "additionalAssumptions": [],
    "status": "supported"
  },
  {
    "id": "P2.1",
    "framework": "Cross-Framework",
    "title": "Domain isolation (no cross-domain leakage)",
    "kernelInvariants": ["K3"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/DomainIsolationK3.lean"},
      {"type": "zig-conformance", "file": "packages/cell-engine/tests/plexus_conformance.zig"},
      {"type": "differential", "file": "packages/cell-engine/tests/differential_conformance.zig"},
      {"type": "mutation", "file": "packages/cell-engine/mutations/plexus_mutations.md"}
    ],
    "additionalAssumptions": [],
    "status": "supported"
  },
  {
    "id": "P3.1",
    "framework": "Cross-Framework",
    "title": "Evidence chain integrity (append-only)",
    "kernelInvariants": ["K6"],
    "proofArtifacts": [
      {"type": "tla-property", "file": "proofs/tla/EvidenceChain.tla"},
      {"type": "tla-property", "file": "proofs/tla/ReplayPrevention.tla"}
    ],
    "additionalAssumptions": ["SHA-256 collision resistance"],
    "status": "supported"
  },
  {
    "id": "P4.1",
    "framework": "Cross-Framework",
    "title": "Compliance by architecture (full conjunction)",
    "kernelInvariants": ["K1", "K2", "K3", "K4", "K5", "K6", "K7"],
    "proofArtifacts": [
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/LinearityK1.lean"},
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/AuthSoundnessK2.lean"},
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/DomainIsolationK3.lean"},
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/FailureAtomicK4.lean"},
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/TerminationK5.lean"},
      {"type": "lean-theorem", "file": "proofs/lean/Semantos/Theorems/CellImmutabilityK7.lean"},
      {"type": "tla-property", "file": "proofs/tla/EvidenceChain.tla"},
      {"type": "tla-property", "file": "proofs/tla/ReplayPrevention.tla"},
      {"type": "tla-property", "file": "proofs/tla/CertRevocation.tla"},
      {"type": "tla-property", "file": "proofs/tla/MeteringFSM.tla"},
      {"type": "tla-property", "file": "proofs/tla/ZoneBoundary.tla"},
      {"type": "tla-property", "file": "proofs/tla/PartitionResilience.tla"},
      {"type": "wasm-manifest", "file": "packages/cell-engine/WASM-MANIFEST.json"},
      {"type": "capstone", "file": "proofs/paper/P4.1-CAPSTONE.md"}
    ],
    "additionalAssumptions": ["SHA-256 collision resistance", "ECDSA unforgeability", "HMAC-SHA-256 PRF security", "Host imports correctly implemented", "BSV chain availability"],
    "status": "supported"
  }
]

```
