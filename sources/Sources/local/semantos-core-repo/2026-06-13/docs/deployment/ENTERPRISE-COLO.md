---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/deployment/ENTERPRISE-COLO.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.754064+00:00
---

# Enterprise Colo Deployment Guide

Deploy a Semantos sovereignty node on bare metal with provable data residency.

## Overview

Enterprise colo deployment provides:
- All data stays on customer hardware (provable data residency)
- On-prem certificate chain (LocalIdentityAdapter)
- 1-minute anchor cycle for faster state finality
- Campus LAN networking (DirectNetworkAdapter)
- Audit logging for compliance (HIPAA, PCI, SOC2)

## Prerequisites

- Dedicated server: 8+ GB RAM, 4+ cores, 100 GB+ NVMe SSD
- Ubuntu 22.04 LTS Server, static IP, DNS configured
- Network: subnet allocation from enterprise IPAM (e.g., 192.168.100.0/24)
- Enterprise root CA certificate (for mutual TLS)
- NTP configured for time synchronization

## Step 1: Hardware Provisioning

The infrastructure team provisions a server on the campus LAN:

```
Server:     Dell R650xs or equivalent
OS:         Ubuntu 22.04 LTS Server
IP:         192.168.100.10 (static)
DNS:        semantos.corp.example.com
Storage:    /mnt/nvme0 (dedicated NVMe for Semantos data)
```

## Step 2: Certificate Chain

Issue a node certificate from the enterprise root CA:

```bash
# On the CA server
openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
  -keyout semantos-node.key -out semantos-node.csr \
  -nodes -subj "/CN=Semantos Node/O=Enterprise/OU=IT"

# Sign with enterprise CA
openssl x509 -req -in semantos-node.csr \
  -CA enterprise-ca.crt -CAkey enterprise-ca.key \
  -CAcreateserial -out semantos-node.crt -days 365

# Transfer to the node
scp semantos-node.crt semantos-node.key admin@192.168.100.10:/tmp/
```

On the Semantos server:
```bash
mkdir -p /etc/semantos/certs
cp /tmp/semantos-node.crt /etc/semantos/certs/node.crt
cp /tmp/semantos-node.key /etc/semantos/certs/node.key
cp /path/to/enterprise-ca.crt /etc/semantos/certs/ca.crt
chmod 600 /etc/semantos/certs/node.key
```

## Step 3: Install

```bash
# From internal mirror (recommended for air-gapped environments)
curl -fsSL https://internal-mirror.corp.example.com/install.sh | bash

# Or from the repository directly
bash scripts/install.sh
```

During prompts:
- Certificate ID: use the enterprise-issued cert ID
- Subnet prefix: enterprise IPAM allocation
- Anchor interval: `60000` (1 minute for enterprise)
- BYOK key: enterprise OpenRouter key (or skip for offline)

## Step 4: Configure for Enterprise

Edit `/etc/semantos/node.json`:

```json
{
  "nodeCert": "<enterprise-cert-id>",
  "storage": { "type": "node-fs", "root": "/mnt/nvme0/semantos" },
  "identity": { "type": "local", "localDir": "/etc/semantos/certs" },
  "anchor": { "type": "bsv", "interval": 60000, "network": "mainnet" },
  "network": { "type": "stub" },
  "extensions": ["sovereignty", "cdm"],
  "anchorIntervalMs": 60000,
  "bcaAddress": "2602:f9f8:0060:0001::a3f8:b2c1",
  "subnetPrefix": "192.168.100.0/24",
  "dataDir": "/mnt/nvme0/semantos"
}
```

Restart the service:
```bash
systemctl restart semantos
```

## Step 5: Verify Data Residency

Confirm no external network calls:

```bash
# Monitor outbound connections
ss -tnp | grep semantos

# Verify data location
ls -la /mnt/nvme0/semantos/
du -sh /mnt/nvme0/semantos/

# Verify audit log
ls -la /var/log/semantos/
```

## Step 6: Audit Logging

Enable audit logging by creating `/etc/semantos/audit.json`:

```json
{
  "enabled": true,
  "logDir": "/var/log/semantos/audit",
  "retentionDays": 365,
  "logLevel": "info"
}
```

## Costs

| Item | Monthly Cost |
|------|-------------|
| Server hardware (amortized) | $100-300 |
| BSV anchoring (1-min cycle) | $5-10 |
| Enterprise CA maintenance | (existing infra) |
| **Total** | **$105-310/month** |

## Compliance Considerations

- **Data residency**: All data on customer hardware. No cloud dependencies.
- **Audit trail**: Append-only BSV anchoring provides tamper-evident audit.
- **Access control**: Mutual TLS with enterprise CA. No shared secrets.
- **Encryption**: All data encrypted at rest via NVMe self-encryption.
- **Backup**: Enterprise backup policies apply to `/mnt/nvme0/semantos`.

## Disaster Recovery

1. Regular snapshots of `/mnt/nvme0/semantos` via enterprise backup
2. Node config in `/etc/semantos` (back up separately)
3. Certificate chain stored in enterprise vault
4. Recovery: provision new server, restore from backup, start service

## Monitoring

Integrate with enterprise monitoring:

```bash
# Prometheus-compatible status endpoint
curl -s https://semantos.corp:6443/api/node/status | jq .data

# Systemd journal integration
journalctl -u semantos --since "1 hour ago"
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Anchor failures | No BSV connectivity | Check outbound firewall for BSV ports |
| Cert rejected | CA mismatch | Verify node cert signed by enterprise CA |
| Slow performance | Disk I/O | Check NVMe health, SMART status |
| Service restart loop | Config error | `journalctl -u semantos -n 50` |
