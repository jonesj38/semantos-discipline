---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/vectors/tenant-manifests/invalid-domain.toml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.274457+00:00
---

# runtime/semantos-brain/tests/vectors/tenant-manifests/invalid-domain.toml

```toml
# D-O8 conformance vector — invalid domain (no dot, single label).
# Expected: validate() reports kind=invalid_domain.

[tenant]
domain = "not_a_valid_domain"
display_name = "X"
owner_cert_path = "./acme-plumbing-cert.pem"
recovery_enrolment_id = "plexus-rec-x"

[extensions]
install = ["sovereignty"]

[branding]
landing_page_template = "minimal"
brand_color = "#000"

```
