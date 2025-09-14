# Homelab

A collection of self-hosted services running in Docker containers for my home lab setup.

## 📋 Services

### 🏠 Core Infrastructure
- **[Pi-hole](https://pi-hole.net/)** - Network-wide ad blocking DNS server that improves network performance by blocking ads before they download
- **[Nginx Proxy Manager](https://github.com/nginx-proxy/nginx-proxy)** - Automated nginx proxy for Docker containers with SSL certificate management
- **[Watchtower](https://github.com/containrrr/watchtower)** - Automatically updates running Docker containers to the latest available image

### 📊 Monitoring & Management
- **[Homarr](https://homarr.dev/)** - Customizable browser's home page to organize your self-hosted services
- **[Dash](https://github.com/MauriceNino/dashdot)** - A simple, modern server dashboard for monitoring system performance
- **[pgAdmin](https://www.pgadmin.org/)** - Management tool for PostgreSQL databases
- **[Unifi Network Application](https://ui.com/)** - Enterprise network management platform for Unifi devices

### 🎬 Media Management
- **[Jellyfin](https://jellyfin.org/)** - Free Software Media System that puts you in control of managing and streaming your media
- **[Jellyseerr](https://github.com/Fallenbagel/jellyseerr)** - Request management and media discovery tool for Jellyfin
- **[Radarr](https://radarr.video/)** - Movie collection manager that works with various download clients
- **[Sonarr](https://sonarr.tv/)** - TV series management and automation tool
- **[Readarr](https://readarr.com/)** - Book collection manager and automation tool
- **[Prowlarr](https://github.com/Prowlarr/Prowlarr)** - Indexer manager/proxy for various download clients
- **[qBittorrent](https://www.qbittorrent.org/)** - Free and open-source BitTorrent client
- **[Suwayomi](https://github.com/Suwayomi/Suwayomi-Server)** - Free and open source manga reader server that runs extensions

### 📸 Photo & File Management
- **[Immich](https://immich.app/)** - High performance self-hosted photo and video management solution

### 🏠 Home Automation
- **[Home Assistant](https://www.home-assistant.io/)** - Open source home automation platform that puts local control and privacy first

### 💰 Finance & Personal Tools
- **[Maybe](https://github.com/maybe-finance/maybe)** *(deprecated)* - Personal finance and wealth management application

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
- Use Conventional Commits in titles and messages (e.g., `feat(compose): add suwayomi service`).
- Follow the PR template; include validation steps and screenshots when relevant.
- For service additions, include `service-name/compose.yaml`, `service-name/example.env`, and update the root `compose.yaml` include list.

## 🫱🏻‍🫲🏽 Community & Conduct

- This project follows a Code of Conduct: see `CODE_OF_CONDUCT.md`.
- Report concerns privately via the contact in the Code of Conduct.
- Open issues using the provided templates (bug report or feature request) to help maintainers triage quickly.
