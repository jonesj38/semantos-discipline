---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/deployment/INFRA-PARTNER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.753801+00:00
---

# Infrastructure Partner Deployment Guide

Deploy Semantos nodes as an infrastructure partner (Equinix Metal, AWS Dedicated, etc.).

## Overview

The infrastructure partner model:
- Partner provisions bare metal hardware
- Semantos provides the software stack and management
- Partner's customers rent node slices
- Semantos bills partner per customer per month
- Partner controls extension installs, billing, compliance

## Prerequisites

- Bare metal servers: Equinix Metal, Packet, or AWS Dedicated Host
- Ubuntu 22.04 LTS on each server
- IPv6 subnet allocation (e.g., 2602:f9f8:0060:NNNN::/64)
- Partner admin certificate from Semantos CA

## Step 1: Hardware Provisioning

Provision bare metal via partner's API:

```
Provider:   Equinix Metal
Plan:       c3.small.x86 (8 cores, 32 GB, 2x 480 GB SSD)
OS:         Ubuntu 22.04 LTS
Location:   SY1 (Sydney) or SV15 (Silicon Valley)
Network:    Public IPv4 + /64 IPv6 block
```

## Step 2: Subnet Registration

Notify Semantos of the allocated subnet:

```
Partner:    <partner-name>
Subnet:     2602:f9f8:0060:NNNN::/64
Location:   SY1 (Sydney, AU)
Capacity:   up to 256 customer nodes
```

Semantos registers the partner entry in the node registry.

## Step 3: Install (Same as VPS)

```bash
ssh root@<server-ip>
curl -fsSL https://semantos.io/install.sh | bash
```

Configure during prompts:
- Cert ID: provided by Semantos after partner registration
- Subnet: allocated /64 block
- Anchor interval: `300000` (5 minutes for partner nodes)

## Step 4: Multi-Customer Configuration

Each customer gets their own node.json within the partner's infrastructure:

```
/etc/semantos/
  partner.json          # Partner-level config
  customers/
    customer-001.json   # Customer 1 node config
    customer-002.json   # Customer 2 node config
```

Partner config (`partner.json`):
```json
{
  "partnerId": "<partner-id>",
  "subnet": "2602:f9f8:0060:NNNN::/64",
  "maxCustomers": 256,
  "billingEndpoint": "https://billing.semantos.io/v1",
  "defaultExtensions": ["sovereignty"]
}
```

Customer config (e.g., `customer-001.json`):
```json
{
  "nodeCert": "<customer-cert-id>",
  "storage": { "type": "node-fs", "root": "/data/customers/001" },
  "identity": { "type": "stub" },
  "anchor": { "type": "bsv", "interval": 300000 },
  "network": { "type": "bsv-overlay" },
  "extensions": ["sovereignty", "trades"],
  "bcaAddress": "2602:f9f8:0060:NNNN::001"
}
```

## Step 5: Customer Provisioning

When a new customer signs up, the partner:

1. Allocates a BCA address from the subnet
2. Creates a customer node config
3. Starts a new node instance via the admin API:

```bash
curl --cert /etc/semantos/certs/partner.crt \
     --key /etc/semantos/certs/partner.key \
     --cacert /etc/semantos/certs/ca.crt \
     -X POST \
     -H "Content-Type: application/json" \
     -d '{"name":"trades"}' \
     https://localhost:6443/api/node/extensions/install
```

## Step 6: Verify

```bash
# Check all customer nodes
for config in /etc/semantos/customers/*.json; do
  echo "$(basename $config): $(curl -s https://localhost:6443/api/node/status | jq -r .data.running)"
done
```

## Billing Model

| Tier | Customers | Price per Customer |
|------|-----------|-------------------|
| Starter | 1-10 | $15/month |
| Growth | 11-50 | $12/month |
| Scale | 51-256 | $8/month |

Partner receives a management fee of 20% on top of Semantos base price.

## Governance

- Partner controls which extensions are available to customers
- Partner can install/uninstall extensions per customer
- Customers cannot modify their own node config (partner-managed)
- Partner handles support escalation to Semantos

## SLA

| Metric | Target |
|--------|--------|
| Node uptime | 99.9% |
| Anchor finality | < 10 minutes |
| API response time | < 200ms p95 |
| Support response | 4 hours (business hours) |

## Costs

| Item | Monthly Cost |
|------|-------------|
| Bare metal (c3.small.x86) | $200-400 |
| BSV anchoring (5-min cycle per customer) | $2-5 per customer |
| Semantos software license | per billing tier |
| **Break-even** | **~15 customers** |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Customer isolation breach | Config error | Verify data dir isolation |
| Subnet exhaustion | Too many customers | Request additional /64 block |
| High anchor costs | Too many customers | Batch anchoring across customers |
| Partner cert expired | Rotation missed | Contact Semantos for renewal |
