---
description: 'Docker Compose conventions for local development environments — file layout, volume taxonomy, image pinning, readiness, profiles and secrets.'
applyTo: '**/docker-compose*.yml,**/docker-compose*.yaml,**/compose*.yml,**/compose*.yaml'
---

# Docker Compose

Compose describes the **local development and demo environment**; it is never the deployment
target. Optimise it for "clone and run", not for production fidelity.

## File Layout

- One Compose file per repository, in the root. Use profiles instead of
  `docker-compose.override.yml` or per-environment files.
- Never include the obsolete top-level `version:` key.
- Open the file with a header comment listing what the default `docker compose up` starts, each
  profile with its command, and the published endpoints. Keep it accurate; it is the first thing a
  contributor reads.
- Delete commented-out services, volumes and settings; git keeps history.

## Volume Taxonomy

Getting mounts wrong silently pollutes the working tree with runtime state.

- **Tracked configuration** lives in a dedicated tracked directory, bind-mounted read-only:
  `./.docker/service.conf:/etc/service/service.conf:ro`.
- **Volatile or regenerable data** — databases, caches, emulator state, downloads — uses a named
  volume, never a bind mount: `database_data:/var/lib/database`.
- **Host fixtures** the application only reads come from a gitignored directory, mounted `:ro`.
- Every bind mount is `:ro`. A writable bind mount needs a comment beside it giving the reason.
- Scope variable defaults to a subdirectory; `${SOME_DIR:-.}` mounts the whole repository.
- Name volumes in `snake_case`, prefixed with the owning service; never a bare `data`.

The tracked configuration directory is allow-listed in `.gitignore` with the same deny-then-allow
form as `.dockerignore`:

```gitignore
.docker/*
!.docker/service.conf
```

- Add the `!` entry in the same change as the mount that consumes the file.
- Never widen the deny rule to hide files a service writes; move that path to a named volume.

## Images

- Pin every image exactly as `FROM` is pinned in `docker.instructions.md`. An untagged image means
  `latest` and is a defect.
- Where upstream publishes no versioned tag, pin by digest and say why in a comment. Where upstream
  documents only `latest`, pin the newest version-specific tag and record the upstream position.
- Before pinning, confirm the tag exists and publishes the platforms you need with
  `docker buildx imagetools inspect <image>:<tag>`; the newest tag in a registry listing can be a
  nightly or single-architecture build.
- Keep an image that also runs in the cluster on the same version in Compose and in the chart.

## Readiness and Restarts

- Give a service a `healthcheck` when another service depends on it, or when a developer would
  otherwise watch logs to see whether it is ready.
- Depend on state, not start order: `condition: service_healthy` for long-lived dependencies and
  `condition: service_completed_successfully` for one-shot initialisers. A bare `depends_on` list
  only orders container start.
- One-shot initialisers use `restart: "no"`; long-lived services use `restart: unless-stopped`.

## Profiles

- The default `docker compose up` starts infrastructure only; the application under development runs
  from the IDE against it.
- Anything that builds from source, needs a GPU, pulls a large model or exists only for a demo goes
  behind a profile named for what it delivers (`demo`, `harness`), documented in the header.

## Secrets

- Inline only well-known public development constants, such as an emulator's published key or a
  local database password.
- Real values come from a gitignored mount or `env_file` with a safe default so a fresh clone still
  starts: `${USER_SECRETS_DIR:-./.secrets}:/path/in/container:ro`.
- Never commit a `.env`; gitignore it alongside the secrets directory.

## Validation

- Validate every profile after an edit with `docker compose --profile '*' config --quiet`; without
  `--profile '*'` services behind a profile are never parsed.
- When a repository keeps a second Compose file for a variant topology, such as a replication
  cluster, fold it into the main file behind a profile, and update every script, solution file and
  README that referenced the old file in the same change.
