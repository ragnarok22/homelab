---
name: Bug report
about: Report a problem with the homelab Docker stack
title: "bug(<service>): short description"
labels: bug
assignees: ""
---

## Summary
Briefly describe the issue and its impact.

## Affected Service(s)
- Example: `jellyfin`, `pihole`, `nginx-manager`, ...

## Environment
- OS/Host: 
- Docker: `docker --version`
- Compose: `docker compose version`
- Network: using external `homelab`? host network?

## Steps to Reproduce
1. 
2. 
3. 

## Expected Behavior

## Actual Behavior

## Logs / Output
Attach relevant excerpts. Prefer:

```bash
docker compose logs -f <service>
```

## Compose / Env Context
Paste minimal relevant snippets (redact secrets):

```yaml
# <service>/compose.yaml
```

```env
# <service>/example.env (or placeholders)
```

## Validation Performed
- [ ] Ran `docker compose config` (no errors)
- [ ] Reproduced with `docker compose -f <service>/compose.yaml up -d`
- [ ] Confirmed volumes and ports are correctly mapped

## Additional Context
Anything else helpful for maintainers.

