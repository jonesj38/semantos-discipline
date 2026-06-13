---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/deployment/VPS-DEPLOYMENT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.754555+00:00
---

# VPS Deployment Guide

Deploy a Semantos node on a cloud VPS (DigitalOcean, Vultr, Hetzner).

## Prerequisites

- Ubuntu 22.04+ or Debian 12+ VPS
- 2 GB RAM, 2 vCPU, 20 GB SSD minimum
- SSH access with root or sudo
- Open ports: 3000 (loom), 6443 (admin API), 9000/udp (shard proxy)

## Step 1: Provision the VPS

Create a droplet/instance with Ubuntu 22.04 LTS. Configure SSH key authentication.

```bash
ssh root@<your-ip>
```

## Step 2: Run the Installer

```bash
curl -fsSL https://raw.githubusercontent.com/todriguez/semantos-core/main/scripts/install.sh | bash
```

The installer will:
1. Detect your OS and CPU architecture
2. Install the Bun runtime
3. Create the `semantos` system user
4. Create directories: `/var/semantos/data`, `/etc/semantos`, `/var/semantos/extensions`
5. Prompt for configuration (cert ID, subnet prefix, BYOK key, anchor interval)
6. Generate self-signed TLS certificates
7. Write `/etc/semantos/node.json`
8. Create and start the systemd service

Expected output:
```
[semantos] Detected: Ubuntu 22.04.4 LTS
[semantos] CPU architecture: x86_64
[semantos] Installing Bun runtime...
[semantos] Creating system user 'semantos'...
[semantos] Creating directory structure...
[semantos] Node configuration
  Node certificate ID [auto]: <press Enter>
  Subnet prefix [2602:f9f8:0060:0001::]: <press Enter>
  OpenRouter API key []: <your-key or Enter to skip>
  Anchor interval (ms) [600000]: <press Enter>
  Install trades extension? (y/n) [y]: y
[semantos] Writing /etc/semantos/node.json...
[semantos] Generating self-signed TLS certificates...
[semantos] Creating systemd service...
[semantos] Enabling and starting service...

  Semantos node installed and running
  Status:      active
  Loom:   http://<your-ip>:3000
  Admin API:   https://<your-ip>:6443/api/node/status
  Node cert:   0x<generated-hex>
  Extensions:  ["sovereignty", "trades"]
```

## Step 3: Verify

```bash
# Check service status
systemctl status semantos

# View live logs
journalctl -u semantos -f

# Query admin API (with client cert)
curl --cert /etc/semantos/certs/client.crt \
     --key /etc/semantos/certs/client.key \
     --cacert /etc/semantos/certs/ca.crt \
     https://localhost:6443/api/node/status
```

## Step 4: Configure Firewall

```bash
ufw allow 3000/tcp   # loom UI
ufw allow 6443/tcp   # admin API
ufw allow 9000/udp   # shard proxy
ufw enable
```

## Costs

| Item | Monthly Cost |
|------|-------------|
| VPS (2GB/2vCPU) | $5-12 |
| Plexus RaaS (identity) | ~$1.70 |
| BSV anchoring fees | < $1 |
| **Total** | **~$10/month** |

## Monitoring

```bash
# Live logs
journalctl -u semantos -f

# Service status
systemctl status semantos

# Node status via API
curl -s https://localhost:6443/api/node/status | jq .data
```

## Backup

Back up the data directory periodically:

```bash
# Create snapshot
tar czf /tmp/semantos-backup-$(date +%Y%m%d).tar.gz /var/semantos/data

# Restore
systemctl stop semantos
tar xzf /tmp/semantos-backup-YYYYMMDD.tar.gz -C /
systemctl start semantos
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Service won't start | Missing config | Check `/etc/semantos/node.json` exists |
| Port 6443 refused | Firewall | `ufw allow 6443/tcp` |
| TLS handshake failed | Wrong certs | Verify cert paths in config |
| High memory usage | Large data set | Increase VPS RAM or add swap |
| Anchor failures | Network issue | Check BSV node connectivity |

## Upgrading

```bash
cd /opt/semantos
git pull origin main
bun install
systemctl restart semantos
```
