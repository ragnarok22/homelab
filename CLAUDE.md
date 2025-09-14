# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a Docker Compose-based homelab infrastructure managing multiple self-hosted services. The architecture uses a modular approach where each service has its own directory with isolated configuration.

**Key architectural patterns:**
- Root `compose.yaml` includes individual service compose files via `include` directive
- Each service directory contains: `compose.yaml`, `example.env`, and optional `config/` folder
- Services use individual `.env` files (not tracked) based on their `example.env` templates
- All services connect to an external Docker network called `homelab`
- Persistent data is managed through Docker volumes and bind mounts

## Common Commands

### Initial Setup
```bash
# Create the shared network (required for first run)
docker network create homelab

# Copy example.env to .env for each service you want to configure
cp service-name/example.env service-name/.env
# Edit the .env file with your actual values
```

### Service Management
```bash
# Start all services
docker compose up -d

# Start individual service
docker compose -f service-name/compose.yaml up -d

# Stop all services
docker compose down

# Stop individual service
docker compose -f service-name/compose.yaml down

# View logs
docker compose logs -f service-name

# Check service status
docker compose ps
```

### Development & Testing
```bash
# Validate compose configuration
docker compose config

# Test individual service configuration
docker compose -f service-name/compose.yaml config

# Smoke test a service (start and check logs)
docker compose -f service-name/compose.yaml up -d
docker compose -f service-name/compose.yaml logs -f
```

## Service Configuration

### Environment Variables
- Each service uses its own `.env` file located in its directory
- Use `example.env` as template - contains placeholder values like `yourdomain.com`, `your-password`
- Common variables across services: `TZ`, `PUID`, `PGID`
- Never commit actual `.env` files (they're gitignored)

### Adding New Services
1. Create `service-name/` directory
2. Add `service-name/compose.yaml` with:
   - External `homelab` network
   - `env_file: .env` configuration
   - Appropriate volumes for persistence
3. Create `service-name/example.env` with placeholder values
4. Add service path to root `compose.yaml` under `include:`

### Service Categories
- **Core Infrastructure**: Pi-hole, Nginx Proxy Manager, Watchtower
- **Media Management**: Jellyfin, Radarr, Sonarr, Prowlarr, qBittorrent
- **Monitoring**: Homarr, Dash, pgAdmin
- **Home Automation**: Home Assistant
- **Productivity**: n8n, Excalidraw
- **Deprecated**: Maybe (marked as deprecated in README)

## Development Conventions

- Use 2-space indentation in YAML files
- Service directories use kebab-case naming
- Container names should be explicit
- Environment variables use UPPER_SNAKE_CASE
- Prefer `env_file` over hardcoded `environment` blocks
- Use Conventional Commits: `feat(scope):`, `fix(compose):`, `docs(readme):`

## Important Files
- `compose.yaml` - Root compose file with service includes
- `example.env` - Global example (now deprecated, services have individual examples)
- `README.md` - Service documentation and setup instructions
- `.gitignore` - Excludes `**/.env` and service `**/config/` directories