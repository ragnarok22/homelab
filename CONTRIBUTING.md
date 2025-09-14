# Contributing Guide

Thank you for improving this homelab Docker stack. This guide explains how to propose changes safely and consistently.

## Prerequisites
- Docker and Docker Compose v2 installed
- Local `.env` (not committed). Use each service’s `example.env` as a reference.
- External Docker network `homelab`:

```bash
docker network ls | grep homelab || docker network create homelab
```

## Project Layout
- Root `compose.yaml` includes per-service files via `include`.
- Each service lives in `service-name/` with `compose.yaml` and `example.env`.
- Persistent data is mounted under each service’s `config/` directory (ignored by Git).

## Development Workflow
1. Create a branch: `feat/<scope>-short-desc` or `fix/<scope>-short-desc`.
2. Follow Conventional Commits in messages, e.g. `feat(compose): add suwayomi service`.
3. Keep PRs focused and small; update docs when user-facing behavior changes.

## Local Validation
- Expand and verify config:
```bash
docker compose config
```
- Start everything or a single service:
```bash
docker compose up -d
# or
docker compose -f <service>/compose.yaml up -d
```
- Inspect:
```bash
docker compose ps
docker compose logs -f <service>
```

## Adding or Updating a Service
1. Create `service-name/` (kebab-case) with:
   - `service-name/compose.yaml` (2-space indents, explicit `container_name`, `env_file: ../.env`, volumes, and network)
   - `service-name/example.env` (placeholders only; no secrets)
2. Reference the service in root `compose.yaml` under `include`.
3. Prefer external `homelab` network; only use `network_mode: "host"` when required.
4. Document ports/URLs and any manual steps in `README.md`.

## Review Checklist (before opening a PR)
- [ ] `docker compose config` passes without errors
- [ ] Service starts and logs show no failures
- [ ] Persistent volumes work across restarts
- [ ] No secrets committed; `.env` stays local; placeholders in `example.env`
- [ ] Root `compose.yaml` include list updated (if adding/removing)
- [ ] README updated for user-facing changes

## Pull Requests
- Use the PR template. Include: summary, rationale, affected services/ports, and exact validation steps.
- Link related issues (e.g., `Closes #123`). Add screenshots for UI changes.

## Security Notes
- Never expose unnecessary ports; scope to the proxy or LAN as appropriate.
- Prefer environment variables over hardcoding. Do not commit sensitive files.
