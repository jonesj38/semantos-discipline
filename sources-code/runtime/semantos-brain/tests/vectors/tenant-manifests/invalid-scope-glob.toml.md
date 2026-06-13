---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/vectors/tenant-manifests/invalid-scope-glob.toml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.276032+00:00
---

# runtime/semantos-brain/tests/vectors/tenant-manifests/invalid-scope-glob.toml

```toml
# D-W2 Phase 0 conformance vector — invalid: scope contains a path
# character (`/`) which the §10 risk mitigation explicitly rejects.

[tenant]
domain = "acme-plumbing.com.au"
display_name = "Acme Plumbing"
owner_cert_path = "./acme-plumbing-cert.pem"
recovery_enrolment_id = "plexus-rec-acme-001"

[extensions]
install = ["sovereignty"]

[branding]
landing_page_template = "default-tradie"
brand_color = "#2a5fb5"

[trusted_signers.platform]
pubkey = "02a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90"
plexus_identity_tx = "deadbeefcafebabe0011223344556677aabbccddeeff00112233445566778899"
scope = "acme.com/oddjobz"
removable = false
label = "Platform — operator-managed"
shard_group = "shard-platform-acme-001"

```
