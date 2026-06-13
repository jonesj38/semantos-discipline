---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/vectors/tenant-manifests/bad-cert-path.toml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.274182+00:00
---

# runtime/semantos-brain/tests/vectors/tenant-manifests/bad-cert-path.toml

```toml
# D-O8 conformance vector — owner_cert_path doesn't resolve on disk.
# Expected: validate() (with manifest_dir) reports kind=cert_not_found.

[tenant]
domain = "x.example"
display_name = "X"
owner_cert_path = "./does-not-exist.pem"
recovery_enrolment_id = "plexus-rec-x"

[extensions]
install = ["sovereignty"]

[branding]
landing_page_template = "minimal"
brand_color = "#000"

```
