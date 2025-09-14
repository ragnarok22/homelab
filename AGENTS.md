# Repository Guidelines

## Project Structure & Module Organization
- Root `compose.yaml` includes per-service Compose files via `include`.
- Each service lives in its own folder with `compose.yaml` and `example.env`.
- A single root `.env` (ignored) provides variables to services via `env_file: ../.env`.
- Typical layout:
  - `compose.yaml`, `README.md`, `LICENSE`
  - `service-name/compose.yaml`, `service-name/example.env`, optional `config/`

## Build, Test, and Development Commands
- Create network (first run): `docker network create homelab`
- Start all services: `docker compose up -d`
- Start one service: `docker compose -f jellyfin/compose.yaml up -d`
- Stop all: `docker compose down`
- Validate config: `docker compose config`
- Inspect status: `docker compose ps`
- Tail logs: `docker compose logs -f <service>`

## Coding Style & Naming Conventions
- Compose files are `compose.yaml`; use 2‑space indentation.
- Service folders use kebab-case: `nginx-manager/`, `home-assistant/`.
- Environment variables are UPPER_SNAKE_CASE; do not hardcode secrets.
- Prefer explicit `container_name`, volumes, and `env_file` in each service file.

## Testing Guidelines
- Lint syntax: `docker compose config` must pass with no warnings.
- Smoke test a service: `docker compose -f <svc>/compose.yaml up -d`, then `docker compose logs -f <svc>`.
- Verify persistence by checking mounted `config/` volumes after restarts.

## Commit & Pull Request Guidelines
- Use Conventional Commits: `feat(scope): ...`, `fix(compose): ...`, `docs(readme): ...`.
- PRs should include:
  - Summary of changes and rationale
  - Affected services and ports
  - Steps to validate (commands + expected outcomes)
  - Screenshots for UI-facing services when applicable

## Security & Configuration Tips
- Never commit real secrets. Keep `.env` local; use `example.env` for placeholders.
- Default network is external `homelab`; prefer it over host networking unless justified.
- When adding a new service, add `service-name/compose.yaml` and `service-name/example.env`, then list it under `include` in root `compose.yaml`.
