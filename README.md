# Homelab

[![Validate Compose](https://github.com/ragnarok22/homelab/actions/workflows/validate.yaml/badge.svg)](https://github.com/ragnarok22/homelab/actions/workflows/validate.yaml)
[![License](https://img.shields.io/github/license/ragnarok22/homelab)](https://github.com/ragnarok22/homelab/blob/main/LICENSE)
[![GitHub last commit](https://img.shields.io/github/last-commit/ragnarok22/homelab)](https://github.com/ragnarok22/homelab/commits/main)

A collection of self-hosted services running on Proxmox VE. The stack is split across four units:

- **Proxmox VE host** (`192.168.100.99`) — hypervisor, installed with the [community post-install script](https://community-scripts.org/scripts/post-pve-install)
- **HAOS VM** (`192.168.100.101`) — Home Assistant OS, installed with the [community HAOS VM script](https://community-scripts.org/scripts/haos-vm)
- **Pi-hole LXC** (`192.168.100.102`) — network-wide DNS with Unbound, installed with the [community Pi-hole script](https://community-scripts.org/scripts/pihole)
- **Docker LXC** (`192.168.100.100`) — all services below, privileged LXC with iGPU and 2TB drive passthrough

## 🧱 Architecture

| Unit | Type | IP | Role |
|---|---|---|---|
| Proxmox VE | Host | `192.168.100.99` | Hypervisor and VM/LXC management |
| Docker | Privileged LXC | `192.168.100.100` | Docker Compose stack, media storage, backups |
| Home Assistant | VM | `192.168.100.101` | HAOS with native add-ons and backups |
| Pi-hole | LXC | `192.168.100.102` | DNS filtering and Unbound recursive DNS |

The Docker LXC receives the Intel iGPU (`/dev/dri`) for Jellyfin hardware transcoding and the 2TB data drive mounted at `/home/Data`.

## 📋 Services

### 🏠 Core Infrastructure
- **[Cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)** - Cloudflare Tunnel client that creates encrypted tunnels to expose local services securely without opening inbound ports
- **[Nginx Proxy Manager](https://nginxproxymanager.com/)** - Reverse proxy for Docker services with SSL certificate management
- **[Watchtower](https://github.com/containrrr/watchtower)** - Automatically updates running Docker containers to the latest available image
- **[Duplicati](https://duplicati.com/)** - Backup software to store encrypted backups online

### 📊 Monitoring & Management
- **[Homarr](https://homarr.dev/)** - Customizable browser's home page to organize your self-hosted services
- **[Dash](https://github.com/MauriceNino/dashdot)** - A simple, modern server dashboard for monitoring system performance
- **[Scrutiny](https://github.com/AnalogJ/scrutiny)** - S.M.A.R.T. drive health dashboard with historical metrics and failure-focused alerts
- **[ntfy](https://ntfy.sh/)** - Self-hosted push notifications for homelab alerts
- **[Uptime Kuma](https://uptime.kuma.pet/)** - Uptime, Docker container, and push-based service monitoring
- **[Diun](https://crazymax.dev/diun/)** - Docker image update notifications
- **[pgAdmin](https://www.pgadmin.org/)** - Management tool for PostgreSQL databases

### 🎬 Media Management
- **[Jellyfin](https://jellyfin.org/)** - Free Software Media System that puts you in control of managing and streaming your media
- **[Jellyseerr](https://github.com/Fallenbagel/jellyseerr)** - Request management and media discovery tool for Jellyfin
- **[Radarr](https://radarr.video/)** - Movie collection manager that works with various download clients
- **[Sonarr](https://sonarr.tv/)** - TV series management and automation tool
- **[Prowlarr](https://github.com/Prowlarr/Prowlarr)** - Indexer manager/proxy for various download clients
- **[qBittorrent](https://www.qbittorrent.org/)** - Free and open-source BitTorrent client
- **[Suwayomi](https://github.com/Suwayomi/Suwayomi-Server)** - Free and open source manga reader server that runs extensions

### 📸 Photo & File Management
- **[Immich](https://immich.app/)** - High performance self-hosted photo and video management solution
- **[Nextcloud](https://nextcloud.com/)** - Self-hosted productivity platform for file sync, sharing, and collaboration

### 🏠 Home Automation
- **[Home Assistant](https://www.home-assistant.io/)** - Runs as HAOS VM on Proxmox (`192.168.100.101`), installed via the [community HAOS VM script](https://community-scripts.org/scripts/haos-vm)

### 💰 Finance & Personal Tools
- **[Invoice Ninja](https://invoiceninja.com/)** - Self-hosted invoicing, billing, and payment platform for freelancers and businesses

### 🔧 Productivity & Automation
- **[n8n](https://n8n.io/)** - Workflow automation tool with a focus on providing a self-hosted alternative to Zapier
- **[Excalidraw](https://excalidraw.com/)** - Virtual whiteboard for sketching hand-drawn like diagrams

## 🚀 Getting Started

### Prerequisites
- Proxmox VE host with the Docker LXC running
- Docker Engine and Docker Compose installed inside the Docker LXC
- External Docker network named `homelab`
- A `.env` file for each service that needs one, based on that service's `example.env`

Create the shared Docker network once inside the Docker LXC:
```bash
docker network create homelab
```

### Running Services

Run these commands from the repo directory inside the Docker LXC.

#### Start All Docker Services
```bash
docker compose up -d
```

#### Start One Docker Service
```bash
docker compose -f jellyfin/compose.yaml up -d
```

#### Stop All Docker Services
```bash
docker compose down
```

#### Validate Compose Configuration
After all required local `.env` files exist:

```bash
docker compose config
```

Home Assistant and Pi-hole are managed separately in Proxmox, not through this Compose stack.

## 🌐 Network Configuration

All Docker services are attached to the external Docker network `homelab`.

External access flows through:

```text
Cloudflare Tunnel → Nginx Proxy Manager → Docker services
```

Pi-hole should be configured as the LAN DNS resolver by setting the router DHCP DNS server to `192.168.100.102`.

## 💾 Backups

The deployment uses three backup layers:

1. **Proxmox vzdump** — weekly snapshots of the Docker LXC, HAOS VM, and Pi-hole LXC to `/mnt/data/vzdump/`, keeping the latest 3 copies.
2. **App-level backup script** — `scripts/backup.sh` runs daily inside the Docker LXC and writes database dumps, service config archives, and selected Docker volume snapshots to `/home/Data/backup_homelab/`.
3. **Duplicati offsite sync** — Duplicati uploads the local backup output and the Immich photo library to Google Drive.

Home Assistant also uses its Google Drive Backup add-on for HA-native backups.

## 🚨 Alerts

The alerting stack uses **ntfy** as the notification target, **Uptime Kuma** for uptime/container/push monitors, **Diun** for pending Docker image updates, and **Scrutiny** for SMART health.

Create local env files before starting the services:

```bash
cp ntfy/example.env ntfy/.env
cp uptime-kuma/example.env uptime-kuma/.env
cp diun/example.env diun/.env
cp scripts/alerts.env.example scripts/alerts.env
```

Update `ntfy/.env` with the public ntfy URL you expose through Nginx Proxy Manager. The Compose service does not publish a host port by default, so proxy `ntfy` to port `80` on the `homelab` Docker network.

Update `diun/.env` if you change the ntfy topic or enable ntfy authentication. By default, Diun checks all running Docker containers every 6 hours and notifies `homelab-alerts` through the internal `http://ntfy` endpoint.

Configure Uptime Kuma through its web UI, then add these monitors:

- HTTP monitors for public Cloudflare Tunnel URLs.
- Docker monitors for critical containers, using the mounted Docker socket.
- Push monitor for `scripts/backup.sh`.
- Push monitor for `scripts/check-disk.sh`.

After creating the Push monitors, add their URLs to `scripts/alerts.env` as `KUMA_BACKUP_PUSH_URL` and `KUMA_DISK_PUSH_URL`. The backup script sends failure alerts automatically and reports success to Kuma. The disk script sends a ntfy alert when usage crosses `DISK_ALERT_THRESHOLD` and a recovery notification when it goes below the threshold.

Example cron entries inside the Docker LXC:

```cron
0 1 * * * /root/homelab/scripts/backup.sh >> /var/log/homelab-backup.log 2>&1
*/30 * * * * /root/homelab/scripts/check-disk.sh >> /var/log/homelab-disk.log 2>&1
```

For SMART alerts, use Scrutiny as the source of truth and configure its notification destination to the same ntfy topic where supported by your Scrutiny config/version.

Uptime Kuma uses the `louislam/uptime-kuma:2` Docker tag. When upgrading an existing v1 deployment, stop the service and back up `uptime-kuma/data` before starting v2 because the first boot migrates the SQLite database and must not be interrupted:

```bash
docker compose -f uptime-kuma/compose.yaml down
tar czf /root/uptime-kuma-data-before-v2.tar.gz uptime-kuma/data
docker compose -f uptime-kuma/compose.yaml up -d
docker compose -f uptime-kuma/compose.yaml logs -f
```

## ⚙️ Configuration

1. Copy `example.env` to `.env` and configure the required variables
2. Each service has its own directory with service-specific configuration
3. Most services use volume mounts for persistent data storage
4. Web interfaces are typically exposed through Nginx Proxy Manager
5. Runtime config and state directories stay untracked (`.env`, `config/`, `cache/`, `data/`, downloads, and service runtime state)

### Personal Setup Reference

If you use an AI assistant (Claude, Cursor, etc.) to help manage your fork of this repo, consider creating a `custom/HOMELAB.md` file with your specific configuration: IP addresses, domain names, hardware specs, backup details, etc. This file is gitignored so it stays local and never gets committed.

Ask your AI assistant: *"Document my current homelab setup in custom/HOMELAB.md"*.

## 🤝 Contributing

- Read the contribution guide: see `CONTRIBUTING.md`.
- Repository guidelines for structure and workflow: see `AGENTS.md`.
- Use Conventional Commits in titles and messages (e.g., `feat(compose): add suwayomi service`).
- Follow the PR template; include validation steps and screenshots when relevant.
- For service additions, include `service-name/compose.yaml`, `service-name/example.env`, and update the root `compose.yaml` include list.

## 🫱🏻‍🫲🏽 Community & Conduct

- This project follows a Code of Conduct: see `CODE_OF_CONDUCT.md`.
- Report concerns privately via the contact in the Code of Conduct.
- Open issues using the provided templates (bug report or feature request) to help maintainers triage quickly.
