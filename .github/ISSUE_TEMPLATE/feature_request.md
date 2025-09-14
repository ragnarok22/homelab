---
name: Feature request
about: Propose a new service or improvement
title: "feat(<scope|service>): short description"
labels: enhancement
assignees: ""
---

## Summary
What do you want to add or change?

## Use Case / Rationale
Why is this useful in the homelab context?

## Proposed Change
- New service or update existing?
- High-level approach (files to add/modify)

## Service Details (if adding)
- Image and tag:
- Ports to expose:
- Volumes (persistence):
- Env vars (placeholders only):
- Network: external `homelab` or host?

## Alternatives Considered

## Validation Plan
How will we verify it works locally?

```bash
# Example
docker network ls | grep homelab || docker network create homelab
docker compose -f <service>/compose.yaml up -d
docker compose logs -f <service>
```

## Checklist
- [ ] Added `<service>/compose.yaml`
- [ ] Added `<service>/example.env` (no secrets)
- [ ] Updated root `compose.yaml` `include` list
- [ ] Documented ports/URLs in README or service docs

## Additional Context
Links, screenshots, or notes for reviewers.

