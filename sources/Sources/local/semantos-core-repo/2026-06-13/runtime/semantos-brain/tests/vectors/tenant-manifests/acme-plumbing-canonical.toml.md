---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/vectors/tenant-manifests/acme-plumbing-canonical.toml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.275751+00:00
---

# runtime/semantos-brain/tests/vectors/tenant-manifests/acme-plumbing-canonical.toml

```toml
# D-O8 conformance vector — canonical §11 example.
#
# Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §11 line 631-700.
# Expected: parses + validates with zero errors (warnings allowed).

[tenant]
domain = "acme-plumbing.com.au"
display_name = "Acme Plumbing"
owner_cert_path = "./acme-plumbing-cert.pem"
recovery_enrolment_id = "plexus-rec-acme-001"

[extensions]
install = ["sovereignty", "oddjobz"]

[branding]
landing_page_template = "default-tradie"
brand_color = "#2a5fb5"

```
