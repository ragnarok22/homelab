# Repository Guidelines

## Architecture Overview
- This repository manages a self-hosted homelab with Docker Compose.
- Root `compose.yaml` includes per-service Compose files via `include`.
- Each service lives in its own directory with isolated config.
- Services share an external Docker network named `homelab`.
- Persistence is handled with service-specific volumes and bind mounts.

## Project Structure & Module Organization
- Root files: `compose.yaml`, `README.md`, `LICENSE`, `.gitignore`.
- Service layout:
  - `service-name/compose.yaml`
  - `service-name/example.env`
  - Optional `service-name/config/` and `service-name/cache/`
- Runtime secrets/config:
  - Copy `service-name/example.env` to `service-name/.env`
  - Keep `.env` untracked (`**/.env` is gitignored)

## Build, Test, and Development Commands
- Create network (first run): `docker network create homelab`
- Start all services: `docker compose up -d`
- Start one service: `docker compose -f service-name/compose.yaml up -d`
- Stop all services: `docker compose down`
- Stop one service: `docker compose -f service-name/compose.yaml down`
- Validate full config: `docker compose config`
- Validate one service: `docker compose -f service-name/compose.yaml config`
- Inspect status: `docker compose ps`
- Tail logs (all stack): `docker compose logs -f`
- Tail logs (single service compose): `docker compose -f service-name/compose.yaml logs -f`

## Coding Style & Naming Conventions
- Compose files are named `compose.yaml` with 2-space indentation.
- Service folders use kebab-case (for example, `nginx-manager/`, `home-assistant/`).
- Environment variables use UPPER_SNAKE_CASE.
- Do not hardcode secrets in Compose files.
- Prefer explicit `container_name`, `volumes`, and `env_file` declarations.

## Testing Guidelines
- Lint syntax: `docker compose config` must pass with no warnings.
- Smoke test a service:
  - `docker compose -f service-name/compose.yaml up -d`
  - `docker compose -f service-name/compose.yaml logs -f`
- Verify persistence by restarting and confirming data under mounted `config/`/volume paths.

## Commit & Pull Request Guidelines
- Use Conventional Commits:
  - `feat(scope): ...`
  - `fix(compose): ...`
  - `docs(readme): ...`
- PRs should include:
  - Summary of changes and rationale
  - Affected services and exposed ports
  - Validation steps with expected outcomes
  - Screenshots for UI-facing services when applicable

## Security & Configuration Tips
- Never commit real secrets.
- Keep `.env` local and use `example.env` placeholders in git.
- Prefer the external `homelab` network over host networking unless justified.
- For new services:
  1. Create `service-name/`
  2. Add `service-name/compose.yaml` with `homelab` external network and persistent volumes
  3. Add `service-name/example.env`
  4. Add the service path under root `compose.yaml` `include:`

## Service Categories
- Core infrastructure: Pi-hole, Nginx Proxy Manager, Watchtower
- Media management: Jellyfin, Radarr, Sonarr, Prowlarr, qBittorrent
- Monitoring: Homarr, Dash, pgAdmin
- Home automation: Home Assistant
- Productivity: n8n, Excalidraw
- Deprecated: Maybe

## Important Files
- `compose.yaml`: root include list for all services
- `README.md`: setup and service documentation
- `.gitignore`: excludes runtime config and state (`**/.env`, `**/config/`, `**/cache/`)
