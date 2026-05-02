# Homelab

[![Validate Compose](https://github.com/ragnarok22/homelab/actions/workflows/validate.yaml/badge.svg)](https://github.com/ragnarok22/homelab/actions/workflows/validate.yaml)
[![License](https://img.shields.io/github/license/ragnarok22/homelab)](https://github.com/ragnarok22/homelab/blob/main/LICENSE)
[![GitHub last commit](https://img.shields.io/github/last-commit/ragnarok22/homelab)](https://github.com/ragnarok22/homelab/commits/main)

A collection of self-hosted services running on Proxmox VE. The stack is split across three units:

- **Proxmox VE host** (`192.168.100.99`) — hypervisor, installed with the [community post-install script](https://community-scripts.org/scripts/post-pve-install)
- **HAOS VM** (`192.168.100.101`) — Home Assistant OS, installed with the [community HAOS VM script](https://community-scripts.org/scripts/haos-vm)
- **Pi-hole LXC** (`192.168.100.102`) — network-wide DNS with Unbound, installed with the [community Pi-hole script](https://community-scripts.org/scripts/pihole)
- **Docker LXC** (`192.168.100.100`) — all services below, privileged LXC with iGPU and 2TB drive passthrough

## 📋 Services

### 🏠 Core Infrastructure
- **[Cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)** - Cloudflare Tunnel client that creates encrypted tunnels to expose local services securely without opening inbound ports
- **[Nginx Proxy Manager](https://github.com/nginx-proxy/nginx-proxy)** - Automated nginx proxy for Docker containers with SSL certificate management
- **[Watchtower](https://github.com/containrrr/watchtower)** - Automatically updates running Docker containers to the latest available image

### 📊 Monitoring & Management
- **[Homarr](https://homarr.dev/)** - Customizable browser's home page to organize your self-hosted services
- **[Dash](https://github.com/MauriceNino/dashdot)** - A simple, modern server dashboard for monitoring system performance
- **[Scrutiny](https://github.com/AnalogJ/scrutiny)** - S.M.A.R.T. drive health dashboard with historical metrics and failure-focused alerts
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

- **[Duplicati](https://duplicati.com/)** - Backup software to store encrypted backups online — configured for Google Drive offsite sync

### 💰 Finance & Personal Tools
- **[Invoice Ninja](https://invoiceninja.com/)** - Self-hosted invoicing, billing, and payment platform for freelancers and businesses

### 🔧 Productivity & Automation
- **[n8n](https://n8n.io/)** - Workflow automation tool with a focus on providing a self-hosted alternative to Zapier
- **[Excalidraw](https://excalidraw.com/)** - Virtual whiteboard for sketching hand-drawn like diagrams

## 🚀 Getting Started

### Prerequisites
- Docker and Docker Compose installed
- A `.env` file configured with required environment variables (see `example.env`)

### Running Services

#### Start All Services
```bash
docker compose up -d
```

#### Start Individual Services
Run a specific service using its compose file:
```bash
docker compose -f pihole/compose.yaml up -d
docker compose -f jellyfin/compose.yaml up -d
# ... etc
```

#### Stop All Services
```bash
docker compose down
```

## 🌐 Network Configuration

All services are configured to use an external Docker network called `homelab`. Create it with:
```bash
docker network create homelab
```

## ⚙️ Configuration

1. Copy `example.env` to `.env` and configure the required variables
2. Each service has its own directory with service-specific configuration
3. Most services use volume mounts for persistent data storage
4. Web interfaces are typically exposed through the nginx proxy manager

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
