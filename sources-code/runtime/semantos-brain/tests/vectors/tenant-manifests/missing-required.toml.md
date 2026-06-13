---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/vectors/tenant-manifests/missing-required.toml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.274731+00:00
---

# runtime/semantos-brain/tests/vectors/tenant-manifests/missing-required.toml

```toml
# D-O8 conformance vector — missing tenant.domain.
# Expected: validate() reports kind=missing_field for tenant.domain.

[tenant]
display_name = "X"
owner_cert_path = "./acme-plumbing-cert.pem"
recovery_enrolment_id = "plexus-rec-x"

[extensions]
install = ["sovereignty"]

[branding]
landing_page_template = "minimal"
brand_color = "#000"

```
