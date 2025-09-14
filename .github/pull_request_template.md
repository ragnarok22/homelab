<!-- Use Conventional Commits in your PR title, e.g., feat(compose): add suwayomi service -->

## Summary
- What problem does this PR solve? Why now?

## Changes
- High-level list of changes (files, services, behavior)
- Note new env vars, volumes, or ports

## Related Issues
- Closes #<issue-id>

## Screenshots / UI
- If the change affects a web UI, add before/after screenshots.

## Validation Steps
Paste the exact steps/commands you used to validate locally.

```bash
# Ensure external network exists (first run only)
docker network ls | grep homelab || docker network create homelab

# Validate compose configuration
docker compose config

# Start all services (if applicable)
docker compose up -d && docker compose ps

# OR start a single service
docker compose -f <service>/compose.yaml up -d
docker compose logs -f <service>
```

Expected result:
- [ ] Services start without errors
- [ ] New/changed service is reachable at documented port/host
- [ ] Data persists across container restarts (if applicable)

## Breaking Changes
- Any backward-incompatible changes or migration steps?

## Checklist
- [ ] PR title follows Conventional Commits (e.g., feat(scope): ...)
- [ ] No secrets committed; `.env` kept local; `example.env` updated
- [ ] If adding a service: `service-name/compose.yaml` and `service-name/example.env` added
- [ ] Root `compose.yaml` `include` list updated (if adding/removing services)
- [ ] Documented affected ports and credentials (placeholders only)
- [ ] Tested locally using the commands above
- [ ] README or service docs updated if user-facing behavior changed

## Additional Notes
- Anything reviewers should pay special attention to (risk, rollout, follow-ups)

