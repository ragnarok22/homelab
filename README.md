# homelab

My home lab.

## Services

This is a list of services I run on my home lab.

- [Watchtower](https://github.com/containrrr/watchtower) - Automatically updates
running Docker containers to the latest available image.
- [Pi-hole](https://pi-hole.net/) - Network-wide ad blocking DNS server that
improves network performance by blocking ads before they download.
- [Home Assistant](https://www.home-assistant.io/) - Open source home automation platform that puts local control and privacy first.
- [Jellyfin](https://jellyfin.org/) - Free Software Media System that puts you in control of managing and streaming your media.
- [Jellyseerr](https://github.com/Fallenbagel/jellyseerr) - Request management and media discovery tool for Jellyfin.
- [Homarr](https://homarr.dev/) - Customizable browser's home page to organize your self-hosted services.
- [Dash](https://github.com/MauriceNino/dashdot) - A simple, modern server dashboard for monitoring system performance.
- [Excalidraw](https://excalidraw.com/) - Virtual whiteboard for sketching hand-drawn like diagrams.
- [n8n](https://n8n.io/) - Workflow automation tool with a focus on providing a self-hosted alternative to Zapier.
- [Nginx Manager](https://github.com/nginx-proxy/nginx-proxy) - Automated nginx proxy for Docker containers.
- [pgAdmin](https://www.pgadmin.org/) - Management tool for PostgreSQL databases.
- [Prowlarr](https://github.com/Prowlarr/Prowlarr) - Indexer manager/proxy for various download clients.
- [qBittorrent](https://www.qbittorrent.org/) - Free and open-source BitTorrent client.
- [Radarr](https://radarr.video/) - Movie collection manager that works with various download clients.
- [Readarr](https://readarr.com/) - Book collection manager and automation tool.
- [Sonarr](https://sonarr.tv/) - TV series management and automation tool.

## Running

Run `docker compose up -d` to start all the services or just run
`docker compose -f pihole/compose.yml up -d` to only run the Pi-hole service.
